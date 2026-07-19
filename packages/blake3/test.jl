#!/usr/bin/env julia
# BLAKE3 Hub package — integration test
#
# Tests the full RepliBuild pipeline for BLAKE3 1.8.5 (portable-C build):
#   clean → build → load wrapper → exercise API against the OFFICIAL test vectors
#
# The known-answer values below are lifted verbatim from the upstream
# test_vectors/test_vectors.json at tag 1.8.5 (first 32 output bytes):
#   - key     = "whats the Elvish word for friend"        (BLAKE3_KEY_LEN bytes)
#   - context = "BLAKE3 2019-12-27 16:29:52 test vectors context"
#   - input[i]= i % 251
# They are an INDEPENDENT oracle — matching them proves the wrapped .so hashes
# correctly, not merely that the symbols load.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/blake3/test.jl

using Test
using RepliBuild

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")
const JULIA_DIR = joinpath(PKG_DIR, "julia")

# ── Driver (defined at top level; `Blake3` is resolved lazily at call time,
#    i.e. after the build testset has run and Blake3.jl has been included) ──────

const KEY_STR = "whats the Elvish word for friend"
const CTX_STR = "BLAKE3 2019-12-27 16:29:52 test vectors context"
const KEY     = collect(codeunits(KEY_STR))                 # 32 bytes
const CTX     = collect(codeunits(CTX_STR))

testinput(n) = UInt8[UInt8(i % 251) for i in 0:(n-1)]

"Hash `input` in the requested mode and return the lowercase hex digest."
function b3hex(input::Vector{UInt8}; mode::Symbol=:hash,
               outlen::Integer=32, seek::Integer=0)
    href = Ref{Blake3.blake3_hasher}()
    if mode === :hash
        Blake3.blake3_hasher_init(href)
    elseif mode === :keyed
        Blake3.blake3_hasher_init_keyed(href, KEY)
    elseif mode === :derive
        Blake3.blake3_hasher_init_derive_key(href, CTX_STR)          # strlen path
    elseif mode === :derive_raw
        Blake3.blake3_hasher_init_derive_key_raw(href, CTX, length(CTX))
    else
        error("bad mode $mode")
    end
    isempty(input) || Blake3.blake3_hasher_update(href, input, length(input))
    out = Vector{UInt8}(undef, Int(outlen))
    if seek == 0
        Blake3.blake3_hasher_finalize(href, out, outlen)
    else
        Blake3.blake3_hasher_finalize_seek(href, UInt64(seek), out, outlen)
    end
    return bytes2hex(out)
end

# Official upstream vectors (tag 1.8.5), first 32 output bytes.
const VEC = Dict(
    0 => (hash   = "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262",
          keyed  = "92b2b75604ed3c761f9d6f62392c8a9227ad0ea3f09573e783f1498a4ed60d26",
          derive = "2cc39783c223154fea8dfb7c1b1660f2ac2dcbd1c1de8277b0b0dd39b7e50d7d"),
    3 => (hash   = "e1be4d7a8ab5560aa4199eea339849ba8e293d55ca0a81006726d184519e647f",
          keyed  = "39e67b76b5a007d4921969779fe666da67b5213b096084ab674742f0d5ec62b9",
          derive = "440aba35cb006b61fc17c0529255de438efc06a8c9ebf3f2ddac3b5a86705797"),
    1024 => (hash   = "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7",
             keyed  = "75c46f6f3d9eb4f55ecaaee480db732e6c2105546f1e675003687c31719c7ba4",
             derive = "7356cd7720d5b66b6d0697eb3177d9f8d73a4a5c5e968896eb6a689684302706"),
)

@testset "BLAKE3 Hub Package" begin

# ── Build ─────────────────────────────────────────────────────────────────────

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libblake3.so") || endswith(lib, "libblake3.dylib")
    @test filesize(lib) > 50_000                     # ~0.25 MB, not a stub

    @test isfile(joinpath(JULIA_DIR, "compilation_metadata.json"))

    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test isfile(joinpath(JULIA_DIR, "Blake3.jl"))
end

include(joinpath(JULIA_DIR, "Blake3.jl"))

# ── Structure ─────────────────────────────────────────────────────────────────

