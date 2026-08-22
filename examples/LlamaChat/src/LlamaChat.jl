"""
    LlamaChat

A multi-turn chat app built on the RepliBuild-generated llama.cpp (b10286)
wrapper — the reference example for **driving a wrapped C library that is all
by-value structs**, and the counterpart to `BoxWorld` (which covers the C++
object-model side).

The layering discipline is the same as BoxWorld's:

- `lib/` holds RepliBuild's build + wrap output (`Llamacpp.jl`, `libllamacpp.so`,
  `compilation_metadata.json`, `thunk_manifest.json`) exactly as `wrap()`
  produced it. It is the ABI layer; it is never edited.
- `src/LlamaChat.jl` (this file) is the ergonomic layer: sessions, chat
  templating, KV-cache bookkeeping, streaming, sampling defaults.

What it exercises, in one pass, that a verify script does not:

  * MEMORY-class structs returned AND passed by value — `llama_model_params`
    (72 B), `llama_context_params` (160 B), `llama_batch`,
    `llama_sampler_chain_params`,
  * an array of C structs built on the Julia side (`llama_chat_message[]`),
  * out-params into plain Julia arrays (tokenize, token_to_piece),
  * Cstring returns (`llama_model_chat_template`),
  * Tier-2 MLIR-JIT dispatch (`llama_model_load_from_file`,
    `llama_init_from_model`),
  * and the Tier-2/Tier-3 overload trap on `llama_vocab_is_eog` — see `_is_eog`.

Unlike the embedding path in `packages/llamacpp/inference.jl`, a wrong answer
here is *legible*: a broken ABI crossing produces garbage text, not a plausible
float vector.

Three names, which is the whole interface:

```julia
using LlamaChat

list_models()              # what is on the box
load("qwen3-coder")        # load it and start talking; /exit frees it
load()                     # \$LLAMACPP_CHAT_MODEL, else qwen3-coder

ask("why did that fail?")  # answer in a SECOND window; this REPL stays yours
```

`load` does not return until you leave the chat loop, and frees the model on the
way out — so the Julia session you come back to holds nothing, and the next
`load` is a clean slate.

`ask` is for when the REPL is the thing you are working in and you do not want
to leave it: the reply renders in a second terminal window driven by this same
process, and the model is handed your terminal's own scrollback, so it sees the
error and the stacktrace rather than only what you thought to retype. Closing
that window is the hangup. See `window.jl`.

Everything else (`ChatSession`, `chat`, `reset!`, `close!`, `resolve_model`,
`default_model`) still exists and is still supported; it is simply not exported,
because a chat app has no business putting a dozen names in your namespace.
Reach it through `LlamaChat.` when scripting — see `chat.jl` for the one-shot
form.

Replies stream as plain text and each markdown block is reprinted formatted as
soon as it closes. There is no switch for this: on a terminal it always happens,
and into a pipe it never does, because the redraw is cursor arithmetic that a
pipe has no cursor for. See `_MDSink`.
"""
module LlamaChat

import JSON
import Markdown

# ── ABI layer: the generated wrapper ─────────────────────────────────────────
# Resolves its shared library sibling-first, so the copy in lib/ is
# self-contained. Its __init__ registers this binary's JIT engine, which is
# what Tier-2 entry points (model load, context init) dispatch through.
#
# `import`, deliberately NOT `using`. A wrapper generated from C++ DWARF
# harvests a name from every symbol that reached the debug info — libstdc++
# included — and this one defines 6,527. Importing the module and reaching
# through `L.` keeps that out of this namespace entirely.
#
# It used to be a correctness matter as well, and that is worth recording
# because it cost a debugging session here: llamacpp defines `error` (from
# `codecvt_base::result.error`) and used to EXPORT it, so `using .Llamacpp`
# made a bare `error("...")` in this file an ambiguous binding and every
# failure path raised `UndefVarError: error not defined` instead of its
# message — invisible until something actually went wrong, since the happy
# path never calls it. RepliBuild fixes that upstream now: names colliding
# with a Base/Core export are withheld from `export` (still defined, still
# reachable as `L.error`), and the wrapper carries a banner listing them —
# here: `all`, `error`, `stat`, `symlink`. So `using` is no longer a hazard,
# just a poor idea at this scale.
include(joinpath(@__DIR__, "..", "lib", "Llamacpp.jl"))
import .Llamacpp
const L = Llamacpp

# `load` opens a model and drops you into the chat loop; `list_models` says what
# there is to open; `ask` answers in a second window while you keep the REPL.
# The rest of this file is what those are made of and stays behind the module
# qualifier — see the module docstring.
export list_models, load, ask

# ─────────────────────────────────────────────────────────────────────────────
# Model resolution — ollama's blob store, so you can say "qwen3-coder" instead
# of "/var/lib/ollama/blobs/sha256-1194192cf2a1...".
# ─────────────────────────────────────────────────────────────────────────────

const REGISTRY = "registry.ollama.ai"

# Both of these read ENV at CALL time. They were `const X = get(ENV, ...)` at
# module scope, which is evaluated during PRECOMPILATION and frozen into the
# .ji — so the documented overrides did nothing for anyone whose first `using
# LlamaChat` predated their setting the variable, and did so silently: you got
# the default model, loaded it, and got a perfectly good answer from the wrong
# 17 GB file. Reading them here also means a change takes effect immediately,
# without a restart or a forced recompile.

"""
    ollama_root() -> String

Where the ollama blob store lives (`\$OLLAMA_MODELS`, default `/var/lib/ollama`).
"""
ollama_root() = get(ENV, "OLLAMA_MODELS", "/var/lib/ollama")

"""
    default_model() -> String

The model bare `load()` opens (`\$LLAMACPP_CHAT_MODEL`, default `qwen3-coder`).

qwen3-coder is 30B-A3B: MoE, so only ~3B params are active per token. On CPU
that makes an 18 GB model faster than a dense 8 GB one, and it has a chat
template baked into the GGUF.
"""
default_model() = get(ENV, "LLAMACPP_CHAT_MODEL", "qwen3-coder")

