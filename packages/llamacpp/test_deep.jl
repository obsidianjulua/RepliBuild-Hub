#!/usr/bin/env julia
# llamacpp Hub package — deep integration test
#
# Assumes the wrapper is already built (this only verifies; there is no test.jl
# yet because a cold rebuild here is a 200 MB clone + 195 TUs + a 252 MB DWARF
# dump ≈ 19 min, so the rebuild driver is deliberately not a routine step).
#
# What this pins, and why each one is here:
#   - every assertion is checked against NATIVE C values produced by
#     native_reference.c compiled against the SAME libllamacpp.so. That is an
#     oracle independent of the wrapper, which matters because the failure mode
#     this package exists to catch (a thunk overrunning the caller's buffer)
#     produces plausible-looking garbage rather than a crash.
#   - llama.cpp's whole entry surface is MEMORY-class struct BY VALUE, in both
#     directions: llama_model_params (72 B) and llama_context_params (160 B) are
#     returned by value and passed by value, and llama_batch is both. Those are
#     the crossings that were silently writing past the Ref.
#   - n_ctx is asserted specifically: it sits at offset 0 of the 160-byte
#     struct and read 3366863085 instead of 512 when the emitted MLIR type was
#     200 bytes wide.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/llamacpp/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Llamacpp.jl")

# nomic-embed-text v1.5 as managed by ollama — 274 MB, nomic-bert arch, an
# EMBEDDING model (no generation head). Override with ARGS[1].
const MODEL = length(ARGS) >= 1 ? ARGS[1] :
    "/var/lib/ollama/blobs/sha256-970aa74c0a90ef7482477cf803618e776e173c007bf957f635f1015bfcfef0e6"

# Native reference values — see native_reference.c
const NATIVE_GGML_VERSION = "0.18.1"
const NATIVE_N_VOCAB      = 30522
const NATIVE_N_EMBD       = 768
const NATIVE_N_TOKENS     = 4
const NATIVE_TOKENS       = Int32[101, 7592, 2088, 102]   # [CLS] hello world [SEP]
const NATIVE_EMBD_HEAD    = Float32[-0.15501, -0.03049, -3.90791, 0.19412]

@assert isfile(WRAPPER) "wrapper not built — run RepliBuild.build/wrap first"
include(WRAPPER)
using .Llamacpp
const L = Llamacpp

# The param structs are immutable byte blobs — they cross the ABI by value, so
# they cannot be mutable. `setproperty`/`setproperties` return a new value with
# the field written at its DWARF offset.

@testset "llamacpp Hub package" begin

@testset "Tier 3 — plain ccall surface" begin
    v = L.ggml_version()
    @test (v isa String ? v : unsafe_string(Ptr{UInt8}(v))) == NATIVE_GGML_VERSION
    @test L.llama_max_devices() == 16
    @test L.llama_supports_mmap() == true
end

@testset "MEMORY-class struct returned by value" begin
    mp = L.llama_model_default_params()
    @test sizeof(mp) == 72
    @test Int(mp.n_gpu_layers) == -1          # native default

    cp = L.llama_context_default_params()
    @test sizeof(cp) == 160
    @test Int(cp.n_ctx)   == 512              # read 3366863085 when the thunk overran
    @test Int(cp.n_batch) == 2048
end

@testset "field setters on by-value param structs" begin
    cp = L.llama_context_default_params()
    @test cp.embeddings == false

    # Immutable: the setter returns a new value, the original is unchanged.
    cp2 = L.setproperty(cp, :embeddings, true)
    @test cp2.embeddings == true
    @test cp.embeddings  == false

    # Bulk form, and untouched fields keep their library defaults.
    cp3 = L.setproperties(L.llama_context_default_params();
                          n_ctx = 4096, n_batch = 512, embeddings = true)
    @test Int(cp3.n_ctx)   == 4096
    @test Int(cp3.n_batch) == 512
    @test cp3.embeddings   == true
    @test Int(cp3.n_threads) == Int(cp.n_threads)
    @test sizeof(cp3) == 160

    mp = L.setproperties(L.llama_model_default_params(); n_gpu_layers = 0, vocab_only = true)
    @test Int(mp.n_gpu_layers) == 0
    @test mp.vocab_only == true
    @test sizeof(mp) == 72

    # `x.f = v` cannot work on an immutable blob; the error must say what does.
    err = try (x = L.llama_context_default_params(); x.embeddings = true; "") catch e
        sprint(showerror, e) end
    @test occursin("setproperties", err)
    # ...and `error` itself must not be the library's `codecvt_base::result.error`.
    @test_throws ErrorException L.setproperty(cp, :not_a_field, 1)
end

@testset "MEMORY-class struct passed by value — full inference" begin
    L.llama_backend_init()

    mp = L.setproperties(L.llama_model_default_params(); n_gpu_layers = 0)
    model = L.llama_model_load_from_file(MODEL, mp)
    @test model != C_NULL

    vocab = L.llama_model_get_vocab(model)
    @test Int(L.llama_vocab_n_tokens(vocab)) == NATIVE_N_VOCAB
    @test Int(L.llama_model_n_embd(model))   == NATIVE_N_EMBD

    cp = L.setproperties(L.llama_context_default_params();
                         n_ctx = 512, n_batch = 512, n_ubatch = 512, embeddings = true)
    ctx = L.llama_init_from_model(model, cp)
    @test ctx != C_NULL

    prompt = "hello world"
    toks = Vector{Int32}(undef, 512)
    ntok = L.llama_tokenize(vocab, prompt, Int32(length(prompt)),
                            toks, Int32(length(toks)), true, false)
    @test ntok == NATIVE_N_TOKENS
    resize!(toks, ntok)
    @test toks == NATIVE_TOKENS

    # llama_batch: returned by value, then passed by value.
    batch = L.llama_batch_get_one(toks, Int32(ntok))
    @test L.llama_decode(ctx, batch) == 0

    p = L.llama_get_embeddings_seq(ctx, Int32(0))
    p == C_NULL && (p = L.llama_get_embeddings(ctx))
    @test p != C_NULL
    v = unsafe_wrap(Array, Ptr{Float32}(p), NATIVE_N_EMBD)
    # Bit-for-bit agreement with the native C run is the real assertion here.
    for i in 1:length(NATIVE_EMBD_HEAD)
        @test isapprox(v[i], NATIVE_EMBD_HEAD[i]; atol=1e-5)
    end

    L.llama_free(ctx)
    L.llama_model_free(model)
    L.llama_backend_free()
end

end
