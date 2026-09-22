# Captured cmake configure output — checked in on purpose

`onednn` cannot be compiled from a bare checkout: these files are
produced by cmake's configure step (`configure_file` over a template), and
RepliBuild compiles all-sources-minus-excludes under one flag set without
ever running a configure. So they have to already exist.

Captured by `RepliBuild.SysConfigGen.cmake_probe` + `capture_config`.

## Files

Paths are relative to this directory, which is the one `include_dirs`
points at. Under `layout=:auto` they keep the include form upstream
compiles with, so `-I` on this directory resolves them unchanged.

- `oneapi/dnnl/dnnl_config.h`
- `oneapi/dnnl/dnnl_version.h`
- `oneapi/dnnl/dnnl_version_hash.h`

## Regenerating (required on any version bump)

```julia
using RepliBuild, RepliBuild.SysConfigGen
p = cmake_probe("<checkout>";
                name="onednn",
                args=["-DDNNL_CPU_RUNTIME=OMP",
                      "-DDNNL_GPU_RUNTIME=OCL",
                      "-DDNNL_GPU_VENDOR=INTEL",
                      "-DDNNL_ENABLE_PRIMITIVE_GPU_ISA=XEHPG",
                      "-DONEDNN_BUILD_GRAPH=OFF",
                      "-DDNNL_ENABLE_ITT_TASKS=OFF",
                      "-DDNNL_ENABLE_JIT_PROFILING=OFF",
                      "-DDNNL_EXPERIMENTAL_UKERNEL=ON",
                      "-DDNNL_BUILD_TESTS=OFF",
                      "-DDNNL_BUILD_EXAMPLES=OFF"])
capture_config(p, "config")
```

Full cmake argument set used:

```
-DCMAKE_BUILD_TYPE=Release
-DCMAKE_EXPORT_COMPILE_COMMANDS=ON
-DBUILD_SHARED_LIBS=ON
-DCMAKE_POLICY_VERSION_MINIMUM=3.5
-DCMAKE_C_COMPILER=clang
-DCMAKE_CXX_COMPILER=clang++
-DDNNL_CPU_RUNTIME=OMP
-DDNNL_GPU_RUNTIME=OCL
-DDNNL_GPU_VENDOR=INTEL
-DDNNL_ENABLE_PRIMITIVE_GPU_ISA=XEHPG
-DONEDNN_BUILD_GRAPH=OFF
-DDNNL_ENABLE_ITT_TASKS=OFF
-DDNNL_ENABLE_JIT_PROFILING=OFF
-DDNNL_EXPERIMENTAL_UKERNEL=ON
-DDNNL_BUILD_TESTS=OFF
-DDNNL_BUILD_EXAMPLES=OFF
```

## The pin this implies

A snapshot of **this machine's** feature detection at the pinned commit.
It travels with the package, so the build is reproducible — but it is a
single-target pin, which matches the Hub. Regenerate on a version bump and
diff: a changed `SIZEOF_*` or a vanished `USE_*` is real news.

Captured from `/tmp/onednn_harvest_2uLnsb` on 2026-09-21, cmake 4.4.3, x86_64-linux-gnu.
