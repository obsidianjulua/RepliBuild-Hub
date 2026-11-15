#!/usr/bin/env bash
#
# Copy the QuickJS wrapper from the Hub's packages into lib/js/, where
# LlamaChat loads it the first time a chat template is run (src/js.jl).
# Re-run after rebuilding the package:
#
#   examples/LlamaChat/vendor_js.sh            # from anywhere
#   HUB=/path/to/RepliBuild-Hub vendor_js.sh   # take packages/ from another checkout
#
# The Jinja library is not vendored from anywhere: js/jinja-0.5.13.cjs is in
# this repository (MIT, js/jinja-LICENSE), as published in the npm package
# @huggingface/jinja 0.5.13, file dist/index.cjs.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hub="${HUB:-$(cd "$here/../.." && pwd)}"
src="$hub/packages/quickjs/julia"
dst="$here/lib/js"

for f in "$src/Quickjs.jl" "$src/libquickjs.so"; do
    [[ -f "$f" ]] || { echo "missing $f — build and wrap the Hub's quickjs package first" >&2; exit 1; }
done

mkdir -p "$dst"
cp -f "$src/Quickjs.jl" "$src/libquickjs.so" "$dst/"

want="$(sed -n 's/^const LIBRARY_SHA = "\(.*\)"/\1/p' "$dst/Quickjs.jl")"
have="$(sha256sum "$dst/libquickjs.so" | cut -d' ' -f1)"
[[ "$want" == "$have" ]] || { echo "lib/js/libquickjs.so is not the build Quickjs.jl was generated from" >&2; exit 1; }

jinja="$here/js/jinja-0.5.13.cjs"
[[ "$(sha256sum "$jinja" | cut -d' ' -f1)" == "e491328e32c9bb0a1f13f2d20ad6d07c91604814e47dde9b818f9ab44bab8dcf" ]] ||
    { echo "$jinja is not the published @huggingface/jinja 0.5.13 dist/index.cjs" >&2; exit 1; }

echo "vendored into $dst"
echo "  Quickjs.jl      RepliBuild $(sed -n 's/^const BUILD_GENERATOR = "\(.*\)"/\1/p' "$dst/Quickjs.jl")"
echo "  libquickjs.so   sha256 ${have:0:16}…"
echo "  jinja-0.5.13.cjs is the published file"
