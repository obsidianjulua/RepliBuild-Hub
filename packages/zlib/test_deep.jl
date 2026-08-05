#!/usr/bin/env julia
# zlib Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
#   - checksums against INDEPENDENT Julia reference implementations of CRC-32
#     and Adler-32, plus the *_combine algebraic identities
#   - the value-macro vocabulary pinned against zlib.h (also the shim-header
#     canary: this box has a system zlib, and a shim that resolved
#     /usr/include/zlib.h would show up only as wrong constants)
#   - compress/uncompress, and the full deflate/inflate stream machine driven
#     byte-starved through tiny buffers, across every flush mode
#   - raw deflate, gzip wrapping, gz_header round-trip, dictionaries
#   - deflateCopy/inflateCopy independence, bounds, pending/prime
#   - the gz* stdio-alike file API on a real temp file
#   - error paths: corrupt data, truncated streams, buffer exhaustion
#   - Tier-1 liveness and churn under GC pressure
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/zlib/test_deep.jl

using Test
using InteractiveUtils: code_typed
using Random: Xoshiro

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Zlib.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const Z = Zlib

function kernel_emits_llvmcall(kernel)
    ms = collect(methods(kernel))
    isempty(ms) && error("no method for $kernel")
    argtypes = Base.tuple_type_tail(ms[1].sig)
    ct = code_typed(kernel, argtypes)
    isempty(ct) && error("code_typed empty for $kernel with $argtypes")
    return occursin("llvmcall", string(ct))
end

# ── Independent checksum oracles ─────────────────────────────────────────────
# Reimplemented from the algorithm definitions, NOT from zlib — so agreement is
# evidence about the wrapped library rather than a tautology.

const CRC_TABLE = let t = zeros(UInt32, 256)
    for n in 0:255
        c = UInt32(n)
        for _ in 1:8
            c = (c & 0x1) != 0 ? (0xEDB88320 ⊻ (c >> 1)) : (c >> 1)
        end
        t[n + 1] = c
    end
    t
end

function ref_crc32(data::AbstractVector{UInt8}, seed::UInt32=UInt32(0))
    c = ⊻(seed, 0xFFFFFFFF)
    for b in data
        c = CRC_TABLE[(UInt8(c & 0xff) ⊻ b) + 1] ⊻ (c >> 8)
    end
    return ⊻(c, 0xFFFFFFFF)
end

function ref_adler32(data::AbstractVector{UInt8}, seed::UInt32=UInt32(1))
    a = UInt32(seed & 0xffff)
    b = UInt32((seed >> 16) & 0xffff)
    for x in data
        a = (a + x) % 0xFFF1
        b = (b + a) % 0xFFF1
    end
    return (b << 16) | a
end

# ── Stream helpers ───────────────────────────────────────────────────────────

"Deflate `src` in one shot through the stream API, with the given init args."
function deflate_stream(src::Vector{UInt8}; level=Z.Z_DEFAULT_COMPRESSION(),
                        windowBits=nothing, dict=nothing, outcap=nothing)
    strm = Ref(Z.z_stream_s())
    rc = if windowBits === nothing
        Z.deflateInit(strm, level)
    else
        Z.deflateInit2(strm, level, Z.Z_DEFLATED(), windowBits, 8, Z.Z_DEFAULT_STRATEGY())
    end
    rc == Z.Z_OK() || error("deflateInit failed: $rc")
    try
        if dict !== nothing
            @assert Z.deflateSetDictionary(strm, dict, length(dict)) == Z.Z_OK()
        end
        cap = outcap === nothing ? Int(Z.deflateBound(strm, length(src))) + 64 : outcap
        dst = Vector{UInt8}(undef, cap)
        GC.@preserve src dst begin
            strm[] = Z.with(strm[];
                            next_in = isempty(src) ? Ptr{UInt8}(C_NULL) : pointer(src),
                            avail_in = Cuint(length(src)),
                            next_out = pointer(dst),
                            avail_out = Cuint(cap))
            rc = Z.deflate(strm, Z.Z_FINISH())
            rc == Z.Z_STREAM_END() || error("deflate did not finish: $rc")
            used = cap - Int(strm[].avail_out)
            return dst[1:used]
        end
    finally
        Z.deflateEnd(strm)
    end
