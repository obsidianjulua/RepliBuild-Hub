#!/usr/bin/env julia
# zstd Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
#   - library identity + the ZSTD_COMPRESSBOUND macro shim (the canary for
#     header resolution: zstd keeps headers in lib/, and a bare "zstd.h"
#     resolves to the system libzstd instead)
#   - simple API round-trips across payloads and levels
#   - frame helpers: content size, compressed-frame size, error names/codes
#   - explicit CCtx/DCtx reuse
#   - streaming through ZSTD_inBuffer_s / ZSTD_outBuffer_s — those are the
#     header-only aggregates that need -fstandalone-debug; empty structs
#     would fail here, not at wrap time
#   - ZSTD_bounds by-value return (16-byte SysV INTEGER class)
#   - raw-prefix dictionary compress/decompress
#   - safety: garbage input and an undersized dest must error, not overrun
#   - Tier 1 is OFF (quarantined); this package is pure ccall
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/zstd/test_deep.jl

using Test
using Random: Xoshiro

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Zstd.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const Z = Zstd

const TEXT = repeat("zstd is a fast lossless compressor. ", 400)
const PAYLOADS = Dict(
    :tiny   => collect(codeunits("hi")),
    :text   => collect(codeunits(TEXT)),
    :zeros  => zeros(UInt8, 80_000),
    :random => rand(Xoshiro(0x5a5a), UInt8, 40_000),
)

function oneshot(data::Vector{UInt8}; level::Integer=3)
    cap = Int(Z.ZSTD_compressBound(length(data)))
    @assert cap > 0
    dst = Vector{UInt8}(undef, cap)
    n = Z.ZSTD_compress(dst, cap, data, length(data), level)
    @assert Z.ZSTD_isError(n) == 0 "compress failed: $(Z.ZSTD_getErrorName(n))"
    back = Vector{UInt8}(undef, length(data))
    m = Z.ZSTD_decompress(back, length(back), dst, n)
    @assert Z.ZSTD_isError(m) == 0 "decompress failed: $(Z.ZSTD_getErrorName(m))"
    return (comp = dst[1:Int(n)], out = back)
end

@testset "zstd Deep Tests" begin

@testset "Library identity" begin
    @test Z.ZSTD_versionNumber() == 10507
    @test Z.ZSTD_versionString() == "1.5.7"
    @test Z.ZSTD_VERSION_MAJOR() == 1
    @test Z.ZSTD_VERSION_MINOR() == 5
    @test Z.ZSTD_VERSION_RELEASE() == 7
    @test Z.ZSTD_VERSION_NUMBER() == 10507
    @test Z.ZSTD_VERSION_STRING() == "1.5.7"
    @test Z.ZSTD_defaultCLevel() == 3
    @test Z.ZSTD_CLEVEL_DEFAULT() == 3
    @test Z.ZSTD_maxCLevel() == 22
    @test Z.ZSTD_minCLevel() < 0
    @test Z.ZSTD_BLOCKSIZE_MAX() == 131072
    @test Z.ZSTD_MAGICNUMBER() == 0xFD2FB528
    @test Z.ZSTD_CONTENTSIZE_UNKNOWN() == typemax(UInt64)
    @test Z.ZSTD_CONTENTSIZE_ERROR() == typemax(UInt64) - 1

    # Macro shim vs real function. Disagreement means the shim compiled
    # against a DIFFERENT zstd.h — which is what a bare "zstd.h" does on
    # a box with system libzstd.
    for n in (0, 1, 100, 65535, 1 << 20)
        @test Z.ZSTD_COMPRESSBOUND(n) == Z.ZSTD_compressBound(n)
    end

    # The remaining four [wrap.macros] entries. Declared-but-unasserted is the
    # same shape as the [ingest] extra_link_libs bug: the value round-trips
    # through the parser whether or not it is right, and a shim built against a
    # foreign zstd.h would carry a wrong constant with no other symptom.
    @test Z.ZSTD_MAGIC_DICTIONARY()      == 0xEC30A437
    @test Z.ZSTD_MAGIC_SKIPPABLE_START() == 0x184D2A50
    @test Z.ZSTD_MAGIC_SKIPPABLE_MASK()  == 0xFFFFFFF0
    @test Z.ZSTD_BLOCKSIZELOG_MAX()      == 17

    # Prefer the RELATIONS the header states over the literals, so these keep
    # their teeth across a version bump instead of becoming values to re-pin.
    # zstd.h: #define ZSTD_BLOCKSIZE_MAX (1 << ZSTD_BLOCKSIZELOG_MAX)
    @test Z.ZSTD_BLOCKSIZE_MAX() == 1 << Z.ZSTD_BLOCKSIZELOG_MAX()

    # zstd.h: all 16 values 0x184D2A50..0x184D2A5F begin a skippable frame, so
    # every one of them must reduce to START under MASK. Catches a START/MASK
    # pair that came from two different headers.
    let start = Z.ZSTD_MAGIC_SKIPPABLE_START(), mask = Z.ZSTD_MAGIC_SKIPPABLE_MASK()
        @test all((start + UInt32(i)) & mask == start for i in 0:15)
        @test (start + UInt32(16)) & mask != start
    end
