#!/usr/bin/env julia
# sundials — regenerate the checked-in cmake configure output.
#
# SUNDIALS cannot be compiled from a bare checkout. Two headers the build needs
# do not exist in git:
#
#   sundials/sundials_config.h   feature probes + the precision/index pins
#   sundials/sundials_export.h   the visibility macros (generate_export_header)
#
# RepliBuild compiles all-sources-minus-excludes under one flag set and never
# runs a configure step, so both have to already be on disk. This script produces
# them by running cmake's *configure* phase only — no build, no compiler on a real
# source file — and copies them into config/sundials/.
#
# The nested layout and the dropped try_compile scratch used to be worked around
# here; both moved into SysConfigGen on 2026-09-06 (RepliBuild
# test_sysconfiggen.jl §"scratch classification + generated header layout"),
# because neither is sundials-specific — any cmake project that generates a
# header under an include root, or probes a feature with try_compile, has them.
# Verified byte-identical to the hand-worked-around output apart from
# config.h's SUN_JOB_ID timestamp.
#
# WHY THE DIFF MATTERS MORE HERE THAN ELSEWHERE: sunrealtype is a config-dependent
# typedef (float | double | long double) and sunindextype likewise (int32|int64).
# A wrong probe does not fail the build — it produces a library that is
# self-consistently NOT the library, integrates at the wrong precision, and passes
# every shallow test. test.jl asserts the built .so agrees with what config.h
# claims; run it after any bump.
#
#   julia --project=/home/john/Desktop/Projects/RepliBuild.jl \
#         packages/sundials/harvest.jl

using RepliBuild
using RepliBuild.SysConfigGen

const TAG     = "v7.9.0"
const COMMIT  = "312fc0f3684f27209ca9dc9249d194436eb41a7a"
const URL     = "https://github.com/LLNL/sundials.git"
const PKG_DIR = @__DIR__

