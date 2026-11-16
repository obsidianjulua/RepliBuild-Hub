#!/usr/bin/env julia
# raylib Hub package — deep integration test
#
# Assumes the wrapper is already built (builds it on a miss). Proves the
# wrapper *drives* raylib, not merely that it loaded:
#   - version value-macros pinned against the tag (shim-header canary)
#   - pure by-value-struct math: Rectangle/Vector2 in, Bool/Rectangle out
#   - Color by value both ways (Fade, ColorFromHSV)
#   - CPU-side Image API: GenImageColor → ImageDraw* through Ptr{Image} →
#     GetImageColor reads back the exact pixels (no display needed)
#   - GPU path on a hidden window: render-texture draw → LoadImageFromTexture
#     → real pixels read back; default font loaded (MeasureText > 0)
#
# X11-only build: the GPU testset runs on DISPLAY (Xwayland on this box,
# defaulting to :1) and is skipped with a note when no display is reachable.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/raylib/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Raylib.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

if !haskey(ENV, "DISPLAY") || isempty(ENV["DISPLAY"])
    ENV["DISPLAY"] = ":1"
end

include(WRAPPER)
const R = Raylib

# raylib.h enum values used below (ConfigFlags / TraceLogLevel). Enum members
# that no function signature references do not reach DWARF, so they are
# spelled here against the pinned header.
const FLAG_WINDOW_HIDDEN = UInt32(0x00000080)
const LOG_INFO    = Cint(3)
const LOG_WARNING = Cint(4)
const LOG_ERROR   = Cint(5)
const LOG_NONE    = Cint(7)

rgba(r, g, b, a=255) = R.Color(UInt8(r), UInt8(g), UInt8(b), UInt8(a))
rect(x, y, w, h)     = R.Rectangle(Float32(x), Float32(y), Float32(w), Float32(h))
vec2(x, y)           = R.Vector2(Float32(x), Float32(y))
same(a::R.Color, b::R.Color) = (a.r, a.g, a.b, a.a) == (b.r, b.g, b.b, b.a)

const BLACK = rgba(0, 0, 0)
const RED   = rgba(230, 41, 55)      # raylib.h RED
const BLUE  = rgba(0, 121, 241)      # raylib.h BLUE

R.SetTraceLogLevel(LOG_WARNING)

"What `f()` printed to stdout (TraceLog vprintf()s and fflush()es it)."
function stdout_of(f)
    path = tempname()
    open(path, "w") do io
        redirect_stdout(io) do
            f()
            Libc.flush_cstdio()
        end
    end
    s = read(path, String)
    rm(path)
    return s
end

@testset "raylib Deep Tests" begin

@testset "[wrap.varargs] TextFormat" begin
    @test R.TextFormat("plain text") == "plain text"          # the fixed-only form still exists
    @test R.TextFormat_Cint("score: %d", 42) == "score: 42"
    @test R.TextFormat_Cdouble("%.3f", Float64(pi)) == "3.142"
    @test R.TextFormat_Cstring("hello %s", "julia") == "hello julia"
    @test R.TextFormat_Cint_Cint("%dx%d", 1920, 1080) == "1920x1080"
    @test R.TextFormat_Cdouble_Cdouble("(%.1f, %.1f)", 1.5, -2.5) == "(1.5, -2.5)"
    @test R.TextFormat_Cstring_Cint("%s=%d", "lives", 3) == "lives=3"
    @test R.TextFormat_Cstring_Cstring("%s/%s", "a", "b") == "a/b"
    @test R.TextFormat_Cint_Cint_Cint("#%02x%02x%02x", 255, 128, 0) == "#ff8000"
    # raylib rotates 4 static buffers; the wrapper copies each result into a
    # Julia String, so results survive any number of later calls.
    rs = [R.TextFormat_Cint("n%d", i) for i in 1:10]
    @test rs == ["n$i" for i in 1:10]
end

@testset "[wrap.varargs] TraceLog" begin
    # Threshold is LOG_WARNING (set above): INFO is dropped, WARNING and ERROR
    # print with their prefix. LOG_FATAL is never called: it exit()s.
    out = stdout_of() do
        R.TraceLog_Cint(LOG_WARNING, "frame %d dropped", 7)
        R.TraceLog_Cstring(LOG_INFO, "below the threshold %s", "x")
        R.TraceLog_Cstring_Cint(LOG_ERROR, "%s failed: %d", "load", -1)
        R.TraceLog_Cdouble(LOG_WARNING, "dt=%.2f", 0.25)
        R.TraceLog_Cint_Cint(LOG_WARNING, "%d of %d", 3, 4)
        R.TraceLog_Cstring_Cstring(LOG_WARNING, "%s %s", "a", "b")
        R.TraceLog(LOG_WARNING, "no arguments")
    end
    @test out == """
        WARNING: frame 7 dropped
        ERROR: load failed: -1
        WARNING: dt=0.25
        WARNING: 3 of 4
        WARNING: a b
        WARNING: no arguments
        """
