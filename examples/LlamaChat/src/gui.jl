"""
    LlamaChat.GUI

A chat window over the same `ChatSession` the REPL uses: a scrolling transcript
and a prompt box, drawn by Dear ImGui in a GLFW window. All three native
libraries are RepliBuild output driven from Julia — `lib/Llamacpp.jl` for the
model, `lib/gui/Imgui.jl` and `lib/gui/Glfw.jl` for the window. There is no C++
host program.

Not loaded with the package. `LlamaChat.gui()` includes this file the first
time it is called (~4 s), so a terminal-only session never maps libimgui,
libglfw or libGL. `vendor_gui.sh` puts the wrappers in `lib/gui/`.

THREADS
-------
The window, its GL context and every GLFW/imgui call stay on the thread that
called `gui()`. The model loads, and every reply generates, in a task on
another thread (`Threads.@spawn`), streaming into a `StreamIO` that the render
loop snapshots once per frame. While that task runs the main thread never
touches the session; the one exception is the cancel flag, an Atomic that
exists for exactly that (`LlamaChat.cancel!`).

`StreamIO` is guarded by a SpinLock, not a ReentrantLock, on purpose. A
contended ReentrantLock parks the waiting task, and a parked main task can only
resume on thread 1 (the root task is sticky). If the generation task were
picked up by thread 1 in that window, the UI would freeze until the next token.
A SpinLock never yields, so neither side gives its thread away.

ONE GLFW
--------
`lib/gui/libglfw.so` is the only GLFW in the process: Glfw.jl resolves its
library next to itself, and libimgui.so's RUNPATH starts with `\$ORIGIN`. GLFW
state is process-global, so a second copy (say the distro's) would be a second
GLFW that `glfwInit` never initialised. The test suite checks /proc/self/maps.
"""
module GUI

import ..LlamaChat
const LC = LlamaChat

const LIBDIR = joinpath(dirname(@__DIR__), "lib", "gui")

# `import`, never `using`: a generated wrapper exports names that shadow Base.
include(joinpath(LIBDIR, "Imgui.jl")); import .Imgui; const G = Imgui
include(joinpath(LIBDIR, "Glfw.jl"));  import .Glfw;  const W = Glfw

# ── small helpers ────────────────────────────────────────────────────────────

vec2(x, y) = G.ImVec2(Cfloat(x), Cfloat(y))
vec4(r, g, b, a = 1) = G.ImVec4(Cfloat(r), Cfloat(g), Cfloat(b), Cfloat(a))
# Bitflag enums are Cuint consts; the C parameter is an int.
flags(xs...) = Cint(reduce(|, UInt32.(xs)))

const ZERO   = Ref(vec2(0, 0))
const C_USER = Ref(vec4(0.55, 0.75, 1.00))
const C_BOT  = Ref(vec4(0.55, 0.88, 0.60))
const C_ERR  = Ref(vec4(1.00, 0.45, 0.45))

const WINDOW_FLAGS = flags(G.ImGuiWindowFlags_NoTitleBar, G.ImGuiWindowFlags_NoResize,
                           G.ImGuiWindowFlags_NoMove, G.ImGuiWindowFlags_NoCollapse,
                           G.ImGuiWindowFlags_NoSavedSettings)
const PROMPT_FLAGS = flags(G.ImGuiInputTextFlags_EnterReturnsTrue,
                           G.ImGuiInputTextFlags_CtrlEnterForNewLine)
const THINK_FLAGS  = flags(G.ImGuiTreeNodeFlags_NoTreePushOnOpen)

"""
Draw `s` verbatim. Model text must never reach a printf-style entry point
(`Text`, `TextWrapped`, …): a single `%` in a reply would read varargs that
were never passed. `TextUnformatted` takes a [begin, end) byte range instead.
"""
function text!(s::String)
    isempty(s) && return nothing
    GC.@preserve s G.ImGui_TextUnformatted(pointer(s), pointer(s) + sizeof(s))
    return nothing
end

function colored(f, col::Ref{G.ImVec4})
    G.ImGui_PushStyleColor(Cint(G.ImGuiCol_Text), col)
    try
        f()
    finally
        G.ImGui_PopStyleColor(Cint(1))
    end
end

style_ptr() = Ptr{G.ImGuiStyle}(G.ImGui_GetStyle())
style_color(idx) = unsafe_load(Ptr{G.ImVec4}(G.ImGui_GetStyleColorVec4(Cint(idx))))

# ── GL: only what clearing and a readback need. The OpenGL3 backend loads its
#    own entry points, so nothing else here resolves GL. ─────────────────────
const GL = "libGL"
gl_viewport(w, h) = ccall((:glViewport, GL), Cvoid, (Cint, Cint, Cint, Cint), 0, 0, w, h)
gl_clear_color(c::G.ImVec4) = ccall((:glClearColor, GL), Cvoid,
                                    (Cfloat, Cfloat, Cfloat, Cfloat), c.x, c.y, c.z, c.w)
gl_clear() = ccall((:glClear, GL), Cvoid, (Cuint,), Cuint(0x4000))   # COLOR_BUFFER_BIT
gl_finish() = ccall((:glFinish, GL), Cvoid, ())
function gl_read(w, h)
    buf = Vector{UInt8}(undef, w * h * 4)
    ccall((:glReadPixels, GL), Cvoid, (Cint, Cint, Cint, Cint, Cuint, Cuint, Ptr{Cvoid}),
          0, 0, w, h, Cuint(0x1908), Cuint(0x1401), buf)            # RGBA, UNSIGNED_BYTE
    return buf
end

# ── the stream a worker writes and the render loop reads ─────────────────────

"""
An IO the generation task streams into and the render loop snapshots. `chat`
writes plain text to any non-tty IO, one complete UTF-8 chunk per write, so a
snapshot never splits a code point. SpinLock: see the module docstring.
"""
mutable struct StreamIO <: IO
    data::Vector{UInt8}
    lk::Threads.SpinLock
end
StreamIO() = StreamIO(UInt8[], Threads.SpinLock())

function Base.unsafe_write(io::StreamIO, p::Ptr{UInt8}, n::UInt)
    lock(io.lk)
    try
        n0 = length(io.data)
        resize!(io.data, n0 + n)
        GC.@preserve io unsafe_copyto!(pointer(io.data, n0 + 1), p, n)
    finally
        unlock(io.lk)
    end
    return Int(n)
end
Base.write(io::StreamIO, x::UInt8) = (lock(() -> push!(io.data, x), io.lk); 1)
Base.flush(::StreamIO) = nothing
Base.isopen(::StreamIO) = true
nbytes(io::StreamIO) = lock(() -> length(io.data), io.lk)
snapshot(io::StreamIO) = lock(() -> String(copy(io.data)), io.lk)

