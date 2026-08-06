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

```julia
using LlamaChat

chat("write a haiku about pointers")
chat("now make it about DWARF")            # remembers the turn before
start!("qwen2.5-coder:1.5b-base")          # switch models
chatrepl()                                 # interactive
```
"""
module LlamaChat

import JSON

# ── ABI layer: the generated wrapper ─────────────────────────────────────────
# Resolves its shared library sibling-first, so the copy in lib/ is
# self-contained. Its __init__ registers this binary's JIT engine, which is
# what Tier-2 entry points (model load, context init) dispatch through.
#
# `import`, deliberately NOT `using`. A wrapper generated from C++ DWARF
# exports thousands of names harvested from every TU that landed in the debug
# info — libstdc++ included — and several of them shadow Base. llamacpp exports
# `error` (from `codecvt_base::result.error`), so `using .Llamacpp` makes a bare
# `error("...")` call an ambiguous binding: every failure path in this file dies
# with `UndefVarError: error not defined` instead of raising. It is invisible
# until something actually goes wrong, because the happy path never calls it.
# Importing the module and going through `L.` keeps this namespace clean.
include(joinpath(@__DIR__, "..", "lib", "Llamacpp.jl"))
import .Llamacpp
const L = Llamacpp

export chat, chatrepl, start!, reset!, close!, ChatSession, Response,
       list_models, resolve_model, run_demo

# ─────────────────────────────────────────────────────────────────────────────
# Model resolution — ollama's blob store, so you can say "qwen3-coder" instead
# of "/var/lib/ollama/blobs/sha256-1194192cf2a1...".
# ─────────────────────────────────────────────────────────────────────────────

const OLLAMA_ROOT = get(ENV, "OLLAMA_MODELS", "/var/lib/ollama")
const REGISTRY    = "registry.ollama.ai"

# qwen3-coder is 30B-A3B: MoE, so only ~3B params are active per token. On CPU
# that makes an 18 GB model faster than a dense 8 GB one, and it has a chat
# template baked into the GGUF. Override with $LLAMACPP_CHAT_MODEL.
const DEFAULT_MODEL = get(ENV, "LLAMACPP_CHAT_MODEL", "qwen3-coder")

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
    p = joinpath(OLLAMA_ROOT, "manifests", REGISTRY, ns, model, tag)
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
              "$OLLAMA_ROOT)" * (isempty(avail) ? "" : "\n  available: $avail"))
    end
    manifest = JSON.parsefile(mp)
    for layer in manifest["layers"]
        layer["mediaType"] == "application/vnd.ollama.image.model" || continue
        blob = joinpath(OLLAMA_ROOT, "blobs", replace(layer["digest"], ':' => '-'))
        isfile(blob) || error("manifest $mp points at a missing blob: $blob")
        return blob
    end
    error("manifest $mp has no model layer")
end

"""
    list_models() -> Vector{Tuple{String,Int}}

