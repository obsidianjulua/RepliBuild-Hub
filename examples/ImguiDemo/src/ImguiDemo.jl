"""
    ImguiDemo

Dear ImGui driven entirely from Julia — window, GL context, widgets, and real
pixels — through the RepliBuild-generated wrapper in `lib/`.

There is no C++ host program here. `lib/libimgui.so` is imgui core plus the
upstream GLFW platform backend and OpenGL3 renderer backend, wrapped from DWARF;
every call below is either a Tier-2 MLIR AOT thunk or a Tier-3 `ccall`.

TWO HUB PACKAGES, ONE LIBRARY
-----------------------------
Both wrappers in `lib/` are RepliBuild output: `Imgui.jl` over imgui core +
backends, and `Glfw.jl` over GLFW (124/124 of the public API). They share **one**
`libglfw.so`, and that is load-bearing rather than tidy.

GLFW keeps process-global state. If imgui were bound to the distro
`/usr/lib/libglfw.so.3` while `Glfw.jl` drove its own copy, both would map into
the session — measured, they did — and `glfwInit()` on one would not initialise
the other. A `GLFWwindow*` created here and handed to
`ImGui_ImplGlfw_InitForOpenGL` (inside libimgui.so, bound to the other copy)
would be undefined behaviour.

`packages/imgui` is therefore linked against `packages/glfw`'s output, with an
rpath so the loader follows the same path the linker did. `-L` alone would not
have done it: RepliBuild's output carries no SONAME, so the recorded DT_NEEDED
is a bare `libglfw.so` and the loader would have found /usr/lib first — the
build succeeding against one copy and the process running against another.

Here, `\$ORIGIN` leads the rpath and `Glfw.jl` resolves its library sibling-first,
so both land on `lib/libglfw.so` and this directory is self-contained. Confirm
any time with:

    ldd lib/libimgui.so | grep glfw        # must be lib/, not /usr/lib
"""
module ImguiDemo

# `run` is deliberately NOT exported: it would shadow `Base.run` for anyone who
# says `using ImguiDemo`. Same rule the wrapper generator applies to itself when
# it withholds `error`, `all` and `symlink`. Reach it as `ImguiDemo.run(...)`.
export render_frame, capture, main

include(joinpath(@__DIR__, "..", "lib", "Imgui.jl"))
import .Imgui
const G = Imgui

include(joinpath(@__DIR__, "..", "lib", "Glfw.jl"))
import .Glfw
const W = Glfw

# Macro constants are shims in the GLFW wrapper, so they are nullary functions
# rather than consts. Bound once here; they are compile-time values upstream.
const GLFW_FALSE                 = W.GLFW_FALSE()
const GLFW_TRUE                  = W.GLFW_TRUE()
const GLFW_VISIBLE               = W.GLFW_VISIBLE()
const GLFW_CONTEXT_VERSION_MAJOR = W.GLFW_CONTEXT_VERSION_MAJOR()
const GLFW_CONTEXT_VERSION_MINOR = W.GLFW_CONTEXT_VERSION_MINOR()
const GLFW_OPENGL_PROFILE        = W.GLFW_OPENGL_PROFILE()
const GLFW_OPENGL_CORE_PROFILE   = W.GLFW_OPENGL_CORE_PROFILE()

glfw_init()          = W.glfwInit()
glfw_terminate()     = W.glfwTerminate()
glfw_hint(h, v)      = W.glfwWindowHint(Cint(h), Cint(v))
glfw_make_current(w) = W.glfwMakeContextCurrent(w)
glfw_poll()          = W.glfwPollEvents()
glfw_swap(w)         = W.glfwSwapBuffers(w)
glfw_destroy(w)      = W.glfwDestroyWindow(w)

# glfwCreateWindow returns Ptr{Cvoid} (opaque returns lose their type in DWARF);
# parameters that TAKE a window are typed Ptr{GLFWwindow}. Convert once here.
glfw_create(w, h, title) =
    Ptr{W.GLFWwindow}(W.glfwCreateWindow(Cint(w), Cint(h), title, C_NULL, C_NULL))

function glfw_error()
    d = Ref{Ptr{UInt8}}(C_NULL)
    c = ccall((:glfwGetError, W.LIBRARY_PATH), Cint, (Ptr{Ptr{UInt8}},), d)
    (c, d[] == C_NULL ? "" : unsafe_string(d[]))
end

# ── GL: only what a readback needs. The OpenGL3 backend carries its own
#    loader, so nothing else here has to resolve GL entry points. ────────────
const GL = "libGL"
const GL_COLOR_BUFFER_BIT = Cuint(0x00004000)
const GL_RGBA             = Cuint(0x1908)
const GL_UNSIGNED_BYTE    = Cuint(0x1401)

