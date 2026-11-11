#!/usr/bin/env julia
# stl Hub package — deep integration test
#
# Host-local wrap of this machine's libstdc++ / libc++. Not a universal
# product. Assumes the wrapper is already built (test.jl rebuilds).
#
# Exercises factories + STLWrappers:
#   - replibuild_stl_host / replibuild_stl_cxx canaries
#   - CppVector{Cint,Cdouble} push / index / length / empty!
#   - CppString default-ctor + String()
#   - CppMap / unordered_map insert / lookup / delete
#   - GC finalizer path (destructor thunks)
#
# Default ctors come from the generated force TU (`T c;` + `-fno-inline` on
# that TU). Allocator-taking overloads in the .so are not bound — the
# factory calls T() with no extra args.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/stl/test_deep.jl

using Test
using RepliBuild

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Stl.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)
using .Stl

@testset "stl host (local)" begin

@testset "canary" begin
    host = Stl.replibuild_stl_host()
    @test host in ("libstdc++", "libc++")
    @test Stl.replibuild_stl_cxx() == 201703  # -std=c++17
end

@testset "CppVector{Cint}" begin
    v = Stl.create_std_vector_int()
    @test v isa RepliBuild.STLWrappers.CppVector{Cint}
    @test length(v) == 0
    @test isempty(v)

    push!(v, Cint(10))
    push!(v, Cint(20))
    push!(v, Cint(30))
    @test length(v) == 3
    @test v[1] == 10
    @test v[2] == 20
    @test v[3] == 30

    v[2] = Cint(99)
    @test v[2] == 99

    empty!(v)
    @test length(v) == 0
end

@testset "CppVector{Cdouble}" begin
    v = Stl.create_std_vector_double()
    @test v isa RepliBuild.STLWrappers.CppVector{Cdouble}
    push!(v, 1.5)
    push!(v, 2.5)
    @test length(v) == 2
    @test v[1] == 1.5
    @test v[2] == 2.5
end

@testset "CppString" begin
    s = Stl.create_std_basic_string_char()
    @test s isa RepliBuild.STLWrappers.CppString
    @test length(s) == 0
    @test String(s) == ""
end

@testset "CppMap{Cint,Cint}" begin
    m = Stl.create_std_map_int_int()
    @test m isa RepliBuild.STLWrappers.CppMap{Cint,Cint}
    @test length(m) == 0
    @test isempty(m)

    m[Cint(1)] = Cint(42)
    @test length(m) == 1
    @test m[Cint(1)] == 42
    @test haskey(m, Cint(1))
    @test !haskey(m, Cint(99))

    m[Cint(2)] = Cint(100)
    m[Cint(3)] = Cint(200)
    @test length(m) == 3

    delete!(m, Cint(2))
    @test length(m) == 2
    @test !haskey(m, Cint(2))

    empty!(m)
    @test length(m) == 0
end

@testset "unordered_map{Cint,Cint}" begin
    m = Stl.create_std_unordered_map_int_int()
    @test m isa RepliBuild.STLWrappers.CppMap{Cint,Cint}
    @test length(m) == 0
    m[Cint(7)] = Cint(70)
    @test m[Cint(7)] == 70
    @test haskey(m, Cint(7))
    delete!(m, Cint(7))
    @test !haskey(m, Cint(7))
end

@testset "finalizers" begin
    v = Stl.create_std_vector_int()
    push!(v, Cint(1))
    s = Stl.create_std_basic_string_char()
    m = Stl.create_std_map_int_int()
    m[Cint(0)] = Cint(1)
    v = nothing
    s = nothing
    m = nothing
    GC.gc()
    @test true
end

end
