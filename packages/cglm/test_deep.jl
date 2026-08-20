#!/usr/bin/env julia
# cglm Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
# cglm carries the Hub's heaviest Tier-1 load — every one of its ~742 wrapped
# functions is a sliced llvmcall — so this file is as much a stress test of the
# slicing machinery as it is of the maths:
#   - linear algebra checked against JULIA's own matrix/vector arithmetic,
#     which is a genuinely independent oracle
#   - identities that must hold exactly or near-exactly: A·A⁻¹ = I,
#     det(AB) = det(A)det(B), transpose involution, quaternion↔matrix
#     round-trips, rotation orthonormality
#   - in-place aliasing (dest === src) behaviour
#   - projection/view matrices probed by what they must do to known points
#   - Tier-1 liveness plus a high-volume churn loop over many distinct kernels
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/cglm/test_deep.jl

using Test
using LinearAlgebra
using InteractiveUtils: code_typed
using Random: Xoshiro

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Cglm.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const G = Cglm

# ── Marshalling ──────────────────────────────────────────────────────────────
# cglm's `mat4` is `vec4[4]`, i.e. four COLUMNS — so the wrapper types it as
# Ptr{NTuple{4,Cfloat}} and a Vector{NTuple{4,Float32}} of length 4 is the exact
# C layout. Reassembling those columns with hcat gives the same matrix Julia
# would write down, so `*` and `inv` become the oracle.

newmat() = Vector{NTuple{4,Float32}}(undef, 4)
newmat3() = Vector{NTuple{3,Float32}}(undef, 3)

function tomat(m::Vector{NTuple{4,Float32}})
    M = Matrix{Float32}(undef, 4, 4)
    for c in 1:4, r in 1:4
        M[r, c] = m[c][r]
    end
    return M
end

function frommat(M::AbstractMatrix)
    m = newmat()
    for c in 1:4
        m[c] = ntuple(r -> Float32(M[r, c]), 4)
    end
    return m
end

vec3(x, y, z) = Float32[x, y, z]
vec4(x, y, z, w) = Float32[x, y, z, w]

# cglm is single precision throughout; comparisons need float32-scale slack.
approx(a, b; atol = 1e-4) = isapprox(a, b; atol = atol)

const RNG = Xoshiro(0xC61A)
"A well-conditioned random matrix (identity plus a small perturbation)."
randmat() = frommat(Matrix{Float32}(I, 4, 4) .+ 0.3f0 .* randn(RNG, Float32, 4, 4))

@testset "cglm Deep Tests" begin

@testset "Tier-1 slicing is live at scale" begin
    @test !isempty(G.TIER1_FUNCTIONS)
    slices_dir = joinpath(PKG_DIR, "julia", "slices")
    @test isdir(slices_dir)
    lls = filter(f -> endswith(f, ".ll"), readdir(slices_dir))
    # cglm is the Hub's largest Tier-1 surface; every wrapped function slices.
    @test length(lls) == length(G.TIER1_FUNCTIONS)
    @test length(lls) > 700

    @test G.dispatch_tier(:glmc_mat4_mul) === :tier1
    @test G.dispatch_tier(:glmc_vec3_dot) === :tier1
    @test G.dispatch_tier(:glmc_mat4_inv) === :tier1
    @test G.dispatch_tier(:glmc_quat_mul) === :tier1

    # Slices must be real IR naming their own entry point.
    for f in first(sort(lls), 25)
        ir = read(joinpath(slices_dir, f), String)
        @test occursin("define", ir)
        @test occursin(splitext(f)[1], ir)
    end
end

@testset "mat4 basics against Julia's arithmetic" begin
    m = newmat()
    G.glmc_mat4_identity(m)
    @test tomat(m) == Matrix{Float32}(I, 4, 4)

    A = randmat(); B = randmat()
    JA, JB = tomat(A), tomat(B)

    C = newmat()
    G.glmc_mat4_mul(A, B, C)
    @test approx(tomat(C), JA * JB)

    # Multiplication is not commutative — a wrapper that swapped the operands
    # would still pass an A·I test, so check the asymmetry explicitly.
    D = newmat()
    G.glmc_mat4_mul(B, A, D)
    @test !approx(tomat(D), JA * JB; atol = 1e-3) || approx(JA * JB, JB * JA)

    # Determinant and trace.
    @test approx(G.glmc_mat4_det(A), det(JA); atol = 1e-3)
    @test approx(G.glmc_mat4_trace(A), tr(JA))
    @test approx(G.glmc_mat4_trace3(A), tr(JA[1:3, 1:3]))

    # det(AB) = det(A)det(B)
    @test approx(G.glmc_mat4_det(C), G.glmc_mat4_det(A) * G.glmc_mat4_det(B); atol = 1e-3)

    # Transpose is an involution and matches Julia's.
    T = newmat(); T2 = newmat()
    G.glmc_mat4_transpose_to(A, T)
    @test approx(tomat(T), transpose(JA))
    G.glmc_mat4_transpose_to(T, T2)
    @test approx(tomat(T2), JA)

    # Copy really copies.
    K = newmat()
    G.glmc_mat4_copy(A, K)
    @test tomat(K) == tomat(A)
    G.glmc_mat4_identity(K)
    @test tomat(A) != tomat(K)          # mutating the copy left A alone
