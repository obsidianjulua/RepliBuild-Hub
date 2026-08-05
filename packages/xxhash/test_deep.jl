#!/usr/bin/env julia
# xxHash Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
# Where a build test proves the pipeline, this file leans on the wrapper:
#   - the OFFICIAL upstream sanity vectors for XXH32/XXH64/XXH3-64/XXH3-128,
#     replayed over upstream's own fillTestBuffer() PRNG stream
#   - Tier-1 liveness: the sliced llvmcall kernels actually reach llvmcall
#   - mixed-tier coherence: Tier-1 one-shot vs Tier-3 streaming must agree
#   - streaming == one-shot under arbitrary chunk splits
#   - state copy independence, canonical (big-endian) roundtrips
#   - secret derivation, incl. the documented generateSecret_fromSeed identity
#   - unaligned inputs, state churn, GC stress
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/xxhash/test_deep.jl

using Test
using InteractiveUtils: code_typed

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Xxhash.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

# ── Upstream oracle ──────────────────────────────────────────────────────────
# tests/sanity_test.c fills its buffer from a fixed 64-bit LCG-ish stream and
# every vector below is a hash of a PREFIX of that stream. Reproducing it here
# is what makes the vectors an INDEPENDENT oracle rather than a self-check:
#
#     XSUM_U64 byteGen = PRIME32;
#     for (i = 0; i < len; ++i) { buffer[i] = (U8)(byteGen >> 56); byteGen *= PRIME64; }
const PRIME32 = 0x9E3779B1 % UInt64
const PRIME64 = 0x9E3779B185EBCA8D % UInt64
const SANITY_BUFFER_SIZE = 4096 + 64 + 1

function fill_test_buffer(n::Integer)
    buf = Vector{UInt8}(undef, n)
    byteGen = PRIME32
    @inbounds for i in 1:n
        buf[i] = UInt8(byteGen >> 56)
        byteGen *= PRIME64          # wraps mod 2^64, matching XSUM_U64
    end
    return buf
end

const SANITY = fill_test_buffer(SANITY_BUFFER_SIZE)

# Hash a length-`len` prefix of the sanity buffer.
prefix(len::Integer) = @view SANITY[1:len]

# The wrapper takes pointers as `Any`; a view is not a valid ccall argument, so
# materialize. (Deliberately a copy per call — it also exercises fresh, freshly
# GC-allocated buffers rather than one long-lived pinned block.)
buf(len::Integer) = SANITY[1:len]

include(joinpath(@__DIR__, "test_deep_vectors.jl"))

# ── Tests ────────────────────────────────────────────────────────────────────

@testset "xxHash Deep Tests" begin

@testset "Library identity" begin
    # 0.8.3 → 00 08 03 encoded as major*10000 + minor*100 + release
    @test Xxhash.XXH_versionNumber() == 803
    @test Xxhash.XXH_OK == Xxhash.XXH_errorcode(0)
    @test Xxhash.XXH_ERROR == Xxhash.XXH_errorcode(1)
end

@testset "Tier-1 slicing is live" begin
    # The point of the sliced-llvmcall rebuild: the kernels must actually
    # generate llvmcall at runtime, not silently sit on the ccall fallback.
    @test !isempty(Xxhash.TIER1_FUNCTIONS)
    @test "XXH32" in Xxhash.TIER1_FUNCTIONS
    @test "XXH64" in Xxhash.TIER1_FUNCTIONS

    slices_dir = joinpath(PKG_DIR, "julia", "slices")
    @test isdir(slices_dir)
    lls = filter(f -> endswith(f, ".ll"), readdir(slices_dir))
    @test length(lls) == length(Xxhash.TIER1_FUNCTIONS)

    # Every slice file must be non-trivial IR naming its own entry symbol.
    for f in lls
        ir = read(joinpath(slices_dir, f), String)
        @test occursin("define", ir)
        @test occursin(splitext(f)[1], ir)
    end

    # The generated kernel resolves to llvmcall (not the ccall demotion path).
    # Argument types come from the kernel's own method signature: a mismatched
    # hand-written one yields an EMPTY code_typed, which reads as "no llvmcall"
    # and would pass the negative check below while proving nothing.
    function kernel_emits_llvmcall(kernel)
        ms = collect(methods(kernel))
        isempty(ms) && error("no method for $kernel")
        argtypes = Base.tuple_type_tail(ms[1].sig)
        ct = code_typed(kernel, argtypes)
        isempty(ct) && error("code_typed empty for $kernel with $argtypes")
        return occursin("llvmcall", string(ct))
    end
    @test kernel_emits_llvmcall(Xxhash._TIER1_XXH32)
    @test kernel_emits_llvmcall(Xxhash._TIER1_XXH64)

    # ...and a Tier-3 function stays a ccall — the tiers are genuinely mixed.
    ct3 = code_typed(Xxhash.XXH3_64bits, (Vector{UInt8}, Int))
    @test !occursin("llvmcall", string(ct3))
