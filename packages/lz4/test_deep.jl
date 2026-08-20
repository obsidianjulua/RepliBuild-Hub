#!/usr/bin/env julia
# LZ4 Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
#   - block API round-trips (default / fast / HC) over a payload spread
#   - compressBound vs the LZ4_COMPRESSBOUND macro shim — the shim is the
#     package's canary for header resolution (lz4 keeps its headers in lib/,
#     and a bare "lz4.h" resolves to the system liblz4 instead)
#   - compress_destSize partial compression, and its exact accounting
#   - the streaming block API with a dictionary/ring buffer, both plain and HC
#   - the LZ4 FRAME API: one-shot frames, streaming frames, frame info,
#     content size, content checksum, block-independence modes, dictionaries
#   - safety: decompress_safe must refuse malformed input rather than overrun
#   - Tier-1 liveness and churn under GC pressure
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/lz4/test_deep.jl

using Test
using InteractiveUtils: code_typed
using Random: Xoshiro

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Lz4.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const L = Lz4

const TEXT = repeat("lz4 is a very fast compressor. ", 700)
const PAYLOADS = Dict(
    :tiny    => collect(codeunits("hello lz4")),
    :text    => collect(codeunits(TEXT)),
    :zeros   => zeros(UInt8, 60_000),
    :random  => rand(Xoshiro(0x1274), UInt8, 40_000),
    :binary  => UInt8[UInt8(i % 251) for i in 0:79_999],
)

"Block-compress with `f`, then decompress_safe back, asserting the round trip."
function block_roundtrip(data::Vector{UInt8}, f)
    cap = L.LZ4_compressBound(length(data))
    @assert cap > 0
    dst = Vector{UInt8}(undef, cap)
    n = f(data, dst, length(data), cap)
    @assert n > 0 "compression failed: $n"
    back = Vector{UInt8}(undef, length(data))
    m = L.LZ4_decompress_safe(dst, back, n, length(back))
    @assert m == length(data) "decompress returned $m, want $(length(data))"
    return (comp = dst[1:n], out = back)
end

@testset "LZ4 Deep Tests" begin

@testset "Library identity" begin
    # 1.10.0 → 1*100*100 + 10*100 + 0
    @test L.LZ4_versionNumber() == 11000
    @test L.LZ4_versionString() == "1.10.0"
    @test L.LZ4F_getVersion() == 100

    # LZ4_COMPRESSBOUND is a pure arithmetic macro; it must agree exactly with
    # the real function. Disagreement means the shim compiled against a
    # DIFFERENT lz4.h — which is precisely what happened before the headers
    # were referenced as lib/lz4.h (system liblz4 lives at /usr/include/lz4.h).
    for n in (0, 1, 2, 100, 65535, 1 << 20)
        @test L.LZ4_COMPRESSBOUND(n) == L.LZ4_compressBound(n)
    end
    @test L.LZ4_compressBound(0) > 0
    @test L.LZ4_DECODER_RING_BUFFER_SIZE(65536) == L.LZ4_decoderRingBufferSize(65536)

    @test L.LZ4F_compressionLevel_max() >= 12
end

@testset "Tier-1 slicing is live" begin
    @test !isempty(L.TIER1_FUNCTIONS)
    slices_dir = joinpath(PKG_DIR, "julia", "slices")
    @test isdir(slices_dir)
    lls = filter(f -> endswith(f, ".ll"), readdir(slices_dir))
    @test length(lls) == length(L.TIER1_FUNCTIONS)
    @test "LZ4_compressBound" in L.TIER1_FUNCTIONS
    @test L.dispatch_tier(:LZ4_compressBound) === :tier1
    @test L.dispatch_tier(:LZ4_versionNumber) === :tier1
end