function _manifest_path(name::AbstractString)
    spec, tag = if occursin(':', name)
        parts = split(name, ':'; limit = 2)
        (String(parts[1]), String(parts[2]))
    else
        (String(name), "latest")
    end
    ns, model = if occursin('/', spec)
        parts = split(spec, '/'; limit = 2)
        (String(parts[1]), String(parts[2]))
    else
        ("library", spec)
    end
    p = joinpath(ollama_root(), "manifests", REGISTRY, ns, model, tag)
    return isfile(p) ? p : nothing
end

"""
    resolve_model(name) -> path

Accept either a path to a .gguf / ollama blob, or an ollama model name
("qwen3-coder", "gemma4:e2b", "igorls/gemma-4-E4B-it-heretic-GGUF:latest"),
and return the blob holding the weights.
"""
function resolve_model(name::AbstractString)
    isfile(name) && return String(name)
    mp = _manifest_path(name)
    if mp === nothing
        avail = try join(sort(first.(list_models())), ", ") catch; "" end
        error("no such model: \"$name\" (not a file, and no ollama manifest under " *
              "$(ollama_root()))" * (isempty(avail) ? "" : "\n  available: $avail"))
    end
    manifest = JSON.parsefile(mp)
    for layer in manifest["layers"]
        layer["mediaType"] == "application/vnd.ollama.image.model" || continue
        blob = joinpath(ollama_root(), "blobs", replace(layer["digest"], ':' => '-'))
        isfile(blob) || error("manifest $mp points at a missing blob: $blob")
        return blob
    end
    error("manifest $mp has no model layer")
end

"""
A `Vector{Tuple{String,Int}}` of (name, bytes) that prints as a table rather
than as a screenful of tuples. It is an `AbstractVector`, so indexing,
iteration, `first`/`last` and broadcasting all work as they did.
"""
struct ModelList <: AbstractVector{Tuple{String,Int}}
    v::Vector{Tuple{String,Int}}
end

Base.size(m::ModelList)                  = size(m.v)
Base.getindex(m::ModelList, i::Int)      = m.v[i]
Base.IndexStyle(::Type{ModelList})       = IndexLinear()

function _human(n::Integer)
    n < 1024 && return "$n B"
    x, i, units = n / 1024, 1, ("KiB", "MiB", "GiB", "TiB")
    while x >= 1024 && i < length(units)
        x /= 1024; i += 1
    end
    return string(x < 10 ? round(x; digits = 1) : round(Int, x), " ", units[i])
end

function Base.show(io::IO, ::MIME"text/plain", ms::ModelList)
    if isempty(ms)
        printstyled(io, "no models under $(ollama_root())\n"; color = :light_black)
        return
    end
    # Mark the one bare `load()` will open. list_models always tags a model,
    # default_model() usually does not, so normalise before comparing.
    dflt = default_model()
    occursin(':', dflt) || (dflt *= ":latest")
    w = maximum(length(first(m)) for m in ms)
    for (name, sz) in ms
        hit = name == dflt
        printstyled(io, hit ? " → " : "   "; color = :green)
        printstyled(io, rpad(name, w); bold = hit)
        printstyled(io, "  ", lpad(_human(sz), 9), "\n"; color = :light_black)
    end
    return nothing
end

"""
    list_models() -> ModelList

Every ollama model visible in the local blob store, largest first, as
(name, bytes). Prints as a table; `→` marks the model bare `load()` opens.
"""
function list_models()
    out = Tuple{String,Int}[]
    root = joinpath(ollama_root(), "manifests", REGISTRY)
    isdir(root) || return ModelList(out)
    for (dir, _, files) in walkdir(root), f in files
        rel = relpath(joinpath(dir, f), root)
        parts = splitpath(rel)
        length(parts) >= 2 || continue
        tag   = parts[end]
        model = join(parts[1:end-1], "/")
        startswith(model, "library/") && (model = model[length("library/")+1:end])
        sz = try
            m = JSON.parsefile(joinpath(dir, f))
            i = findfirst(l -> l["mediaType"] == "application/vnd.ollama.image.model",
                          m["layers"])
            i === nothing ? 0 : Int(m["layers"][i]["size"])
        catch
            0
        end
        sz > 0 && push!(out, ("$model:$tag", sz))
    end
    sort!(out; by = last, rev = true)
    return ModelList(out)
end

# ─────────────────────────────────────────────────────────────────────────────
# Small helpers
# ─────────────────────────────────────────────────────────────────────────────

# NUL-terminated byte buffer we control the lifetime of — llama_chat_message
# holds raw `const char *`, so the bytes must outlive the ccall.
function _cstr(s::AbstractString)
    b = Vector{UInt8}(undef, ncodeunits(s) + 1)
    copyto!(b, codeunits(s))
    b[end] = 0x00
    return b
end

# The wrapper exports TWO llama_vocab_is_eog methods: the C API as a plain ccall
# (vocab, ::Int32), and a Tier-2 MLIR-JIT thunk for the C++ member function
# llama_vocab::is_eog (this, ::Integer). Tuple{Any,Int32} is strictly more
# specific than Tuple{Any,Integer}, so an Int32 token lands on the ccall — but a
# plain Int (Julia's default literal type!) would route through the JIT instead.
# Every token that crosses this boundary goes through here.
_is_eog(vocab, tok::Integer) = L.llama_vocab_is_eog(vocab, Int32(tok))

# Longest complete-UTF8 prefix of `pending`, consumed; a trailing partial
# sequence stays put. A token is a byte sequence, not a character — CJK and
# emoji routinely split across two tokens, and printing half of one corrupts
# the terminal.
function _take_utf8!(pending::Vector{UInt8})
    n = length(pending)
    n == 0 && return ""
    cut, i, back = n, n, 0
    while i >= 1 && back < 4
        b = pending[i]
        if b & 0x80 == 0x00              # ASCII — everything before is complete
            break
        elseif b & 0xC0 == 0xC0          # lead byte
            need = (b & 0xE0 == 0xC0) ? 2 : (b & 0xF0 == 0xE0) ? 3 : 4
            (n - i + 1) < need && (cut = i - 1)
            break
        end
        i -= 1; back += 1                # continuation byte, keep walking back
    end
    cut <= 0 && return ""
    s = String(pending[1:cut])
    deleteat!(pending, 1:cut)
    return s
end

