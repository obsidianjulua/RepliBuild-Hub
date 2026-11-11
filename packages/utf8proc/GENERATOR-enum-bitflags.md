# Generator / missing feature: C bitflag enums wrap as closed Julia `@enum`

> **STATUS:** CLOSED — class document
> **PACKAGE:** utf8proc 2.11.3
> **STAGE:** wrap
> **BLOCKS:** nothing. `utf8proc_map` / `utf8proc_decompose` now take combined flags.
> **HUB PIN:** none
>
> **FIXED BY:** RepliBuild.jl `d74eb12` — *Emit C bitflag enums as integer
> aliases, not closed `@enum`s*. The report's diagnosis was correct in full and
> its first suggested shape (integer alias + named constants) was taken, for a
> reason the report did not have: nothing downstream needs to change. `Ptr{T}`
> in a blob accessor, a `ccall` argument typed `T`, `_defined_type_names` and
> the `export` collector all already handle a `const` alias, so widening the
> call sites — the report's second option — would have been the larger change.
>
> **VERIFIED:** this report's own negative check, run verbatim after re-wrapping
> (cache `project_hash` cleared first, since an engine edit does not invalidate
> the package cache). `utf8proc_option_t(11)` constructs; `utf8proc_map` returns
> `n == 2` and `"é"`; the bare `NULLTERM|STABLE|COMPOSE` works and is a `UInt32`;
> single flags and the NFC/NFD/NFKC path are unaffected. `test_deep` 211/211.
>
> **DETECTION, and the one rule worth knowing about.** A bitflag is recognised
> by four rules — ≥3 distinct single-bit members, no contiguous runs, every
> value spelled only in declared bits, no negatives — plus **bit density**, at
> least half the positions between the lowest and highest single-bit member
> being members themselves. Density is what rejects libstdc++'s `_Ios_Seekdir`
> (`{0,1,2,65536}`), which passes all four other tests. Measured across all 544
> `@enum`s in the shipped Hub wrappers: **59 reclassify, 485 unchanged**, and
> density accounts for 5 of the 64 the other rules alone would have taken.
>
> **NOT DONE HERE:** no Hub sweep. Every other package keeps its closed `@enum`s
> until re-wrapped — imgui (42), llamacpp (5), pugixml (3), miniaudio (3),
> box2d3 (3), blake3 (2), curl, miniz, clipper2, argon2, zstd (1 each).

Triggered while wrapping **utf8proc 2.11.3**. Not a bad TOML. The library's
option parameter is a `typedef enum` of orthogonal bits that C callers OR
together. The wrapper emits a Julia `@enum`, which rejects any value that
is not a named member — so the documented way to request NFC (NULLTERM |
STABLE | COMPOSE = 11) cannot be constructed on the Julia side.

## Symptom

`utf8proc_option_t` is emitted as:

```julia
@enum utf8proc_option_t::Cuint begin
    UTF8PROC_NULLTERM = 1
    UTF8PROC_STABLE = 2
    UTF8PROC_COMPAT = 4
    UTF8PROC_COMPOSE = 8
    UTF8PROC_DECOMPOSE = 16
    # ...
    UTF8PROC_NLF2LF = 384   # the header's own OR, so this one IS a member
end
```

and `utf8proc_map` takes that type:

```julia
function utf8proc_map(str::Any, strlen::Cptrdiff_t, dstptr::Any,
                      options::utf8proc_option_t)::Cptrdiff_t
    ccall((:utf8proc_map, LIBRARY_PATH), Cptrdiff_t,
          (Ptr{UInt8}, Cptrdiff_t, Ptr{Ptr{UInt8}}, utf8proc_option_t,),
          str, strlen, dstptr, options)
end
```

The documented NFC flags cannot be passed:

```julia
julia> combined = UInt32(UTF8PROC_NULLTERM) | UInt32(UTF8PROC_STABLE) | UInt32(UTF8PROC_COMPOSE)
11
julia> utf8proc_option_t(combined)
ERROR: ArgumentError: invalid value for Enum utf8proc_option_t: 11
```

