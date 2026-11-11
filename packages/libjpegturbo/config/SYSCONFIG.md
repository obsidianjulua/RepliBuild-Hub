# Captured cmake configure output — checked in on purpose

`libjpegturbo` cannot be compiled from a bare checkout: these files are
produced by cmake's configure step (`configure_file` over a template), and
RepliBuild compiles all-sources-minus-excludes under one flag set without
ever running a configure. So they have to already exist.

Captured by `RepliBuild.SysConfigGen.cmake_probe` + `capture_config`.

## Files

Paths are relative to this directory, which is the one `include_dirs`
points at. Under `layout=:auto` they keep the include form upstream
compiles with, so `-I` on this directory resolves them unchanged.

- `jconfig.h`
- `jconfigint.h`
- `jversion.h`

## Regenerating (required on any version bump)

```julia
using RepliBuild, RepliBuild.SysConfigGen
p = cmake_probe("<checkout>";
                name="libjpegturbo",
                args=["-DENABLE_SHARED=ON",
                      "-DENABLE_STATIC=OFF",
                      "-DWITH_TURBOJPEG=ON",
                      "-DWITH_SIMD=OFF",
                      "-DWITH_TOOLS=OFF",
                      "-DWITH_TESTS=OFF",
                      "-DWITH_FUZZ=OFF",
                      "-DWITH_JAVA=OFF"])
capture_config(p, "config")
```

Full cmake argument set used:

```
-DCMAKE_BUILD_TYPE=Release
-DCMAKE_EXPORT_COMPILE_COMMANDS=ON
-DBUILD_SHARED_LIBS=ON
-DCMAKE_POLICY_VERSION_MINIMUM=3.5
-DENABLE_SHARED=ON
-DENABLE_STATIC=OFF
-DWITH_TURBOJPEG=ON
-DWITH_SIMD=OFF
-DWITH_TOOLS=OFF
-DWITH_TESTS=OFF
-DWITH_FUZZ=OFF
-DWITH_JAVA=OFF
```

## The pin this implies

A snapshot of **this machine's** feature detection at the pinned commit.
It travels with the package, so the build is reproducible — but it is a
single-target pin, which matches the Hub. Regenerate on a version bump and
diff: a changed `SIZEOF_*` or a vanished `USE_*` is real news.

Captured from `<tmp>/libjpegturbo_harvest_sHyGn6` on 2026-11-10, cmake 4.4.5, x86_64-linux-gnu.