end

@testset "Tier 1 is OFF — pure ccall" begin
    for n in (:TIER1_FUNCTIONS, :TIER1_DECLARES, :_TIER1_KERNEL, :_slice_symbols_resolve)
        @test !isdefined(Z, n)
    end
    @test !isdir(joinpath(PKG_DIR, "julia", "slices"))
    src = read(WRAPPER, String)
    @test !occursin("@generated function _TIER1_", src)
    @test !occursin("const _SLICE_", src)
    @test !occursin("llvmcall", src)
    @test !occursin("code_typed", src)
    @test !occursin(":deferred", src)
    @test !isdefined(Z, :DISPATCH_TIER)
    @test !isdefined(Z, :dispatch_tier)
    @test occursin("Every function in this module dispatches through Tier 3", src)
end

@testset "Layout of the public aggregates" begin
    # Header-only structs the caller fills. Empty here means
    # -fstandalone-debug was dropped.
    @test Z.struct_size(:ZSTD_inBuffer_s) == 24
    @test Z.struct_size(:ZSTD_outBuffer_s) == 24
    @test Z.struct_size(:ZSTD_bounds) == 16
    @test Z.member_offset(:ZSTD_inBuffer_s, :src) == 0
    @test Z.member_offset(:ZSTD_inBuffer_s, :size) == 8
    @test Z.member_offset(:ZSTD_inBuffer_s, :pos) == 16
    @test Z.member_offset(:ZSTD_outBuffer_s, :dst) == 0
    @test Z.member_offset(:ZSTD_outBuffer_s, :size) == 8
    @test Z.member_offset(:ZSTD_outBuffer_s, :pos) == 16
    @test Z.member_offset(:ZSTD_bounds, :error) == 0
    @test Z.member_offset(:ZSTD_bounds, :lowerBound) == 8
    @test Z.member_offset(:ZSTD_bounds, :upperBound) == 12
    @test fieldnames(Z.ZSTD_inBuffer_s) === (:src, :size, :pos)
    @test fieldnames(Z.ZSTD_outBuffer_s) === (:dst, :size, :pos)
end

@testset "Simple API round-trips" begin
    for (name, data) in PAYLOADS, level in (1, 3, 19)
        r = oneshot(data; level=level)
        @test r.out == data
        @test length(r.comp) <= Int(Z.ZSTD_compressBound(length(data)))
    end

    text = PAYLOADS[:text]
    ct = oneshot(text; level=3)
    @test length(ct.comp) < length(text) ÷ 4

    # Higher level must not expand past level-1 on this input.
    c1 = oneshot(text; level=1)
    c19 = oneshot(text; level=19)
    @test length(c19.comp) <= length(c1.comp)

    @test Z.ZSTD_getFrameContentSize(ct.comp, length(ct.comp)) == length(text)
    @test Z.ZSTD_findFrameCompressedSize(ct.comp, length(ct.comp)) == length(ct.comp)
end

@testset "Error paths" begin
    garbage = UInt8[0x01, 0x02, 0x03, 0x04, 0x05]
    out = Vector{UInt8}(undef, 64)
    e = Z.ZSTD_decompress(out, length(out), garbage, length(garbage))
    @test Z.ZSTD_isError(e) != 0
    @test Z.ZSTD_getErrorCode(e) == Z.ZSTD_error_srcSize_wrong
    @test occursin("Src size", Z.ZSTD_getErrorName(e))

    src = PAYLOADS[:text]
    tiny = Vector{UInt8}(undef, 8)
    e2 = Z.ZSTD_compress(tiny, length(tiny), src, length(src), 3)
    @test Z.ZSTD_isError(e2) != 0
    @test occursin("too small", Z.ZSTD_getErrorName(e2))