# ── llama.cpp's own logging ──────────────────────────────────────────────────
#
# llama.cpp writes a few hundred lines of loader detail, and a couple more when a
# context is freed, using C `printf` — straight to fd 1/2, where Julia's own
# `redirect_stdout`/`redirect_stderr` cannot reach it without redirecting the
# whole process.
#
# Process-wide is exactly what we must not do here. A sidecar model loads on a
# background thread for 36 s while you keep working, and swallowing the REPL's
# stderr for that long would eat your own errors. Worse in the other direction:
# `~llama_context: CPU compute buffer size …` from freeing a sidecar model lands
# on the terminal you are typing in, on top of the `julia>` the REPL has already
# drawn. Julia does not redraw on foreign writes to its tty, so the prompt sits
# there looking wedged until you press enter — which is precisely how it got
# reported, and it was never a hang at all.
#
# `llama_log_set` routes every line through a callback instead, so a destination
# can be chosen per use: discarded by default, the window for the sidecar, fd 2
# when you asked to see it. The callback is three ccalls and allocates nothing —
# llama.cpp may call it from a ggml worker, and a thread the Julia runtime never
# adopted is no place to allocate or take a lock.

const _LOG_FD = Ref{Cint}(Cint(-1))         # -1 discards
const _LOG_CB = Ref{Ptr{Cvoid}}(C_NULL)     # set in __init__; not precompilable

# `Base.fd(::IOStream)` returns a `RawFD`, which is NOT an `Integer` — so an
# `fd::Integer` signature compiles, type-checks, and then MethodErrors at
# runtime on the one call that passes a real stream's descriptor. That has now
# happened twice in this file (once in `_winsize`, once in `_logto`), both times
# at a sidecar call site no test reaches. Every fd argument goes through here so
# there is no third time.
_fdint(fd::Integer) = Cint(fd)
_fdint(fd::RawFD)   = Base.bitcast(Cint, fd)

function _llama_log(::Cint, text::Ptr{Cchar}, ::Ptr{Cvoid})
    fd = _LOG_FD[]
    fd < 0 && return nothing
    n = ccall(:strlen, Csize_t, (Ptr{Cchar},), text)
    n == 0 && return nothing
    ccall(:write, Cssize_t, (Cint, Ptr{Cchar}, Csize_t), fd, text, n)
    return nothing
end

"""
Send llama.cpp's logging to `fd` for the duration of `f`, then put it back.

`fd = -1` discards. Not a lock: two concurrent loads would race on it, and the
worst case is a few loader lines going to the other one's window — cheap next to
holding a lock across a 36 s load.
"""
function _logto(f, fd)
    prev = _LOG_FD[]
    _LOG_FD[] = _fdint(fd)
    try
        return f()
    finally
        _LOG_FD[] = prev
    end
end

# Retained: callers still read as "do this quietly", and `verbose` still means
# "let it through to stderr". The mechanism underneath is the log callback now
# rather than a redirect the whole process shares.
function _quiet(f, verbose::Bool)
    return _logto(f, verbose ? 2 : -1)
end

const _backend_up = Ref(false)
function _ensure_backend(verbose::Bool)
    _backend_up[] && return
    # Install the log callback BEFORE backend init, or the backend's own banner
    # is already on your terminal by the time anything can redirect it.
    _LOG_CB[] == C_NULL || L.llama_log_set(_LOG_CB[], C_NULL)
    _quiet(verbose) do
        L.llama_backend_init()
    end
    _backend_up[] = true
    return
end

# ─────────────────────────────────────────────────────────────────────────────
# Terminal markdown
#
# Markdown cannot be rendered incrementally — a fenced block, list or table only
# has a shape once it is closed — so it is fundamentally at odds with streaming
# tokens. Rather than give up one for the other, a streamed turn prints raw text
# live and then, if it still occupies the visible screen, erases those lines and
# reprints them formatted. When the reply scrolled past the top of the terminal
# the erase can't reach it, so the raw text is simply left in place.
# ─────────────────────────────────────────────────────────────────────────────

# "Can I move a cursor around in this?" — the one question that decides whether a
# reply is rendered or streamed raw.
#
# Not `io isa Base.TTY`, which was true only of this process's own stdout. The
# sidecar window (see window.jl) is a pts we opened by path, so it arrives as an
# `IOStream` that is every bit a terminal — `isatty` is what actually knows, and
# the type does not. IOContext has to be unwrapped for the same reason: the
# sidecar wraps its stream to state a size and colour support, and a wrapper
# around a terminal is still a terminal.
_istty(io::IO)        = false
_istty(io::Base.TTY)  = true
_istty(io::IOStream)  = ccall(:isatty, Cint, (Cint,), fd(io)) == 1
_istty(io::IOContext) = _istty(io.io)

# Terminal lines a string occupies at width `w`, counting soft wraps. Wide (CJK,
# emoji) characters take two columns, which is why this is not `count('\n')`.
function _wrapped_lines(s::AbstractString, w::Integer)
    w = max(Int(w), 1)
    lines, col = 0, 0
    for c in s
        if c == '\n'
            lines += 1; col = 0
        else
            cw = max(textwidth(c), 0)
            if col + cw > w
                lines += 1; col = cw
            else
                col += cw
            end
        end
    end
    return lines + (col > 0 ? 1 : 0)
end

# Julia's terminal markdown backend underlines a header with a run of characters
# chosen by level — `_header_underlines = collect("≡=–-⋅ ")` in the Markdown
# stdlib. h1 gets `≡`, which reads as decoration, but h2 gets plain ASCII `=`,
# and a bold line over `==========` is character-for-character what setext
# markdown SOURCE looks like. So a *correctly* rendered `## Heading` looks like a
# renderer that failed to strip the syntax — which is exactly how it got
# reported, and models reach for `##` constantly.
#
# h1 keeps its rule. h2 and below become bold text with no rule at all, which is
# what they already looked like minus the false syntax. Done by rewriting the
# parsed tree with public node types rather than by poking the stdlib's private
# underline table, which is a mutable global shared with `?help` and every other
# markdown render in the session.
_restyle(x) = x
_restyle(h::Markdown.Header{1}) = h
_restyle(h::Markdown.Header) = Markdown.Paragraph(Any[Markdown.Bold(h.text)])

