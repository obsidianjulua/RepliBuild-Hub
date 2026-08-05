#!/usr/bin/env julia
# BLAKE3 Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
# Where test.jl proves the pipeline against a hand-picked slice of the KAT, this
# file leans on the wrapper:
#   - ALL 35 upstream cases × 3 modes, at FULL extended (XOF) length
#   - finalize_seek across the whole XOF stream, incl. mid-block offsets
#   - streaming under arbitrary chunk splits, across chunk/subtree boundaries
#   - reset semantics and hasher-struct copy independence
#   - the portable-build proof (simd_degree == 1) and the version-string canary
#     that catches a macro-shim resolving to a system header
#   - the low-level compression primitives, which are the sliced Tier-1 targets
#   - Tier-1 liveness and mixed-tier coherence
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/blake3/test_deep.jl

using Test
using InteractiveUtils: code_typed

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Blake3.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)
include(joinpath(@__DIR__, "test_deep_vectors.jl"))

# ── Oracle plumbing ──────────────────────────────────────────────────────────
# Upstream defines the test input as input[i] = i % 251.
kat_input(n::Integer) = UInt8[UInt8(i % 251) for i in 0:(n - 1)]

const KEY_BYTES = collect(codeunits(KAT_KEY))     # exactly BLAKE3_KEY_LEN
const CTX_BYTES = collect(codeunits(KAT_CONTEXT))

"Fresh hasher in the requested mode."
function new_hasher(mode::Symbol)
    h = Ref(Blake3.blake3_hasher())
    if mode === :hash
        Blake3.blake3_hasher_init(h)
    elseif mode === :keyed
        Blake3.blake3_hasher_init_keyed(h, KEY_BYTES)
    elseif mode === :derive
        Blake3.blake3_hasher_init_derive_key(h, KAT_CONTEXT)       # strlen path
    elseif mode === :derive_raw
        Blake3.blake3_hasher_init_derive_key_raw(h, CTX_BYTES, length(CTX_BYTES))
    else
        error("bad mode $mode")
    end
    return h
end

"Hash `input` in `mode`, producing `outlen` bytes from offset `seek`."
function b3(input::Vector{UInt8}, mode::Symbol; outlen::Integer=32, seek::Integer=0)
    h = new_hasher(mode)
    isempty(input) || Blake3.blake3_hasher_update(h, input, length(input))
    out = Vector{UInt8}(undef, Int(outlen))
    if seek == 0
        Blake3.blake3_hasher_finalize(h, out, outlen)
    else
        Blake3.blake3_hasher_finalize_seek(h, UInt64(seek), out, outlen)
    end
    return out
end

b3hex(args...; kw...) = bytes2hex(b3(args...; kw...))

"""
Does the Tier-1 `@generated` kernel actually generate an `llvmcall`?

The argument types are read off the kernel's own method signature rather than
written out here: a hand-written signature that doesn't match returns an EMPTY
`code_typed` result, which reads as "no llvmcall" and passes a naive negative
check while proving nothing. Empty is an error, not a verdict.
"""
function kernel_emits_llvmcall(kernel)
    ms = collect(methods(kernel))
    isempty(ms) && error("no method for $kernel")
    argtypes = Base.tuple_type_tail(ms[1].sig)
    ct = code_typed(kernel, argtypes)
    isempty(ct) && error("code_typed empty for $kernel with $argtypes")
    return occursin("llvmcall", string(ct))
end

@testset "BLAKE3 Deep Tests" begin

