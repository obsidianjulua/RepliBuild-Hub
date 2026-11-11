#!/usr/bin/env julia
# stl Hub package — cold rebuild
#
# Host-local wrap. clean + build + wrap, then the canary. Behavioral
# coverage lives in test_deep.jl — do not use this file to ask "does
# the wrapper work".
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/stl/test.jl

using Test
using RepliBuild

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")
const JULIA_DIR = joinpath(PKG_DIR, "julia")

@testset "stl Hub Package" begin

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libstl.so") || endswith(lib, "libstl.dylib") || endswith(lib, "libstl.dll")
    @test filesize(lib) > 100_000
    @test isfile(joinpath(JULIA_DIR, "compilation_metadata.json"))
    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test isfile(joinpath(JULIA_DIR, "Stl.jl"))
end

include(joinpath(JULIA_DIR, "Stl.jl"))

@testset "canary after rebuild" begin
    @test isdefined(Stl, :replibuild_stl_host)
    @test Stl.replibuild_stl_host() in ("libstdc++", "libc++")
    @test isdefined(Stl, :create_std_vector_int)
    @test isdefined(Stl, :create_std_map_int_int)
end

end
