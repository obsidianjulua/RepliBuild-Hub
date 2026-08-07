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

@testset "JIT engine registered for the vendored library" begin
    engines = RepliBuild.JITManager.GLOBAL_JIT.engines
    @test length(engines) == 1
    @test engines[1].init_error === nothing
    @test occursin("libllamacpp", engines[1].binary_path)
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

@testset "markdown parsing and fallback" begin
    m = md("# Title\n\nsome `code` here")
    @test m isa Markdown.MD
    @test occursin("Title", sprint(show, MIME"text/plain"(), m))

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

@testset "Response markdown display" begin
    base = Response("**bold**", 1, 1, 0.1, 0.1, :eog, false)
    @test base.markdown == false                     # 7-arg form still works
    @test sprint(show, MIME"text/plain"(), base) == "**bold**"

    rendered = Response("**bold**", 1, 1, 0.1, 0.1, :eog, false, true)
    shown = sprint(show, MIME"text/plain"(), rendered)
    @test shown != "**bold**"                        # went through the renderer
    @test occursin("bold", shown)

    # Streamed responses still show throughput, markdown or not — the text is
    # already on screen.
    streamed = Response("**bold**", 1, 1, 0.1, 0.1, :eog, true, true)
    @test occursin("tok", sprint(show, MIME"text/plain"(), streamed))

    @test md(rendered) isa Markdown.MD
end

@testset "model resolution" begin
    @test !isempty(LC.list_models())         # ollama store is populated on this box
    @test all(sz -> sz > 0, last.(LC.list_models()))
    @test LC.resolve_model(@__FILE__) == @__FILE__      # a path passes through
    @test_throws ErrorException LC.resolve_model("definitely-not-a-model:v0")
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
    s = ChatSession(MODEL; n_ctx = 1024, temp = 0.0)   # greedy → deterministic

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
        r = chat(s, "Say hello."; max_tokens = 16, stream = false)
        @test r isa Response
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
        r = chat(s, "And again."; max_tokens = 16, stream = false)

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
        r = chat(s, "Reply with the word ok."; max_tokens = 8, stream = false)
        @test r.text isa String
        @test String(r) == r.text
        @test ("got: " * r) == "got: " * r.text
        @test sprint(show, MIME"text/plain"(), r) == r.text      # not streamed → shows text
        r2 = Response(r.text, r.n_prompt, r.n_gen, r.t_prompt, r.t_gen, r.stop, true)
        @test occursin("tok", sprint(show, MIME"text/plain"(), r2))  # streamed → shows stats
    end

    @testset "reset! clears conversation and cache" begin
        reset!(s)
        @test isempty(s.history)
        @test isempty(s.decoded)
        @test s.n_past == 0
        r = chat(s, "Say hi."; max_tokens = 8, stream = false)   # usable afterwards
        @test r.n_gen > 0
    end

    @testset "context budget is enforced, not overrun" begin
        small = ChatSession(MODEL; n_ctx = 64, temp = 0.0)
        try
            long = repeat("the quick brown fox jumps over the lazy dog. ", 40)
            @test_throws ErrorException chat(small, long; max_tokens = 4, stream = false)
            @test isempty(small.history)      # the failed turn was rolled back
        finally
            close!(small)
        end
    end

    @testset "teardown is idempotent" begin
        close!(s)
        @test !s.isopen
        close!(s)
        @test !s.isopen
        @test_throws ErrorException chat(s, "anything")
    end
end

end

println("✓ LlamaChat app tests passed")