end

@testset "XXH32 — upstream sanity vectors" begin
    for (len, seed, want) in XXH32_VEC
        @test Xxhash.XXH32(buf(len), len, UInt32(seed)) == UInt32(want)
    end
end

@testset "XXH64 — upstream sanity vectors" begin
    for (len, seed, want) in XXH64_VEC
        @test Xxhash.XXH64(buf(len), len, UInt64(seed)) == UInt64(want)
    end
end

@testset "XXH3-64 — upstream sanity vectors" begin
    for (len, seed, want) in XXH3_VEC
        b = buf(len)
        if seed == 0
            # The seedless entry point must agree with the seed-0 vector.
            @test Xxhash.XXH3_64bits(b, len) == UInt64(want)
        end
        @test Xxhash.XXH3_64bits_withSeed(b, len, UInt64(seed)) == UInt64(want)
    end
end

@testset "XXH3-128 — upstream sanity vectors" begin
    for (len, seed, lo, hi) in XXH128_VEC
        b = buf(len)
        h = Xxhash.XXH3_128bits_withSeed(b, len, UInt64(seed))
        @test h.low64 == UInt64(lo)
        @test h.high64 == UInt64(hi)
        if seed == 0
            h0 = Xxhash.XXH3_128bits(b, len)
            @test h0.low64 == UInt64(lo)
            @test h0.high64 == UInt64(hi)
        end
        # XXH128() is the same function under its legacy name.
        h2 = Xxhash.XXH128(b, len, UInt64(seed))
        @test h2.low64 == UInt64(lo) && h2.high64 == UInt64(hi)
    end
end

@testset "Mixed-tier coherence (Tier-1 one-shot vs Tier-3 streaming)" begin
    # XXH32/XXH64 one-shot are Tier 1 (llvmcall on a slice); *_update is Tier 3
    # (ccall into the .so). If static promotion had left the two tiers looking at
    # different copies of internal state, these would diverge — this is the
    # cJSON-class check, rotated onto a hash.
    for len in (0, 1, 15, 16, 17, 128, 241, 1024, 4096)
        b = buf(len)

        s32 = Xxhash.XXH32_createState()
        @test s32 != C_NULL
        @test Xxhash.XXH32_reset(s32, UInt32(0)) == Xxhash.XXH_OK
        len > 0 && @test Xxhash.XXH32_update(s32, b, len) == Xxhash.XXH_OK
        @test Xxhash.XXH32_digest(s32) == Xxhash.XXH32(b, len, UInt32(0))
        @test Xxhash.XXH32_freeState(s32) == Xxhash.XXH_OK

        s64 = Xxhash.XXH64_createState()
        @test Xxhash.XXH64_reset(s64, UInt64(0)) == Xxhash.XXH_OK
        len > 0 && @test Xxhash.XXH64_update(s64, b, len) == Xxhash.XXH_OK
        @test Xxhash.XXH64_digest(s64) == Xxhash.XXH64(b, len, UInt64(0))
        @test Xxhash.XXH64_freeState(s64) == Xxhash.XXH_OK
    end
end