include("gui_md.jl")
include("gui_term.jl")

# ── transcript ───────────────────────────────────────────────────────────────

"""
    split_think(raw) -> (think, answer, open)

Separate a reply's leading `<think>…</think>` block from the answer. `think` is
`nothing` when the reply does not open with one; `open` is true while the block
has not closed yet (still streaming). Same rule as `LlamaChat._strip_think`:
only a block that OPENS the reply is reasoning.

Needed in the window whatever `think` is set to: `think = false` shortens the
reasoning and strips it from `Response.text`, but the stream still carries it.
"""
function split_think(raw::AbstractString)
    s = lstrip(raw)
    if !startswith(s, "<think>")
        # Streaming delivers the opening tag a token at a time; don't flash it.
        !isempty(s) && startswith("<think>", s) && return (nothing, "", false)
        return (nothing, String(raw), false)
    end
    body = SubString(s, ncodeunits("<think>") + 1)
    i = findfirst("</think>", body)
    i === nothing && return (String(strip(body)), "", true)
    return (String(strip(SubString(body, 1, prevind(body, first(i))))),
            String(lstrip(SubString(body, nextind(body, last(i))))), false)
end

mutable struct Turn
    role::Symbol                        # :user :assistant :note :ready :error
    id::Int
    text::String                        # raw — an assistant turn keeps its <think>
    live::Union{Nothing,StreamIO}       # set while a worker still writes to it
    seen::Int                           # bytes of `live` already in `text`
    think::String                       # derived from `text` by `split!`
    answer::String
    thinking::Bool
    label::String                       # the fold's label, "" when no reasoning
    stats::String                       # "[… tok @ …/s]" once the reply is done
    segs::Vector{Seg}                   # the answer as parsed markdown, see gui_md.jl
    model::String                       # who answered: the window can switch models
    attached::String                    # a user turn: terminal text sent along with it
end
Turn(role::Symbol, id::Int, text::AbstractString = "", model::AbstractString = "") =
    split!(Turn(role, id, String(text), nothing, 0, "", "", false, "", "", Seg[], String(model), ""))

function split!(t::Turn)
    t.role === :assistant || return t
    th, t.answer, t.thinking = split_think(t.text)
    t.think = something(th, "")
    # "###" keeps the fold's ID fixed while its label changes, so an opened
    # fold stays open as the count grows.
    t.label = th === nothing ? "" :
        string(!t.thinking ? "Reasoning  " :
               t.live !== nothing ? "Thinking...  " : "Reasoning, cut off  ",
               "(", length(split(t.think)), " words)###think", t.id)
    t.segs = segments(t.answer, t.segs)     # parses only segments that changed
    return t
end

# Pull new bytes from the worker. Only when there are some: a fresh String per
# frame would be pointless garbage, and garbage is GC, and a GC has to wait for
# the worker to leave llama_decode.
function refresh!(t::Turn)
    io = t.live
    io === nothing && return t
    nbytes(io) == t.seen && return t
    t.text = snapshot(io)
    t.seen = ncodeunits(t.text)
    return split!(t)
end

# ── the app ──────────────────────────────────────────────────────────────────
"""
The four faces markdown draws with. `C_NULL` for one that did not load makes
`PushFont` keep the current face and change only the size.
"""
struct Fonts
    regular::Ptr{Cvoid}
    bold::Ptr{Cvoid}
    italic::Ptr{Cvoid}
    mono::Ptr{Cvoid}
    size::Float32
end


mutable struct App
    win::Ptr{W.GLFWwindow}
    ctx::Ptr{G.ImGuiContext}
    io::Ptr{UInt8}                      # ImGuiIO*
    model::String
    state::Symbol                       # :empty :loading :idle :generating :unloading :failed
    closing::Bool
    session::Union{Nothing,LC.ChatSession}
    task::Union{Nothing,Task}
    t_start::Float64
    turns::Vector{Turn}
    next_id::Int
    reply::Union{Nothing,Turn}          # the assistant turn being generated
    last::Union{Nothing,LC.Response}
    n_ctx::Int
    ctx_used::Int
    max_tokens::Int
    buf::Vector{UInt8}                  # the prompt box's bytes, NUL-terminated
    refocus::Bool
    active::Bool                        # the prompt box had keyboard focus last frame
    snap::Bool                          # jump the transcript to the bottom once
    clear::G.ImVec4                     # GL clear colour (the window covers it)
    dim::Base.RefValue{G.ImVec4}
    spacing_y::Float32
    fbw::Base.RefValue{Cint}
    fbh::Base.RefValue{Cint}
    frames::Int
    rects::Dict{Symbol,NTuple{4,Float32}}   # last frame's widget rects, for tests
    fonts::Fonts
    markdown::Bool                      # render replies as markdown, or raw
    sesskw::Dict{Symbol,Any}            # ChatSession keywords, reused by every load
    models::Vector{Tuple{String,Int}}   # what the picker offers: (name, bytes)
    picker_open::Bool
    pad::G.ImVec2                       # style.FramePadding
    title::String                       # what the window title was last set to
    term::Union{Nothing,Term}           # the embedded terminal, once opened
    term_open::Bool                     # shown (it keeps running while hidden)
    term_focus::Bool                    # give it keyboard focus next frame
    term_focused::Bool                  # it had keyboard focus last frame
    term_cmd::Cmd
    term_dir::String
    split::Float32                      # chat's share of the width while the terminal shows
    attach::Base.RefValue{Bool}         # send the terminal's text with the next message
    queued::Bool                        # Enter came while busy: send the box once idle
    pull::Union{Nothing,Tuple{LC.PullProgress,Task}}   # a download in flight
    pull_open::Bool                     # the Pull row is showing
    pullbuf::Vector{UInt8}              # its name box
end

"""
The terminal's default program: this Julia's own executable, without the
banner. It starts without a shell, so a shell alias like
`alias julia='julia --banner=no'` never applies here; the flag has to be on
the command (startup.jl runs too late to turn the banner off).
"""
default_terminal() = Cmd([joinpath(Sys.BINDIR, Base.julia_exename()), "--banner=no"])

function _glfw_error()
    d = Ref{Ptr{UInt8}}(C_NULL)
    c = W.glfwGetError(d)
    return d[] == C_NULL ? "error $c" : unsafe_string(d[])
end