end

@testset "Version macros match the pinned tag" begin
    @test R.RAYLIB_VERSION_MAJOR() == 6
    @test R.RAYLIB_VERSION_MINOR() == 2
    @test R.RAYLIB_VERSION_PATCH() == 0
    @test R.RAYLIB_VERSION() == "6.2"   # const char* shim already returns a String
end

@testset "Collision math — structs by value" begin
    a = rect(0, 0, 10, 10)
    b = rect(5, 5, 10, 10)
    c = rect(20, 20, 4, 4)
    @test R.CheckCollisionRecs(a, b) == true
    @test R.CheckCollisionRecs(a, c) == false

    # Struct returned by value: overlap of a and b is the 5×5 square at (5,5).
    o = R.GetCollisionRec(a, b)
    @test (o.x, o.y, o.width, o.height) == (5f0, 5f0, 5f0, 5f0)

    @test R.CheckCollisionCircleRec(vec2(-2, 5), 3f0, a) == true
    @test R.CheckCollisionCircleRec(vec2(-5, 5), 3f0, a) == false
end

@testset "Color by value both ways" begin
    f = R.Fade(RED, 0.5f0)
    @test (f.r, f.g, f.b) == (RED.r, RED.g, RED.b)
    @test f.a == 127                     # (unsigned char)(0.5f*255.0f)

    h = R.ColorFromHSV(120f0, 1f0, 1f0)  # pure green
    @test (h.r, h.g, h.b, h.a) == (0, 255, 0, 255)
end

@testset "CPU Image API — pixels through Ptr{Image}" begin
    img = Ref(R.GenImageColor(Cint(64), Cint(48), BLACK))
    @test img[].width == 64
    @test img[].height == 48
    @test img[].data != C_NULL

    R.ImageDrawRectangle(img, Cint(4), Cint(4), Cint(10), Cint(6), RED)
    R.ImageDrawCircle(img, Cint(40), Cint(30), Cint(5), BLUE)

    @test same(R.GetImageColor(img[], Cint(4),  Cint(4)),  RED)    # rect corner
    @test same(R.GetImageColor(img[], Cint(13), Cint(9)),  RED)    # rect far corner
    @test same(R.GetImageColor(img[], Cint(14), Cint(10)), BLACK)  # just outside
    @test same(R.GetImageColor(img[], Cint(40), Cint(30)), BLUE)   # circle centre
    @test same(R.GetImageColor(img[], Cint(60), Cint(2)),  BLACK)  # untouched

    R.UnloadImage(img[])
end

@testset "GPU path — hidden window, render texture, real pixels" begin
    R.SetTraceLogLevel(LOG_NONE)
    R.SetConfigFlags(FLAG_WINDOW_HIDDEN)
    R.InitWindow(Cint(160), Cint(120), "raylib test_deep")
    if !R.IsWindowReady()
        @info "No usable display/GL context on DISPLAY=$(ENV["DISPLAY"]) — GPU testset skipped"
        @test_skip false
    else
        @test R.IsWindowReady()
        @test R.MeasureText("Hello", Cint(20)) > 0   # default font is loaded

        W, H = 64, 64
        rt = R.LoadRenderTexture(Cint(W), Cint(H))
        @test rt.id != 0
        @test rt.texture.width == W

        R.BeginTextureMode(rt)
        R.ClearBackground(BLACK)
        R.DrawRectangle(Cint(0), Cint(0), Cint(16), Cint(16), RED)
        R.EndTextureMode()

        img = R.LoadImageFromTexture(rt.texture)
        @test img.width == W && img.height == H
        # GL render targets are bottom-up: raylib reads them back flipped, so
        # the rectangle drawn at the top-left lands at the bottom-left.
        @test same(R.GetImageColor(img, Cint(4), Cint(H - 5)), RED)
        @test same(R.GetImageColor(img, Cint(4), Cint(4)), BLACK)
        @test same(R.GetImageColor(img, Cint(W - 5), Cint(H - 5)), BLACK)

        R.UnloadImage(img)
        R.UnloadRenderTexture(rt)
        R.CloseWindow()
        @test !R.IsWindowReady()
    end
end

end