# Julia's markdown backend can throw on pathological input (and a reply cut off
# at max_tokens is pathological by construction — an unterminated fence, a
# half-written table). Falling back to the raw text is always acceptable;
# throwing away a finished generation is not.
function _show_markdown(io::IO, text::AbstractString)
    try
        parsed = Markdown.parse(text)
        map!(_restyle, parsed.content, parsed.content)
        show(io, MIME"text/plain"(), parsed)
    catch e
        e isa InterruptException && rethrow()
        print(io, text)
    end
    return nothing
end

# ── Block segmentation ───────────────────────────────────────────────────────
#
# A block is rendered the moment it is unambiguously closed, which is either a
# blank line (outside a fence) or a closing code fence. Both are cheap to
# recognise from a line at a time, which is all a token stream gives you.

const _FENCE = r"^ {0,3}(`{3,}|~{3,})"

# The opening run of a fenced code block, or "" if this line does not open one.
_fence_open(line::AbstractString) =
    (m = match(_FENCE, line)) === nothing ? "" : String(m.captures[1])

# Whether `line` closes a fence opened by `open`: same character, at least as
# long, and nothing after it — a closing fence carries no info string, which is
# what stops "```julia" inside a block from being read as the close.
function _fence_closes(line::AbstractString, open::AbstractString)
    m = match(_FENCE, line)
    m === nothing && return false
    run = String(m.captures[1])
    (first(run) == first(open) && length(run) >= length(open)) || return false
    return isempty(strip(chopprefix(line, m.match)))
end

# Four spaces or a tab: an indented code block. Blank lines belong to it, so a
# blank line must NOT close a block that is in the middle of one.
_indented_code(line::AbstractString) = startswith(line, "    ") || startswith(line, "\t")

"""
Streaming sink that renders each markdown block as soon as it closes.

Markdown has no meaning until a block is closed — a fence, a list, a table only
has a shape once it ends — so a reply cannot be rendered token by token. The
first version of this streamed the whole reply raw and redrew it once at the
end, which meant any reply taller than the window stayed raw forever: `\\e[0J`
cannot erase what has already scrolled into scrollback, so the redraw had to be
skipped rather than shred the terminal. In practice that is most replies of
substance — a 47-row answer needs a 49-row window.

Blocks are individually short, so redrawing one at a time removes the height
limit instead of working around it, and formats sooner besides: a code fence
gets syntax-highlighted the moment it closes rather than after the last token.

Raw text still streams live, character by character. When a block closes,
exactly the rows it occupies are erased and reprinted formatted.

`render = false` makes this a plain passthrough, which is what a non-tty gets:
`\\e[nA` has nowhere to move a cursor a pipe does not have.
"""
mutable struct _MDSink
    io::IO
    render::Bool
    block::IOBuffer     # complete lines of the block being accumulated
    partial::String     # bytes after the last newline — printed, not yet a line
    fence::String       # the opening run while inside a code fence, else ""
    indented::Bool      # last non-blank line was indented code
    col0::Bool          # cursor is at column 0
end

_MDSink(io::IO; render::Bool = false) =
    _MDSink(io, render, IOBuffer(), "", "", false, true)

"""
Feed one complete line (including its newline). Returns the block's raw text if
this line closed one, `nothing` otherwise.
"""
function _feed_line!(sk::_MDSink, line::AbstractString)
    write(sk.block, line)
    body = rstrip(line, '\n')

    if !isempty(sk.fence)
        if _fence_closes(body, sk.fence)
            sk.fence = ""
            return _take_block!(sk)
        end
        return nothing
    end

    op = _fence_open(body)
    if !isempty(op)
        sk.fence = op
        sk.indented = false
        return nothing
    end

    if isempty(strip(body))
        # Blank lines are interior to an indented code block, so one only ends
        # a block when we are not in the middle of one. When we are, the block
        # keeps growing and closes at the next blank line after the code ends —
        # which renders code + prose together, and parses identically.
        sk.indented && return nothing
        return _take_block!(sk)
    end

    sk.indented = _indented_code(body)
    return nothing
end

function _take_block!(sk::_MDSink)
    raw = String(take!(sk.block))
    sk.indented = false
    return isempty(raw) ? nothing : raw
end

"""
Render one closed block in place of the raw lines already on screen.

The caller guarantees the cursor sits at column 0 immediately below those
lines — which is why `_emit!` prints line by line and flushes BEFORE printing
the partial line that follows: with the partial already on screen the cursor
would be neither at column 0 nor `up` rows down, and `\\e[0J` would eat it.
"""
function _render_block!(sk::_MDSink, raw::AbstractString)
    isempty(strip(raw)) && return false
    h, w = displaysize(sk.io)
    up = _wrapped_lines(raw, w)
    # A single block taller than the window has already scrolled; leave it raw.
    (up == 0 || up + 1 >= h) && return false
    # Reproduce the raw block's own trailing blank lines so the spacing the
    # stream established is preserved — the renderer emits no trailing newline
    # of its own, so the first one also ends its last line.
    body = rstrip(raw, '\n')
    trailing = max(1, ncodeunits(raw) - ncodeunits(body))
    print(sk.io, "\e[$(up)A\r\e[0J")
    _show_markdown(sk.io, body)
    print(sk.io, "\n"^trailing)
    sk.col0 = true
    return true
end

"""
Stream `chunk` and render any block it completes.

Lines are printed one at a time rather than as one `print(chunk)` so that a
block closing mid-chunk is redrawn while the cursor is still directly below it.
"""
function _emit!(sk::_MDSink, chunk::AbstractString; onblock = b -> _render_block!(sk, b))
    isempty(chunk) && return nothing
    if !sk.render
        print(sk.io, chunk)
        sk.col0 = endswith(chunk, '\n')
        flush(sk.io)
        return nothing
    end

    rest = SubString(chunk)
    while (i = findfirst('\n', rest)) !== nothing
        head = SubString(rest, 1, i)
        print(sk.io, head)
        sk.col0 = true
        blk = _feed_line!(sk, sk.partial * head)
        sk.partial = ""
        blk === nothing || onblock(blk)
        rest = SubString(rest, nextind(rest, i))
    end
    if !isempty(rest)
        print(sk.io, rest)
        sk.partial *= rest
        sk.col0 = false
    end
    flush(sk.io)
    return nothing
end

