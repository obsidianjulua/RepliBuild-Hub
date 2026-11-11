#!/usr/bin/env bash
#
# Copy the Dear ImGui, GLFW and libvterm wrappers from the Hub's packages into lib/gui/,
# where LlamaChat.gui() loads them from. Re-run after rebuilding either package:
#
#   examples/LlamaChat/vendor_gui.sh            # from anywhere
#   HUB=/path/to/RepliBuild-Hub vendor_gui.sh   # take packages/ from another checkout
#
# lib/gui/ is its own directory because lib/ already holds llama.cpp's
# compilation_metadata.json and thunk_manifest.json, which imgui's would clobber.
#
# Both wrappers MUST land side by side. Glfw.jl dlopens the libglfw.so next to
# itself, and libimgui.so's RUNPATH starts with $ORIGIN, so imgui's own
# DT_NEEDED libglfw.so resolves to the same file. GLFW state is process-global:
# with two copies mapped, glfwInit on one does not initialise the other.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hub="${HUB:-$(cd "$here/../.." && pwd)}"
src_imgui="$hub/packages/imgui/julia"
src_glfw="$hub/packages/glfw/julia"
src_vterm="$hub/packages/libvterm/julia"
dst="$here/lib/gui"

for f in "$src_imgui/Imgui.jl" "$src_imgui/libimgui.so" "$src_imgui/libimgui_thunks.so" \
         "$src_glfw/Glfw.jl" "$src_glfw/libglfw.so" \
         "$src_vterm/Libvterm.jl" "$src_vterm/liblibvterm.so"; do
    [[ -f "$f" ]] || { echo "missing $f — build and wrap the package first" >&2; exit 1; }
done

mkdir -p "$dst"
cp -f "$src_imgui/Imgui.jl" "$src_imgui/libimgui.so" "$src_imgui/libimgui_thunks.so" "$dst/"
cp -f "$src_glfw/Glfw.jl" "$src_glfw/libglfw.so" "$dst/"
cp -f "$src_vterm/Libvterm.jl" "$src_vterm/liblibvterm.so" "$dst/"

# The check that matters: imgui's libglfw must be the vendored one.
resolved="$(ldd "$dst/libimgui.so" | awk '/libglfw/ {print $3}')"
if [[ -z "$resolved" || "$(realpath "$resolved")" != "$(realpath "$dst/libglfw.so")" ]]; then
    echo "libimgui.so resolves libglfw to '$resolved', not $dst/libglfw.so" >&2
    exit 1
fi

gen() { sed -n 's/^const BUILD_GENERATOR = "\(.*\)"/\1/p' "$1"; }
echo "vendored into $dst"
echo "  Imgui.jl  RepliBuild $(gen "$dst/Imgui.jl")"
echo "  Glfw.jl   RepliBuild $(gen "$dst/Glfw.jl")"
echo "  Libvterm.jl RepliBuild $(gen "$dst/Libvterm.jl")"
echo "  libimgui.so -> $resolved"
echo "LlamaChat.gui() loads these on its first call; restart Julia to pick them up."