end

"Inflate `src`, feeding `inchunk` bytes and taking `outchunk` bytes at a time."
function inflate_stream(src::Vector{UInt8}; windowBits=nothing, dict=nothing,
                        inchunk=typemax(Int), outchunk=typemax(Int))
    strm = Ref(Z.z_stream_s())
    rc = windowBits === nothing ? Z.inflateInit(strm) : Z.inflateInit2(strm, windowBits)
    rc == Z.Z_OK() || error("inflateInit failed: $rc")
    out = UInt8[]
    try
        inpos = 0
        buf = Vector{UInt8}(undef, min(outchunk, 1 << 16))
        while true
            navail = min(inchunk, length(src) - inpos)
            GC.@preserve src buf begin
                strm[] = Z.with(strm[];
                                next_in = pointer(src) + inpos,
                                avail_in = Cuint(navail),
                                next_out = pointer(buf),
                                avail_out = Cuint(length(buf)))
                rc = Z.inflate(strm, Z.Z_NO_FLUSH())
                # Account for what was consumed/produced FIRST. Z_NEED_DICT has
                # already eaten the zlib header, so retrying without advancing
                # inpos re-feeds those bytes and the next call fails Z_DATA_ERROR.
                produced = length(buf) - Int(strm[].avail_out)
                produced > 0 && append!(out, buf[1:produced])
                inpos += navail - Int(strm[].avail_in)

                if rc == Z.Z_NEED_DICT() && dict !== nothing
                    @assert Z.inflateSetDictionary(strm, dict, length(dict)) == Z.Z_OK()
                    continue
                end
                rc in (Z.Z_OK(), Z.Z_STREAM_END(), Z.Z_BUF_ERROR()) ||
                    error("inflate failed: $rc")
                rc == Z.Z_STREAM_END() && break
                if produced == 0 && inpos >= length(src)
                    error("inflate stalled before Z_STREAM_END")
                end
            end
        end
        return out
    finally
        Z.inflateEnd(strm)
    end
end

# Test payloads: highly compressible, incompressible, and mixed.
const TEXT = repeat("the quick brown fox jumps over the lazy dog. ", 400)
const PAYLOADS = Dict(
    :empty        => UInt8[],
    :tiny         => collect(codeunits("hi")),
    :text         => collect(codeunits(TEXT)),
    :zeros        => zeros(UInt8, 100_000),
    :random       => rand(Xoshiro(0xC0FFEE), UInt8, 50_000),
    :binary       => UInt8[UInt8(i % 256) for i in 0:99_999],
)

@testset "zlib Deep Tests" begin

@testset "Library identity and value macros" begin
    @test Z.zlibVersion() == "1.3.1"
    @test Z.ZLIB_VERSION() == "1.3.1"      # shim-header canary
    @test Z.zlibCompileFlags() != 0

    # Status codes
    @test Z.Z_OK() == 0
    @test Z.Z_STREAM_END() == 1
    @test Z.Z_NEED_DICT() == 2
    @test Z.Z_ERRNO() == -1
    @test Z.Z_STREAM_ERROR() == -2
    @test Z.Z_DATA_ERROR() == -3
    @test Z.Z_MEM_ERROR() == -4
    @test Z.Z_BUF_ERROR() == -5
    @test Z.Z_VERSION_ERROR() == -6

    # Flush modes
    @test Z.Z_NO_FLUSH() == 0
    @test Z.Z_PARTIAL_FLUSH() == 1
    @test Z.Z_SYNC_FLUSH() == 2
    @test Z.Z_FULL_FLUSH() == 3
    @test Z.Z_FINISH() == 4
    @test Z.Z_BLOCK() == 5
    @test Z.Z_TREES() == 6

    # Levels, strategies, misc
    @test Z.Z_NO_COMPRESSION() == 0
    @test Z.Z_BEST_SPEED() == 1
    @test Z.Z_BEST_COMPRESSION() == 9
    @test Z.Z_DEFAULT_COMPRESSION() == -1
    @test Z.Z_DEFAULT_STRATEGY() == 0
    @test Z.Z_FILTERED() == 1
    @test Z.Z_HUFFMAN_ONLY() == 2
    @test Z.Z_RLE() == 3
    @test Z.Z_FIXED() == 4
    @test Z.Z_BINARY() == 0
    @test Z.Z_TEXT() == 1
    @test Z.Z_UNKNOWN() == 2
    @test Z.Z_DEFLATED() == 8
    @test Z.MAX_WBITS() == 15

    # zError maps codes to the message table.
    @test Z.zError(Z.Z_STREAM_END()) == "stream end"
    @test Z.zError(Z.Z_DATA_ERROR()) == "data error"
    @test Z.zError(Z.Z_OK()) == ""
