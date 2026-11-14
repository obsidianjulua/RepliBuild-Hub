#!/usr/bin/env bash
# Serve a model from LlamaChat's store over llama.cpp's OpenAI-compatible HTTP
# API, for tools that want an endpoint rather than a library (opencode).
#
#   llama-serve.sh                 # qwen3-coder on http://127.0.0.1:8090/v1
#   llama-serve.sh qwen3.8:27b     # another model from the store
#   PORT=8091 CTX=16384 llama-serve.sh
#   FA=off BATCH=256 CTX=20480 llama-serve.sh   # faster deep in a context, smaller window
#
# LlamaChat itself has no server: it runs models in-process. This only finds
# the model's GGUF in the store (a blob named by its sha256, in ollama's
# layout) and hands the path to `llama-server`, which must be on PATH or named
# in $LLAMA_SERVER. Port 8090 by default: 8080 is `laya serve`'s.
#
# --jinja runs the model's own chat template, which is what gives the client
# tool calls. One slot (-np 1), so the whole context is one conversation's.
#
# FA=off is the trade LlamaChat's planner measures (README, "The sweet spot"):
# on this card flash attention is the slow path once a few thousand tokens are
# in context, and opencode starts every session about 8.5k tokens deep.
# qwen3-coder at 8k: 28.5 tok/s with it on, 42.9 with it off. Off costs VRAM
# that grows with batch × context, so it needs BATCH=256 and a window near 20k.
#
# CTX defaults to 24576 for the B60: qwen3-coder's 17.3 GiB of weights plus
# 96 KiB of KV cache a token is 20.0 GiB there, inside what the card has free
# with a desktop running. llama-server does not fit a load to the card: ask for
# more than fits and it aborts. Unload the model in the LlamaChat window first;
# both cannot hold it at once.
set -euo pipefail

name="${1:-qwen3-coder}"
port="${PORT:-8090}"
ctx="${CTX:-24576}"
fa="${FA:-on}"
batch="${BATCH:-512}"
store="${LLAMACHAT_MODELS:-${XDG_DATA_HOME:-$HOME/.local/share}/llamachat/models}"
server="${LLAMA_SERVER:-$(command -v llama-server || true)}"

[[ -n "$server" && -x "$server" ]] || {
    echo "llama-serve: no llama-server on PATH (or set \$LLAMA_SERVER to it)" >&2; exit 1; }

spec="${name%%:*}"; tag="latest"; [[ "$name" == *:* ]] && tag="${name#*:}"
[[ "$spec" == */* ]] || spec="library/$spec"
manifest="$store/manifests/registry.ollama.ai/$spec/$tag"
[[ -f "$manifest" ]] || { echo "llama-serve: no model \"$name\" in $store" >&2; exit 1; }

digest=$(jq -r '.layers[] | select(.mediaType == "application/vnd.ollama.image.model") | .digest' "$manifest" | head -1)
blob="$store/blobs/${digest/:/-}"
[[ -f "$blob" ]] || { echo "llama-serve: $name's weights are not in $store/blobs ($digest)" >&2; exit 1; }

echo "llama-serve: $name  →  http://127.0.0.1:$port/v1   (ctx $ctx, $blob)" >&2
exec "$server" -m "$blob" --alias "$name" \
    --host 127.0.0.1 --port "$port" \
    -ngl 99 -c "$ctx" -b "$batch" -ub "$batch" -fa "$fa" -np 1 \
    --jinja
