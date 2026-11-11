# The embedded terminal. Included by gui.jl, inside `module GUI`.
#
# Three pieces, all driven from this file:
#
#   * a pty — libc's posix_openpt/grantpt/unlockpt, with the child started as
#     `setsid --ctty --wait <cmd>` on the slave side. setsid makes the slave the
#     child's controlling terminal, so job control, Ctrl-C and SIGWINCH behave as
#     in any terminal, and this process never calls fork() (unsafe with threads);
#   * libvterm (lib/gui/Libvterm.jl, RepliBuild-wrapped from packages/libvterm):
#     bytes in, a grid of cells out. Its screen callbacks mark damaged rows,
#     track the cursor, and hand over each line that scrolls off the top;
#   * imgui: the grid is drawn with the window's draw list in the mono face,
#     and keys go back through libvterm's keyboard encoder to the pty.
#
# EVERYTHING HERE RUNS ON THE MAIN THREAD. The pty master is non-blocking and
# read once per frame. A worker blocked in read() would sit in a ccall — not a
# GC safepoint — for as long as the child stays quiet, and every collection in
# the process would wait for it. Polling costs one syscall a frame and keeps
# libvterm's callbacks on the render thread with the rest of the drawing.

include(joinpath(LIBDIR, "Libvterm.jl")); import .Libvterm; const V = Libvterm

const O_RDWR, O_NOCTTY, O_NONBLOCK, O_CLOEXEC = Cint(0o2), Cint(0o400), Cint(0o4000), Cint(0o2000000)
const F_SETFD, F_GETFL, F_SETFL, FD_CLOEXEC = Cint(2), Cint(3), Cint(4), Cint(1)
const TIOCSWINSZ = Culong(0x5414)
const EAGAIN, EINTR = 11, 4
const SCROLLBACK_MAX = 10_000
const WIDE_TAIL = 0xffffffff        # libvterm's marker for the right half of a wide cell

struct WinSize
    row::UInt16
    col::UInt16
    xpixel::UInt16
    ypixel::UInt16
end

"""One run of identically styled text on a terminal row, placed by column."""
struct Run
    col::Int32
    text::String
    fg::UInt32                      # ImU32
    bg::UInt32                      # ImU32; 0 = the panel's background
    under::Bool
end

mutable struct Term
    vt::Ptr{V.VTerm}
    screen::Ptr{V.VTermScreen}
    callbacks::Base.RefValue{V.VTermScreenCallbacks}
    fd::Cint                        # pty master, non-blocking; -1 once closed
    proc::Union{Nothing,Base.Process}
    cmd::Cmd
    dir::String
    rows::Int
    cols::Int
    lines::Vector{Vector{Run}}      # one per screen row, rebuilt when dirty
    dirty::BitVector
    scrollback::Vector{String}      # lines pushed off the top, oldest first
    view::Int                       # lines scrolled back; 0 = following the live screen
    cursor::NTuple{2,Int}           # row, col
    cursor_visible::Bool
    altscreen::Bool
    exited::Bool
    pending::Vector{UInt8}          # bytes for the pty a write could not take yet
    rbuf::Vector{UInt8}
    obuf::Vector{UInt8}
    cell::Base.RefValue{V.VTermScreenCell}
    fg::UInt32                      # default colours, ImU32
    bg::UInt32
    cw::Float32                     # cell width and height at `fsize`
    lh::Float32
    fsize::Float32
    bytes_in::Int
end

_term(user::Ptr{Cvoid}) = unsafe_pointer_to_objref(user)::Term

# ── libvterm screen callbacks (C → Julia, on this thread, inside input_write) ─

function _damage(rect::V.VTermRect, user::Ptr{Cvoid})::Cint
    t = _term(user)
    # Bounded by the flags, not t.rows: this runs inside C (vterm_set_size
    # calls it), and an exception must never unwind through libvterm's frames.
    for r in max(0, rect.start_row):min(length(t.dirty), rect.end_row) - 1
        t.dirty[r + 1] = true
    end
    return Cint(1)