gl_viewport(w, h) = ccall((:glViewport, GL), Cvoid, (Cint, Cint, Cint, Cint), 0, 0, w, h)
gl_clear_color(r, g, b, a) = ccall((:glClearColor, GL), Cvoid,
                                   (Cfloat, Cfloat, Cfloat, Cfloat), r, g, b, a)
gl_clear() = ccall((:glClear, GL), Cvoid, (Cuint,), GL_COLOR_BUFFER_BIT)
gl_finish() = ccall((:glFinish, GL), Cvoid, ())
function gl_read_pixels(w, h)
    buf = Vector{UInt8}(undef, w * h * 4)
    ccall((:glReadPixels, GL), Cvoid,
          (Cint, Cint, Cint, Cint, Cuint, Cuint, Ptr{Cvoid}),
          0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, buf)
    return buf
end

# ── ImGuiIO is an opaque byte blob; the wrapper ships the field offsets ──────
const IO_BACKEND_FLAGS = 4      # ImGuiIO::BackendFlags
const IO_DISPLAY_SIZE  = 8      # ImGuiIO::DisplaySize  (ImVec2)
const IO_DELTA_TIME    = 24     # ImGuiIO::DeltaTime    (float)

mutable struct Ctx
    window::Ptr{Glfw.GLFWwindow}
    imgui::Ptr{G.ImGuiContext}
    w::Int
    h::Int
    open::Bool
end

"""
    Ctx(; width = 1280, height = 720, visible = false) -> Ctx

Create a GL 3.3 core window and bring up both imgui backends.

`visible = false` by default: the interesting evidence is what lands in the
framebuffer, which `capture` reads back, and a hidden window does not disturb
whatever is on screen. Pass `visible = true` to actually watch it.
"""
function Ctx(; width::Int = 1280, height::Int = 720, visible::Bool = false,
             vsync::Bool = visible)
    glfw_init() == GLFW_TRUE || error("glfwInit failed: $(glfw_error())")
    glfw_hint(GLFW_CONTEXT_VERSION_MAJOR, 3)
    glfw_hint(GLFW_CONTEXT_VERSION_MINOR, 3)
    glfw_hint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE)
    glfw_hint(GLFW_VISIBLE, visible ? GLFW_TRUE : GLFW_FALSE)

    win = glfw_create(width, height, "RepliBuild · Dear ImGui")
    win == C_NULL && (glfw_terminate(); error("glfwCreateWindow failed: $(glfw_error())"))
    glfw_make_current(win)

    # Vsync. GLFW's default swap interval is 0 — SwapBuffers returns
    # immediately and the render loop runs as fast as the GPU allows, which for
    # a static UI means pegging the card to redraw an unchanged window. A first
    # interactive run measured 5,508 frames in roughly twenty seconds (~275 fps)
    # doing nothing.
    #
    # `vsync = false` is left available because the headless path wants it: with
    # no compositor to sync to there is nothing to wait for, and the tests would
    # otherwise pay 16 ms per frame for no reason.
    vsync && W.glfwSwapInterval(Cint(1))

    ictx = G.ImGui_CreateContext(C_NULL)
    ictx == C_NULL && error("ImGui_CreateContext returned NULL")

    io = Ptr{UInt8}(G.ImGui_GetIO())
    unsafe_store!(Ptr{Float32}(io + IO_DISPLAY_SIZE),     Float32(width))
    unsafe_store!(Ptr{Float32}(io + IO_DISPLAY_SIZE + 4), Float32(height))
    unsafe_store!(Ptr{Float32}(io + IO_DELTA_TIME),       1.0f0 / 60)

    G.ImGui_ImplGlfw_InitForOpenGL(win, true) ||
        error("ImGui_ImplGlfw_InitForOpenGL failed")
    G.ImGui_ImplOpenGL3_Init(C_NULL) ||
        error("ImGui_ImplOpenGL3_Init failed")

    return Ctx(win, ictx, width, height, true)
end

function close!(c::Ctx)
    c.open || return
    G.ImGui_ImplOpenGL3_Shutdown()
    G.ImGui_ImplGlfw_Shutdown()
    G.ImGui_DestroyContext(c.imgui)
    glfw_destroy(c.window)
    glfw_terminate()
    c.open = false
    return
end