Every ollama model visible in the local blob store, as (name, bytes).
"""
function list_models()
    out = Tuple{String,Int}[]
    root = joinpath(OLLAMA_ROOT, "manifests", REGISTRY)
    isdir(root) || return out
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
    return out
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

# llama.cpp writes a few hundred lines of loader detail to stderr. This is an
# fd-level redirect (not just Base.stderr) because the noise comes from C.
function _quiet(f, verbose::Bool)
    verbose && return f()
    devnull_io = open("/dev/null", "w")
    saved = stderr
    try
        redirect_stderr(devnull_io)
        return f()
    finally
        redirect_stderr(saved)
        close(devnull_io)
    end
end

const _backend_up = Ref(false)
function _ensure_backend(verbose::Bool)
    _backend_up[] && return
    _quiet(verbose) do
        L.llama_backend_init()
    end
    _backend_up[] = true
    return
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
    stop::Symbol           # :eog | :max_tokens | :ctx_full | :decode_error
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
# return value is just noise — show the throughput instead.
function Base.show(io::IO, ::MIME"text/plain", r::Response)
    if r.streamed
        printstyled(io, _stats_line(r); color = :light_black)
    else
        print(io, r.text)
    end
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
    ChatSession(model = DEFAULT_MODEL; kwargs...)

Load a model and open a context. `model` is an ollama name or a path.

  `system`       system prompt (default none)
  `n_ctx`        context window (default 4096)
  `n_threads`    default = physical cores (SMT threads / 2)
  `n_gpu_layers` default 0 — this build is CPU-only (no ggml GPU backends)
  `temp`         default 0.7; `temp <= 0` selects greedy sampling
  `top_k`/`top_p`/`min_p`  default 40 / 0.95 / 0.05
  `seed`         default random
  `verbose`      let llama.cpp's loader log to stderr (default false)
"""
function ChatSession(model::AbstractString = DEFAULT_MODEL;
                     system::AbstractString = "",
                     n_ctx::Integer = 4096,
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

    verbose || print(stderr, "loading $model … ")
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

    verbose || println(stderr, "ok  ($(round((time_ns()-t0)/1e9, digits=1))s, " *
                               "n_ctx=$n_ctx, $n_threads threads, " *
                               "template=$(tmpl === nothing ? "chatml (fallback)" : "built-in"))")
    return s
end

function close!(s::ChatSession)
    s.isopen || return s
    s.smpl  != C_NULL && L.llama_sampler_free(s.smpl)
    s.ctx   != C_NULL && L.llama_free(s.ctx)
    s.model != C_NULL && L.llama_model_free(s.model)
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

function _generate!(s::ChatSession, max_tokens::Int, stream::Bool, io::IO)
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
            stream && (print(io, chunk); flush(io))
        end
    end

    # Anything left in `pending` is a truncated code point; emit it so the text
    # round-trips byte-for-byte rather than silently dropping bytes.
    if !isempty(pending)
        tail = String(pending)
        write(out, tail)
        stream && print(io, tail)
    end
    return String(take!(out)), ngen, stop
end

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

const _SESSION = Ref{Union{Nothing,ChatSession}}(nothing)

"""
    start!(model = DEFAULT_MODEL; kwargs...) -> ChatSession

Open (or replace) the session that bare `chat("...")` talks to. Same keywords
as [`ChatSession`](@ref).
"""
function start!(model::AbstractString = DEFAULT_MODEL; kwargs...)
    cur = _SESSION[]
    cur !== nothing && cur.isopen && close!(cur)
    _SESSION[] = ChatSession(model; kwargs...)
    return _SESSION[]
end

function session()
    s = _SESSION[]
    (s === nothing || !s.isopen) && return start!()
    return s
end

"""
    chat(prompt; kwargs...) -> Response
    chat(session, prompt; kwargs...) -> Response

Send `prompt` as a user turn and generate the reply. The session keeps the
conversation, so follow-up turns see what came before; `reset!` clears it.

  `max_tokens` cap on generated tokens (default 512)
  `stream`     print tokens as they arrive (default true)
  `io`         where to stream (default stdout)

The reply is `r.text`. When streamed, the REPL shows a throughput line instead
of repeating the text.
"""
chat(prompt::AbstractString; kwargs...) = chat(session(), prompt; kwargs...)

function chat(s::ChatSession, prompt::AbstractString;
              max_tokens::Integer = 512, stream::Bool = true, io::IO = stdout)
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
    text, ngen, stop = try
        _generate!(s, Int(max_tokens), stream, io)
    catch
        # Generation died partway: the cache holds tokens no transcript records.
        # Drop the cache (not the conversation) so the next turn rebuilds from a
        # known-good state instead of appending to a phantom prefix.
        _invalidate!(s)
        pop!(s.history)
        rethrow()
    end
    t_gen = (time_ns() - t1) / 1e9
    stream && (println(io); flush(io))

    push!(s.history, "assistant" => text)
    # The generated bytes sit immediately after the assistant header, so the KV
    # cache now corresponds to exactly this many transcript bytes. The closing
    # <|im_end|> was sampled but deliberately not decoded — it arrives as part
    # of the next turn's delta, which keeps cache and transcript in step.
    append!(s.decoded, codeunits(text))

    return Response(text, length(toks), ngen, t_prompt, t_gen, stop, stream)
end

reset!() = reset!(session())
close!() = (s = _SESSION[]; s === nothing ? nothing : close!(s))

"""
    chatrepl([session])

Interactive loop. Commands: `/reset`, `/system <text>`, `/model <name>`,
`/stats`, `/exit`.
"""
function chatrepl(s::ChatSession = session())
    println("$(s.name) — /reset /system <text> /model <name> /stats /exit")
    while true
        print("\n"); printstyled("> "; bold = true); flush(stdout)
        # eof() before readline(), not after: on a tty it blocks until a byte is
        # available (which is the wait we want anyway) and on a pipe it is the
        # only honest end signal. Checking it after readline() would swallow the
        # last line of piped input and stall a tty on every turn.
        eof(stdin) && (println(); break)
        line = strip(readline(stdin))
        isempty(line) && continue

        if startswith(line, "/")
            cmd = split(line, ' '; limit = 2)
            verb = cmd[1]
            rest = length(cmd) > 1 ? strip(cmd[2]) : ""
            if verb in ("/exit", "/quit", "/q")
                break
            elseif verb == "/reset"
                reset!(s); println("(history cleared)")
            elseif verb == "/system"
                s.system = String(rest); reset!(s)
                println("(system prompt set, history cleared)")
            elseif verb == "/model"
                isempty(rest) && (println("usage: /model <name>"); continue)
                close!(s)
                s = start!(String(rest))
                println("(now: $(s.name))")
            elseif verb == "/stats"
                println("$(s.name)  $(s.n_past)/$(s.n_ctx) tokens  " *
                        "$(length(s.history)) messages  $(length(s.decoded)) transcript bytes")
            else
                println("unknown command: $verb")
            end
            continue
        end

        print("\n")
        try
            r = chat(s, line)
            printstyled(_stats_line(r), "\n"; color = :light_black)
        catch e
            e isa InterruptException && rethrow()
            printstyled("error: ", sprint(showerror, e), "\n"; color = :red)
        end
    end
    return s
end

"""
    run_demo(; model = DEFAULT_MODEL)

Two turns on a fresh session, printed. The second turn is the interesting one:
it only tokenizes the new tail of the transcript, so the prompt-token count
covers just that turn rather than the whole conversation.
"""
function run_demo(; model::AbstractString = DEFAULT_MODEL)
    s = ChatSession(model; n_ctx = 2048, system = "You are terse.")
    try
        println("── turn 1 ", "─"^50)
        r1 = chat(s, "In one sentence: what is a DWARF DIE?"; max_tokens = 96)
        printstyled(_stats_line(r1), "\n"; color = :light_black)

        println("\n── turn 2 (same session, incremental prompt) ", "─"^18)
        r2 = chat(s, "And what reads them?"; max_tokens = 96)
        printstyled(_stats_line(r2), "\n"; color = :light_black)

        println("\ncache: $(s.n_past)/$(s.n_ctx) tokens · " *
                "$(length(s.decoded)) transcript bytes · $(length(s.history)) messages")
        return s
    finally
        close!(s)
    end
end

end # module LlamaChat
