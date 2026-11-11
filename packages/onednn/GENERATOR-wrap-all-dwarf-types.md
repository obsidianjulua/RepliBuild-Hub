# Generator bug: wrap emits every DWARF type, not the wrap-surface types

> **STATUS:** OPEN
> **PACKAGE:** onednn 3.11.3
> **STAGE:** wrap
> **BLOCKS:** load — `Onednn.jl` is 13 MB / 271k lines, mostly nGEN instruction
> structs the C API never names. `include` dies on those internals
> (`duplicate field name: "_"`, `const Integer = Pipe(3)` vs `v::Integer`).
> **HUB PIN:** none. Filtering `struct_definitions` down to types reachable
> from the 302 exported functions is localized proof, not a pin.

## Symptom

`nm -D --defined-only` on `libonednn.so` has 217 `dnnl_*` symbols. Metadata
has 302 functions and **2974** `struct_definitions` (2664 structs + 310
enums). A one-pass name match from those 302 signatures hits **52** of the
2974. The other ~2920 are `dnnl::impl` / nGEN GPU-JIT internals that no
exported function takes or returns.

`include("Onednn.jl")` then fails on those internals, in order:

1. `const Integer = Pipe(3)` then `v::Integer` (GENERATOR-integer-shadow.md)
2. `struct Instruction12_anon1_imm32; _::UInt64; _::UInt32; …` — duplicate
   field `_` (Onednn.jl:9706). Anonymous nGEN padding fields, both sanitized
   to `_`.

The public C functions (`dnnl_engine_create`, `dnnl_sgemm`, …) have real
DWARF signatures and are not the failure. They never get a chance to run.

## Why this is not a TOML mistake

`[wrap] language = "cpp"` plus `-fstandalone-debug` is required so `dnnl.hpp`
aggregates are not declaration-only. That debug info *contains* nGEN. The
TOML cannot say “emit types reachable from `.dynsym` only”; wrap emits the
whole `struct_definitions` map. `use_clang_jl = false` already dropped the
header-walk extras. DWARF internals remain.

## C++ source that produces it

nGEN instruction encodings under `third_party/ngen`, compiled into the Intel
GPU JIT TUs. They are not the package's wrap surface. The surface is
`include/oneapi/dnnl/dnnl.h` (`extern "C"`, `DNNL_API`).

## Pipeline stage

`wrap` / `generate_introspective_module_cpp`. It iterates
`metadata["struct_definitions"]` in full (`GeneratorCpp.jl` ~307).

## What you tried

- Wrap wrote `Onednn.jl`. `include` died at `set_hs!` (`::Integer`), then
  after a `Base.Integer` proof-patch, at duplicate field `_` on
  `Instruction12_anon1_imm32`.
- Counted reachability: 52 / 2974 struct keys named from the 302 function
  records (not yet a transitive member walk).
- Did not edit `RepliBuild.jl/src/`.

## Suggested fix, not applied

Emit types **reachable from the wrap surface** (exported functions' parameter
and return types, then members, transitively). Internals stay in DWARF for
thunks if a signature needs them; they do not become `struct`/`@enum` in the
module.

**Negative check:** `include("Onednn.jl")` succeeds. `Onednn.dnnl_engine_get_count(Onednn.dnnl_cpu) == 1` and `…(Onednn.dnnl_gpu) == 1` against this `.so`. The module must not contain `Instruction12_anon1_imm32` or `set_hs!`. A fixture with one `extern "C"` function and a large unused internal struct is the library-free form.

## Environment

- Julia 1.13.0, RepliBuild.jl 4.0.1
- `Onednn.jl` 13 243 124 bytes; `libonednn.so` 783 MB
