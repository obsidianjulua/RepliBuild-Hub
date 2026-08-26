# Harvested cmake configure output — checked in on purpose

`pcre2` cannot be compiled from a bare checkout: these files are
produced by cmake's configure step (`configure_file` over a template), and
RepliBuild compiles all-sources-minus-excludes under one flag set without
ever running a configure. So they have to already exist.

Captured by `RepliBuild.SysConfigGen.cmake_probe` + `capture_config`.

## Files

- `config.h`
- `pcre2.h`
- `pcre2_chartables.c`

## Regenerating (required on any version bump)

```julia
using RepliBuild, RepliBuild.SysConfigGen
p = cmake_probe("<checkout>";
                name="pcre2",
                args=["-DPCRE2_BUILD_TESTS=OFF",
                      "-DPCRE2_BUILD_PCRE2GREP=OFF",
                      "-DPCRE2_BUILD_PCRE2_8=ON",
                      "-DPCRE2_BUILD_PCRE2_16=OFF",
                      "-DPCRE2_BUILD_PCRE2_32=OFF",
                      "-DPCRE2_SUPPORT_JIT=OFF"])
capture_config(p, "config")
```

Full cmake argument set used:

```
-DCMAKE_BUILD_TYPE=Release
-DCMAKE_EXPORT_COMPILE_COMMANDS=ON
-DBUILD_SHARED_LIBS=ON
-DCMAKE_POLICY_VERSION_MINIMUM=3.5
-DPCRE2_BUILD_TESTS=OFF
-DPCRE2_BUILD_PCRE2GREP=OFF
-DPCRE2_BUILD_PCRE2_8=ON
-DPCRE2_BUILD_PCRE2_16=OFF
-DPCRE2_BUILD_PCRE2_32=OFF
-DPCRE2_SUPPORT_JIT=OFF
```

## The pin this implies

A snapshot of **this machine's** feature detection at the pinned commit.
It travels with the package, so the build is reproducible — but it is a
single-target pin, which matches the Hub. Regenerate on a version bump and
diff: a changed `SIZEOF_*` or a vanished `USE_*` is real news.

Captured from `/tmp/pcre2_harvest_SQMBgD` on 2026-08-17, cmake 4.4.2, x86_64-linux-gnu.
