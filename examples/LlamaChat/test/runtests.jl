using Test
using LlamaChat
using RepliBuild
using Markdown

const LC = LlamaChat

# Pick the smallest *generative* model in the local ollama store — embedding
# models have no generation head, so they are excluded. Override with
# $LLAMACHAT_TEST_MODEL.
# Only LlamaChat's own store is considered (models_dir(), see import_ollama):
# the tests must not depend on ollama's /var/lib/ollama, which may be gone.
function test_model()
    haskey(ENV, "LLAMACHAT_TEST_MODEL") && return ENV["LLAMACHAT_TEST_MODEL"]
    # Typed decision models (Laya, Nimble) are in the store too and are not
    # chat models: told apart by their files, not their names.
    chat(m) = !occursin("embed", lowercase(first(m))) &&
              (try LC.model_kind(LC.resolve_model(first(m))) === :chat catch; false end)
    cands = filter(chat, LC.list_models(; roots = [LC.models_dir()]))
    isempty(cands) && return nothing
    return first(cands[end])          # list_models sorts by size, descending
end

const MODEL = test_model()

# An IO that runs `f` on its first write. `chat` writes a token's text only after
# that token is decoded, so `f` runs at an exact, known point in a generation.
mutable struct OnFirstWrite <: IO
    f::Function
    fired::Bool
    buf::IOBuffer
end
OnFirstWrite(f) = OnFirstWrite(f, false, IOBuffer())
_fire!(io::OnFirstWrite) = io.fired || (io.fired = true; io.f())
Base.unsafe_write(io::OnFirstWrite, p::Ptr{UInt8}, n::UInt) = (_fire!(io); unsafe_write(io.buf, p, n))
Base.write(io::OnFirstWrite, x::UInt8) = (_fire!(io); write(io.buf, x))
Base.flush(::OnFirstWrite) = nothing

# The GUI module is included on first use, never by `using LlamaChat`. Load it
# here, at top level, so the testsets below run in a world that can see it.
const GUI_DIR = joinpath(pkgdir(LlamaChat), "lib", "gui")
const GM = all(f -> isfile(joinpath(GUI_DIR, f)), LC._GUI_FILES) ? LC._gui_module() : nothing

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
    # eachline, not read(path, String): procfs reports size 0, and a sized read
    # came back without this mapping once the process got big (on the sysimage).
    maps = join(eachline("/proc/self/maps"), "\n")
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