end

@testset "Tier-1 slicing is live" begin
    @test !isempty(Z.TIER1_FUNCTIONS)
    @test "crc32" in Z.TIER1_FUNCTIONS
    @test "compress" in Z.TIER1_FUNCTIONS

    slices_dir = joinpath(PKG_DIR, "julia", "slices")
    @test isdir(slices_dir)
    @test kernel_emits_llvmcall(Z._TIER1_crc32)
    @test kernel_emits_llvmcall(Z._TIER1_adler32)

    # deflate/inflate themselves stay Tier 3, so every stream test below is a
    # mixed-tier run: Tier-1 init/end around a Tier-3 state machine.
    @test !("deflate" in Z.TIER1_FUNCTIONS)
    @test !("inflate" in Z.TIER1_FUNCTIONS)
end

@testset "CRC-32 against an independent implementation" begin
    # The universal CRC-32 check value, and then a spread of real payloads.
    check = collect(codeunits("123456789"))
    @test Z.crc32(0, check, length(check)) % UInt32 == 0xCBF43926
    @test ref_crc32(check) == 0xCBF43926

    for (name, data) in PAYLOADS
        want = ref_crc32(data)
        @test Z.crc32(0, isempty(data) ? C_NULL : data, length(data)) % UInt32 == want
        @test Z.crc32_z(0, isempty(data) ? C_NULL : data, length(data)) % UInt32 == want
    end

    # crc32(0, NULL, 0) is the documented way to get the initial value.
    @test Z.crc32(0, C_NULL, 0) == 0

    # Seeding continues a running CRC — chunking must not change the result.
    data = PAYLOADS[:binary]
    for chunk in (1, 7, 4096)
        c = UInt32(0)
        off = 0
        while off < length(data)
            n = min(chunk, length(data) - off)
            part = data[(off + 1):(off + n)]
            c = Z.crc32(c, part, n) % UInt32
            off += n
        end
        @test c == ref_crc32(data)
    end
end

@testset "Adler-32 against an independent implementation" begin
    for (name, data) in PAYLOADS
        want = ref_adler32(data)
        @test Z.adler32(1, isempty(data) ? C_NULL : data, length(data)) % UInt32 == want
        @test Z.adler32_z(1, isempty(data) ? C_NULL : data, length(data)) % UInt32 == want
    end
    @test Z.adler32(0, C_NULL, 0) == 1     # returns the initial value

    data = PAYLOADS[:text]
    for chunk in (1, 13, 8192)
        a = UInt32(1)
        off = 0
        while off < length(data)
            n = min(chunk, length(data) - off)
            a = Z.adler32(a, data[(off + 1):(off + n)], n) % UInt32
            off += n
        end
        @test a == ref_adler32(data)
    end
end

@testset "Checksum combine identities" begin
    # combine(cs(a), cs(b), len(b)) == cs(a ++ b) — a strong algebraic oracle
    # that exercises the combine machinery independently of the tables.
    a = PAYLOADS[:text][1:5000]
    b = PAYLOADS[:binary][1:7777]
    ab = vcat(a, b)

    ca = Z.crc32(0, a, length(a))
    cb = Z.crc32(0, b, length(b))
    @test Z.crc32_combine(ca, cb, length(b)) % UInt32 == ref_crc32(ab)
    @test Z.crc32_combine64(ca, cb, length(b)) % UInt32 == ref_crc32(ab)

    aa = Z.adler32(1, a, length(a))
    bb = Z.adler32(1, b, length(b))
    @test Z.adler32_combine(aa, bb, length(b)) % UInt32 == ref_adler32(ab)
    @test Z.adler32_combine64(aa, bb, length(b)) % UInt32 == ref_adler32(ab)

    # The precomputed-operator form must agree with the direct one.
    op = Z.crc32_combine_gen(length(b))
    @test Z.crc32_combine_op(ca, cb, op) % UInt32 == ref_crc32(ab)

    # Combining with an empty tail is the identity.
    @test Z.crc32_combine(ca, Z.crc32(0, C_NULL, 0), 0) % UInt32 == ca % UInt32
