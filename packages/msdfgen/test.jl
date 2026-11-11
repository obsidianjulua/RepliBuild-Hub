#!/usr/bin/env julia
# msdfgen Hub package — cold rebuild, then the deep verifier.
#
# REBUILDS: RepliBuild.clean deletes build/, julia/ and .replibuild_cache/
# (including the vendored clone), then re-clones v1.13 and rebuilds the core
# library. Use test_deep.jl alone to check an existing wrapper.
#
#   julia --project=<RepliBuild.jl> packages/msdfgen/test.jl

using Test
using RepliBuild

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")

@testset "msdfgen Hub package" begin
    RepliBuild.clean(TOML_PATH)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib) && endswith(lib, "libmsdfgen.so")
    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)

    src = read(wrapper, String)
    # -fstandalone-debug: header-only value types must be real definitions, not
    # 0-byte forward stubs — generateSDF takes Range by value.
    @test occursin(r"struct Range\n    lower::Cdouble\n    upper::Cdouble", src)
    @test !occursin(r"^struct Range end"m, src)
    @test !occursin(r"^struct BitmapSection_float_1 end"m, src)
end

include(joinpath(PKG_DIR, "test_deep.jl"))
