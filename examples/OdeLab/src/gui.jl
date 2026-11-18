# Dear ImGui inside a raylib window.
#
# The Hub's imgui ships two backends, GLFW (platform) and OpenGL3 (renderer).
# Only the renderer is usable here. raylib compiles its own GLFW in with hidden
# visibility, while libimgui.so links packages/glfw's libglfw.so: two GLFW
# copies with separate global state, so a raylib window handed to
# ImGui_ImplGlfw_InitForOpenGL would belong to a GLFW that was never
# initialised. Instead:
#
#   * the OpenGL3 renderer draws into raylib's GL 3.3 context (it carries its own
#     GL loader and saves/restores the GL state it touches);
#   * this file is the platform backend: each frame it reads raylib's mouse,
#     wheel, keys and typed characters and queues them as ImGuiIO events.
#
# Frame order: `begin_frame!` (input, NewFrame) → widgets → raylib drawing →
# `end_frame!` (flush raylib's batch, render imgui on top) → EndDrawing.

mutable struct Gui
    ctx::Ptr{G.ImGuiContext}
    io::Ptr{UInt8}
    off_display::Int
    off_fbscale::Int
    off_dt::Int
    off_want_mouse::Int
    off_want_keys::Int
    font_size::Float32
end

# raylib key code → ImGuiKey, for the keys a slider's text field needs
# (ctrl-click a slider to type a value).
const _KEYMAP = ((258, G.ImGuiKey_Tab), (263, G.ImGuiKey_LeftArrow), (262, G.ImGuiKey_RightArrow),
                 (265, G.ImGuiKey_UpArrow), (264, G.ImGuiKey_DownArrow), (268, G.ImGuiKey_Home),
                 (269, G.ImGuiKey_End), (261, G.ImGuiKey_Delete), (259, G.ImGuiKey_Backspace),
                 (257, G.ImGuiKey_Enter), (335, G.ImGuiKey_KeypadEnter), (256, G.ImGuiKey_Escape),
                 (65, G.ImGuiKey_A), (67, G.ImGuiKey_C), (86, G.ImGuiKey_V), (88, G.ImGuiKey_X),
                 (90, G.ImGuiKey_Z))

"""A sans-serif TTF from fontconfig, or nothing (imgui then uses its built-in font)."""
function find_font()
    Sys.which("fc-match") === nothing && return nothing
    path = try
        readchomp(`fc-match -f '%{file}' sans`)
    catch
        ""
    end
    return isfile(path) && lowercase(splitext(path)[2]) in (".ttf", ".otf") ? path : nothing
end

"""Create the imgui context and the OpenGL3 renderer. Call after raylib's InitWindow."""
function Gui(; font::Union{Nothing,AbstractString} = find_font(), font_size::Real = 17)
    ctx = G.ImGui_CreateContext(C_NULL)
    ctx == C_NULL && error("OdeLab: ImGui_CreateContext returned NULL")
    io = Ptr{UInt8}(G.ImGui_GetIO())
    off(f) = G.member_offset("ImGuiIO", f)
    # No imgui.ini: the layout is fixed by the code, and the default path is the cwd.
    unsafe_store!(Ptr{Ptr{UInt8}}(io + off("IniFilename")), C_NULL)
    G.ImGui_StyleColorsDark(C_NULL)
    sp = Ptr{UInt8}(G.ImGui_GetStyle())
    soff(f) = G.member_offset("ImGuiStyle", f)
    for (f, v) in (("WindowRounding", 0f0), ("FrameRounding", 4f0), ("GrabRounding", 4f0),
                   ("WindowBorderSize", 0f0))
        unsafe_store!(Ptr{Cfloat}(sp + soff(f)), v)
    end
    if font !== nothing
        atlas = unsafe_load(Ptr{Ptr{Cvoid}}(io + off("Fonts")))
        f = G.ImFontAtlas_AddFontFromFileTTF(atlas, String(font), Cfloat(font_size), C_NULL, C_NULL)
        if f == C_NULL
            @warn "OdeLab: could not load font $font; using imgui's built-in one"
        else
            unsafe_store!(Ptr{Cfloat}(sp + soff("FontSizeBase")), Cfloat(font_size))
        end
    end
    G.ImGui_ImplOpenGL3_Init("#version 330") || error("OdeLab: ImGui_ImplOpenGL3_Init failed")
    return Gui(ctx, io, off("DisplaySize"), off("DisplayFramebufferScale"), off("DeltaTime"),
               off("WantCaptureMouse"), off("WantCaptureKeyboard"), Float32(font_size))
end

function shutdown!(g::Gui)
    g.ctx == C_NULL && return
    G.ImGui_ImplOpenGL3_Shutdown()
    G.ImGui_DestroyContext(g.ctx)
    g.ctx = C_NULL
    return
end

_store2!(p, a, b) = (unsafe_store!(Ptr{Float32}(p), Float32(a)); unsafe_store!(Ptr{Float32}(p + 4), Float32(b)))