@testset "Streaming equals one-shot under arbitrary chunk splits" begin
    # Chunk boundaries are where a streaming implementation's internal buffer
    # management goes wrong; walk a spread of splits including 1-byte dribbles.
    for len in (0, 1, 4, 16, 31, 64, 129, 240, 241, 512, 2048, 4160)
        b = buf(len)
        want32 = Xxhash.XXH32(b, len, UInt32(0))
        want64 = Xxhash.XXH64(b, len, UInt64(0))
        want3  = Xxhash.XXH3_64bits(b, len)
        want128 = Xxhash.XXH3_128bits(b, len)

        for chunk in (1, 3, 7, 16, 64, 1000)
            s32 = Xxhash.XXH32_createState(); Xxhash.XXH32_reset(s32, UInt32(0))
            s64 = Xxhash.XXH64_createState(); Xxhash.XXH64_reset(s64, UInt64(0))
            s3  = Xxhash.XXH3_createState();  Xxhash.XXH3_64bits_reset(s3)
            s128 = Xxhash.XXH3_createState(); Xxhash.XXH3_128bits_reset(s128)

            off = 0
            while off < len
                n = min(chunk, len - off)
                part = b[(off + 1):(off + n)]
                @test Xxhash.XXH32_update(s32, part, n) == Xxhash.XXH_OK
                @test Xxhash.XXH64_update(s64, part, n) == Xxhash.XXH_OK
                @test Xxhash.XXH3_64bits_update(s3, part, n) == Xxhash.XXH_OK
                @test Xxhash.XXH3_128bits_update(s128, part, n) == Xxhash.XXH_OK
                off += n
            end

            @test Xxhash.XXH32_digest(s32) == want32
            @test Xxhash.XXH64_digest(s64) == want64
            @test Xxhash.XXH3_64bits_digest(s3) == want3
            h = Xxhash.XXH3_128bits_digest(s128)
            @test h.low64 == want128.low64 && h.high64 == want128.high64

            Xxhash.XXH32_freeState(s32); Xxhash.XXH64_freeState(s64)
            Xxhash.XXH3_freeState(s3);   Xxhash.XXH3_freeState(s128)
        end
    end
end

@testset "State copy is independent" begin
    b = buf(1000)
    src = Xxhash.XXH64_createState()
    Xxhash.XXH64_reset(src, UInt64(0))
    Xxhash.XXH64_update(src, b, 500)

    dst = Xxhash.XXH64_createState()
    Xxhash.XXH64_copyState(dst, src)

    # Feeding only one of them must not disturb the other.
    tail = SANITY[501:1000]
    Xxhash.XXH64_update(src, tail, 500)
    @test Xxhash.XXH64_digest(src) == Xxhash.XXH64(b, 1000, UInt64(0))
    @test Xxhash.XXH64_digest(dst) == Xxhash.XXH64(buf(500), 500, UInt64(0))

    # Continuing the copy afterwards reaches the same place as the original.
    Xxhash.XXH64_update(dst, tail, 500)
    @test Xxhash.XXH64_digest(dst) == Xxhash.XXH64_digest(src)

    Xxhash.XXH64_freeState(src); Xxhash.XXH64_freeState(dst)

    # Same for the XXH3 state (much larger, with an embedded secret).
    s1 = Xxhash.XXH3_createState(); Xxhash.XXH3_64bits_reset_withSeed(s1, UInt64(42))
    Xxhash.XXH3_64bits_update(s1, b, 300)
    s2 = Xxhash.XXH3_createState(); Xxhash.XXH3_copyState(s2, s1)
    Xxhash.XXH3_64bits_update(s1, SANITY[301:1000], 700)
    @test Xxhash.XXH3_64bits_digest(s1) == Xxhash.XXH3_64bits_withSeed(b, 1000, UInt64(42))
    @test Xxhash.XXH3_64bits_digest(s2) == Xxhash.XXH3_64bits_withSeed(buf(300), 300, UInt64(42))
    Xxhash.XXH3_freeState(s1); Xxhash.XXH3_freeState(s2)
end