end

function _movecursor(pos::V.VTermPos, ::V.VTermPos, ::Cint, user::Ptr{Cvoid})::Cint
    _term(user).cursor = (Int(pos.row), Int(pos.col))
    return Cint(1)
end

function _settermprop(prop::Cint, val::Ptr{Cvoid}, user::Ptr{Cvoid})::Cint
    t = _term(user)
    on = unsafe_load(Ptr{Cint}(val)) != 0          # VTermValue.boolean
    if prop == Cint(V.VTERM_PROP_CURSORVISIBLE)
        t.cursor_visible = on
    elseif prop == Cint(V.VTERM_PROP_ALTSCREEN)
        t.altscreen = on
        t.view = 0
        fill!(t.dirty, true)
    end
    return Cint(1)
end

_bell(::Ptr{Cvoid})::Cint = Cint(1)

function _sb_clear(user::Ptr{Cvoid})::Cint
    t = _term(user)
    empty!(t.scrollback)
    t.view = 0
    return Cint(1)
end

function _cells_text(cells::Ptr{V.VTermScreenCell}, n::Integer)
    io = IOBuffer()
    for i in 1:n
        c = unsafe_load(cells, i)
        for u in c.chars
            (u == 0 || u == WIDE_TAIL) && break
            print(io, Char(u))
        end
        c.chars[1] == 0 && print(io, ' ')
    end
    return rstrip(String(take!(io)))
end

function _sb_pushline4(cols::Cint, cells::Ptr{V.VTermScreenCell}, ::Bool, user::Ptr{Cvoid})::Cint
    t = _term(user)
    push!(t.scrollback, _cells_text(cells, cols))
    length(t.scrollback) > SCROLLBACK_MAX && deleteat!(t.scrollback, 1:1000)
    t.view > 0 && (t.view = min(t.view + 1, length(t.scrollback)))   # keep the reader's place
    return Cint(1)
end

# ── lifetime ─────────────────────────────────────────────────────────────────

_setwinsize(fd, rows, cols) =
    ccall(:ioctl, Cint, (Cint, Culong, Ptr{WinSize}), fd, TIOCSWINSZ, Ref(WinSize(rows, cols, 0, 0)))

"""
    Term(cmd; dir, rows, cols) -> Term

Start `cmd` on a new pty, behind a libvterm screen of `rows`×`cols`.
"""
function Term(cmd::Cmd; dir::AbstractString = pwd(), rows::Integer = 24, cols::Integer = 80,
              fg::UInt32 = 0xffdddddd, bg::UInt32 = 0xff17130f)
    vt = V.vterm_new(rows, cols)
    vt == C_NULL && error("vterm_new failed")
    V.vterm_set_utf8(vt, 1)
    scr = V.vterm_obtain_screen(vt)
    t = Term(vt, scr, Ref{V.VTermScreenCallbacks}(), Cint(-1), nothing, cmd, String(dir),
             Int(rows), Int(cols), [Run[] for _ in 1:rows], trues(rows), String[], 0,
             (0, 0), true, false, false, UInt8[], zeros(UInt8, 1 << 16), zeros(UInt8, 4096),
             Ref(V.VTermScreenCell()), fg, bg, 0f0, 0f0, 0f0, 0)
    t.callbacks[] = V.VTermScreenCallbacks(
        @cfunction(_damage, Cint, (V.VTermRect, Ptr{Cvoid})),
        C_NULL,                                                     # moverect: damage instead
        @cfunction(_movecursor, Cint, (V.VTermPos, V.VTermPos, Cint, Ptr{Cvoid})),
        @cfunction(_settermprop, Cint, (Cint, Ptr{Cvoid}, Ptr{Cvoid})),
        @cfunction(_bell, Cint, (Ptr{Cvoid},)),
        C_NULL, C_NULL, C_NULL,                                     # resize, sb_pushline, sb_popline
        @cfunction(_sb_clear, Cint, (Ptr{Cvoid},)),
        @cfunction(_sb_pushline4, Cint, (Cint, Ptr{V.VTermScreenCell}, Bool, Ptr{Cvoid})))
    # libvterm keeps both pointers. `t.callbacks` lives in `t`, and `t` lives in
    # the App for as long as the screen does.
    V.vterm_screen_set_callbacks(scr, t.callbacks, pointer_from_objref(t))
    V.vterm_screen_callbacks_has_pushline4(scr)
    V.vterm_screen_set_damage_merge(scr, V.VTERM_DAMAGE_ROW)
    V.vterm_screen_enable_altscreen(scr, 1)
    V.vterm_screen_reset(scr, 1)
    spawn!(t)
    return t
