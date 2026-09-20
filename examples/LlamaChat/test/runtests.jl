using Test
using LlamaChat
using RepliBuild
using Markdown

const LC = LlamaChat

# Pick the smallest *generative* model in the local ollama store — embedding
# models have no generation head, so they are excluded. Override with
# $LLAMACHAT_TEST_MODEL.
function test_model()
    haskey(ENV, "LLAMACHAT_TEST_MODEL") && return ENV["LLAMACHAT_TEST_MODEL"]
    cands = filter(m -> !occursin("embed", lowercase(first(m))), LC.list_models())
    isempty(cands) && return nothing
    return first(cands[end])          # list_models sorts by size, descending
end

const MODEL = test_model()

@testset "LlamaChat (chat app on RepliBuild wrapper)" begin

@testset "Tier 2 runs off AOT thunks, with no JIT engine" begin
    # The vendored wrapper is built with `aot_thunks = true`, so its Tier-2
    # thunks were compiled into libllamacpp_thunks.so at build time and loading
    # it is a dlopen. This testset used to assert the opposite — one registered
    # JIT engine — because that was the only way Tier 2 had ever worked. Both
    # spellings dispatch through the same thunks; the difference is that this
    # one does not construct a 43k-line MLIR module in every process that says
    # `using LlamaChat` (24.8s → 5.4s for the wrapper alone).
    @test isempty(RepliBuild.JITManager.GLOBAL_JIT.engines)

    # The thunks library must be the SIBLING copy, not the one in the package
    # tree this wrapper was generated from. It is linked `-Wl,-rpath,$ORIGIN`
    # ahead of its build directory precisely so a vendored set stays
    # self-contained; without that the loader satisfies the thunks library's
    # own `NEEDED libllamacpp.so` from the build tree, and the process ends up
    # with TWO copies of a 41 MB library — each with its own static state, both
    # torn down at exit. That is not a hypothetical: it aborted with
    # `double free or corruption (!prev)` on the way out, after every test had
    # already passed.
    @test isfile(joinpath(@__DIR__, "..", "lib", "libllamacpp_thunks.so"))
    @test occursin("lib", LC.L.THUNKS_LIBRARY_PATH)
    @test isfile(LC.L.THUNKS_LIBRARY_PATH)
    @test LC.L.THUNKS_HANDLE[] != C_NULL

    # One mapping of the library, from lib/ — the assertion the abort would fail.
    maps = read("/proc/self/maps", String)
    loaded = unique([m.match for m in eachmatch(r"/[^ \n]*libllamacpp\.so"m, maps)])
    @test length(loaded) == 1
    @test occursin(joinpath("LlamaChat", "lib"), only(loaded))
end

# ── Pure layers — no model required ──────────────────────────────────────────

@testset "incremental UTF-8 assembly" begin
    # A token is a byte sequence, not a character. Printing half a code point
    # corrupts the terminal, so partial tails are held back until completed.
    p = Vector{UInt8}("hello")
    @test LC._take_utf8!(p) == "hello"
    @test isempty(p)

    jp = Vector{UInt8}("日")                 # 3 bytes
    p = jp[1:2]                              # split mid-character
    @test LC._take_utf8!(p) == ""            # nothing emitted yet
    @test length(p) == 2                     # tail retained
    push!(p, jp[3])
    @test LC._take_utf8!(p) == "日"
    @test isempty(p)

    emoji = Vector{UInt8}("🔧")              # 4 bytes
    p = vcat(Vector{UInt8}("ok"), emoji[1:3])
    @test LC._take_utf8!(p) == "ok"          # ASCII flushes, partial emoji held
    @test length(p) == 3
    append!(p, emoji[4:4])
    @test LC._take_utf8!(p) == "🔧"

    p = UInt8[]
    @test LC._take_utf8!(p) == ""
end

@testset "terminal line accounting for the markdown redraw" begin
    # The redraw erases exactly the lines the raw text occupied, so this count
    # has to include soft wraps and double-width characters — an undercount
    # leaves debris on screen, an overcount eats the line above.
    @test LC._wrapped_lines("", 80) == 0
    @test LC._wrapped_lines("abc", 80) == 1
    @test LC._wrapped_lines("a\nb", 80) == 2
    @test LC._wrapped_lines("a\nb\n", 80) == 2      # trailing newline ends line 2
    @test LC._wrapped_lines(repeat("x", 80), 80) == 1
    @test LC._wrapped_lines(repeat("x", 81), 80) == 2
    @test LC._wrapped_lines(repeat("x", 160), 80) == 2
    @test LC._wrapped_lines(repeat("日", 40), 80) == 1   # 2 columns each
    @test LC._wrapped_lines(repeat("日", 41), 80) == 2
    @test LC._wrapped_lines("hi", 0) == 2                # width clamps to 1: one char per line
end

@testset "markdown block segmentation" begin
    # A block is renderable the moment it is unambiguously closed: a blank line
    # outside a fence, or a closing fence. Everything here is about not closing
    # one early, because a half-block renders as the wrong thing entirely.
    @test LC._segment("para one\n\npara two\n") == ["para one\n\n", "para two\n"]

    # A blank line INSIDE a fence must not split it — this is the case that
    # turns a code block into two paragraphs of source.
    fenced = "```julia\nf(x) = 1\n\ng(x) = 2\n```\n"
    @test LC._segment(fenced) == [fenced]

    # A fence closes its block immediately, without waiting for a blank line:
    # syntax highlighting is the whole reason to render early.
    @test LC._segment("```\ncode\n```\ntext after\n") ==
          ["```\ncode\n```\n", "text after\n"]

    # "```julia" carries an info string, so it opens rather than closes.
    @test length(LC._segment("````\n```julia\nnested\n```\n````\n")) == 1

    # Blank lines are interior to an INDENTED code block; closing on one would
    # split it and the second half would stop being code. The consequence is
    # that the run stays open until a blank line arrives with the code already
    # behind us, so the code and the prose after it render as one block — which
    # parses to exactly the same thing, just later and in one go.
    indented = "    line one\n\n    line two\n\nprose\n"
    @test LC._segment(indented) == [indented]
    @test LC._segment(indented * "\nmore\n") == [indented * "\n", "more\n"]

    # Headings and lists ride on the blank-line rule.
    @test LC._segment("# H\n\n- a\n- b\n\n") == ["# H\n\n", "- a\n- b\n\n"]

    # A trailing block with no closing blank line still gets flushed.
    @test LC._segment("only a paragraph") == ["only a paragraph\n"]
    # ...and an unterminated fence (a reply cut off at max_tokens) comes out
    # whole rather than being dropped.
    @test LC._segment("```julia\nx = 1") == ["```julia\nx = 1\n"]

    @test isempty(LC._segment(""))

    # Tokens do not respect line boundaries. Segmentation must not depend on
    # where the model happened to split, so drive the same text one byte at a
    # time — including multi-byte characters, which must not be cut mid-point.
    doc = "# Título\n\nprose 日本語\n\n```julia\nx = 1\n```\n\ntail\n"
    whole = LC._segment(doc)
    for n in (1, 2, 3, 7, 64)
        @test LC._segment(doc; chunk = n) == whole
    end
    @test join(whole) == doc
