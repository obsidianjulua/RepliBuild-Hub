#!/usr/bin/env julia
#
# Prompt in, text out — llama.cpp text generation through the RepliBuild wrapper.
#
#   julia --project=/path/to/RepliBuild.jl packages/llamacpp/generate.jl \
#         "def fibonacci(n):" [n_predict] [model.gguf]
#
# Defaults to qwen2.5-coder 1.5b-base as managed by ollama (986 MB) — the
# smallest generative model on this box. It is a BASE model, not instruct: it
# CONTINUES your text, it does not answer it. Give it a prefix to complete
# ("def fibonacci(n):"), not a question.
#
# The difference from inference.jl is only the sampler chain and the token
# loop. Everything before that is identical.
#
# Every signature below was found without opening llama.h, using
# RepliBuildTooling's api surface — the wrapper is 5,364 definitions and
# nothing in it marks which ~1,200 are the API:
#
#   julia --project=/path/to/RepliBuildTooling.jl -e '
#       using RepliBuildTooling
#       s = api_surface("packages/llamacpp")
#       foreach(println, api(s, "sampler_init_"))
#       println(byvalue_args(only(api(s, "llama_decode")), s))
#       foreach(println, api_struct(s, "llama_batch"))'

using RepliBuild

const PKG    = @__DIR__
const PROMPT = length(ARGS) >= 1 ? ARGS[1] : "def fibonacci(n):"
const NPRED  = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 64
const MODEL  = length(ARGS) >= 3 ? ARGS[3] :
    "/var/lib/ollama/blobs/sha256-6a77366395772462c84f0c4d226ac404674327cbe78c01e4391cc7e0c698851e"

include(joinpath(PKG, "julia", "Llamacpp.jl"))
using .Llamacpp
const L = Llamacpp

# Quiet llama.cpp's logging so the completion is the only thing on the stream.
# Passing C_NULL here does NOT do it — llama.cpp reads a null callback as
# "restore the default", which is the stderr printer. It needs a real no-op
# function pointer, i.e. a Julia function handed to C as a callback:
#   void (*)(enum ggml_log_level, const char *, void *)
# Both libraries keep their own callback, so both have to be set.
_silence(level::Cint, text::Ptr{UInt8}, ud::Ptr{Cvoid})::Cvoid = nothing
const _SILENCE = @cfunction(_silence, Cvoid, (Cint, Ptr{UInt8}, Ptr{Cvoid}))
L.llama_log_set(_SILENCE, C_NULL)
L.ggml_log_set(_SILENCE, C_NULL)

L.llama_backend_init()

# ── Model + context (identical to inference.jl, minus embeddings) ────────────
mp    = L.setproperties(L.llama_model_default_params(); n_gpu_layers = 0)
model = L.llama_model_load_from_file(MODEL, mp)
model == C_NULL && Base.error("model load failed: $MODEL")
vocab = L.llama_model_get_vocab(model)

cp  = L.setproperties(L.llama_context_default_params();
                      n_ctx = 2048, n_batch = 2048, n_ubatch = 512)
ctx = L.llama_init_from_model(model, cp)
ctx == C_NULL && Base.error("context creation failed")

# ── Sampler chain ────────────────────────────────────────────────────────────
# llama_sampler_chain_params is another by-value struct. Samplers are applied
# in the order added; the LAST one must select a token. Greedy is deterministic,
# which is what makes this reproducible — swap in top_k/top_p/temp + dist for
# variety (all four signatures are in explore.jl under api("sampler_init_")).
chain = L.llama_sampler_chain_init(L.llama_sampler_chain_default_params())
L.llama_sampler_chain_add(chain, L.llama_sampler_init_greedy())

# ── Tokenize the prompt ──────────────────────────────────────────────────────
toks = Vector{Int32}(undef, 4096)
ntok = L.llama_tokenize(vocab, PROMPT, Int32(sizeof(PROMPT)),
                        toks, Int32(length(toks)),
                        true,    # add_special — BOS
                        false)   # parse_special
ntok < 0 && Base.error("prompt needs a buffer of at least $(-ntok) tokens")
resize!(toks, ntok)

print(PROMPT)
flush(stdout)

# ── Prefill: decode the whole prompt in one batch ────────────────────────────
# llama_batch_get_one stores a POINTER to `toks` inside the returned struct, so
# the array has to outlive the decode — hence GC.@preserve around both.
GC.@preserve toks begin
    rc = L.llama_decode(ctx, L.llama_batch_get_one(toks, Int32(ntok)))
    rc == 0 || Base.error("prefill llama_decode returned $rc")
end

# ── Generate ─────────────────────────────────────────────────────────────────
one = Int32[0]                       # reused 1-token batch buffer
buf = Vector{UInt8}(undef, 256)      # llama_token_to_piece writes UTF-8 here
n_generated = 0

for _ in 1:NPRED
    # idx = -1 → sample from the logits of the last decoded position.
    tok = L.llama_sampler_sample(chain, ctx, Int32(-1))
    L.llama_vocab_is_eog(vocab, tok) && break

    # Detokenize this one token. Returns the byte count, or NEGATIVE the needed
    # size if `buf` is too small — a multi-byte piece can exceed a small buffer.
    n = L.llama_token_to_piece(vocab, tok, buf, Int32(length(buf)),
                               Int32(0),   # lstrip
                               true)       # special
    if n < 0
        resize!(buf, -n)
        n = L.llama_token_to_piece(vocab, tok, buf, Int32(length(buf)), Int32(0), true)
    end
    print(String(buf[1:n]))
    flush(stdout)

    # Tell the chain what was chosen — required by any stateful sampler
    # (penalties, mirostat, dist); a no-op for greedy, but wrong to omit.
    L.llama_sampler_accept(chain, tok)

    one[1] = tok
    GC.@preserve one begin
        L.llama_decode(ctx, L.llama_batch_get_one(one, Int32(1))) == 0 || break
    end
    global n_generated += 1
end

println("\n\n[$n_generated tokens]")

# ── Teardown ─────────────────────────────────────────────────────────────────
L.llama_sampler_free(chain)
L.llama_free(ctx)
L.llama_model_free(model)
L.llama_backend_free()
