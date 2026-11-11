#!/usr/bin/env julia
# libwebp Hub package — deep integration test of a GRAPH package.
#
# Four libraries from upstream's own CMake project, taken from a pinned git
# checkout ([graph] dependency): sharpyuv ← webp ← libwebpmux / webpdemux.
# Assumes the graph is built (builds it on a miss). Proves:
#   - the graph: four libraries in load order, versions read from each .so
#   - type identity across libraries (RepliBuild #80):
#       owner → importer:  Libwebpmux.WebPPicture/WebPConfig ARE Webp's
#       siblings:          Webpdemux.WebPData IS Libwebpmux's (imported from an
#                          earlier library outside its link closure)
#       file-local:        Webp.MemBuffer and Webpdemux.MemBuffer (two .c-file
#                          structs that share a name) stay two types
#   - still images: lossless RGBA encode → info → decode, bit-exact
#   - animation ACROSS the libraries: frames built as Webp.WebPPicture under a
#     Webp.WebPConfig, encoded by libwebpmux, the resulting WebPData handed
#     straight to webpdemux's decoder, every frame bit-exact
#
# WebP's ...Init()/...New() helpers are `static inline` wrappers around the
# exported ...Internal(…, ABI_VERSION) functions, and graph mode does not yet
# apply per-library [wrap.macros]; so the ABI versions are spelled here,
# against the pinned headers.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/libwebp/test_deep.jl

using Test, TOML

const PKG_DIR = @__DIR__
const GRAPH = joinpath(PKG_DIR, "julia", "Libwebp.jl")

if !isfile(GRAPH)
    @info "Graph wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(GRAPH)
const W = Libwebp.Webp
const MX = Libwebp.Libwebpmux
const DX = Libwebp.Webpdemux

# src/webp/{encode,decode,mux,demux}.h at v1.6.0
const WEBP_ENCODER_ABI_VERSION = Cint(0x0210)
const WEBP_MUX_ABI_VERSION     = Cint(0x0109)
const WEBP_DEMUX_ABI_VERSION   = Cint(0x0107)

"Set one field of an isbits struct held in a Ref, in place (after C initialised it)."
function poke!(r::Ref{T}, field::Symbol, v) where {T}
    i = Base.fieldindex(T, field)
    FT = fieldtype(T, i)
    GC.@preserve r unsafe_store!(Ptr{FT}(Base.unsafe_convert(Ptr{T}, r) + fieldoffset(T, i)),
                                 convert(FT, v))
    return r
end

"W×H RGBA, opaque, a pattern that differs per `k`."
rgba_image(Wd, Ht, k) = UInt8[c == 4 ? 0xff : UInt8(mod(x * 13 + y * 7 + c * 50 + k * 60, 256))
                              for c in 1:4, x in 1:Wd, y in 1:Ht]

copy_out(p::Ptr{UInt8}, n) = copy(unsafe_wrap(Vector{UInt8}, p, n))

@testset "libwebp graph" begin

@testset "Graph: four libraries, upstream versions" begin
    m = TOML.parsefile(joinpath(PKG_DIR, "julia", "graph.toml"))
    @test [l["name"] for l in m["libraries"]] == ["sharpyuv", "webp", "libwebpmux", "webpdemux"]
    @test m["dependency"] == "libwebp"
    # (major << 16) | (minor << 8) | revision
    @test W.WebPGetDecoderVersion() == 0x010600
    @test W.WebPGetEncoderVersion() == 0x010600
    @test MX.WebPGetMuxVersion() == 0x010600
    @test DX.WebPGetDemuxVersion() == 0x010600
end

@testset "Type identity across the graph" begin
    @test MX.WebPPicture === W.WebPPicture          # owner → importer
    @test MX.WebPConfig === W.WebPConfig
    @test DX.WebPData === MX.WebPData               # sibling, imported by load order
    @test W.MemBuffer !== DX.MemBuffer              # file-local: two types
    @test sizeof(W.MemBuffer) == 56 && sizeof(DX.MemBuffer) == 40
end

