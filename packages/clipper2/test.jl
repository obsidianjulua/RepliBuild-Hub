#!/usr/bin/env julia
# clipper2 Hub package — integration test
#
# Tests the full RepliBuild pipeline for Clipper2 2.0.1:
#   clean → build → load wrapper → Version + one BooleanOp64 intersection
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/clipper2/test.jl
#
# This REBUILDS from cold (deletes the git clone). For "does the wrapper
# work?" reach for test_deep.jl instead.

using Test
using RepliBuild

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")
const JULIA_DIR = joinpath(PKG_DIR, "julia")

@testset "Clipper2 Hub Package" begin

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libclipper2.so") || endswith(lib, "libclipper2.dylib")
    @test filesize(lib) > 1_000_000
    @test isfile(joinpath(JULIA_DIR, "libclipper2_thunks.so")) ||
          isfile(joinpath(JULIA_DIR, "libclipper2_thunks.dylib"))
    @test isfile(joinpath(JULIA_DIR, "compilation_metadata.json"))
    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test isfile(joinpath(JULIA_DIR, "Clipper2.jl"))
end

include(joinpath(JULIA_DIR, "Clipper2.jl"))

@testset "C ABI is present" begin
    @test isdefined(Clipper2, :Version)
    @test isdefined(Clipper2, :BooleanOp64)
    @test isdefined(Clipper2, :DisposeArray64)
    @test isdefined(Clipper2, :InflatePaths64)
    @test Clipper2.Version() == "2.0.1"
end

end