@testset "Block API round-trips" begin
    for (name, data) in PAYLOADS
        r = block_roundtrip(data, (s, d, sn, dc) -> L.LZ4_compress_default(s, d, sn, dc))
        @test r.out == data

        # compress_fast with several acceleration factors.
        for accel in (1, 4, 64)
            rf = block_roundtrip(data,
                (s, d, sn, dc) -> L.LZ4_compress_fast(s, d, sn, dc, accel))
            @test rf.out == data
        end

        # High-compression mode at both ends of the level range.
        for lvl in (1, 9, 12)
            rh = block_roundtrip(data,
                (s, d, sn, dc) -> L.LZ4_compress_HC(s, d, sn, dc, lvl))
            @test rh.out == data
        end
    end

    # Compressible data must actually shrink; random data must not blow past
    # the documented bound.
    text = PAYLOADS[:text]
    ct = block_roundtrip(text, (s, d, sn, dc) -> L.LZ4_compress_default(s, d, sn, dc))
    @test length(ct.comp) < length(text) ÷ 4

    rnd = PAYLOADS[:random]
    cr = block_roundtrip(rnd, (s, d, sn, dc) -> L.LZ4_compress_default(s, d, sn, dc))
    @test length(cr.comp) <= L.LZ4_compressBound(length(rnd))

    # HC should beat default on compressible input.
    ch = block_roundtrip(text, (s, d, sn, dc) -> L.LZ4_compress_HC(s, d, sn, dc, 12))
    @test length(ch.comp) <= length(ct.comp)

    # Higher acceleration should not produce a smaller output than accel=1.
    c1 = block_roundtrip(text, (s, d, sn, dc) -> L.LZ4_compress_fast(s, d, sn, dc, 1))
    c64 = block_roundtrip(text, (s, d, sn, dc) -> L.LZ4_compress_fast(s, d, sn, dc, 64))
    @test length(c64.comp) >= length(c1.comp)
end

@testset "compress_destSize accounting" begin
    # destSize mode fills a fixed output budget and reports how much INPUT it
    # consumed — the src size is an in/out parameter.
    data = PAYLOADS[:text]
    for budget in (64, 512, 4096)
        srcsize = Ref{Cint}(length(data))
        dst = Vector{UInt8}(undef, budget)
        n = L.LZ4_compress_destSize(data, dst, srcsize, budget)
        @test n > 0
        @test n <= budget
        @test 0 < Int(srcsize[]) <= length(data)

        # Exactly the reported prefix must come back out.
        back = Vector{UInt8}(undef, Int(srcsize[]))
        m = L.LZ4_decompress_safe(dst, back, n, length(back))
        @test m == Int(srcsize[])
        @test back == data[1:Int(srcsize[])]
    end
end

@testset "Streaming block API with a shared dictionary" begin
    # The streaming API compresses successive blocks against the previous
    # ones, so decoding requires the same history — this is where a wrapper
    # that mishandles the stream pointer shows up immediately.
    stream = L.LZ4_createStream()
    @test stream != C_NULL
    decode = L.LZ4_createStreamDecode()
    @test decode != C_NULL

    blocks = [collect(codeunits("block $(i): " * TEXT[1:500])) for i in 1:8]
    comps = Vector{Vector{UInt8}}()

    # Keep every source block alive: LZ4 streaming references earlier input.
    GC.@preserve blocks begin
        for b in blocks
            cap = L.LZ4_compressBound(length(b))
            dst = Vector{UInt8}(undef, cap)
            n = L.LZ4_compress_fast_continue(stream, b, dst, length(b), cap, 1)
            @test n > 0
            push!(comps, dst[1:n])
        end
    end

    # Decode with a contiguous history buffer.
    history = UInt8[]
    for (i, c) in enumerate(comps)
        want = blocks[i]
        out = Vector{UInt8}(undef, length(want))
        # Re-seed the decoder with everything decoded so far.
        GC.@preserve history begin
            if !isempty(history)
                @test L.LZ4_setStreamDecode(decode, history, length(history)) == 1
            else
                @test L.LZ4_setStreamDecode(decode, C_NULL, 0) == 1
            end
        end
        m = L.LZ4_decompress_safe_continue(decode, c, out, length(c), length(out))
        @test m == length(want)
        @test out == want
        append!(history, want)
    end

    @test L.LZ4_freeStream(stream) == 0
    @test L.LZ4_freeStreamDecode(decode) == 0

    # HC streaming over the same blocks.
    hc = L.LZ4_createStreamHC()
    @test hc != C_NULL
    L.LZ4_resetStreamHC_fast(hc, 9)
    hcomps = Vector{Vector{UInt8}}()
    GC.@preserve blocks begin
        for b in blocks
            cap = L.LZ4_compressBound(length(b))
            dst = Vector{UInt8}(undef, cap)
            n = L.LZ4_compress_HC_continue(hc, b, dst, length(b), cap)
            @test n > 0
            push!(hcomps, dst[1:n])
        end
    end
    hist = UInt8[]
    dec2 = L.LZ4_createStreamDecode()
    for (i, c) in enumerate(hcomps)
        want = blocks[i]
        out = Vector{UInt8}(undef, length(want))
        GC.@preserve hist begin
            isempty(hist) ? L.LZ4_setStreamDecode(dec2, C_NULL, 0) :
                            L.LZ4_setStreamDecode(dec2, hist, length(hist))
        end
        @test L.LZ4_decompress_safe_continue(dec2, c, out, length(c), length(out)) == length(want)
        @test out == want
        append!(hist, want)
    end
    L.LZ4_freeStreamDecode(dec2)
    @test L.LZ4_freeStreamHC(hc) == 0