@testset "Build identity — portable, vendored header" begin
    # The SIMD translation units are excluded and every BLAKE3_NO_* is defined,
    # so dispatch must fall through to the portable path. Degree 1 is the
    # load-bearing proof that the SIMD-off build is real and not just unused.
    @test Blake3.blake3_simd_degree() == 1

    # Version comes from the macro shim. If that shim resolved a bare
    # "blake3.h" to the system libblake3 (1.8.4 on this box) instead of the
    # vendored c/blake3.h, this is the ONLY symptom. Guarded in the engine now;
    # asserted here so the package notices independently.
    @test Blake3.blake3_version() == "1.8.5"
    @test Blake3.BLAKE3_VERSION_STRING() == "1.8.5"

    # Compiler-erased constants, shimmed as bare-expression macros.
    @test Blake3.BLAKE3_KEY_LEN() == 32
    @test Blake3.BLAKE3_OUT_LEN() == 32
    @test Blake3.BLAKE3_BLOCK_LEN() == 64
    @test Blake3.BLAKE3_CHUNK_LEN() == 1024
    @test Blake3.BLAKE3_MAX_DEPTH() == 54
    @test length(KEY_BYTES) == Blake3.BLAKE3_KEY_LEN()
end

@testset "Tier-1 slicing is live" begin
    @test !isempty(Blake3.TIER1_FUNCTIONS)
    @test "blake3_hasher_init" in Blake3.TIER1_FUNCTIONS
    @test "blake3_hasher_finalize" in Blake3.TIER1_FUNCTIONS

    slices_dir = joinpath(PKG_DIR, "julia", "slices")
    @test isdir(slices_dir)
    lls = filter(f -> endswith(f, ".ll"), readdir(slices_dir))
    @test length(lls) == length(Blake3.TIER1_FUNCTIONS)
    for f in lls
        @test occursin("define", read(joinpath(slices_dir, f), String))
    end

    @test kernel_emits_llvmcall(Blake3._TIER1_blake3_hasher_init)
    @test kernel_emits_llvmcall(Blake3._TIER1_blake3_hasher_finalize)

    # blake3_hasher_update is NOT sliced (it stays Tier 3), so every KAT below
    # is already a mixed-tier run: Tier-1 init/finalize around a Tier-3 update.
    @test !("blake3_hasher_update" in Blake3.TIER1_FUNCTIONS)
end

@testset "Upstream KAT — all cases, all modes, full XOF length" begin
    for (len, hash_hex, keyed_hex, derive_hex) in KAT_CASES
        input = kat_input(len)
        nbytes = length(hash_hex) ÷ 2
        @test b3hex(input, :hash;   outlen=nbytes) == hash_hex
        @test b3hex(input, :keyed;  outlen=nbytes) == keyed_hex
        @test b3hex(input, :derive; outlen=nbytes) == derive_hex

        # The raw-length derive_key entry point must agree with the strlen one.
        @test b3hex(input, :derive_raw; outlen=nbytes) == derive_hex
    end
end

@testset "finalize_seek walks the same XOF stream" begin
    # Seeking must be equivalent to slicing the extended output — including
    # offsets that are not multiples of the 64-byte output block.
    for (len, hash_hex, keyed_hex, _) in KAT_CASES
        len > 8192 && continue          # keep the seek sweep to a sane runtime
        input = kat_input(len)
        full = hex2bytes(hash_hex)
        for seek in (1, 31, 32, 63, 64, 65, 100)
            seek >= length(full) && continue
            n = min(37, length(full) - seek)
            @test b3(input, :hash; outlen=n, seek=seek) == full[(seek + 1):(seek + n)]
        end
        fullk = hex2bytes(keyed_hex)
        @test b3(input, :keyed; outlen=33, seek=64) == fullk[65:97]
    end

    # A zero-length request must write nothing and not fault.
    h = new_hasher(:hash)
    Blake3.blake3_hasher_update(h, kat_input(100), 100)
    sentinel = fill(0xAB, 8)
    Blake3.blake3_hasher_finalize(h, sentinel, 0)
    @test all(==(0xAB), sentinel)
end

