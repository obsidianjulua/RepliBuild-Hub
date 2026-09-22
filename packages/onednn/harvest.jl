#!/usr/bin/env julia
# onednn — regenerate the checked-in cmake configure output, plus the OpenCL
# kernel blobs that configure alone does not produce.
#
# oneDNN cannot be compiled from a bare checkout. Two DIFFERENT generation
# mechanisms are in play, and only the first is a SysConfigGen case:
#
#   1. CONFIGURE-TIME (SysConfigGen handles this) — 3 headers + 1 source:
#        oneapi/dnnl/dnnl_config.h        the build's feature/runtime decisions
#        oneapi/dnnl/dnnl_version.h       version triple
#        oneapi/dnnl/dnnl_version_hash.h  upstream commit
#        src/gpu/intel/ocl_kernel_list.cpp   configure_file over a .cpp.in
#      The checked-in include/dnnl_config.h is only a SHIM forwarding to
#      oneapi/dnnl/dnnl_config.h, which exists in git solely as a .in template.
#      Without these nothing in src/ compiles. Headers land in config/ and ARE
#      COMMITTED; diff them after a bump, a changed runtime or a vanished
#      ONEDNN_BUILD_GRAPH is real news.
#
#   2. BUILD-RULE (SysConfigGen explicitly cannot, and says so) — 92 blobs:
#      Every .cl kernel (62) and every gpu/intel .h (30) is turned into a .cpp
#      holding its text as a C string, by a per-file `cmake -P` add_custom_command.
#      ocl_kernel_list.cpp then references all 92 by a MANGLED name
#      (gpu/intel/foo/bar.cl -> foo_bar_kernel). Reimplementing that mangling by
#      hand is how you get a link that succeeds and a runtime that cannot find a
#      kernel, so this drives ninja on the real custom-command targets instead.
#      These land in ocl/ with ocl_kernel_list.cpp beside them, and are
#      GITIGNORED (1.4 MB, regenerable) — see .gitignore.
#
# THE COUPLING THAT MATTERS
# -------------------------
# The cmake options below are the SINGLE SOURCE OF TRUTH for what the harvested
# dnnl_config.h claims, and replibuild.toml's [compile] flags + exclude list
# must agree with them. They are not independent knobs:
#
#   ONEDNN_BUILD_GRAPH=OFF           <-> exclude "graph/"
#   DNNL_GPU_RUNTIME=OCL             <-> exclude "sycl/", link OpenCL
#   DNNL_CPU_RUNTIME=OMP             <-> -fopenmp=libomp, exclude stream_threadpool.cpp
#   DNNL_ENABLE_ITT_TASKS=OFF   \    <-> exclude "third_party/" wholesale; both must
#   DNNL_ENABLE_JIT_PROFILING=OFF /      be off, src/CMakeLists.txt:63 ORs them
#   DNNL_ENABLE_PRIMITIVE_GPU_ISA    <-> see the ISA note below
#   DNNL_EXPERIMENTAL_UKERNEL=ON     <-> #define DNNL_EXPERIMENTAL_UKERNEL in
#     the harvested header, and nothing else. cpu/CMakeLists.txt already globs
#     ukernel/*.cpp into the TU set; those files include dnnl_config.h before
#     the #ifdef, so this is not an exclude change and not a [compile] -D.
#
# A config that disagrees with the compiled source set still compiles, still
# links, and still passes a shallow smoke test — it fails later and elsewhere.
# Change one side here, change the other side there, and re-run this script.
#
# Note the option is ONEDNN_BUILD_GRAPH, not DNNL_BUILD_GRAPH. CMake ignores
# unknown -D silently, so the wrong spelling leaves graph ON and the harvested
# config then advertises a component whose sources the manifest excludes. The
# assertions below exist because that failure is invisible at build time.
#
# Run after any version bump, then diff config/.
#
#   julia --project=/path/to/RepliBuild.jl packages/onednn/harvest.jl

using RepliBuild
using RepliBuild.SysConfigGen
using JSON

