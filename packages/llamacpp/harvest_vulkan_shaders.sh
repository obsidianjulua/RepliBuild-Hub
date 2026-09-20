#!/bin/bash
#
# Harvest ggml-vulkan's generated shader sources into packages/llamacpp/vulkan/.
#
# WHY THIS EXISTS
# ---------------
# ggml-vulkan does not ship compilable C++ for its shaders. It ships 136 GLSL
# .comp files plus a host tool, `vulkan-shaders-gen`, built as a CMake
# ExternalProject — a nested sub-build RepliBuild's resolver cannot run. The
# tool is invoked once for the declaration header and once per .comp file, and
# each invocation emits a .cpp holding that shader's SPIR-V as a byte array.
#
# So this is the generated-header case from the 2026-08-17 rule (run upstream's
# generator, check the output in) — just 137 files wide instead of one, and
# 206 MB, which is why `vulkan/` is gitignored rather than committed. The Hub
# already works this way: track the manifest, regenerate everything else.
#
# Run this BEFORE `RepliBuild.build()`. It needs the dependency clone, which
# build() creates, so on a cold package run build() once to populate
# .replibuild_cache/deps/llamacpp and then run this.
#
#   ./harvest_vulkan_shaders.sh
#
# Re-run it whenever the [dependencies.llamacpp] tag moves. The shader sources
# are pinned to upstream's .comp files, not to anything in this repo.

set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLONE="${PKG}/.replibuild_cache/deps/llamacpp"
SHADER_SRC="${CLONE}/ggml/src/ggml-vulkan/vulkan-shaders"
OUT="${PKG}/vulkan"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -d "$SHADER_SRC" ]; then
    echo "ERROR: dependency clone not found at:"
    echo "  $CLONE"
    echo
    echo "The clone is created by the build. Run it once first:"
    echo "  julia --project=/path/to/RepliBuild.jl -e 'using RepliBuild; RepliBuild.build(\"${PKG}/replibuild.toml\")'"
    echo "then re-run this script."
    exit 1
fi

for tool in glslc clang++; do
    command -v "$tool" >/dev/null || { echo "ERROR: $tool not found in PATH"; exit 1; }
done

# ── 1. Probe glslc for shader extension support ──────────────────────────────
#
# Upstream does this in CMake (ggml-vulkan/CMakeLists.txt) and forwards each
# result to the generator's sub-build as a -D cache var, which that CMakeLists
# turns 1:1 into a compile definition. The defines gate which shader VARIANTS
# get emitted, so a missing one silently drops a code path rather than failing.
#
# These test what GLSLC can compile, not what the DRIVER can run —
# ggml-vulkan.cpp picks among the compiled variants at runtime. Generating a
# variant this box's driver won't use is harmless; failing to generate one it
# would have used is a silent performance loss.
DEFS=()
probe() { # <feature-test-basename> <define-name>
    local err
    err="$(glslc -o - -fshader-stage=compute --target-env=vulkan1.3 \
            "${SHADER_SRC}/feature-tests/$1.comp" 2>&1 >/dev/null || true)"
    if echo "$err" | grep -q "extension not supported"; then
        echo "  OFF  $2"
    else
        echo "  ON   $2"
        DEFS+=("-D$2")
    fi
}

echo "== probing glslc extension support =="
probe coopmat               GGML_VULKAN_COOPMAT_GLSLC_SUPPORT
probe coopmat2              GGML_VULKAN_COOPMAT2_GLSLC_SUPPORT
probe coopmat2_decode_vector GGML_VULKAN_COOPMAT2_DECODE_VECTOR_GLSLC_SUPPORT
probe integer_dot           GGML_VULKAN_INTEGER_DOT_GLSLC_SUPPORT
probe bfloat16              GGML_VULKAN_BFLOAT16_GLSLC_SUPPORT
probe float_e2m1            GGML_VULKAN_FLOAT_E2M1_GLSLC_SUPPORT
probe float_e4m3            GGML_VULKAN_FLOAT_E4M3_GLSLC_SUPPORT

# ── 2. Build the generator ───────────────────────────────────────────────────
# Upstream builds this through an ExternalProject; the actual target is one
# translation unit against pthreads, so CMake buys nothing here.
echo "== building vulkan-shaders-gen =="
clang++ -O2 -std=c++17 "${DEFS[@]}" \
    "${SHADER_SRC}/vulkan-shaders-gen.cpp" -lpthread -o "${WORK}/vulkan-shaders-gen"

# ── 3. Generate ──────────────────────────────────────────────────────────────
# The .spv files are an INTERMEDIATE: the generator writes each compiled shader
# there and then embeds its bytes into the .cpp. Nothing reads them at build or
# run time, so they stay in $WORK and never reach the package — that is the
# difference between the 206 MB kept and the ~258 MB produced.
HPP="${OUT}/ggml-vulkan-shaders.hpp"
SPV="${WORK}/spv"
rm -rf "$OUT"; mkdir -p "$OUT" "$SPV"

echo "== generating declaration header =="
"${WORK}/vulkan-shaders-gen" --output-dir "$SPV" --target-hpp "$HPP"

echo "== generating shader sources ($(ls "${SHADER_SRC}"/*.comp | wc -l) shaders) =="
ls "${SHADER_SRC}"/*.comp | xargs -P "$(nproc)" -I{} bash -c '
    f="{}"
    "'"${WORK}/vulkan-shaders-gen"'" --glslc glslc --source "$f" \
        --output-dir "'"$SPV"'" --target-hpp "'"$HPP"'" \
        --target-cpp "'"$OUT"'/$(basename "$f").cpp"
'

echo
echo "== done =="
echo "  $(ls "$OUT"/*.comp.cpp | wc -l) shader sources + 1 header in $OUT ($(du -sh "$OUT" | cut -f1))"
echo "  Now run RepliBuild.build() — [dependencies.vkshaders] picks these up."