@testset "dollar signs are money, not LaTeX or interpolation" begin
    esc = LC._escape_dollars
    plain(x) = Markdown.plain(Markdown.parse(esc(x)))
    @test plain(raw"Cost $10k–$100k/kg") == "Cost \$10k–\$100k/kg\n"     # was LaTeX in the middle
    @test plain(raw"| a | $10 |") == "| a | \$10 |\n"                   # was an interpolated 10
    @test plain(raw"run it with $HOME set") == "run it with \$HOME set\n"
    @test esc(raw"area $x^2$ here") == raw"area $x^2$ here"            # real maths stays maths
    @test esc("```bash\necho \$5\n```") == "```bash\necho \$5\n```"     # code is left alone
    @test esc(raw"set `$5` and $5") == raw"set `$5` and \$5"
    @test esc(raw"already \$5") == raw"already \$5"
    @test esc("no dollars") == "no dollars"
    # A pair whose inside looks like maths stays maths, even starting with a digit.
    @test esc(raw"$9.81 \times 2 \approx 19.6$ m/s") == raw"$9.81 \times 2 \approx 19.6$ m/s"
    @test esc(raw"mass $\rightarrow$ curve") == raw"mass $\rightarrow$ curve"
    # ***bold italic*** is literal to the parser; **_…_** is not.
    @test esc("a ***both*** b") == "a **_both_** b"
    @test Markdown.parse(esc("a ***both*** b")).content[1].content[2] isa Markdown.Bold
    @test esc("```\n***x***\n```") == "```\n***x***\n```"
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
    for n in (:chat, :ChatSession, :Response, :reset!, :close!, :cancel!, :gui, :pull,
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
    withenv("OLLAMA_MODELS" => "/nonexistent-store", "LLAMACHAT_MODELS" => "/nonexistent-own") do
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

    withenv("OLLAMA_MODELS" => "/nonexistent-store", "LLAMACHAT_MODELS" => "/nonexistent-own") do
        @test LC.ollama_root() == "/nonexistent-store"
        # ...and both are actually consulted, not just readable: no manifests there.
        @test isempty(LC.list_models())
    end
    withenv("OLLAMA_MODELS" => nothing) do
        @test LC.ollama_root() == "/var/lib/ollama"
    end
    # Restored afterwards — the live testsets below resolve real models.
    @test !isempty(LC.list_models())
end

@testset "pull, offline: names, stores, request events, the status line" begin
    @test LC._split_name("qwen3") == ("library", "qwen3", "latest")
    @test LC._split_name("qwen3:0.6b") == ("library", "qwen3", "0.6b")
    @test LC._split_name("someone/model:q4") == ("someone", "model", "q4")
    # LlamaChat's own store first, then ollama's (read only). pull writes to the
    # own store only — never to $OLLAMA_MODELS, which on this machine points at
    # /var/lib/ollama, owned by the ollama user.
    own = joinpath(homedir(), ".local", "share", "llamachat", "models")
    withenv("OLLAMA_MODELS" => nothing, "LLAMACHAT_MODELS" => nothing, "XDG_DATA_HOME" => nothing) do
        @test LC.models_dir() == own
        @test LC.model_roots() == [own, "/var/lib/ollama", joinpath(homedir(), ".ollama", "models")]
        @test LC.pull_root() == own
    end
    withenv("OLLAMA_MODELS" => "/var/lib/ollama", "LLAMACHAT_MODELS" => "/mine") do
        @test LC.model_roots() == ["/mine", "/var/lib/ollama"]
        @test LC.pull_root() == "/mine"                     # not the service's store
    end
    f = tempname(); write(f, "hello")
    try
        # Downloads notifies a request's `interrupt` event itself when the
        # request finishes. Shared between requests, the first to finish aborts
        # the rest — the bug `_request` exists to avoid. If this stops being
        # true, Downloads changed and _request's docstring is out of date.
        ev = Base.Event()
        LC.Downloads.request("file://$f"; output = IOBuffer(), interrupt = ev)
        @test ev.set
        p = LC.PullProgress("x")
        for _ in 1:3                       # every request gets its own event
            io = IOBuffer()
            LC._request("file://$f", p; output = io)
            @test String(take!(io)) == "hello"
        end
        @test !p.aborted[] && isempty(p.live)
        LC.cancel!(p)
        @test LC.cancelled(p) && p.aborted[]
    finally
        rm(f; force = true)
    end
    # import_ollama, against a fake ollama store: blobs and manifest copied,
    # names reported, a rerun copies nothing, the source untouched.
    mktempdir() do d
        src, dst = joinpath(d, "ollama"), joinpath(d, "mine")
        blob(store, dg) = joinpath(store, "blobs", replace(dg, ':' => '-'))
        wdig, cdig = "sha256:" * "a"^64, "sha256:" * "c"^64
        mkpath(joinpath(src, "blobs"))
        write(blob(src, wdig), rand(UInt8, 4096)); write(blob(src, cdig), "{}")
        mp = joinpath(src, "manifests", "registry.ollama.ai", "library", "tiny", "1b")
        mkpath(dirname(mp))
        write(mp, LC.JSON.json(Dict("config" => Dict("digest" => cdig, "size" => 2),
            "layers" => [Dict("mediaType" => "application/vnd.ollama.image.model", "digest" => wdig, "size" => 4096)])))
        @test LC.import_ollama(; from = [src], to = dst, io = devnull) == ["tiny:1b"]
        @test read(blob(dst, wdig)) == read(blob(src, wdig))
        @test isfile(blob(dst, cdig)) && isfile(joinpath(dst, "manifests", "registry.ollama.ai", "library", "tiny", "1b"))
        @test !any(f -> occursin("partial", f), readdir(joinpath(dst, "blobs")))
        out = sprint(io -> LC.import_ollama(; from = [src], to = dst, io = io))
        @test occursin("already here", out)               # a rerun copies nothing
        withenv("LLAMACHAT_MODELS" => dst, "OLLAMA_MODELS" => joinpath(d, "none")) do
            @test LC.resolve_model("tiny:1b") == blob(dst, wdig)   # resolves from the own store
        end
        @test isfile(blob(src, wdig))                     # the source is left alone
    end

    q = LC.PullProgress("m")
    LC._phase!(q, :downloading); q.total[] = 100 * 2^20; q.done[] = 25 * 2^20
    s = LC.pull_status(q)
    @test occursin("25 MiB / 100 MiB", s) && occursin("25%", s)
    LC._phase!(q, :verifying); @test occursin("verifying", LC.pull_status(q))
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
    @warn "no generative model in LlamaChat's store ($(LC.models_dir())) — skipping live " *
          "inference tests; LlamaChat.pull(\"qwen3:4b\") or LlamaChat.import_ollama() adds one"
else
    @info "live tests using $MODEL"
    s = LC.ChatSession(MODEL; n_ctx = 1024, temp = 0.0)   # greedy → deterministic

    @testset "session opens" begin
        # The weights come from LlamaChat's own store, not ollama's.
        @test startswith(LC.resolve_model(MODEL), LC.models_dir())
        @test s.isopen
        @test s.model != C_NULL
        @test s.ctx   != C_NULL
        @test s.vocab != C_NULL
        @test s.n_ctx == 1024
        @test Int(LC.L.llama_n_ctx(s.ctx)) == 1024     # what the library actually built
        @test s.n_layer > 0 && 0 <= s.gpu_layers <= s.n_layer
        @test s.template === nothing || s.template isa String
    end

    @testset "placement reads as the planner placed it" begin
        n, g = s.n_layer, s.gpu_layers
        try
            s.gpu_layers = n;      @test LC.placement(s) == "all $n layers on GPU"
            s.gpu_layers = n - 5;  @test LC.placement(s) == "$(n - 5)/$n layers on GPU"
            s.gpu_layers = 0;      @test LC.placement(s) == "CPU only"
        finally
            s.gpu_layers = g
        end
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

    @testset "cancel! stops at a token boundary and keeps the cache in step" begin
        # The GUI's Stop button: an Atomic another thread sets, checked once per
        # token, leaving by the same exit as Ctrl-C. Fired from the sink so the
        # stop point is exact rather than a race.
        io = OnFirstWrite(() -> LC.cancel!(s))
        r = LC.chat(s, "Count from 1 to 50, one number per line."; max_tokens = 200, io = io)
        @test r.stop === :interrupt
        @test 1 <= r.n_gen < 10                  # the token after the first piece never ran
        @test !s.cancel[]                        # consumed: it cannot cut off the next turn
        raw = last(last(s.history))
        streamed = String(take!(io.buf))         # `chat` ends a stream at column 0
        @test streamed == raw || streamed == raw * "\n"
        @test endswith(String(copy(s.decoded)), raw)
        formatted = LC._format(s, LC._messages(s), false)
        @test formatted[1:length(s.decoded)] == s.decoded
        # The next turn runs to completion on the same cache.
        r2 = LC.chat(s, "Say hi."; max_tokens = 8, stream = false)
        @test r2.stop in (:eog, :max_tokens)
        @test r2.n_gen > 0
        # A request with nothing running applies to the next generation, which
        # then stops before its first token — and still leaves the session usable.
        LC.cancel!(s)
        r3 = LC.chat(s, "Say hi."; max_tokens = 8, stream = false)
        @test r3.stop === :interrupt && r3.n_gen == 0
        @test !s.cancel[]
        formatted = LC._format(s, LC._messages(s), false)
        @test formatted[1:length(s.decoded)] == s.decoded
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
        # Gemma 4's thought channel is a reasoning block too.
        @test LC._strip_think("<|channel>thought\nhm\n<channel|>Answer.") == "Answer."
        @test LC._strip_think("Say <channel|> literally.") == "Say <channel|> literally."
    end
end

# llama_chat_apply_template returns -1 for Gemma 4's template, and the ChatML
# fallback made gemma4:26b answer in garbage. LlamaChat writes the format itself.
@testset "Gemma 4 chat format (llama.cpp's matcher does not know it)" begin
    tmpl = "{{- bos_token -}}{{- '<|turn>' + role + '\\n' }}…{{- '<turn|>\\n' -}}"
    @test LC._is_gemma4(tmpl)
    @test !LC._is_gemma4(nothing) && !LC._is_gemma4("{% for m in messages %}<|im_start|>")
    # The C matcher really does refuse it, which is what made this necessary.
    L = LC.L
    m = [L.llama_chat_message(pointer("user"), pointer("hi"))]
    buf = zeros(UInt8, 256)
    @test GC.@preserve m buf L.llama_chat_apply_template(tmpl, m, 1, true, buf, Int32(256)) == -1

    f(think, msgs, add) = String(LC._format_gemma4(think, msgs, add))
    @test f(false, ["user" => " hi "], true) ==
          "<|turn>user\nhi<turn|>\n<|turn>model\n<|channel>thought\n<channel|>"
    @test f(true, ["user" => "hi"], true) ==
          "<|turn>system\n<|think|>\n<turn|>\n<|turn>user\nhi<turn|>\n<|turn>model\n"
    @test f(false, ["system" => "Be brief.", "user" => "hi"], true) ==
          "<|turn>system\nBe brief.<turn|>\n<|turn>user\nhi<turn|>\n<|turn>model\n<|channel>thought\n<channel|>"
    # The KV-cache invariant: a finished turn renders as an extension of what
    # was decoded — the transcript up to the generation prompt, then the reply.
    for think in (false, true)
        msgs = ["system" => "S", "user" => "q1"]
        reply = think ? "<|channel>thought\nr\n<channel|>A1" : "A1"
        decoded = f(think, msgs, true) * reply
        next = f(think, [msgs; "assistant" => reply; "user" => "q2"], true)
        @test startswith(next, decoded)
        @test next[ncodeunits(decoded)+1:end] == "<turn|>\n<|turn>user\nq2<turn|>\n<|turn>model\n" *
                                                 (think ? "" : "<|channel>thought\n<channel|>")
    end
end

@testset "terse mode (think = false), continued" begin

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
    # Only the types the planner reads: uint32, string, and a uint32 array (a
    # hybrid model's per-layer `head_count_kv`).
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
                elseif v isa AbstractVector
                    write(io, UInt32(9)); write(io, UInt32(4)); write(io, UInt64(length(v)))
                    for x in v; write(io, UInt32(x)); end
                else
                    write(io, UInt32(4)); write(io, UInt32(v))   # uint32
                end
            end
            # Stand in for the tensor data. `plan_offload` only ever asks
            # `filesize`, so the bytes need not exist — truncate sets the size
            # without writing (and sparsely, on any filesystem that supports it).
            #
            # This used to be `write(io, zeros(UInt8, pad))`, which allocated up
            # to 4 GiB at once and put 6 GiB through a tempdir on EVERY run of
            # this suite. Fine on a 62 GB box with NVMe; not fine on CI, on a
            # tmpfs sized to half of RAM, or on a Windows temp directory.
            pad > 0 && truncate(io, position(io) + pad)
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

        # A hybrid (qwen35/qwen35moe) keeps KV only on its full-attention layers;
        # the rest carry a fixed recurrent state. Counting every layer made
        # qwen3.6:35b's cache 640 KiB/token where llama.cpp allocates 20.
        @testset "a hybrid's KV is on its full-attention layers only" begin
            # qwen3.6:35b's shape: an array, 0 on each linear-attention layer.
            q36 = write_gguf(joinpath(dir, "q36.gguf"); arch = "qwen35moe", pad = 1024,
                  kv = Dict{String,Any}("qwen35moe.block_count" => 40,
                                        "qwen35moe.attention.head_count" => 16,
                                        "qwen35moe.attention.head_count_kv" => [il % 4 == 3 ? 2 : 0 for il in 0:39],
                                        "qwen35moe.attention.key_length" => 256,
                                        "qwen35moe.attention.value_length" => 256,
                                        "qwen35moe.full_attention_interval" => 4,
                                        "qwen35moe.expert_count" => 256,
                                        "qwen35moe.ssm.conv_kernel" => 4, "qwen35moe.ssm.inner_size" => 4096,
                                        "qwen35moe.ssm.state_size" => 128, "qwen35moe.ssm.group_count" => 16))
            s = LC.model_shape(q36)
            @test (s.n_kv_layers, s.n_head_kv) == (10, 2)
            @test LC.kv_bytes(s, 1) == 10 * 2 * 512 * 2              # 20 KiB, not 640
            # 30 recurrent layers × (3 × (4096 + 2·16·128) + 128·4096) f32.
            @test s.rs_bytes == 30 * (3 * 8192 + 524288) * 4
            @test LC.plan_offload(q36; n_ctx = 1024).vram_needed ==
                  s.file_bytes + LC.kv_bytes(s, 1024) + s.rs_bytes + LC._COMPUTE_RESERVE
            # qwen3.8:27b's: a scalar and an interval. Layer il is full attention
            # when (il + 1) % 4 == 0, llama.cpp's rule: 16 of 65.
            q38 = write_gguf(joinpath(dir, "q38.gguf"); arch = "qwen35", pad = 1024,
                  kv = Dict{String,Any}("qwen35.block_count" => 65,
                                        "qwen35.attention.head_count" => 24,
                                        "qwen35.attention.head_count_kv" => 4,
                                        "qwen35.attention.key_length" => 256,
                                        "qwen35.attention.value_length" => 256,
                                        "qwen35.full_attention_interval" => 4))
            s38 = LC.model_shape(q38)
            @test s38.n_kv_layers == 16
            @test LC.kv_bytes(s38, 1) == 16 * 4 * 512 * 2           # 64 KiB, not 260
            @test findall(>(0), s38.kv_heads) == 4:4:64
            # A plain transformer is unchanged: every layer, no recurrent state.
            @test LC.model_shape(q4).n_kv_layers == 36
            @test LC.model_shape(q4).rs_bytes == 0
        end

        @testset "the budget: override, else live VRAM, else the B60's" begin
            withenv("LLAMACHAT_VRAM_GB" => "3") do
                @test LC._vram_budget() == 3 * LC._GiB
            end
            withenv("LLAMACHAT_VRAM_GB" => nothing) do
                live = LC._live_vram_free()
                @test LC._vram_budget() == (live === nothing ? LC._B60_BUDGET_GIB * LC._GiB :
                                                              max(live - LC._VRAM_MARGIN, 0.0))
            end
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

        # `load("qwen3:4b")` with no flags: the default window shrinks until the
        # whole model is on the card, rather than the plan going partial at 32k.
        @testset "an unchosen n_ctx is fitted to the GPU" begin
            withenv("LLAMACHAT_VRAM_GB" => "6.5") do
                @test LC.plan_offload(q4; n_ctx = 32768).why !== :fits   # the case at hand
                c = LC.auto_ctx(q4)
                @test LC._CTX_FLOOR <= c < LC._CTX_CEILING
                @test c % 1024 == 0
                @test LC.plan_offload(q4; n_ctx = c).why === :fits           # whole model on GPU
                @test LC.plan_offload(q4; n_ctx = c + 1024).why !== :fits    # and the largest such
            end
            # Already fits at the ceiling: nothing to trade.
            withenv("LLAMACHAT_VRAM_GB" => "16") do
                @test LC.auto_ctx(q4) == LC._CTX_CEILING
            end
            # Only a sliver of window would fit: keep the full one, the plan decides.
            withenv("LLAMACHAT_VRAM_GB" => "3.5") do
                @test LC.plan_offload(q4; n_ctx = LC._CTX_FLOOR).why !== :fits
                @test LC.auto_ctx(q4) == LC._CTX_CEILING
            end
        end

        # q4's shape plus a vocabulary: the compute buffer is mostly the logits
        # node, n_batch × n_vocab × f32, so the reserve has to see n_vocab.
        qv = write_gguf(joinpath(dir, "qv.gguf"); arch = "qwen3", pad = 2 * 1024^3,
              kv = Dict{String,Any}("qwen3.block_count" => 36,
                                    "qwen3.attention.head_count" => 32,
                                    "qwen3.attention.head_count_kv" => 8,
                                    "qwen3.attention.key_length" => 128,
                                    "qwen3.attention.value_length" => 128,
                                    "qwen3.embedding_length" => 2560,
                                    "qwen3.vocab_size" => 151936))

        @testset "sliding-window layers are a fixed cost (Gemma 4)" begin
            # One sliding layer (8 heads, 256+256, window 1024) and one full one
            # (2 heads, 512+512). llama.cpp gives the sliding layer
            # pad256(window + ubatch) cells whatever n_ctx is.
            s = (kv_heads = [8, 2], swa = BitVector([true, false]), n_swa = 1024,
                 k_len = 512, v_len = 512, k_len_swa = 256, v_len_swa = 256)
            swa = 8 * 512 * 1536 * 2                  # 1024 + 512, already a multiple of 256
            @test LC.kv_bytes(s, 32768; n_batch = 512) == swa + 2 * 1024 * 32768 * 2
            @test LC.kv_bytes(s, 65536; n_batch = 512) - LC.kv_bytes(s, 32768; n_batch = 512) ==
                  2 * 1024 * 32768 * 2                # only the full layer grows
            @test LC.kv_bytes(s, 512; n_batch = 512) == (8 * 512 + 2 * 1024) * 512 * 2   # window > n_ctx
            # A bigger ubatch widens the sliding cache.
            @test LC.kv_bytes(s, 32768; n_batch = 2048) - LC.kv_bytes(s, 32768; n_batch = 512) ==
                  8 * 512 * (3072 - 1536) * 2
            # q8_0 stores 32 values in 34 bytes.
            @test LC.kv_bytes(s, 32768; n_batch = 512, kv_type = :q8_0) ==
                  round(Int, (LC.kv_bytes(s, 32768; n_batch = 512) ÷ 2) * 34 / 32)
            @test LC.kv_bytes(s, 32768; n_batch = 512, kv_type = :f16) == LC.kv_bytes(s, 32768; n_batch = 512)
            g4 = try LC.resolve_model("gemma4:26b") catch; nothing end
            if g4 !== nothing
                sh = LC.model_shape(g4)
                @test count(sh.swa) == 25 && sh.n_swa == 1024 && sh.k_len_swa == 256
                # 20 KiB/token past the window, not the 430 KiB of counting
                # every layer at full context; and so a 32k window fits.
                @test LC.kv_bytes(sh, 65537) - LC.kv_bytes(sh, 65536) == 20480
                withenv("LLAMACHAT_VRAM_GB" => "20.5") do
                    @test LC.auto_ctx(g4) == LC._CTX_CEILING
                end
            end
        end

        @testset "flash attention off: the scores' buffer, and when to pay it" begin
            s = (n_head = 32,)
            MiB = 1024^2
            @test LC.attn_scores_bytes(s, 512, 32768, :on) == 0 && LC.attn_scores_bytes(s, 512, 32768, :auto) == 0
            # Two copies from 1 GiB of scores. llama.cpp's own figures for
            # qwen3:4b: 4194.01 MiB at 512/32768, 2114.01 at 512/16384.
            @test LC.attn_scores_bytes(s, 512, 32768, :off) == 4096MiB
            @test LC.attn_scores_bytes(s, 512, 16384, :off) == 2048MiB
            # One copy (and the mask) up to 768 MiB: 562.01 MiB at 512/8192.
            @test LC.attn_scores_bytes(s, 512, 8192, :off) == 512MiB + 12 * 512 * 8192
            @test 562.01MiB - 0.5 * 1024MiB < LC.attn_scores_bytes(s, 512, 8192, :off) <= 562.01MiB
            # qwen3.8:27b (24 heads): 832.01 MiB at 256/32768, 864.01 at 512/16384.
            s24 = (n_head = 24,)
            # The estimate covers both and overshoots neither by 5%.
            @test 832.01MiB - 64.01MiB <= LC.attn_scores_bytes(s24, 256, 32768, :off) <= 1.05 * 832.01MiB
            @test LC.attn_scores_bytes(s24, 512, 16384, :off) == LC.attn_scores_bytes(s24, 256, 32768, :off)
            @test 864.01MiB - 0.02MiB <= LC.attn_scores_bytes(s24, 512, 16384, :off) <= 864.01MiB
            @test LC.attn_scores_bytes(s24, 512, 32768, :off) == 2 * 1536MiB     # past one copy
            # Unmeasured between 768 MiB and 1 GiB: counted as two.
            @test LC.attn_scores_bytes(s, 512, 12800, :off) == 2 * 800MiB
            @test LC._batch_floor(:off) == 256 && LC._batch_floor(:on) == 512
            for (m, want) in (("gemma4:26b", :off), ("qwen3-coder", :on))
                p = try LC.resolve_model(m) catch; nothing end
                p === nothing && continue
                withenv("LLAMACHAT_VRAM_GB" => "20.5") do
                    @test LC.auto_flash_attn(p) === want
                    @test LC.auto_flash_attn(p; kv_type = :q8_0) === :on     # quantised V needs it
                    on  = LC.plan_offload(p; n_ctx = 16384, n_batch = 512, flash_attn = :on)
                    off = LC.plan_offload(p; n_ctx = 16384, n_batch = 512, flash_attn = :off)
                    @test off.compute > on.compute                             # the scores cost VRAM…
                    @test off.compute - on.compute == LC.attn_scores_bytes(off.shape, 512, 16384, :off)
                    # The largest window the plan offers is one it then accepts.
                    for nb in (256, 512, 1024)
                        c = LC.plan_offload(p; n_ctx = 8192, n_batch = nb, flash_attn = :off).max_ctx_on_gpu
                        c > 0 || continue
                        @test LC.plan_offload(p; n_ctx = c, n_batch = nb, flash_attn = :off).why === :fits
                        @test LC.plan_offload(p; n_ctx = c + 1024, n_batch = nb, flash_attn = :off).why !== :fits
                    end
                end
            end
        end

        @testset "compute reserve: n_batch × n_vocab" begin
            # The token array's LENGTH survives the header skipping its contents.
            tv = joinpath(dir, "tv.gguf")
            open(tv, "w") do io
                wstr(x) = (write(io, UInt64(sizeof(x))); write(io, codeunits(x)))
                write(io, b"GGUF"); write(io, UInt32(3)); write(io, UInt64(0)); write(io, UInt64(3))
                wstr("general.architecture");  write(io, UInt32(8)); wstr("qwen3")
                wstr("qwen3.block_count");     write(io, UInt32(4)); write(io, UInt32(2))
                wstr("tokenizer.ggml.tokens"); write(io, UInt32(9)); write(io, UInt32(8))
                write(io, UInt64(5000)); for i in 1:5000; wstr("t$i"); end
            end
            @test LC.model_shape(tv).n_vocab == 5000
            @test LC.model_shape(q4).n_vocab == 0            # unknown: the floor alone

            sv = LC.model_shape(qv)
            @test sv.n_vocab == 151936
            # Vulkan0 compute buffers measured on the B60 (plan.jl's table):
            # qwen3-coder shares this vocab — 300.75 MiB at 512, 1643.05 at 2048.
            MiB = 1024^2
            @test LC.compute_reserve(sv, 512) == LC._COMPUTE_RESERVE  # floor binds at 512
            @test LC.compute_reserve(sv, 512)  >= 300.75  * MiB
            @test LC.compute_reserve(sv, 2048) >= 1643.05 * MiB
            # gemma4:26b was over the old flat 0.5 GiB even at 512.
            @test LC.compute_reserve((n_vocab = 262144,), 512)  >= 535.66  * MiB
            @test LC.compute_reserve((n_vocab = 262144,), 2048) >= 2512.08 * MiB
            @test LC.compute_reserve((n_vocab = 248320,), 512)  >= 505.00  * MiB
            @test LC.compute_reserve((n_vocab = 248320,), 2048) >= 2604.19 * MiB
            p = LC.plan_offload(qv; n_ctx = 1024, n_batch = 2048)
            @test p.compute == LC.compute_reserve(sv, 2048)
            @test p.vram_needed == sv.file_bytes + LC.kv_bytes(sv, 1024) + p.compute
        end

        @testset "auto_batch: context first, then speed" begin
            # Room to spare: the biggest batch costs no window.
            withenv("LLAMACHAT_VRAM_GB" => "16") do
                @test LC.auto_batch(qv) == 2048
            end
            # Tight: 2048's buffer would come out of the window, so it steps
            # down until the window is what 512 gets (here, all the way).
            withenv("LLAMACHAT_VRAM_GB" => "6.5") do
                nb = LC.auto_batch(qv)
                @test nb < 2048
                @test LC.auto_ctx(qv; n_batch = nb) >= LC.auto_ctx(qv; n_batch = 512)
                # An explicit small window leaves room the batch can use.
                @test LC.auto_batch(qv; n_ctx = 8192) == 2048
            end
            # Not on the GPU at 512: no batch helps it onto the card.
            withenv("LLAMACHAT_VRAM_GB" => "1") do
                @test LC.auto_batch(qv) == 512
            end
            # Flash attention off: the scores scale with n_batch × n_ctx, so
            # the steps go down to 256 and the widest window wins.
            withenv("LLAMACHAT_VRAM_GB" => "8.5") do
                nb = LC.auto_batch(qv; flash_attn = :off)
                @test nb == 256
                @test LC.auto_ctx(qv; n_batch = 256, flash_attn = :off) >
                      LC.auto_ctx(qv; n_batch = 512, flash_attn = :off)
                @test LC.auto_batch(qv; flash_attn = :on) >= 512         # never below 512 with it on
                @test LC.auto_batch(qv; n_ctx = 4096, flash_attn = :off) == 2048
            end
            q38 = try LC.resolve_model("qwen3.8:27b") catch; nothing end
            if q38 !== nothing
                withenv("LLAMACHAT_VRAM_GB" => "20.4") do
                    @test LC.auto_flash_attn(q38) === :off
                    @test LC.auto_batch(q38; flash_attn = :off) == 256
                    @test LC.auto_ctx(q38; n_batch = 256, flash_attn = :off) == LC._CTX_CEILING
                end
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

# ── GUI: imgui + GLFW + llama.cpp in one process ─────────────────────────────
#
# Drives the real app (`LlamaChat.GUI.App`) in a hidden window: keystrokes and
# clicks go in through ImGuiIO, one edge per frame, as GLFW's callbacks would
# deliver them; the reply generates on a worker while this thread renders.
@testset "GUI" begin
if GM === nothing
    @warn "lib/gui/ is not vendored — skipping GUI tests (run vendor_gui.sh)"
else
    G = GM.G

    @testset "code blocks are coloured like an editor" begin
        # The colour of the run that is `tok`, else of the first run holding it
        # (runs merge neighbours of one colour).
        function colour(runs, tok)
            for l in runs, (s, c) in l
                strip(s) == tok && return c
            end
            return first(c for l in runs for (s, c) in l if occursin(tok, s))
        end
        j = GM.highlight_code("julia", "f(x) = 1 # hi\nprintln(2)")
        @test colour(j, "f") == GM.HL_FUNC                 # a definition (Julia's own parser)
        @test colour(j, "println") == GM.HL_FUNC           # a call
        @test colour(j, "1") == GM.HL_NUMBER
        @test colour(j, "# hi") == GM.HL_COMMENT
        c = GM.highlight_code("cpp", "int main() { return 42; } // c")
        @test colour(c, "int") == GM.HL_TYPE && colour(c, "main") == GM.HL_FUNC
        @test colour(c, "return") == GM.HL_KEYWORD && colour(c, "42") == GM.HL_NUMBER
        @test colour(c, "// c") == GM.HL_COMMENT
        p = GM.highlight_code("python", "def f():\n    return \"s\"")
        @test colour(p, "def") == GM.HL_KEYWORD && colour(p, "f") == GM.HL_FUNC
        @test colour(p, "\"s\"") == GM.HL_STRING
        b = GM.highlight_code("bash", "echo \$HOME # x")
        @test colour(b, "\$HOME") == GM.HL_SYMBOL && colour(b, "# x") == GM.HL_COMMENT
        t = GM.highlight_code("toml", "[a]\nk = 1")
        @test colour(t, "[a]") == GM.HL_KEYWORD && colour(t, "k") == GM.HL_MACRO && colour(t, "1") == GM.HL_NUMBER
        @test all(c == 0 for l in GM.highlight_code("text", "x = 1 # no") for (_, c) in l)
        # Highlighting never changes the text (tabs become four spaces).
        src = "a\tb = \"q\"\n\nend"
        @test [join(first.(l)) for l in GM.highlight_code("julia", src)] == ["a    b = \"q\"", "", "end"]
    end

    @testset "loaded on demand, not exported" begin
        @test LC._GUI[] === GM
        @test GM.default_terminal().exec[2:end] == ["--banner=no"]   # no shell, so no alias: the flag is on the command
        @test !(:gui in names(LlamaChat))
    end

    @testset "split_think" begin
        @test GM.split_think("plain answer") == (nothing, "plain answer", false)
        @test GM.split_think("<think>\nhm\n</think>\n\nAnswer.") == ("hm", "Answer.", false)
        @test GM.split_think("\n<think>still going") == ("still going", "", true)
        @test GM.split_think("<|channel>thought\nhm\n<channel|>Answer.") == ("hm", "Answer.", false)
        @test GM.split_think("<|chan") == (nothing, "", false)   # Gemma 4's tag arriving
        @test GM.split_think("<thi") == (nothing, "", false)       # tag arriving in pieces
        @test GM.split_think("<think></think>Hi") == ("", "Hi", false)
        # Only a block that OPENS the reply is reasoning.
        @test GM.split_think("A <think>x</think>") == (nothing, "A <think>x</think>", false)
        @test GM.split_think("<think>é ✓</think>ü") == ("é ✓", "ü", false)
    end

    @testset "markdown → render tree" begin
        p = only(GM.parse_md("plain **bold** *it* `code` [link](http://x)\n"))
        @test p isa GM.Para
        runs = [(join(s.pieces), s.style) for s in p.spans]
        @test ("plain ", 0x00) in runs
        @test ("bold", GM.S_BOLD) in runs
        @test ("it", GM.S_ITALIC) in runs
        @test ("code", GM.S_CODE) in runs
        @test ("link", GM.S_LINK) in runs
        h = only(GM.parse_md("## Title\n"))
        @test h isa GM.Heading && h.level == 2
        l = only(GM.parse_md("- a\n- b\n  - c\n"))
        @test l isa GM.ListBlk && l.start < 0 && length(l.items) == 2
        @test l.items[2][end] isa GM.ListBlk                    # nested
        @test only(GM.parse_md("3. x\n4. y\n")).start == 3
        c = only(GM.parse_md("```julia\nf(x) = 1\n```\n"))
        @test c isa GM.CodeBlock && (c.lang, c.code) == ("julia", "f(x) = 1")
        t = only(GM.parse_md("| **A** | B |\n|---|---|\n| 1 | 2 |\n"))
        @test t isa GM.TableBlk && t.header == ["A", "B"] && length(t.rows) == 1
        @test only(GM.parse_md("---\n")) isa GM.Rule
        @test only(GM.parse_md("> q\n")) isa GM.Quote
        # No usable emoji font (16-bit ImWchar, or only Noto's bitmap strike):
        # emoji are dropped, not shown as U+FFFD.
        @test GM.display_text("📊 Summary 1️⃣ ✓") == " Summary 1 ✓"
        # A streaming reply re-parses only the segment that changed.
        a = GM.segments("para one\n\npara two", GM.Seg[])
        b = GM.segments("para one\n\npara two grows", a)
        @test length(b) == 2 && b[1] === a[1] && b[2] !== a[2]
    end

    # A GGUF header that says "typed decision model", and a stand-in for the
    # `laya daemon`: the ready line, then one canned answer per request line.
    function fake_typed_gguf(path, family; max_opts = 16)
        open(path, "w") do io
            wstr(x) = (write(io, UInt64(sizeof(x))); write(io, codeunits(x)))
            kv = Any["general.architecture" => "ggmlc", "laya.family" => family,
                     "laya.model_name" => "laya-$family", "laya.max_len" => 1024, "laya.max_opts" => max_opts]
            write(io, b"GGUF"); write(io, UInt32(3)); write(io, UInt64(0)); write(io, UInt64(length(kv)))
            for (k, v) in kv
                wstr(k)
                v isa String ? (write(io, UInt32(8)); wstr(v)) : (write(io, UInt32(4)); write(io, UInt32(v)))
            end
            write(io, family)                       # so two families hash apart
        end
        return path
    end
    function fake_laya_bin(dir)
        bin = joinpath(dir, "fake-laya")
        write(bin, raw"""
        #!/bin/sh
        case "$2" in *broken*) echo "cannot load $2" >&2; exit 3 ;; esac
        echo '{"status":"ready","model":"laya"}'
        while IFS= read -r line; do
          case "$line" in
            *boom*) echo '{"error":"JSON parse error: bad literal at 0"}' ;;
            *) echo '{"model":"laya","family":"english","answers":{"churn_risk":{"type":"noul","confidence":0.7,"noul":0.7},"intent":{"type":"choice","confidence":0.5,"choice":"b","probabilities":{"a":0.2,"b":0.8}},"frustration":{"type":"score","confidence":0.3,"score":1.4,"legend":{"0":"lo","1":"mid","2":"hi"},"probabilities":{"0":0.1,"1":0.4,"2":0.5}}},"usage":{"input_tokens":42,"output_tokens":0,"latency_ms":12.5}}' ;;
          esac
        done
        """)
        chmod(bin, 0o755)
        return bin
    end
    TYPED_QS = """{"intent": {"type": "choice", "instructions": "Which?", "criteria": {"b": "second", "a": null}},
                         "frustration": {"type": "score", "instructions": "How much?", "criteria": ["lo", "mid", "hi"]},
                         "churn_risk": {"type": "noul", "instructions": "Leaving?"}}"""

    @testset "typed decisions: the format, the engine, the store" begin
        dir = mktempdir()
        # A chat model's header, for telling the two kinds apart.
        q4 = joinpath(mktempdir(), "chat.gguf")
        open(q4, "w") do io
            wstr(x) = (write(io, UInt64(sizeof(x))); write(io, codeunits(x)))
            write(io, b"GGUF"); write(io, UInt32(3)); write(io, UInt64(0)); write(io, UInt64(2))
            wstr("general.architecture"); write(io, UInt32(8)); wstr("qwen3")
            wstr("qwen3.block_count"); write(io, UInt32(4)); write(io, UInt32(2))
        end
        # Objects keep file order: option order is input to the model.
        o = LC._parse_json("""{"z": 1, "a": {"y": null, "b": [1, 2]}, "m": "s"}""")
        @test collect(keys(o)) == ["z", "a", "m"] && collect(keys(o["a"])) == ["y", "b"]
        @test LC.JSON.json(o) == """{"z":1,"a":{"y":null,"b":[1,2]},"m":"s"}"""
        o["z"] = 2
        @test collect(keys(o)) == ["z", "a", "m"] && o["z"] == 2 && !haskey(o, "q")

        qs = LC.parse_questions(LC._parse_json(TYPED_QS))
        @test [q.id for q in qs] == ["intent", "frustration", "churn_risk"]
        @test qs[1] isa LC.Choice && qs[1].criteria == ["b" => "second", "a" => nothing]   # as written, not sorted
        @test qs[2] isa LC.Score && qs[2].criteria == ["lo", "mid", "hi"]
        @test qs[3] isa LC.Noul && qs[3].no === nothing && qs[3].yes === nothing
        @test LC.n_options.(qs) == [2, 3, 2] && LC.question_type.(qs) == [:choice, :score, :noul]
        # Out and back in, unchanged.
        @test LC.JSON.json(LC.questions_json(LC.parse_questions(LC.questions_json(qs)))) == LC.JSON.json(LC.questions_json(qs))
        n = LC.parse_questions(LC._parse_json("""{"q": {"type": "noul", "instructions": "x", "criteria": {"true": "yes!", "false": "no!"}}}"""))[1]
        @test n.no == "no!" && n.yes == "yes!"

        # Every way a request can be wrong is refused with the field named. The
        # engine itself answers a question typed "nope" with a confident "".
        bad(json) = try LC.parse_questions(LC._parse_json(json)); nothing catch e; e end
        for (json, param, word) in (
                ("[1]", "questions", "object"),
                ("{}", "questions", "no questions"),
                ("""{"q": 3}""", "questions.q", "object"),
                ("""{"q": {"instructions": "x"}}""", "questions.q.type", "missing"),
                ("""{"q": {"type": "nope", "instructions": "x"}}""", "questions.q.type", "\"nope\""),
                ("""{"q": {"type": "noul"}}""", "questions.q.instructions", "sentence"),
                ("""{"q": {"type": "noul", "instructions": " "}}""", "questions.q.instructions", "sentence"),
                ("""{"q": {"type": "noul", "instructions": "x", "options": []}}""", "questions.q.options", "not a field"),
                ("""{"q": {"type": "choice", "instructions": "x"}}""", "questions.q.criteria", "label"),
                ("""{"q": {"type": "choice", "instructions": "x", "criteria": {"a": null}}}""", "questions.q.criteria", "2 to 16"),
                ("""{"q": {"type": "choice", "instructions": "x", "criteria": {"a": null, "b": 4}}}""", "questions.q.criteria.b", "string or null"),
                ("""{"q": {"type": "choice", "instructions": "x", "criteria": ["a", "b"]}}""", "questions.q.criteria", "object"),
                ("""{"q": {"type": "score", "instructions": "x", "criteria": {"a": null, "b": null}}}""", "questions.q.criteria", "list"),
                ("""{"q": {"type": "score", "instructions": "x", "criteria": ["only"]}}""", "questions.q.criteria", "2 to 16"),
                ("""{"q": {"type": "noul", "instructions": "x", "criteria": {"maybe": "y"}}}""", "questions.q.criteria.maybe", "only"))
            e = bad(json)
            @test e isa LC.TypedFormatError && e.param == param && occursin(word, e.msg)
        end
        many = "{" * join(("\"l$i\": null" for i in 1:17), ", ") * "}"
        @test bad("""{"q": {"type": "choice", "instructions": "x", "criteria": $many}}""").param == "questions.q.criteria"
        @test sprint(showerror, bad("""{"q": 3}""")) == "questions.q: must be an object with `type` and `instructions`"

        # The four shapes a JSON file can have.
        r = LC.parse_typed("""{"id": "1", "state": {"m": "hi"}, "questions": $TYPED_QS}""")
        @test r.kind === :request && length(r.states) == 1 && r.states[1]["m"] == "hi" && length(r.questions) == 3
        b = LC.parse_typed("""{"states": [{"l": 1}, "plain", {"l": 3}], "questions": $TYPED_QS}""")
        @test b.kind === :batch && length(b.states) == 3 && b.states[2] == "plain"
        q = LC.parse_typed(TYPED_QS)
        @test q.kind === :questions && isempty(q.states) && length(q.questions) == 3
        @test LC.parse_typed("""{"questions": $TYPED_QS}""").kind === :questions
        s = LC.parse_typed("""{"ticket": 4, "message": "late"}""")
        @test s.kind === :state && isempty(s.questions) && collect(keys(s.states[1])) == ["ticket", "message"]
        pt = LC.parse_typed("  Where is my refund?\n")
        @test pt.kind === :state && pt.states == ["Where is my refund?"]          # not JSON: a plain-text state
        @test LC.parse_typed("""{"type": "x", "note": {"type": "memo"}}""").kind === :state   # looks like one, is not
        @test_throws LC.TypedFormatError LC.parse_typed("""{"state": 1, "questions": {"q": {"type": "pick", "instructions": "x"}}}""")
        @test_throws LC.TypedFormatError LC.parse_typed("""{"states": [], "questions": $TYPED_QS}""")
        f = joinpath(dir, "req.json"); write(f, """{"state": "s", "questions": $TYPED_QS}""")
        @test LC.load_typed(f).kind === :request

        # The model file: told apart by its header, and into the store by name.
        g1 = fake_typed_gguf(joinpath(dir, "laya_english.gguf"), "english")
        g2 = fake_typed_gguf(joinpath(dir, "laya_typed.gguf"), "typed-decisions"; max_opts = 2)
        @test LC.model_kind(g1) === :typed && LC.model_kind(q4) === :chat
        @test LC.model_kind(joinpath(dir, "req.json")) === :chat           # not a GGUF at all
        @test LC.typed_info(g2) == (family = "typed-decisions", name = "laya-typed-decisions",
                                    max_len = 1024, head_max_len = 192, max_opts = 2, max_batch = 8)
        write(joinpath(dir, "other.gguf"), read(q4))                        # a chat model in the same folder
        root = joinpath(dir, "store")
        withenv("LLAMACHAT_MODELS" => root, "OLLAMA_MODELS" => joinpath(dir, "no-ollama")) do
            @test LC.bring_laya(; from = dir) == ["laya:english", "laya:typed-decisions"]
            @test sort(first.(LC.list_models())) == ["laya:english", "laya:typed-decisions"]
            blob = LC.resolve_model("laya:typed-decisions")
            @test read(blob) == read(g2) && startswith(blob, joinpath(root, "blobs", "sha256-"))
            @test stat(blob).nlink == 2                                 # a hard link, not a second copy
            @test LC.bring_laya(; from = dir) == ["laya:english", "laya:typed-decisions"]   # again: the same store
            @test length(readdir(joinpath(root, "blobs"))) == 2
            @test LC.add_model(q4, "me/tiny:q4") == "me/tiny:q4" && isfile(LC.resolve_model("me/tiny:q4"))
            @test_throws ErrorException LC.add_model(f, "x")           # not a GGUF
            @test_throws ErrorException LC.bring_laya(; from = joinpath(dir, "nope"))
            err = try LC.ChatSession("laya:english"; log = devnull); nothing catch e; e end
            @test err isa ErrorException && occursin("typed decision model", err.msg)

            withenv("LLAMACHAT_LAYA" => fake_laya_bin(dir)) do
                log = IOBuffer()
                ts = LC.open_model("laya:english"; log = log, n_ctx = 2048, think = false)   # chat keywords: ignored
                @test ts isa LC.TypedSession && ts.info.family == "english" && ts.isopen
                @test occursin("typed decisions", String(take!(log)))
                @test LC.placement(ts) == "typed decisions on $(LC.laya_device())"
                d = LC.decide(ts, LC.ODict("message" => "hi"), TYPED_QS)
                @test d isa LC.Decisions && d.input_tokens == 42 && d.latency_ms == 12.5 && length(d) == 3
                # Answers come back in the QUESTIONS' order, options in theirs.
                @test [a.id for a in d] == ["intent", "frustration", "churn_risk"]
                @test d["intent"].value == "b" && d["intent"].probabilities == ["b" => 0.8, "a" => 0.2]
                @test d["frustration"].value == 1.4 && d["frustration"].probabilities == ["lo" => 0.1, "mid" => 0.4, "hi" => 0.5]
                @test d["churn_risk"].value == 0.7 && last.(d["churn_risk"].probabilities) ≈ [0.3, 0.7]
                @test LC.headline.(d.answers) == ["b  0.8", "1.4 of 2", "yes  0.7"]
                @test_throws KeyError d["nope"]
                shown = sprint(show, MIME"text/plain"(), d)
                @test occursin("[intent] choice  b  0.8", shown) && occursin("###################.....  0.8     b", shown)
                # A batch file: one Decisions a state.
                write(f, """{"states": ["one", "two"], "questions": $TYPED_QS}""")
                @test length(LC.decide(ts, LC.load_typed(f))) == 2 && ts.n_decided == 3
                @test_throws LC.TypedFormatError LC.decide(ts, LC.parse_typed(TYPED_QS))        # questions, no state
                @test_throws LC.TypedFormatError LC.decide(ts, "s", """{"q": {"type": "nope", "instructions": "x"}}""")
                e = try LC.decide(ts, "boom", TYPED_QS); nothing catch e; e end
                @test e isa ErrorException && occursin("JSON parse error", e.msg)   # the engine's own error, passed on
                @test LC.decide(ts, "after", TYPED_QS) isa LC.Decisions             # and the session survives it
                LC.close!(ts)
                @test !ts.isopen && !process_running(ts.proc) && !isfile(ts.errlog)
                @test LC.close!(ts) === ts
                @test_throws ErrorException LC.decide(ts, "s", TYPED_QS)
                # The model's own option limit, from its header.
                t2 = LC.TypedSession("laya:typed-decisions"; log = devnull)
                e = try LC.decide(t2, "s", TYPED_QS); nothing catch e; e end
                @test e isa LC.TypedFormatError && e.param == "questions.frustration.criteria"
                LC.close!(t2)
                @test length(LC.decide("laya:english", f)) == 2                     # load, run a file, free
                # A daemon that dies says why.
                gb = fake_typed_gguf(joinpath(dir, "broken.gguf"), "english")
                e = try LC.TypedSession(gb; log = devnull); nothing catch e; e end
                @test e isa ErrorException && occursin("did not start", e.msg) && occursin("cannot load", e.msg)
                @test_throws ErrorException LC.TypedSession(q4; log = devnull)      # a chat model
            end
        end
    end

    @testset "typed decisions from a language model's logits (Nimble)" begin
        # The prompt contract, written out: context, the whole schema with a
        # letter per option, then the one field asked for.
        qs = LC.parse_questions(LC._parse_json("""{
            "intent": {"type": "choice", "instructions": "What is wanted in `m`?", "criteria": {"refund": "money <back>", "other": null}},
            "level":  {"type": "score",  "instructions": "How bad?", "criteria": ["fine", "bad"]},
            "leave":  {"type": "noul",   "instructions": "Leaving?", "criteria": {"true": "says so"}}}"""))
        shared, tails = LC.nimble_prompt(LC.ODict("m" => "a \"q\" <b>", "n" => Any[1, 2.5, true, nothing]), qs)
        @test startswith(shared, "<|im_start|>system\nClassify the context using the supplied schema.")
        @test occursin("one-letter code, without reasoning or explanation.<|im_end|>\n<|im_start|>user\n{\"context\": ", shared)
        # The state is given as JSON TEXT inside a JSON string, Python-spaced, with < and > escaped.
        user = LC.JSON.parse(shared[last(findfirst("<|im_start|>user\n", shared))+1:end])     # the user turn is one JSON object
        @test user["context"] == "{\"m\": \"a \\\"q\\\" <b>\", \"n\": [1, 2.5, true, null]}" && length(user["schema"]) == 3
        @test !occursin('<', split(shared, "<|im_start|>user\n")[2]) && occursin("\\u003cb\\u003e", shared)   # no raw < or > from data
        @test occursin("""{"name": "intent", "description": "What is wanted in `m`?", "choices": [{"code": "A", "value": "refund", "description": "money \\u003cback\\u003e"}, {"code": "B", "value": "other"}]}""", shared)
        @test occursin("""{"name": "level", "description": "How bad?", "choices": [{"code": "A", "value": "0", "description": "fine"}, {"code": "B", "value": "1", "description": "bad"}]}""", shared)
        @test endswith(shared, """{"name": "leave", "description": "Leaving?", "choices": [{"code": "A", "value": false}, {"code": "B", "value": true, "description": "says so"}]}]}""")
        @test tails == ["\n\nRequested field: \"$id\"<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n" for id in ("intent", "level", "leave")]
        @test occursin("""{"context": "plain \\u003ctext\\u003e", "schema": [""", LC.nimble_prompt("plain <text>", qs)[1])
        @test LC._pyjson(LC.ODict("a" => "é\n\t", "b" => 3.0, "c" => LC.ODict())) == "{\"a\": \"é\\n\\t\", \"b\": 3.0, \"c\": {}}"

        # Probabilities → the typed answer, with the same confidence rules as Laya's.
        @test LC._softmax([0.0, 0.0]) == [0.5, 0.5] && sum(LC._softmax([1000.0, 999.0, -5.0])) ≈ 1
        a = LC._logit_answer(qs[1], [0.8, 0.2])
        @test a.type === :choice && a.value == "refund" && a.probabilities == ["refund" => 0.8, "other" => 0.2]
        @test a.confidence ≈ 1 + (0.8log(0.8) + 0.2log(0.2)) / log(2)
        s = LC._logit_answer(qs[2], [0.25, 0.75])
        @test s.type === :score && s.value ≈ 0.75 && s.probabilities == ["fine" => 0.25, "bad" => 0.75]
        n = LC._logit_answer(qs[3], [0.1, 0.9])
        @test n.type === :noul && n.value == 0.9 && n.confidence == 0.9 && LC.headline(n) == "yes  0.9"
        @test LC._logit_answer(qs[1], [1.0, 0.0]).confidence == 1

        # How runs are cut for the GPU: whatever the cut, every token once, in order.
        for nb in (64, 256, 2048), k in (1, 7, 8, 9, 13, 31, 32, 40, 127, 128, 129, 159, 257, 375, 424, 1000, 2049, 5000)
            @test sum(LC._split_run(k, nb)) == k && maximum(LC._split_run(k, nb)) <= max(nb, 8)
            @test sum(LC._prompt_runs(k, nb)) == k && maximum(LC._prompt_runs(k, nb)) <= nb
            @test LC._prompt_runs(k, nb, false) == [fill(nb, k ÷ nb); k % nb == 0 ? Int[] : [k % nb]]   # CPU: plain batches
        end
        @test LC._split_run(13, 2048) == [8, 5] && LC._split_run(130, 2048) == [128, 2]
        @test LC._split_run(159, 2048) == [128, 8, 8, 8, 7] && LC._split_run(375, 2048) == [375]
        @test LC._prompt_runs(20, 2048) == [8, 8, 4] && LC._prompt_runs(32, 2048) == [32]
        @test LC._prompt_runs(129, 2048) == [128, 1] && LC._prompt_runs(144, 2048) == [128, 8, 8]
        @test LC._prompt_runs(145, 2048) == [145] && LC._prompt_runs(2060, 2048) == [2048, 8, 4]

        # The hybrid thinking switch is read from the template, not the name.
        sw = "{%- if enable_thinking is defined and enable_thinking is false %}{{- '<think>\\n\\n</think>\\n\\n' }}{%- else %}{{- '<think>\\n' }}{%- endif %}"
        @test LC._has_think_switch(sw) && !LC._has_think_switch("{{- '<|im_start|>assistant\\n<think>\\n' }}") && !LC._has_think_switch(nothing)
        @test LC._system_for("Be kind.", false, sw) == "Be kind." && LC._system_for("", false, sw) == ""
        @test LC._system_for("", false, nothing) == LC._TERSE_DIRECTIVE

        nim = try LC.resolve_model("nimble") catch; nothing end
        if nim === nothing
            @warn "no nimble model — skipping the logits decision tests"
        else
            @test LC.model_kind(nim) === :typed && LC.decision_template(nim) !== nothing
            ls = LC.open_model("nimble"; log = devnull, think = false, temp = 0.0)
            try
                @test ls isa LC.LogitSession && ls.chat.n_ctx == LC.NIMBLE_CTX && ls.info.max_opts == 26
                @test length(ls.codes) == 26 && allunique(ls.codes)
                st = LC.ODict("message" => "This is the third time the webhook failed this week. If you cannot fix it today I am moving to a competitor.")
                q = LC._parse_json("""{
                    "intent": {"type": "choice", "instructions": "What does the customer want in `message`?",
                               "criteria": {"refund": "money returned", "technical_help": "a bug or outage fixed", "other": null}},
                    "frustration": {"type": "score", "instructions": "How frustrated does `message` sound?", "criteria": ["calm", "annoyed", "very angry"]},
                    "churn_risk": {"type": "noul", "instructions": "Does `message` say the customer may leave?"}}""")
                d = LC.decide(ls, st, q)
                @test [x.id for x in d] == ["intent", "frustration", "churn_risk"]
                @test all(x -> sum(last.(x.probabilities)) ≈ 1, d.answers)
                @test d["intent"].value == "technical_help" && d["churn_risk"].value > 0.9 && d["frustration"].value > 1
                # The shared part was decoded once: fewer tokens evaluated than three whole prompts.
                @test ls.reuse === :checkpoint && d.input_tokens < d.raw["usage"]["prompt_tokens"] ÷ 2
                # Going back to the checkpoint gives what decoding every prompt from scratch gives.
                ls.reuse = :redecode
                d2 = LC.decide(ls, st, q)
                @test d2.input_tokens == d2.raw["usage"]["prompt_tokens"]
                @test all(isapprox.(last.(d["intent"].probabilities), last.(d2["intent"].probabilities); atol = 2e-3))
                @test isapprox(d["churn_risk"].value, d2["churn_risk"].value; atol = 2e-3)
                ls.reuse = :checkpoint
                e = try LC.decide(ls, "s", """{"q": {"type": "nope", "instructions": "x"}}"""); nothing catch e; e end
                @test e isa LC.TypedFormatError
                # The same weights chat, and with the model's own switch the reply is the answer.
                c = ls.chat
                r = LC.chat(c, "What is 17*23? Reply with the number only."; stream = false, io = devnull, max_tokens = 64)
                @test occursin("391", r.text) && !occursin("<think>", r.text) && r.n_gen < 16
                r2 = LC.chat(c, "Add 9 to that. Number only."; stream = false, io = devnull, max_tokens = 64)
                @test occursin("400", r2.text) && r2.n_prompt < 40          # the cache was extended, not rebuilt
                @test startswith(last(c.history[2]), LC._NO_THINK_PREFILL)
                @test LC.decide(ls, st, q)["intent"].value == "technical_help"   # and decisions after a chat
                @test isempty(c.history) && c.n_past == 0                    # which cleared it
            finally
                LC.close!(ls)
            end
        end
    end

    @testset "places, notes and stats: the parts that need no window" begin
        dir = mktempdir()
        a, b = mkpath(joinpath(dir, "one")), mkpath(joinpath(dir, "two's"))
        pf = joinpath(dir, "places")
        write(pf, "# my folders\nFirst = $a/\n\nSecond=$b   # the other\nGone = $dir/nope\nnot a line\n")
        pl = GM.load_places(pf)
        @test [p.name for p in pl] == ["First", "Second"]         # in file order; a missing folder is left out
        @test pl[1].dir == a && pl[2].dir == b
        d = GM.load_places(joinpath(dir, "no-such-file"))         # no file: the defaults
        @test [p.name for p in d] == [p.name for p in GM.default_places() if isdir(p.dir)]
        @test first(GM.default_places()).name == "RepliBuild" && GM.default_places()[2].name == "Hub"
        @test GM.default_places()[2].dir == rstrip(normpath(joinpath(@__DIR__, "..", "..", "..")), '/')
        # A window started from $HOME opens its terminal in the first place.
        cd(homedir()) do
            @test GM.start_dir(nothing, pl) == a
            @test GM.start_dir(nothing, GM.Place[]) == homedir()
        end
        cd(b) do
            @test GM.start_dir(nothing, pl) == pwd()
        end
        @test GM.start_dir(dir, pl) == dir

        @test GM.term_kind(GM.julia_cmd()) === :julia && GM.term_kind(`zsh`) === :shell
        @test GM.term_kind(`htop`) === :other
        @test "--project=@." in GM.julia_cmd().exec
        @test GM.cd_line(:julia, a) == "cd($(repr(a)))\r"
        @test GM.cd_line(:shell, b) == " cd -- '$(dir)/two'\\''s'\r"   # a quote in the name survives

        @test GM.system_with_notes("", "  \n") == ""
        @test GM.system_with_notes("Be kind.", "") == "Be kind."
        s = GM.system_with_notes("Be kind.", "I use Arch.\n")
        @test startswith(s, "Be kind.\n\n" * GM.NOTES_HEADER) && endswith(s, "\n\nI use Arch.")
        @test GM.system_with_notes("", "I use Arch.") == GM.NOTES_HEADER * "\n\nI use Arch."
        nf = joinpath(dir, "cfg", "notes.md")
        @test GM.read_notes(nf) == ""
        GM.write_notes("héllo", nf)
        @test GM.read_notes(nf) == "héllo"

        @test GM.cpu_jiffies("cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 1 2 3\n") == (850.0, 1000.0)
        @test GM.mem_bytes("MemTotal:       1000 kB\nMemFree: 10 kB\nMemAvailable:    250 kB\n") == (750 * 1024.0, 1000 * 1024.0)

        # A card as Intel's xe driver publishes it.
        dev = mkpath(joinpath(dir, "drm", "card0", "device"))
        mkpath(joinpath(dir, "drm", "card0-DP-1"))
        mkpath(joinpath(dev, "driver"))
        hw = mkpath(joinpath(dev, "hwmon", "hwmon5"))
        idle = joinpath(mkpath(joinpath(dev, "tile0", "gt0", "gtidle")), "idle_residency_ms")
        put(f, v) = write(joinpath(hw, f), string(v, "\n"))
        put("name", "xe"); put("temp2_label", "pkg"); put("temp2_input", 61000)
        put("temp3_label", "vram"); put("temp3_input", 58000)
        put("energy1_input", 1_000_000); put("fan1_input", 1200)
        write(idle, "5000\n")
        g = GM.find_gpu(joinpath(dir, "drm"))
        @test g.name == "xe" && g.idle_ms == idle && g.busy_pct === nothing
        @test g.temp == joinpath(hw, "temp2_input") && g.temp_vram == joinpath(hw, "temp3_input")
        @test GM.find_gpu(joinpath(dir, "nothing-here")) === nothing
        st = GM.Stats(); st.gpu = g; st.t = 0.0
        GM.sample!(st, 100.0; tokens = 10)
        @test isnan(st.gpu_busy) && isnan(st.gpu_w) && st.tps == 0     # a rate needs two samples
        @test st.gpu_temp == 61 && st.vram_temp == 58 && st.fan == 1200
        write(idle, "5250\n"); put("energy1_input", 51_000_000)        # 1 s later: idle 250 ms, 50 J
        GM.sample!(st, 101.0; tokens = 30)
        @test st.gpu_busy ≈ 0.75 && st.gpu_w ≈ 50 && st.tps ≈ 20
        @test st.hist_gpu == Float32[0, 0.75] && st.hist_tps == Float32[0, 20]
        @test 0 <= st.cpu <= 1 && st.ram_total > st.ram_used > 0       # this machine's /proc
        GM.sample!(st, 102.0)                                          # not generating: no rate
        @test st.tps == 0
        for i in 1:200; GM.sample!(st, 102.0 + i); end
        @test length(st.hist_gpu) == GM.HIST
    end

    if isempty(get(ENV, "DISPLAY", ""))
        @warn "no DISPLAY — skipping the GUI window tests"
    elseif Threads.nthreads() < 2
        @warn "GUI window tests need julia -t 2 or more — skipping"
    else
        W, H = 900, 640
        envdir = mktempdir()            # this window's notes and places, not the user's
        PLACES = [GM.Place(n, mkpath(joinpath(envdir, n))) for n in ("Alpha", "Beta")]
        app = GM.App(; width = W, height = H, visible = false, vsync = false, theme = "Dark",
                     notes_file = joinpath(envdir, "notes.md"), places = PLACES, terminal_dir = PLACES[1].dir)
        key(k, down) = G.ImGuiIO_AddKeyEvent(app.io, k, down)
        type!(s) = G.ImGuiIO_AddInputCharactersUTF8(app.io, s)
        frames!(n = 1) = for _ in 1:n; GM.step!(app); end
        # One key edge per frame: imgui trickles queued input, but a chord's
        # down and up in one frame is not how a keyboard delivers it.
        function chord!(keys...)
            for k in keys;          key(k, true);  frames!(); end
            for k in reverse(keys); key(k, false); frames!(); end
        end
        function click!(which)
            x0, y0, x1, y1 = app.rects[which]
            G.ImGuiIO_AddMousePosEvent(app.io, (x0 + x1) / 2, (y0 + y1) / 2); frames!()
            G.ImGuiIO_AddMouseButtonEvent(app.io, 0, true);  frames!()
            G.ImGuiIO_AddMouseButtonEvent(app.io, 0, false); frames!()
        end
        # Enter (or a click) takes focus off the box; it comes back a frame or
        # two later. Keys pressed in between land nowhere, as they would for a
        # real keyboard, so wait for it rather than race it.
        refocused!() = until!(() -> app.active; timeout = 5)
        function until!(pred; timeout = 300)
            t0 = time()
            while !pred()
                time() - t0 > timeout && error("GUI test timed out after $(timeout)s")
                frames!()
            end
        end
        # The thread a running worker is on, sampled while it runs.
        tids = Int[]
        sample_worker!() = (t = app.task; t !== nothing && istaskstarted(t) && !istaskdone(t) &&
                            push!(tids, Threads.threadid(t)); nothing)
        rgb(px, i) = (px[i], px[i+1], px[i+2])
        to8(c) = round.(UInt8, 255 .* (c.x, c.y, c.z))
        try
            @testset "window and layout" begin
                frames!(2)                       # frame 1 only settles the font atlas
                @test G.ImGui_GetFontSize() == 18f0
                @test app.fbw[] == W && app.fbh[] == H
                # The prompt box spans the window and sits at its bottom edge.
                x0, y0, x1, y1 = app.rects[:prompt]
                st = unsafe_load(Ptr{G.ImGuiStyle}(G.ImGui_GetStyle()))
                @test x1 - x0 ≈ W - 2 * st.WindowPadding.x atol = 1
                @test app.rects[:stop][4] < y0
                # The stats row has the bottom line; the prompt box sits on it.
                sy0, sy1 = app.rects[:stat_ram][2], app.rects[:stat_ram][4]
                @test sy1 ≈ H - st.WindowPadding.y atol = 1
                @test y1 ≈ sy0 - st.ItemSpacing.y atol = 1
                until!(() -> haskey(app.rects, :stat_cpu); timeout = 10)   # a rate: it needs a second sample
                words = Dict(GM.stats_text(app))
                @test words["model"] == "none" && haskey(words, "CPU") && haskey(words, "RAM")
                @test occursin("GiB", words["RAM"])
                app.stats_open = false; frames!(2)
                @test app.rects[:prompt][4] ≈ H - st.WindowPadding.y atol = 1   # without it, the old layout
                app.stats_open = true; frames!(2)
            end

            @testset "notes: a box that saves itself, and the system prompt it becomes" begin
                @test !app.notes_open && GM.notes_text(app) == "" && !isfile(app.notes_file)
                top0 = app.rects[:transcript][2]
                click!(:notes_toggle)
                @test app.notes_open
                frames!(2)
                @test app.rects[:notes][2] < app.rects[:transcript][2] > top0   # above the transcript
                click!(:notes)
                type!("My test word is quokka."); frames!(2)
                @test GM.notes_text(app) == "My test word is quokka."
                @test !isfile(app.notes_file)                # not until the box is left
                click!(:notes_toggle)                        # Hide notes: saved
                @test !app.notes_open
                @test read(app.notes_file, String) == "My test word is quokka."
                @test GM.system_text(app) == GM.NOTES_HEADER * "\n\nMy test word is quokka."
                refocused!()
            end

            @testset "markdown in colour: headings, emphasis, maths, quotes" begin
                # Inline LaTeX becomes Unicode, in its own style and colour.
                @test GM.tex2uni(raw"\rightarrow") == "→"
                @test GM.tex2uni(raw"E = mc^2") == "E = mc²"
                @test GM.tex2uni(raw"v_0 \approx 9.81 \times t") == "v₀ ≈ 9.81 × t"
                @test GM.tex2uni(raw"\frac{GM}{r^2}") == "(GM)/(r²)"
                @test GM.tex2uni(raw"\Delta t, \alpha \neq \beta") == "Δ t, α ≠ β"
                @test GM.tex2uni(raw"x^{n+1}") == "xⁿ⁺¹" && GM.tex2uni(raw"x^{ab}") == "x^(ab)"
                @test GM.tex2uni(raw"\text{mass} \to \mathrm{curve}") == "mass → curve"
                p = only(GM.parse_md(raw"mass $\rightarrow$ motion" * "\n"))
                @test any(s -> s.style & GM.S_MATH != 0 && join(s.pieces) == "→", p.spans)
                # Colour by role: code, maths and links keep theirs; a heading's colour
                # wins over bold; bold and italic have their own.
                @test GM.color_for(GM.S_CODE | GM.S_BOLD, GM.C_H[1]) === GM.C_CODE
                @test GM.color_for(GM.S_MATH, nothing) === GM.C_MATH
                @test GM.color_for(GM.S_BOLD, GM.C_H[2]) === GM.C_H[2]
                @test GM.color_for(GM.S_BOLD | GM.S_ITALIC, nothing) === GM.C_BOLD
                @test GM.color_for(GM.S_ITALIC, nothing) === GM.C_ITALIC
                @test GM.color_for(0x00, nothing) === nothing
                # Each theme brings its own markdown palette.
                k = GM.theme_named("Gruvbox"); GM.apply_theme!(app, k)
                @test GM.C_H[1][] == GM._rgb(GM.THEMES[k].md[1]) && GM.C_BOLD[] == GM._rgb(GM.THEMES[k].md[4])
                @test all(t -> length(unique(t.md[1:3])) == 3, GM.THEMES)     # three distinct heading colours
                # All of it draws: headings with their rules, a quote bar, maths, a table.
                t = GM.Turn(:assistant, 20_000, "# H1\n\n## H2\n\n### H3\n\n**b** *i* `c` [l](x) " *
                            raw"$x^2$" * "\n\n> q\n\n- one\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n---\n")
                push!(app.turns, t); frames!(3)
                @test length(t.segs) >= 6 && all(s -> s.h > 0, t.segs)
                empty!(app.turns)
                GM.apply_theme!(app, GM.theme_named("Dark")); frames!()
            end

            @testset "characters no font has are left out, not drawn as U+FFFD" begin
                @test GM.WCHAR_BYTES in (2, 4)
                @test GM.GLYPH_FONT[] != C_NULL
                @test GM.display_text("plain → αβγ ⇒") == "plain → αβγ ⇒"         # Symbols/Greek are merged
                @test GM.display_text("a✅b") == (GM._has_glyph('✅') ? "a✅b" : "ab")
                # Emoji only with a scalable colour emoji font; Noto Color Emoji is
                # one bitmap strike FreeType will not scale, so it is not used.
                @test GM.display_text("hi \U1F680!") == (GM.EMOJI[] ? "hi \U1F680!" : "hi !")
                @test GM.display_text("x️‍y") == "xy"                   # selectors and joiners
                if GM.WCHAR_BYTES == 4 && GM.HAS_FREETYPE && GM.cjk_font_data() !== nothing
                    @test GM.display_text("你好") == "你好"                          # beyond what stb + 16-bit drew
                end
            end

            @testset "themes: presets, the code palette, the saved choice" begin
                mktempdir() do cfg
                    withenv("XDG_CONFIG_HOME" => cfg) do
                        @test GM.load_theme_choice() == ("Dark", nothing)   # nothing saved yet
                        k = GM.theme_named("nord")
                        @test GM.THEMES[k].name == "Nord" && GM.theme_named("no such") == 1
                        GM.apply_theme!(app, k); frames!(2)
                        th = GM.THEMES[k]
                        @test GM.style_color(G.ImGuiCol_WindowBg) == GM._rgb(th.bg)
                        @test app.clear == GM._rgb(th.bg) && app.dim[] == GM._rgb(th.dim)
                        # Code runs hold a class; the colour is the theme's, at draw time.
                        @test GM.HL_RGBA[GM.HL_FUNC] == GM._u32rgb(th.hl[3])
                        @test GM.C_USER[] == GM._rgb(th.user) && GM.indicator(app)[1] == GM.C_OFF[]
                        GM.save_theme_choice(app)
                        @test GM.load_theme_choice() == ("Nord", nothing)
                        # An accent of your own overrides the theme's, and is saved with it.
                        app.accent_custom, app.accent_rgb = true, 0x123456
                        GM.apply_theme!(app); frames!()
                        @test GM.style_color(G.ImGuiCol_CheckMark) == GM._rgb(0x123456)
                        GM.save_theme_choice(app)
                        @test GM.load_theme_choice() == ("Nord", 0x123456)
                        # The menu sits in the status bar and opens.
                        @test haskey(app.rects, :theme)
                        n0 = app.frames
                        click!(:theme); frames!(2)               # the open list, swatches and picker draw
                        @test app.frames == n0 + 5
                        @test app.theme_open
                        click!(:transcript)                      # a click elsewhere closes it…
                        frames!(2)
                        @test !app.theme_open && app.active      # …and hands the prompt the keyboard
                        app.accent_custom = false
                        GM.apply_theme!(app, GM.theme_named("Dark")); frames!(2)
                    end
                end
            end

            @testset "typing: UTF-8 in, Ctrl+Enter is a newline, no model refuses Enter" begin
                type!("héllo ✓ 100%"); frames!(2)
                @test GM.prompt_text(app) == "héllo ✓ 100%"
                chord!(G.ImGuiMod_Ctrl, G.ImGuiKey_Enter)
                type!("x"); frames!()
                @test GM.prompt_text(app) == "héllo ✓ 100%\nx"
                chord!(G.ImGuiKey_Enter)         # nothing to send to: the text stays
                frames!(2)
                @test GM.prompt_text(app) == "héllo ✓ 100%\nx"
                @test isempty(app.turns)
                refocused!()                     # Enter let go of the box; it took it back
                chord!(G.ImGuiMod_Ctrl, G.ImGuiKey_A)
                chord!(G.ImGuiKey_Backspace)
                @test GM.prompt_text(app) == ""
            end

            @testset "a reply is drawn as markdown" begin
                t = GM.Turn(:assistant, 10_000, "# Big\n\nsmall **text**\n\n```\ncode\n```\n")
                push!(app.turns, t)
                frames!(3)                       # code blocks size themselves a frame late
                @test length(t.segs) == 3
                @test all(s -> s.h > 0, t.segs)  # each segment drew and measured itself
                @test t.segs[1].h > t.segs[2].h  # the heading is set larger than body text
                md, _, _ = GM.capture!(app)
                app.markdown = false; frames!(2)
                raw, _, _ = GM.capture!(app)
                app.markdown = true
                @test md != raw
                empty!(app.turns); frames!()
            end

            # ── the embedded terminal: a pty, libvterm, drawn by imgui ──
            function open_terminal!(cmd)
                while app.term !== nothing; GM.close_terminal!(app); end
                app.term_open = false
                app.term_cmd = cmd
                GM.toggle_terminal!(app)
                frames!(2)
                return app.term
            end
            screen(t) = GM.term_text(t; lines = 1000)

            @testset "terminal: a child on a pty, drawn through libvterm" begin
                t = open_terminal!(`sh -c 'printf "ready \033[1;31mred\033[0m\n"; stty size; exec cat'`)
                @test app.term_open && t.proc !== nothing
                until!(() -> occursin("ready red", screen(t)); timeout = 30)
                # The child measured its terminal: the size the panel gave libvterm and the pty.
                until!(() -> occursin("$(t.rows) $(t.cols)", screen(t)); timeout = 30)
                @test t.rows >= 2 && t.cols >= 10
                @test startswith(screen(t), "ready red\n$(t.rows) $(t.cols)")
                # SGR 31 came through as red: a run whose red channel dominates.
                red = filter(r -> strip(r.text) == "red", t.lines[1])
                @test length(red) == 1 && (red[1].fg & 0xff) > 0xa0 && ((red[1].fg >> 8) & 0xff) < 0x80
                @test app.term_focused                  # opening it gave it the keyboard
                # Keys go through libvterm's encoder to the pty: the tty echoes,
                # then cat prints the line back.
                type!("abc é"); frames!()
                chord!(G.ImGuiKey_Enter)
                until!(() -> occursin("abc é\nabc é", screen(t)); timeout = 30)
                @test !occursin("abc", GM.prompt_text(app))   # the chat box did not get the keys
                # Ctrl+C: the pty turns it into SIGINT; cat dies, the pty hangs up.
                chord!(G.ImGuiMod_Ctrl, G.ImGuiKey_C)
                until!(() -> t.exited; timeout = 30)
                @test t.fd == -1
                click!(:term_restart)
                until!(() -> occursin("ready red", screen(t)) && !t.exited; timeout = 30)
                @test !t.exited && t.fd >= 0
            end

            @testset "terminal: scrollback, the wheel, typing returns to live" begin
                t = open_terminal!(`sh -c 'seq 1 300; exec cat'`)
                until!(() -> occursin("300", screen(t)); timeout = 30)
                @test length(t.scrollback) >= 300 - t.rows
                @test t.scrollback[1] == "1"            # sb_pushline4 handed over every line
                x0, y0, x1, y1 = app.rects[:term]
                G.ImGuiIO_AddMousePosEvent(app.io, (x0 + x1) / 2, (y0 + y1) / 2); frames!()
                G.ImGuiIO_AddMouseWheelEvent(app.io, 0f0, 2f0); frames!()
                @test t.view == 6
                type!("q"); frames!()
                @test t.view == 0
                tail = split(GM.term_text(t; lines = 5), '\n')
                @test length(tail) <= 5
            end

            @testset "terminal: hiding keeps it running; the splitter moves" begin
                t = app.term
                click!(:terminal)                       # Hide terminal
                @test !app.term_open && app.term === t && t.fd >= 0
                before = t.bytes_in
                GM.send_bytes!(t, "still here\r")
                until!(() -> t.bytes_in > before; timeout = 30)   # read while hidden
                @test app.rects[:transcript][3] > W - 40          # chat has the full width again
                click!(:terminal)                       # show it again
                @test app.term_open
                frames!(2)
                s0 = app.split
                x0, y0, x1, y1 = app.rects[:split]
                G.ImGuiIO_AddMousePosEvent(app.io, (x0 + x1) / 2, (y0 + y1) / 2); frames!()
                G.ImGuiIO_AddMouseButtonEvent(app.io, 0, true); frames!()
                G.ImGuiIO_AddMousePosEvent(app.io, (x0 + x1) / 2 - 90, (y0 + y1) / 2); frames!()
                G.ImGuiIO_AddMouseButtonEvent(app.io, 0, false); frames!()
                @test app.split < s0
                app.split = 0.5f0
            end

            @testset "terminals: tabs, places, Go, Close" begin
                first_ = app.term
                @test app.terms == [first_]
                t2 = GM.open_terminal!(app, `sh`, PLACES[2].dir)
                frames!(3)
                @test app.term === t2 && length(app.terms) == 2 && t2.kind === :shell
                @test t2.title == "sh  ·  Beta"            # the place's name, not the folder's
                @test GM.term_title(app, :julia, GM.julia_cmd(), envdir) == "julia  ·  " * basename(envdir)
                until!(() -> (t2.cwd_t = 0; GM.term_cwd!(t2) == PLACES[2].dir); timeout = 30)
                # Go: the terminal's own `cd`, as typed.
                GM.send_bytes!(t2, GM.cd_line(t2.kind, PLACES[1].dir))
                until!(() -> (t2.cwd_t = 0; GM.term_cwd!(t2) == PLACES[1].dir); timeout = 30)
                @test GM.term_where(t2) == "a sh shell in $(PLACES[1].dir)"
                click!(:term_tab)                           # the first tab
                @test app.term === first_
                before = t2.bytes_in
                GM.send_bytes!(t2, "echo background\r")
                until!(() -> t2.bytes_in > before; timeout = 30)   # a tab not showing is still read
                app.term = t2; frames!(2)
                click!(:term_close)
                @test app.terms == [first_] && app.term === first_ && t2.fd == -1 && app.term_open
                frames!(2)                                  # one tab fewer: the buttons moved left
                click!(:term_close)                         # the last one: the panel goes
                @test isempty(app.terms) && app.term === nothing && !app.term_open
                frames!(2)
                @test app.rects[:transcript][3] > W - 40
                # No model: Ask says so instead of sending.
                t = open_terminal!(`sh -c 'echo hi; exec cat'`)
                n = length(app.turns)
                @test !GM.ask_terminal!(app)
                @test length(app.turns) == n + 1 && app.turns[end].role === :note
                empty!(app.turns)
                click!(:terminal)                       # hide for the tests below
            end

            @testset "Pull: a failed download says so and leaves the window usable" begin
                withenv("OLLAMA_MODELS" => mktempdir(), "LLAMACHAT_MODELS" => mktempdir()) do
                    click!(:pull_toggle)
                    @test app.pull_open
                    frames!()
                    click!(:pull_name)
                    type!("no-such-model-llamachat:none"); frames!()
                    click!(:pull_go)
                    @test app.pull !== nothing
                    until!(() -> app.pull === nothing; timeout = 60)
                    @test app.turns[end].role === :error
                    @test startswith(app.turns[end].text, "download failed")
                    @test app.pull_open                    # the row stays open to try again
                    if get(ENV, "LLAMACHAT_TEST_PULL", "") == "1"
                        # Opt-in: a real 44 MiB download, through the UI.
                        click!(:pull_name); type!("all-minilm"); frames!()
                        click!(:pull_go)
                        until!(() -> app.pull === nothing; timeout = 600)
                        @test app.turns[end].role === :ready
                        @test any(m -> first(m) == "all-minilm:latest", app.models)
                    end
                    app.pull_open && click!(:pull_toggle)   # a successful pull closes it itself
                    @test !app.pull_open
                    empty!(app.turns)
                end
                app.models = GM.list_chat_models()         # back to the real stores
                refocused!()                               # closing the row gave the prompt back
                @test app.active
            end

            if MODEL === nothing
                @warn "no generative model — skipping the GUI chat tests"
            else
                app.max_tokens = 160            # long enough to be seen arriving
                @testset "the model loads on a worker; its progress lands in the transcript" begin
                    GM.load!(app, MODEL; n_ctx = 2048, think = false, temp = 0.0)
                    @test app.state === :loading
                    empty!(tids)
                    until!(() -> (sample_worker!(); app.state !== :loading))
                    @test app.state === :idle
                    @test !isempty(tids) && all(!=(Threads.threadid()), tids)
                    @test app.n_ctx == 2048
                    # "loading … ok" read as still loading; the window says ready.
                    @test app.turns[end].role === :ready
                    @test startswith(app.turns[end].text, "$MODEL is ready")
                    @test occursin(LC.placement(app.session), app.turns[end].text)   # where it runs
                    @test !any(t -> occursin("loading", t.text), app.turns)
                    @test GM.indicator(app)[2] == "ready"
                    @test app.title == "LlamaChat · $MODEL · ready"
                    @test startswith(GM.prompt_hint(app), "Message $MODEL")
                    @test any(m -> GM.same_model(first(m), MODEL), app.models)   # the picker lists it
                    # The notes went in as its system prompt, and it says so.
                    @test occursin("My test word is quokka.", app.session.system)
                    @test occursin("it has your notes", app.turns[end].text)
                    @test !app.think[] && !app.session.think      # `think = false` unticked the box
                end

                @testset "Enter sends; the box comes back empty and focused" begin
                    type!("Say hello in five words."); frames!()
                    empty!(tids)
                    chord!(G.ImGuiKey_Enter)
                    @test app.state === :generating
                    @test app.turns[end-1].role === :user
                    @test app.turns[end-1].text == "Say hello in five words."
                    @test GM.prompt_text(app) == ""
                    refocused!()
                    @test app.active
                    # imgui keeps its own copy of an active field. If clearing our
                    # buffer had not reached it, typing would append to the old text.
                    type!("z"); frames!(2)
                    @test GM.prompt_text(app) == "z"
                    chord!(G.ImGuiKey_Backspace)
                    @test GM.prompt_text(app) == ""
                end

                @testset "the reply streams on a worker while this thread renders" begin
                    lens = Int[]; stamps = Float64[]
                    until!() do
                        sample_worker!()
                        push!(lens, ncodeunits(app.turns[end].text)); push!(stamps, time())
                        app.state !== :generating
                    end
                    t = app.turns[end]
                    @test !isempty(tids) && all(!=(Threads.threadid()), tids)
                    @test length(unique(lens)) > 3           # arrived in pieces, drawn as it came
                    @test app.state === :idle
                    @test app.last isa LC.Response && app.last.n_gen > 0
                    @test app.last.stop in (:eog, :max_tokens)
                    @test startswith(t.stats, "[") && occursin("gen tok", t.stats)
                    @test occursin("tok/s", GM.status_text(app))
                    @test app.ctx_used == app.session.n_past > 0
                    # qwen3 reasons even with think = false; it is folded, not inline.
                    @test !occursin("<think>", t.answer) && !occursin("</think>", t.answer)
                    startswith(lstrip(t.text), "<think>") && @test !isempty(t.label)
                    gaps = diff(stamps) .* 1000
                    @info "GUI stream" frames = length(stamps) n_gen = app.last.n_gen tok_s = round(app.last.n_gen / app.last.t_gen; digits = 1) gap_ms_median = round(sort(gaps)[cld(length(gaps), 2)]; digits = 1) gap_ms_max = round(maximum(gaps); digits = 1)
                end

                @testset "Attach sends the terminal with the message" begin
                    t = open_terminal!(`sh -c 'echo "the answer is 4217"; exec cat'`)
                    until!(() -> occursin("4217", screen(t)); timeout = 30)
                    click!(:attach)
                    @test app.attach[]
                    @test occursin("terminal attached", GM.prompt_hint(app))
                    app.max_tokens = 24
                    refocused!()
                    type!("What number does my terminal show?"); frames!()
                    chord!(G.ImGuiKey_Enter)
                    @test app.state === :generating
                    u = app.turns[end-1]
                    @test u.role === :user && u.text == "What number does my terminal show?"
                    @test occursin("the answer is 4217", u.attached)
                    @test !app.attach[]                 # one message at a time
                    until!(() -> app.state === :idle)   # the session is the worker's until then
                    sent = last(app.session.history[end-1])  # the user message the model got
                    @test occursin("the answer is 4217", sent) && endswith(sent, u.text)
                end

                @testset "Ask sends the terminal now; the stats row follows the reply" begin
                    t = app.term
                    click!(:term_ask)
                    @test app.state === :generating
                    u = app.turns[end-1]
                    @test u.text == GM.ASK_DEFAULT && occursin("the answer is 4217", u.attached)
                    seen = Float32[]
                    until!() do
                        push!(seen, app.stats.tps)
                        app.state === :idle
                    end
                    sent = last(app.session.history[end-1])
                    @test startswith(sent, "Here is my terminal (a sh shell in ") && endswith(sent, GM.ASK_DEFAULT)
                    @test startswith(Dict(GM.stats_text(app))["model"], "last ")
                    @test haskey(Dict(GM.stats_text(app)), "VRAM")     # the backend is up: the card's memory shows
                    # With text in the box, that is the question.
                    q = codeunits("What number is that?")
                    copyto!(app.buf, 1, q, 1, length(q)); app.buf[length(q) + 1] = 0x00
                    @test GM.ask_terminal!(app)
                    @test app.turns[end-1].text == "What number is that?" && GM.prompt_text(app) == ""
                    # Asked again while it replies: queued with the terminal attached.
                    @test GM.ask_terminal!(app)
                    @test app.queued && app.attach[] && GM.prompt_text(app) == GM.ASK_DEFAULT
                    until!(() -> app.state === :idle && !app.queued)
                    until!(() -> app.state === :idle)
                    @test app.turns[end-1].text == GM.ASK_DEFAULT && !isempty(app.turns[end-1].attached)
                    click!(:terminal)                   # hide it again
                    @test !app.term_open
                    refocused!()
                end

                @testset "New chat hands the model changed notes and the Think box" begin
                    s = app.session
                    sys0 = s.system
                    b = codeunits("Second note.")
                    copyto!(app.notes, 1, b, 1, length(b)); app.notes[length(b) + 1] = 0x00
                    @test s.system == sys0                    # not mid-conversation
                    @test GM.new_chat!(app)
                    @test occursin("Second note.", s.system) && !occursin("quokka", s.system)
                    @test s.n_past == 0 && isempty(s.history)
                    @test occursin(LC._TERSE_DIRECTIVE, s.system) || LC._is_gemma4(s.template)
                    app.think[] = true
                    @test GM.new_chat!(app)
                    @test s.think && !occursin(LC._TERSE_DIRECTIVE, s.system) && occursin("Second note.", s.system)
                    app.think[] = false
                    @test GM.new_chat!(app)
                    @test !s.think
                    frames!(2)
                end

                @testset "a stale Super or Alt does not eat Enter" begin
                    # A compositor binding can leave Super reported as held; imgui's
                    # Enter is a no-modifier Shortcut, so the box took characters and
                    # ignored Enter. Down here, and the release never comes until after.
                    for mod in ((G.ImGuiKey_LeftSuper, G.ImGuiMod_Super), (G.ImGuiKey_LeftAlt, G.ImGuiMod_Alt))
                        app.max_tokens = 8
                        refocused!()
                        for k in mod; key(k, true); end; frames!()
                        type!("Say ok."); frames!()
                        chord!(G.ImGuiKey_Enter)
                        @test app.state === :generating
                        @test GM.prompt_text(app) == ""
                        for k in mod; key(k, false); end; frames!()
                        until!(() -> app.state === :idle)
                    end
                end

                @testset "Enter while a reply streams queues the message; it goes when the reply ends" begin
                    app.max_tokens = 300
                    refocused!()
                    type!("Count from 1 to 100, one number per line."); frames!()
                    chord!(G.ImGuiKey_Enter)
                    @test app.state === :generating
                    refocused!()
                    type!("Now say done."); frames!()
                    chord!(G.ImGuiKey_Enter)
                    @test app.state === :generating        # 300 tokens outlast a few frames
                    @test app.queued
                    @test GM.prompt_text(app) == "Now say done."    # kept, still editable
                    @test occursin("your message sends when this reply ends", GM.status_text(app))
                    n = length(app.turns)
                    until!(() -> !app.queued)              # the reply ended; the queue went
                    @test app.state === :generating
                    @test app.turns[end-1].role === :user && app.turns[end-1].text == "Now say done."
                    @test length(app.turns) == n + 2
                    @test GM.prompt_text(app) == ""
                    refocused!()
                    type!("z"); frames!(2)                 # imgui's copy was emptied too
                    @test GM.prompt_text(app) == "z"
                    chord!(G.ImGuiKey_Backspace)
                    until!(() -> app.state === :idle)
                end

                @testset "Stop ends a reply at a token and keeps the session consistent" begin
                    app.max_tokens = 1000
                    refocused!()                 # hiding the terminal handed focus back
                    type!("Count from 1 to 300, one number per line."); frames!()
                    chord!(G.ImGuiKey_Enter)
                    until!(() -> ncodeunits(app.turns[end].text) > 0)
                    click!(:stop)
                    until!(() -> app.state === :idle)
                    s = app.session
                    @test app.last.stop === :interrupt
                    @test app.last.n_gen < 1000
                    @test occursin("interrupt", app.turns[end].stats)
                    @test !s.cancel[]
                    formatted = LC._format(s, LC._messages(s), false)
                    @test formatted[1:length(s.decoded)] == s.decoded
                    # ...and the next turn runs normally.
                    app.max_tokens = 32
                    refocused!()                 # the click on Stop handed focus back
                    type!("Say ok."); frames!()
                    chord!(G.ImGuiKey_Enter)
                    @test app.state === :generating
                    until!(() -> app.state === :idle)
                    @test app.last.stop in (:eog, :max_tokens)
                end

                @testset "the GPU drew it, against the window's own background" begin
                    # The full-viewport window covers every pixel, so the GL clear
                    # colour must show nowhere: make it one that cannot hide.
                    app.clear = G.ImVec4(1f0, 0f0, 1f0, 1f0)
                    bg = to8(GM.style_color(G.ImGuiCol_WindowBg))
                    px, w, h = GM.capture!(app)
                    n = w * h
                    @test count(i -> rgb(px, i) == (0xff, 0x00, 0xff), 1:4:4n) == 0
                    onbg = count(i -> rgb(px, i) == bg, 1:4:4n)
                    @test onbg > n ÷ 4                     # the window's own colour…
                    full = n - onbg
                    @test full > 2000                      # …and things drawn on it

                    click!(:new_chat)
                    @test isempty(app.turns)
                    @test isempty(app.session.history) && app.ctx_used == 0
                    px, w, h = GM.capture!(app)
                    empty_ = n - count(i -> rgb(px, i) == bg, 1:4:4n)
                    @test full > empty_ + 2000             # the transcript was text
                    @info "GUI pixels" off_window_bg = (with_transcript = full, empty = empty_)
                end

                @testset "switching models frees the old one before loading the new" begin
                    old = app.session
                    @test GM.switch!(app, MODEL)         # the same name: a reload is still a switch
                    @test app.state === :loading && app.session === nothing
                    @test !GM.switch!(app, MODEL)        # one at a time
                    @test !GM.send!(app, "hi")           # nothing to send to yet
                    @test GM.indicator(app)[2] == "loading"
                    @test occursin("Enter sends once it is ready", GM.prompt_hint(app))
                    until!(() -> app.state !== :loading)
                    @test app.state === :idle
                    @test !old.isopen && app.session.isopen
                    @test any(t -> t.role === :note && startswith(t.text, "Switched from"), app.turns)
                    @test app.turns[end].role === :ready
                    @test GM.same_model("qwen3-coder", "qwen3-coder:latest")
                    @test !GM.same_model("qwen3", "qwen3:4b")
                end

                @testset "Unload frees the model and keeps the window" begin
                    s = app.session
                    frames!()
                    click!(:unload)
                    until!(() -> app.state !== :unloading)
                    @test app.state === :empty && app.session === nothing
                    @test !s.isopen
                    @test GM.indicator(app)[2] == "no model loaded"
                    @test startswith(GM.prompt_hint(app), "Pick a model")
                    frames!(2)
                    @test app.title == "LlamaChat"
                    # With nothing to report the status line is shorter; the
                    # transcript still starts below it, at the left margin.
                    @test app.rects[:transcript][2] > app.rects[:model][4]
                    @test app.rects[:transcript][1] ≈ app.rects[:prompt][1]
                    @test !GM.send!(app, "hi")
                end
            end
            @testset "typed mode: a decision model swaps the chat side for State, Questions, Decide" begin
                tdir = mktempdir()
                g = fake_typed_gguf(joinpath(tdir, "laya_english.gguf"), "english")
                withenv("LLAMACHAT_LAYA" => fake_laya_bin(tdir)) do
                    @test GM.model_kind(app, g) === :typed
                    until!(() -> app.state in (:empty, :idle, :failed); timeout = 60)
                    @test !GM.typed(app)
                    GM.load!(app, g)
                    until!(() -> app.state !== :loading; timeout = 60)
                    @test app.state === :idle && GM.typed(app) && app.session isa LC.TypedSession
                    frames!(2)
                    # The panel took the transcript's place; the sample is ready to run.
                    @test haskey(app.rects, :typed_decide) && app.rects[:typed_state][2] < app.rects[:typed_q][2]
                    @test occursin("\"churn_risk\"", GM.buf_text(app.typed_q)) && app.typed_builtin
                    @test !GM.new_chat!(app) && !GM.send!(app, "hi")      # chat verbs do nothing here
                    click!(:typed_decide)
                    until!(() -> app.state === :idle; timeout = 60)
                    @test app.typed_err == "" && length(app.typed_out) == 1
                    @test [a.id for a in app.typed_out[1]] == ["intent", "frustration", "churn_risk"]
                    @test occursin("last decision 3 answers", GM.status_text(app))
                    @test startswith(Dict(GM.stats_text(app))["model"], "last 12.5 ms")
                    frames!(2)
                    @test haskey(app.rects, :typed_out)
                    # A batch file fills the State box; Decide answers each state.
                    bf = joinpath(tdir, "batch.json")
                    write(bf, """{"states": [{"l": "one"}, {"l": "two"}, "three"], "questions": $TYPED_QS}""")
                    @test GM.typed_load!(app, bf)
                    @test occursin("a batch of 3 states, 3 questions", app.typed_note) && !app.typed_builtin
                    @test GM.typed_states(GM.buf_text(app.typed_state)) == Any[LC.ODict("l" => "one"), LC.ODict("l" => "two"), "three"]
                    @test isempty(app.typed_out)                          # the old answers went with the old request
                    @test GM.typed_decide!(app) && app.state === :deciding && GM.indicator(app)[2] == "deciding"
                    until!(() -> app.state === :idle; timeout = 60)
                    @test length(app.typed_out) == 3
                    frames!(2)
                    # A state file leaves the questions; a questions file leaves the state.
                    sf = joinpath(tdir, "state.json"); write(sf, """{"message": "only a state"}""")
                    qtext = GM.buf_text(app.typed_q)
                    @test GM.typed_load!(app, sf) && GM.buf_text(app.typed_q) == qtext
                    @test GM.typed_states(GM.buf_text(app.typed_state)) == Any[LC.ODict("message" => "only a state")]
                    @test GM.typed_states("just text") == Any["just text"]
                    @test GM.json_files(tdir) == [bf, sf]
                    # What is wrong is said in the panel, and nothing is sent.
                    GM.set_buf!(app.typed_q, """{"q": {"type": "pick", "instructions": "x"}}""")
                    @test !GM.typed_decide!(app) && app.state === :idle
                    @test startswith(app.typed_err, "questions.q.type: must be")
                    GM.set_buf!(app.typed_q, "{ not json")
                    @test !GM.typed_decide!(app) && app.typed_err == "questions: is not valid JSON"
                    @test !GM.typed_load!(app, joinpath(tdir, "missing.json")) && startswith(app.typed_err, "no such file")
                    frames!(2)
                    # Ask: the terminal is the state, with questions about terminals.
                    t = open_terminal!(`sh -c 'echo "ls: cannot access nope"; exec cat'`)
                    until!(() -> occursin("cannot access", screen(t)); timeout = 30)
                    app.typed_builtin = true
                    click!(:term_ask)
                    until!(() -> app.state === :idle; timeout = 60)
                    st = GM.typed_states(GM.buf_text(app.typed_state))[1]
                    @test occursin("cannot access nope", st["terminal"]) && startswith(st["where"], "a sh shell in ")
                    @test occursin("\"failed\"", GM.buf_text(app.typed_q)) && app.typed_err != ""   # the stand-in knows three ids
                    GM.close_terminal!(app)
                    # Unload: the daemon ends, and the chat side is back.
                    proc = app.session.proc
                    @test GM.unload!(app)
                    until!(() -> app.state === :empty; timeout = 60)
                    @test !process_running(proc) && !GM.typed(app)
                    frames!(2)
                    @test app.rects[:transcript][2] > app.rects[:model][4]
                end
            end
        finally
            GM.close!(app)
        end

        @testset "close! frees the model and the window, once" begin
            @test app.term === nothing                  # the terminal went with it
            @test app.session === nothing
            @test app.win == C_NULL
            GM.close!(app)                     # idempotent
            @test app.win == C_NULL
        end

        @testset "gui() opens with no model unless one is named" begin
            withenv("LLAMACHAT_GUI_MODEL" => nothing) do
                @test LC.gui_default_model() === nothing
            end
            withenv("LLAMACHAT_GUI_MODEL" => "qwen3:4b") do
                @test LC.gui_default_model() == "qwen3:4b"
            end
            withenv("LLAMACHAT_GUI_MODEL" => nothing) do
                @test LC.gui(; visible = false, vsync = false, max_frames = 3) === nothing
            end
        end

        if MODEL !== nothing
            @testset "LlamaChat.gui end to end" begin
                # Closing while the model is still loading: the window stays up
                # until the load lands, then frees it.
                @test LC.gui(MODEL; visible = false, vsync = false, max_frames = 3, n_ctx = 512) === nothing
            end
        end

        @testset "one GLFW in the process" begin
            # eachline, not read(): a whole-file read of /proc/self/maps came back
            # without the mapping in a full process.
            maps = unique(split(l)[end] for l in eachline("/proc/self/maps") if occursin("libglfw", l))
            @test length(maps) == 1
            @test !isempty(maps) && realpath(maps[1]) == realpath(joinpath(GUI_DIR, "libglfw.so"))
        end
    end
end
end

end

println("✓ LlamaChat app tests passed")