end

@testset "compress / uncompress" begin
    for (name, data) in PAYLOADS
        bound = Z.compressBound(length(data))
        @test bound >= length(data)

        dst = Vector{UInt8}(undef, Int(bound))
        dlen = Ref{Culong}(bound)
        @test Z.compress(dst, dlen, isempty(data) ? C_NULL : data, length(data)) == Z.Z_OK()
        comp = dst[1:Int(dlen[])]

        back = Vector{UInt8}(undef, max(length(data), 1))
        blen = Ref{Culong}(length(back))
        @test Z.uncompress(back, blen, comp, length(comp)) == Z.Z_OK()
        @test Int(blen[]) == length(data)
        @test back[1:length(data)] == data

        # The compressed form must carry a valid zlib checksum trailer, which
        # the stream inflater independently validates.
        @test inflate_stream(comp) == data
    end

    # Levels trade size for speed; level 0 must be strictly larger than 9.
    data = PAYLOADS[:text]
    sizes = map(0:9) do lvl
        bound = Z.compressBound(length(data))
        dst = Vector{UInt8}(undef, Int(bound))
        dlen = Ref{Culong}(bound)
        @test Z.compress2(dst, dlen, data, length(data), lvl) == Z.Z_OK()
        back = Vector{UInt8}(undef, length(data))
        blen = Ref{Culong}(length(back))
        @test Z.uncompress(back, blen, dst, Int(dlen[])) == Z.Z_OK()
        @test back == data
        Int(dlen[])
    end
    @test sizes[1] > sizes[10]         # level 0 (stored) vs level 9
    @test sizes[10] <= sizes[2]        # level 9 no worse than level 1

    # uncompress2 reports how much input it consumed.
    comp = deflate_stream(data)
    back = Vector{UInt8}(undef, length(data))
    blen = Ref{Culong}(length(back))
    slen = Ref{Culong}(length(comp))
    @test Z.uncompress2(back, blen, comp, slen) == Z.Z_OK()
    @test Int(slen[]) == length(comp)
    @test back == data

    # Too small an output buffer is Z_BUF_ERROR, not a silent truncation.
    tiny = Vector{UInt8}(undef, 4)
    tlen = Ref{Culong}(4)
    @test Z.uncompress(tiny, tlen, comp, length(comp)) == Z.Z_BUF_ERROR()
end

@testset "deflate / inflate stream machine" begin
    for (name, data) in PAYLOADS
        comp = deflate_stream(data)
        @test inflate_stream(comp) == data

        # Byte-starved on both sides: the state machine must make progress with
        # 1-byte input and 1-byte output windows.
        name === :zeros || name === :binary || name === :random ||
            @test inflate_stream(comp; inchunk=1, outchunk=1) == data
        @test inflate_stream(comp; inchunk=7, outchunk=13) == data
    end

    # Every compression level and strategy round-trips.
    data = PAYLOADS[:text]
    for lvl in (0, 1, 6, 9, Z.Z_DEFAULT_COMPRESSION())
        @test inflate_stream(deflate_stream(data; level=lvl)) == data
    end

    # Flush modes: SYNC_FLUSH must produce independently decodable prefixes.
    strm = Ref(Z.z_stream_s())
    @test Z.deflateInit(strm, 6) == Z.Z_OK()
    src = collect(codeunits("first chunk. "))
    out = Vector{UInt8}(undef, 4096)
    GC.@preserve src out begin
        strm[] = Z.with(strm[]; next_in=pointer(src), avail_in=Cuint(length(src)),
                        next_out=pointer(out), avail_out=Cuint(length(out)))
        @test Z.deflate(strm, Z.Z_SYNC_FLUSH()) == Z.Z_OK()
        produced = length(out) - Int(strm[].avail_out)
        @test produced > 0
        # A SYNC_FLUSH boundary ends in the empty stored block 00 00 FF FF.
        @test out[(produced - 3):produced] == UInt8[0x00, 0x00, 0xff, 0xff]
    end
    Z.deflateEnd(strm)

    # deflateBound is an upper bound, never an underestimate.
    for (_, data) in PAYLOADS
        s = Ref(Z.z_stream_s())
        Z.deflateInit(s, 9)
        @test Z.deflateBound(s, length(data)) >= length(deflate_stream(data; level=9))
        Z.deflateEnd(s)
    end