end

# A terminal just far enough along to prove the cursor math: an undercount
# leaves debris on screen and an overcount eats the line above, and neither is
# visible in the escape sequence itself — only in what the screen ends up
# holding. Handles what the renderer emits: text, \n, \e[<n>A, \r, \e[0J.
function screen(out::AbstractString; w = 80, h = 40)
    rows = [Char[]]                      # per-row Chars: the renderer emits ≡ and •
    r, c = 1, 1
    ensure(n) = while length(rows) < n; push!(rows, Char[]); end
    put(ch) = begin
        ensure(r)
        row = rows[r]
        while length(row) < c - 1; push!(row, ' '); end
        length(row) >= c ? (row[c] = ch) : push!(row, ch)
        c += 1
        c > w && (r += 1; c = 1; ensure(r))
    end
    i = firstindex(out)
    while i <= lastindex(out)
        ch = out[i]
        if ch == '\e' && i < lastindex(out) && out[nextind(out, i)] == '['
            j = nextind(out, i, 2)
            while j <= lastindex(out) && !isletter(out[j]); j = nextind(out, j); end
            body, verb = out[nextind(out, i, 2):prevind(out, j)], out[j]
            if verb == 'A'
                r = max(1, r - (isempty(body) ? 1 : parse(Int, body)))
            elseif verb == 'J' && body in ("", "0")
                ensure(r)
                length(rows[r]) >= c && deleteat!(rows[r], c:length(rows[r]))
                length(rows) > r && deleteat!(rows, (r+1):length(rows))
            end
            i = nextind(out, j); continue
        elseif ch == '\n'
            r += 1; c = 1; ensure(r)
        elseif ch == '\r'
            c = 1
        else
            put(ch)
        end
        i = nextind(out, i)
    end
    return rstrip(join((rstrip(String(row)) for row in rows), "\n"))
end

@testset "block rendering replaces exactly its own rows" begin
    # Sanity-check the simulator itself before trusting it as an oracle.
    @test screen("abc") == "abc"
    @test screen("one\ntwo\n") == "one\ntwo"
    @test screen("one\ntwo\n\e[2A\rX") == "Xne\ntwo"
    @test screen("one\ntwo\n\e[2A\r\e[0J") == ""
    @test screen("keep\none\ntwo\n\e[2A\r\e[0Jnew\n") == "keep\nnew"

    render(doc; w = 80, h = 40, chunk = typemax(Int)) = begin
        buf = IOBuffer()
        io  = IOContext(buf, :displaysize => (h, w), :color => false)
        sk  = LC._MDSink(io; render = true)
        i = firstindex(doc)
        while i <= lastindex(doc)
            j = thisind(doc, min(i + chunk - 1, lastindex(doc)))
            LC._emit!(sk, SubString(doc, i, j)); i = nextind(doc, j)
        end
        LC._finish!(sk)
        screen(String(take!(buf)); w = w, h = h)
    end

    # Raw markdown must not survive: the source line is gone, the rendered
    # heading is there. Debris from a short redraw shows up as the '#' still
    # being on screen.
    out = render("# Title\n\nsome prose\n")
    @test !occursin("# Title", out)
    @test occursin("Title", out)
    @test occursin("≡", out)                      # heading rule
    @test occursin("some prose", out)

    # The line ABOVE the reply must survive — an overcount eats it.
    out = render("para\n\n")
    sk_out = let buf = IOBuffer()
        io = IOContext(buf, :displaysize => (40, 80), :color => false)
        print(io, "PROMPT LINE\n")
        sk = LC._MDSink(io; render = true)
        LC._emit!(sk, "para\n\n"); LC._finish!(sk)
        screen(String(take!(buf)))
    end
    @test startswith(sk_out, "PROMPT LINE")
    @test occursin("para", sk_out)

    # Several blocks in sequence: each redraw must land on its own rows, so
    # nothing earlier is clobbered and nothing raw is left behind.
    doc = "# H\n\nfirst para\n\n- a\n- b\n\nlast para\n"
    out = render(doc)
    for want in ("H", "first para", "a", "b", "last para")
        @test occursin(want, out)
    end
    @test !occursin("# H", out)
    @test !occursin("- a", out)
    # ...and the order is preserved.
    @test findfirst("first para", out).start < findfirst("last para", out).start

    # Independent of how the stream was chopped.
    @test render(doc; chunk = 1) == out
    @test render(doc; chunk = 5) == out

    # A block taller than the window is left raw rather than half-erased: its
    # top has already scrolled past what \e[0J can reach.
    tall = join(("line $i" for i in 1:30), "\n") * "\n\n"
    out = render(tall; h = 10)
    @test occursin("line 1", out) && occursin("line 30", out)

    # Not a tty (render = false) must emit no escapes at all — a pipe or a file
    # gets plain text.
    buf = IOBuffer()
    sk = LC._MDSink(buf; render = false)
    LC._emit!(sk, "# Title\n\nprose\n"); LC._finish!(sk)
    plain = String(take!(buf))
    @test !occursin('\e', plain)
    @test plain == "# Title\n\nprose\n"