"""
    render_frame(c; ui = default_ui) -> NamedTuple

One complete frame: backend NewFrame → imgui NewFrame → `ui()` → Render →
RenderDrawData → SwapBuffers. Returns the draw-data counters.

NOTE the first frame of a context emits **no geometry** — imgui settles its font
atlas during it. That is upstream behaviour, not a wrapper defect; call twice
before believing a zero.
"""
function render_frame(c::Ctx; ui::Function = default_ui, clear = (0.10f0, 0.11f0, 0.13f0))
    glfw_poll()
    G.ImGui_ImplOpenGL3_NewFrame()
    G.ImGui_ImplGlfw_NewFrame()
    G.ImGui_NewFrame()

    ui()

    G.ImGui_Render()
    gl_viewport(Cint(c.w), Cint(c.h))
    gl_clear_color(clear[1], clear[2], clear[3], 1.0f0)
    gl_clear()
    dd = G.ImGui_GetDrawData()
    G.ImGui_ImplOpenGL3_RenderDrawData(dd)
    glfw_swap(c.window)

    d = unsafe_load(dd)
    return (valid = d.Valid, vtx = Int(d.TotalVtxCount),
            idx = Int(d.TotalIdxCount), cmdlists = Int(d.CmdListsCount))
end

const _SLIDER = Ref(Float32(0.35))
const _CHECK  = Ref(false)
const _ZERO   = Ref(G.ImVec2(0f0, 0f0))

"""A small window exercising text, a button, a slider and a checkbox."""
function default_ui()
    G.ImGui_Begin("RepliBuild", C_NULL, Cint(0))
    G.ImGui_TextUnformatted("Dear ImGui, driven from Julia.", C_NULL)
    G.ImGui_Separator()
    G.ImGui_Button("Click me", _ZERO)
    G.ImGui_SliderFloat("weight", _SLIDER, 0f0, 1f0, C_NULL, Cint(0))
    G.ImGui_Checkbox("enabled", _CHECK)
    G.ImGui_End()
    return nothing
end

"""
    capture(c) -> (buf, nonbg)

Read the framebuffer back with `glReadPixels` and count pixels that differ from
the clear colour. This is the actual proof that something was rasterised — a
non-zero `TotalVtxCount` only says imgui *built* geometry, not that the GPU drew
it.
"""
function capture(c::Ctx; clear = (0.10f0, 0.11f0, 0.13f0))
    gl_finish()
    buf = gl_read_pixels(Cint(c.w), Cint(c.h))
    cr, cg, cb = round.(UInt8, 255 .* clear)
    nonbg = 0
    @inbounds for i in 1:4:length(buf)-3
        (buf[i] != cr || buf[i+1] != cg || buf[i+2] != cb) && (nonbg += 1)
    end
    return (buf = buf, nonbg = nonbg)
end

"""
    run(ui = default_ui; width = 1280, height = 720, max_frames = 0)

Open a window and render `ui` every frame until you close it. This is the
normal way to use the package.

`ui` is a zero-argument function called once per frame, between `NewFrame` and
`Render`. Immediate mode: it re-declares the whole interface every frame, so
widget state lives in `Ref`s you own, not in a retained tree.

```julia
const count = Ref(0)

function my_ui()
    G = ImguiDemo.G                       # the wrapped imgui module
    G.ImGui_Begin("Counter", C_NULL, Cint(0))
    G.ImGui_TextUnformatted("clicks: \$(count[])", C_NULL)
    G.ImGui_Button("bump", ImguiDemo._ZERO) && (count[] += 1)
    G.ImGui_End()
    nothing
end

ImguiDemo.run(my_ui)
```

`max_frames > 0` stops after that many frames regardless — how the tests drive
it without a human to close the window.

Blocks the REPL until the window closes. Ctrl-C works.
"""
function run(ui::Function = default_ui; width::Int = 1280, height::Int = 720,
             vsync::Bool = true,
             max_frames::Int = 0, visible::Bool = true)
    c = Ctx(width = width, height = height, visible = visible, vsync = vsync)
    n = 0
    try
        while max_frames == 0 || n < max_frames
            W.glfwWindowShouldClose(c.window) != 0 && break
            render_frame(c; ui = ui)
            n += 1
        end
    catch e
        e isa InterruptException || rethrow()
    finally
        close!(c)
    end
    return n
end

"""
    main(; frames = 120, visible = true)

Run the demo. Defaults to a visible window; the test suite calls the pieces
directly with `visible = false`.
"""
function main(; frames::Int = 120, visible::Bool = true)
    c = Ctx(visible = visible)
    try
        local r
        for _ in 1:frames
            r = render_frame(c)
        end
        px = capture(c)
        println("frames=$frames  vtx=$(r.vtx) idx=$(r.idx) cmdlists=$(r.cmdlists)  " *
                "non-background pixels=$(px.nonbg)")
        return px.nonbg
    finally
        close!(c)
    end
end

end # module