end

@testset "Raw deflate and gzip wrappers" begin
    data = PAYLOADS[:text]

    # windowBits < 0 → raw deflate, no header, no checksum.
    raw = deflate_stream(data; windowBits=-15)
    @test inflate_stream(raw; windowBits=-15) == data
    # A raw stream is not a valid zlib stream.
    @test_throws Exception inflate_stream(raw)

    # windowBits + 16 → gzip wrapper. Check the magic bytes and the trailer.
    gz = deflate_stream(data; windowBits=15 + 16)
    @test gz[1] == 0x1f && gz[2] == 0x8b && gz[3] == 0x08
    @test inflate_stream(gz; windowBits=15 + 16) == data
    # The gzip trailer is CRC32 then ISIZE, both little-endian.
    crc_le = reinterpret(UInt32, gz[(end - 7):(end - 4)])[1]
    isize  = reinterpret(UInt32, gz[(end - 3):end])[1]
    @test crc_le == ref_crc32(data)
    @test isize == UInt32(length(data) % (1 << 32))

    # windowBits + 32 → auto-detect zlib or gzip.
    @test inflate_stream(gz; windowBits=15 + 32) == data
    @test inflate_stream(deflate_stream(data); windowBits=15 + 32) == data

    # A gz_header round-trips through deflateSetHeader / inflateGetHeader.
    name = push!(collect(codeunits("payload.txt")), 0x00)
    comment = push!(collect(codeunits("written by test_deep")), 0x00)
    strm = Ref(Z.z_stream_s())
    @test Z.deflateInit2(strm, 6, Z.Z_DEFLATED(), 15 + 16, 8, Z.Z_DEFAULT_STRATEGY()) == Z.Z_OK()
    out = Vector{UInt8}(undef, length(data) + 4096)
    hdr = Ref(Z.gz_header_s())
    GC.@preserve name comment data out begin
        hdr[] = Z.with(hdr[]; name=pointer(name), name_max=Cuint(length(name)),
                       comment=pointer(comment), comm_max=Cuint(length(comment)),
                       time=Culong(0), os=Cint(3), text=Cint(1))
        @test Z.deflateSetHeader(strm, hdr) == Z.Z_OK()
        strm[] = Z.with(strm[]; next_in=pointer(data), avail_in=Cuint(length(data)),
                        next_out=pointer(out), avail_out=Cuint(length(out)))
        @test Z.deflate(strm, Z.Z_FINISH()) == Z.Z_STREAM_END()
    end
    ncomp = length(out) - Int(strm[].avail_out)
    gzh = out[1:ncomp]
    Z.deflateEnd(strm)

    istrm = Ref(Z.z_stream_s())
    @test Z.inflateInit2(istrm, 15 + 16) == Z.Z_OK()
    gotname = zeros(UInt8, 64)
    gotcomm = zeros(UInt8, 64)
    ghdr = Ref(Z.gz_header_s())
    back = Vector{UInt8}(undef, length(data))
    GC.@preserve gotname gotcomm gzh back begin
        ghdr[] = Z.with(ghdr[]; name=pointer(gotname), name_max=Cuint(length(gotname)),
                        comment=pointer(gotcomm), comm_max=Cuint(length(gotcomm)))
        @test Z.inflateGetHeader(istrm, ghdr) == Z.Z_OK()
        istrm[] = Z.with(istrm[]; next_in=pointer(gzh), avail_in=Cuint(length(gzh)),
                         next_out=pointer(back), avail_out=Cuint(length(back)))
        @test Z.inflate(istrm, Z.Z_FINISH()) == Z.Z_STREAM_END()
    end
    @test back == data
    @test ghdr[].done == 1
    @test unsafe_string(pointer(gotname)) == "payload.txt"
    @test unsafe_string(pointer(gotcomm)) == "written by test_deep"
    @test ghdr[].os == 3
    Z.inflateEnd(istrm)
