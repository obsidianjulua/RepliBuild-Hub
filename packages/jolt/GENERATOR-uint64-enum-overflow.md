# Generator gap: an enumerator above typemax(Int64) aborts the whole wrap

> **STATUS:** OPEN
> **PACKAGE:** jolt 5.7.0 (`cf16769`)
> **STAGE:** wrap (C++ enum rendering → `_is_bitflag_enum`)
> **BLOCKS:** the entire Jolt wrapper. `build` succeeds (144 sources, 158
> forced constructors, 2,165 forced methods, `julia/libjolt.so`); `wrap`
> throws before writing `Jolt.jl`, so nothing of Jolt is callable from Julia.
> **HUB PIN (workaround in place):** `overrides/Jolt/Physics/LargeIslandSplitter.h`
> is upstream's header with only `enum EIterationStatus : uint64` rewritten as
> five `static constexpr uint64` members (same names, same values; every use
> reads them as uint64 constants, so the code is unchanged). `include_dirs`
> lists `overrides` before the clone so it shadows upstream's copy. With it,
> the cold build + wrap completes (`Jolt.jl`, 7,170 functions, 1,253 structs).
> `[wrap] exclude_symbols = ["*EIterationStatus*"]` was tried first and does
> not reach enums: "1 pattern(s) matched nothing". **To retire:** delete
> `overrides/`, remove it from `include_dirs` (and the WORKAROUND note under
> `[wrap]`), rebuild cold; the wrap must complete with the upstream header.
> **ENGINE AT:** RepliBuild.jl `a875932` (main, #111)

## Symptom

```
ERROR: LoadError: InexactError: Int64(18446462598732840960)
  [1] Type                 @ ./gmp.jl:386
  [2] _is_bitflag_enum(values::Vector{Signed})   @ src/Wrapper/Utils.jl:1058
  [3] _render_enum_chunks(...)                   @ src/Wrapper/Utils.jl:1351
  [4] generate_introspective_module_cpp(...)     @ src/Wrapper/Cpp/GeneratorCpp.jl:4829
  ...
  [11] wrap(toml_path::String)                   @ src/RepliBuild.jl:998
```

18446462598732840960 is `0xffff000000000000`.

## Source

`Jolt/Physics/LargeIslandSplitter.h:100`, a nested enum with a 64-bit
unsigned underlying type:

```cpp
enum EIterationStatus : uint64
{
    StatusIterationMask  = 0xffff000000000000,
    StatusIterationShift = 48,
    StatusSplitMask      = 0x0000ffff00000000,
    StatusSplitShift     = 32,
    StatusItemMask       = 0x00000000ffffffff,
};
```

It is a legal C++ enum, and its first enumerator does not fit in Int64.

## Why this is not a TOML mistake

The enum is internal to `LargeIslandSplitter` and nothing in the recipe asks
for it. It reaches the wrapper because the class's DWARF is in the library,
which `-fstandalone-debug` puts there for every Jolt type. No recipe key
changes an enumerator's value. Whether `[wrap] exclude_symbols` also removes
enums was not checked (see Not checked); it is a symbol filter by its name and
docs.

## Pipeline stage

- `src/Wrapper/Utils.jl:1054-1059`, `_is_bitflag_enum(values)`:
  `vals = Int64[]; for v in values … push!(vals, Int64(v))`. The values come
  in as `Vector{Signed}` with this one as a `BigInt`, and `Int64(v)` throws.
- Called from `src/Wrapper/Utils.jl:1351` (`_render_enum_chunks`, the frame
  above) and also from `src/Wrapper/TypeImports.jl:846`
  (`_is_bitflag_enum(last.(c.members)) && continue`), which has the same
  exposure.
- The exception is not caught per enum, so one enum ends the whole wrap.

## Minimal reproduction

```cpp
// lib.h
#include <cstdint>
enum Wide : uint64_t { A = 1, B = 2, C = 4, High = 0xffff000000000000ull };
int take(Wide w);
// lib.cpp
#include "lib.h"
int take(Wide w) { return int(w & 7); }
```

Expected at `a875932`: `wrap` throws the same `InexactError` at
`Utils.jl:1058`. Derived from the Jolt case. The fixture was not built here.

## Proposed fix (from this package's data)

Scoped to what this package shows. The general fix, and whether it holds for
every wrapped Hub package, arm64, Linux and Windows, is the engine side's call.

1. **Make the bitflag test total.** Do the arithmetic in `Int128`, or in the
   enum's underlying type, instead of `Int64`. Alternatively, return `false`
   for any value outside `typemin(Int64):typemax(Int64)`. That would render
   `EIterationStatus` as a plain enumeration, not a flag set. Either way it
   must never throw. The same applies at `TypeImports.jl:846`.
2. **Back the rendered enum with its DWARF underlying type** (`UInt64` here),
   so `0xffff000000000000` is representable after the check as well. Not
   checked: whether the rendering after `_is_bitflag_enum` already does this.
3. **Contain per-enum failures.** If one enum cannot be rendered, skip it with
   a named warning rather than aborting the module.

Tests this would want:
- the fixture above: wrap completes and `High == 0xffff000000000000`
  round-trips through `take`;
- an Int64-range flag enum: still detected as bitflags, today's behaviour;
- Hub: `packages/jolt` wraps.

**Checked here:** Linux x86-64, Julia 1.13, engine `a875932`, Jolt v5.7.0
built with the recipe in this directory. Build OK in 349 s. Wrap fails at the
frame above. Only one enumerator in `Jolt/` matches `0xffff000000000000`.
**Not checked:**
- whether other Jolt enums have values ≥ 2^63 (the wrap stops at the first);
- why `[wrap] exclude_symbols` does not reach enums (observed: it matched
  nothing; reading `_apply_symbol_filter!` was refused by the Hub's repo gate);
- the rendering path after the bitflag check, arm64, Windows.
