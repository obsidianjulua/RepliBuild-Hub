# Generator bug: enumerator named `_` sanitizes to empty, wrapper fails to parse

> **STATUS:** OPEN
> **PACKAGE:** onednn 3.11.3
> **STAGE:** wrap
> **BLOCKS:** wrap | tests — `libonednn.so` exists and smokes; `_assert_wrapper_parses` refuses `Onednn.jl`
> **HUB PIN:** none. `[wrap] use_clang_jl = false` is a C-API surface choice (dnnl.h),
> not a dodge — DWARF still carries `inner_blk_t._`. A JSON rename of that
> enumerator is localized proof, not a pin; the next metadata extract restores `_`.

## Symptom

`RepliBuild.wrap` on `packages/onednn/replibuild.toml` ran ~17 min (Clang.jl
header walk, then C++ module emit), produced 13 MB / 271 923 lines of Julia,
and refused to write it:

```
ERROR: Refusing to write wrapper 'Onednn': the generated source is not valid Julia syntax.

Base.Meta.ParseError:
# Error @ Onednn.jl:4712:6
@enum inner_blk_t::Cint begin
     = 0
#    ╙ ── unexpected `=`
```

Rejected source: `/tmp/replibuild_rejected_Onednn.jl`. Second identical hole
at line 6932, `@enum block_dim_t` (Clang.jl header path, "not in DWARF").

Stack: `_assert_wrapper_parses` ← `_write_wrapper` ← `wrap_introspective`
(`Generator.jl:1090`) ← `RepliBuild.wrap`.

## Why this is not a TOML mistake

The enumerators are real C++ identifiers. Upstream writes them as `_`:

```cpp
// src/common/tag_traits.hpp
enum class block_dim_t { _, _A, _B, _C, _D, _E, _AB, _BC, _CD, _CE };
enum class inner_blk_t { _, _4a, _4b, /* … */ };
```

DWARF metadata records that faithfully:

```json
"__enum__inner_blk_t": {
  "enumerators": [{"name": "_", "value": 0}, {"name": "_4a", "value": 1}, ...]
}
```

The TOML did not invent these names. `_` is a legal C++ enumerator and a legal
Julia identifier. The emitter is what emptied it.

## C++ source / IR that produces it

`packages/onednn/.replibuild_cache/deps/onednn/src/common/tag_traits.hpp:58-72`
(oneDNN v3.11.3). Any library with `enum { _, … }` hits this. The llamacpp
lambda-spelling sanitizer (`rstrip` of trailing `_`) is the code that does it.

## Pipeline stage

`wrap` (`STAGE:` above). Build is fine. `_write_wrapper`'s parse guard is
working as designed — it is how this was caught instead of shipping a module
that dies at `include`.

## What you tried

- Full wrap, pid 76009, 2026-09-20. CPU-bound in libclang ~16 min, then emit.
  21723 dag-diff mismatches, 4926 names dropped from export, then the parse
  refusal. `Onednn.jl` not written.
- Confirmed `_sanitize_cpp_type_name("_")` → `""`:
  `rstrip(s, '_')` on a name that *is* `_` yields empty; the digit-prefix
  guard does not run on empty; nothing restores a placeholder.
- `_4a` survives (`rstrip` only strips trailing `_`). Only a name of all
  underscores dies.
- Did not edit `RepliBuild.jl/src/`.

## Suggested fix, not applied

`Wrapper/Cpp/UtilsCpp.jl` `_sanitize_cpp_type_name`, after the `rstrip`:

```julia
s = String(rstrip(s, '_'))
isempty(s) && (s = "_")   # enumerator/type whose C++ name was "_"
```

Same function is used for struct names, field names, and enum members. Empty
must not reach an identifier position in any of those. A fixture enum

```cpp
enum class inner_blk_t { _, _4a };
```

compiled `-g -fstandalone-debug`, wrapped, must parse. Negative check on
this package: `RepliBuild.wrap` writes `Onednn.jl` that `Meta.parse`s, and
`@enum inner_blk_t` contains a member for value 0 whose name is `_` (or
`underscore` / `c__`, whatever the chosen spelling — not empty).

Do **not** drop the enumerator. Value 0 is the C++ default (`inner_blk_t{}`).
Skipping it would compile the wrapper and silently change the default.

`GeneratorC.jl` has the same sanitize-then-emit path for DWARF enums; apply
the empty-after-rstrip guard in both, or in the one function both call.

## Environment

- Julia 1.13.0, RepliBuild.jl 4.0.1
- system clang 22.1.8 (build); wrap used in-process libclang 20.1.8 (Clang.jl)
- oneDNN v3.11.3 `74d04752…`, `libonednn.so` 783 MB already linked
