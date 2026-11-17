#!/usr/bin/env bash
#
# Copy the bullet3, jolt and raylib wrappers from the Hub's packages into lib/, where
# ObjectSim loads them from. Re-run after rebuilding either package:
#
#   examples/ObjectSim/vendor.sh            # from anywhere
#   HUB=/path/to/RepliBuild-Hub vendor.sh   # take packages/ from another checkout
#
# Each wrapper gets its own directory: both ship a compilation_metadata.json,
# and the generated module resolves its .so sibling-first, so wrapper and
# library must travel together.
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
    # Ahead-of-time thunks ([compile] aot_thunks): the wrapper loads them from
    # the .so next to itself, so they travel with it. A stale copy from an
    # earlier AOT build would be loaded against a new library: drop it.
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
vendor bullet3 Bullet3.jl libbullet3.so
vendor jolt    Jolt.jl    libjolt.so
vendor raylib  Raylib.jl  libraylib.so
echo "Restart Julia (and let ObjectSim precompile again) to pick them up."