@testset "Canonical (big-endian) representation roundtrips" begin
    for len in (0, 7, 64, 1024)
        b = buf(len)

        h32 = Xxhash.XXH32(b, len, UInt32(0))
        c32 = Ref(Xxhash.XXH32_canonical_t())
        Xxhash.XXH32_canonicalFromHash(c32, h32)
        # Canonical form is big-endian: byte 1 is the most significant.
        @test c32[].digest[1] == UInt8((h32 >> 24) & 0xff)
        @test c32[].digest[4] == UInt8(h32 & 0xff)
        @test Xxhash.XXH32_hashFromCanonical(c32) == h32

        h64 = Xxhash.XXH64(b, len, UInt64(0))
        c64 = Ref(Xxhash.XXH64_canonical_t())
        Xxhash.XXH64_canonicalFromHash(c64, h64)
        @test c64[].digest[1] == UInt8((h64 >> 56) & 0xff)
        @test c64[].digest[8] == UInt8(h64 & 0xff)
        @test Xxhash.XXH64_hashFromCanonical(c64) == h64

        h128 = Xxhash.XXH3_128bits(b, len)
        c128 = Ref(Xxhash.XXH128_canonical_t())
        Xxhash.XXH128_canonicalFromHash(c128, h128)
        @test c128[].digest[1] == UInt8((h128.high64 >> 56) & 0xff)   # high first
        @test c128[].digest[16] == UInt8(h128.low64 & 0xff)
        back = Xxhash.XXH128_hashFromCanonical(c128)
        @test back.low64 == h128.low64 && back.high64 == h128.high64
    end
end

@testset "XXH128 comparison semantics" begin
    a = Xxhash.XXH3_128bits(buf(100), 100)
    b = Xxhash.XXH3_128bits(buf(101), 101)
    ra, rb = Ref(a), Ref(b)

    @test Xxhash.XXH128_isEqual(a, a) == 1
    @test Xxhash.XXH128_isEqual(a, b) == 0
    @test Xxhash.XXH128_cmp(ra, ra) == 0
    # cmp is a total order: exactly one direction is negative.
    @test Xxhash.XXH128_cmp(ra, rb) == -Xxhash.XXH128_cmp(rb, ra)
    @test Xxhash.XXH128_cmp(ra, rb) != 0
end

@testset "Secrets" begin
    SECRET_MIN = 136          # XXH3_SECRET_SIZE_MIN
    SECRET_DEFAULT = 192      # XXH3_SECRET_DEFAULT_SIZE

    secret = zeros(UInt8, SECRET_DEFAULT)
    @test Xxhash.XXH3_generateSecret(secret, SECRET_DEFAULT, buf(64), 64) == Xxhash.XXH_OK
    @test any(!iszero, secret)

    other = zeros(UInt8, SECRET_DEFAULT)
    Xxhash.XXH3_generateSecret(other, SECRET_DEFAULT, buf(65), 65)
    @test secret != other                      # different customSeed → different secret

    for len in (0, 32, 240, 241, 2048)
        b = buf(len)
        h = Xxhash.XXH3_64bits_withSecret(b, len, secret, SECRET_DEFAULT)
        @test h == Xxhash.XXH3_64bits_withSecret(b, len, secret, SECRET_DEFAULT)  # deterministic
        @test h != Xxhash.XXH3_64bits_withSecret(b, len, other, SECRET_DEFAULT)

        # Streaming with the same secret must land on the same digest.
        st = Xxhash.XXH3_createState()
        @test Xxhash.XXH3_64bits_reset_withSecret(st, secret, SECRET_DEFAULT) == Xxhash.XXH_OK
        len > 0 && Xxhash.XXH3_64bits_update(st, b, len)
        @test Xxhash.XXH3_64bits_digest(st) == h
        Xxhash.XXH3_freeState(st)
    end

    # Documented identity (xxhash.h): a secret produced by
    # XXH3_generateSecret_fromSeed() makes _withSecretandSeed() reproduce
    # _withSeed() EXACTLY. This is a cross-function oracle, not a self-check.
    seeded = zeros(UInt8, SECRET_DEFAULT)
    seed = UInt64(0x9E3779B185EBCA8D)
    Xxhash.XXH3_generateSecret_fromSeed(seeded, seed)
    for len in (0, 16, 240, 241, 1024, 4096)
        b = buf(len)
        @test Xxhash.XXH3_64bits_withSecretandSeed(b, len, seeded, SECRET_DEFAULT, seed) ==
              Xxhash.XXH3_64bits_withSeed(b, len, seed)
        h1 = Xxhash.XXH3_128bits_withSecretandSeed(b, len, seeded, SECRET_DEFAULT, seed)
        h2 = Xxhash.XXH3_128bits_withSeed(b, len, seed)
        @test h1.low64 == h2.low64 && h1.high64 == h2.high64
    end

    @test SECRET_MIN <= SECRET_DEFAULT   # the minimum we relied on above holds
