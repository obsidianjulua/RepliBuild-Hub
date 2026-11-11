# Generator bug: AOT thunks.so is missing symbols the wrapper binds

> **STATUS:** CLOSED — class document
> **PACKAGE:** clipper2 2.0.1
> **STAGE:** AOT
> **BLOCKS:** nothing. `aot_thunks = true` stays; the package wraps and its
> `test_deep.jl` is green at 233/233.
> **HUB PIN:** none.
>
> **⚠ RETRACTION — the 2026-08-27 block on this file said `HUB PIN:
> [compile] aot_thunks = false — REQUIRED NOW` and told you to set it as
> GROK ACTION 1. Do NOT do that.** That watermark was written against a
> partial diagnosis: it treated the symptom (wrap binding symbols AOT never
> built) as unfixable and told you to turn AOT off to route around it. The
> real cause was found two days later and fixed in the engine. Turning
> `aot_thunks` off now would drop this package back to a *worse* state than
> before — no AOT thunks at all, rather than seven missing ones.
>
> **FIXED BY:** RepliBuild.jl, two commits:
> - *Refuse to ship a wrapper binding AOT thunks the library lacks* — the
>   wrap-time cross-check (`_assert_aot_thunks_present`). This is what turned
>   the load-time warning into a build stop, and it is how the gap was
>   measured. It does not fix anything by itself.
> - *Route wrapper-bound virtuals to FunctionGen on the AOT path too* — the
>   actual fix. `ThunkBuilder.build_aot_thunks` never passed the thunk
>   manifest into `generate_jlcs_ir`, and `needed_symbols` is not merely
>   dead-thunk elimination — it is what ROUTES a virtual method to the right
>   emitter. Without it every virtual took the legacy vmethod-IR pass, which
>   emits `thunk_<mangled>`: a name no wrapper has looked up since
>   2026-07-17. Now they take the function-thunk pass, which emits
>   `_mlir_ciface_<mangled>_thunk` and `jlcs.vcall`. Second half of the fix:
>   a cold build has no manifest, so `needed_symbols === nothing` now falls
>   back to metadata's function list instead of meaning "no virtual is
>   wrapper-needed" — otherwise the bug reproduced on every fresh package.
>
> **This report's own §"Pipeline stage" was close but not right.** It read the
> split as "AOT runs at build from metadata, wrap runs later" — an ordering
> problem. Both stages read the same `metadata["functions"]`; the divergence
> was one missing argument. Full analysis:
> `docs/updates/2026-08-29-virtual-branch-policy-audit.md` in RepliBuild.jl,
> which also rejected the obvious fix (pointing the wrapper at
> `thunk_<mangled>`) on the grounds that it reverts the 2026-07-17 routing
> decision, loses override-honoring dispatch, and skips the Cstring pair.
>
> **VERIFIED** on this package after John's rebuild:
> - `libclipper2_thunks.so`: 180 `_mlir_ciface_*_thunk`, **0** legacy `thunk__Z*`
> - all seven symbols from *Symptom* now define their ciface thunk
> - `Clipper2.jl`: 157 `invoke_aot_ptr` sites, 0 legacy `:thunk__Z` ccalls
> - live load: `_THUNK_SLOTS` 156 total, **0 unresolved** — the warning in
>   *Symptom* no longer fires
> - `Clipper2Exception::what` now returns `::Union{String,Nothing}` with a
>   `_ptr` sibling; on the legacy path it could not have had the Cstring
>   policy at all
>
> **GROK ACTION:** done 2026-08-29 — confirmed, no TOML change:
> 1. `nm -D --defined-only` → **0** `thunk__Z`, 180 `_mlir_ciface_*_thunk`.
> 2. Load: `_THUNK_SLOTS` 156, **0** unresolved. `Version() == "2.0.1"`.
> 3. `[compile] aot_thunks = true` still set.
> 4. `test_deep.jl` 233/233. HUB.md row dropped from *Resolved*.
>
> **THEN:** keep as class document (this block). The class is worth keeping for two reasons: a
> stage that reads a manifest for one purpose (dead-thunk elimination) while
> that manifest silently carries a second (emitter routing), and a watermark
> that prescribed a workaround before the root cause was known. The second is
> a lesson about this protocol, not about clipper2.
>
> **Still open and unrelated:** `GENERATOR-header-inline-api.md`. Resolving
> these thunks makes the seven callable; it does not create
> `Clipper64::AddSubject`, which no TU ever emitted. The class API is still a
> skeleton for that separate reason.

