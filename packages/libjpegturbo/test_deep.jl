#!/usr/bin/env julia
# libjpegturbo Hub package — deep integration test
#
# Assumes the wrapper is already built (builds it on a miss). Proves the
# wrapper *drives* libjpeg-turbo, and that the build is the library — every
# precision upstream compiles via src/wrapper/*-{8,12,16}.c is really there:
#   - version value-macro pinned against the tag (shim-header canary)
#   - 8-bit lossy round trip: a four-quadrant RGB image survives within JPEG
#     tolerance; header width/height/subsampling read back
#   - 12-bit lossy round trip (tj3Compress12/Decompress12 → the -12 wrapper TUs)
#   - 16-bit LOSSLESS round trip, bit-exact (the -16 wrapper TUs + jclossls)
#   - lossless transform: tj3Transform ROT90 swaps dimensions and moves the
#     quadrants where a clockwise rotation puts them
#   - image I/O: tj3SaveImage8/tj3LoadImage8 through PNG (folded spng + zlib)
#     and BMP, bit-exact
#   - error path: garbage input fails with an error string, no crash
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/libjpegturbo/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Libjpegturbo.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)
const J = Libjpegturbo

# turbojpeg.h enum values (the tj3Set/tj3Get `param` is a plain int, so these
# enums need not reach DWARF; spelled here against the pinned header).
const TJINIT_COMPRESS, TJINIT_DECOMPRESS, TJINIT_TRANSFORM = Cint(0), Cint(1), Cint(2)
const TJPARAM_QUALITY, TJPARAM_SUBSAMP = Cint(3), Cint(4)
const TJPARAM_JPEGWIDTH, TJPARAM_JPEGHEIGHT, TJPARAM_PRECISION = Cint(5), Cint(6), Cint(7)
const TJPARAM_LOSSLESS = Cint(15)
const TJSAMP_444 = Cint(0)
const TJPF_RGB, TJPF_GRAY = Cint(0), Cint(6)
const TJXOP_ROT90 = Cint(5)

# ── helpers ──────────────────────────────────────────────────────────────────

handle(kind) = (h = J.tj3Init(kind); @assert h != C_NULL "tj3Init failed"; h)

"Copy a library-allocated JPEG buffer into Julia memory and tj3Free it."
function take!(buf::Ref{Ptr{UInt8}}, size::Ref{Csize_t})
    out = copy(unsafe_wrap(Vector{UInt8}, buf[], Int(size[])))
    J.tj3Free(buf[])
    return out
end

"W×H RGB, quadrants: TL red, TR green, BL blue, BR white."
function quadrants(W, H)
    img = zeros(UInt8, 3, W, H)
    for y in 1:H, x in 1:W
        c = x <= W ÷ 2 ? (y <= H ÷ 2 ? (220, 30, 30) : (30, 30, 220)) :
                         (y <= H ÷ 2 ? (30, 200, 30) : (240, 240, 240))
        img[:, x, y] .= c
    end
    return img
end

px(img, x, y) = Int.(img[:, x, y])               # 1-based
near(a, b; tol=12) = all(abs.(a .- b) .<= tol)

function compress8(img, W, H; quality=95)
    h = handle(TJINIT_COMPRESS)
    J.tj3Set(h, TJPARAM_QUALITY, Cint(quality))
    J.tj3Set(h, TJPARAM_SUBSAMP, TJSAMP_444)
    buf, size = Ref{Ptr{UInt8}}(C_NULL), Ref{Csize_t}(0)
    rc = J.tj3Compress8(h, img, Cint(W), Cint(0), Cint(H), TJPF_RGB, buf, size)
    rc == 0 || error("tj3Compress8: ", J.tj3GetErrorStr(h))
    J.tj3Destroy(h)
    return take!(buf, size)
end

function decompress8(jpeg)
    h = handle(TJINIT_DECOMPRESS)
    J.tj3DecompressHeader(h, jpeg, Csize_t(length(jpeg))) == 0 ||
        error("header: ", J.tj3GetErrorStr(h))
    W, H = J.tj3Get(h, TJPARAM_JPEGWIDTH), J.tj3Get(h, TJPARAM_JPEGHEIGHT)
    out = zeros(UInt8, 3, W, H)
    J.tj3Decompress8(h, jpeg, Csize_t(length(jpeg)), out, Cint(0), TJPF_RGB) == 0 ||
        error("tj3Decompress8: ", J.tj3GetErrorStr(h))
    J.tj3Destroy(h)
    return out, W, H
end

# ── tests ────────────────────────────────────────────────────────────────────

@testset "libjpeg-turbo Deep Tests" begin

@testset "Version macro matches the pinned tag" begin
    @test J.TURBOJPEG_VERSION_NUMBER() == 3002000
    @test J.TJ_NUMPF() == 12
end

@testset "8-bit lossy round trip" begin
    W, H = 64, 48
    img = quadrants(W, H)
    jpeg = compress8(img, W, H)
    @test jpeg[1:2] == [0xFF, 0xD8]                       # SOI marker
    @test length(jpeg) < sizeof(img)                      # it compressed

    h = handle(TJINIT_DECOMPRESS)
    @test J.tj3DecompressHeader(h, jpeg, Csize_t(length(jpeg))) == 0
    @test J.tj3Get(h, TJPARAM_JPEGWIDTH) == W
    @test J.tj3Get(h, TJPARAM_JPEGHEIGHT) == H
    @test J.tj3Get(h, TJPARAM_SUBSAMP) == TJSAMP_444
    @test J.tj3Get(h, TJPARAM_PRECISION) == 8
    J.tj3Destroy(h)

    out, _, _ = decompress8(jpeg)
    for (x, y) in ((16, 12), (48, 12), (16, 36), (48, 36))   # quadrant centres
        @test near(px(out, x, y), px(img, x, y))
    end