@testset "Module structure" begin
    for f in (:blake3_hasher_init, :blake3_hasher_init_keyed,
              :blake3_hasher_init_derive_key, :blake3_hasher_init_derive_key_raw,
              :blake3_hasher_update, :blake3_hasher_finalize,
              :blake3_hasher_finalize_seek, :blake3_hasher_reset,
              :blake3_version, :blake3_simd_degree)
        @test isdefined(Blake3, f)
    end
    for m in (:BLAKE3_KEY_LEN, :BLAKE3_OUT_LEN, :BLAKE3_BLOCK_LEN,
              :BLAKE3_CHUNK_LEN, :BLAKE3_MAX_DEPTH, :BLAKE3_VERSION_STRING)
        @test isdefined(Blake3, m)
    end
    @test isdefined(Blake3, :blake3_hasher)
    @test sizeof(Blake3.blake3_hasher) == 1912       # exact C layout from DWARF
end

@testset "Value macros + portable build" begin
    @test Blake3.BLAKE3_KEY_LEN()   == 32
    @test Blake3.BLAKE3_OUT_LEN()   == 32
    @test Blake3.BLAKE3_BLOCK_LEN() == 64
    @test Blake3.BLAKE3_CHUNK_LEN() == 1024
    @test Blake3.BLAKE3_MAX_DEPTH() == 54
    @test Blake3.BLAKE3_VERSION_STRING() == "1.8.5"
    @test Blake3.blake3_version()        == "1.8.5"
    # We excluded every SIMD TU and defined BLAKE3_NO_*; the runtime dispatch
    # must therefore report the scalar/portable degree of 1.
    @test Blake3.blake3_simd_degree() == 1
end

# ── Known-answer tests ────────────────────────────────────────────────────────

@testset "KAT — default hash (len=$n)" for n in (0, 3, 1024)
    @test b3hex(testinput(n); mode=:hash) == VEC[n].hash
end

@testset "KAT — keyed hash (len=$n)" for n in (0, 3, 1024)
    @test b3hex(testinput(n); mode=:keyed) == VEC[n].keyed
end

@testset "KAT — derive_key (len=$n)" for n in (0, 3, 1024)
    # Both the strlen entrypoint and the explicit-length entrypoint must agree
    # with the upstream vector and with each other.
    @test b3hex(testinput(n); mode=:derive)     == VEC[n].derive
    @test b3hex(testinput(n); mode=:derive_raw) == VEC[n].derive
end

# ── Extended output (XOF) ─────────────────────────────────────────────────────

@testset "Extended output is a prefix-stable stream" begin
    inp  = testinput(3)
    long = b3hex(inp; outlen=64)
    @test length(long) == 128
    @test long[1:64] == VEC[3].hash                     # first 32 B == the digest
    tail = b3hex(inp; outlen=32, seek=32)               # finalize_seek(32, 32)
    @test tail == long[65:128]
end

# ── Incremental / streaming ───────────────────────────────────────────────────

@testset "Chunked update == single-shot" begin
    inp  = testinput(1024)
    href = Ref{Blake3.blake3_hasher}()
    Blake3.blake3_hasher_init(href)
    for chunk in (inp[1:100], inp[101:500], inp[501:end])   # 100 + 400 + 524
        Blake3.blake3_hasher_update(href, chunk, length(chunk))
    end
    out = Vector{UInt8}(undef, 32)
    Blake3.blake3_hasher_finalize(href, out, 32)
    @test bytes2hex(out) == VEC[1024].hash
end

# ── Lifecycle: reset ──────────────────────────────────────────────────────────

@testset "reset restores a fresh hasher" begin
    href = Ref{Blake3.blake3_hasher}()
    Blake3.blake3_hasher_init(href)
    Blake3.blake3_hasher_update(href, testinput(1024), 1024)
    Blake3.blake3_hasher_reset(href)
    Blake3.blake3_hasher_update(href, testinput(3), 3)
    out = Vector{UInt8}(undef, 32)
    Blake3.blake3_hasher_finalize(href, out, 32)
    @test bytes2hex(out) == VEC[3].hash                 # == a fresh len-3 hash
end

# ── Edge / negative behaviour ─────────────────────────────────────────────────

@testset "Domain separation + zero-length finalize" begin
    inp = testinput(3)
    h = b3hex(inp; mode=:hash)
    k = b3hex(inp; mode=:keyed)
    d = b3hex(inp; mode=:derive)
    @test h != k && h != d && k != d                    # 3 distinct digests
    # out_len == 0 is a well-defined no-op: it must not crash or write.
    href = Ref{Blake3.blake3_hasher}()
    Blake3.blake3_hasher_init(href)
    @test Blake3.blake3_hasher_finalize(href, UInt8[], 0) === nothing
end

end # top testset

println("\nAll BLAKE3 Hub tests passed.")