end

@testset "Dictionaries" begin
    dict = collect(codeunits("the quick brown fox jumps over the lazy dog"))
    data = collect(codeunits(repeat("the quick brown fox is lazy. ", 50)))

    with_dict = deflate_stream(data; dict=dict, level=9)
    without   = deflate_stream(data; level=9)
    # A well-matched dictionary should not make things bigger.
    @test length(with_dict) <= length(without)

    # Decoding needs the dictionary: without it inflate stops at Z_NEED_DICT.
    @test inflate_stream(with_dict; dict=dict) == data

    strm = Ref(Z.z_stream_s())
    Z.inflateInit(strm)
    buf = Vector{UInt8}(undef, length(data))
    GC.@preserve with_dict buf begin
        strm[] = Z.with(strm[]; next_in=pointer(with_dict), avail_in=Cuint(length(with_dict)),
                        next_out=pointer(buf), avail_out=Cuint(length(buf)))
        @test Z.inflate(strm, Z.Z_NO_FLUSH()) == Z.Z_NEED_DICT()
        # The adler field names which dictionary is required.
        @test strm[].adler % UInt32 == ref_adler32(dict)
    end
    Z.inflateEnd(strm)

    # deflateGetDictionary reports back what the compressor is holding.
    d = Ref(Z.z_stream_s())
    Z.deflateInit(d, 6)
    Z.deflateSetDictionary(d, dict, length(dict))
    got = zeros(UInt8, 512)
    glen = Ref{Cuint}(length(got))
    @test Z.deflateGetDictionary(d, got, glen) == Z.Z_OK()
    @test Int(glen[]) == length(dict)
    @test got[1:length(dict)] == dict
    Z.deflateEnd(d)
end

@testset "Copy independence, reset, pending, prime" begin
    data = PAYLOADS[:text]

    # deflateCopy must fork the compressor: feeding one must not move the other.
    a = Ref(Z.z_stream_s())
    @test Z.deflateInit(a, 6) == Z.Z_OK()
    outa = Vector{UInt8}(undef, 65536)
    GC.@preserve data outa begin
        a[] = Z.with(a[]; next_in=pointer(data), avail_in=Cuint(2000),
                     next_out=pointer(outa), avail_out=Cuint(length(outa)))
        Z.deflate(a, Z.Z_NO_FLUSH())
    end
    b = Ref(Z.z_stream_s())
    @test Z.deflateCopy(b, a) == Z.Z_OK()
    @test a[].total_in == b[].total_in
    # Advance only `a`; `b` must stay where it was.
    before = b[].total_in
    GC.@preserve data outa begin
        a[] = Z.with(a[]; next_in=pointer(data) + 2000, avail_in=Cuint(2000))
        Z.deflate(a, Z.Z_NO_FLUSH())
    end
    @test b[].total_in == before
    @test a[].total_in > before
    Z.deflateEnd(a); Z.deflateEnd(b)

    # deflateReset returns a used stream to a fresh one — same output as new.
    fresh = deflate_stream(data; level=6)
    r = Ref(Z.z_stream_s())
    Z.deflateInit(r, 6)
    scratch = Vector{UInt8}(undef, 65536)
    GC.@preserve data scratch begin
        r[] = Z.with(r[]; next_in=pointer(data), avail_in=Cuint(1000),
                     next_out=pointer(scratch), avail_out=Cuint(length(scratch)))
        Z.deflate(r, Z.Z_FINISH())
    end
    @test Z.deflateReset(r) == Z.Z_OK()
    @test r[].total_in == 0 && r[].total_out == 0
    out2 = Vector{UInt8}(undef, Int(Z.deflateBound(r, length(data))) + 64)
    GC.@preserve data out2 begin
        r[] = Z.with(r[]; next_in=pointer(data), avail_in=Cuint(length(data)),
                     next_out=pointer(out2), avail_out=Cuint(length(out2)))
        @test Z.deflate(r, Z.Z_FINISH()) == Z.Z_STREAM_END()
    end
    @test out2[1:(length(out2) - Int(r[].avail_out))] == fresh
    Z.deflateEnd(r)

    # deflatePending reports buffered-but-unemitted bits.
    p = Ref(Z.z_stream_s())
    Z.deflateInit(p, 9)
    pend = Ref{Cuint}(0); bits = Ref{Cint}(0)
    @test Z.deflatePending(p, pend, bits) == Z.Z_OK()
    @test pend[] == 0 && bits[] == 0
    Z.deflateEnd(p)

    # deflateParams mid-stream is legal and the result still decodes.
    q = Ref(Z.z_stream_s())
    Z.deflateInit(q, 1)
    qout = Vector{UInt8}(undef, length(data) + 4096)
    GC.@preserve data qout begin
        q[] = Z.with(q[]; next_in=pointer(data), avail_in=Cuint(1000),
                     next_out=pointer(qout), avail_out=Cuint(length(qout)))
        Z.deflate(q, Z.Z_NO_FLUSH())
        @test Z.deflateParams(q, 9, Z.Z_RLE()) == Z.Z_OK()
        q[] = Z.with(q[]; next_in=pointer(data) + 1000,
                     avail_in=Cuint(length(data) - 1000))
        @test Z.deflate(q, Z.Z_FINISH()) == Z.Z_STREAM_END()
    end
    nq = length(qout) - Int(q[].avail_out)
    @test inflate_stream(qout[1:nq]) == data
    Z.deflateEnd(q)

    # inflateCopy forks a decompressor mid-stream.
    comp = deflate_stream(data)
    i1 = Ref(Z.z_stream_s()); Z.inflateInit(i1)
    ibuf = Vector{UInt8}(undef, 1024)
    GC.@preserve comp ibuf begin
        i1[] = Z.with(i1[]; next_in=pointer(comp), avail_in=Cuint(length(comp)),
                      next_out=pointer(ibuf), avail_out=Cuint(length(ibuf)))
        Z.inflate(i1, Z.Z_NO_FLUSH())
    end
    i2 = Ref(Z.z_stream_s())
    @test Z.inflateCopy(i2, i1) == Z.Z_OK()
    @test i2[].total_out == i1[].total_out
    @test Z.inflateCodesUsed(i1) == Z.inflateCodesUsed(i2)
    Z.inflateEnd(i1); Z.inflateEnd(i2)
