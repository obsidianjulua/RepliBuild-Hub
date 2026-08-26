#!/usr/bin/env julia
# pcre2 — regenerate the checked-in cmake configure output.
#
# pcre2 cannot be compiled from a bare checkout. Three of the files the build
# needs do not exist in git:
#
#   config.h             47 feature-probe results, 31 set (HAVE_*, SUPPORT_*, PCRE2_*)
#   pcre2.h              the PUBLIC header, configure_file'd from src/pcre2.h.in
#   pcre2_chartables.c   configure_file(COPYONLY) of src/pcre2_chartables.c.dist
#
# RepliBuild compiles all-sources-minus-excludes under one flag set and never
# runs a configure step, so all three have to already be on disk. This script
# produces them by running cmake's *configure* phase only — no build, no
# compiler on a real source file — and copies them into config/.
#
# Run after any version bump, then diff config/: a changed SIZEOF_* or a
# vanished SUPPORT_* is real news, not noise.
#
#   julia --project=@v#.#.# \
#         packages/pcre2/harvest.jl

using RepliBuild
using RepliBuild.SysConfigGen   # moved in-house 2026-08-26 (was RepliBuildTooling)

const TAG     = "pcre2-10.45"
const COMMIT  = "2dce7761b1831fd3f82a9c2bd5476259d945da4d"
const URL     = "https://github.com/PCRE2Project/pcre2.git"
const PKG_DIR = @__DIR__

checkout = mktempdir(; prefix="pcre2_harvest_")
try
    run(`git clone --depth 1 --branch $TAG -q $URL $checkout`)
    head = strip(read(`git -C $checkout rev-parse HEAD`, String))
    head == COMMIT || error("pcre2 harvest: $TAG resolved to $head, expected $COMMIT")

    # The -D set is what keeps the build lean. JIT is off because its sources are
    # #included into pcre2_jit_compile.c rather than compiled standalone, and
    # because a JIT inside a wrapped library is a second code generator competing
    # with RepliBuild's own. The 16- and 32-bit code-unit widths are off so the
    # tree resolves to ONE target over ONE flag set; PCRE2_CODE_UNIT_WIDTH=8 is
    # the standard build and the one pcre2.h's macro aliases are generated for.
    probe = cmake_probe(checkout;
                        name      = "pcre2",
                        clone_rel = ".replibuild_cache/deps/pcre2",
                        args      = ["-DPCRE2_BUILD_TESTS=OFF",
                                     "-DPCRE2_BUILD_PCRE2GREP=OFF",
                                     "-DPCRE2_BUILD_PCRE2_8=ON",
                                     "-DPCRE2_BUILD_PCRE2_16=OFF",
                                     "-DPCRE2_BUILD_PCRE2_32=OFF",
                                     "-DPCRE2_SUPPORT_JIT=OFF"])
    display(probe)
    println("\n")

    uniform(probe) || error("pcre2 harvest: chosen target is no longer uniform — " *
                            "the manifest's single flag set cannot reproduce it")

    written = capture_config(probe, joinpath(PKG_DIR, "config"))
    println("harvested:")
    foreach(w -> println("  ", w), written)

    println("\n── proposal (for reference; replibuild.toml is hand-maintained) ──")
    println(toml_fragment(probe; language="c", shim_headers=["pcre2.h"]))
finally
    rm(checkout; recursive=true, force=true)
end