function _check_display()
    isempty(get(ENV, "DISPLAY", "")) || return nothing
    socks = isdir("/tmp/.X11-unix") ?
        [":" * f[2:end] for f in readdir("/tmp/.X11-unix") if occursin(r"^X\d+$", f)] : String[]
    error("no X display. This GLFW build is X11-only, so it needs \$DISPLAY " *
          "(under a Wayland compositor, the Xwayland display). " *
          (isempty(socks) ? "No X server sockets found in /tmp/.X11-unix." :
                            "X servers here: $(join(socks, ", ")) — e.g. ENV[\"DISPLAY\"] = \"$(last(socks))\"."))
end

_ttf(p) = isfile(p) && lowercase(splitext(p)[2]) in (".ttf", ".otf") ? p : nothing
_fc(pattern) = _ttf(try readchomp(`fc-match -f "%{file}" $pattern`) catch; "" end)

"""The system sans-serif via fontconfig, or `nothing` (imgui's built-in font)."""
function default_font()
    p = get(ENV, "LLAMACHAT_FONT", "")
    return isempty(p) ? _fc("sans") : _ttf(p)
end

"""
Load the regular face and its bold, italic and mono siblings (fontconfig's
`sans:bold`, `sans:italic`, `monospace`). Each gets Noto's Symbols2 and Math
merged in as fallbacks, for the arrows, checkmarks and operators models like.
"""
function load_fonts(io::Ptr{UInt8}, font, size::Real)
    font === nothing && return Fonts(C_NULL, C_NULL, C_NULL, C_NULL, Float32(size))
    atlas = unsafe_load(Ptr{Ptr{Cvoid}}(io + G.member_offset("ImGuiIO", "Fonts")))
    extras = filter(p -> p !== nothing && occursin(r"Symbols|Math", basename(p)),
                    [_fc("Noto Sans Symbols2"), _fc("Noto Sans Math")])
    function add(path)
        path === nothing && return C_NULL
        # imgui 1.92 rasterises glyphs on demand, so no glyph ranges: anything
        # the font has, the window can draw.
        f = G.ImFontAtlas_AddFontFromFileTTF(atlas, String(path), Cfloat(size), C_NULL, C_NULL)
        f == C_NULL && (@warn "could not load font $path"; return C_NULL)
        for x in extras             # MergeMode: into the font just added
            cfg = zeros(UInt8, 512)
            GC.@preserve cfg begin
                G.ImFontConfig_ImFontConfig(pointer(cfg))
                unsafe_store!(pointer(cfg) + G.member_offset("ImFontConfig", "MergeMode"), 0x01)
                G.ImFontAtlas_AddFontFromFileTTF(atlas, x, Cfloat(size), pointer(cfg), C_NULL)
            end
        end
        return Ptr{Cvoid}(f)
    end
    regular = add(font)              # first added: the default face
    sib(pattern) = (p = _fc(pattern); p === nothing || p == font ? C_NULL : add(p))
    return Fonts(regular, sib("sans:bold"), sib("sans:italic"), sib("monospace"), Float32(size))
end

"""
    App(; width, height, title, visible, vsync, font, font_size, max_tokens, markdown)

Open the window and bring up both imgui backends. No model yet — `load!` that.
"""
function App(; width::Integer = 960, height::Integer = 720, title::AbstractString = "LlamaChat",
             visible::Bool = true, vsync::Bool = visible,
             font::Union{Nothing,AbstractString} = default_font(), font_size::Real = 18,
             max_tokens::Integer = 4096, markdown::Bool = true,
             terminal::Cmd = default_terminal(), terminal_dir::AbstractString = pwd())
    _check_display()
    # Pick X11 outright rather than let GLFW probe for a Wayland it was not
    # built with.
    W.glfwPlatformSupported(W.GLFW_PLATFORM_X11()) != 0 &&
        W.glfwInitHint(W.GLFW_PLATFORM(), W.GLFW_PLATFORM_X11())
    W.glfwInit() == W.GLFW_TRUE() || error("glfwInit failed: $(_glfw_error())")
    W.glfwWindowHint(W.GLFW_CONTEXT_VERSION_MAJOR(), 3)
    W.glfwWindowHint(W.GLFW_CONTEXT_VERSION_MINOR(), 3)
    W.glfwWindowHint(W.GLFW_OPENGL_PROFILE(), W.GLFW_OPENGL_CORE_PROFILE())
    W.glfwWindowHint(W.GLFW_VISIBLE(), visible ? W.GLFW_TRUE() : W.GLFW_FALSE())
    # Opaque types lose their pointee in DWARF returns: cast once, here.
    win = Ptr{W.GLFWwindow}(W.glfwCreateWindow(width, height, title, C_NULL, C_NULL))
    if win == C_NULL
        err = _glfw_error()
        W.glfwTerminate()
        error("glfwCreateWindow failed: $err")
    end
    W.glfwMakeContextCurrent(win)
    # Without vsync the loop redraws an idle window as fast as the GPU allows.
    vsync && W.glfwSwapInterval(Cint(1))

    ctx = G.ImGui_CreateContext(C_NULL)
    ctx == C_NULL && error("ImGui_CreateContext returned NULL")
    io = Ptr{UInt8}(G.ImGui_GetIO())
    # No imgui.ini: this window has no layout worth remembering, and the
    # default path is the process cwd.
    unsafe_store!(Ptr{Ptr{UInt8}}(io + G.member_offset("ImGuiIO", "IniFilename")), C_NULL)

    sp = Ptr{UInt8}(style_ptr())
    fonts = load_fonts(io, font, font_size)
    unsafe_store!(Ptr{Cfloat}(sp + G.member_offset("ImGuiStyle", "FontSizeBase")), Cfloat(font_size))
    # Opaque window background. The dark style's is 94% alpha, which over a
    # full-viewport window only blends in the GL clear colour.
    bg = sp + G.member_offset("ImGuiStyle", "Colors") + sizeof(G.ImVec4) * Int(G.ImGuiCol_WindowBg)
    unsafe_store!(Ptr{Cfloat}(bg + 12), 1f0)

    G.ImGui_ImplGlfw_InitForOpenGL(win, true) || error("ImGui_ImplGlfw_InitForOpenGL failed")
    G.ImGui_ImplOpenGL3_Init(C_NULL)          || error("ImGui_ImplOpenGL3_Init failed")

    st = unsafe_load(style_ptr())
    return App(win, ctx, io, "", :empty, false, nothing, nothing, 0.0,
               Turn[], 1, nothing, nothing, 0, 0, Int(max_tokens),
               zeros(UInt8, 32 * 1024), true, false, false,
               style_color(G.ImGuiCol_WindowBg), Ref(style_color(G.ImGuiCol_TextDisabled)),
               st.ItemSpacing.y, Ref(Cint(width)), Ref(Cint(height)), 0,
               Dict{Symbol,NTuple{4,Float32}}(), fonts, markdown,
               Dict{Symbol,Any}(), list_chat_models(), false, st.FramePadding, String(title),
               nothing, false, false, false, terminal, String(terminal_dir), 0.5f0, Ref(false),
               false, nothing, false, zeros(UInt8, 256))