end

@testset "External dictionary (usingDict)" begin
    dict = collect(codeunits(TEXT[1:4096]))
    data = collect(codeunits(TEXT[2000:8000]))

    stream = L.LZ4_createStream()
    GC.@preserve dict data begin
        @test L.LZ4_loadDict(stream, dict, length(dict)) > 0
        cap = L.LZ4_compressBound(length(data))
        dst = Vector{UInt8}(undef, cap)
        n = L.LZ4_compress_fast_continue(stream, data, dst, length(data), cap, 1)
        @test n > 0

        # Decoding needs the same dictionary.
        back = Vector{UInt8}(undef, length(data))
        m = L.LZ4_decompress_safe_usingDict(dst, back, n, length(back), dict, length(dict))
        @test m == length(data)
        @test back == data

        # Without it, the result must not silently be the right bytes.
        bad = Vector{UInt8}(undef, length(data))
        m2 = L.LZ4_decompress_safe_usingDict(dst, bad, n, length(bad), C_NULL, 0)
        @test m2 < 0 || bad != data
    end
    L.LZ4_freeStream(stream)
end

@testset "Frame API — one-shot" begin
    for (name, data) in PAYLOADS
        bound = L.LZ4F_compressFrameBound(length(data), C_NULL)
        @test bound > 0
        dst = Vector{UInt8}(undef, Int(bound))
        n = L.LZ4F_compressFrame(dst, Int(bound), data, length(data), C_NULL)
        @test L.LZ4F_isError(n) == 0
        frame = dst[1:Int(n)]

        # LZ4 frame magic.
        @test frame[1:4] == UInt8[0x04, 0x22, 0x4d, 0x18]

        # Decompress through a context.
        dctx = Ref{Ptr{L.LZ4F_dctx_s}}(C_NULL)
        @test L.LZ4F_isError(L.LZ4F_createDecompressionContext(dctx, L.LZ4F_getVersion())) == 0
        out = Vector{UInt8}(undef, max(length(data), 1))
        dstSize = Ref{Csize_t}(length(out))
        srcSize = Ref{Csize_t}(length(frame))
        rc = L.LZ4F_decompress(dctx[], out, dstSize, frame, srcSize, C_NULL)
        @test L.LZ4F_isError(rc) == 0
        @test rc == 0                       # 0 ⇒ frame fully consumed
        @test Int(dstSize[]) == length(data)
        @test out[1:length(data)] == data
        L.LZ4F_freeDecompressionContext(dctx[])
    end
end