end

@testset "headings do not render as their own source" begin
    # Julia's terminal backend picks a header underline by level from
    # `Markdown._header_underlines = collect("≡=–-⋅ ")`. h1's `≡` reads as
    # decoration, but h2's is plain ASCII `=` — and a bold line above
    # `==========` is character-for-character what setext markdown SOURCE looks
    # like, so a correctly rendered `## Heading` looks like a renderer that
    # failed to strip the syntax. Models reach for `##` constantly, so this is
    # the common case rather than an edge one.
    h1 = sprint(io -> LC._show_markdown(io, "# Heading here"))
    @test occursin("Heading here", h1)
    @test occursin("≡", h1)                    # unambiguous, so h1 keeps its rule

    for lvl in 2:6
        out = sprint(io -> LC._show_markdown(io, "#"^lvl * " Heading here"))
        @test occursin("Heading here", out)     # the text always survives
        @test !occursin("==", out)              # ...with no rule that reads as setext
        @test !occursin("--", out)
        @test !occursin("––", out)
        @test !occursin("#", out)               # and no ATX marker left behind
    end

    # Inline formatting inside a heading still renders rather than being flattened.
    out = sprint(io -> LC._show_markdown(io, "## A `code` and **bold** heading"))
    @test occursin("code", out) && occursin("bold", out)
    @test !occursin("**", out) && !occursin("`", out)

    # A heading whose TEXT contains `=` must not lose it — the rule is what gets
    # dropped, not the content.
    @test occursin("a == b", sprint(io -> LC._show_markdown(io, "## a == b")))

    # Headings are still separated from surrounding prose.
    doc = sprint(io -> LC._show_markdown(io, "## Title\n\nbody text\n"))
    @test occursin("Title", doc) && occursin("body text", doc)
    @test findfirst("Title", doc).start < findfirst("body text", doc).start
end

@testset "markdown parsing and fallback" begin
    # A reply truncated at max_tokens is malformed by construction — an
    # unterminated fence must never cost us the generation.
    out = sprint(io -> LC._show_markdown(io, "text\n\n```julia\nx = 1"))
    @test occursin("x = 1", out)
    out2 = sprint(io -> LC._show_markdown(io, "| a | b |\n|---|"))
    @test !isempty(out2)

    # Non-tty: never emit cursor-movement escapes into a pipe or a file. The
    # sink's `render` defaults to off, so a plain IO passes text straight
    # through — the block redraw is opt-in, not opt-out.
    buf = IOBuffer()
    sk = LC._MDSink(buf)
    LC._emit!(sk, "# hi\n\nthere\n")
    LC._finish!(sk)
    @test String(take!(buf)) == "# hi\n\nthere\n"
end

@testset "Response display formats unconditionally" begin
    # There is no `markdown` field any anymore, and no kwarg feeding it. A reply
    # that did not stream still owes the caller its content, and the display path
    # is a display path: it formats.
    r = LC.Response("**bold**", 1, 1, 0.1, 0.1, :eog, false)
    shown = sprint(show, MIME"text/plain"(), r)
    @test occursin("bold", shown)
    @test !occursin("**", shown)                     # went through the renderer

    # A streamed reply shows throughput instead — its text is already on screen,
    # so printing it again as the REPL's return value is noise.
    streamed = LC.Response("**bold**", 1, 1, 0.1, 0.1, :eog, true)
    @test occursin("tok", sprint(show, MIME"text/plain"(), streamed))

    # String interop is unaffected by the field going away.
    @test String(r) == "**bold**"
    @test ("got: " * r) == "got: **bold**"
    @test sprint(print, r) == "**bold**"              # print stays raw
end