end

"""ollama names default to the `:latest` tag: `qwen3-coder` is `qwen3-coder:latest`."""
same_model(a::AbstractString, b::AbstractString) =
    a == b || (occursin(':', a) ? a : a * ":latest") == (occursin(':', b) ? b : b * ":latest")

"""Generative models in the ollama store, largest first. Embedding models have no
generation head, so they are left out."""
list_chat_models() =
    try
        [(n, sz) for (n, sz) in LC.list_models() if !occursin("embed", lowercase(n))]
    catch e
        e isa InterruptException && rethrow()
        Tuple{String,Int}[]
    end

function push_turn!(app::App, role::Symbol, text::AbstractString = "", model::AbstractString = "")
    t = Turn(role, app.next_id, text, model)
    app.next_id += 1
    push!(app.turns, t)
    return t
end

"""
    load!(app, model; kwargs...)

Load `model` on a worker thread; `kwargs` are `ChatSession`'s and are kept for
every later load (the model picker reuses them). Call after `App()`: the planner
measures free VRAM when the load starts, and the GL context is part of that.
"""
function load!(app::App, model::AbstractString; kwargs...)
    isempty(kwargs) || (app.sesskw = Dict{Symbol,Any}(kwargs))
    switch!(app, model) || error("cannot load $model while the window is $(app.state)")
    return app
end

"""
    switch!(app, model) -> Bool

Unload the current model, if any, then load `model` — both in one task on a
worker thread, in that order: the planner sizes the new load from the VRAM
the old one just gave back. `false` (nothing happens) unless nothing is
loading, generating or unloading.

A new model starts a new conversation. Its chat template and KV cache are its
own, so the turns above stay on screen but are not sent to it.
"""
function switch!(app::App, model::AbstractString)
    (app.state in (:empty, :idle, :failed) && !app.closing) || return false
    old, prev = app.session, app.model
    app.session = nothing
    app.model = String(model)
    app.n_ctx = app.ctx_used = 0
    app.last = nothing
    old === nothing || push_turn!(app, :note,
        "Switched from $prev to $(app.model). The new model starts a new conversation; " *
        "it does not see the turns above.")
    log = StreamIO()
    note = push_turn!(app, :note)
    note.live = log
    app.state = :loading
    app.t_start = time()
    app.snap = true
    name, kw = app.model, app.sesskw
    app.task = Threads.@spawn begin
        old === nothing || LC.close!(old)
        LC.ChatSession(name; log = log, kw...)
    end
    return true
end

"""
    unload!(app) -> Bool

Free the model (weights and context) on a worker thread and keep the window.
Pick a model to load another.
"""
function unload!(app::App)
    (app.state === :idle && app.session !== nothing && !app.closing) || return false
    old = app.session
    app.session = nothing
    app.state = :unloading
    app.t_start = time()
    app.task = Threads.@spawn LC.close!(old)
    return true
end

"""
    send!(app, prompt) -> Bool

Start a reply to `prompt` on a worker thread. `false` (and nothing happens)
unless the session is idle.
"""
function send!(app::App, prompt::AbstractString; context::AbstractString = "")
    (app.state === :idle && !app.closing) || return false
    s = app.session
    s.cancel[] = false                  # idle: nothing is generating to race with
    shown = String(prompt)
    # The model gets the terminal text; the transcript shows the prompt and
    # folds the attachment under it.
    p = isempty(context) ? shown :
        "Here is my terminal (its last $(count(==('\n'), context) + 1) lines):\n```\n$context\n```\n\n$shown"
    push_turn!(app, :user, shown).attached = String(context)
    io = StreamIO()
    app.reply = push_turn!(app, :assistant, "", app.model)
    app.reply.live = io
    app.state = :generating
    app.t_start = time()
    app.snap = true
    mt = app.max_tokens
    app.task = Threads.@spawn LC.chat(s, p; io = io, stream = true, max_tokens = mt)
    return true
end

"""Stop the reply being generated, at the next token. See `LlamaChat.cancel!`."""
function stop!(app::App)
    app.state === :generating && LC.cancel!(app.session)   # an Atomic store, nothing else
    return app
end

"""Forget the conversation, keep the model. Only while idle."""
function new_chat!(app::App)
    app.state === :idle || return false
    LC.reset!(app.session)
    empty!(app.turns)
    app.last = nothing
    app.ctx_used = 0
    return true
end

_unwrap(e) = e isa TaskFailedException ? _unwrap(e.task.exception) : e

"""
    start_pull!(app, name) -> Bool

Download `name` from ollama's registry on a worker thread (see
`LlamaChat.pull`), with the progress bar in the Pull row. One at a time.
"""
function start_pull!(app::App, name::AbstractString)
    app.pull === nothing || return false
    n = String(strip(name))
    isempty(n) && return false
    p = LC.PullProgress(n)
    app.pull = (p, Threads.@spawn LC.pull(n; progress = p, io = devnull))
    app.pull_open = true
    app.refocus = true                     # keep chatting while it downloads
    return true
end

function poll_pull!(app::App)
    app.pull === nothing && return
    p, t = app.pull
    istaskdone(t) || return
    app.pull = nothing
    res = try fetch(t) catch e; _unwrap(e) end
    if res isa Exception
        push_turn!(app, :error, "download failed: " * sprint(showerror, res))
    else
        app.models = list_chat_models()
        push_turn!(app, :ready, "Downloaded $(p.name)  ·  $(LC._human(p.total[]))  ·  " *
                                "$(round(time() - p.t0; digits = 1)) s. Pick it from the model list.")
        app.pull_open = false
        app.refocus = true
    end
    app.snap = true
end

