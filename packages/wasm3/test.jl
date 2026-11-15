#!/usr/bin/env julia
# wasm3 Hub package — cold rebuild
#
# DESTRUCTIVE: clean() wipes build/, julia/ and the cache, but deps=false keeps
# the wasm3 clone. Then build + wrap + gates, then the deep test against the
# fresh wrapper.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/wasm3/test.jl

using Test
using RepliBuild
using JSON

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")
const JULIA_DIR = joinpath(PKG_DIR, "julia")

@testset "wasm3 Hub Package" begin

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH; deps=false)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libwasm3.so")
    @test filesize(lib) > 300_000
    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test endswith(wrapper, "Wasm3.jl")
end

@testset "what was compiled" begin
    meta = JSON.parsefile(joinpath(JULIA_DIR, "compilation_metadata.json"))
    names = sort(basename.(meta["source_files"]))
    # source/CMakeLists.txt's m3 target (16 files) + the [wrap.macros] shims;
    # nothing from platforms/ or source/extensions/
    @test length(names) == 17
    @test all(n -> startswith(n, "m3_") || n == "replibuild_shims.c", names)
    @test !any(s -> occursin("/platforms/", s) || occursin("/extensions/", s), meta["source_files"])
    # Simple WASI is in, uvwasi and meta-WASI compiled to nothing
    syms = read(`nm -D --defined-only $(joinpath(JULIA_DIR, "libwasm3.so"))`, String)
    @test occursin(" m3_LinkWASI\n", syms)
    @test occursin(" m3_LinkTracer\n", syms)          # -Dd_m3HasTracer, as upstream
    @test !occursin("uvwasi", syms)
end

@testset "LTO off: every call is a ccall" begin
    # [link] enable_lto = false, the Hub pin. (The truncated LTO declarations of
    # GENERATOR-lto-global-type-truncated.md were fixed in RepliBuild.jl#104;
    # with LTO off the module is not built at all.)
    w = read(joinpath(JULIA_DIR, "Wasm3.jl"), String)
    @test occursin("const LTO_IR = \"\"", w)
    @test !isfile(joinpath(JULIA_DIR, "wasm3_lto.bc"))
end

end

# Behaviour: every value type, traps, memory, host imports, WASI.
include(joinpath(PKG_DIR, "test_deep.jl"))
