#!/usr/bin/env julia
# zstd Hub package — integration test
#
# Tests the full RepliBuild pipeline for zstd 1.5.7:
#   clean → build → load wrapper → identity + one round-trip
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/zstd/test.jl
#
# This REBUILDS from cold (deletes the git clone). For "does the wrapper
# work?" reach for test_deep.jl instead.

using Test
using RepliBuild

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")
const JULIA_DIR = joinpath(PKG_DIR, "julia")

@testset "zstd Hub Package" begin

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libzstd.so") || endswith(lib, "libzstd.dylib")
    @test filesize(lib) > 1_000_000

    @test isfile(joinpath(JULIA_DIR, "compilation_metadata.json"))

    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test isfile(joinpath(JULIA_DIR, "Zstd.jl"))
end

include(joinpath(JULIA_DIR, "Zstd.jl"))

@testset "Module structure" begin
    @test isdefined(Zstd, :ZSTD_compress)
    @test isdefined(Zstd, :ZSTD_decompress)
    @test isdefined(Zstd, :ZSTD_compressBound)
    @test isdefined(Zstd, :ZSTD_isError)
    @test isdefined(Zstd, :ZSTD_getErrorName)
    @test isdefined(Zstd, :ZSTD_versionNumber)
    @test isdefined(Zstd, :ZSTD_versionString)
    @test isdefined(Zstd, :ZSTD_createCCtx)
    @test isdefined(Zstd, :ZSTD_freeCCtx)
    @test isdefined(Zstd, :ZSTD_compressStream2)
    @test isdefined(Zstd, :ZSTD_inBuffer_s)
    @test isdefined(Zstd, :ZSTD_outBuffer_s)
    @test isdefined(Zstd, :ZSTD_COMPRESSBOUND)
    @test isdefined(Zstd, :ZSTD_VERSION_STRING)
end

@testset "Identity + one round-trip" begin
    @test Zstd.ZSTD_versionNumber() == 10507
    @test Zstd.ZSTD_versionString() == "1.5.7"
    src = collect(codeunits("hello zstd"))
    cap = Int(Zstd.ZSTD_compressBound(length(src)))
    dst = Vector{UInt8}(undef, cap)
    n = Zstd.ZSTD_compress(dst, cap, src, length(src), 1)
    @test Zstd.ZSTD_isError(n) == 0
    back = Vector{UInt8}(undef, length(src))
    m = Zstd.ZSTD_decompress(back, length(back), dst, n)
    @test m == length(src)
    @test back == src
end

end
