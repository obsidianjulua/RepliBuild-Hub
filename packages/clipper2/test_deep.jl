#!/usr/bin/env julia
# clipper2 Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
# Exercises the official C ABI compiled in via src/export_tu.cpp:
#   - Version() == "2.0.1"
#   - BooleanOp64 intersection / union / difference of two squares
#   - InflatePaths64 grows a square
#   - DisposeArray64 frees the returned buffers
#   - Point_long layout (the header-only aggregate -fstandalone-debug canary)
#   - ClipType / FillRule enumerants
#
# The C++ class API (Clipper64::AddSubject, implicit ctor) is NOT asserted
# here — those symbols are header-inline and never emitted into the .so.
# See GENERATOR-header-inline-api.md. Seven AOT thunks are missing from
# libclipper2_thunks.so (GENERATOR-aot-thunk-gap.md); this file does not
# call them.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/clipper2/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Clipper2.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const C = Clipper2

# CPaths64 packing (clipper.export.h): [A, C, (N, 0, x1,y1, …)*C]
# A = total Int64 count, C = path count, N = vertex count of that path.
function cpaths64(paths::Vector{Vector{NTuple{2,Int64}}})
    blocks = Int64[]
    for p in paths
        push!(blocks, Int64(length(p)), Int64(0))
        for (x, y) in p
            push!(blocks, x, y)
        end
    end
    return vcat(Int64[2 + length(blocks), length(paths)], blocks)
end

function parse_cpaths64(p::Ptr{Int64})
    p == C_NULL && return Vector{Vector{NTuple{2,Int64}}}()
    Cnt = Int(unsafe_load(p, 2))
    i = 3
    out = Vector{Vector{NTuple{2,Int64}}}()
    for _ in 1:Cnt
        N = Int(unsafe_load(p, i)); i += 2
        path = NTuple{2,Int64}[]
        for _ in 1:N
            x = unsafe_load(p, i); y = unsafe_load(p, i + 1); i += 2
            push!(path, (x, y))
        end
        push!(out, path)
    end
    return out
end

function with_boolean(cliptype::UInt8, fillrule::UInt8, subj, clip)
    sol = Ref{Ptr{Int64}}(C_NULL)
    open = Ref{Ptr{Int64}}(C_NULL)
    rc = Cint(-99)
    GC.@preserve subj clip begin
        rc = C.BooleanOp64(cliptype, fillrule, subj, C_NULL, clip, sol, open, true, false)
    end
    paths = parse_cpaths64(sol[])
    sol[] != C_NULL && C.DisposeArray64(sol)
    open[] != C_NULL && C.DisposeArray64(open)
    return rc, paths
end

const SQUARE_A = cpaths64([[(Int64(0), Int64(0)), (Int64(10), Int64(0)),
                            (Int64(10), Int64(10)), (Int64(0), Int64(10))]])
const SQUARE_B = cpaths64([[(Int64(5), Int64(5)), (Int64(15), Int64(5)),
                            (Int64(15), Int64(15)), (Int64(5), Int64(15))]])

@testset "Clipper2 Deep Tests" begin

@testset "Library identity" begin
    @test C.Version() == "2.0.1"
    @test C.ClipType(1) == C.Intersection
    @test Int(C.c_Union) == 2
    @test C.FillRule(0) == C.EvenOdd
    @test C.FillRule(1) == C.NonZero
end

@testset "Point_long layout" begin
    @test sizeof(C.Point_long) == 16
    @test fieldnames(C.Point_long) === (:x, :y)
    p = C.Point_long(3, 4)
    @test p.x == 3
    @test p.y == 4
    @test C.struct_size(:Point_long) == 16
    @test C.member_offset(:Point_long, :x) == 0
    @test C.member_offset(:Point_long, :y) == 8
end

@testset "BooleanOp64 intersection" begin
    rc, paths = with_boolean(UInt8(1), UInt8(0), SQUARE_A, SQUARE_B)
    @test rc == 0
    @test length(paths) == 1
    verts = Set(paths[1])
    @test verts == Set([(Int64(5), Int64(5)), (Int64(10), Int64(5)),
                        (Int64(10), Int64(10)), (Int64(5), Int64(10))])
end

@testset "BooleanOp64 union" begin
    rc, paths = with_boolean(UInt8(2), UInt8(0), SQUARE_A, SQUARE_B)
    @test rc == 0
    @test length(paths) == 1
    @test length(paths[1]) >= 6          # L-octagon of two overlapping squares
end

@testset "BooleanOp64 difference" begin
    rc, paths = with_boolean(UInt8(3), UInt8(0), SQUARE_A, SQUARE_B)
    @test rc == 0
    @test !isempty(paths)
    # The (10,10) corner of A is inside B, so it must not survive as a vertex
    # of a positive-area remainder. At least one vertex of A outside B remains.
    allv = reduce(vcat, paths; init=NTuple{2,Int64}[])
    @test (Int64(0), Int64(0)) in allv
end

@testset "BooleanOp64 xor is symmetric" begin
    rc1, p1 = with_boolean(UInt8(4), UInt8(0), SQUARE_A, SQUARE_B)
    rc2, p2 = with_boolean(UInt8(4), UInt8(0), SQUARE_B, SQUARE_A)
    @test rc1 == 0 && rc2 == 0
    @test length(p1) == length(p2)
end

@testset "InflatePaths64" begin
    # JoinType Square=0, EndType Polygon=0. Positive delta grows the square.
    src = SQUARE_A
    p = Ptr{Int64}(C_NULL)
    GC.@preserve src begin
        p = C.InflatePaths64(src, 2.0, UInt8(0), UInt8(0), 2.0, 0.0, false)
    end
    @test p != C_NULL
    grown = parse_cpaths64(p)
    pref = Ref(p)
    C.DisposeArray64(pref)
    @test length(grown) == 1
    xs = [v[1] for v in grown[1]]
    ys = [v[2] for v in grown[1]]
    @test minimum(xs) <= 0
    @test maximum(xs) >= 10
    @test minimum(ys) <= 0
    @test maximum(ys) >= 10
    # Grown area must exceed the original 10×10.
    @test (maximum(xs) - minimum(xs)) * (maximum(ys) - minimum(ys)) > 100
end

@testset "Error: bad cliptype" begin
    rc, paths = with_boolean(UInt8(9), UInt8(0), SQUARE_A, SQUARE_B)
    @test rc == -4
    @test isempty(paths)
end

@testset "GC churn" begin
    for _ in 1:100
        rc, paths = with_boolean(UInt8(1), UInt8(0), SQUARE_A, SQUARE_B)
        @test rc == 0
        @test length(paths) == 1
        GC.safepoint()
    end
    GC.gc()
    rc, paths = with_boolean(UInt8(1), UInt8(0), SQUARE_A, SQUARE_B)
    @test rc == 0
end

end