end

function spawn!(t::Term)
    fd = ccall(:posix_openpt, Cint, (Cint,), O_RDWR | O_NOCTTY)
    fd < 0 && error("posix_openpt failed: $(Libc.strerror())")
    (ccall(:grantpt, Cint, (Cint,), fd) == 0 && ccall(:unlockpt, Cint, (Cint,), fd) == 0) ||
        (ccall(:close, Cint, (Cint,), fd); error("grantpt/unlockpt failed: $(Libc.strerror())"))
    name = unsafe_string(ccall(:ptsname, Ptr{UInt8}, (Cint,), fd))
    # The master must not leak into the child (or any later child): with a copy
    # open over there, the child's exit would never read as a hangup here.
    ccall(:fcntl, Cint, (Cint, Cint, Cint...), fd, F_SETFD, FD_CLOEXEC)
    fl = ccall(:fcntl, Cint, (Cint, Cint, Cint...), fd, F_GETFL, Cint(0))
    ccall(:fcntl, Cint, (Cint, Cint, Cint...), fd, F_SETFL, fl | O_NONBLOCK)
    _setwinsize(fd, t.rows, t.cols)              # before the child asks
    slave = ccall(:open, Cint, (Cstring, Cint), name, O_RDWR | O_NOCTTY | O_CLOEXEC)
    slave < 0 && (ccall(:close, Cint, (Cint,), fd); error("open $name failed: $(Libc.strerror())"))
    env = copy(ENV)
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
    delete!(env, "COLUMNS"); delete!(env, "LINES")
    cmd = setenv(`setsid --ctty --wait $(t.cmd)`, env; dir = t.dir)
    proc = try
        Base.run(pipeline(cmd; stdin = RawFD(slave), stdout = RawFD(slave), stderr = RawFD(slave)); wait = false)
    catch
        ccall(:close, Cint, (Cint,), fd)
        rethrow()
    finally
        ccall(:close, Cint, (Cint,), slave)       # the child has its own copies now
    end
    t.fd, t.proc, t.exited = fd, proc, false
    return t
end

"""Close the pty (the child gets SIGHUP), stop the child, free the screen."""
function close!(t::Term)
    if t.fd >= 0
        ccall(:close, Cint, (Cint,), t.fd)
        t.fd = -1
    end
    if t.proc !== nothing
        try kill(t.proc) catch end
        t.proc = nothing
    end
    if t.vt != C_NULL
        V.vterm_free(t.vt)
        t.vt = C_NULL
    end
    return nothing
end

"""Kill the child and start the command again on the same screen."""
function restart!(t::Term)
    t.fd >= 0 && (ccall(:close, Cint, (Cint,), t.fd); t.fd = -1)
    t.proc !== nothing && (try kill(t.proc) catch end)
    empty!(t.pending)
    V.vterm_screen_reset(t.screen, 1)
    empty!(t.scrollback); t.view = 0
    fill!(t.dirty, true)
    spawn!(t)
end

function term_resize!(t::Term, rows::Integer, cols::Integer)
    (rows == t.rows && cols == t.cols) && return t
    t.rows, t.cols = Int(rows), Int(cols)
    t.lines = [Run[] for _ in 1:rows]           # before set_size: it calls back into _damage
    t.dirty = trues(rows)
    t.cursor = (min(t.cursor[1], rows - 1), min(t.cursor[2], cols - 1))
    V.vterm_set_size(t.vt, rows, cols)
    t.fd >= 0 && _setwinsize(t.fd, rows, cols)   # the kernel sends the child SIGWINCH
    return t
