# Generator / missing feature: header-inline C++ API is not a wrap surface

> **STATUS:** OPEN
> **PACKAGE:** clipper2 2.0.1
> **STAGE:** wrap
> **BLOCKS:** class API (`Clipper64` ctor / `AddSubject` / `Intersect` never emitted)
> **HUB PIN:** `src/export_tu.cpp` — compiles `clipper.export.h`, the library's own C ABI. Not a generator dodge; it is how non-C++ consumers are supposed to call Clipper2.

Triggered while wrapping **Clipper2 2.0.1**. Not a bad TOML. The library's
*documented* C++ API is mostly header-inline; the .so only contains the
out-of-line engine. RepliBuild wraps what is in DWARF of the compiled
binary, so that API is absent.

The package is still useful: `src/export_tu.cpp` compiles
`clipper.export.h`, which is Clipper2's own language-agnostic ABI
(`BooleanOp64`, `InflatePaths64`, `Version`). Tests use that. This report
is about the C++ class API a caller of `clipper.h` would expect.

## Symptom

After a successful build+wrap of the four library TUs:

| Expected (clipper.h / clipper.engine.h) | In the wrapper |
|---|---|
| `Clipper64` with ClipperBase layout | `struct Clipper64 end` (0-byte opaque stub) |
| `Clipper64()` default constructor | **no symbol** in `nm -D` of the .so |
| `Clipper64::AddSubject(const Paths64&)` | **no symbol** — header-inline, never emitted |
| `Clipper64::AddClip` / `AddOpenSubject` | same |
| `Intersect` / `Union` / `Difference` / `Xor` | same — `inline` in `clipper.h` |
| `Clipper64::Execute(...)` | wrapped (`W` symbol, header-inline but emitted because a TU called it) |
| `Clipper64::~Clipper64` | wrapped |
| `ClipperBase::AddPaths` (protected) | wrapped — the only way to add geometry, and it takes `Any` (the `std::vector` of paths) |

`[types] templates` for `std::vector<Clipper2Lib::Point64>` and
`vector<vector<…>>` did **not** produce `CppVector` types in the wrapper.
Path arguments are `Any`. Point64 itself wrapped as `Point_long` with
proven `x,y` layout (16 bytes) — that half worked.

There is no `ManagedClipper64`. Zero-initializing the empty Julia struct
and passing it as `this` would be a 0-byte object against a ~256-byte
C++ instance (ClipperBase size). Not attempted.

## Why this is not a TOML mistake

- The four `CPP/Clipper2Lib/src/*.cpp` files are the library. They implement
  the engine; they do not construct a `Clipper64` at namespace scope, so
  the implicit constructor is never codegen'd. Users construct it in *their*
  TU, against the header.
- `AddSubject` is:

  ```cpp
  void AddSubject(const Paths64& subjects)
  {
      AddPaths(subjects, PathType::Subject, false);
  }
  ```

  inline in the class body. No `.cpp` takes its address. It is not a
  dynamic symbol. DWARF of the .so cannot recover a function that was
  never compiled.
- Templates in the TOML forced instantiations of the vector types (a
  `replibuild_templates.cpp` TU was compiled — 6 sources vs 4 library
  TUs + export). That did not promote path parameters off `Any`.

This is the C++ dual of "macros do not survive compilation." Header-inline
methods and implicit constructors do not survive unless some TU emits them.

## What I tried

- `[types] templates` + `template_headers` for Path64/Paths64.
- `-fstandalone-debug` — recovered `Point_long` / `Rect_long`, not Clipper64.
- `aot_thunks = true` — thunks exist for the out-of-line methods.
- Added `src/export_tu.cpp` including `clipper.export.h`. That is the
  **library's** answer for non-C++ consumers; it does not emit `AddSubject`
  as a standalone symbol either (the inlines are called from BooleanOp64
  and folded).

A Hub-side stub that does `Clipper64 c; c.AddSubject(p);` would force
those symbols. That is the same job `[types] templates` already does for
STL, applied to methods. Doing it by hand in every C++ package is the
workaround that belongs in the generator.

## Suggested fix (not applied)

A `[wrap] instantiate` (or an extension of `[types] templates`) that
writes a stub TU taking addresses / calling:

- default/copy/move constructors of named classes
- named methods, even if they are inline in the header

Once they exist as symbols with DWARF, the rest of the pipeline already
wraps them (Execute, destructor, AddPaths prove that).

Until then, C++ libraries whose public API is header-inline need an
`extern "C"` export header (Clipper2 has one; many do not) or they wrap
as an unusable class skeleton plus internals.

## Environment

- Julia 1.12.7, Clang/LLVM 22.1.8, RepliBuild 3.3.3
- First seen 2026-08-27, `packages/clipper2` 2.0.1
