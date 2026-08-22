# ─────────────────────────────────────────────────────────────────────────────
# Sidecar window
#
# `ask("...")` from a working REPL: the answer renders in a second terminal
# window, the REPL is yours again immediately, and the model sees what you have
# actually been doing — output included, not just the lines you typed.
#
# Three pieces have to be true at once for that to work, and each is a choice:
#
#   * The window is a REAL tty, not a pipe. A fifo relayed by `cat` would carry
#     the escapes fine, but `\e[nA` is only correct if we know the window's
#     width, and a fifo has no width to ask for. So the child in the window
#     reports its pts path and we open THAT — a character device we can ioctl
#     for a live size, which is also what makes window resizes work mid-reply.
#   * Generation runs on a spawned thread, or `ask` would block the REPL for the
#     length of a reply, which defeats the entire point. $JULIA_NUM_THREADS is
#     `auto` on this box (12), so there is a thread to spawn onto.
#   * Context is sent as a DELTA. Re-sending the scrollback every turn would
#     spend the context window on the same 200 lines over and over; three turns
#     of a full capture overruns a 32k window on its own.
#
# Closing the window is the hangup: the monitor task sees kitty exit, frees the
# context and the weights, and the next `ask` starts clean — same contract as
# `/exit` in `load`.
# ─────────────────────────────────────────────────────────────────────────────

# ── Terminal geometry ────────────────────────────────────────────────────────

const _TIOCGWINSZ = 0x5413      # Linux/x86_64; struct winsize is 4 × UInt16

"""
Live (rows, cols) of the terminal behind `fd`, or `nothing` if it is not one.

Asked fresh before every turn rather than cached at open: the redraw erases a
row count computed from this, so a window resized mid-conversation would
otherwise shred exactly the reply it is rendering.
"""
function _winsize(fd)                          # Integer or RawFD — see `_fdint`
    ws = Ref((UInt16(0), UInt16(0), UInt16(0), UInt16(0)))
    rc = ccall(:ioctl, Cint, (Cint, Culong, Ptr{Cvoid}), _fdint(fd), _TIOCGWINSZ, ws)
    rc == 0 || return nothing
    rows, cols = Int(ws[][1]), Int(ws[][2])
    (rows == 0 || cols == 0) && return nothing
    return (rows, cols)
end

# ── Scrollback capture ───────────────────────────────────────────────────────

_kitty_socket() = get(ENV, "KITTY_LISTEN_ON", "")

"""
    _scrollback(; extent = "all") -> String | Nothing

The calling window's own text — everything you typed and everything Julia
printed back — via kitty's remote control. `nothing` when that is unavailable,
which is any of: not running under kitty, `allow_remote_control` off, or a
window that predates it being turned on (kitty reads it at window start).

Plain text by default: `--ansi` would hand the model a transcript full of
`\\e[0m`, which is tokens spent on nothing.
"""
function _scrollback(; extent::AbstractString = "all")
    sock = _kitty_socket()
    isempty(sock) && return nothing
    out = try
        cmd = `kitty @ --to $sock get-text --extent=$extent --add-cursor=no`
        read(pipeline(cmd; stderr = devnull), String)
    catch
        return nothing            # kitty missing, socket stale, RC refused
    end
    return isempty(strip(out)) ? nothing : out
end

# Lines of `cur` that come after everything in `prev`.
#
# Both are windows onto the same growing stream, so this is a suffix/prefix
# overlap: find the largest k where the last k lines of `prev` are the first k
# lines of `cur`, and everything past k is new. Not a line count or a byte
# offset, because a scrollback is not append-only from our side — once it
# reaches `scrollback_lines` it drops from the top, so the same content sits at
# a different index each time we look.
#
# A fixed-size anchor on the tail of `prev` gets this wrong on exactly that
# case: trim four lines off the top and the anchor still matches, but trim
# enough that the anchor itself is gone and it re-sends the entire capture,
# including the several hundred lines already spent. The overlap search has no
# such cliff — it degrades a line at a time.
#
# Largest k wins. Ambiguity needs a repeated run of identical lines at the join,
# which in a real scrollback means blank lines, and preferring the longer
# overlap there re-reads nothing.
function _context_delta(prev::Vector{String}, cur::Vector{String})
    isempty(prev) && return cur
    for k in min(length(prev), length(cur)):-1:1
        if @views prev[end-k+1:end] == cur[1:k]
            return cur[k+1:end]
        end
    end
    return cur                    # no overlap at all: all of it is new
