# ImguiDemo — proves the wrapper puts pixels in a framebuffer.
#
# Needs a GL context, so it needs a display. Under Hyprland that is Xwayland:
# GLFW_PLATFORM=x11 DISPLAY=:1. The window is created with GLFW_VISIBLE=false,
# so nothing appears on screen; the evidence is the readback.
#
# A non-zero TotalVtxCount only proves imgui BUILT geometry. glReadPixels
# proves the GPU drew it. Both are asserted — they fail for different reasons
# (the first for a broken wrapper, the second for a broken renderer backend or
# a context that never became current).

using Test

include(joinpath(@__DIR__, "..", "src", "ImguiDemo.jl"))
using .ImguiDemo
const D = ImguiDemo

const HAVE_DISPLAY = haskey(ENV, "DISPLAY") || haskey(ENV, "WAYLAND_DISPLAY")

@testset "ImguiDemo" begin

if !HAVE_DISPLAY
    @info "no DISPLAY/WAYLAND_DISPLAY — skipping GL tests"
else

@testset "context comes up" begin
    c = D.Ctx(width = 640, height = 480, visible = false)
    try
        @test c.window != C_NULL
        @test c.imgui  != C_NULL
        @test c.open
        @test (c.w, c.h) == (640, 480)
    finally
        D.close!(c)
    end
    @test true   # close! did not throw
end

@testset "frame 1 is empty, frame 2 draws" begin
    # Upstream imgui settles its font atlas during the first frame. This is
    # asserted rather than worked around: if it ever changes, the assertion
    # tells us instead of a "why is my first frame blank" hunt later.
    c = D.Ctx(width = 640, height = 480, visible = false)
    try
        f1 = D.render_frame(c)
        @test f1.valid
        @test f1.vtx == 0
        @test f1.cmdlists == 0

        f2 = D.render_frame(c)
        @test f2.valid
        @test f2.vtx > 0
        @test f2.idx > 0
        @test f2.cmdlists == 1
    finally
        D.close!(c)
    end
end

@testset "pixels actually reach the framebuffer" begin
    c = D.Ctx(width = 320, height = 240, visible = false)
    try
        for _ in 1:8
            D.render_frame(c)
        end
        px = D.capture(c)
        @test length(px.buf) == 320 * 240 * 4
        # A window with text, a button, a slider and a checkbox covers a
        # meaningful area. A handful of stray pixels would mean the clear
        # colour was wrong, not that imgui drew.
        @test px.nonbg > 1000
    finally
        D.close!(c)
    end
end

@testset "widget state survives across frames" begin
    # The immediate-mode contract: state lives in the caller's Refs, and imgui
    # reads them every frame. If the wrapper mis-marshalled the Ref the value
    # would not round-trip.
    c = D.Ctx(width = 320, height = 240, visible = false)
    try
        D._SLIDER[] = 0.75f0
        D._CHECK[]  = true
        for _ in 1:3
            D.render_frame(c)
        end
        @test D._SLIDER[] == 0.75f0
        @test D._CHECK[]  == true
    finally
        D._SLIDER[] = 0.35f0
        D._CHECK[]  = false
        D.close!(c)
    end
end

@testset "a custom ui function is honoured" begin
    c = D.Ctx(width = 320, height = 240, visible = false)
    hits = Ref(0)
    ui = function ()
        hits[] += 1
        D.G.ImGui_Begin("custom", C_NULL, Cint(0))
        D.G.ImGui_TextUnformatted("hello from a closure", C_NULL)
        D.G.ImGui_End()
        nothing
    end
    try
        D.render_frame(c; ui = ui)
        r = D.render_frame(c; ui = ui)
        @test hits[] == 2
        @test r.vtx > 0
    finally
        D.close!(c)
    end
end

end # HAVE_DISPLAY
end

println("✓ ImguiDemo tests passed")