end

@testset "Unaligned and offset inputs" begin
    # Hash the same bytes from differently-aligned addresses; xxHash documents
    # alignment independence, and a slice that mis-declared its argument would
    # show up here as a mismatch.
    payload = SANITY[1:257]
    want = Xxhash.XXH64(payload, 257, UInt64(7))
    for pad in 1:8
        padded = vcat(zeros(UInt8, pad), payload)
        GC.@preserve padded begin
            p = pointer(padded) + pad
            @test Xxhash.XXH64(p, 257, UInt64(7)) == want
            @test Xxhash.XXH3_64bits(p, 257) == Xxhash.XXH3_64bits(payload, 257)
        end
    end
end

@testset "Edge cases" begin
    empty = UInt8[]
    # Zero-length hashing is well defined and seed-sensitive.
    @test Xxhash.XXH32(empty, 0, UInt32(0)) == 0x02cc5d05
    @test Xxhash.XXH32(empty, 0, UInt32(1)) != Xxhash.XXH32(empty, 0, UInt32(0))
    @test Xxhash.XXH64(empty, 0, UInt64(0)) == 0xef46db3751d8e999

    # A NULL pointer with length 0 is the documented degenerate call.
    @test Xxhash.XXH32(C_NULL, 0, UInt32(0)) == 0x02cc5d05
    @test Xxhash.XXH3_64bits(C_NULL, 0) == Xxhash.XXH3_64bits(empty, 0)

    # Digest is idempotent — calling it twice must not consume the state.
    st = Xxhash.XXH64_createState()
    Xxhash.XXH64_reset(st, UInt64(0))
    Xxhash.XXH64_update(st, buf(99), 99)
    d1 = Xxhash.XXH64_digest(st)
    @test Xxhash.XXH64_digest(st) == d1
    # ...and reset returns it to the empty-input digest.
    Xxhash.XXH64_reset(st, UInt64(0))
    @test Xxhash.XXH64_digest(st) == Xxhash.XXH64(empty, 0, UInt64(0))
    Xxhash.XXH64_freeState(st)

    # Single-bit input changes propagate (avalanche sanity, not a strict claim).
    one = UInt8[0x00]
    two = UInt8[0x01]
    @test Xxhash.XXH64(one, 1, UInt64(0)) != Xxhash.XXH64(two, 1, UInt64(0))
    @test Xxhash.XXH3_128bits(one, 1).low64 != Xxhash.XXH3_128bits(two, 1).low64
end

@testset "State churn and GC stress" begin
    # Many create/use/free cycles across all three state types, with Julia GC
    # pressure interleaved — catches a slice binding a stale allocator symbol.
    want = Xxhash.XXH3_64bits(buf(777), 777)
    for i in 1:500
        s = Xxhash.XXH3_createState()
        @assert s != C_NULL
        Xxhash.XXH3_64bits_reset(s)
        Xxhash.XXH3_64bits_update(s, buf(777), 777)
        @assert Xxhash.XXH3_64bits_digest(s) == want
        @assert Xxhash.XXH3_freeState(s) == Xxhash.XXH_OK
        iszero(i % 100) && GC.gc()
    end
    @test true

    # Hammer the Tier-1 one-shot path with churning garbage buffers.
    acc = UInt64(0)
    for i in 1:5000
        b = rand(UInt8, (i % 300) + 1)
        acc ⊻= Xxhash.XXH64(b, length(b), UInt64(i))
        iszero(i % 1000) && GC.gc()
    end
    @test acc != 0
end

end  # top-level testset