@testset "Frame API — preferences, header, content size and checksum" begin
    data = PAYLOADS[:text]

    prefs = Ref(L.LZ4F_preferences_t())
    fi = L.LZ4F_frameInfo_t()
    fi = L.with(fi; blockSizeID = L.LZ4F_max256KB,
                    blockMode = L.LZ4F_blockIndependent,
                    contentChecksumFlag = L.LZ4F_contentChecksumEnabled,
                    contentSize = Culonglong(length(data)))
    prefs[] = L.with(prefs[]; frameInfo = fi, compressionLevel = Cint(9))

    bound = L.LZ4F_compressFrameBound(length(data), prefs)
    dst = Vector{UInt8}(undef, Int(bound))
    n = L.LZ4F_compressFrame(dst, Int(bound), data, length(data), prefs)
    @test L.LZ4F_isError(n) == 0
    frame = dst[1:Int(n)]

    # The declared header size must match what the parser wants.
    hs = L.LZ4F_headerSize(frame, length(frame))
    @test L.LZ4F_isError(hs) == 0
    @test 7 <= Int(hs) <= 19

    dctx = Ref{Ptr{L.LZ4F_dctx_s}}(C_NULL)
    L.LZ4F_createDecompressionContext(dctx, L.LZ4F_getVersion())
    info = Ref(L.LZ4F_frameInfo_t())
    srcSize = Ref{Csize_t}(length(frame))
    rc = L.LZ4F_getFrameInfo(dctx[], info, frame, srcSize)
    @test L.LZ4F_isError(rc) == 0
    # NOT max256KB as requested: LZ4F_compressFrame runs the requested ID
    # through LZ4F_optimalBSID(), which drops to the smallest block that still
    # holds the whole input. This payload is ~21 KB, so it lands on max64KB.
    @test info[].blockSizeID == L.LZ4F_max64KB
    @test info[].blockMode == L.LZ4F_blockIndependent
    @test info[].contentChecksumFlag == L.LZ4F_contentChecksumEnabled
    @test Int(info[].contentSize) == length(data)      # size travelled in the header

    # Decompress the remainder after the header we just consumed.
    consumed = Int(srcSize[])
    out = Vector{UInt8}(undef, length(data))
    dstSize = Ref{Csize_t}(length(out))
    rest = Ref{Csize_t}(length(frame) - consumed)
    GC.@preserve frame out begin
        rc2 = L.LZ4F_decompress(dctx[], out, dstSize,
                                pointer(frame) + consumed, rest, C_NULL)
        @test L.LZ4F_isError(rc2) == 0
    end
    @test Int(dstSize[]) == length(data)
    @test out == data
    L.LZ4F_freeDecompressionContext(dctx[])

    # A corrupted payload must be caught by the content checksum.
    bad = copy(frame)
    bad[div(end, 2)] ⊻= 0xff
    d2 = Ref{Ptr{L.LZ4F_dctx_s}}(C_NULL)
    L.LZ4F_createDecompressionContext(d2, L.LZ4F_getVersion())
    o2 = Vector{UInt8}(undef, length(data) + 1024)
    ds2 = Ref{Csize_t}(length(o2))
    ss2 = Ref{Csize_t}(length(bad))
    r2 = L.LZ4F_decompress(d2[], o2, ds2, bad, ss2, C_NULL)
    @test L.LZ4F_isError(r2) != 0 || o2[1:length(data)] != data
    L.LZ4F_freeDecompressionContext(d2[])

    # ...and with an input too big for 64 KB the requested ID does stick,
    # which is the other half of the optimalBSID rule.
    big = PAYLOADS[:binary]                      # 80 000 bytes > 64 KiB
    @test length(big) > 65536
    pbig = Ref(L.LZ4F_preferences_t())
    pbig[] = L.with(pbig[]; frameInfo = L.with(L.LZ4F_frameInfo_t();
                                               blockSizeID = L.LZ4F_max256KB))
    bb = L.LZ4F_compressFrameBound(length(big), pbig)
    dbig = Vector{UInt8}(undef, Int(bb))
    nbig = L.LZ4F_compressFrame(dbig, Int(bb), big, length(big), pbig)
    @test L.LZ4F_isError(nbig) == 0
    dcb = Ref{Ptr{L.LZ4F_dctx_s}}(C_NULL)
    L.LZ4F_createDecompressionContext(dcb, L.LZ4F_getVersion())
    ib = Ref(L.LZ4F_frameInfo_t())
    sb = Ref{Csize_t}(Int(nbig))
    @test L.LZ4F_isError(L.LZ4F_getFrameInfo(dcb[], ib, dbig, sb)) == 0
    @test ib[].blockSizeID == L.LZ4F_max256KB
    L.LZ4F_freeDecompressionContext(dcb[])

    # Every block size ID round-trips.
    for bs in (L.LZ4F_max64KB, L.LZ4F_max256KB, L.LZ4F_max1MB, L.LZ4F_max4MB)
        @test L.LZ4F_getBlockSize(bs) > 0
        p = Ref(L.LZ4F_preferences_t())
        p[] = L.with(p[]; frameInfo = L.with(L.LZ4F_frameInfo_t(); blockSizeID = bs))
        b = L.LZ4F_compressFrameBound(length(data), p)
        d = Vector{UInt8}(undef, Int(b))
        m = L.LZ4F_compressFrame(d, Int(b), data, length(data), p)
        @test L.LZ4F_isError(m) == 0

        dc = Ref{Ptr{L.LZ4F_dctx_s}}(C_NULL)
        L.LZ4F_createDecompressionContext(dc, L.LZ4F_getVersion())
        o = Vector{UInt8}(undef, length(data))
        os = Ref{Csize_t}(length(o)); is = Ref{Csize_t}(Int(m))
        @test L.LZ4F_isError(L.LZ4F_decompress(dc[], o, os, d, is, C_NULL)) == 0
        @test o == data
        L.LZ4F_freeDecompressionContext(dc[])
    end