checkout = mktempdir(; prefix="sundials_harvest_")
try
    run(`git clone --depth 1 --branch $TAG -q $URL $checkout`)
    head = strip(read(`git -C $checkout rev-parse HEAD`, String))
    head == COMMIT || error("sundials harvest: $TAG resolved to $head, expected $COMMIT")

    # The -D set keeps the build lean. SUNDIALS configures 22 separate object
    # libraries; every optional package/TPL left ON adds targets and link deps.
    # We want core + CVODE + the serial/dense/Krylov stack and nothing else.
    #
    # PRECISION and INDEX_SIZE are pinned EXPLICITLY rather than inherited from
    # cmake's defaults — they are the two probes that silently change the ABI of
    # every function in the library.
    probe = cmake_probe(checkout;
        name      = "sundials",
        clone_rel = ".replibuild_cache/deps/sundials",
        args      = [
            # solvers: CVODE only
            "-DSUNDIALS_ENABLE_CVODE=ON",
            "-DSUNDIALS_ENABLE_CVODES=OFF",
            "-DSUNDIALS_ENABLE_ARKODE=OFF",
            "-DSUNDIALS_ENABLE_IDA=OFF",
            "-DSUNDIALS_ENABLE_IDAS=OFF",
            "-DSUNDIALS_ENABLE_KINSOL=OFF",
            # no Fortran interface — 84 .f90 in src/ we never want in the picture
            "-DSUNDIALS_ENABLE_FORTRAN=OFF",
            "-DBUILD_FORTRAN_MODULE_INTERFACE=OFF",
            # no examples / tests / benchmarks (227 + 157 + 34 files with main())
            "-DSUNDIALS_ENABLE_C_EXAMPLES=OFF",
            "-DSUNDIALS_ENABLE_CXX_EXAMPLES=OFF",
            "-DSUNDIALS_ENABLE_FORTRAN_EXAMPLES=OFF",
            "-DSUNDIALS_ENABLE_EXAMPLES_INSTALL=OFF",
            "-DSUNDIALS_ENABLE_BENCHMARKS=OFF",
            "-DBUILD_TESTING=OFF",
            # no parallelism backends
            "-DSUNDIALS_ENABLE_MPI=OFF",
            "-DSUNDIALS_ENABLE_OPENMP=OFF",
            "-DSUNDIALS_ENABLE_PTHREAD=OFF",
            "-DSUNDIALS_ENABLE_CUDA=OFF",
            "-DSUNDIALS_ENABLE_HIP=OFF",
            "-DSUNDIALS_ENABLE_SYCL=OFF",
            # no external TPLs — each one is a link_libraries entry that can
            # break use("sundials") on its next bump
            "-DSUNDIALS_ENABLE_LAPACK=OFF",
            "-DSUNDIALS_ENABLE_KLU=OFF",
            "-DSUNDIALS_ENABLE_SUPERLUMT=OFF",
            "-DSUNDIALS_ENABLE_SUPERLUDIST=OFF",
            "-DSUNDIALS_ENABLE_PETSC=OFF",
            "-DSUNDIALS_ENABLE_HYPRE=OFF",
            "-DSUNDIALS_ENABLE_GINKGO=OFF",
            "-DSUNDIALS_ENABLE_KOKKOS=OFF",
            "-DSUNDIALS_ENABLE_TRILINOS=OFF",
            "-DSUNDIALS_ENABLE_MAGMA=OFF",
            "-DSUNDIALS_ENABLE_ONEMKL=OFF",
            "-DSUNDIALS_ENABLE_RAJA=OFF",
            "-DSUNDIALS_ENABLE_XBRAID=OFF",
            "-DSUNDIALS_ENABLE_CALIPER=OFF",
            "-DSUNDIALS_ENABLE_ADIAK=OFF",
            "-DSUNDIALS_ENABLE_PYTHON=OFF",
            # vectors / matrices / linear solvers: serial + dense + Krylov
            "-DSUNDIALS_ENABLE_NVECTOR_SERIAL=ON",
            "-DSUNDIALS_ENABLE_NVECTOR_MANYVECTOR=OFF",
            "-DSUNDIALS_ENABLE_SUNMATRIX_DENSE=ON",
            "-DSUNDIALS_ENABLE_SUNMATRIX_BAND=ON",
            "-DSUNDIALS_ENABLE_SUNMATRIX_SPARSE=OFF",
            "-DSUNDIALS_ENABLE_SUNLINSOL_DENSE=ON",
            "-DSUNDIALS_ENABLE_SUNLINSOL_BAND=ON",
            "-DSUNDIALS_ENABLE_SUNNONLINSOL_NEWTON=ON",
            # THE TWO THAT MATTER — see the header comment
            "-DSUNDIALS_PRECISION=double",
            "-DSUNDIALS_INDEX_SIZE=64",
            "-DBUILD_STATIC_LIBS=OFF",
        ])

    display(probe)
    println("\n")

    # NOTE: uniform(probe) here reports the CHOSEN target (sundials_core_obj_shared,
    # 26 TUs). SUNDIALS configures 22 object libraries and the probe picks the
    # largest; the manifest deliberately compiles the UNION of core + cvode + the
    # serial/dense/Krylov impls. That union is legitimate under one flag set only
    # because every target's sole distinguishing define is <target>_EXPORTS, and
    # sundials_export.h expands both branches of that conditional to
    # __attribute__((visibility("default"))) on ELF — there is ONE export header
    # for the whole project, not one per target. Re-check that on a version bump:
    # if upstream ever makes the branches differ, the union stops being uniform.
    uniform(probe) || error("sundials harvest: chosen target is no longer uniform — " *
                            "the manifest's single flag set cannot reproduce it")

    # Upstream canary. SUNDIALS' monotonic-timer probe is a hand-rolled
    # try_compile with its own bindir, so it leaves POSIX_TIMER_TEST/ltest.c —
    # six lines with its own main() — sitting in the build tree. capture_config
    # classifies it as scratch (no configured target compiles it) and does not
    # capture it. If it ever stops appearing, the probe itself is gone and
    # SUNDIALS_HAVE_POSIX_TIMERS is answering from somewhere else.
    any(s -> basename(s) == "ltest.c", probe.scratch_sources) ||
        @warn "sundials harvest: the POSIX timer probe left no try_compile " *
              "scratch — upstream may have dropped it. Verify " *
              "SUNDIALS_HAVE_POSIX_TIMERS is still set in config.h." probe.scratch_sources

    # Nothing to post-process. capture_config lays each header out under the
    # deepest build-tree -I root containing it, so `include/sundials/…` out of
    # the build tree lands at `config/sundials/…` — which is what the sources'
    # own `<sundials/sundials_config.h>` (25 sites) needs `-Iconfig` to resolve.
    # Clear first: capture_config overwrites per file and would leave a header
    # upstream has since stopped generating.
    config = joinpath(PKG_DIR, "config")
    ispath(config) && rm(config; recursive=true)
    written = capture_config(probe, config)

    println("harvested:")
    foreach(w -> println("  config/", relpath(w, config)), written)

    isfile(joinpath(config, "sundials", "sundials_config.h")) ||
        error("sundials harvest: config/sundials/sundials_config.h missing — the " *
              "capture layout no longer matches the include form the sources use")

    println("\n── proposal (reference only; replibuild.toml is hand-maintained) ──")
    println(toml_fragment(probe; language="c", shim_headers=["cvode/cvode.h"]))
finally
    rm(checkout; recursive=true, force=true)
end