end

# ── bytes in and out ─────────────────────────────────────────────────────────

function _drain_vterm!(t::Term)
    while (n = V.vterm_output_read(t.vt, t.obuf, length(t.obuf))) > 0
        append!(t.pending, view(t.obuf, 1:n))
    end
end

function _flush!(t::Term)
    (t.fd < 0 || isempty(t.pending)) && return
    n = GC.@preserve t ccall(:write, Cssize_t, (Cint, Ptr{UInt8}, Csize_t), t.fd, t.pending, length(t.pending))
    n > 0 && deleteat!(t.pending, 1:n)           # the rest goes next frame
end

"""
    pump!(t)

Read what the child wrote (non-blocking, bounded per frame), feed it to
libvterm, and send libvterm's replies and any typed bytes back.
"""
function pump!(t::Term)
    t.fd < 0 && return false
    got = false
    for _ in 1:8                                 # ≤ 512 KiB a frame: a flood cannot stall drawing
        n = GC.@preserve t ccall(:read, Cssize_t, (Cint, Ptr{UInt8}, Csize_t), t.fd, t.rbuf, length(t.rbuf))
        if n > 0
            GC.@preserve t V.vterm_input_write(t.vt, pointer(t.rbuf), n)
            t.bytes_in += n
            got = true
        elseif n < 0 && Libc.errno() == EINTR
            continue
        else
            # EAGAIN: nothing more for now. 0 or EIO: every slave fd is closed —
            # the child (and anything it started on this pty) is gone.
            if n == 0 || Libc.errno() != EAGAIN
                t.exited = true
                ccall(:close, Cint, (Cint,), t.fd)
                t.fd = -1
            end
            break
        end
    end
    got && V.vterm_screen_flush_damage(t.screen)
    _drain_vterm!(t)                             # e.g. answers to cursor-position queries
    _flush!(t)
    return got
end

"""Send bytes to the child as if typed (no keyboard encoding)."""
function send_bytes!(t::Term, s::AbstractString)
    append!(t.pending, codeunits(s))
    _flush!(t)
end

# ── what the model sees ──────────────────────────────────────────────────────

function row_text(t::Term, r::Integer)
    buf = zeros(UInt8, 4 * t.cols + 8)
    n = V.vterm_screen_get_text(t.screen, buf, length(buf), V.VTermRect(r, r + 1, 0, t.cols))
    return rstrip(String(buf[1:n]))
end

"""
    term_text(t; lines = 120) -> String

The terminal as plain text: scrollback then screen, the last `lines` lines,
trailing blank rows dropped. This is what "Attach terminal" sends.
"""
function term_text(t::Term; lines::Integer = 120)
    t.vt == C_NULL && return ""
    screen = [row_text(t, r) for r in 0:t.rows - 1]
    while !isempty(screen) && isempty(screen[end]); pop!(screen); end
    all_ = t.altscreen ? screen : vcat(t.scrollback, screen)
    return join(all_[max(1, end - lines + 1):end], '\n')
end

# ── drawing ──────────────────────────────────────────────────────────────────

_u32(d) = 0xff000000 | UInt32(d[4]) << 16 | UInt32(d[3]) << 8 | UInt32(d[2])   # VTermColor → ImU32

function _colors(t::Term, c)
    fg, bg = c.fg, c.bg
    f = fg.data[1] & 0x02 != 0 ? t.fg :
        _u32((fg.data[1] & 0x01 != 0 ? (r = Ref(fg); V.vterm_screen_convert_color_to_rgb(t.screen, r); r[]) : fg).data)
    b = bg.data[1] & 0x04 != 0 ? UInt32(0) :
        _u32((bg.data[1] & 0x01 != 0 ? (r = Ref(bg); V.vterm_screen_convert_color_to_rgb(t.screen, r); r[]) : bg).data)
    if V.get_reverse(c.attrs) != 0
        f, b = (b == 0 ? t.bg : b), f
    end
    return f, b