# Collect a finished worker. The only place the session changes hands back.
function poll!(app::App)
    # The child keeps running while the panel is hidden; reading it every frame
    # keeps a full pty buffer from blocking it.
    app.term === nothing || pump!(app.term)
    poll_pull!(app)
    t = app.task
    t === nothing && return app
    if app.reply !== nothing
        refresh!(app.reply)
    elseif !isempty(app.turns)
        refresh!(app.turns[end])        # the load log
    end
    istaskdone(t) || return app
    app.task = nothing
    res = try
        fetch(t)
    catch e
        _unwrap(e)
    end

    if app.state === :loading
        log = app.turns[end]
        refresh!(log)
        log.live = nothing
        if res isa LC.ChatSession
            app.session = res
            app.n_ctx = res.n_ctx
            app.ctx_used = res.n_past
            app.state = :idle
            # "loading qwen3:4b … ok (1.6s, …)" reads as still loading. Replace
            # it with a line that says what is true now; keep anything else the
            # loader said (a partial-offload note, say).
            rest = [l for l in split(log.text, '\n') if !isempty(strip(l)) && !startswith(l, "loading ")]
            isempty(rest) ? pop!(app.turns) : (log.text = join(rest, '\n'))
            push_turn!(app, :ready, "$(app.model) is ready  ·  $(LC.placement(res))  ·  " *
                                    "$(res.n_ctx) ctx  ·  loaded in $(round(time() - app.t_start; digits = 1)) s")
        else
            log.text = rstrip(log.text)
            push_turn!(app, :error, "load failed: " * sprint(showerror, res))
            app.state = :failed
        end
    elseif app.state === :unloading
        push_turn!(app, :note, "Unloaded $(app.model). Pick a model above to load one.")
        app.model = ""
        app.n_ctx = app.ctx_used = 0
        app.last = nothing
        app.state = :empty
    elseif app.state === :generating
        r = app.reply
        refresh!(r)
        r.live = nothing
        r.text = rstrip(r.text)         # `chat` ends a stream with a newline
        split!(r)
        app.reply = nothing
        if res isa LC.Response
            app.last = res
            r.stats = LC._stats_line(res)
        else
            # `chat` has already put the session back the way it was. A reply
            # that never produced a byte has nothing worth a header.
            isempty(r.text) && app.turns[end] === r && pop!(app.turns)
            push_turn!(app, :error, sprint(showerror, res))
        end
        app.ctx_used = app.session.n_past
        app.state = :idle
    end
    return app
end

# ── drawing ──────────────────────────────────────────────────────────────────

const C_READY = vec4(0.40, 0.85, 0.45)
const C_BUSY  = vec4(0.95, 0.75, 0.30)
const C_GEN   = vec4(0.45, 0.70, 1.00)
const C_OFF   = vec4(0.55, 0.55, 0.55)

"""
    indicator(app) -> (colour, word, busy)

What the window is doing, as the status light shows it. `busy` pulses the light.
"""
function indicator(app::App)
    app.closing && return (C_BUSY, "closing", true)
    st = app.state
    st === :idle       && return (C_READY, "ready", false)
    st === :loading    && return (C_BUSY, "loading", true)
    st === :generating && return (C_GEN, "replying", true)
    st === :unloading  && return (C_BUSY, "unloading", true)
    st === :failed     && return (C_ERR[], "load failed", false)
    return (C_OFF, "no model loaded", false)
end

"""The details after the status light: time in the current step, context, last speed."""
function status_text(app::App)
    parts = String[]
    st = app.state
    app.queued && push!(parts, st === :loading ? "your message sends once it is loaded" :
                                                 "your message sends when this reply ends (Stop sends it now)")
    st in (:loading, :generating, :unloading) &&
        push!(parts, "$(round(time() - app.t_start; digits = 1)) s")
    app.n_ctx > 0 && push!(parts, "$(app.ctx_used) / $(app.n_ctx) ctx")
    if st === :idle && app.last !== nothing
        r = app.last
        tps = r.t_gen > 0 ? round(r.n_gen / r.t_gen; digits = 1) : 0.0
        push!(parts, "last reply $(r.n_gen) tok · $(tps) tok/s" *
                     (r.stop === :eog ? "" : " · stopped: $(r.stop)"))
    end
    return join(parts, "  ·  ")
end

"""What Enter does right now, shown inside the empty prompt box."""
function prompt_hint(app::App)
    app.closing && return "Closing..."
    st, m = app.state, app.model
    st === :empty      && return "Pick a model from the list above to start."
    st === :loading    && return "Loading $m... you can type now; Enter sends once it is ready."
    st === :unloading  && return "Unloading..."
    st === :failed     && return "That model did not load. Pick another from the list above."
    st === :generating && return "$m is replying. Type the next message: Enter sends it when this one ends."
    app.attach[] && return "Message $m, with the terminal attached. Enter sends."
    return "Message $m. Enter sends, Ctrl+Enter adds a newline."
end

function rect!(app::App, key::Symbol)
    lo = G.ImGui_GetItemRectMin(); hi = G.ImGui_GetItemRectMax()
    app.rects[key] = (lo.x, lo.y, hi.x, hi.y)
end

function picker!(app::App)
    G.ImGui_SetNextItemWidth(app.fonts.size * 13)
    G.ImGui_BeginDisabled(!(app.state in (:empty, :idle, :failed)) || app.closing)
    preview = isempty(app.model) ? "Load a model..." : app.model
    if G.ImGui_BeginCombo("##model", preview, Cint(G.ImGuiComboFlags_HeightLarge))
        # Re-read the store each time the list opens: `ollama pull` in another
        # terminal shows up without restarting the window.
        app.picker_open || (app.models = list_chat_models(); app.picker_open = true)
        isempty(app.models) && colored(() -> text!("No models yet: Pull... downloads one"), app.dim)
        for (k, (name, bytes)) in enumerate(app.models)
            here = same_model(name, app.model) && app.session !== nothing
            G.ImGui_PushID(Cint(k))
            if G.ImGui_Selectable(name, here, Cint(0), ZERO)
                here || switch!(app, name)
                app.refocus = true
            end
            here && G.ImGui_SetItemDefaultFocus()
            G.ImGui_SameLine(0f0, app.fonts.size * 2)
            colored(() -> text!(LC._human(bytes)), app.dim)
            G.ImGui_PopID()
        end
        G.ImGui_EndCombo()
    else
        app.picker_open = false
    end
    rect!(app, :model)
    G.ImGui_EndDisabled()
end

function light!(app::App)
    col, word, busy = indicator(app)
    if busy                         # pulse while something is in flight
        col = G.ImVec4(col.x, col.y, col.z, Cfloat(0.55 + 0.45 * cospi(2 * time())))
    end
    G.ImGui_AlignTextToFramePadding()
    p = G.ImGui_GetCursorScreenPos()
    h = G.ImGui_GetFrameHeight()
    r = app.fonts.size * 0.28f0
    G.ImDrawList_AddCircleFilled(G.ImGui_GetWindowDrawList(), Ref(vec2(p.x + r, p.y + h / 2)),
                                 r, G.ImGui_GetColorU32(Ref(col)), Cint(0))
    G.ImGui_Dummy(Ref(vec2(2r, G.ImGui_GetTextLineHeight())))
    G.ImGui_SameLine(0f0, -1f0)
    colored(() -> text!(word), Ref(col))
end