"""
Close the stream: render whatever block is still open and leave the cursor at
column 0 on a fresh line.
"""
function _finish!(sk::_MDSink; onblock = b -> _render_block!(sk, b))
    if sk.render
        if !isempty(sk.partial)
            # Give the last line the newline it never got, so this block ends at
            # column 0 like every other one and the cursor math is unchanged.
            print(sk.io, "\n")
            sk.col0 = true
            blk = _feed_line!(sk, sk.partial * "\n")
            sk.partial = ""
            blk === nothing || onblock(blk)
        end
        # An unterminated fence (a reply cut off at max_tokens) lands here;
        # _show_markdown's fallback is what keeps that from costing the text.
        blk = _take_block!(sk)
        blk === nothing || onblock(blk)
    end
    sk.col0 || print(sk.io, "\n")
    sk.col0 = true
    flush(sk.io)
    return nothing
end

"""
    _segment(text; chunk = typemax(Int)) -> Vector{String}

The blocks the streaming renderer would flush for `text`, delivered `chunk`
bytes at a time. Exists so the tests can prove segmentation does not depend on
where the token boundaries happen to fall — a model splits text at its own
whims, and a splitter that only works on whole lines would look fine until it
did not.
"""
function _segment(text::AbstractString; chunk::Integer = typemax(Int))
    sk = _MDSink(devnull; render = true)
    blocks = String[]
    collect_block = b -> push!(blocks, b)
    i = firstindex(text)
    while i <= lastindex(text)
        j = thisind(text, min(i + Int(chunk) - 1, lastindex(text)))
        _emit!(sk, SubString(text, i, j); onblock = collect_block)
        i = nextind(text, j)
    end
    _finish!(sk; onblock = collect_block)
    return blocks
end

# ─────────────────────────────────────────────────────────────────────────────
# Response — what chat() hands back
# ─────────────────────────────────────────────────────────────────────────────

struct Response
    text::String
    n_prompt::Int          # tokens fed in this turn
    n_gen::Int             # tokens generated
    t_prompt::Float64      # seconds
    t_gen::Float64
    stop::Symbol           # :eog | :max_tokens | :ctx_full | :decode_error | :interrupt
    streamed::Bool
end

Base.String(r::Response)          = r.text
Base.print(io::IO, r::Response)   = print(io, r.text)
Base.show(io::IO, r::Response)    = show(io, r.text)
Base.length(r::Response)          = length(r.text)
Base.isempty(r::Response)         = isempty(r.text)
Base.:(*)(a::AbstractString, r::Response) = a * r.text
Base.:(*)(r::Response, a::AbstractString) = r.text * a

function _stats_line(r::Response)
    pps = r.t_prompt > 0 ? r.n_prompt / r.t_prompt : 0.0
    gps = r.t_gen    > 0 ? r.n_gen    / r.t_gen    : 0.0
    tag = r.stop === :eog ? "" : " · stopped: $(r.stop)"
    return "[$(r.n_prompt) prompt tok @ $(round(pps, digits=1))/s · " *
           "$(r.n_gen) gen tok @ $(round(gps, digits=1))/s$tag]"
end

# When the text already streamed to the terminal, echoing it again as the REPL
# return value is just noise — show the throughput instead. A response that was
# NOT streamed still owes the caller its content, and gets it formatted: this is
# the display path, and the display path always formats.
function Base.show(io::IO, ::MIME"text/plain", r::Response)
    r.streamed ? printstyled(io, _stats_line(r); color = :light_black) :
                 _show_markdown(io, r.text)
end

# ─────────────────────────────────────────────────────────────────────────────
# ChatSession
# ─────────────────────────────────────────────────────────────────────────────

mutable struct ChatSession
    name::String
    path::String
    model::Ptr{L.llama_model}
    ctx::Ptr{L.llama_context}
    vocab::Ptr{L.llama_vocab}
    smpl::Ptr{L.llama_sampler}
    template::Union{String,Nothing}
    system::String
    history::Vector{Pair{String,String}}   # role => content
    decoded::Vector{UInt8}                 # exact transcript bytes now in the KV cache
    n_past::Int
    n_ctx::Int
    n_batch::Int
    verbose::Bool
    isopen::Bool
end