"""Feed this frame's raylib input to imgui and start an imgui frame."""
function begin_frame!(g::Gui)
    io = g.io
    sw, sh = R.GetScreenWidth(), R.GetScreenHeight()
    rw, rh = R.GetRenderWidth(), R.GetRenderHeight()
    _store2!(io + g.off_display, sw, sh)
    _store2!(io + g.off_fbscale, sw > 0 ? rw / sw : 1, sh > 0 ? rh / sh : 1)
    unsafe_store!(Ptr{Float32}(io + g.off_dt), max(R.GetFrameTime(), 1f-4))

    m = R.GetMousePosition()
    G.ImGuiIO_AddMousePosEvent(io, m.x, m.y)
    for b in 0:2      # imgui drops events that repeat the current state
        G.ImGuiIO_AddMouseButtonEvent(io, b, R.IsMouseButtonDown(Cint(b)))
    end
    w = R.GetMouseWheelMoveV()
    (w.x != 0 || w.y != 0) && G.ImGuiIO_AddMouseWheelEvent(io, w.x, w.y)
    down(k) = R.IsKeyDown(Cint(k))
    G.ImGuiIO_AddKeyEvent(io, G.ImGuiMod_Ctrl, down(341) || down(345))
    G.ImGuiIO_AddKeyEvent(io, G.ImGuiMod_Shift, down(340) || down(344))
    for (k, key) in _KEYMAP
        G.ImGuiIO_AddKeyEvent(io, key, down(k))
    end
    while (c = R.GetCharPressed()) > 0
        G.ImGuiIO_AddInputCharacter(io, c)
    end
    G.ImGui_ImplOpenGL3_NewFrame()
    G.ImGui_NewFrame()
    return
end

"""Flush raylib's pending geometry, then draw imgui over it."""
function end_frame!(::Gui)
    R.rlDrawRenderBatchActive()
    G.ImGui_Render()
    G.ImGui_ImplOpenGL3_RenderDrawData(G.ImGui_GetDrawData())
    return
end

"""True while the mouse is over an imgui window (the camera should not take it)."""
wants_mouse(g::Gui) = unsafe_load(Ptr{Bool}(g.io + g.off_want_mouse))
"""True while an imgui text field has the keyboard."""
wants_keyboard(g::Gui) = unsafe_load(Ptr{Bool}(g.io + g.off_want_keys))

# ── widgets, the Julia way round ────────────────────────────────────────────
# imgui's Text/TextWrapped are printf-style (`%` would be read as a format), so
# all text goes through TextUnformatted.

text(s::AbstractString) = G.ImGui_TextUnformatted(s, C_NULL)
function wrapped(s::AbstractString)
    G.ImGui_PushTextWrapPos(0f0)
    G.ImGui_TextUnformatted(s, C_NULL)
    G.ImGui_PopTextWrapPos()
end
function dim(s::AbstractString; wrap::Bool = false)
    G.ImGui_PushStyleColor(Int(G.ImGuiCol_Text), Ref(G.ImVec4(0.62f0, 0.64f0, 0.70f0, 1f0)))
    wrap ? wrapped(s) : text(s)
    G.ImGui_PopStyleColor(1)
end
heading(s::AbstractString) = G.ImGui_SeparatorText(s)
sameline() = G.ImGui_SameLine(0f0, -1f0)
button(label::AbstractString) = G.ImGui_Button(label, Ref(G.ImVec2(0f0, 0f0)))
radio(label::AbstractString, active::Bool) = G.ImGui_RadioButton(label, active)
checkbox!(label::AbstractString, v::Ref{Bool}) = G.ImGui_Checkbox(label, v)

"""A Float64 slider; `log = true` for a logarithmic scale. Returns true when changed."""
function slider!(label::AbstractString, v::Ref{Float64}, lo::Real, hi::Real;
                 log::Bool = false, fmt::AbstractString = "%.4g")
    flags = log ? Int(G.ImGuiSliderFlags_Logarithmic) : 0
    return G.ImGui_SliderScalar(label, Int(G.ImGuiDataType_Double), v, Ref(Float64(lo)), Ref(Float64(hi)), fmt, flags)
end

"""A line chart of `values` (Float32) between `lo` and `hi`."""
function plot(label::AbstractString, values::Vector{Float32}, lo::Real, hi::Real, w::Real, h::Real;
              overlay::AbstractString = "")
    isempty(values) && return
    GC.@preserve values G.ImGui_PlotLines(label, pointer(values), length(values), 0, overlay,
                                         Float32(lo), Float32(hi), G.ImVec2(Float32(w), Float32(h)),
                                         sizeof(Float32))
end

"""A two-column key/value table; `id` must be unique within the window."""
function table(id::AbstractString, rows)
    if G.ImGui_BeginTable(id, 2, 0, Ref(G.ImVec2(0f0, 0f0)), 0f0)
        for (k, v) in rows
            G.ImGui_TableNextRow(0, 0f0)
            G.ImGui_TableNextColumn(); dim(k)
            G.ImGui_TableNextColumn(); text(v)
        end
        G.ImGui_EndTable()
    end
end