function status_bar!(app::App)
    picker!(app)
    G.ImGui_SameLine(0f0, -1f0)
    G.ImGui_BeginDisabled(app.state !== :idle || app.closing)
    G.ImGui_Button("Unload", ZERO) && (unload!(app); app.refocus = true)
    rect!(app, :unload)
    G.ImGui_EndDisabled()
    G.ImGui_SameLine(0f0, -1f0)
    if G.ImGui_Button(app.pull !== nothing ? "Pull (running)" : "Pull...", ZERO)
        app.pull_open = !app.pull_open
        app.pull_open || (app.refocus = true)      # closing the row hands the keyboard back
    end
    rect!(app, :pull_toggle)
    G.ImGui_SameLine(0f0, -1f0)
    G.ImGui_BeginDisabled(app.state !== :generating)
    # A click takes keyboard focus off the prompt; give it straight back.
    G.ImGui_Button("Stop", ZERO) && (stop!(app); app.refocus = true)
    rect!(app, :stop)
    G.ImGui_EndDisabled()
    G.ImGui_SameLine(0f0, -1f0)
    G.ImGui_BeginDisabled(app.state !== :idle || app.closing)
    G.ImGui_Button("New chat", ZERO) && (new_chat!(app); app.refocus = true)
    rect!(app, :new_chat)
    G.ImGui_EndDisabled()
    G.ImGui_SameLine(0f0, -1f0)
    if G.ImGui_Button(app.term_open ? "Hide terminal" : "Terminal", ZERO)
        toggle_terminal!(app)
    end
    rect!(app, :terminal)
    if app.term !== nothing
        G.ImGui_SameLine(0f0, -1f0)
        G.ImGui_Checkbox("Attach", app.attach) && (app.refocus = true)   # tick it, then type
        rect!(app, :attach)
        if G.ImGui_BeginItemTooltip()
            text!("Send the terminal's last 120 lines with your next message.")
            G.ImGui_EndTooltip()
        end
    end
    G.ImGui_SameLine(0f0, app.fonts.size)
    light!(app)
    # Only SameLine into something: an open SameLine with nothing after it
    # puts the transcript on this line instead.
    st = status_text(app)
    isempty(st) && return
    G.ImGui_SameLine(0f0, app.fonts.size)
    colored(() -> text!(st), app.dim)
end

const PULL_FLAGS = flags(G.ImGuiInputTextFlags_EnterReturnsTrue)

"""The Pull row: a name box and Download, or the running download's progress and Cancel."""
function pull_row!(app::App)
    if app.pull === nothing
        G.ImGui_SetNextItemWidth(app.fonts.size * 14)
        b = app.pullbuf
        go = GC.@preserve b G.ImGui_InputText("##pullname", pointer(b), length(b), PULL_FLAGS, C_NULL, C_NULL)
        rect!(app, :pull_name)
        if b[1] == 0x00 && !G.ImGui_IsItemActive()
            lo = G.ImGui_GetItemRectMin()
            h = "model:tag, e.g. qwen3:0.6b"
            GC.@preserve h G.ImDrawList_AddText(G.ImGui_GetWindowDrawList(),
                Ref(vec2(lo.x + app.pad.x, lo.y + app.pad.y)),
                G.ImGui_GetColorU32(Cint(G.ImGuiCol_TextDisabled), 1f0), pointer(h), pointer(h) + sizeof(h))
        end
        G.ImGui_SameLine(0f0, -1f0)
        go |= G.ImGui_Button("Download", ZERO)
        rect!(app, :pull_go)
        G.ImGui_SameLine(0f0, app.fonts.size)
        colored(() -> text!("names and tags: ollama.com/library  ·  saved in $(LC.pull_root())"), app.dim)
        name = GC.@preserve b unsafe_string(pointer(b))
        if go && start_pull!(app, name)
            fill!(b, 0x00)
        end
    else
        p, _ = app.pull
        frac = p.total[] > 0 ? Float32(p.done[] / p.total[]) : 0f0
        G.ImGui_ProgressBar(frac, Ref(vec2(app.fonts.size * 32, 0)), LC.pull_status(p))
        rect!(app, :pull_bar)
        G.ImGui_SameLine(0f0, -1f0)
        G.ImGui_Button("Cancel", ZERO) && LC.cancel!(p)
        rect!(app, :pull_cancel)
    end
end

function turn!(app::App, t::Turn, first::Bool)
    if t.role === :user
        first || (G.ImGui_Spacing(); G.ImGui_Separator(); G.ImGui_Spacing())
        colored(() -> text!("You"), C_USER)
        text!(t.text)
        if !isempty(t.attached)
            colored(app.dim) do
                n = count(==('\n'), t.attached) + 1
                if G.ImGui_TreeNodeEx("terminal  ($n lines attached)###att$(t.id)", THINK_FLAGS)
                    G.ImGui_PushFont(app.fonts.mono, app.fonts.size)
                    text!(t.attached)
                    G.ImGui_PopFont()
                end
            end
        end
    elseif t.role === :assistant
        G.ImGui_Spacing()
        colored(() -> text!(t.model), C_BOT)
        if !isempty(t.label)
            # Reasoning folds away, dimmed, closed by default; the answer below
            # is what the reply is.
            colored(app.dim) do
                if G.ImGui_TreeNodeEx(t.label, THINK_FLAGS)
                    G.ImGui_Indent(0f0)
                    text!(t.think)
                    G.ImGui_Unindent(0f0)
                end
            end
        end
        app.markdown ? draw_markdown!(app, t) : text!(t.answer)
        if isempty(t.answer) && t.live === nothing && !isempty(t.stats)
            colored(() -> text!("(no answer: the reply stopped before its reasoning ended)"), app.dim)
        end
        if !isempty(t.stats)
            colored(() -> text!(t.stats), app.dim)
            G.ImGui_SameLine(0f0, -1f0)
            if G.ImGui_SmallButton("copy###copy$(t.id)")
                G.ImGui_SetClipboardText(isempty(t.answer) ? t.text : t.answer)
            end
        end
    elseif t.role === :note
        colored(() -> text!(t.text), app.dim)
    elseif t.role === :ready
        colored(() -> text!(t.text), Ref(C_READY))
    else
        colored(() -> text!(t.text), C_ERR)
    end
    return nothing
end

function transcript!(app::App, height::Float32)
    G.ImGui_BeginChild("transcript", Ref(vec2(0, -height)), Cint(G.ImGuiChildFlags_Borders), Cint(0))
    G.ImGui_PushTextWrapPos(0f0)
    for (i, t) in enumerate(app.turns)
        turn!(app, t, i == 1)
    end
    G.ImGui_PopTextWrapPos()
    # Follow the stream only while the reader is already at the bottom; a
    # send jumps there regardless.
    if app.snap || G.ImGui_GetScrollY() >= G.ImGui_GetScrollMaxY() - 1
        G.ImGui_SetScrollHereY(1f0)
        app.snap = false
    end
    G.ImGui_EndChild()
    rect!(app, :transcript)