end

@testset "Explicit context reuse" begin
    src = PAYLOADS[:text]
    cctx = Z.ZSTD_createCCtx()
    dctx = Z.ZSTD_createDCtx()
    @test cctx != C_NULL
    @test dctx != C_NULL
    cap = Int(Z.ZSTD_compressBound(length(src)))
    dst = Vector{UInt8}(undef, cap)
    back = Vector{UInt8}(undef, length(src))
    try
        for level in (1, 5, 12)
            n = Z.ZSTD_compressCCtx(cctx, dst, cap, src, length(src), level)
            @test Z.ZSTD_isError(n) == 0
            m = Z.ZSTD_decompressDCtx(dctx, back, length(back), dst, n)
            @test m == length(src)
            @test back == src
        end
    finally
        Z.ZSTD_freeCCtx(cctx)
        Z.ZSTD_freeDCtx(dctx)
    end
end

@testset "ZSTD_bounds by-value return" begin
    b = Z.ZSTD_cParam_getBounds(Z.ZSTD_c_compressionLevel)
    @test Z.ZSTD_isError(b.error) == 0
    @test b.lowerBound == Z.ZSTD_minCLevel()
    @test b.upperBound == Z.ZSTD_maxCLevel()
end

@testset "Streaming through inBuffer/outBuffer" begin
    src = PAYLOADS[:text]
    cctx = Z.ZSTD_createCCtx()
    dctx = Z.ZSTD_createDCtx()
    dst = Vector{UInt8}(undef, Int(Z.ZSTD_compressBound(length(src))))
    back = Vector{UInt8}(undef, length(src))
    try
        GC.@preserve src dst begin
            inp = Ref(Z.ZSTD_inBuffer_s(Ptr{Cvoid}(pointer(src)), length(src), 0))
            outp = Ref(Z.ZSTD_outBuffer_s(Ptr{Cvoid}(pointer(dst)), length(dst), 0))
            r = Z.ZSTD_compressStream2(cctx, outp, inp, Z.ZSTD_e_end)
            @test Z.ZSTD_isError(r) == 0
            @test r == 0
            @test inp[].pos == length(src)
            @test outp[].pos > 0
            n = Int(outp[].pos)

            inp2 = Ref(Z.ZSTD_inBuffer_s(Ptr{Cvoid}(pointer(dst)), n, 0))
            outp2 = Ref(Z.ZSTD_outBuffer_s(Ptr{Cvoid}(pointer(back)), length(back), 0))
            r2 = Z.ZSTD_decompressStream(dctx, outp2, inp2)
            @test Z.ZSTD_isError(r2) == 0
            @test outp2[].pos == length(src)
            @test back == src
        end

        # Byte-starved: tiny buffers, many round-trips, pos must advance.
        empty!(dst)
        resize!(dst, 0)
        Z.ZSTD_CCtx_reset(cctx, Z.ZSTD_reset_session_and_parameters)
        Z.ZSTD_DCtx_reset(dctx, Z.ZSTD_reset_session_and_parameters)
        compiled = UInt8[]
        inoff = 0
        GC.@preserve src begin
            while inoff < length(src) || true
                chunk = min(97, length(src) - inoff)
                outbuf = Vector{UInt8}(undef, 64)
                GC.@preserve outbuf begin
                    inp = Ref(Z.ZSTD_inBuffer_s(
                        chunk == 0 ? C_NULL : Ptr{Cvoid}(pointer(src) + inoff),
                        chunk, 0))
                    outp = Ref(Z.ZSTD_outBuffer_s(Ptr{Cvoid}(pointer(outbuf)), length(outbuf), 0))
                    endop = inoff + chunk >= length(src) ? Z.ZSTD_e_end : Z.ZSTD_e_continue
                    r = Z.ZSTD_compressStream2(cctx, outp, inp, endop)
                    @test Z.ZSTD_isError(r) == 0
                    inoff += Int(inp[].pos)
                    append!(compiled, view(outbuf, 1:Int(outp[].pos)))
                    endop == Z.ZSTD_e_end && r == 0 && break
                end
            end
        end
        recovered = UInt8[]
        din = 0
        GC.@preserve compiled begin
            while din < length(compiled) || true
                chunk = min(53, length(compiled) - din)
                outbuf = Vector{UInt8}(undef, 80)
                GC.@preserve outbuf begin
                    inp = Ref(Z.ZSTD_inBuffer_s(
                        chunk == 0 ? C_NULL : Ptr{Cvoid}(pointer(compiled) + din),
                        chunk, 0))
                    outp = Ref(Z.ZSTD_outBuffer_s(Ptr{Cvoid}(pointer(outbuf)), length(outbuf), 0))
                    r = Z.ZSTD_decompressStream(dctx, outp, inp)
                    @test Z.ZSTD_isError(r) == 0
                    din += Int(inp[].pos)
                    append!(recovered, view(outbuf, 1:Int(outp[].pos)))
                    r == 0 && din >= length(compiled) && break
                end
            end
        end
        @test recovered == src
    finally
        Z.ZSTD_freeCCtx(cctx)
        Z.ZSTD_freeDCtx(dctx)
    end