end

@testset "Frame API — streaming compression" begin
    data = PAYLOADS[:binary]
    cctx = Ref{Ptr{L.LZ4F_cctx_s}}(C_NULL)
    @test L.LZ4F_isError(L.LZ4F_createCompressionContext(cctx, L.LZ4F_getVersion())) == 0

    prefs = Ref(L.LZ4F_preferences_t())
    prefs[] = L.with(prefs[]; compressionLevel = Cint(3),
                     frameInfo = L.with(L.LZ4F_frameInfo_t();
                                        contentChecksumFlag = L.LZ4F_contentChecksumEnabled))

    chunk = 8192
    outbuf = Vector{UInt8}(undef, Int(L.LZ4F_compressBound(chunk, prefs)) + 1024)
    frame = UInt8[]

    n = L.LZ4F_compressBegin(cctx[], outbuf, length(outbuf), prefs)
    @test L.LZ4F_isError(n) == 0
    append!(frame, outbuf[1:Int(n)])

    off = 0
    while off < length(data)
        m = min(chunk, length(data) - off)
        part = data[(off + 1):(off + m)]
        k = L.LZ4F_compressUpdate(cctx[], outbuf, length(outbuf), part, m, C_NULL)
        @test L.LZ4F_isError(k) == 0
        Int(k) > 0 && append!(frame, outbuf[1:Int(k)])
        off += m
    end

    # An explicit flush must be legal mid-stream.
    fl = L.LZ4F_flush(cctx[], outbuf, length(outbuf), C_NULL)
    @test L.LZ4F_isError(fl) == 0
    Int(fl) > 0 && append!(frame, outbuf[1:Int(fl)])

    e = L.LZ4F_compressEnd(cctx[], outbuf, length(outbuf), C_NULL)
    @test L.LZ4F_isError(e) == 0
    append!(frame, outbuf[1:Int(e)])
    @test L.LZ4F_isError(L.LZ4F_freeCompressionContext(cctx[])) == 0

    # Decode the assembled frame in small output windows.
    dctx = Ref{Ptr{L.LZ4F_dctx_s}}(C_NULL)
    L.LZ4F_createDecompressionContext(dctx, L.LZ4F_getVersion())
    out = UInt8[]
    small = Vector{UInt8}(undef, 1000)
    inpos = 0
    while inpos < length(frame)
        dstSize = Ref{Csize_t}(length(small))
        srcSize = Ref{Csize_t}(length(frame) - inpos)
        GC.@preserve frame small begin
            rc = L.LZ4F_decompress(dctx[], small, dstSize,
                                   pointer(frame) + inpos, srcSize, C_NULL)
            @test L.LZ4F_isError(rc) == 0
        end
        append!(out, small[1:Int(dstSize[])])
        inpos += Int(srcSize[])
        Int(srcSize[]) == 0 && Int(dstSize[]) == 0 && break
    end
    @test out == data
    L.LZ4F_freeDecompressionContext(dctx[])

    # resetDecompressionContext makes a context reusable after an abort.
    d = Ref{Ptr{L.LZ4F_dctx_s}}(C_NULL)
    L.LZ4F_createDecompressionContext(d, L.LZ4F_getVersion())
    junk = rand(Xoshiro(7), UInt8, 64)
    o = Vector{UInt8}(undef, 256)
    os = Ref{Csize_t}(length(o)); is = Ref{Csize_t}(length(junk))
    @test L.LZ4F_isError(L.LZ4F_decompress(d[], o, os, junk, is, C_NULL)) != 0
    L.LZ4F_resetDecompressionContext(d[])
    # After the reset a valid frame decodes normally again.
    b = L.LZ4F_compressFrameBound(length(data), C_NULL)
    fdst = Vector{UInt8}(undef, Int(b))
    fn = L.LZ4F_compressFrame(fdst, Int(b), data, length(data), C_NULL)
    o2 = Vector{UInt8}(undef, length(data))
    os2 = Ref{Csize_t}(length(o2)); is2 = Ref{Csize_t}(Int(fn))
    @test L.LZ4F_isError(L.LZ4F_decompress(d[], o2, os2, fdst, is2, C_NULL)) == 0
    @test o2 == data
    L.LZ4F_freeDecompressionContext(d[])