end

"""Rebuild one row's runs from the screen. ASCII of one style shares a run;
anything wider than ASCII gets a run of its own, placed by column, so a glyph
from a fallback font cannot push the rest of the row off the grid."""
function build_row!(t::Term, r::Integer)
    runs = t.lines[r + 1]
    empty!(runs)
    io = IOBuffer()
    start, key = 0, (UInt32(0), UInt32(0), false)
    flush_run(col) = (s = String(take!(io)); isempty(s) || push!(runs, Run(start, s, key...)); start = col)
    for c in 0:t.cols - 1
        V.vterm_screen_get_cell(t.screen, V.VTermPos(r, c), t.cell)
        cell = t.cell[]
        u = cell.chars[1]
        u == WIDE_TAIL && continue
        f, b = _colors(t, cell)
        k = (f, b, V.get_underline(cell.attrs) != 0)
        ascii = u < 0x80
        if k != key || !ascii || position(io) == 0
            flush_run(c)
            key = k
        end
        if u == 0
            print(io, ' ')
        else
            for ch in cell.chars
                (ch == 0 || ch == WIDE_TAIL) && break
                print(io, Char(ch))
            end
        end
        ascii || flush_run(c + max(1, cell.width))
    end
    flush_run(t.cols)
    # A run of spaces on the default background draws nothing; drop it.
    filter!(x -> x.bg != 0 || x.under || !all(==(' '), x.text), runs)
    t.dirty[r + 1] = false
    return runs
end

function _metrics!(app, t::Term)
    size = app.fonts.size
    t.fsize == size && return
    G.ImGui_PushFont(app.fonts.mono, size)
    m = "M"
    t.cw = GC.@preserve m G.ImGui_CalcTextSize(pointer(m), pointer(m) + 1, false, -1f0).x
    t.lh = G.ImGui_GetTextLineHeight()
    G.ImGui_PopFont()
    t.fsize = size
end

function draw_grid!(app, t::Term, origin::G.ImVec2, focused::Bool)
    dl = G.ImGui_GetWindowDrawList()
    font, size = app.fonts.mono, app.fonts.size
    S = length(t.scrollback)
    v = t.altscreen ? 0 : clamp(t.view, 0, S)
    for i in 0:t.rows - 1
        y = origin.y + i * t.lh
        li = S - v + i                              # 0-based index into scrollback ++ screen
        if li < S                                   # a scrollback line: plain text
            s = t.scrollback[li + 1]
            isempty(s) && continue
            GC.@preserve s G.ImDrawList_AddText(dl, font, size, Ref(vec2(origin.x, y)), t.fg,
                                                pointer(s), pointer(s) + sizeof(s), 0f0, C_NULL)
            continue
        end
        r = li - S
        t.dirty[r + 1] && build_row!(t, r)
        for run in t.lines[r + 1]
            x = origin.x + run.col * t.cw
            w = length(run.text) * t.cw
            run.bg != 0 && G.ImDrawList_AddRectFilled(dl, Ref(vec2(x, y)), Ref(vec2(x + w, y + t.lh)), run.bg, 0f0, Cint(0))
            s = run.text
            GC.@preserve s G.ImDrawList_AddText(dl, font, size, Ref(vec2(x, y)), run.fg,
                                                pointer(s), pointer(s) + sizeof(s), 0f0, C_NULL)
            run.under && G.ImDrawList_AddLine(dl, Ref(vec2(x, y + t.lh - 1)), Ref(vec2(x + w, y + t.lh - 1)), run.fg, 1f0)
        end
    end
    if v == 0 && t.cursor_visible && !t.exited
        r, c = t.cursor
        p0 = vec2(origin.x + c * t.cw, origin.y + r * t.lh)
        p1 = vec2(p0.x + t.cw, p0.y + t.lh)
        focused ? G.ImDrawList_AddRectFilled(dl, Ref(p0), Ref(p1), 0x99dddddd, 0f0, Cint(0)) :
                  G.ImDrawList_AddRect(dl, Ref(p0), Ref(p1), 0x99dddddd, 0f0, 1f0, Cint(0))
    end