end

prompt_text(app::App) = GC.@preserve app unsafe_string(pointer(app.buf))

"""
Enter, pressed with only Super and/or Alt held: an Enter imgui ignores.

The prompt's Enter is an imgui `Shortcut`, which matches only with *no*
modifier down, so Super or Alt held made it do nothing while characters still
typed. Neither has to be really held: a compositor keybinding can take Super's
release (Hyprland over Xwayland), and GLFW then reports Super down until it is
pressed again. The box filled and would not send. Ctrl and Shift keep their
meaning (Ctrl+Enter, Shift+Enter: a newline).
"""
function _stale_mod_enter(app::App)
    G.ImGui_IsKeyPressed(G.ImGuiKey_Enter, true) || G.ImGui_IsKeyPressed(G.ImGuiKey_KeypadEnter, true) ||
        return false
    k(f) = unsafe_load(Ptr{Bool}(app.io + G.member_offset("ImGuiIO", f)))
    return (k("KeySuper") || k("KeyAlt")) && !k("KeyCtrl") && !k("KeyShift")
end

"""
Send what the prompt box holds, with the terminal's text if Attach is ticked.
The box is emptied only by a send that happened; a refused one keeps the text.
"""
function send_box!(app::App)
    p = prompt_text(app)
    isempty(strip(p)) && return false
    ctx = app.attach[] && app.term !== nothing ? term_text(app.term) : ""
    send!(app, p; context = ctx) || return false
    fill!(app.buf, 0x00)
    app.attach[] = false            # one message at a time: tick it again to resend
    return true
end

function prompt!(app::App, height::Float32)
    # Enter while the model loaded or replied queued the box; it goes now.
    if app.queued
        if app.state === :idle && !app.closing
            app.queued = false
            # imgui keeps its own copy of an active box's text. Let go of the
            # box before emptying ours, or the old text would stay on screen
            # and come back on the next keystroke.
            app.active && (G.ImGui_ClearActiveID(); app.refocus = true)
            send_box!(app)
        elseif !(app.state in (:loading, :generating))
            app.queued = false      # the load failed or the model went: nothing to send to
        end
    end
    # Focus is requested before the item it applies to.
    if app.refocus
        G.ImGui_SetKeyboardFocusHere(Cint(0))
        app.refocus = false
    end
    b = app.buf
    entered = GC.@preserve b G.ImGui_InputTextMultiline(
        "##prompt", pointer(b), length(b), Ref(vec2(-1, height)), PROMPT_FLAGS, C_NULL, C_NULL)
    rect!(app, :prompt)
    if !entered && G.ImGui_IsItemActive() && _stale_mod_enter(app)
        # imgui saw Super+Enter or Alt+Enter and did nothing: let go of the box
        # as its own Enter would have, so emptying it below reaches the screen.
        G.ImGui_ClearActiveID()
        entered = true
    end
    app.active = G.ImGui_IsItemActive()
    if b[1] == 0x00 && !app.picker_open
        # The box is a child window that paints its own background over this
        # one's draw list, so the hint goes on the foreground list.
        lo = G.ImGui_GetItemRectMin()
        h = prompt_hint(app)
        GC.@preserve h G.ImDrawList_AddText(G.ImGui_GetForegroundDrawList(),
            Ref(vec2(lo.x + app.pad.x, lo.y + app.pad.y)),
            G.ImGui_GetColorU32(Cint(G.ImGuiCol_TextDisabled), 1f0), pointer(h), pointer(h) + sizeof(h))
    end
    if entered
        # Enter deactivates the box; take focus back whether or not this sent,
        # so typing carries on.
        app.refocus = true
        if app.state in (:loading, :generating) && !app.closing
            # Busy: keep the text and send it the moment the model is free.
            # Until then it can still be edited; Stop sends it at once.
            app.queued = !isempty(strip(prompt_text(app)))
        else
            send_box!(app)
        end
    end
end

"""Open the terminal (starting it the first time) or hide it; hiding keeps it running."""
function toggle_terminal!(app::App)
    if app.term_open
        app.term_open = false
        app.refocus = true
    else
        app.term === nothing && (app.term = Term(app.term_cmd; dir = app.term_dir))
        app.term_open = true
        app.term_focus = true
    end
    return app
end

"""The bar between chat and terminal: drag to share the width differently."""
function splitter!(app::App, sw::Float32, avail)
    G.ImGui_InvisibleButton("##split", Ref(vec2(sw, avail.y)), Cint(0))
    rect!(app, :split)
    if G.ImGui_IsItemActive()
        dx = unsafe_load(Ptr{Float32}(app.io + G.member_offset("ImGuiIO", "MouseDelta")))
        app.split = clamp(app.split + dx / avail.x, 0.2f0, 0.8f0)
    end
    (G.ImGui_IsItemHovered(Cint(0)) || G.ImGui_IsItemActive()) &&
        G.ImGui_SetMouseCursor(Cint(G.ImGuiMouseCursor_ResizeEW))
    lo = G.ImGui_GetItemRectMin(); hi = G.ImGui_GetItemRectMax()
    x = (lo.x + hi.x) / 2
    G.ImDrawList_AddLine(G.ImGui_GetWindowDrawList(), Ref(vec2(x, lo.y)), Ref(vec2(x, hi.y)),
                         G.ImGui_GetColorU32(Cint(G.ImGuiCol_Separator), 1f0), 1f0)
end

function ui!(app::App)
    vp = unsafe_load(G.ImGui_GetMainViewport())
    G.ImGui_SetNextWindowPos(Ref(vp.WorkPos), Cint(G.ImGuiCond_Always), ZERO)
    G.ImGui_SetNextWindowSize(Ref(vp.WorkSize), Cint(G.ImGuiCond_Always))
    G.ImGui_Begin("LlamaChat", C_NULL, WINDOW_FLAGS)
    status_bar!(app)
    (app.pull_open || app.pull !== nothing) && pull_row!(app)
    input_h = Float32(G.ImGui_GetFrameHeight() + 3 * G.ImGui_GetTextLineHeight())
    if app.term_open && app.term !== nothing
        avail = G.ImGui_GetContentRegionAvail()
        sw = 8f0
        left = clamp(app.split * avail.x, 240f0, max(240f0, avail.x - 240f0 - sw))
        G.ImGui_BeginChild("##chat", Ref(vec2(left, avail.y)), Cint(0), Cint(0))
        transcript!(app, input_h + app.spacing_y)
        prompt!(app, input_h)
        G.ImGui_EndChild()
        G.ImGui_SameLine(0f0, 0f0)
        splitter!(app, sw, avail)
        G.ImGui_SameLine(0f0, 0f0)
        terminal_panel!(app, avail.x - left - sw, avail.y)
    else
        transcript!(app, input_h + app.spacing_y)
        prompt!(app, input_h)
    end
    G.ImGui_End()