end

@testset "mat4 inverse identities" begin
    for _ in 1:50
        A = randmat()
        JA = tomat(A)
        abs(det(JA)) < 1e-3 && continue

        Inv = newmat()
        G.glmc_mat4_inv(A, Inv)
        @test approx(tomat(Inv), inv(JA); atol = 1e-2)

        # A · A⁻¹ = I is the identity that actually matters.
        P = newmat()
        G.glmc_mat4_mul(A, Inv, P)
        @test approx(tomat(P), Matrix{Float32}(I, 4, 4); atol = 1e-3)

        # The precise variant must be at least as good as the fast one.
        Ip = newmat(); If = newmat()
        G.glmc_mat4_inv_precise(A, Ip)
        G.glmc_mat4_inv_fast(A, If)
        Pp = newmat(); G.glmc_mat4_mul(A, Ip, Pp)
        @test approx(tomat(Pp), Matrix{Float32}(I, 4, 4); atol = 1e-3)
        err_p = maximum(abs.(tomat(Pp) .- Matrix{Float32}(I, 4, 4)))
        Pf = newmat(); G.glmc_mat4_mul(A, If, Pf)
        err_f = maximum(abs.(tomat(Pf) .- Matrix{Float32}(I, 4, 4)))
        @test err_p <= err_f + 1e-3
    end
end

@testset "mat4-vector products" begin
    A = randmat()
    JA = tomat(A)
    for _ in 1:20
        v = Float32[randn(RNG, Float32) for _ in 1:4]
        out = Vector{Float32}(undef, 4)
        G.glmc_mat4_mulv(A, v, out)
        @test approx(out, JA * v; atol = 1e-3)

        # mulv3 promotes a vec3 with an explicit w and drops it again.
        v3 = v[1:3]
        out3 = Vector{Float32}(undef, 3)
        G.glmc_mat4_mulv3(A, v3, 1.0f0, out3)
        @test approx(out3, (JA * Float32[v3[1], v3[2], v3[3], 1])[1:3]; atol = 1e-3)
    end

    # mulN chains a list of matrices — equals the left-to-right product.
    B = randmat(); C = randmat()
    # The C API takes an array of mat4* pointers.
    GC.@preserve A B C begin
        ptrs = Ptr{NTuple{4,Cfloat}}[Base.unsafe_convert(Ptr{NTuple{4,Cfloat}}, A),
                                     Base.unsafe_convert(Ptr{NTuple{4,Cfloat}}, B),
                                     Base.unsafe_convert(Ptr{NTuple{4,Cfloat}}, C)]
        dest = newmat()
        G.glmc_mat4_mulN(ptrs, UInt32(3), dest)
        @test approx(tomat(dest), tomat(A) * tomat(B) * tomat(C); atol = 1e-2)
    end
end

@testset "vec3 / vec4 operations" begin
    for _ in 1:50
        a = vec3(randn(RNG, Float32), randn(RNG, Float32), randn(RNG, Float32))
        b = vec3(randn(RNG, Float32), randn(RNG, Float32), randn(RNG, Float32))

        @test approx(G.glmc_vec3_dot(a, b), dot(a, b))
        @test approx(G.glmc_vec3_norm(a), norm(a))

        c = Vector{Float32}(undef, 3)
        G.glmc_vec3_cross(a, b, c)
        @test approx(c, cross(a, b); atol = 1e-4)

        # Cross product is orthogonal to both inputs and anticommutative.
        @test approx(dot(c, a), 0.0f0; atol = 1e-3)
        @test approx(dot(c, b), 0.0f0; atol = 1e-3)
        d = Vector{Float32}(undef, 3)
        G.glmc_vec3_cross(b, a, d)
        @test approx(d, -c; atol = 1e-4)

        # Normalisation produces a unit vector in the same direction.
        n = Vector{Float32}(undef, 3)
        G.glmc_vec3_normalize_to(a, n)
        @test approx(norm(n), 1.0f0)
        @test approx(dot(n, a), norm(a); atol = 1e-3)
    end

    # Known exact values leave no room for a coincidence.
    x = vec3(1, 0, 0); y = vec3(0, 1, 0)
    z = Vector{Float32}(undef, 3)
    G.glmc_vec3_cross(x, y, z)
    @test z == Float32[0, 0, 1]
    @test G.glmc_vec3_dot(x, y) == 0.0f0
    @test G.glmc_vec3_norm(vec3(3, 4, 0)) == 5.0f0