`utf8proc_NFC("e\u0301")` still returns `"é"` — that path never takes an
options argument. `test_deep.jl` covers NFC/NFD/NFKC/casefold that way.
`utf8proc_map` with a *single* named flag (e.g. `UTF8PROC_NULLTERM` alone)
would type-check; any real normalisation needs at least two bits.

## Why this is not a TOML mistake

- The header really is a `typedef enum`, not `#define`s. `[wrap.macros]`
  cannot redeclare the members; they already exist as DWARF enumerators.
- There is no TOML knob for "this enum is a bitmask." `allow_unknown_enums`
  is about missing enumerators, not about ORing known ones.
- The convenience functions (`utf8proc_NFC` etc.) are the library's own
  answer for the four common combinations. They do not cover
  `utf8proc_map(..., UTF8PROC_CHARBOUND | UTF8PROC_COMPOSE)` or a custom
  `utf8proc_decompose` option set — those are the public API.

This is the C dual of "macros do not survive compilation": the *values*
survive as enumerators, the *algebra* (OR of two named members) does not
survive Julia's closed `@enum`.

## C/C++ source or IR that produces it

From `utf8proc.h`:

```c
typedef enum {
  UTF8PROC_NULLTERM  = (1<<0),
  UTF8PROC_STABLE    = (1<<1),
  UTF8PROC_COMPAT    = (1<<2),
  UTF8PROC_COMPOSE   = (1<<3),
  UTF8PROC_DECOMPOSE = (1<<4),
  /* ... */
  UTF8PROC_NLF2LF    = (UTF8PROC_NLF2LS | UTF8PROC_NLF2PS),
} utf8proc_option_t;

UTF8PROC_DLLEXPORT utf8proc_ssize_t utf8proc_map(
  const utf8proc_uint8_t *str, utf8proc_ssize_t strlen,
  utf8proc_uint8_t **dstptr, utf8proc_option_t options);
```

NFC in the library is `utf8proc_map(str, 0, &retval, NULLTERM | STABLE | COMPOSE)`.
That call is inside `utf8proc_NFC`, so it never has to cross the wrapper.

## Pipeline stage

wrap — DWARF has the enumerators; the C generator emits `@enum` + a typed
`ccall` parameter. Load succeeds. The failure is at the Julia call site
when the caller tries to form a legal C value that is not a named member.

## What I tried

- `[wrap.macros]` for the option bits — redundant with the enum, and would
  not change the `utf8proc_map` parameter type.
- Constructing `utf8proc_option_t(11)` — `ArgumentError` as above.
- Calling `utf8proc_NFC` / `utf8proc_NFD` / `utf8proc_NFKC` /
  `utf8proc_NFKC_Casefold` — these work and are what `test_deep.jl` uses.
  They are a subset of the option space, not a substitute for `utf8proc_map`.

A Hub-side `reinterpret(utf8proc_option_t, UInt32(11))` would punch through
the closed enum. That is a generator dodge, not a library choice.

## Suggested fix, not applied

Treat a C enum as a bitflag when every enumerator is a power of two (or an
explicit OR of other enumerators, like `UTF8PROC_NLF2LF`). Emit:

- `primitive type` / `Cuint` alias, plus named constants, **or**
- `@enum` plus a `Base.cconvert` / constructor that accepts any `Integer`
  (not just named members),

and type the `ccall` parameter as that integer-compatible type.

Negative check: wrap utf8proc, then

```julia
opts = utf8proc_option_t(UInt32(UTF8PROC_NULLTERM) | UInt32(UTF8PROC_STABLE) | UInt32(UTF8PROC_COMPOSE))
dst = Ref{Ptr{UInt8}}(C_NULL)
n = utf8proc_map("e\u0301", Cptrdiff_t(0), dst, opts)
```

must return `n == 2` and `unsafe_string(dst[]) == "é"` (then `Libc.free`).
Today the first line throws. Single-flag values (`UTF8PROC_NULLTERM`) and
the convenience functions must keep working.

## Environment

- Julia 1.12.7
- RepliBuild.jl 3.3.4 (sibling clone)
- system clang 22.1.8, libLLVM 22.1.8 (also 18/20 present)
- wrap of `packages/utf8proc` at utf8proc v2.11.3 / `e5e799221b45`
