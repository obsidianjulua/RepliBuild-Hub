#!/usr/bin/env julia
# libjpegturbo — regenerate the checked-in cmake configure output.
#
# Three headers the build needs are configure_file'd and absent from git:
#
#   jconfig.h      public: JPEG_LIB_VERSION, BITS_IN_JSAMPLE default, C_/D_ARITH_CODING_SUPPORTED …
#   jconfigint.h   private: INLINE, THREAD_LOCAL, SIZEOF_SIZE_T, HAVE_BUILTIN_CTZL, VERSION/BUILD …
#   jversion.h     private: copyright/version strings
#
# This runs cmake's *configure* phase only and copies them into config/.
# Run after any version bump, then diff config/.
#
#   julia --project=/path/to/RepliBuild.jl packages/libjpegturbo/harvest.jl

using RepliBuild
using RepliBuild.SysConfigGen

const TAG     = "3.2.1"
const COMMIT  = "7b4993786d856cbccabfc0ed2f923ba000e326cc"
const URL     = "https://github.com/libjpeg-turbo/libjpeg-turbo.git"
const PKG_DIR = @__DIR__

checkout = mktempdir(; prefix="libjpegturbo_harvest_")
try
    run(`git clone --depth 1 --branch $TAG -q $URL $checkout`)
    head = strip(read(`git -C $checkout rev-parse HEAD`, String))
    head == COMMIT || error("libjpegturbo harvest: $TAG resolved to $head, expected $COMMIT")

    # Lean configure:
    #   WITH_SIMD=OFF   the x86-64 SIMD is NASM .asm with per-file flags — not a
    #                   C TU RepliBuild can compile. The C paths are the
    #                   reference implementation (same output, slower).
    #   ENABLE_STATIC=OFF, WITH_TOOLS/TESTS/FUZZ/JAVA=OFF  consumers only.
    #   WITH_TURBOJPEG=ON  the target we wrap: libturbojpeg.so, which compiles
    #                   every libjpeg TU (8/12/16-bit via src/wrapper/*-N.c) plus
    #                   the TurboJPEG API and its BMP/PPM/PNG image I/O.
    probe = cmake_probe(checkout;
                        name      = "libjpegturbo",
                        clone_rel = ".replibuild_cache/deps/libjpegturbo",
                        args      = ["-DENABLE_SHARED=ON",
                                     "-DENABLE_STATIC=OFF",
                                     "-DWITH_TURBOJPEG=ON",
                                     "-DWITH_SIMD=OFF",
                                     "-DWITH_TOOLS=OFF",
                                     "-DWITH_TESTS=OFF",
                                     "-DWITH_FUZZ=OFF",
                                     "-DWITH_JAVA=OFF"])
    display(probe)
    println("\n")

    t = main_target(probe; target="turbojpeg")
    t === nothing && error("libjpegturbo harvest: no turbojpeg target")
    uniform(t) || error("libjpegturbo harvest: turbojpeg is no longer one flag set")

    written = capture_config(probe, joinpath(PKG_DIR, "config"))
    println("harvested:")
    foreach(w -> println("  ", w), written)

    println("\n── proposal (for reference; replibuild.toml is hand-maintained) ──")
    println(toml_fragment(probe; target="turbojpeg", language="c",
                          shim_headers=["src/turbojpeg.h"]))
finally
    rm(checkout; recursive=true, force=true)
end