end

# The `ask(...)` call is on screen by the time we capture, and echoing the
# question back as context just wastes tokens.
const _ASK_ECHO = r"^\s*(julia>\s*)?(LlamaChat\.)?ask\("

function _trim_context(lines::Vector{String})
    while !isempty(lines) && (isempty(strip(lines[end])) || occursin(_ASK_ECHO, lines[end]))
        pop!(lines)
    end
    return lines
end

# ── The window ───────────────────────────────────────────────────────────────

mutable struct Sidecar
    proc::Base.Process        # the kitty window
    tty::IOStream             # its pts, opened for writing
    ttyfd::RawFD
    model::String
    opts::NamedTuple          # ChatSession keywords, applied when it is built
    session::Union{Nothing,ChatSession}   # nothing until the first turn loads it
    lock::ReentrantLock       # one llama context, one turn at a time
    seen::Vector{String}      # scrollback lines already sent as context
    dir::String               # scratch dir holding the tty handshake file
    live::Bool
end

const _SIDECAR = Ref{Union{Nothing,Sidecar}}(nothing)

# The child reports which pts it got, then watches the Julia process that
# started it and exits when that is gone.
#
# It used to `exec sleep infinity`, and a Julia that died without unwinding — a
# crash, a SIGKILL, closing the REPL — left the window behind forever, holding a
# terminal nothing was ever going to write to again. `wait(proc)` is how WE
# notice the window closing; this is how the window notices US, and it is the
# direction that has no in-process handler to rely on precisely because the
# process is gone. A 1s poll costs nothing and makes the window's lifetime what
# it is advertised to be: attached to the Julia session.
const _WINDOW_SH = raw"""
tty > "$1" 2>/dev/null || echo "" > "$1"
while kill -0 "$2" 2>/dev/null; do sleep 1; done
"""

function _spawn_window(title::AbstractString, geometry::NTuple{2,Int})
    Sys.which("kitty") === nothing &&
        error("ask() renders into a kitty window and kitty is not on PATH")

    dir     = mktempdir(; prefix = "llamachat-")
    ttyfile = joinpath(dir, "tty")
    w, h    = geometry

    cmd = `kitty --title $title
                 -o initial_window_width=$(w)
                 -o initial_window_height=$(h)
                 -o confirm_os_window_close=0
                 sh -c $_WINDOW_SH sh $ttyfile $(getpid())`
    proc = run(pipeline(cmd; stdout = devnull, stderr = devnull); wait = false)

    # Handshake. A window that dies on the way up (no compositor, bad option)
    # must fail here rather than leave us blocking on a file that never appears.
    path = ""
    for _ in 1:200
        if isfile(ttyfile)
            path = strip(read(ttyfile, String))
            isempty(path) || break
        end
        process_running(proc) || break
        sleep(0.05)
    end
    if isempty(path) || !ispath(path)
        kill(proc, Base.SIGKILL); rm(dir; recursive = true, force = true)
        error("kitty window did not report a tty within 10s" *
              (process_running(proc) ? "" : " (it exited immediately)"))
    end
    return proc, path, dir
end

# An IOStream on a pts is a tty by fd but not a `Base.TTY` by type, so nothing
# downstream infers either its size or its colour support. Both are stated here:
# the size freshly, so a resize is picked up, and colour unconditionally,
# because we know what we are writing to even if `get(io, :color, …)` does not.
function _window_io(sc::Sidecar)
    sz = _winsize(sc.ttyfd)
    io = IOContext(sc.tty, :color => true)
    return sz === nothing ? io : IOContext(io, :displaysize => sz)
