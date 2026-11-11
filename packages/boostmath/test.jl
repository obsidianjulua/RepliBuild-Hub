#!/usr/bin/env julia
# boostmath Hub package — cold rebuild
#
# DESTRUCTIVE: clean() wipes build/, julia/ and the cache, but deps=false keeps
# the boostorg/math clone (341 MB, ~5 min to fetch). Then build + wrap + a canary.
# Behavioral coverage lives in test_deep.jl — do not use this file to ask
# "does the wrapper work".
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/boostmath/test.jl

using Test
using RepliBuild

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")
const JULIA_DIR = joinpath(PKG_DIR, "julia")

@testset "boostmath Hub Package" begin

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH; deps=false)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libboostmath.so")
    @test filesize(lib) > 500_000
    @test isfile(joinpath(JULIA_DIR, "compilation_metadata.json"))
    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test isfile(joinpath(JULIA_DIR, "libboostmath_thunks.so"))
end

@testset "dynamic table is the shim" begin
    # visibility = "hidden" + RB_API: no Boost internal reaches .dynsym.
    lib = joinpath(JULIA_DIR, "libboostmath.so")
    dyn = filter(!isempty, split(read(`nm -DC --defined-only $lib`, String), '\n'))
    @test !any(l -> occursin("boost::math::detail::", l) &&
                    !occursin("bessel_traits", l), dyn)   # bessel_traits is a RETURN type spelling
    @test any(l -> occursin("boost::math::tgamma<double>(double)", l), dyn)
end

include(joinpath(JULIA_DIR, "Boostmath.jl"))

@testset "canary after rebuild" begin
    @test Boostmath.boost_math_tgamma_double(5.0) == 24.0
end

end
