#!/usr/bin/env julia
#
# llama.cpp inference through the RepliBuild wrapper — the minimum set of calls
# that gets you from a .gguf on disk to numbers out.
#
#   julia --project=/path/to/RepliBuild.jl packages/llamacpp/inference.jl [model.gguf]
#
# Defaults to the ollama-managed nomic-embed-text blob (274 MB, BERT arch), which
# is an EMBEDDING model — it has no generation head, so this runs the embedding
# path. The generation path is the same up to llama_decode; see the note at the
# bottom for the extra calls.
#
# Verified against a plain-C program compiled against the same libllamacpp.so:
# same n_vocab, same n_embd, same token count, same embedding values.

using RepliBuild

const PKG   = @__DIR__
const MODEL = length(ARGS) >= 1 ? ARGS[1] :
    "/var/lib/ollama/blobs/sha256-970aa74c0a90ef7482477cf803618e776e173c007bf957f635f1015bfcfef0e6"

include(joinpath(PKG, "julia", "Llamacpp.jl"))
using .Llamacpp
const L = Llamacpp

# ── Setting fields on a by-value param struct ────────────────────────────────
#
# These param structs are immutable byte blobs — they cross the ABI by value,
# so they cannot be mutable. `setproperty`/`setproperties` return a NEW value
# with the field written at its DWARF offset; the original is untouched.
# `params.embeddings = true` is not skippable here: an embedding model returns
# nothing without it.

# ── 1. Backend ───────────────────────────────────────────────────────────────
L.llama_backend_init()

# ── 2. Model ─────────────────────────────────────────────────────────────────
# llama_model_params is 72 bytes, MEMORY-class, RETURNED by value.
mp = L.setproperties(L.llama_model_default_params(); n_gpu_layers = 0)   # CPU only
# ...and passed BY VALUE into the loader.
model = L.llama_model_load_from_file(MODEL, mp)
model == C_NULL && error("model load failed: $MODEL")

vocab   = L.llama_model_get_vocab(model)
n_vocab = L.llama_vocab_n_tokens(vocab)
n_embd  = L.llama_model_n_embd(model)
println("model    : n_vocab=$n_vocab  n_embd=$n_embd")

# ── 3. Context ───────────────────────────────────────────────────────────────
# llama_context_params is 160 bytes, also MEMORY-class by value both ways.
cp = L.setproperties(L.llama_context_default_params();
                     n_ctx = 512, n_batch = 512, n_ubatch = 512,
                     embeddings = true)                # required for embeddings
ctx = L.llama_init_from_model(model, cp)
ctx == C_NULL && error("context creation failed")

# ── 4. Tokenize ──────────────────────────────────────────────────────────────
# Out-params are plain Julia arrays; the wrapper takes them as Any.
prompt = "hello world"
toks   = Vector{Int32}(undef, 512)
ntok   = L.llama_tokenize(vocab, prompt, Int32(length(prompt)),
                          toks, Int32(length(toks)),
                          true,    # add_special (BOS/CLS)
                          false)   # parse_special
ntok < 0 && error("tokenize needs a buffer of at least $(-ntok)")
resize!(toks, ntok)
println("tokenize : \"$prompt\" -> $ntok tokens  $(toks)")

# ── 5. Decode ────────────────────────────────────────────────────────────────
# llama_batch is returned by value AND passed by value — the crossing that used
# to overrun the caller's buffer.
batch = L.llama_batch_get_one(toks, Int32(ntok))
rc = L.llama_decode(ctx, batch)
rc != 0 && error("llama_decode returned $rc")
println("decode   : ok")

# ── 6. Read the result ───────────────────────────────────────────────────────
emb = L.llama_get_embeddings_seq(ctx, Int32(0))
if emb == C_NULL
    emb = L.llama_get_embeddings(ctx)
end
emb == C_NULL && error("no embeddings — was cp.embeddings set?")
v = unsafe_wrap(Array, Ptr{Float32}(emb), n_embd)
println("embed    : [", join((round(v[i], digits=5) for i in 1:4), ", "), " ...]  norm=",
        round(sqrt(sum(abs2, v)), digits=4))

# ── 7. Teardown ──────────────────────────────────────────────────────────────
L.llama_free(ctx)
L.llama_model_free(model)
L.llama_backend_free()
println("done")

# ── Text generation instead of embeddings ────────────────────────────────────
# Steps 1-5 are identical (leave cp.embeddings false). Then loop:
#
#   scp   = L.llama_sampler_chain_default_params()   # by-value struct again
#   chain = L.llama_sampler_chain_init(scp)
#   L.llama_sampler_chain_add(chain, L.llama_sampler_init_greedy())
#
#   cur = copy(toks)
#   for _ in 1:max_new
#       tok = L.llama_sampler_sample(chain, ctx, Int32(-1))
#       L.llama_vocab_is_eog(vocab, tok) && break
#       buf = Vector{UInt8}(undef, 256)
#       n = L.llama_token_to_piece(vocab, tok, buf, Int32(length(buf)), Int32(0), true)
#       print(String(buf[1:n]))
#       L.llama_decode(ctx, L.llama_batch_get_one([tok], Int32(1))) == 0 || break
#   end
#   L.llama_sampler_free(chain)
#
# Raw logits instead of a sampler: L.llama_get_logits_ith(ctx, Int32(-1))
# then unsafe_wrap(Array, Ptr{Float32}(p), n_vocab).