end

@testset "12-bit lossy round trip" begin
    W, H = 32, 32
    src = Int16[(x - 1) * 128 for c in 1:3, x in 1:W, y in 1:H]   # 0…3968 ramp
    h = handle(TJINIT_COMPRESS)
    J.tj3Set(h, TJPARAM_PRECISION, Cint(12))
    J.tj3Set(h, TJPARAM_QUALITY, Cint(95))
    J.tj3Set(h, TJPARAM_SUBSAMP, TJSAMP_444)
    buf, size = Ref{Ptr{UInt8}}(C_NULL), Ref{Csize_t}(0)
    @test J.tj3Compress12(h, src, Cint(W), Cint(0), Cint(H), TJPF_RGB, buf, size) == 0
    J.tj3Destroy(h)
    jpeg = take!(buf, size)

    d = handle(TJINIT_DECOMPRESS)
    J.tj3DecompressHeader(d, jpeg, Csize_t(length(jpeg)))
    @test J.tj3Get(d, TJPARAM_PRECISION) == 12
    out = zeros(Int16, 3, W, H)
    @test J.tj3Decompress12(d, jpeg, Csize_t(length(jpeg)), out, Cint(0), TJPF_RGB) == 0
    J.tj3Destroy(d)
    @test maximum(abs.(Int.(out) .- Int.(src))) <= 64        # ~1.5% of 4095
    @test maximum(out) > 3000                                 # really 12-bit range
end

@testset "16-bit lossless round trip is bit-exact" begin
    W, H = 24, 16
    src = UInt16[(x * 2731 + y * 977) % 65536 for x in 1:W, y in 1:H]   # grayscale
    h = handle(TJINIT_COMPRESS)
    J.tj3Set(h, TJPARAM_PRECISION, Cint(16))
    J.tj3Set(h, TJPARAM_LOSSLESS, Cint(1))
    buf, size = Ref{Ptr{UInt8}}(C_NULL), Ref{Csize_t}(0)
    rc = J.tj3Compress16(h, src, Cint(W), Cint(0), Cint(H), TJPF_GRAY, buf, size)
    rc == 0 || @info "tj3Compress16" J.tj3GetErrorStr(h)
    @test rc == 0
    J.tj3Destroy(h)
    jpeg = take!(buf, size)

    d = handle(TJINIT_DECOMPRESS)
    J.tj3DecompressHeader(d, jpeg, Csize_t(length(jpeg)))
    @test J.tj3Get(d, TJPARAM_PRECISION) == 16
    @test J.tj3Get(d, TJPARAM_LOSSLESS) == 1
    out = zeros(UInt16, W, H)
    @test J.tj3Decompress16(d, jpeg, Csize_t(length(jpeg)), out, Cint(0), TJPF_GRAY) == 0
    J.tj3Destroy(d)
    @test out == src
end

@testset "Lossless transform — ROT90" begin
    W, H = 64, 48                                   # multiples of the 8×8 MCU (4:4:4)
    jpeg = compress8(quadrants(W, H), W, H)

    t = handle(TJINIT_TRANSFORM)
    xf = Ref(J.tjtransform(J.tjregion(Cint(0), Cint(0), Cint(0), Cint(0)),
                           TJXOP_ROT90, Cint(0), C_NULL, C_NULL))
    dst, dsz = Ref{Ptr{UInt8}}(C_NULL), Ref{Csize_t}(0)
    @test J.tj3Transform(t, jpeg, Csize_t(length(jpeg)), Cint(1), dst, dsz, xf) == 0
    J.tj3Destroy(t)
    rot = take!(dst, dsz)

    out, RW, RH = decompress8(rot)
    @test (RW, RH) == (H, W)                        # dimensions swapped
    # Clockwise: original top-left (red) → top-right; bottom-left (blue) → top-left.
    @test near(px(out, 36, 16), [220, 30, 30])      # red,   now top-right
    @test near(px(out, 12, 16), [30, 30, 220])      # blue,  now top-left
    @test near(px(out, 36, 48), [30, 200, 30])      # green, now bottom-right
    @test near(px(out, 12, 48), [240, 240, 240])    # white, now bottom-left
end

@testset "Image I/O — PNG (folded spng+zlib) and BMP, bit-exact" begin
    W, H = 40, 30
    img = quadrants(W, H)
    mktempdir() do dir
        for ext in ("png", "bmp")
            path = joinpath(dir, "q.$ext")
            h = handle(TJINIT_COMPRESS)
            @test J.tj3SaveImage8(h, path, img, Cint(W), Cint(0), Cint(H), TJPF_RGB) == 0
            @test filesize(path) > 0

            w, hh, pf = Ref{Cint}(0), Ref{Cint}(0), Ref{Cint}(TJPF_RGB)
            p = J.tj3LoadImage8(h, path, w, Cint(1), hh, pf)
            @test p != C_NULL
            @test (w[], hh[]) == (W, H)
            back = copy(unsafe_wrap(Array, Ptr{UInt8}(p), (3, W, H)))
            J.tj3Free(p)
            J.tj3Destroy(h)
            @test back == img
        end
    end
end

@testset "Error path — garbage is refused, not a crash" begin
    h = handle(TJINIT_DECOMPRESS)
    junk = rand(UInt8, 256); junk[1:2] .= 0x00
    @test J.tj3DecompressHeader(h, junk, Csize_t(length(junk))) == -1
    msg = J.tj3GetErrorStr(h)
    @test msg isa AbstractString && !isempty(msg)
    J.tj3Destroy(h)
end

end
