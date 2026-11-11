# Captured cmake configure output — checked in on purpose

`sundials` cannot be compiled from a bare checkout: these files are
produced by cmake's configure step (`configure_file` over a template), and
RepliBuild compiles all-sources-minus-excludes under one flag set without
ever running a configure. So they have to already exist.

Captured by `RepliBuild.SysConfigGen.cmake_probe` + `capture_config`.

## Files

Paths are relative to this directory, which is the one `include_dirs`
points at. Under `layout=:auto` they keep the include form upstream
compiles with, so `-I` on this directory resolves them unchanged.

- `sundials/sundials_config.h`
- `sundials/sundials_export.h`

## Skipped — generated, but no target compiles them

Not captured. Overwhelmingly cmake `try_compile` probe scratch, which has
its own `main()` — never add one to `[compile] source_files`.

- `POSIX_TIMER_TEST/ltest.c`

## Regenerating (required on any version bump)

```julia
using RepliBuild, RepliBuild.SysConfigGen
p = cmake_probe("<checkout>";
                name="sundials",
                args=["-DSUNDIALS_ENABLE_CVODE=ON",
                      "-DSUNDIALS_ENABLE_CVODES=OFF",
                      "-DSUNDIALS_ENABLE_ARKODE=OFF",
                      "-DSUNDIALS_ENABLE_IDA=OFF",
                      "-DSUNDIALS_ENABLE_IDAS=OFF",
                      "-DSUNDIALS_ENABLE_KINSOL=OFF",
                      "-DSUNDIALS_ENABLE_FORTRAN=OFF",
                      "-DBUILD_FORTRAN_MODULE_INTERFACE=OFF",
                      "-DSUNDIALS_ENABLE_C_EXAMPLES=OFF",
                      "-DSUNDIALS_ENABLE_CXX_EXAMPLES=OFF",
                      "-DSUNDIALS_ENABLE_FORTRAN_EXAMPLES=OFF",
                      "-DSUNDIALS_ENABLE_EXAMPLES_INSTALL=OFF",
                      "-DSUNDIALS_ENABLE_BENCHMARKS=OFF",
                      "-DBUILD_TESTING=OFF",
                      "-DSUNDIALS_ENABLE_MPI=OFF",
                      "-DSUNDIALS_ENABLE_OPENMP=OFF",
                      "-DSUNDIALS_ENABLE_PTHREAD=OFF",
                      "-DSUNDIALS_ENABLE_CUDA=OFF",
                      "-DSUNDIALS_ENABLE_HIP=OFF",
                      "-DSUNDIALS_ENABLE_SYCL=OFF",
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
                      "-DSUNDIALS_ENABLE_NVECTOR_SERIAL=ON",
                      "-DSUNDIALS_ENABLE_NVECTOR_MANYVECTOR=OFF",
                      "-DSUNDIALS_ENABLE_SUNMATRIX_DENSE=ON",
                      "-DSUNDIALS_ENABLE_SUNMATRIX_BAND=ON",
                      "-DSUNDIALS_ENABLE_SUNMATRIX_SPARSE=OFF",
                      "-DSUNDIALS_ENABLE_SUNLINSOL_DENSE=ON",
                      "-DSUNDIALS_ENABLE_SUNLINSOL_BAND=ON",
                      "-DSUNDIALS_ENABLE_SUNNONLINSOL_NEWTON=ON",
                      "-DSUNDIALS_PRECISION=double",
                      "-DSUNDIALS_INDEX_SIZE=64",
                      "-DBUILD_STATIC_LIBS=OFF"])
capture_config(p, "config")
```

Full cmake argument set used:

```
-DCMAKE_BUILD_TYPE=Release
-DCMAKE_EXPORT_COMPILE_COMMANDS=ON
-DBUILD_SHARED_LIBS=ON
-DCMAKE_POLICY_VERSION_MINIMUM=3.5
-DSUNDIALS_ENABLE_CVODE=ON
-DSUNDIALS_ENABLE_CVODES=OFF
-DSUNDIALS_ENABLE_ARKODE=OFF
-DSUNDIALS_ENABLE_IDA=OFF
-DSUNDIALS_ENABLE_IDAS=OFF
-DSUNDIALS_ENABLE_KINSOL=OFF
-DSUNDIALS_ENABLE_FORTRAN=OFF
-DBUILD_FORTRAN_MODULE_INTERFACE=OFF
-DSUNDIALS_ENABLE_C_EXAMPLES=OFF
-DSUNDIALS_ENABLE_CXX_EXAMPLES=OFF
-DSUNDIALS_ENABLE_FORTRAN_EXAMPLES=OFF
-DSUNDIALS_ENABLE_EXAMPLES_INSTALL=OFF
-DSUNDIALS_ENABLE_BENCHMARKS=OFF
-DBUILD_TESTING=OFF
-DSUNDIALS_ENABLE_MPI=OFF
-DSUNDIALS_ENABLE_OPENMP=OFF
-DSUNDIALS_ENABLE_PTHREAD=OFF
-DSUNDIALS_ENABLE_CUDA=OFF
-DSUNDIALS_ENABLE_HIP=OFF
-DSUNDIALS_ENABLE_SYCL=OFF
-DSUNDIALS_ENABLE_LAPACK=OFF
-DSUNDIALS_ENABLE_KLU=OFF
-DSUNDIALS_ENABLE_SUPERLUMT=OFF
-DSUNDIALS_ENABLE_SUPERLUDIST=OFF
-DSUNDIALS_ENABLE_PETSC=OFF
-DSUNDIALS_ENABLE_HYPRE=OFF
-DSUNDIALS_ENABLE_GINKGO=OFF
-DSUNDIALS_ENABLE_KOKKOS=OFF
-DSUNDIALS_ENABLE_TRILINOS=OFF
-DSUNDIALS_ENABLE_MAGMA=OFF
-DSUNDIALS_ENABLE_ONEMKL=OFF
-DSUNDIALS_ENABLE_RAJA=OFF
-DSUNDIALS_ENABLE_XBRAID=OFF
-DSUNDIALS_ENABLE_CALIPER=OFF
-DSUNDIALS_ENABLE_ADIAK=OFF
-DSUNDIALS_ENABLE_PYTHON=OFF
-DSUNDIALS_ENABLE_NVECTOR_SERIAL=ON
-DSUNDIALS_ENABLE_NVECTOR_MANYVECTOR=OFF
-DSUNDIALS_ENABLE_SUNMATRIX_DENSE=ON
-DSUNDIALS_ENABLE_SUNMATRIX_BAND=ON
-DSUNDIALS_ENABLE_SUNMATRIX_SPARSE=OFF
-DSUNDIALS_ENABLE_SUNLINSOL_DENSE=ON
-DSUNDIALS_ENABLE_SUNLINSOL_BAND=ON
-DSUNDIALS_ENABLE_SUNNONLINSOL_NEWTON=ON
-DSUNDIALS_PRECISION=double
-DSUNDIALS_INDEX_SIZE=64
-DBUILD_STATIC_LIBS=OFF
```

## The pin this implies

A snapshot of **this machine's** feature detection at the pinned commit.
It travels with the package, so the build is reproducible — but it is a
single-target pin, which matches the Hub. Regenerate on a version bump and
diff: a changed `SIZEOF_*` or a vanished `USE_*` is real news.

Captured from `/tmp/sundials_harvest_Kc6c5G` on 2026-09-06, cmake 4.4.3, x86_64-linux-gnu.