"""
    ChatSession(model = default_model(); kwargs...)

Load a model and open a context. `model` is an ollama name or a path.

  `system`       system prompt (default none)
  `n_ctx`        context window (default 32768; model trains to 262144)
  `n_threads`    default = physical cores (SMT threads / 2)
  `n_gpu_layers` default 0 — this build is CPU-only (no ggml GPU backends)
  `temp`         default 0.7; `temp <= 0` selects greedy sampling
  `top_k`/`top_p`/`min_p`  default 40 / 0.95 / 0.05
  `seed`         default random
  `verbose`      let llama.cpp's loader log to stderr (default false)
  `log`          where the one-line load progress goes (default stderr)

`log` exists because a 35 s load has to say something, and where that something
belongs depends on who is waiting for it. At the REPL it is stderr. For the
sidecar window it is the window — a line appearing in a REPL you are typing into,
asynchronously, several seconds after you moved on, is worse than no line.
"""
function ChatSession(model::AbstractString = default_model();
                     system::AbstractString = "",
                     log::IO = stderr,
                     n_ctx::Integer = 32768,
                     n_batch::Integer = 512,
                     n_threads::Integer = max(1, Sys.CPU_THREADS ÷ 2),
                     n_gpu_layers::Integer = 0,
                     temp::Real = 0.7,
                     top_k::Integer = 40,
                     top_p::Real = 0.95,
                     min_p::Real = 0.05,
                     seed::Integer = rand(UInt32),
                     verbose::Bool = false)

    path = resolve_model(model)
    _ensure_backend(verbose)

    verbose || (print(log, "loading $model … "); flush(log))
    t0 = time_ns()

    # 72-byte MEMORY-class struct, returned by value then passed by value into
    # a Tier-2 JIT thunk.
    mp = L.setproperties(L.llama_model_default_params(); n_gpu_layers = Int32(n_gpu_layers))
    m = _quiet(verbose) do
        L.llama_model_load_from_file(path, mp)
    end
    m == C_NULL && error("model load failed: $path")

    # 160-byte MEMORY-class struct, same round trip.
    cp = L.setproperties(L.llama_context_default_params();
                         n_ctx           = UInt32(n_ctx),
                         n_batch         = UInt32(n_batch),
                         n_ubatch        = UInt32(n_batch),
                         n_threads       = Int32(n_threads),
                         n_threads_batch = Int32(n_threads))
    ctx = _quiet(verbose) do
        L.llama_init_from_model(m, cp)
    end
    if ctx == C_NULL
        L.llama_model_free(m)
        error("context creation failed (n_ctx=$n_ctx)")
    end

    vocab = L.llama_model_get_vocab(m)

    # Sampler chain. llama_sampler_chain_params is another by-value struct.
    scp   = L.llama_sampler_chain_default_params()
    chain = L.llama_sampler_chain_init(scp)
    if temp <= 0
        L.llama_sampler_chain_add(chain, L.llama_sampler_init_greedy())
    else
        top_k > 0     && L.llama_sampler_chain_add(chain, L.llama_sampler_init_top_k(Int32(top_k)))
        top_p < 1     && L.llama_sampler_chain_add(chain, L.llama_sampler_init_top_p(Cfloat(top_p), 1))
        min_p > 0     && L.llama_sampler_chain_add(chain, L.llama_sampler_init_min_p(Cfloat(min_p), 1))
        L.llama_sampler_chain_add(chain, L.llama_sampler_init_temp(Cfloat(temp)))
        L.llama_sampler_chain_add(chain, L.llama_sampler_init_dist(UInt32(seed)))
    end

    # Cstring return: the model's own chat template, or nothing. `nothing`
    # becomes C_NULL below, which llama_chat_apply_template reads as "chatml".
    tmpl = L.llama_model_chat_template(m, C_NULL)

    s = ChatSession(String(model), path, m, ctx, vocab, chain, tmpl, String(system),
                    Pair{String,String}[], UInt8[], 0, Int(n_ctx), Int(n_batch),
                    verbose, true)

    verbose || (println(log, "ok  ($(round((time_ns()-t0)/1e9, digits=1))s, " *
                             "n_ctx=$n_ctx, $n_threads threads, " *
                             "template=$(tmpl === nothing ? "chatml (fallback)" : "built-in"))");
                flush(log))
    return s
end

# Freeing a context logs too (`~llama_context: CPU compute buffer size …`), and
# that line is the one that lands on a REPL prompt seconds after you moved on.
# Same treatment as the load.
function close!(s::ChatSession)
    s.isopen || return s
    _quiet(s.verbose) do
        s.smpl  != C_NULL && L.llama_sampler_free(s.smpl)
        s.ctx   != C_NULL && L.llama_free(s.ctx)
        s.model != C_NULL && L.llama_model_free(s.model)
    end
    s.smpl = s.ctx = C_NULL; s.model = C_NULL
    s.isopen = false
    return s
end

# Throw away the KV cache but keep the conversation. The next turn re-decodes
# the whole transcript — slower, but it cannot inherit a corrupt prefix.
function _invalidate!(s::ChatSession)
    mem = L.llama_get_memory(s.ctx)
    mem != C_NULL && L.llama_memory_clear(mem, true)
    empty!(s.decoded)
    s.n_past = 0
    return s
end

"""
    reset!(session) -> session

Drop the conversation and clear the KV cache. The model stays loaded.
"""
function reset!(s::ChatSession)
    empty!(s.history)
    _invalidate!(s)
    L.llama_sampler_reset(s.smpl)
    return s
end

function Base.show(io::IO, s::ChatSession)
    st = s.isopen ? "$(s.n_past)/$(s.n_ctx) tok, $(length(s.history)) msgs" : "closed"
    print(io, "ChatSession(\"$(s.name)\", $st)")
end

# ─────────────────────────────────────────────────────────────────────────────
# Prompt formatting — llama_chat_apply_template over an array of C structs
# ─────────────────────────────────────────────────────────────────────────────

function _messages(s::ChatSession)
    msgs = Pair{String,String}[]
    isempty(s.system) || push!(msgs, "system" => s.system)
    append!(msgs, s.history)
    return msgs
end

"""
Render `msgs` through the model's chat template. Returns the formatted
transcript as bytes (the byte level is what matters — the delta we feed to the
tokenizer has to be a byte-exact suffix).
"""
function _format(s::ChatSession, msgs::Vector{Pair{String,String}}, add_ass::Bool)
    isempty(msgs) && return UInt8[]
    n = length(msgs)

    roles = [_cstr(first(m)) for m in msgs]
    conts = [_cstr(last(m))  for m in msgs]
    tmpl  = s.template === nothing ? C_NULL : s.template

    return GC.@preserve roles conts begin
        cmsgs = [L.llama_chat_message(pointer(roles[i]), pointer(conts[i])) for i in 1:n]
        cap = 2 * sum(length, conts; init = 0) + 256 * n + 512
        buf = Vector{UInt8}(undef, cap)
        res = GC.@preserve cmsgs buf begin
            L.llama_chat_apply_template(tmpl, cmsgs, n, add_ass, buf, Int32(length(buf)))
        end
        if res < 0
            if s.template !== nothing
                # Template string the C applier doesn't recognise (it is a
                # matcher over known templates, not a Jinja engine). ChatML is
                # the least-wrong universal fallback.
                @warn "model chat template not supported by llama_chat_apply_template; falling back to chatml" maxlog=1
                s.template = nothing
                return _format(s, msgs, add_ass)
            end
            error("llama_chat_apply_template failed (returned $res)")
        end
        if res > length(buf)                       # buffer was short — it told us how short
            buf = Vector{UInt8}(undef, res)
            res = GC.@preserve cmsgs buf begin
                L.llama_chat_apply_template(tmpl, cmsgs, n, add_ass, buf, Int32(length(buf)))
            end
            res < 0 && error("llama_chat_apply_template failed on retry (returned $res)")
        end
        resize!(buf, res)
        buf
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# Tokenize + decode
# ─────────────────────────────────────────────────────────────────────────────