end

@testset "Quaternions" begin
    q = Vector{Float32}(undef, 4)
    G.glmc_quat_identity(q)
    @test approx(q[4], 1.0f0)                       # w = 1
    @test approx(q[1:3], Float32[0, 0, 0])

    # A quaternion built from an axis/angle must rotate as advertised.
    for (axis, angle) in [(vec3(0, 0, 1), Float32(π / 2)),
                          (vec3(0, 1, 0), Float32(π)),
                          (vec3(1, 0, 0), Float32(π / 3))]
        qq = Vector{Float32}(undef, 4)
        G.glmc_quat(qq, angle, axis[1], axis[2], axis[3])
        @test approx(G.glmc_quat_angle(qq), angle; atol = 1e-3)

        ax = Vector{Float32}(undef, 3)
        G.glmc_quat_axis(qq, ax)
        G.glmc_vec3_normalize_to(copy(ax), ax)
        @test approx(abs(dot(ax, axis)), 1.0f0; atol = 1e-3)

        # quat → mat4 → quat must round-trip (up to sign, which is inherent).
        m = newmat()
        G.glmc_quat_mat4(qq, m)
        back = Vector{Float32}(undef, 4)
        G.glmc_mat4_quat(m, back)
        @test approx(abs(dot(back, qq)), 1.0f0; atol = 1e-3)

        # The rotation matrix is orthonormal with determinant +1.
        R = tomat(m)[1:3, 1:3]
        @test approx(R * transpose(R), Matrix{Float32}(I, 3, 3); atol = 1e-3)
        @test approx(det(R), 1.0f0; atol = 1e-3)
    end

    # A 90° rotation about +Z sends +X to +Y.
    qz = Vector{Float32}(undef, 4)
    G.glmc_quat(qz, Float32(π / 2), 0f0, 0f0, 1f0)
    mz = newmat(); G.glmc_quat_mat4(qz, mz)
    out = Vector{Float32}(undef, 4)
    G.glmc_mat4_mulv(mz, vec4(1, 0, 0, 1), out)
    @test approx(out[1:3], Float32[0, 1, 0]; atol = 1e-4)

    # Composition: q·q⁻¹ = identity, and conjugate == inverse for unit quats.
    inv_q = Vector{Float32}(undef, 4)
    G.glmc_quat_inv(qz, inv_q)
    prod = Vector{Float32}(undef, 4)
    G.glmc_quat_mul(qz, inv_q, prod)
    @test approx(prod[4], 1.0f0; atol = 1e-3)
    @test approx(prod[1:3], Float32[0, 0, 0]; atol = 1e-3)

    conj_q = Vector{Float32}(undef, 4)
    G.glmc_quat_conjugate(qz, conj_q)
    @test approx(conj_q, inv_q; atol = 1e-4)

    # Two 90° Z rotations compose into a 180° one.
    twice = Vector{Float32}(undef, 4)
    G.glmc_quat_mul(qz, qz, twice)
    m2 = newmat(); G.glmc_quat_mat4(twice, m2)
    o2 = Vector{Float32}(undef, 4)
    G.glmc_mat4_mulv(m2, vec4(1, 0, 0, 1), o2)
    @test approx(o2[1:3], Float32[-1, 0, 0]; atol = 1e-4)

    # lerp endpoints.
    a = Vector{Float32}(undef, 4); b = Vector{Float32}(undef, 4)
    G.glmc_quat_identity(a)
    G.glmc_quat(b, Float32(π / 2), 0f0, 0f0, 1f0)
    l = Vector{Float32}(undef, 4)
    G.glmc_quat_lerp(a, b, 0.0f0, l)
    @test approx(l, a; atol = 1e-5)
    G.glmc_quat_lerp(a, b, 1.0f0, l)
    @test approx(l, b; atol = 1e-5)
end