end

@testset "Error handling and bounds safety" begin
    data = PAYLOADS[:text]
    cap = L.LZ4_compressBound(length(data))
    dst = Vector{UInt8}(undef, cap)
    n = L.LZ4_compress_default(data, dst, length(data), cap)
    comp = dst[1:n]

    # An output buffer that is too small returns 0, not a partial write.
    small = Vector{UInt8}(undef, 16)
    @test L.LZ4_compress_default(data, small, length(data), 16) == 0

    # decompress_safe must refuse to write past maxDecompressedSize.
    tight = Vector{UInt8}(undef, length(data) - 1)
    @test L.LZ4_decompress_safe(comp, tight, length(comp), length(tight)) < 0

    # Corrupt input is rejected rather than trusted.
    for pos in (1, div(length(comp), 3), length(comp))
        bad = copy(comp)
        bad[pos] ⊻= 0xff
        out = Vector{UInt8}(undef, length(data))
        r = L.LZ4_decompress_safe(bad, out, length(bad), length(out))
        @test r < 0 || out != data
    end

    # Truncated input is an error, never a short success.
    @test L.LZ4_decompress_safe(comp, Vector{UInt8}(undef, length(data)),
                                length(comp) ÷ 2, length(data)) < 0

    # Pure garbage that is not LZ4 at all.
    junk = rand(Xoshiro(3), UInt8, 256)
    out = Vector{UInt8}(undef, 4096)
    @test L.LZ4_decompress_safe(junk, out, length(junk), length(out)) < 0

    # Frame errors carry readable names.
    @test L.LZ4F_isError(L.LZ4F_compressFrame(Vector{UInt8}(undef, 4), 4,
                                              data, length(data), C_NULL)) != 0
    code = L.LZ4F_compressFrame(Vector{UInt8}(undef, 4), 4, data, length(data), C_NULL)
    name = L.LZ4F_getErrorName(code)
    @test name !== nothing && !isempty(name)
    @test L.LZ4F_getErrorCode(code) != L.LZ4F_OK_NoError
end

@testset "Churn and GC stress" begin
    data = PAYLOADS[:text]
    for i in 1:400
        r = block_roundtrip(data, (s, d, sn, dc) -> L.LZ4_compress_fast(s, d, sn, dc, (i % 8) + 1))
        @assert r.out == data
        iszero(i % 100) && GC.gc()
    end
    @test true

    # Frame round-trips in a loop, creating and freeing contexts each time.
    small = PAYLOADS[:tiny]
    for i in 1:500
        b = L.LZ4F_compressFrameBound(length(small), C_NULL)
        d = Vector{UInt8}(undef, Int(b))
        m = L.LZ4F_compressFrame(d, Int(b), small, length(small), C_NULL)
        @assert L.LZ4F_isError(m) == 0
        dc = Ref{Ptr{L.LZ4F_dctx_s}}(C_NULL)
        L.LZ4F_createDecompressionContext(dc, L.LZ4F_getVersion())
        o = Vector{UInt8}(undef, 64)
        os = Ref{Csize_t}(length(o)); is = Ref{Csize_t}(Int(m))
        L.LZ4F_decompress(dc[], o, os, d, is, C_NULL)
        @assert o[1:length(small)] == small
        L.LZ4F_freeDecompressionContext(dc[])
        iszero(i % 100) && GC.gc()
    end
    @test true

    # Tier-1 hammer.
    acc = 0
    for i in 1:20_000
        acc += L.LZ4_compressBound(i)
    end
    @test acc > 0
end

end  # top-level testset