function _tokenize(s::ChatSession, text::AbstractString, add_special::Bool)
    isempty(text) && return Int32[]
    nb = ncodeunits(text)
    toks = Vector{Int32}(undef, nb + 64)
    # parse_special = true is mandatory here: the transcript is full of
    # <|im_start|> / <|im_end|> markers that must become single control tokens
    # rather than a dozen literal-text tokens.
    n = L.llama_tokenize(s.vocab, text, Int32(nb), toks, Int32(length(toks)),
                         add_special, true)
    if n < 0
        resize!(toks, -n)
        n = L.llama_tokenize(s.vocab, text, Int32(nb), toks, Int32(length(toks)),
                             add_special, true)
        n < 0 && error("llama_tokenize failed (needs $(-n) tokens)")
    end
    resize!(toks, n)
    return toks
end

# Feed tokens through llama_decode in n_batch-sized chunks. llama_batch_get_one
# tracks positions itself, so this just has to not exceed the batch size.
function _decode!(s::ChatSession, toks::Vector{Int32})
    isempty(toks) && return 0
    i = 1
    while i <= length(toks)
        j = min(i + s.n_batch - 1, length(toks))
        chunk = toks[i:j]                       # a plain Vector; ccall needs contiguous memory
        rc = GC.@preserve chunk begin
            batch = L.llama_batch_get_one(chunk, Int32(length(chunk)))
            L.llama_decode(s.ctx, batch)
        end
        rc != 0 && return rc
        s.n_past += length(chunk)
        i = j + 1
    end
    return 0
end

# ─────────────────────────────────────────────────────────────────────────────
# Generation
# ─────────────────────────────────────────────────────────────────────────────

function _generate!(s::ChatSession, max_tokens::Int, stream::Bool, sink::_MDSink)
    piece   = Vector{UInt8}(undef, 256)
    pending = UInt8[]
    out     = IOBuffer()
    ngen    = 0
    stop    = :max_tokens

    for _ in 1:max_tokens
        if s.n_past >= s.n_ctx
            stop = :ctx_full
            break
        end

        # Ctrl-C stops generation without corrupting the session: every token
        # already decoded is accounted for in `out`, and the caller appends
        # exactly that to s.decoded, so cache and transcript stay in step.
        tok = try
            L.llama_sampler_sample(s.smpl, s.ctx, Int32(-1))
        catch e
            e isa InterruptException || rethrow()
            stop = :interrupt
            break
        end
        # NOTE: llama_sampler_sample already calls llama_sampler_accept
        # internally (src/llama-sampler.cpp:874) — accepting again here would
        # double-count for any stateful sampler in the chain.

        if _is_eog(s.vocab, tok)
            stop = :eog
            break
        end

        np = L.llama_token_to_piece(s.vocab, tok, piece, Int32(length(piece)), Int32(0), false)
        if np < 0
            resize!(piece, -np)
            np = L.llama_token_to_piece(s.vocab, tok, piece, Int32(length(piece)), Int32(0), false)
            np < 0 && error("llama_token_to_piece failed for token $tok")
        end

        # Feed the token back BEFORE emitting its text. The caller appends
        # exactly this text to s.decoded, so emitting first would let a failure
        # (or Ctrl-C) between the two leave a byte in the transcript whose token
        # never reached the cache — the one drift the incremental path can't see.
        one = Int32[tok]
        rc = try
            GC.@preserve one begin
                batch = L.llama_batch_get_one(one, Int32(1))
                L.llama_decode(s.ctx, batch)
            end
        catch e
            e isa InterruptException || rethrow()
            stop = :interrupt
            break
        end
        if rc != 0
            @warn "llama_decode returned $rc during generation" n_past=s.n_past
            stop = :decode_error
            break
        end
        s.n_past += 1
        ngen += 1

        append!(pending, view(piece, 1:np))
        chunk = _take_utf8!(pending)
        if !isempty(chunk)
            write(out, chunk)
            stream && _emit!(sink, chunk)
        end
    end

    # Anything left in `pending` is a truncated code point; emit it so the text
    # round-trips byte-for-byte rather than silently dropping bytes.
    if !isempty(pending)
        tail = String(pending)
        write(out, tail)
        stream && _emit!(sink, tail)
    end
    return String(take!(out)), ngen, stop
end

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

"""
    LlamaChat.chat(session, prompt; kwargs...) -> Response

Send `prompt` as a user turn and generate the reply. The session keeps the
conversation, so follow-up turns see what came before; `reset!` clears it.

  `max_tokens` cap on generated tokens (default 4096)
  `stream`     print tokens as they arrive (default true)
  `io`         where to stream (default stdout)

The reply is `r.text`. When streamed, the REPL shows a throughput line instead
of repeating the text, which is already on screen.

Streamed to a terminal, tokens appear live as plain text and each markdown block
is reprinted formatted the moment it closes — so a code fence is highlighted as
soon as it ends, and reply length does not matter. There is no kwarg for this:
the redraw is cursor arithmetic, so it is available exactly when `io` is a tty
and meaningless when it is not. See `_MDSink`.

Not exported — `load` is the front door. This is the scripting entry point.
"""
function chat(s::ChatSession, prompt::AbstractString;
              max_tokens::Integer = 4096, stream::Bool = true, io::IO = stdout)
    s.isopen || error("session is closed")

    push!(s.history, "user" => String(prompt))
    formatted = _format(s, _messages(s), true)   # add_ass: end with the assistant header

    # `s.decoded` is exactly what the KV cache holds. Normally the new transcript
    # extends it and we only tokenize the tail. If a template re-renders earlier
    # turns (some do), the prefix breaks — then re-decode from scratch rather
    # than feeding the model a transcript it never saw.
    npre = length(s.decoded)
    if npre > length(formatted) || @views formatted[1:npre] != s.decoded
        s.verbose && @info "chat template re-rendered history; rebuilding KV cache"
        _invalidate!(s)
        npre = 0
    end
    deltab = formatted[npre+1:end]

    t0   = time_ns()
    toks = _tokenize(s, String(copy(deltab)), npre == 0)   # BOS only on the first chunk
    if s.n_past + length(toks) >= s.n_ctx
        pop!(s.history)
        error("prompt needs $(s.n_past + length(toks)) tokens but n_ctx is $(s.n_ctx) — " *
              "reset!(session) or reopen with a larger n_ctx")
    end
    rc = _decode!(s, toks)
    if rc != 0
        pop!(s.history)
        error("llama_decode returned $rc while evaluating the prompt")
    end
    append!(s.decoded, deltab)
    t_prompt = (time_ns() - t0) / 1e9

    t1 = time_ns()
    # Blocks are rendered as they close, so the reply formats progressively and
    # its height never matters — see `_MDSink`.
    sink = _MDSink(io; render = stream && _istty(io))
    text, ngen, stop = try
        _generate!(s, Int(max_tokens), stream, sink)
    catch
        # Generation died partway: the cache holds tokens no transcript records.
        # Drop the cache (not the conversation) so the next turn rebuilds from a
        # known-good state instead of appending to a phantom prefix.
        _invalidate!(s)
        pop!(s.history)
        rethrow()
    end
    t_gen = (time_ns() - t1) / 1e9
    # Renders the block still open and leaves the cursor at column 0.
    stream && _finish!(sink)

    push!(s.history, "assistant" => text)
    # The generated bytes sit immediately after the assistant header, so the KV
    # cache now corresponds to exactly this many transcript bytes. The closing
    # <|im_end|> was sampled but deliberately not decoded — it arrives as part
    # of the next turn's delta, which keeps cache and transcript in step.
    append!(s.decoded, codeunits(text))

    return Response(text, length(toks), ngen, t_prompt, t_gen, stop, stream)