@testset "Camera and projection matrices" begin
    # lookat: the eye maps to the origin in view space.
    view = newmat()
    eye = vec3(0, 0, 5); center = vec3(0, 0, 0); up = vec3(0, 1, 0)
    G.glmc_lookat(eye, center, up, view)
    out = Vector{Float32}(undef, 4)
    G.glmc_mat4_mulv(view, vec4(0, 0, 5, 1), out)
    @test approx(out[1:3], Float32[0, 0, 0]; atol = 1e-4)
    # ...and the target sits straight down the -Z axis at distance 5.
    G.glmc_mat4_mulv(view, vec4(0, 0, 0, 1), out)
    @test approx(out[1], 0.0f0; atol = 1e-4)
    @test approx(out[2], 0.0f0; atol = 1e-4)
    @test approx(out[3], -5.0f0; atol = 1e-4)

    # A view matrix is a rigid transform: its rotation block is orthonormal.
    R = tomat(view)[1:3, 1:3]
    @test approx(R * transpose(R), Matrix{Float32}(I, 3, 3); atol = 1e-4)

    # perspective: the near and far planes map to the clip-space extremes.
    proj = newmat()
    nearz, farz = 0.1f0, 100.0f0
    G.glmc_perspective(Float32(π / 4), 16f0 / 9f0, nearz, farz, proj)
    P = tomat(proj)
    for (z, want) in [(-nearz, -1.0f0), (-farz, 1.0f0)]
        clip = P * Float32[0, 0, z, 1]
        @test approx(clip[3] / clip[4], want; atol = 1e-3)
    end
    # Perspective divide shrinks with distance.
    c1 = P * Float32[1, 0, -1, 1]
    c2 = P * Float32[1, 0, -10, 1]
    @test abs(c1[1] / c1[4]) > abs(c2[1] / c2[4])

    # ortho preserves parallel lines: x/w is linear in x.
    o = newmat()
    G.glmc_ortho(-1f0, 1f0, -1f0, 1f0, 0.1f0, 10f0, o)
    O = tomat(o)
    p1 = O * Float32[-1, 0, -1, 1]
    p2 = O * Float32[1, 0, -1, 1]
    @test approx(p1[1] / p1[4], -1.0f0; atol = 1e-4)
    @test approx(p2[1] / p2[4], 1.0f0; atol = 1e-4)
end

@testset "In-place aliasing (dest === src)" begin
    # cglm documents that most functions tolerate dest aliasing src. If the
    # wrapper's GC.@preserve or pointer conversion were wrong, aliasing is
    # where the corruption would surface first.
    A = randmat()
    JA = tomat(A)

    T = newmat(); G.glmc_mat4_copy(A, T)
    G.glmc_mat4_transpose(T)
    @test approx(tomat(T), transpose(JA))

    v = vec3(3, 4, 0)
    G.glmc_vec3_normalize(v)
    @test approx(norm(v), 1.0f0)
    @test approx(v, Float32[0.6, 0.8, 0]; atol = 1e-5)

    q = Vector{Float32}(undef, 4)
    G.glmc_quat(q, Float32(π / 2), 0f0, 0f0, 1f0)
    before = copy(q)
    G.glmc_quat_normalize(q)
    @test approx(q, before; atol = 1e-5)     # already unit length
end

@testset "Churn and GC stress across many kernels" begin
    # Hammer a wide spread of DISTINCT Tier-1 kernels: each one JIT-compiles its
    # own slice on first call, so this is the real scale test for the slicing
    # machinery (a bad slice tends to surface as a wrong value, not a crash).
    A = randmat(); B = randmat()
    C = newmat(); D = newmat()
    JA, JB = tomat(A), tomat(B)
    want = JA * JB

    for i in 1:5000
        G.glmc_mat4_mul(A, B, C)
        @assert approx(tomat(C), want; atol = 1e-3)
        G.glmc_mat4_transpose_to(C, D)
        a = vec3(Float32(i), 1f0, 2f0)
        b = vec3(2f0, Float32(i), 3f0)
        x = Vector{Float32}(undef, 3)
        G.glmc_vec3_cross(a, b, x)
        @assert approx(x, cross(a, b); atol = 1e-2 * max(1f0, Float32(i)))
        @assert approx(G.glmc_vec3_dot(a, b), dot(a, b); atol = 1e-2 * max(1f0, Float32(i)))
        iszero(i % 1000) && GC.gc()
    end
    @test true

    # Inverses under GC pressure, with freshly allocated matrices each round.
    for i in 1:1000
        M = randmat()
        JM = tomat(M)
        abs(det(JM)) < 1e-3 && continue
        Inv = newmat(); G.glmc_mat4_inv(M, Inv)
        P = newmat(); G.glmc_mat4_mul(M, Inv, P)
        @assert approx(tomat(P), Matrix{Float32}(I, 4, 4); atol = 1e-2)
        iszero(i % 200) && GC.gc()
    end
    @test true
end

end  # top-level testset
