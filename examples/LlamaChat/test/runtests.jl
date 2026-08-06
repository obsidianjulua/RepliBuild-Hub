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

    # Distance the cursor travels back up. The caller prints the reply plus one
    # newline; a reply that already ends in a newline sits one line further up.
    @test LC._redraw_up("one line", 80) == 1
    @test LC._redraw_up("one line\n", 80) == 2           # models end replies this way
    @test LC._redraw_up("a\nb", 80) == 2
    @test LC._redraw_up("a\nb\n", 80) == 3
    @test LC._redraw_up("a\n\n", 80) == 3
    @test LC._redraw_up(repeat("x", 81), 80) == 2        # soft wrap counts
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

    # Non-tty: never emit cursor-movement escapes into a pipe or a file.
    buf = IOBuffer()
    @test LC._rerender_markdown(buf, "# hi") == false
    @test isempty(take!(buf))
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