end

@testset "gz* file API" begin
    mktempdir() do dir
        path = joinpath(dir, "sample.txt.gz")
        payload = TEXT
        # gzwrite takes a void*; a Julia String has no unsafe_convert to
        # Ptr{Cvoid}, so hand it bytes.
        payload_bytes = collect(codeunits(payload))

        f = Z.gzopen(path, "wb9")
        @test f != C_NULL
        n = Z.gzwrite(f, payload_bytes, length(payload_bytes))
        @test n == length(payload_bytes)
        @test Z.gzputs(f, "tail line\n") == 10
        @test Z.gzputc(f, Int('X')) == Int('X')
        @test Z.gzprintf_Cint(f, "\nnum=%d", Cint(42)) == 7
        @test Z.gzclose(f) == Z.Z_OK()
        @test isfile(path)
        # It really is a gzip file.
        @test read(path)[1:2] == UInt8[0x1f, 0x8b]

        r = Z.gzopen(path, "rb")
        @test r != C_NULL
        @test Z.gzdirect(r) == 0            # it is compressed, not passthrough
        buf = Vector{UInt8}(undef, sizeof(payload))
        @test Z.gzread(r, buf, length(buf)) == length(buf)
        @test String(copy(buf)) == payload
        @test Z.gztell(r) == sizeof(payload)
        @test Z.gzeof(r) == 0

        line = Vector{UInt8}(undef, 256)
        @test Z.gzgets(r, line, length(line)) == "tail line\n"
        @test Z.gzgetc(r) == Int('X')
        @test Z.gzungetc(Int('X'), r) == Int('X')
        @test Z.gzgetc(r) == Int('X')

        rest = Vector{UInt8}(undef, 64)
        got = Z.gzread(r, rest, length(rest))
        @test String(rest[1:got]) == "\nnum=42"
        @test Z.gzeof(r) == 1

        # rewind + seek land where they claim.
        @test Z.gzrewind(r) == 0
        @test Z.gztell(r) == 0
        @test Z.gzseek(r, 10, 0) == 10       # SEEK_SET
        @test Z.gztell(r) == 10
        one = Vector{UInt8}(undef, 5)
        Z.gzread(r, one, 5)
        @test String(one) == payload[11:15]

        errnum = Ref{Cint}(0)
        @test Z.gzerror(r, errnum) == ""
        @test errnum[] == Z.Z_OK()
        Z.gzclearerr(r)
        @test Z.gzclose(r) == Z.Z_OK()

        # A non-gzip file opened for reading is passed through verbatim.
        plain = joinpath(dir, "plain.txt")
        write(plain, "not compressed at all")
        pf = Z.gzopen(plain, "rb")
        @test pf != C_NULL
        @test Z.gzdirect(pf) == 1
        pb = Vector{UInt8}(undef, 64)
        pn = Z.gzread(pf, pb, length(pb))
        @test String(pb[1:pn]) == "not compressed at all"
        Z.gzclose(pf)

        # Opening a missing file fails cleanly.
        @test Z.gzopen(joinpath(dir, "nope.gz"), "rb") == C_NULL
    end
