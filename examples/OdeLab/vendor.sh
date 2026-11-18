#!/usr/bin/env bash
#
# Copy the sundials, raylib and imgui wrappers from the Hub's packages into lib/,
# where OdeLab loads them from. Re-run after rebuilding any of them:
#
#   examples/OdeLab/vendor.sh            # from anywhere
#   HUB=/path/to/RepliBuild-Hub vendor.sh   # take packages/ from another checkout
#
# Each wrapper gets its own directory: all three ship a compilation_metadata.json,
# and the generated module resolves its .so sibling-first, so wrapper and library
# travel together.
#
# imgui also gets the GLFW library next to it. libimgui.so carries a DT_NEEDED on
# libglfw.so (its GLFW platform backend) with $ORIGIN first in its RUNPATH, so a
# copy beside it keeps lib/ self-contained. OdeLab never calls into that GLFW:
# the window is raylib's, and raylib compiles its own GLFW in with hidden
# visibility, so the two copies cannot see each other.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hub="${HUB:-$(cd "$here/../.." && pwd)}"

vendor() {   # vendor <package> <Wrapper.jl> <lib.so>
    local src="$hub/packages/$1/julia" dst="$here/lib/$1"
    for f in "$src/$2" "$src/$3" "$src/compilation_metadata.json"; do
        [[ -f "$f" ]] || { echo "missing $f — build and wrap packages/$1 first" >&2; exit 1; }
    done
    mkdir -p "$dst"
    cp -f "$src/$2" "$src/$3" "$src/compilation_metadata.json" "$dst/"
    if [[ -f "$src/thunk_manifest.json" ]]; then cp -f "$src/thunk_manifest.json" "$dst/"; fi
    # Ahead-of-time thunks travel with the wrapper; a stale copy from an earlier
    # AOT build would be loaded against a new library, so drop it if upstream has none.
    local thunks="${3%.so}_thunks.so"
    if [[ -f "$src/$thunks" ]]; then
        cp -f "$src/$thunks" "$dst/"
        echo "  $thunks (ahead-of-time thunks)"
    else
        rm -f "$dst/$thunks"
    fi
    local gen
    gen="$(sed -n 's/^const BUILD_GENERATOR = "\(.*\)"/\1/p' "$dst/$2")"
    echo "  $2  RepliBuild $gen  -> lib/$1/"
}

echo "vendoring into $here/lib"
vendor sundials Sundials.jl libsundials.so
vendor raylib   Raylib.jl   libraylib.so
vendor imgui    Imgui.jl    libimgui.so
glfw="$hub/packages/glfw/julia/libglfw.so"
[[ -f "$glfw" ]] || { echo "missing $glfw — build packages/glfw first (libimgui.so needs it)" >&2; exit 1; }
cp -f "$glfw" "$here/lib/imgui/"
echo "  libglfw.so  -> lib/imgui/ (libimgui.so's DT_NEEDED)"
echo "Restart Julia (and let OdeLab precompile again) to pick them up."