@testset "Streaming equals one-shot under arbitrary chunk splits" begin
    # Chunk (1024) and subtree boundaries are where a Merkle-tree hasher's
    # stack handling breaks; drive splits that straddle them deliberately.
    for len in (0, 1, 63, 64, 65, 1023, 1024, 1025, 2048, 2049, 4096, 8193, 16384)
        input = kat_input(len)
        want = b3(input, :hash; outlen=64)
        wantk = b3(input, :keyed; outlen=64)

        for chunk in (1, 7, 64, 100, 1023, 1024, 1025, 4096)
            h = new_hasher(:hash)
            hk = new_hasher(:keyed)
            off = 0
            while off < len
                n = min(chunk, len - off)
                part = input[(off + 1):(off + n)]
                Blake3.blake3_hasher_update(h, part, n)
                Blake3.blake3_hasher_update(hk, part, n)
                off += n
            end
            out = Vector{UInt8}(undef, 64); Blake3.blake3_hasher_finalize(h, out, 64)
            outk = Vector{UInt8}(undef, 64); Blake3.blake3_hasher_finalize(hk, outk, 64)
            @test out == want
            @test outk == wantk
        end
    end
end

@testset "Reset and hasher-copy independence" begin
    input = kat_input(3000)
    want = b3(input, :hash; outlen=32)

    h = new_hasher(:hash)
    Blake3.blake3_hasher_update(h, input, length(input))
    out1 = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(h, out1, 32)
    @test out1 == want

    # finalize is non-destructive: the state can be finalized twice.
    out2 = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(h, out2, 32)
    @test out2 == want

    # reset returns to the initial keying, NOT to a default-initialized hasher.
    Blake3.blake3_hasher_reset(h)
    Blake3.blake3_hasher_update(h, input, length(input))
    out3 = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(h, out3, 32)
    @test out3 == want

    hk = new_hasher(:keyed)
    Blake3.blake3_hasher_reset(hk)
    Blake3.blake3_hasher_update(hk, input, length(input))
    outk = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(hk, outk, 32)
    @test outk == b3(input, :keyed; outlen=32)   # still keyed after reset

    # The hasher is a plain struct: copying the Ref's value must fork the state.
    a = new_hasher(:hash)
    Blake3.blake3_hasher_update(a, kat_input(500), 500)
    b = Ref(a[])                       # by-value copy of the whole struct
    Blake3.blake3_hasher_update(a, kat_input(500), 500)
    oa = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(a, oa, 32)
    ob = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(b, ob, 32)
    @test ob == b3(kat_input(500), :hash)
    @test oa != ob
end

@testset "Keying modes are domain-separated" begin
    input = kat_input(1000)
    @test b3(input, :hash) != b3(input, :keyed)
    @test b3(input, :hash) != b3(input, :derive)
    @test b3(input, :keyed) != b3(input, :derive)

    # A different key gives a different hash.
    otherkey = copy(KEY_BYTES); otherkey[1] ⊻= 0x01
    h = Ref(Blake3.blake3_hasher())
    Blake3.blake3_hasher_init_keyed(h, otherkey)
    Blake3.blake3_hasher_update(h, input, length(input))
    out = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(h, out, 32)
    @test out != b3(input, :keyed)

    # A different context gives a different derived key.
    h2 = Ref(Blake3.blake3_hasher())
    Blake3.blake3_hasher_init_derive_key(h2, KAT_CONTEXT * "!")
    Blake3.blake3_hasher_update(h2, input, length(input))
    out2 = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(h2, out2, 32)
    @test out2 != b3(input, :derive)

    # An embedded NUL truncates the strlen path but not the raw path — proving
    # the two entry points really differ in how they measure the context.
    ctx_nul = "abc\0def"
    hs = Ref(Blake3.blake3_hasher()); Blake3.blake3_hasher_init_derive_key(hs, ctx_nul)
    hr = Ref(Blake3.blake3_hasher())
    Blake3.blake3_hasher_init_derive_key_raw(hr, collect(codeunits(ctx_nul)), sizeof(ctx_nul))
    os = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(hs, os, 32)
    orr = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(hr, orr, 32)
    @test os != orr

    ht = Ref(Blake3.blake3_hasher()); Blake3.blake3_hasher_init_derive_key(ht, "abc")
    ot = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(ht, ot, 32)
    @test os == ot   # strlen path stopped at the NUL