end

@testset "Raw-prefix dictionary" begin
    dict = collect(codeunits(TEXT[1:4096]))
    data = collect(codeunits(TEXT[2000:9000]))
    cctx = Z.ZSTD_createCCtx()
    dctx = Z.ZSTD_createDCtx()
    try
        cap = Int(Z.ZSTD_compressBound(length(data)))
        dst = Vector{UInt8}(undef, cap)
        n = Z.ZSTD_compress_usingDict(cctx, dst, cap, data, length(data), dict, length(dict), 3)
        @test Z.ZSTD_isError(n) == 0
        back = Vector{UInt8}(undef, length(data))
        m = Z.ZSTD_decompress_usingDict(dctx, back, length(back), dst, n, dict, length(dict))
        @test m == length(data)
        @test back == data

        # Wrong dictionary must not silently produce the original bytes.
        wrong = collect(codeunits("not the dictionary " ^ 200))
        bad = Vector{UInt8}(undef, length(data))
        m2 = Z.ZSTD_decompress_usingDict(dctx, bad, length(bad), dst, n, wrong, length(wrong))
        @test Z.ZSTD_isError(m2) != 0 || bad != data
    finally
        Z.ZSTD_freeCCtx(cctx)
        Z.ZSTD_freeDCtx(dctx)
    end
end

@testset "GC churn" begin
    src = PAYLOADS[:text]
    for _ in 1:200
        r = oneshot(src; level=1)
        @test r.out == src
        GC.safepoint()
    end
    GC.gc()
    r = oneshot(src; level=3)
    @test r.out == src
end

@testset "Trace surface is present (ZSTD_TRACE not pinned off)" begin
    # Upstream default on ELF: four weak profiler hooks. `-DZSTD_TRACE=0`
    # used to drop them to dodge an icmp-constexpr assemble failure
    # (GENERATOR-icmp-constexpr.md). They are WEAK UNDEFINED — a tracer
    # provides the body — so they do not become Julia wrappers. The
    # surface is: they appear in the .so, and the IR that used to fail
    # assembly still contains the weak-NULL icmp and still linked.
    so = joinpath(PKG_DIR, "julia", "libzstd.so")
    abi = joinpath(PKG_DIR, "build", "zstd_abi.ll")
    @test isfile(so)
    @test isfile(abi)

    nm = read(`nm -D $so`, String)
    for s in ("ZSTD_trace_compress_begin", "ZSTD_trace_compress_end",
              "ZSTD_trace_decompress_begin", "ZSTD_trace_decompress_end")
        @test occursin(s, nm)
        @test !isdefined(Z, Symbol(s))   # not a defined object; not wrapped
    end

    # The check is an icmp against the weak symbol. Older LLVM folded it into a
    # constant expression, `icmp eq (ptr @X, ptr null)`; LLVM 23 emits it as an
    # instruction, `icmp ne ptr @X, null`. Either spelling is the trace gate.
    abi_txt = read(abi, String)
    @test occursin(r"icmp (eq|ne) \(?ptr @ZSTD_trace_compress_end, (ptr )?null", abi_txt)
    @test occursin(r"icmp (eq|ne) \(?ptr @ZSTD_trace_decompress_end, (ptr )?null", abi_txt)
end

end