end

# ── keyboard ─────────────────────────────────────────────────────────────────

const _KEYMAP = (
    (G.ImGuiKey_Enter, V.VTERM_KEY_ENTER), (G.ImGuiKey_KeypadEnter, V.VTERM_KEY_ENTER),
    (G.ImGuiKey_Tab, V.VTERM_KEY_TAB), (G.ImGuiKey_Backspace, V.VTERM_KEY_BACKSPACE),
    (G.ImGuiKey_Escape, V.VTERM_KEY_ESCAPE),
    (G.ImGuiKey_UpArrow, V.VTERM_KEY_UP), (G.ImGuiKey_DownArrow, V.VTERM_KEY_DOWN),
    (G.ImGuiKey_LeftArrow, V.VTERM_KEY_LEFT), (G.ImGuiKey_RightArrow, V.VTERM_KEY_RIGHT),
    (G.ImGuiKey_Insert, V.VTERM_KEY_INS), (G.ImGuiKey_Delete, V.VTERM_KEY_DEL),
    (G.ImGuiKey_Home, V.VTERM_KEY_HOME), (G.ImGuiKey_End, V.VTERM_KEY_END),
    (G.ImGuiKey_PageUp, V.VTERM_KEY_PAGEUP), (G.ImGuiKey_PageDown, V.VTERM_KEY_PAGEDOWN),
)

_iobool(app, f) = unsafe_load(Ptr{Bool}(app.io + G.member_offset("ImGuiIO", f)))

"""
Turn this frame's keys and characters into terminal input. Characters come
from imgui's input queue (consumed here, so nothing else sees them); keys that
produce no character — Enter, arrows, Ctrl+letter — come from key state.
"""
function term_keys!(app, t::Term)
    ctrl, shift, alt = _iobool(app, "KeyCtrl"), _iobool(app, "KeyShift"), _iobool(app, "KeyAlt")
    mods = V.VTermModifier((shift ? 1 : 0) | (alt ? 2 : 0) | (ctrl ? 4 : 0))
    typed = false
    if ctrl && shift && G.ImGui_IsKeyPressed(G.ImGuiKey_V, false)
        clip = G.ImGui_GetClipboardText()
        if clip !== nothing && !isempty(clip)
            V.vterm_keyboard_start_paste(t.vt); _drain_vterm!(t)       # bracketed paste, if the child asked for it
            append!(t.pending, codeunits(replace(clip, "\r\n" => "\r", '\n' => '\r')))
            V.vterm_keyboard_end_paste(t.vt)
            typed = true
        end
    elseif shift && G.ImGui_IsKeyPressed(G.ImGuiKey_PageUp, true)
        t.view = min(t.view + max(1, t.rows - 2), length(t.scrollback))
    elseif shift && G.ImGui_IsKeyPressed(G.ImGuiKey_PageDown, true)
        t.view = max(t.view - max(1, t.rows - 2), 0)
    else
        for (ik, vk) in _KEYMAP
            if G.ImGui_IsKeyPressed(ik, true)
                V.vterm_keyboard_key(t.vt, vk, mods); typed = true
            end
        end
        # F1–F12 are not sent. C names them VTERM_KEY_FUNCTION(n) =
        # VTERM_KEY_FUNCTION_0 + n, values between the enum's declared members,
        # and the generated `vterm_keyboard_key(vt, key::VTermKey, mod)` takes
        # only declared members: `VTermKey(257)` is an ArgumentError. A wrapper
        # finding (an open-range C enum), reported rather than bit-cast around.
        if ctrl && !shift                            # Ctrl+letter makes no character event
            for n in 0:25
                if G.ImGui_IsKeyPressed(G.ImGuiKey(Int(G.ImGuiKey_A) + n), true)
                    V.vterm_keyboard_unichar(t.vt, UInt32('a' + n), V.VTERM_MOD_CTRL); typed = true
                end
            end
        end
    end
    # The character queue: an ImVector<ImWchar16> inside ImGuiIO.
    q = app.io + G.member_offset("ImGuiIO", "InputQueueCharacters")
    n = unsafe_load(Ptr{Cint}(q))
    if n > 0
        data = unsafe_load(Ptr{Ptr{UInt16}}(q + 8))
        cm = V.VTermModifier(alt ? 2 : 0)
        for i in 1:n
            u = unsafe_load(data, i)
            (0xd800 <= u <= 0xdfff) && continue      # no 32-bit ImWchar here: no astral planes
            ctrl && !alt && continue                 # Ctrl+letter was handled as a key
            V.vterm_keyboard_unichar(t.vt, UInt32(u), cm); typed = true
        end
        unsafe_store!(Ptr{Cint}(q), Cint(0))         # consumed
    end
    if typed
        t.view = 0                                   # typing returns to the live screen
        _drain_vterm!(t); _flush!(t)
    end
    return typed
