#!/usr/bin/env julia
# expat Hub package — cold rebuild, then the deep verifier.
#
# REBUILDS: RepliBuild.clean deletes build/, julia/ and .replibuild_cache/
# (including the vendored clone), then re-clones R_2_7_5 and rebuilds. Use
# test_deep.jl alone to check an existing wrapper.
#
# expat cannot be compiled from a bare checkout: every TU includes the cmake-
# generated expat_config.h, which is harvested into config/ by harvest.jl.
#
#   julia --project=<RepliBuild.jl> packages/expat/test.jl

using Test
using RepliBuild

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")

@testset "expat Hub package" begin
    @testset "harvested configure output" begin
        cfg = joinpath(PKG_DIR, "config")
        @test isfile(joinpath(cfg, "expat_config.h"))
        conf = read(joinpath(cfg, "expat_config.h"), String)
        @test occursin(r"#define XML_DTD\b", conf)
        @test occursin(r"#define XML_NS\b", conf)
        @test occursin(r"#\s*define XML_CONTEXT_BYTES 1024", conf)
    end

    @testset "build pipeline" begin
        RepliBuild.clean(TOML_PATH)
        lib = RepliBuild.build(TOML_PATH)
        @test isfile(lib) && endswith(lib, "libexpat.so")
        @test filesize(lib) > 200_000
        wrapper = RepliBuild.wrap(TOML_PATH)
        @test isfile(wrapper)

        # visibility = "hidden" keeps the surface to upstream's XMLIMPORT set: the
        # 19 internals (Xml*Encoding*, XmlProlog*, testing*) must not be wrapped.
        src = read(wrapper, String)
        @test occursin("function XML_ParserCreate(", src)
        @test !occursin("function XmlInitEncoding(", src)
        @test !occursin("function testingAccountingGetCountBytesDirect(", src)
    end
end

include(joinpath(PKG_DIR, "test_deep.jl"))
