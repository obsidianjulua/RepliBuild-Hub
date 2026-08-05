// Native oracle for the llamacpp Hub package.
//
// Plain C against the same headers, linked against the SAME libllamacpp.so the
// Julia wrapper loads. Two jobs:
//
//   1. Separates build failures from wrapper failures. If this passes and
//      test_deep.jl does not, the .so is fine and the generator/dialect is at
//      fault — which is exactly how the by-value overrun was localised.
//   2. Produces the reference values test_deep.jl asserts against. The failure
//      mode here (a thunk writing past the caller's buffer) yields plausible
//      garbage, not a crash, so an oracle outside the wrapper is the only way
//      to tell "512" from "3366863085" is wrong.
//
// Build & run (from the Hub root):
//   D=packages/llamacpp/.replibuild_cache/deps/llamacpp
//   clang packages/llamacpp/native_reference.c \
//       -I$D/include -I$D/ggml/include \
//       -Lpackages/llamacpp/julia -lllamacpp -lstdc++ \
//       -Wl,-rpath,$PWD/packages/llamacpp/julia -o /tmp/native_reference
//   /tmp/native_reference
//
// Expected: ggml 0.18.1 | n_vocab 30522 | n_embd 768 | 4 tokens
//           embeddings[0..3] = -0.15501 -0.03049 -3.90791 0.19412
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include "llama.h"
#include "ggml.h"

static const char * MODEL =
    "/var/lib/ollama/blobs/sha256-970aa74c0a90ef7482477cf803618e776e173c007bf957f635f1015bfcfef0e6";

static void quiet_log(enum ggml_log_level level, const char * text, void * ud) {
    (void) level; (void) text; (void) ud;   // keep the output readable
}

int main(void) {
    printf("ggml_version           = %s\n", ggml_version());
    printf("llama_max_devices      = %zu\n", llama_max_devices());
    printf("llama_supports_mmap    = %d\n", llama_supports_mmap());

    llama_log_set(quiet_log, NULL);
    llama_backend_init();

    // MEMORY-class struct returned by value
    struct llama_model_params mp = llama_model_default_params();
    printf("model_params.n_gpu_layers = %d  (sizeof=%zu)\n",
           mp.n_gpu_layers, sizeof(mp));
    mp.n_gpu_layers = 0;
    mp.use_extra_bufts = false;

    // MEMORY-class struct passed by value
    struct llama_model * model = llama_model_load_from_file(MODEL, mp);
    if (!model) { printf("FAIL: model load returned NULL\n"); return 1; }
    printf("model loaded           = %p\n", (void *) model);

    const struct llama_vocab * vocab = llama_model_get_vocab(model);
    printf("n_vocab                = %d\n", llama_vocab_n_tokens(vocab));
    printf("n_embd                 = %d\n", llama_model_n_embd(model));

    struct llama_context_params cp = llama_context_default_params();
    cp.n_ctx      = 128;
    cp.n_batch    = 128;
    cp.embeddings = true;
    printf("context_params sizeof  = %zu\n", sizeof(cp));

    struct llama_context * ctx = llama_init_from_model(model, cp);
    if (!ctx) { printf("FAIL: context init returned NULL\n"); return 1; }
    printf("context created        = %p\n", (void *) ctx);

    const char * prompt = "hello world";
    llama_token toks[64];
    int n = llama_tokenize(vocab, prompt, (int) strlen(prompt), toks, 64, true, false);
    printf("tokenized \"%s\" -> %d tokens\n", prompt, n);
    if (n <= 0) { printf("FAIL: tokenize\n"); return 1; }

    // llama_batch is returned AND passed by value
    struct llama_batch batch = llama_batch_get_one(toks, n);
    int rc = llama_decode(ctx, batch);
    printf("llama_decode           = %d\n", rc);
    if (rc != 0) { printf("FAIL: decode\n"); return 1; }

    const float * emb = llama_get_embeddings_seq(ctx, 0);
    if (!emb) emb = llama_get_embeddings(ctx);
    if (emb) {
        printf("embeddings[0..3]       = %.5f %.5f %.5f %.5f\n",
               emb[0], emb[1], emb[2], emb[3]);
    } else {
        printf("FAIL: no embeddings\n"); return 1;
    }

    llama_free(ctx);
    llama_model_free(model);
    llama_backend_free();
    printf("NATIVE SMOKE OK\n");
    return 0;
}