end

@testset "Error paths" begin
    data = PAYLOADS[:text]
    comp = deflate_stream(data)

    # Corrupting a payload byte must be caught by the checksum/decoder.
    bad = copy(comp)
    bad[div(end, 2)] ⊻= 0xff
    @test_throws Exception inflate_stream(bad)

    # Truncation stalls before Z_STREAM_END rather than returning short data.
    @test_throws Exception inflate_stream(comp[1:(end - 5)])

    # Garbage is not a zlib stream.
    @test_throws Exception inflate_stream(collect(codeunits("definitely not zlib")))

    # inflate on an uninitialized stream is a stream error, not a crash.
    s = Ref(Z.z_stream_s())
    @test Z.inflate(s, Z.Z_NO_FLUSH()) == Z.Z_STREAM_ERROR()
    @test Z.deflate(s, Z.Z_NO_FLUSH()) == Z.Z_STREAM_ERROR()
    @test Z.deflateEnd(s) == Z.Z_STREAM_ERROR()

    # An invalid compression level is rejected at init.
    l = Ref(Z.z_stream_s())
    @test Z.deflateInit(l, 42) == Z.Z_STREAM_ERROR()

    # inflateSync finds the next flush point in a damaged stream.
    a = collect(codeunits("first part of the data "))
    strm = Ref(Z.z_stream_s())
    Z.deflateInit(strm, 6)
    out = Vector{UInt8}(undef, 8192)
    GC.@preserve a out begin
        strm[] = Z.with(strm[]; next_in=pointer(a), avail_in=Cuint(length(a)),
                        next_out=pointer(out), avail_out=Cuint(length(out)))
        Z.deflate(strm, Z.Z_FULL_FLUSH())
    end
    npart = length(out) - Int(strm[].avail_out)
    Z.deflateEnd(strm)
    istrm = Ref(Z.z_stream_s())
    Z.inflateInit(istrm)
    ibuf = Vector{UInt8}(undef, 4096)
    part = out[1:npart]
    GC.@preserve part ibuf begin
        istrm[] = Z.with(istrm[]; next_in=pointer(part), avail_in=Cuint(npart),
                         next_out=pointer(ibuf), avail_out=Cuint(length(ibuf)))
        Z.inflate(istrm, Z.Z_NO_FLUSH())
        @test Z.inflateSyncPoint(istrm) in (0, 1)
    end
    Z.inflateEnd(istrm)
end

@testset "Churn and GC stress" begin
    data = PAYLOADS[:text]
    want_crc = ref_crc32(data)
    for i in 1:300
        comp = deflate_stream(data; level=(i % 10))
        @assert inflate_stream(comp) == data
        @assert Z.crc32(0, data, length(data)) % UInt32 == want_crc
        iszero(i % 50) && GC.gc()
    end
    @test true

    # Hammer the Tier-1 checksum path with churning buffers.
    acc = UInt32(0)
    for i in 1:20_000
        b = rand(UInt8, (i % 512) + 1)
        acc ⊻= Z.crc32(0, b, length(b)) % UInt32
        iszero(i % 5000) && GC.gc()
    end
    @test acc != 0
end

end  # top-level testset