end

function _teardown!(sc::Sidecar)
    sc.live || return sc
    sc.live = false

    # Order matters, and it is not the obvious one.
    #
    # Closing the tty FIRST is what makes a turn still in flight stop: the next
    # token it emits writes to a closed stream and throws, so the generation
    # loop unwinds within a token rather than running to max_tokens against a
    # window nobody is looking at.
    #
    # Only then take the lock. Freeing the context while another thread is
    # inside `llama_decode` with it is a use-after-free — the first version did
    # exactly that, on the theory that the doomed turn would throw its way out
    # on its own, which is true but says nothing about *when*. The lock is the
    # part that makes it true before the memory goes away.
    try close(sc.tty) catch end
    lock(sc.lock) do
        sc.session === nothing || close!(sc.session)      # context + weights
        sc.session = nothing
    end

    process_running(sc.proc) && (try kill(sc.proc) catch end)
    rm(sc.dir; recursive = true, force = true)
    _SIDECAR[] === sc && (_SIDECAR[] = nothing)
    return sc
end

function _ensure_sidecar(model::AbstractString, geometry::NTuple{2,Int}; kwargs...)
    sc = _SIDECAR[]
    sc !== nothing && sc.live && process_running(sc.proc) && return sc
    sc !== nothing && _teardown!(sc)

    proc, path, dir = _spawn_window("LlamaChat — $model", geometry)
    tty = try
        open(path, "w")
    catch
        kill(proc, Base.SIGKILL); rm(dir; recursive = true, force = true)
        rethrow()
    end

    # No session yet. Loading 18 GB takes 35 s, and doing it here would block the
    # REPL for all of it on the very call whose whole purpose is not to — the
    # first `ask` would freeze the prompt it is supposed to leave you holding.
    # The window opens now, says what it is doing, and the load happens on the
    # worker under the lock, so a second `ask` simply queues behind it.
    sc = Sidecar(proc, tty, RawFD(fd(tty)), String(model), NamedTuple(kwargs),
                 nothing, ReentrantLock(), String[], dir, true)
    _SIDECAR[] = sc

    banner = _window_io(sc)
    print(banner, "\e[2J\e[H")
    printstyled(banner, model; bold = true)
    printstyled(banner, "  ·  close this window to free the model\n\n"; color = :light_black)
    flush(tty)

    # Closing the window is the hangup. This is the only teardown path that does
    # not need the lock: kitty is already gone, so a turn in flight is writing
    # into a dead pts and will throw its way out on its own.
    Threads.@spawn begin
        try wait(sc.proc) catch end
        _teardown!(sc)
    end
    return sc
end

# Built on the worker, under the lock, on the first turn. Load progress is
# routed into the window rather than stderr — a "loading … ok" line surfacing in
# a REPL you have already moved on in is noise arriving at the wrong desk.
function _session!(sc::Sidecar, io::IO)
    sc.session === nothing || return sc.session
    # llama.cpp's own loader chatter goes to the window too, not to the REPL —
    # `verbose` decides whether it is shown at all, `_LOG_FD` decides where.
    sc.session = _logto(fd(sc.tty)) do
        ChatSession(sc.model; log = io, sc.opts...)             # prints its own progress
    end
    println(io)
    flush(sc.tty)
    return sc.session
end

# ── Public entry point ───────────────────────────────────────────────────────

function _compose(prompt::AbstractString, ctx::Vector{String})
    isempty(ctx) && return String(prompt)
    return """
    Here is what has happened in my Julia REPL since we last spoke:

    ```
    $(join(ctx, "\n"))
    ```

    $prompt"""
end

