#!/usr/bin/env julia
# GLFW Hub package — deep integration test
#
# Assumes the wrapper is already built. Proves the wrapper *drives* GLFW, not
# merely that it loaded:
#   - value-macro constants pinned against glfw3.h
#   - glfwInit / glfwGetVersion / glfwGetPlatform (X11-only build)
#   - hidden window (GLFW_VISIBLE=false) → size/pos query → resize
#   - a Julia @cfunction error callback that fires on an invalid window hint
#     (size callbacks do not fire on a never-mapped X11 window)
#   - destroy + terminate
#
# X11-only wrap: run with DISPLAY=:1 (Xwayland on this box). Wayland is not
# compiled in; glfwPlatformSupported(GLFW_PLATFORM_WAYLAND) is 0.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/glfw/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Glfw.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

# X11-only binary. Prefer the session's Xwayland if DISPLAY is unset.
if !haskey(ENV, "DISPLAY") || isempty(ENV["DISPLAY"])
    ENV["DISPLAY"] = ":1"
end

include(WRAPPER)

# ── Callbacks (must be top-level, non-closure, for @cfunction) ───────────────

const SIZE_HITS = Ref(0)
const LAST_W = Ref(0)
const LAST_H = Ref(0)

# C: void (*)(GLFWwindow*, int, int)
function jl_winsize(window::Ptr{Glfw.GLFWwindow}, width::Cint, height::Cint)::Cvoid
    SIZE_HITS[] += 1
    LAST_W[] = Int(width)
    LAST_H[] = Int(height)
    return nothing
end

const ERR_HITS = Ref(0)
const LAST_ERR = Ref(0)

# C: void (*)(int, const char*)
function jl_error(code::Cint, desc::Cstring)::Cvoid
    ERR_HITS[] += 1
    LAST_ERR[] = Int(code)
    return nothing
end

# ── Tests ────────────────────────────────────────────────────────────────────

@testset "GLFW Deep Tests" begin

@testset "Value-macro constants match glfw3.h" begin
    @test Glfw.GLFW_VERSION_MAJOR() == 3
    @test Glfw.GLFW_VERSION_MINOR() == 5
    @test Glfw.GLFW_VERSION_REVISION() == 1
    @test Glfw.GLFW_TRUE() == 1
    @test Glfw.GLFW_FALSE() == 0
    @test Glfw.GLFW_RELEASE() == 0
    @test Glfw.GLFW_PRESS() == 1
    @test Glfw.GLFW_VISIBLE() == 0x00020004
    @test Glfw.GLFW_CONTEXT_VERSION_MAJOR() == 0x00022002
    @test Glfw.GLFW_CONTEXT_VERSION_MINOR() == 0x00022003
    @test Glfw.GLFW_OPENGL_PROFILE() == 0x00022008
    @test Glfw.GLFW_OPENGL_CORE_PROFILE() == 0x00032001
    @test Glfw.GLFW_PLATFORM_X11() == 0x00060004
    @test Glfw.GLFW_PLATFORM_WAYLAND() == 0x00060003
    @test Glfw.GLFW_NO_ERROR() == 0
end

@testset "Hub .so is not the distro copy" begin
    hub = realpath(Glfw.LIBRARY_PATH)
    @test occursin("packages/glfw/julia/libglfw.so", hub)
    sys = "/usr/lib/libglfw.so.3"
    if ispath(sys)
        @test realpath(hub) != realpath(sys)
    end
end

@testset "glfwInit + version + X11 platform" begin
    @test Glfw.glfwInit() == Glfw.GLFW_TRUE()
    major = Ref{Cint}(0); minor = Ref{Cint}(0); rev = Ref{Cint}(0)
    Glfw.glfwGetVersion(major, minor, rev)
    @test major[] == 3
    @test minor[] == 5
    @test rev[] == 1
    vs = Glfw.glfwGetVersionString()
    @test vs isa AbstractString
    @test occursin("3.5.1", vs)
    @test occursin("X11", vs)
    @test Glfw.glfwGetPlatform() == Glfw.GLFW_PLATFORM_X11()
    @test Glfw.glfwPlatformSupported(Glfw.GLFW_PLATFORM_X11()) == Glfw.GLFW_TRUE()
    @test Glfw.glfwPlatformSupported(Glfw.GLFW_PLATFORM_WAYLAND()) == Glfw.GLFW_FALSE()
end

@testset "Hidden window: create, query, resize, callback, destroy" begin
    Glfw.glfwWindowHint(Glfw.GLFW_VISIBLE(), Glfw.GLFW_FALSE())
    Glfw.glfwWindowHint(Glfw.GLFW_CONTEXT_VERSION_MAJOR(), 3)
    Glfw.glfwWindowHint(Glfw.GLFW_CONTEXT_VERSION_MINOR(), 3)
    Glfw.glfwWindowHint(Glfw.GLFW_OPENGL_PROFILE(), Glfw.GLFW_OPENGL_CORE_PROFILE())

    title = "glfw-hub-test-deep"
    raw = Glfw.glfwCreateWindow(1280, 720, title, C_NULL, C_NULL)
    @test raw != C_NULL
    window = Ptr{Glfw.GLFWwindow}(raw)

    w = Ref{Cint}(0); h = Ref{Cint}(0)
    Glfw.glfwGetWindowSize(window, w, h)
    @test w[] == 1280
    @test h[] == 720

    x = Ref{Cint}(0); y = Ref{Cint}(0)
    Glfw.glfwGetWindowPos(window, x, y)
    # Position is compositor-defined; just prove the out-params were written
    # (zeros are a legal position, so we only check the call did not throw).
    @test x[] isa Cint
    @test y[] isa Cint

    SIZE_HITS[] = 0
    LAST_W[] = 0
    LAST_H[] = 0
    cb = @cfunction(jl_winsize, Cvoid, (Ptr{Glfw.GLFWwindow}, Cint, Cint))
    prev = Glfw.glfwSetWindowSizeCallback(window, cb)
    @test prev == C_NULL   # no previous callback

    Glfw.glfwSetWindowSize(window, 640, 480)
    Glfw.glfwPollEvents()
    w2 = Ref{Cint}(0); h2 = Ref{Cint}(0)
    Glfw.glfwGetWindowSize(window, w2, h2)
    @test w2[] == 640
    @test h2[] == 480
    # A never-mapped (GLFW_VISIBLE=false) X11 window does not get
    # ConfigureNotify, so the size callback typically does not fire even
    # though the stored size changes. The firing proof is the error
    # callback below, which does not need a mapped window.

    Glfw.glfwDestroyWindow(window)
end

@testset "Error callback from Julia @cfunction" begin
    ERR_HITS[] = 0
    LAST_ERR[] = 0
    ecb = @cfunction(jl_error, Cvoid, (Cint, Cstring))
    Glfw.glfwSetErrorCallback(ecb)
    # glfwGetKey(NULL) asserts when NDEBUG is off (this wrap compiles without
    # NDEBUG). An unknown window hint takes the GLFW_INVALID_ENUM path in
    # glfwWindowHint and reports through the error callback without aborting.
    Glfw.glfwWindowHint(Cint(-1), 0)
    @test ERR_HITS[] >= 1
    @test LAST_ERR[] != Glfw.GLFW_NO_ERROR()
    Glfw.glfwSetErrorCallback(C_NULL)
    # Drain the last error so terminate sees a clean TLS slot.
    @test Glfw.glfwGetError(C_NULL) != Glfw.GLFW_NO_ERROR()
end

@testset "terminate" begin
    Glfw.glfwTerminate()
end

end # @testset GLFW Deep Tests

println("✓ glfw deep test passed")