end

"""
    frame!(app; swap = true)

One frame: events, imgui NewFrame, the UI, Render, draw, swap. The first frame
of a context draws nothing — imgui settles its font atlas — which is upstream
behaviour.
"""
function frame!(app::App; swap::Bool = true)
    title = isempty(app.model) ? "LlamaChat" : "LlamaChat · $(app.model) · $(indicator(app)[2])"
    title == app.title || (W.glfwSetWindowTitle(app.win, title); app.title = title)
    W.glfwPollEvents()
    G.ImGui_ImplOpenGL3_NewFrame(); G.ImGui_ImplGlfw_NewFrame(); G.ImGui_NewFrame()
    st = _RECOVERY
    GC.@preserve st G.ImGui_ErrorRecoveryStoreState(pointer(st))
    try
        ui!(app)
    catch
        # A frame that throws half way leaves Begin/Child/Push stacks open, and
        # the next NewFrame would assert ("Forgot to call Render()") and abort
        # the process. Unwind imgui to where this frame started, end the frame,
        # and let the exception go on to the caller.
        _recover!(app)
        rethrow()
    end
    G.ImGui_Render()
    W.glfwGetFramebufferSize(app.win, app.fbw, app.fbh)
    gl_viewport(app.fbw[], app.fbh[])
    gl_clear_color(app.clear)
    gl_clear()
    G.ImGui_ImplOpenGL3_RenderDrawData(G.ImGui_GetDrawData())
    swap && W.glfwSwapBuffers(app.win)
    app.frames += 1
    return app
end

const _RECOVERY = zeros(UInt8, 64)          # ImGuiErrorRecoveryState is 22 bytes

function _recover!(app::App)
    flag = Ptr{Bool}(app.io + G.member_offset("ImGuiIO", "ConfigErrorRecoveryEnableAssert"))
    old = unsafe_load(flag)
    unsafe_store!(flag, false)              # recovering is what this is for: do not assert
    st = _RECOVERY
    try
        GC.@preserve st G.ImGui_ErrorRecoveryTryToRecoverState(pointer(st))
        G.ImGui_EndFrame()
    finally
        unsafe_store!(flag, old)
    end
end

"""
Let Julia's event loop turn. Sockets, timers and process exits — everything
`Downloads` and `Base.Process` wait on — are serviced only when the main task
yields, and the render loop never blocks. Without this a pull sat at "fetching
manifest" for as long as the window was open.

`yield()` runs the loop at full speed (7.1 MiB/s measured, against 2.3 for one
`process_events()` a frame), but a yield can also hand the thread to a queued
task. On an interactive thread that cannot be a `Threads.@spawn` task — a
reply generating — which would otherwise run on the render thread until it
finished. Julia ≥ 1.12 runs the main task on one with plain `-t N`.
"""
_tick() = Threads.threadpool() === :interactive ? yield() : Base.process_events()

"""Collect a finished worker, draw a frame, let the event loop turn."""
step!(app::App; swap::Bool = true) = (poll!(app); frame!(app; swap = swap); _tick(); app)

"""
    capture!(app) -> (pixels, width, height)

Draw a frame and read it back before it is swapped: RGBA, bottom row first.
"""
function capture!(app::App)
    step!(app; swap = false)
    gl_finish()
    w, h = Int(app.fbw[]), Int(app.fbh[])
    px = gl_read(w, h)
    W.glfwSwapBuffers(app.win)
    return px, w, h
end

"""
    close!(app)

Stop any reply, wait for the worker, free the model, close the window. Safe to
call more than once.
"""
function close!(app::App)
    app.closing = true
    if (t = app.task) !== nothing
        app.session !== nothing && LC.cancel!(app.session)
        res = try fetch(t) catch e; _unwrap(e) end
        res isa LC.ChatSession && (app.session = res)   # a load still in flight
        app.task = nothing
    end
    if app.session !== nothing
        LC.close!(app.session)
        app.session = nothing
    end
    if app.term !== nothing
        close!(app.term)
        app.term = nothing
    end
    if app.pull !== nothing
        LC.cancel!(app.pull[1])          # finished ranges stay on disk; a later pull resumes
        try wait(app.pull[2]) catch end
        app.pull = nothing
    end
    if app.win != C_NULL
        G.ImGui_ImplOpenGL3_Shutdown()
        G.ImGui_ImplGlfw_Shutdown()
        G.ImGui_DestroyContext(app.ctx)
        W.glfwDestroyWindow(app.win)
        W.glfwTerminate()
        app.win = C_NULL
        app.ctx = C_NULL
    end
    return nothing
end

const _APP_KW = (:width, :height, :title, :visible, :vsync, :font, :font_size, :max_tokens, :markdown,
                 :terminal, :terminal_dir)

"""
    run(model; kwargs...)

`LlamaChat.gui`'s body. Window keywords go to `App`, the rest to `ChatSession`;
`max_frames > 0` ends the loop after that many frames (how the tests run it).
"""
function run(model::Union{Nothing,AbstractString}; max_frames::Integer = 0, kwargs...)
    Threads.nthreads() >= 2 ||
        error("LlamaChat.gui generates on a worker thread while this one draws: " *
              "start Julia with `julia -t 2` (or more)")
    appkw  = Dict{Symbol,Any}(:title => model === nothing ? "LlamaChat" : "LlamaChat · $model")
    sesskw = Dict{Symbol,Any}()
    for (k, v) in kwargs
        (k in _APP_KW ? appkw : sesskw)[k] = v
    end
    app = App(; appkw...)
    try
        if model === nothing
            app.sesskw = sesskw             # kept for whatever the picker loads
        else
            load!(app, model; sesskw...)
        end
        while true
            if !app.closing && (W.glfwWindowShouldClose(app.win) != 0 ||
                                (max_frames > 0 && app.frames >= max_frames))
                # Stop a reply in flight; a load cannot be interrupted, so the
                # window stays up, saying so, until it lands.
                app.closing = true
                stop!(app)
            end
            app.closing && app.task === nothing && break
            step!(app)
        end
    catch e
        e isa InterruptException || rethrow()
    finally
        close!(app)
    end
    return nothing
end

end # module GUI