function _run_ask(sc::Sidecar, prompt::AbstractString, ctx::Vector{String},
                  max_tokens::Int)
    lock(sc.lock) do
        sc.live || return
        io = _window_io(sc)
        printstyled(io, ">>> ", prompt, "\n\n"; bold = true, color = :green)
        isempty(ctx) ||
            printstyled(io, "(+ $(length(ctx)) lines of REPL context)\n\n";
                        color = :light_black)
        flush(sc.tty)
        try
            session = _session!(sc, io)                 # first turn pays the load
            r = chat(session, _compose(prompt, ctx); io = io, max_tokens = max_tokens)
            printstyled(io, _stats_line(r), "\n\n"; color = :light_black)
        catch e
            e isa InterruptException && rethrow()
            # A dead window is the ordinary way this ends, not an error worth
            # shouting about — the monitor task is already tearing down.
            if sc.live && process_running(sc.proc)
                printstyled(io, "error: ", sprint(showerror, e), "\n"; color = :red)
            end
        finally
            try flush(sc.tty) catch end
        end
    end
    return nothing
end

"""
    ask(prompt; kwargs...)

Ask the model something from a working REPL and get the answer in a **second
terminal window**, without giving up the prompt you are typing at.

The first call opens the window and loads the model; every call after that is a
turn in the same conversation. It returns immediately — generation runs on a
spawned thread — so the REPL is yours again while the reply streams next door.

The model is given your terminal's own scrollback, so it sees what you have been
doing rather than only what you type into `ask`: the call that failed, the error,
the stacktrace, the `@show` output. Only what is new since the previous `ask` is
sent, so a long session does not spend its whole context window re-reading
itself.

**Closing the window is the hangup.** It frees the context and the weights and
the next `ask` starts clean, exactly like `/exit` does in [`load`](@ref).

  `model`       which model to open (default `default_model()`)
  `context`     send REPL scrollback (default `true`)
  `lines`       cap on context lines per turn (default 400)
  `max_tokens`  cap on generated tokens (default 4096)
  `geometry`    window size in pixels (default `(900, 1000)`)

plus `ChatSession`'s keywords — `system`, `n_ctx`, `temp`, `n_batch`, … — which
apply on the call that opens the window, since that is the one that builds the
session.

```julia
julia> using LlamaChat

julia> RepliBuild.wrap("packages/pugixml/replibuild.toml")
ERROR: MethodError: no method matching thunk_abi(::MEMORY, ::Val{:byval})

julia> ask("why did that fail?")      # answer appears in the other window
julia> ask("show me the fix")         # remembers, and sees anything since
```

Requires kitty with remote control enabled (`allow_remote_control socket-only`)
for the scrollback; without it `ask` still works, it just has nothing to attach
and says so once.
"""
function ask(prompt::AbstractString;
             model::AbstractString = default_model(),
             context::Bool = true,
             lines::Integer = 400,
             max_tokens::Integer = 4096,
             geometry::NTuple{2,Int} = (900, 1000),
             kwargs...)

    sc = _ensure_sidecar(model, geometry; kwargs...)

    ctx = String[]
    if context
        raw = _scrollback()
        if raw === nothing
            @warn """no terminal context available — `ask` is sending your prompt alone.
                     kitty remote control is off, or this window started before it was \
                     enabled (restart the window). Pass `context = false` to silence this.""" maxlog=1
        else
            cur = collect(eachline(IOBuffer(raw)))
            ctx = _trim_context(_context_delta(sc.seen, cur))
            length(ctx) > lines && (ctx = ctx[end-Int(lines)+1:end])
            sc.seen = cur
        end
    end

    Threads.@spawn _run_ask(sc, String(prompt), ctx, Int(max_tokens))
    return nothing
end

# Quitting Julia normally frees the weights here rather than leaving it to the
# OS, and closes the window immediately instead of within a second of the
# child's next poll. The poll is still what covers a Julia that never gets to
# run this — it is the backstop, not the plan.
#
# Called from the module's single `__init__`, not defined as one: a second
# `__init__` in the same module silently replaces the first.
function _atexit_teardown()
    atexit() do
        sc = _SIDECAR[]
        sc === nothing || (try _teardown!(sc) catch end)
    end
end