end

@testset "Low-level portable primitives (sliced Tier-1 targets)" begin
    # blake3_compress_in_place_portable and blake3_hash_many_portable are both
    # sliced. Exercise them directly so a bad slice can't hide behind the
    # high-level API, and check they agree with the dispatching front ends.
    IV = UInt32[0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
                0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]
    block = kat_input(64)
    CHUNK_START, CHUNK_END, ROOT = UInt8(1), UInt8(2), UInt8(8)
    flags = CHUNK_START | CHUNK_END | ROOT

    cv_a = copy(IV); cv_b = copy(IV)
    Blake3.blake3_compress_in_place(cv_a, block, UInt8(64), UInt64(0), flags)
    Blake3.blake3_compress_in_place_portable(cv_b, block, UInt8(64), UInt64(0), flags)
    @test cv_a == cv_b                 # dispatch really lands on portable
    @test cv_a != IV                   # and it did something

    # The compression of a single 64-byte block as a root chunk is exactly the
    # BLAKE3 hash of that block — cross-checks the primitive against the API.
    @test reinterpret(UInt8, cv_a)[1:32] == b3(block, :hash; outlen=32)

    # XOF form must agree with in-place on its first 32 bytes.
    xof = Vector{UInt8}(undef, 64)
    cv_c = copy(IV)
    Blake3.blake3_compress_xof(cv_c, block, UInt8(64), UInt64(0), flags, xof)
    @test xof[1:32] == reinterpret(UInt8, cv_a)[1:32]
    xof_p = Vector{UInt8}(undef, 64)
    cv_d = copy(IV)
    Blake3.blake3_compress_xof_portable(cv_d, block, UInt8(64), UInt64(0), flags, xof_p)
    @test xof_p == xof
end

@testset "Edge cases" begin
    # Empty input is a well-defined hash, not an error.
    @test b3hex(UInt8[], :hash) == first(c for c in KAT_CASES if c[1] == 0)[2][1:64]

    # Update with zero length is a no-op.
    h = new_hasher(:hash)
    Blake3.blake3_hasher_update(h, UInt8[], 0)
    out = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(h, out, 32)
    @test out == b3(UInt8[], :hash)

    # Long extended output stays consistent with seeked reads deep into it.
    input = kat_input(2049)
    long = b3(input, :hash; outlen=1024)
    @test b3(input, :hash; outlen=64, seek=960) == long[961:1024]
    @test b3(input, :hash; outlen=1, seek=1023) == long[1024:1024]

    # Binary-safe: NUL-heavy input hashes distinctly from truncation at the NUL.
    nulls = UInt8[0x61, 0x00, 0x62, 0x00, 0x63]
    @test b3(nulls, :hash) != b3(UInt8[0x61], :hash)
end

@testset "Churn and GC stress" begin
    # Many independent hashers, interleaved with Julia GC — a slice bound to a
    # stale symbol or a duplicated static would drift here.
    want = b3(kat_input(5000), :hash; outlen=32)
    for i in 1:400
        @assert b3(kat_input(5000), :hash; outlen=32) == want
        iszero(i % 100) && GC.gc()
    end
    @test true

    # Interleave two live hashers to make sure no shared mutable state leaks
    # between them (the class static promotion exists to prevent).
    h1 = new_hasher(:hash)
    h2 = new_hasher(:keyed)
    for i in 1:200
        blk = kat_input(97)
        Blake3.blake3_hasher_update(h1, blk, 97)
        Blake3.blake3_hasher_update(h2, blk, 97)
        iszero(i % 50) && GC.gc()
    end
    big = reduce(vcat, (kat_input(97) for _ in 1:200))
    o1 = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(h1, o1, 32)
    o2 = Vector{UInt8}(undef, 32); Blake3.blake3_hasher_finalize(h2, o2, 32)
    @test o1 == b3(big, :hash)
    @test o2 == b3(big, :keyed)
end

end  # top-level testset
