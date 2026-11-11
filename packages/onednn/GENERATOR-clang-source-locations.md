# Generator bug: linked C++ IR exceeds Clang's source-location budget at create_library

> **STATUS:** OPEN
> **PACKAGE:** onednn 3.11.3
> **STAGE:** create_library
> **BLOCKS:** wrap | tests — 779 TUs compiled, llvm-link and opt succeeded, no `.so`
> **HUB PIN:** none. The TOML is not the cause. A Hub-side per-TU `clang++ -c`
> then `clang++ -shared *.o` is localized proof, not a pin — drop it once
> `create_library` stops feeding Clang one combined module.

## Symptom

`RepliBuild.build` on `packages/onednn/replibuild.toml` compiles 779 C++ TUs
to IR (cacheable, ~9 min, 12 threads), `llvm-link -S` writes
`build/onednn_linked.ll` (3.7 GB), `opt -S -O2` writes `build/onednn_opt.ll`
(3.9 GB, 21 435 123 metadata records). `create_library` then dies:

```
Library creation failed: fatal error: translation unit is too large for Clang to process: ran out of source locations
note: 2B (2B) in local locations, 0B (0B) in locations loaded from AST files, for a total of 2B (2B) (0% of available space)
note: file entered 1 time using 1B (1B) of space
1 error generated.
```

Stack: `Compiler.create_library` (`Compiler.jl:1401`) ← `compile_project:2628`
← `RepliBuild.build`. No `libonednn.so`. No `compilation_metadata.json`.

llamacpp on the same machine takes the same path and ships: its
`llamacpp_opt.ll` is 519 MB. clipper2's is 17 MB. This is the first Hub
package whose combined debug IR saturates Clang's 32-bit `SourceLocation`
space (~2^31). The C++ pipeline always llvm-links first (`link_optimize_ir`
does not have a size hatch); the existing "llvm-link failed → return the
per-TU vector" fallback never runs, because llvm-link *succeeded*.

## Why this is not a TOML mistake

`replibuild.toml` is the harvest-agreed OpenCL+OMP+XEHPG pin:

- 779 TUs, 0 `.cxx` fragments, 0 `graph/`, 0 `sycl/`, 93 harvested `ocl/` blobs
- `-fstandalone-debug` is the llamacpp/box2d rule for header-only aggregates
- `-g` is added by `compile_single_to_ir` and is load-bearing for wrap
- `[link] enable_lto = false`, `aot_thunks = false` — Hub C++ doctrine
- `DNNL_DLL` + `DNNL_DLL_EXPORTS` + `-fvisibility=hidden` so `DNNL_API` is live

Nothing in the manifest asks Clang to parse 3.9 GB of IR as one TU. That is
`compile_project` passing the llvm-link output into `create_library` as a
single path.

## C++ source / IR that produces it

Not one kernel. The overflow is the *union* of 779 `-g -fstandalone-debug`
modules. Largest per-TU IR is `ref_rnn.cpp` at 218 MB; that file **alone**
assembles:

```
clang++ -c -fPIC build/ref_rnn.cpp-c684c950.ll -o /tmp/onednn_ref_rnn.o
# 20s, 32 MB ELF, with debug_info, llvm-dwarfdump reports 6316 functions
```

So the per-TU IR is well inside Clang's budget. `onednn_opt.ll` is the same
debug metadata, concatenated. `grep -c '^!' build/onednn_opt.ll` → 21435123.

## Pipeline stage

`create_library` (`STAGE:` above). Compile-to-IR and llvm-link/opt are fine.
The next consumer of the linked module is `clang++ -shared <one .ll> -o lib.so`,
which re-parses the whole thing as a single Clang TU and allocates a
`SourceLocation` per debug location.

Passing the 779 `.ll` files to **one** `clang++ -shared a.ll b.ll …` is not a
sufficient fix: one Clang process still has one `SourceManager`. The path that
actually works is `clang++ -c` per file (fresh SourceManager each time) then
`clang++ -shared *.o`.

## What you tried

- Full `RepliBuild.build` (pid 66292, 2026-09-20). Compile 779/779, llvm-link
  3.7 GB, opt 3.9 GB, then the error above. RSS of `opt` peaked ~24 GB; no OOM.
- `clang++ -c` on the largest per-TU IR: succeeds, DWARF present.
- Did not drop `-fstandalone-debug` or `-g` — that would shrink locations by
  emptying the wrap surface, which is a pin, not a fix.
- Did not edit `RepliBuild.jl/src/`.

## Suggested fix, not applied

In `link_optimize_ir` / `create_library` (C++ external pipeline):

1. After llvm-link/opt, do **not** hand a multi-GB `.ll` to Clang as one TU.
2. On the Clang diagnostic `translation unit is too large` / `ran out of
   source locations`, **or** when the linked IR is over a hard size (llamacpp's
   519 MB worked; 3.7 GB did not — pick a threshold with a fixture, not a
   guess), fall back to: `clang++ -c -fPIC` each per-TU `.ll` → `.o`, then
   `clang++ -shared *.o` with the same `-l` set `create_library` already
   appends.
3. Do not treat "pass the vector of `.ll` to one `clang++ -shared`" as the
   fallback. That is what `create_library` already does when `ir_files isa
   Vector`, and it still uses one SourceManager.
4. Keep DWARF. Stripping debug to make the combined module fit is how you
   ship a `.so` the wrapper cannot read.

**Negative check** (run on this package, IR cache hot — do not `clean`):

```julia
using RepliBuild
lib = RepliBuild.build("/abs/packages/onednn/replibuild.toml")
@assert isfile(lib) && occursin("libonednn", lib)
@assert filesize(lib) > 10_000_000
```

Must not print `ran out of source locations`. `nm -D --defined-only` on the
`.so` must show `dnnl_sgemm` / `dnnl_engine_create` (DNNL_API, i.e. the
defines actually took). Then `RepliBuild.wrap` on the same TOML must produce
`Onednn.jl` whose `dnnl_engine_create` is not zero-arg.

A library-free fixture: one C++ file that `#include`s enough debug-heavy
headers, compiled `-g -fstandalone-debug -S -emit-llvm`, concatenated with
itself until `llvm-link` output is >2 GB, then `create_library` on that
single path. If the engine only works with onednn in play, it is not this
bug.

## Environment

- Julia 1.13.0 (`juliaup`), `Threads.nthreads() = 12`
- system clang++ / llvm-link / opt **22.1.8** (C++ bucket, external pipeline)
- libLLVM 22.1.8 also present; C bucket unused (this package is `language = "cpp"`)
- RepliBuild.jl 4.0.1, sibling of the Hub
- 62 GB RAM, no OOM, no swap used
- oneDNN v3.11.3 `74d04752d9eaefff6a9ff62466c4d20b155e5bca`, Arc A750 / XEHPG