@testset "tty detection follows isatty, not the concrete type" begin
    # The sidecar window is a pts we opened by path, so it is an IOStream that is
    # every bit a terminal. `io isa Base.TTY` said no and the reply streamed raw
    # into a window perfectly able to render it, so the question is delegated to
    # `isatty` — and IOContext is unwrapped, because the sidecar wraps its stream
    # to state a size and colour support and a wrapper around a terminal is one.
    @test !LC._istty(IOBuffer())
    @test !LC._istty(devnull)
    @test !LC._istty(IOContext(IOBuffer(), :color => true))

    # A real character device that is not a terminal must still be false.
    open("/dev/null", "w") do f
        @test !LC._istty(f)
        @test !LC._istty(IOContext(f, :color => true))
    end

    # ...and a real pty must be true through every wrapper. openpty(3) gives one
    # without needing a terminal to run the tests in.
    # Unqualified: openpty lived in libutil until glibc 2.34 folded it into libc,
    # and Arch is well past that — `("openpty", "libutil")` fails to dlopen here.
    mfd, sfd = Ref{Cint}(0), Ref{Cint}(0)
    rc = ccall(:openpty, Cint,
               (Ptr{Cint}, Ptr{Cint}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
               mfd, sfd, C_NULL, C_NULL, C_NULL)
    if rc == 0
        slave = fdio(sfd[], true)
        try
            @test LC._istty(slave)
            @test LC._istty(IOContext(slave, :color => true))
            @test LC._istty(IOContext(IOContext(slave, :color => true),
                                      :displaysize => (40, 100)))
            # And the geometry ioctl reads back what was set on it.
            ws = Ref((UInt16(24), UInt16(100), UInt16(0), UInt16(0)))
            ccall(:ioctl, Cint, (Cint, Culong, Ptr{Cvoid}), sfd[], 0x5414, ws)  # TIOCSWINSZ
            @test LC._winsize(sfd[]) == (24, 100)
        finally
            close(slave)
            ccall(:close, Cint, (Cint,), mfd[])
        end
    else
        @warn "openpty unavailable — skipping the pty half of tty detection"
    end
    @test LC._winsize(RawFD(-1)) === nothing        # not a terminal at all
    @test LC._winsize(-1) === nothing               # ...by either spelling
end

@testset "fd helpers accept what Base.fd actually returns" begin
    # `Base.fd(::IOStream)` returns a `RawFD`, which is NOT an `Integer`. An
    # `fd::Integer` signature therefore compiles, type-checks, and MethodErrors
    # at runtime — and every such call site in this package is inside the
    # sidecar, which no test can reach without a window and a model. It shipped
    # that way twice (`_winsize`, then `_logto`). Pinning the type is what makes
    # the third time impossible.
    open("/dev/null", "w") do f
        @test fd(f) isa RawFD                       # the assumption that was wrong
        @test LC._fdint(fd(f)) isa Cint
        @test LC._fdint(3) === Cint(3)
        @test LC._fdint(RawFD(3)) === Cint(3)       # both spellings, same answer

        # The exact call the sidecar makes on its window. Before `_fdint` this
        # raised MethodError the moment a model finished loading.
        LC._logto(fd(f)) do
            @test LC._LOG_FD[] == LC._fdint(fd(f))
        end
        @test LC._LOG_FD[] == -1                    # restored

        @test LC._winsize(fd(f)) === nothing        # /dev/null is not a terminal
        @test !LC._istty(f)
    end
end

@testset "sidecar render path against a real pty" begin
    # `_window_io` is the whole reason the tty predicate changed, and it is the
    # one part of the sidecar a model-less test can drive end to end: open a pty,
    # wrap the slave exactly as the sidecar does, and check that a reply renders
    # rather than streaming raw into a window well able to display it.
    mfd, sfd = Ref{Cint}(0), Ref{Cint}(0)
    rc = ccall(:openpty, Cint,
               (Ptr{Cint}, Ptr{Cint}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
               mfd, sfd, C_NULL, C_NULL, C_NULL)
    if rc != 0
        @warn "openpty unavailable — skipping the sidecar render path"
    else
        ws = Ref((UInt16(40), UInt16(90), UInt16(0), UInt16(0)))
        ccall(:ioctl, Cint, (Cint, Culong, Ptr{Cvoid}), sfd[], 0x5414, ws)   # TIOCSWINSZ
        slave = fdio(sfd[], true)
        try
            # Exactly what _window_io builds: colour stated, size read live.
            io = IOContext(IOContext(slave, :color => true),
                           :displaysize => LC._winsize(sfd[]))
            @test LC._istty(io)                       # ...so `chat` will render
            @test displaysize(io) == (40, 90)         # ...and wrap to the window
            @test get(io, :color, false)              # ...in colour

            # Drive the renderer and read the bytes back off the master.
            sink = LC._MDSink(io; render = LC._istty(io))
            @test sink.render
            LC._emit!(sink, "## Heading\n\n```julia\nf(x) = 1\n```\n\n")
            LC._finish!(sink)
            flush(slave)

            buf = Vector{UInt8}(undef, 65536)
            n = ccall(:read, Cssize_t, (Cint, Ptr{UInt8}, Csize_t), mfd[], buf, 65536)
            out = n > 0 ? String(buf[1:n]) : ""
            @test occursin("\e[", out)                # redraw + colour actually emitted
            @test occursin("\e[1m", out)              # ...bold, which a non-tty would skip

            # The raw markdown IS in the byte stream — it streamed live before
            # being erased. What matters is the screen it leaves behind, which
            # is what the simulator above reconstructs.
            final = screen(out; w = 90, h = 40)
            @test occursin("Heading", final)
            @test occursin("f(x) = 1", final)
            @test !occursin("## Heading", final)      # source replaced, not appended
            @test !occursin("```", final)
        finally
            close(slave)
            ccall(:close, Cint, (Cint,), mfd[])
        end
    end
end

@testset "REPL context is sent as a delta, not re-sent whole" begin
    # Re-sending the scrollback every turn spends the context window on the same
    # lines over and over: three turns of a 400-line capture overruns 32k on its
    # own. Both captures are windows onto one growing stream, so the new content
    # is whatever follows their overlap.
    prev = ["a", "b", "c", "d", "e", "f"]

    @test LC._context_delta(String[], prev) == prev          # first call: all new
    @test LC._context_delta(prev, prev) == String[]          # nothing happened
    @test LC._context_delta(prev, [prev; "g"; "h"]) == ["g", "h"]

    # The case a fixed-size tail anchor gets wrong: the scrollback hit its limit
    # and dropped lines off the TOP, so the overlap is no longer prev's full
    # length. Only genuinely-new lines may come back.
    @test LC._context_delta(prev, ["c", "d", "e", "f", "g"]) == ["g"]
    @test LC._context_delta(prev, ["f", "g", "h"]) == ["g", "h"]
    # ...including when the overlap is down to its last line.
    @test LC._context_delta(prev, ["f"]) == String[]

    # No overlap at all (cleared, or a different window): treat it all as new
    # rather than silently dropping the context being asked about.
    @test LC._context_delta(prev, ["x", "y"]) == ["x", "y"]
    @test LC._context_delta(prev, String[]) == String[]

    # The `ask(...)` call is on screen by the time we capture — echoing the
    # question back as context is tokens spent on nothing.
    @test LC._trim_context(["work", "julia> ask(\"why?\")"]) == ["work"]
    @test LC._trim_context(["work", "ask(\"why?\")", "", "   "]) == ["work"]
    @test LC._trim_context(["work", "LlamaChat.ask(\"why?\")"]) == ["work"]
    @test LC._trim_context(["a task(x) call"]) == ["a task(x) call"]   # not an echo
    @test LC._trim_context(String[]) == String[]

    # Composition keeps the prompt last, so the question is the most recent
    # thing the model reads.
    body = LC._compose("why?", ["ERROR: MethodError", "Stacktrace: [1] emit"])
    @test occursin("ERROR: MethodError", body)
    @test occursin("Stacktrace: [1] emit", body)
    @test endswith(strip(body), "why?")
    @test LC._compose("why?", String[]) == "why?"        # no context, no wrapper
end

@testset "the sidecar window dies with its Julia process" begin
    # The child used to `exec sleep infinity`, so a Julia that went away without
    # unwinding — SIGKILL, a crash, closing the REPL — left a kitty window up
    # forever holding a terminal nothing would ever write to again. Found by
    # doing exactly that. `wait(proc)` is how we notice the window closing; this
    # is the other direction, and it is the one with no in-process handler left
    # to run, so it has to be the child's job.
    dir     = mktempdir()
    ttyfile = joinpath(dir, "tty")
    try
        parent = run(`sleep 2`; wait = false)
        child  = run(pipeline(`sh -c $(LC._WINDOW_SH) sh $ttyfile $(getpid(parent))`;
                              stdout = devnull, stderr = devnull); wait = false)

        # The handshake file appears immediately even with no tty to report —
        # _spawn_window blocks on this file, so it must never simply not arrive.
        for _ in 1:100
            isfile(ttyfile) && break
            sleep(0.05)
        end
        @test isfile(ttyfile)
        @test process_running(child)          # stays up while the parent does

        wait(parent)
        t0 = time()
        while process_running(child) && time() - t0 < 20
            sleep(0.2)
        end
        @test !process_running(child)         # ...and follows it down promptly
        @test time() - t0 < 20
    finally
        rm(dir; recursive = true, force = true)
    end
end

@testset "exported surface is exactly list_models, load and ask" begin
    # The point of this package's front door: two names. Everything else is
    # reachable through the module qualifier and nothing else lands in the
    # caller's namespace.
    @test Set(names(LlamaChat)) == Set([:LlamaChat, :list_models, :load, :ask])

    # ...and the things that stopped being exported still exist, because scripts
    # (chat.jl among them) go through them.
    for n in (:chat, :ChatSession, :Response, :reset!, :close!,
              :resolve_model, :default_model, :ollama_root)
        @test isdefined(LlamaChat, n)
    end
    # These are gone outright, not merely unexported.
    for n in (:md, :chatrepl, :start!, :run_demo)
        @test !isdefined(LlamaChat, n)
    end
    # No markdown toggle survives on the chat entry point.
    @test !(:markdown in Base.kwarg_decl(only(methods(LlamaChat.chat))))
end

@testset "model resolution" begin
    @test !isempty(LC.list_models())         # ollama store is populated on this box
    @test all(sz -> sz > 0, last.(LC.list_models()))
    @test LC.resolve_model(@__FILE__) == @__FILE__      # a path passes through
    @test_throws ErrorException LC.resolve_model("definitely-not-a-model:v0")
end

@testset "list_models prints a table, still behaves as a vector" begin
    ms = LC.list_models()
    # It has to stay indexable/iterable/broadcastable — the pretty printing is a
    # display concern and must not cost the data.
    @test ms isa AbstractVector{Tuple{String,Int}}
    @test length(ms) == length(collect(ms))
    @test first(ms) == ms[1]
    @test issorted(last.(ms); rev = true)               # largest first
    @test filter(m -> true, ms) == collect(ms)          # filter falls back cleanly

    out = sprint(show, MIME"text/plain"(), ms)
    @test occursin(first(first(ms)), out)               # every name is listed
    @test count('\n', out) == length(ms)                # one row each
    @test occursin(r"\d+(\.\d)? (B|KiB|MiB|GiB|TiB)", out)   # sizes are human
    @test !occursin("(\"", out)                         # not a tuple dump

    # The row bare `load()` would open is marked.
    dflt = LC.default_model()
    occursin(':', dflt) || (dflt *= ":latest")
    dflt in first.(ms) && @test occursin("→", out)

    # An empty store says so rather than printing nothing at all.
    withenv("OLLAMA_MODELS" => "/nonexistent-store") do
        empty_out = sprint(show, MIME"text/plain"(), LC.list_models())
        @test occursin("no models", empty_out)
    end

    @test LC._human(512) == "512 B"
    @test LC._human(1024) == "1.0 KiB"
    @test LC._human(1536) == "1.5 KiB"
    @test LC._human(17 * 1024^3) == "17 GiB"            # ≥10 drops the decimal
end

@testset "env overrides are read when used, not baked at precompile" begin
    # These were `const X = get(ENV, ...)` at module scope. Julia evaluates that
    # during PRECOMPILATION and freezes the result into the .ji, so the
    # documented overrides did nothing once the package had been compiled once —
    # silently: you got the default model and a perfectly good answer from the
    # wrong 17 GB file. Setting the variable inside this process and observing
    # the accessor is exactly the case that used to fail.
    withenv("LLAMACPP_CHAT_MODEL" => "sentinel-model:v0") do
        @test LC.default_model() == "sentinel-model:v0"
    end
    withenv("LLAMACPP_CHAT_MODEL" => nothing) do
        @test LC.default_model() == "qwen3-coder"        # documented default
    end

    withenv("OLLAMA_MODELS" => "/nonexistent-store") do
        @test LC.ollama_root() == "/nonexistent-store"
        # ...and it is actually consulted, not just readable: no manifests there.
        @test isempty(LC.list_models())
    end
    withenv("OLLAMA_MODELS" => nothing) do
        @test LC.ollama_root() == "/var/lib/ollama"
    end
    # Restored afterwards — the live testsets below resolve real models.
    @test !isempty(LC.list_models())
end

@testset "the wrapper withholds Base-shadowing names from export" begin
    # llamacpp defines `error` (codecvt_base::result.error), `all`, `stat` and
    # `symlink`. Exporting them made `using .Llamacpp` shadow the caller's
    # Base bindings, so every failure path in THIS file raised
    # `UndefVarError: error not defined` instead of its message. RepliBuild
    # withholds them now; they stay defined and reachable through `L.`.
    exported = Set(String.(names(LC.L)))
    for n in ("error", "all", "stat", "symlink")
        @test !(n in exported)                       # not exported...
        @test isdefined(LC.L, Symbol(n))             # ...but still defined
    end
    # Reachable, and still the library's own thing rather than Base's.
    @test LC.L.error isa LC.L.result
    @test LC.L.error !== Base.error
    # The wrapper says so in the file, which is also how you spot a stale lib/.
    @test occursin("Withheld from `export`",
                   read(joinpath(@__DIR__, "..", "lib", "Llamacpp.jl"), String))
end

@testset "by-value param structs (the ABI this package stresses)" begin
    mp = LC.L.llama_model_default_params()
    @test sizeof(mp) == 72
    cp = LC.L.llama_context_default_params()
    @test sizeof(cp) == 160
    # n_ctx sits at offset 0 of the 160-byte struct — it read garbage when the
    # emitted MLIR type was the wrong width.
    @test Int(cp.n_ctx) == 512
    cp2 = LC.L.setproperties(cp; n_ctx = UInt32(4096), n_threads = Int32(3))
    @test Int(cp2.n_ctx) == 4096
    @test Int(cp2.n_threads) == 3
    @test Int(cp.n_ctx) == 512               # immutable: original untouched
end

# ── Live model ───────────────────────────────────────────────────────────────

if MODEL === nothing
    @warn "no generative model in the ollama store — skipping live inference tests"
else
    @info "live tests using $MODEL"
    s = LC.ChatSession(MODEL; n_ctx = 1024, temp = 0.0)   # greedy → deterministic

    @testset "session opens" begin
        @test s.isopen
        @test s.model != C_NULL
        @test s.ctx   != C_NULL
        @test s.vocab != C_NULL
        @test s.n_ctx == 1024
        @test Int(LC.L.llama_n_ctx(s.ctx)) == 1024     # what the library actually built
        @test s.template === nothing || s.template isa String
    end

    @testset "tokenize/detokenize round-trip" begin
        text = "The quick brown fox — 日本語 — 🔧"
        toks = LC._tokenize(s, text, false)
        @test !isempty(toks)
        @test eltype(toks) == Int32
        buf = Vector{UInt8}(undef, 256)
        out = UInt8[]
        for t in toks
            n = LC.L.llama_token_to_piece(s.vocab, t, buf, Int32(length(buf)), Int32(0), false)
            @test n >= 0
            append!(out, view(buf, 1:n))
        end
        @test String(out) == text
    end

    @testset "chat template renders a transcript" begin
        msgs = ["user" => "hi"]
        b = LC._format(s, msgs, true)
        @test !isempty(b)
        @test isvalid(String(copy(b)))
        # add_ass=true must extend, not replace, the add_ass=false rendering —
        # this prefix property is what the incremental KV path relies on.
        b0 = LC._format(s, msgs, false)
        @test length(b) > length(b0)
        @test b[1:length(b0)] == b0
    end

    @testset "turn 1 generates and advances the cache" begin
        r = LC.chat(s, "Say hello."; max_tokens = 16, stream = false)
        @test r isa LC.Response
        @test r.n_prompt > 0
        @test r.n_gen > 0
        @test s.n_past >= r.n_prompt + r.n_gen
        @test length(s.history) == 2                   # user + assistant
        @test r.stop in (:eog, :max_tokens)
        # s.decoded is exactly the transcript bytes backing the KV cache.
        @test !isempty(s.decoded)
        @test isvalid(String(copy(s.decoded)))
    end

    @testset "turn 2 reuses the cache instead of re-decoding" begin
        n_past_before = s.n_past
        decoded_before = copy(s.decoded)
        r = LC.chat(s, "And again."; max_tokens = 16, stream = false)

        @test s.n_past > n_past_before
        # The transcript only ever extends — the earlier bytes are untouched.
        @test s.decoded[1:length(decoded_before)] == decoded_before
        # The whole conversation would cost this many tokens from scratch:
        full = length(LC._tokenize(s, String(copy(s.decoded)), true))
        # ...but only the new turn was fed in. If incremental reuse ever breaks,
        # this is the assertion that catches it.
        @test r.n_prompt < full ÷ 2
        @test length(s.history) == 4
    end

    @testset "decoded transcript stays a prefix of the rendered template" begin
        formatted = LC._format(s, LC._messages(s), false)
        @test length(s.decoded) <= length(formatted)
        @test formatted[1:length(s.decoded)] == s.decoded
    end

    @testset "Response interop" begin
        r = LC.chat(s, "Reply with the word ok."; max_tokens = 8, stream = false)
        @test r.text isa String
        @test String(r) == r.text
        @test ("got: " * r) == "got: " * r.text
        @test sprint(print, r) == r.text                         # print stays raw...
        @test !isempty(sprint(show, MIME"text/plain"(), r))      # ...display renders
        r2 = LC.Response(r.text, r.n_prompt, r.n_gen, r.t_prompt, r.t_gen, r.stop, true)
        @test occursin("tok", sprint(show, MIME"text/plain"(), r2))  # streamed → shows stats
    end

    @testset "reset! clears conversation and cache" begin
        LC.reset!(s)
        @test isempty(s.history)
        @test isempty(s.decoded)
        @test s.n_past == 0
        r = LC.chat(s, "Say hi."; max_tokens = 8, stream = false)   # usable afterwards
        @test r.n_gen > 0
    end

    @testset "context budget is enforced, not overrun" begin
        small = LC.ChatSession(MODEL; n_ctx = 64, temp = 0.0)
        try
            long = repeat("the quick brown fox jumps over the lazy dog. ", 40)
            @test_throws ErrorException LC.chat(small, long; max_tokens = 4, stream = false)
            @test isempty(small.history)      # the failed turn was rolled back
        finally
            LC.close!(small)
        end
    end

    @testset "llama.cpp logging never reaches the caller's terminal" begin
        # llama.cpp logs with C printf straight to fd 1/2, which Julia's
        # redirect_stdout cannot reach and which no Julia-level capture will
        # show. Freeing a context prints `~llama_context: CPU compute buffer
        # size …`; in the sidecar that landed on the REPL prompt seconds after
        # the user had moved on, and a prompt Julia will not redraw reads
        # exactly like a hang. So this has to be asserted at fd level or not at
        # all — hence the dup2 rather than a redirect_stdout.
        # Both fds have to be pointed at the file BEFORE f runs — redirecting
        # them one at a time around separate calls captures neither reliably.
        capture(f) = mktemp() do path, io
            s1 = ccall(:dup, Cint, (Cint,), 1)
            s2 = ccall(:dup, Cint, (Cint,), 2)
            ccall(:dup2, Cint, (Cint, Cint), fd(io), 1)
            ccall(:dup2, Cint, (Cint, Cint), fd(io), 2)
            try
                f()
            finally
                ccall(:dup2, Cint, (Cint, Cint), s1, 1); ccall(:close, Cint, (Cint,), s1)
                ccall(:dup2, Cint, (Cint, Cint), s2, 2); ccall(:close, Cint, (Cint,), s2)
            end
            flush(io)
            return read(path, String)
        end

        quiet = capture() do
            q = LC.ChatSession(MODEL; n_ctx = 128, log = devnull)
            LC.close!(q)                       # the line that caused the report
        end
        @test isempty(quiet)

        # ...but `verbose` still means verbose: the same run must produce the
        # loader detail, or this "fix" is just a mute button.
        loud = capture() do
            v = LC.ChatSession(MODEL; n_ctx = 128, verbose = true)
            LC.close!(v)
        end
        @test !isempty(loud)
        @test occursin("llama", lowercase(loud))

        # And the routing knob itself: -1 discards, a real fd receives.
        @test LC._LOG_FD[] == -1                       # restored after _logto
        LC._logto(2) do
            @test LC._LOG_FD[] == 2
        end
        @test LC._LOG_FD[] == -1                       # ...even though we left via a @test
        @test LC._LOG_CB[] != C_NULL                   # callback installed in __init__
    end

    @testset "teardown is idempotent" begin
        LC.close!(s)
        @test !s.isopen
        LC.close!(s)
        @test !s.isopen
        @test_throws ErrorException LC.chat(s, "anything")
    end
end

# ── Reasoning-model terse mode ───────────────────────────────────────────────
#
# `think = false` SHORTENS reasoning and hides it; it does not disable it.
# Three mechanisms were measured on qwen3:4b (temp=0, two prompts, total gen):
#   baseline 662 tok / 11.8 s · `<think></think>` prefill 606 / 11.0 ·
#   system directive 201 / 3.9 · directive+prefill 252 / 4.9
# Qwen3's `/no_think` and `enable_thinking` both live in the Jinja template that
# `llama_chat_apply_template` does not run — `enable_thinking` does not appear
# in this model's template at all, whose generation prompt is unconditionally
# `<|im_start|>assistant\n<think>\n`.
@testset "terse mode (think = false)" begin
    @testset "_strip_think folds only a leading block" begin
        @test LC._strip_think("<think>\nreasoning\n</think>\n\nHello!") == "Hello!"
        @test LC._strip_think("<think></think>answer") == "answer"
        # Leading whitespace before the block is still a leading block.
        @test LC._strip_think("\n  <think>r</think>\n\nA") == "A"
        # A plain reply is returned untouched.
        @test LC._strip_think("Plain answer.") == "Plain answer."
        # A closing tag with no opener is content — e.g. explaining the tag.
        @test LC._strip_think("Use </think> in XML.") == "Use </think> in XML."
        # A block that does not OPEN the reply is content too.
        @test LC._strip_think("Hi <think>x</think> there") == "Hi <think>x</think> there"
        @test LC._strip_think("") == ""
    end

    if MODEL !== nothing
        @testset "the directive lands in the system prompt" begin
            # Session-level, not per-turn: it changes the system prompt, and
            # changing that mid-conversation re-renders every earlier turn.
            s = LC.ChatSession(MODEL; n_ctx = 64, think = false)
            @test occursin(LC._TERSE_DIRECTIVE, s.system)
            @test !s.think
            LC.close!(s)

            # A user system prompt is kept, with the directive appended.
            s = LC.ChatSession(MODEL; n_ctx = 64, think = false, system = "You are Ada.")
            @test occursin("You are Ada.", s.system)
            @test occursin(LC._TERSE_DIRECTIVE, s.system)
            LC.close!(s)

            # Default leaves the system prompt exactly as given.
            s = LC.ChatSession(MODEL; n_ctx = 64, system = "You are Ada.")
            @test s.system == "You are Ada."
            @test s.think
            LC.close!(s)
        end
    end
end

# ── GPU placement planning (plan.jl) ─────────────────────────────────────────
#
# This code exists to stop a process abort: llama.cpp does not fit-to-available,
# and an over-commit on the Vulkan backend calls abort() from inside ggml with
# no Julia exception to catch. So it must decide correctly from a header rather
# than by trying and recovering — and that means it has to be tested against
# headers, not against a live card.
#
# Fixtures are synthesized GGUF v3 files written to a tempdir: a header alone is
# a few hundred bytes, so the suite can cover shapes no local blob has (MoE,
# derived head_dim, a clip projector) without downloading anything.
@testset "GPU placement planning" begin
    # Minimal GGUF v3 writer: magic, version, tensor_count, kv_count, then pairs.
    # Only the scalar/string types the planner reads.
    function write_gguf(path; arch::String, kv::Dict{String,Any}, pad::Int = 0)
        open(path, "w") do io
            write(io, b"GGUF"); write(io, UInt32(3))
            write(io, UInt64(0))                       # tensor_count
            all = merge(Dict{String,Any}("general.architecture" => arch), kv)
            write(io, UInt64(length(all)))
            for (k, v) in all
                write(io, UInt64(sizeof(k))); write(io, codeunits(k))
                if v isa String
                    write(io, UInt32(8)); write(io, UInt64(sizeof(v))); write(io, codeunits(v))
                else
                    write(io, UInt32(4)); write(io, UInt32(v))   # uint32
                end
            end
            pad > 0 && write(io, zeros(UInt8, pad))    # stand in for tensor data
        end
        return path
    end

    mktempdir() do dir
        # qwen3:4b's real shape, at a size that lets budgets be exercised.
        q4 = write_gguf(joinpath(dir, "q4.gguf"); arch = "qwen3", pad = 2 * 1024^3,
              kv = Dict{String,Any}("qwen3.block_count" => 36,
                                    "qwen3.attention.head_count" => 32,
                                    "qwen3.attention.head_count_kv" => 8,
                                    "qwen3.attention.key_length" => 128,
                                    "qwen3.attention.value_length" => 128,
                                    "qwen3.embedding_length" => 2560))

        @testset "header + shape" begin
            s = LC.model_shape(q4)
            @test s.arch == "qwen3"
            @test (s.n_layer, s.n_head_kv, s.k_len, s.v_len) == (36, 8, 128, 128)
            @test !s.is_moe
            # THE reason key_length is read explicitly: the derivation
            # embedding_length ÷ head_count gives 2560÷32 = 80, not 128.
            @test s.n_embd ÷ s.n_head == 80
            @test s.k_len == 128
        end

        @testset "KV is the expensive half" begin
            s = LC.model_shape(q4)
            # 36 layers × 8 kv-heads × (128+128) × 2 bytes = 147456 B/token.
            @test LC.kv_bytes(s, 1) == 147_456
            @test LC.kv_bytes(s, 32768) == 147_456 * 32768
            @test LC.kv_bytes(s, 32768) > 4 * 1024^3      # > 4 GiB, i.e. > the weights
            @test LC.kv_bytes(s, 1024; bits = 8) == LC.kv_bytes(s, 1024) ÷ 2
        end

        @testset "budget decides, and n_ctx is the dial" begin
            withenv("LLAMACHAT_VRAM_GB" => "5") do
                @test LC.plan_offload(q4; n_ctx = 2048).ngl  == 99
                @test LC.plan_offload(q4; n_ctx = 2048).why  === :fits
                big = LC.plan_offload(q4; n_ctx = 32768)
                @test big.ngl == 0
                @test big.why === :too_big
                # A refusal must say what WOULD work, not just "no".
                @test 0 < big.max_ctx_on_gpu < 32768
                @test LC.plan_offload(q4; n_ctx = big.max_ctx_on_gpu).ngl == 99
            end
            # Raising the budget moves the boundary.
            withenv("LLAMACHAT_VRAM_GB" => "16") do
                @test LC.plan_offload(q4; n_ctx = 32768).ngl == 99
            end
        end

        @testset "explicit over-budget is refused, not warned" begin
            withenv("LLAMACHAT_VRAM_GB" => "5") do
                p = LC.plan_offload(q4; n_ctx = 32768, requested = 99)
                @test p.why === :requested
                @test p.ngl == 99                      # honoured in the plan…
                err = try LC.check_request(p, q4, 32768); nothing catch e; e end
                @test err isa ErrorException           # …and vetoed by the check
                msg = sprint(showerror, err)
                @test occursin("does not fit the VRAM budget", msg)
                @test occursin("LLAMACHAT_VRAM_GB", msg)   # names the override
                @test occursin(string(p.max_ctx_on_gpu), msg)
                # CPU is always allowed, whatever the budget.
                @test LC.check_request(LC.plan_offload(q4; n_ctx = 32768, requested = 0),
                                       q4, 32768) === nothing
            end
        end

        @testset "a CPU fallback is never silent" begin
            withenv("LLAMACHAT_VRAM_GB" => "5") do
                @test LC.plan_note(LC.plan_offload(q4; n_ctx = 2048), 2048) === nothing
                note = LC.plan_note(LC.plan_offload(q4; n_ctx = 32768), 32768)
                @test note !== nothing && occursin("CPU", note)
            end
        end

        @testset "MoE is detected and advised on" begin
            moe = write_gguf(joinpath(dir, "moe.gguf"); arch = "qwen3moe", pad = 4 * 1024^3,
                  kv = Dict{String,Any}("qwen3moe.block_count" => 48,
                                        "qwen3moe.attention.head_count" => 32,
                                        "qwen3moe.attention.head_count_kv" => 4,
                                        "qwen3moe.attention.key_length" => 128,
                                        "qwen3moe.attention.value_length" => 128,
                                        "qwen3moe.embedding_length" => 2048,
                                        "qwen3moe.expert_count" => 128))
            s = LC.model_shape(moe)
            @test s.is_moe && s.n_expert == 128
            withenv("LLAMACHAT_VRAM_GB" => "5") do
                @test occursin("MoE", LC.plan_note(LC.plan_offload(moe; n_ctx = 8192), 8192))
            end
        end

        @testset "non-LLM blobs fail legibly" begin
            # ollama's blob store mixes vision projectors in with text models;
            # "no clip.block_count" reads like a corrupt file.
            clip = write_gguf(joinpath(dir, "clip.gguf"); arch = "clip",
                              kv = Dict{String,Any}("clip.has_text_encoder" => 0))
            err = try LC.model_shape(clip); nothing catch e; e end
            @test err isa ErrorException
            @test occursin("not a language model", sprint(showerror, err))

            notgguf = joinpath(dir, "nope.bin"); write(notgguf, b"NOTAGGUF")
            @test_throws ErrorException LC.model_shape(notgguf)
        end

        @testset "\$LLAMACHAT_NGL" begin
            withenv("LLAMACHAT_NGL" => nothing) do; @test LC._env_ngl() === :auto; end
            withenv("LLAMACHAT_NGL" => "auto") do; @test LC._env_ngl() === :auto; end
            withenv("LLAMACHAT_NGL" => "0")    do; @test LC._env_ngl() == 0;      end
            withenv("LLAMACHAT_NGL" => "99")   do; @test LC._env_ngl() == 99;     end
            # Unparseable falls back to auto rather than erroring at load time.
            withenv("LLAMACHAT_NGL" => "yes please") do
                @test (@test_logs (:warn,) match_mode=:any LC._env_ngl()) === :auto
            end
        end
    end
end

end

println("✓ LlamaChat app tests passed")