end

# ─────────────────────────────────────────────────────────────────────────────
# The chat interface
# ─────────────────────────────────────────────────────────────────────────────

const _COMMANDS = (
    ("/reset",          "forget the conversation, keep the model loaded"),
    ("/system <text>",  "set the system prompt (clears the conversation)"),
    ("/stats",          "context use, message count, transcript size"),
    ("/help",           "this list"),
    ("/exit",           "free the model and return to Julia"),
)

function _help(io::IO)
    w = maximum(length(first(c)) for c in _COMMANDS)
    for (verb, what) in _COMMANDS
        printstyled(io, "  ", rpad(verb, w); bold = true)
        printstyled(io, "  ", what, "\n"; color = :light_black)
    end
    return nothing
end

_note(msg) = printstyled("(", msg, ")\n"; color = :light_black)

"""
Read-eval-print over a live session. Returns when the user leaves; freeing the
model is the caller's job, so that `load` owns the whole lifetime and a throw
out of here still frees.
"""
function _repl!(s::ChatSession)
    printstyled("\n", s.name; bold = true)
    printstyled("  ·  $(s.n_ctx) ctx  ·  /help for commands\n"; color = :light_black)

    while true
        print("\n"); printstyled(">>> "; bold = true, color = :green); flush(stdout)
        # eof() before readline(), not after: on a tty it blocks until a byte is
        # available (which is the wait we want anyway) and on a pipe it is the
        # only honest end signal. Checking it after readline() would swallow the
        # last line of piped input and stall a tty on every turn.
        eof(stdin) && (println(); break)
        line = strip(readline(stdin))
        isempty(line) && continue

        if startswith(line, "/")
            cmd  = split(line, ' '; limit = 2)
            verb = cmd[1]
            rest = length(cmd) > 1 ? strip(cmd[2]) : ""
            if verb in ("/exit", "/quit", "/bye", "/q")
                break
            elseif verb in ("/reset", "/clear")
                reset!(s); _note("conversation cleared")
            elseif verb == "/system"
                isempty(rest) && (_note("usage: /system <text>"); continue)
                s.system = String(rest); reset!(s)
                _note("system prompt set, conversation cleared")
            elseif verb == "/stats"
                _note("$(s.n_past)/$(s.n_ctx) tokens · $(length(s.history)) messages · " *
                      "$(length(s.decoded)) transcript bytes")
            elseif verb in ("/help", "/?")
                _help(stdout)
            else
                _note("unknown command: $verb — /help for the list")
            end
            continue
        end

        print("\n")
        try
            r = chat(s, line)
            printstyled(_stats_line(r), "\n"; color = :light_black)
        catch e
            # Ctrl-C stops the turn, not the loop — `chat` has already rolled the
            # session back to a consistent state, so there is nothing to leave.
            # /exit and Ctrl-D are the ways out.
            if e isa InterruptException
                println(); _note("interrupted")
            else
                printstyled("error: ", sprint(showerror, e), "\n"; color = :red)
            end
        end
    end
    return s
end

"""
    load([model]; kwargs...)

Load a model and start talking to it. `model` is an ollama name
(`"qwen3-coder"`, `"gemma4:e2b"`, `"igorls/gemma-4-E4B-it-heretic-GGUF:latest"`)
or a path to a `.gguf`; with no argument it opens `default_model()` —
`\$LLAMACPP_CHAT_MODEL`, else `qwen3-coder`. `list_models()` shows what is here.

In the chat loop: `/reset`, `/system <text>`, `/stats`, `/help`, `/exit`.
Ctrl-C stops a reply without leaving; Ctrl-D leaves like `/exit`.

`/exit` frees the context and the weights and returns to the Julia prompt with
nothing resident, so the next `load` starts clean — including on a model that
failed halfway, since the teardown is in a `finally`. The cost of that is a full
reload to resume (~35 s for a 30B MoE off warm cache), which is the trade: no
lingering 18 GB you have to remember to drop.

Keywords are `ChatSession`'s — `system`, `n_ctx` (default 32768), `n_threads`,
`temp`, `top_k`/`top_p`/`min_p`, `seed`, `verbose`:

```julia
load()
load("qwen2.5-coder:1.5b-base"; temp = 0)          # greedy
load("qwen3-coder"; system = "You are terse.", n_ctx = 8192)
```
"""
function load(model::AbstractString = default_model(); kwargs...)
    s = ChatSession(model; kwargs...)
    try
        _repl!(s)
    finally
        close!(s)
        _note("unloaded")
    end
    return nothing
end

# `ask` — same model, same process, answers in a second terminal window while
# this REPL stays yours. Kept in its own file because it is terminal plumbing
# (ptys, ioctls, kitty remote control), not part of the ABI story above.
include("window.jl")

function __init__()
    # A @cfunction pointer is this process's, so it cannot be baked into the .ji.
    _LOG_CB[] = @cfunction(_llama_log, Cvoid, (Cint, Ptr{Cchar}, Ptr{Cvoid}))
    _atexit_teardown()
    return nothing
end

end # module LlamaChat
