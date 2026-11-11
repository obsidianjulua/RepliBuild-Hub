# Captured cmake configure output — checked in on purpose

`expat` cannot be compiled from a bare checkout: these files are
produced by cmake's configure step (`configure_file` over a template), and
RepliBuild compiles all-sources-minus-excludes under one flag set without
ever running a configure. So they have to already exist.

Captured by `RepliBuild.SysConfigGen.cmake_probe` + `capture_config`.

## Files

Paths are relative to this directory, which is the one `include_dirs`
points at. Under `layout=:auto` they keep the include form upstream
compiles with, so `-I` on this directory resolves them unchanged.

- `expat_config.h`

## Regenerating (required on any version bump)

```julia
using RepliBuild, RepliBuild.SysConfigGen
p = cmake_probe("<checkout>";
                name="expat",
                args=["-DEXPAT_BUILD_TOOLS=OFF",
                      "-DEXPAT_BUILD_EXAMPLES=OFF",
                      "-DEXPAT_BUILD_TESTS=OFF",
                      "-DEXPAT_BUILD_DOCS=OFF",
                      "-DEXPAT_BUILD_FUZZERS=OFF",
                      "-DEXPAT_BUILD_PKGCONFIG=OFF",
                      "-DEXPAT_WITH_LIBBSD=OFF",
                      "-DEXPAT_SHARED_LIBS=ON"])
capture_config(p, "config")
```

Full cmake argument set used:

```
-DCMAKE_BUILD_TYPE=Release
-DCMAKE_EXPORT_COMPILE_COMMANDS=ON
-DBUILD_SHARED_LIBS=ON
-DCMAKE_POLICY_VERSION_MINIMUM=3.5
-DEXPAT_BUILD_TOOLS=OFF
-DEXPAT_BUILD_EXAMPLES=OFF
-DEXPAT_BUILD_TESTS=OFF
-DEXPAT_BUILD_DOCS=OFF
-DEXPAT_BUILD_FUZZERS=OFF
-DEXPAT_BUILD_PKGCONFIG=OFF
-DEXPAT_WITH_LIBBSD=OFF
-DEXPAT_SHARED_LIBS=ON
```

## The pin this implies

A snapshot of **this machine's** feature detection at the pinned commit.
It travels with the package, so the build is reproducible — but it is a
single-target pin, which matches the Hub. Regenerate on a version bump and
diff: a changed `SIZEOF_*` or a vanished `USE_*` is real news.

Captured from `/tmp/expat_harvest_oqG6fj/expat` on 2026-09-25, cmake 4.4.3, x86_64-linux-gnu.