Triggered while wrapping **Clipper2 2.0.1** with `[compile] aot_thunks = true`.
The package TOML is not the cause. Rebuild after wrap still leaves the gap.

## Symptom

Loading `Clipper2.jl` prints:

```
┌ Warning: AOT thunks missing from the thunks library — calling any of these will raise.
│   _mlir_ciface__ZN11Clipper2Lib10PolyPath645ClearEv_thunk
│   _mlir_ciface__ZN11Clipper2Lib10PolyPath648AddChildERKSt6vectorINS_5PointIlEESaIS3_EE_thunk
│   _mlir_ciface__ZN11Clipper2Lib9PolyPathD5ClearEv_thunk
│   _mlir_ciface__ZN11Clipper2Lib9PolyPathD8AddChildERKSt6vectorINS_5PointIlEESaIS3_EE_thunk
│   _mlir_ciface__ZNK11Clipper2Lib10PolyPath645CountEv_thunk
│   _mlir_ciface__ZNK11Clipper2Lib17Clipper2Exception4whatEv_thunk
│   _mlir_ciface__ZNK11Clipper2Lib9PolyPathD5CountEv_thunk
│   library = "…/julia/libclipper2_thunks.so"
│   count = 7
```

The wrapper still emits `invoke_aot_ptr` call sites for those seven. Calling
any of them is a hard error, not a JIT fallback. The C ABI (`BooleanOp64`,
`Version`, …) is `ccall` into `libclipper2.so` and is unaffected.

First wrap (library TUs only, no `export_tu.cpp`) reported **count = 1**
(`Clipper2Exception::what`). Adding the export TU, which constructs
`PolyTree64` / `PolyPath64` from header-inline methods, grew the list to 7.
So the missing set tracks **header-inline methods that became symbols in a
later TU**, not a one-off.

`nm -D` on `libclipper2_thunks.so` has none of those `_mlir_ciface_*_thunk`
names. `nm -D` on `libclipper2.so` **does** define the underlying
`Clipper2Lib::PolyPath64::Clear` / `Count` / `AddChild` / `what`.

## Why this is not a TOML mistake

- `aot_thunks = true` is the documented switch. Build printed
  `aot: libclipper2_thunks.so (153.6 KB) in 2.99s` — AOT ran and claimed
  success.
- A wrap-only after that build does not regenerate thunks. A full
  `build` then `wrap` in the same process still warns. Not stale artifacts.
- These methods are real C++ virtuals/inlines with symbols in the .so.
  The wrapper is right to bind them. The thunks library is a subset of
  what wrap later emits.

Wrap also printed `dag-diff: 62 mismatches (12 types, 0 functions), 12 thunk sites`
on both wraps. The 12 thunk sites vs 7 missing is the same neighbourhood
(layout-unproven types used as thunk arguments).

## Pipeline stage

`ThunkBuilder` during `RepliBuild.build` (AOT) vs `GeneratorCpp` during
`RepliBuild.wrap`. Two derivations of the thunk set; they disagree.

AOT runs at **build**, from compilation metadata. Wrap runs later and
binds every remaining C++ method that `is_ccall_safe` rejects. Header-inline
methods that only exist because a later TU instantiated them (or that
DWARF describes as inlined-but-emitted) can appear in wrap's list and
miss AOT's.

## What I tried

- `aot_thunks = true` (required).
- Rebuild after adding `src/export_tu.cpp`. Gap grew 1 → 7, did not close.
- Did not call the seven in tests; the C ABI is the package's supported
  surface.

## Suggested fix (not applied)

One derivation: wrap should be the source of the thunk name list, or AOT
should run *after* wrap's method list is known. A missing AOT symbol must
either (a) demote that call site to JIT (`invoke` not `invoke_aot_ptr`)
or (b) fail wrap/build loudly. A load-time warning plus a raising call
site is the silent-wrong-until-you-touch-it class.

The `Exception::what` miss is independently a `char*` return on a C++
method (Tier 2) — confirm it goes through `_cstring_wrapper_pair`. The
wrapper already has `what()::Union{String,Nothing}` plus `_ptr`.

## Environment

- Julia 1.12.7, system Clang/LLVM 22.1.8, `libJLCS.so` present
- RepliBuild 3.3.3
- `check_environment()` green for Tier 2/3
- First seen 2026-08-27, `packages/clipper2` 2.0.1
