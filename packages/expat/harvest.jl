#!/usr/bin/env julia
# expat — regenerate the checked-in cmake configure output.
#
# expat cannot be compiled from a bare checkout: every TU starts with
# `#include <expat_config.h>`, which cmake generates from expat_config.h.cmake
# (byte order, HAVE_* probes, XML_DTD / XML_NS / XML_GE feature switches,
# XML_CONTEXT_BYTES). This runs cmake's configure phase only and copies the
# result into config/.
#
# Run after any version bump, then diff config/: a flipped XML_DTD or a changed
# XML_CONTEXT_BYTES is real news, not noise.
#
#   julia --project=<RepliBuild.jl> packages/expat/harvest.jl

using RepliBuild
using RepliBuild.SysConfigGen

const TAG     = "R_2_7_5"
const COMMIT  = "f31adfd584b7f6c50bbf4d22eb928538ffc9145a"
const URL     = "https://github.com/libexpat/libexpat.git"
const PKG_DIR = @__DIR__

checkout = mktempdir(; prefix="expat_harvest_")
try
    run(`git -c advice.detachedHead=false clone --depth 1 --branch $TAG -q $URL $checkout`)
    head = strip(read(`git -C $checkout rev-parse HEAD`, String))
    head == COMMIT || error("expat harvest: $TAG resolved to $head, expected $COMMIT")

    # Lean: no tools (xmlwf), examples, tests, docs, fuzzers or pkg-config.
    # libbsd off so arc4random_buf comes from glibc, not a second library.
    probe = cmake_probe(joinpath(checkout, "expat");
                        name      = "expat",
                        clone_rel = ".replibuild_cache/deps/expat/expat",
                        args      = ["-DEXPAT_BUILD_TOOLS=OFF",
                                     "-DEXPAT_BUILD_EXAMPLES=OFF",
                                     "-DEXPAT_BUILD_TESTS=OFF",
                                     "-DEXPAT_BUILD_DOCS=OFF",
                                     "-DEXPAT_BUILD_FUZZERS=OFF",
                                     "-DEXPAT_BUILD_PKGCONFIG=OFF",
                                     "-DEXPAT_WITH_LIBBSD=OFF",
                                     "-DEXPAT_SHARED_LIBS=ON"])
    display(probe)
    println("\n")

    uniform(probe) || error("expat harvest: chosen target is no longer uniform — " *
                            "the manifest's single flag set cannot reproduce it")

    written = capture_config(probe, joinpath(PKG_DIR, "config"))
    println("harvested:")
    foreach(w -> println("  ", w), written)

    println("\n── proposal (for reference; replibuild.toml is hand-maintained) ──")
    println(toml_fragment(probe; language="c", shim_headers=["expat.h"]))
finally
    rm(checkout; recursive=true, force=true)
end
