#!/usr/bin/env julia
# Behavior test for the cglm Hub wrapper.
# cglm types (vec3/vec4/mat4) are float-array typedefs; the glmc_* call API
# takes them by pointer, so we pass plain Vector{Float32} buffers.

using Test

const PKG_DIR = @__DIR__
include(joinpath(PKG_DIR, "julia", "Cglm.jl"))
using .Cglm

const F = Float32
v3(x, y, z) = F[x, y, z]

@testset "cglm wrapper" begin

    @testset "vec3 arithmetic" begin
        a = v3(1, 2, 3)
        b = v3(4, 5, 6)
        dest = zeros(F, 3)

        Cglm.glmc_vec3_add(a, b, dest)
        @test dest == F[5, 7, 9]

        # dot product: 1*4 + 2*5 + 3*6 = 32
        @test Cglm.glmc_vec3_dot(a, b) ≈ 32.0f0

        # cross(x̂, ŷ) = ẑ
        x = v3(1, 0, 0); y = v3(0, 1, 0); c = zeros(F, 3)
        Cglm.glmc_vec3_cross(x, y, c)
        @test c ≈ F[0, 0, 1]

        # scale
        s = zeros(F, 3)
        Cglm.glmc_vec3_scale(a, 2.0, s)
        @test s == F[2, 4, 6]
    end

    @testset "vec3 norms & distance" begin
        # |(3,4,0)| = 5
        @test Cglm.glmc_vec3_norm(v3(3, 4, 0)) ≈ 5.0f0

        # normalize in place -> unit length
        u = v3(3, 4, 0)
        Cglm.glmc_vec3_normalize(u)
        @test Cglm.glmc_vec3_norm(u) ≈ 1.0f0
        @test u ≈ F[0.6, 0.8, 0.0]

        # distance between (0,0,0) and (3,4,0) = 5
        @test Cglm.glmc_vec3_distance(v3(0, 0, 0), v3(3, 4, 0)) ≈ 5.0f0
    end

    @testset "mat4 identity & multiply" begin
        # mat4 == float[4][4] == 16 contiguous floats (column-major in cglm)
        I = zeros(F, 16)
        Cglm.glmc_mat4_identity(I)
        @test I == F[1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]

        # I * I == I
        prod = zeros(F, 16)
        Cglm.glmc_mat4_mul(I, I, prod)
        @test prod == I

        # I * v == v  (vec4)
        v = F[2, 3, 4, 1]
        out = zeros(F, 4)
        Cglm.glmc_mat4_mulv(I, v, out)
        @test out == v
    end

    @testset "error path / degenerate input" begin
        # norm of zero vector is 0 (no crash, well-defined)
        @test Cglm.glmc_vec3_norm(v3(0, 0, 0)) == 0.0f0

        # dot of orthogonal vectors is 0
        @test Cglm.glmc_vec3_dot(v3(1, 0, 0), v3(0, 1, 0)) == 0.0f0
    end

end

println("\ncglm wrapper: all tests passed.")
