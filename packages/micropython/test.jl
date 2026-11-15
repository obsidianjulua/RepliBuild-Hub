#!/usr/bin/env julia
# micropython Hub package — cold rebuild
#
# DESTRUCTIVE: clean() wipes build/, julia/ and the cache. embed/ (the harvested
# source tree, see harvest_embed.sh) lives in the package directory and is
# kept. Then build + wrap + gates, then the deep test against the fresh wrapper.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/micropython/test.jl

using Test
using RepliBuild
using JSON
using SHA

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")
const JULIA_DIR = joinpath(PKG_DIR, "julia")
const EMBED     = joinpath(PKG_DIR, "embed")

@testset "micropython Hub Package" begin

@testset "harvested tree matches the committed config" begin
    @test isdir(EMBED)       # absent → run harvest_embed.sh first
    record = read(joinpath(EMBED, "HARVEST.md"), String)
    config_sha = bytes2hex(open(sha256, joinpath(PKG_DIR, "mpconfigport.h")))
    # genhdr is generated under one config; compiling it under another gives a
    # qstr table that does not match the code. Re-harvest after any edit.
    @test occursin("config_sha256: $config_sha", record)
    @test occursin("tag: v1.29.0", record)
    @test occursin("commit: 0fd6c573ea815774668bbb16b8e197c8822368b2", record)
end

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH; deps=false)
    @test isdir(EMBED)       # clean did not touch the harvested tree
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libmicropython.so")
    @test filesize(lib) > 500_000
    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test endswith(wrapper, "Micropython.jl")
end

@testset "what was compiled" begin
    meta = JSON.parsefile(joinpath(JULIA_DIR, "compilation_metadata.json"))
    srcs = meta["source_files"]
    # Every .c in the harvested tree, plus the [wrap.macros] shims file
    harvested = [f for (d, _, fs) in walkdir(EMBED) for f in fs if endswith(f, ".c")]
    @test length(srcs) == length(harvested) + 1
    @test any(s -> endswith(s, "py/vm.c"), srcs)
    @test any(s -> endswith(s, "port/embed_util.c"), srcs)
    @test any(s -> endswith(s, "replibuild_shims.c"), srcs)
    # The embed API made it into the dynamic symbol table
    syms = read(`nm -D --defined-only $(joinpath(JULIA_DIR, "libmicropython.so"))`, String)
    for s in ("mp_embed_init", "mp_embed_exec_str", "mp_embed_exec_mpy", "mp_embed_deinit",
              "mp_stack_set_limit", "mp_map_lookup")
        @test occursin(" $s\n", syms)
    end
end

end

# Behaviour: run Python, read results, errors, recursion, GC, callbacks.
include(joinpath(PKG_DIR, "test_deep.jl"))