const TAG     = "v3.11.3"
const COMMIT  = "74d04752d9eaefff6a9ff62466c4d20b155e5bca"
const URL     = "https://github.com/oneapi-src/oneDNN.git"
const PKG_DIR = @__DIR__

# Arc A750 is Alchemist / DG2, i.e. the Xe-HPG ISA.
#
# This is LOAD-BEARING, not a tuning choice. With the default ALL, cmake
# compiles src/gpu/intel/gemm/jit/generator/generator.cpp SIX TIMES — once per
# ISA (XELP, XEHP, XEHPG, XEHPC, XE2, XE3), each with a different
# -DDNNL_GPU_ISA_* define, as six one-TU object libraries. RepliBuild compiles
# every source exactly once under one flag set, so ALL is not merely untidy
# here: it is unbuildable. Pinning one ISA takes the duplicate count to zero.
#
# Upstream's own docs note reference OpenCL implementations stay available
# regardless of this value, so the floor is a working GPU either way; what this
# selects is which architecture gets the JIT-generated GEMM kernels. That makes
# it a per-system choice in the same sense as the stl package — a different GPU
# is a different binary, which is the point of a personal Hub, not a defect.
const GPU_ISA = "XEHPG"

checkout = mktempdir(; prefix="onednn_harvest_")
build    = mktempdir(; prefix="onednn_ninja_")
try
    run(`git clone --depth 1 --branch $TAG -q $URL $checkout`)
    head = strip(read(`git -C $checkout rev-parse HEAD`, String))
    head == COMMIT || error("onednn harvest: $TAG resolved to $head, expected $COMMIT")

    cmake_args = ["-DCMAKE_C_COMPILER=clang", "-DCMAKE_CXX_COMPILER=clang++",
                  "-DDNNL_CPU_RUNTIME=OMP",
                  "-DDNNL_GPU_RUNTIME=OCL",
                  "-DDNNL_GPU_VENDOR=INTEL",
                  "-DDNNL_ENABLE_PRIMITIVE_GPU_ISA=$GPU_ISA",
                  "-DONEDNN_BUILD_GRAPH=OFF",
                  "-DDNNL_ENABLE_ITT_TASKS=OFF",
                  "-DDNNL_ENABLE_JIT_PROFILING=OFF",
                  "-DDNNL_EXPERIMENTAL_UKERNEL=ON",
                  "-DDNNL_BUILD_TESTS=OFF",
                  "-DDNNL_BUILD_EXAMPLES=OFF"]

    probe = cmake_probe(checkout;
                        name      = "onednn",
                        build_dir = build,
                        clone_rel = ".replibuild_cache/deps/onednn",
                        args      = cmake_args)
    display(probe)
    println("\n")

    # ── Guard 1: the options actually took ───────────────────────────────────
    # cmake ignores unknown -D silently.
    cfg = joinpath(build, "include", "oneapi", "dnnl", "dnnl_config.h")
    isfile(cfg) || error("onednn harvest: configure produced no dnnl_config.h")
    cfgtxt = read(cfg, String)
    occursin(r"^/\* #undef ONEDNN_BUILD_GRAPH \*/"m, cfgtxt) ||
        error("onednn harvest: ONEDNN_BUILD_GRAPH still enabled. The manifest " *
              "excludes graph/, so this config would advertise a component with " *
              "no symbols behind it.")
    occursin("#define DNNL_GPU_RUNTIME DNNL_RUNTIME_OCL", cfgtxt) ||
        error("onednn harvest: harvested config is not an OpenCL GPU build")
    occursin(r"^#define DNNL_EXPERIMENTAL_UKERNEL\b"m, cfgtxt) ||
        error("onednn harvest: DNNL_EXPERIMENTAL_UKERNEL did not land as a " *
              "#define. cmake ignores an unknown -D silently, and the ukernel " *
              "TUs then compile with the API #ifdef'd out.")

    # ── Guard 2: no source compiled more than once ───────────────────────────
    # `uniform(probe)` is the wrong question for oneDNN. It inspects only the
    # target `main_target` picks, and oneDNN is ~19 object libraries: the pick
    # is dnnl_cpu_x64, which reports two flag sets purely because upstream drops
    # gemm/*/*_kern_autogen.cpp to -O1 to cut BUILD TIME ("remove optimizations
    # of files that don't need them" — src/cpu/x64/CMakeLists.txt), not for
    # correctness. Compiling those at -O2 with everything else is fine.
    #
    # What genuinely breaks a one-flag-set build is the same FILE needing two
    # different flag sets, which is exactly the six-ISA generator.cpp case. So
    # that is what gets asserted, across the union of all targets.
    cc = JSON.parsefile(joinpath(build, "compile_commands.json"))
    counts = Dict{String,Int}()
    for e in cc
        counts[e["file"]] = get(counts, e["file"], 0) + 1
    end
    dupes = sort([f for (f, n) in counts if n > 1])
    isempty(dupes) || error("onednn harvest: $(length(dupes)) source(s) compiled " *
        "more than once under these options — RepliBuild compiles each source " *
        "exactly once, so this cannot be reproduced under one flag set:\n  " *
        join(first(dupes, 5), "\n  ") *
        "\nIf DNNL_ENABLE_PRIMITIVE_GPU_ISA drifted back to ALL, that is the cause.")
    println("one-flag-set check: $(length(cc)) TUs, 0 compiled twice\n")

    # ── Configure-time output → config/ (COMMITTED) ──────────────────────────
    # sources=false: ocl_kernel_list.cpp is a generated SOURCE and belongs with
    # the 92 blobs it references, not in the header dir. It is copied below.
    written = capture_config(probe, joinpath(PKG_DIR, "config"); sources=false)
    println("harvested config headers:")
    foreach(w -> println("  ", w), written)

    # ── Build-rule output → ocl/ (GITIGNORED) ────────────────────────────────
    # Ask ninja which targets the custom commands declare rather than predicting
    # the mangled names, then build ONLY those. Nothing is compiled.
    targets = String[]
    for line in eachline(`ninja -C $build -t targets all`)
        m = match(r"^(src/gpu/intel/[a-z0-9_]+_(?:kernel|header)\.cpp):", line)
        m === nothing || push!(targets, m.captures[1])
    end
    unique!(sort!(targets))
    length(targets) == 92 || error("onednn harvest: expected 92 generated blob " *
        "targets, found $(length(targets)). Upstream's .cl/.h set moved; re-check " *
        "cmake/gen_gpu_kernel_list.cmake before trusting this harvest.")

    println("\ngenerating $(length(targets)) kernel blob sources…")
    run(pipeline(`ninja -C $build $targets`; stdout=devnull))

    ocl = joinpath(PKG_DIR, "ocl")
    rm(ocl; recursive=true, force=true); mkpath(ocl)
    for f in readdir(joinpath(build, "src", "gpu", "intel"); join=true)
        endswith(f, ".cpp") && cp(f, joinpath(ocl, basename(f)))
    end
    # configure_file output, not a custom-command target: it rides along in the
    # copy above. Without it every get_kernel_source() call is undefined at link.
    isfile(joinpath(ocl, "ocl_kernel_list.cpp")) ||
        error("onednn harvest: ocl_kernel_list.cpp missing from harvest")

    n = count(f -> endswith(f, ".cpp"), readdir(ocl))
    println("  $n sources in ocl/ (gitignored)")

    println("\n── proposal (for reference; replibuild.toml is hand-maintained) ──")
    println("# NOTE: toml_fragment reports the ONE target main_target picks")
    println("# (dnnl_cpu_x64). oneDNN is ~19 object libraries and RepliBuild")
    println("# builds their UNION, so its exclude list is far too aggressive and")
    println("# its -D set is only that target's. Read it, do not paste it.")
    println(toml_fragment(probe; language="cpp",
            link_libraries=["OpenCL", "omp", "m", "pthread", "dl"]))
finally
    rm(checkout; recursive=true, force=true)
    rm(build;    recursive=true, force=true)
end
