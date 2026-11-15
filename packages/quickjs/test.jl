#!/usr/bin/env julia
# quickjs Hub package — cold rebuild
#
# DESTRUCTIVE: clean() wipes build/, julia/ and the cache, but deps=false keeps
# the unpacked release tarball. Then build + wrap + gates, then the deep test
# against the fresh wrapper.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/quickjs/test.jl

using Test
using RepliBuild
using JSON

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")
const JULIA_DIR = joinpath(PKG_DIR, "julia")

@testset "quickjs Hub Package" begin

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH; deps=false)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libquickjs.so")
    @test filesize(lib) > 1_000_000
    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test endswith(wrapper, "Quickjs.jl")
end

@testset "what was compiled and wrapped" begin
    meta = JSON.parsefile(joinpath(JULIA_DIR, "compilation_metadata.json"))
    # The Makefile's QJS_LIB_OBJS, none of the programs with a main(), plus the
    # generated file holding the [wrap.macros] shims
    names = sort(basename.(meta["source_files"]))
    @test names == ["cutils.c", "dtoa.c", "libregexp.c", "libunicode.c", "quickjs-libc.c", "quickjs.c",
                    "replibuild_shims.c"]
    # The release's VERSION reached the library as a C string (CONFIG_VERSION)
    @test occursin("QuickJS memory usage -- 2026-06-04 version", read(joinpath(JULIA_DIR, "libquickjs.so"), String))
    @test meta["function_count"] > 250
end

end

# Behaviour: eval, errors, calls both ways, libc helpers, leak-free teardown.
include(joinpath(PKG_DIR, "test_deep.jl"))