@testset "Still image: lossless RGBA round trip is bit-exact" begin
    Wd, Ht = 40, 24
    img = rgba_image(Wd, Ht, 0)
    out = Ref{Ptr{UInt8}}(C_NULL)
    n = W.WebPEncodeLosslessRGBA(img, Wd, Ht, 4Wd, out)
    @test n > 0
    data = copy_out(out[], n)
    W.WebPFree(out[])
    @test data[1:4] == codeunits("RIFF") && data[9:12] == codeunits("WEBP")

    w, h = Ref{Cint}(0), Ref{Cint}(0)
    @test W.WebPGetInfo(data, length(data), w, h) == 1
    @test (w[], h[]) == (Wd, Ht)
    p = W.WebPDecodeRGBA(data, length(data), w, h)
    @test p != C_NULL
    @test copy_out(p, 4Wd * Ht) == vec(img)
    W.WebPFree(p)

    @test W.WebPGetInfo(rand(UInt8, 64), 64, w, h) == 0     # not WebP: refused
end

@testset "Animation: encoded by libwebpmux, decoded by webpdemux" begin
    Wd, Ht, N = 16, 12, 3
    frames = [rgba_image(Wd, Ht, k) for k in 1:N]

    # ── encode (libwebpmux), frames are webp's WebPPicture / WebPConfig ──
    eopts = Ref{MX.WebPAnimEncoderOptions}()
    @test MX.WebPAnimEncoderOptionsInitInternal(eopts, WEBP_MUX_ABI_VERSION) == 1
    enc = MX.WebPAnimEncoderNewInternal(Wd, Ht, eopts, WEBP_MUX_ABI_VERSION)
    @test enc != C_NULL

    cfg = Ref{W.WebPConfig}()
    @test W.WebPConfigInitInternal(cfg, W.WEBP_PRESET_DEFAULT, 75f0, WEBP_ENCODER_ABI_VERSION) == 1
    poke!(cfg, :lossless, 1)
    poke!(cfg, :exact, 1)

    for (k, img) in enumerate(frames)
        pic = Ref{W.WebPPicture}()
        @test W.WebPPictureInitInternal(pic, WEBP_ENCODER_ABI_VERSION) == 1
        poke!(pic, :use_argb, 1); poke!(pic, :width, Wd); poke!(pic, :height, Ht)
        @test W.WebPPictureImportRGBA(pic, img, 4Wd) == 1
        @test MX.WebPAnimEncoderAdd(enc, pic, 100 * (k - 1), cfg) == 1   # webp's types into mux
        W.WebPPictureFree(pic)
    end
    @test MX.WebPAnimEncoderAdd(enc, C_NULL, 100N, C_NULL) == 1           # end of stream
    anim = Ref(MX.WebPData(C_NULL, 0))
    @test MX.WebPAnimEncoderAssemble(enc, anim) == 1
    MX.WebPAnimEncoderDelete(enc)
    @test anim[].size > 0

    # ── decode (webpdemux), from the very WebPData libwebpmux filled ──
    dopts = Ref{DX.WebPAnimDecoderOptions}()
    @test DX.WebPAnimDecoderOptionsInitInternal(dopts, WEBP_DEMUX_ABI_VERSION) == 1
    dec = DX.WebPAnimDecoderNewInternal(anim, dopts, WEBP_DEMUX_ABI_VERSION)
    @test dec != C_NULL
    info = Ref{DX.WebPAnimInfo}()
    @test DX.WebPAnimDecoderGetInfo(dec, info) == 1
    @test (info[].canvas_width, info[].canvas_height, info[].frame_count) == (Wd, Ht, N)

    buf, ts = Ref{Ptr{UInt8}}(C_NULL), Ref{Cint}(0)
    stamps = Int[]
    for k in 1:N
        @test DX.WebPAnimDecoderHasMoreFrames(dec) == 1
        @test DX.WebPAnimDecoderGetNext(dec, buf, ts) == 1
        push!(stamps, ts[])
        @test copy_out(buf[], 4Wd * Ht) == vec(frames[k])      # lossless: exact canvas
    end
    @test DX.WebPAnimDecoderHasMoreFrames(dec) == 0
    @test stamps == [100, 200, 300]                             # each frame's end time
    DX.WebPAnimDecoderDelete(dec)
    W.WebPFree(anim[].bytes)                                    # WebPDataClear
end

end