end

"""Lay the terminal out in `w`×`h`: a header line, then the grid."""
function terminal_panel!(app, w::Real, h::Real)
    t = app.term
    G.ImGui_BeginChild("##termpane", Ref(vec2(w, h)), Cint(0), Cint(0))
    head = string(basename(first(t.cmd.exec)), "  ·  ", t.cols, "×", t.rows,
                  t.exited ? "  ·  exited" : "",
                  t.view > 0 ? "  ·  scrolled back $(t.view) lines (Shift+PgDn, or type)" : "")
    G.ImGui_AlignTextToFramePadding()
    colored(() -> text!(head), app.dim)
    G.ImGui_SameLine(0f0, app.fonts.size)
    G.ImGui_SmallButton("Restart") && (restart!(t); app.term_focus = true)
    rect!(app, :term_restart)
    if t.exited
        G.ImGui_SameLine(0f0, -1f0)
        colored(() -> text!("the process exited: Restart starts it again"), C_ERR)
    end
    _metrics!(app, t)
    if app.term_focus
        G.ImGui_SetNextWindowFocus()
        app.term_focus = false
    end
    G.ImGui_PushStyleColor(Cint(G.ImGuiCol_ChildBg), Ref(vec4(((t.bg >> 0) & 0xff) / 255, ((t.bg >> 8) & 0xff) / 255, ((t.bg >> 16) & 0xff) / 255)))
    G.ImGui_BeginChild("##term", ZERO, Cint(G.ImGuiChildFlags_Borders),
                       flags(G.ImGuiWindowFlags_NoScrollbar, G.ImGuiWindowFlags_NoScrollWithMouse))
    focused = G.ImGui_IsWindowFocused(Cint(0))
    origin = G.ImGui_GetCursorScreenPos()
    avail = G.ImGui_GetContentRegionAvail()
    rows = max(2, floor(Int, avail.y / t.lh))
    cols = max(10, floor(Int, avail.x / t.cw))
    term_resize!(t, rows, cols)
    if G.ImGui_IsWindowHovered(Cint(0)) && !t.altscreen
        wheel = unsafe_load(Ptr{Float32}(app.io + G.member_offset("ImGuiIO", "MouseWheel")))
        wheel != 0 && (t.view = clamp(t.view + round(Int, 3 * wheel), 0, length(t.scrollback)))
    end
    focused && !t.exited && term_keys!(app, t)
    draw_grid!(app, t, origin, focused)
    G.ImGui_Dummy(Ref(vec2(avail.x, avail.y)))      # the grid's extent, as an item
    app.term_focused = focused
    G.ImGui_EndChild()
    rect!(app, :term)
    G.ImGui_PopStyleColor(Cint(1))
    G.ImGui_EndChild()
end
