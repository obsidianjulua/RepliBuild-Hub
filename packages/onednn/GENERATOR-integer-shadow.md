# Generator bug: C++ enumerator `Integer` shadows `::Integer` in bitfield setters

> **STATUS:** OPEN
> **PACKAGE:** onednn 3.11.3
> **STAGE:** wrap
> **BLOCKS:** load — `Onednn.jl` is written and parses; `include` dies on the first
> bitfield setter
> **HUB PIN:** none. 522 generated `v::Integer` annotations resolve to
> `const Integer = Pipe(3)`, not `Base.Integer`.

## Symptom

After wrap wrote `packages/onednn/julia/Onednn.jl` (13 MB):

```
ERROR: LoadError: ArgumentError: invalid type for argument v in method definition
for set_hs! at Onednn.jl:6496
```

```julia
function set_hs!(s::BinaryOperand12_direct, v::Integer)  # line 6496
```

`Integer` at that point is not `Base.Integer`. Earlier in the same module:

```julia
@enum Pipe::UInt8 begin
    Default = 0
    A = 1
    F = 2
    I = 3
    …
end
const Integer = Pipe(3)   # Onednn.jl:1305 — duplicate-value enumerator alias
```

A `const` binding is a value, so `v::Integer` is `invalid type for argument v`.
522 methods in this wrapper use that annotation (ngen bitfield setters).

`_assert_wrapper_parses` does not catch this — `Meta.parse` succeeds; the
failure is at eval of the method definition. `_base_shadowing` already
*withholds `Integer` from `export`* (the wrap log lists it), which protects
`using .Onednn` consumers and does nothing for names *inside* the module.

## Why this is not a TOML mistake

`Pipe` / `Integer` come from nGEN (`third_party/ngen`), compiled into the GPU
JIT. The C API (`dnnl_engine_create`, `dnnl_sgemm`) does not mention them.
The wrapper emits them because DWARF has the types. No TOML flag stops one
enumerator from colliding with a spelling the *emitter itself* uses.

`_sanitize_cpp_type_name` already renames `Type`, `Ref`, `Ptr`, `Vector`,
`Any`, … It does not rename `Integer`.

## C++ source that produces it

nGEN `enum class Pipe` with an enumerator whose DWARF name is `Integer` at
value 3 (same value as `I`, hence the `const` alias emit). oneDNN v3.11.3,
`third_party/ngen`. Any C++ enum member named `Integer` / `Float` / `error`
will do this the moment the wrapper also emits `::Integer`.

## Pipeline stage

`wrap` load, after `_write_wrapper`. Build is fine. `Onednn.jl` is on disk.

## What you tried

- Wrap with `use_clang_jl = false` and the `_` enumerator proof-rename
  (GENERATOR-enum-underscore-name.md). Wrap wrote the file. `include` died here.
- Confirmed `const Integer = Pipe(3)` precedes every `v::Integer`.
- Did not edit `RepliBuild.jl/src/`.

## Suggested fix, not applied

Both, not either:

1. Bitfield setters (and any other generated signature that means “Julia
   Integer”) must spell `Base.Integer`, same way `setproperty!` already spells
   `Base.error`.
2. `_sanitize_cpp_type_name` must rename `Integer` (and the rest of the
   `_base_shadowing` set that can appear as *values* in the module: `Float`,
   `error`, `undef`, …) the way it already renames `Type`/`Ptr`. Export
   withholding is not enough.

**Negative check:** `include("Onednn.jl")` must get past `set_hs!`. Then
`Onednn.dnnl_engine_get_count(Onednn.dnnl_cpu) == 1` against this package's
`.so`. A fixture enum `{ I = 3, Integer = 3 }` plus one generated
`f(v::Integer)` is the library-free form.

## Environment

- Julia 1.13.0, RepliBuild.jl 4.0.1
- `Onednn.jl` 13 243 124 bytes, wrap 2026-09-20T19:08:51
- `libonednn.so` 783 MB, smoke via raw ccall already green
