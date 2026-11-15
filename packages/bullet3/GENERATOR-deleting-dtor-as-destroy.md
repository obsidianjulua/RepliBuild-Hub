# Generator bug: `destroy_` binds the deleting destructor when it is the only one

> **STATUS:** FIXED — RepliBuild.jl #102 (`d933a70` "A deleting destructor is
> `<X>_delete_<X>`, never destroy_"), verified on a cold bullet3 rebuild at
> `d975de8` (2026-11-15): no `destroy_` wrapper binds a D0 symbol any more
> (197 `delete_` wrappers, 166 `destroy_`), and test_deep.jl frees the box
> through `btBoxShape_delete_btBoxShape`. test.jl 10/10, test_deep.jl 25/25.
> **PACKAGE:** bullet3 3.25 (`2c204c4`)
> **STAGE:** wrap (C++ method dedup, destructor variants)
> **BLOCKS:** correct teardown of every bullet3 `destroy_` wrapper bound to a
> D0 symbol; a caller who follows the usual pattern (destroy, then free the
> storage) double-frees. Also present in msdfgen (3), clipper2 (2), tinyxml2
> (2), fmt (1), hello_world (1).
> **CORRECTION (2026-11-15):** the counts first given here (bullet3 93/259,
> box2d 20, and "none in the others") came from a grep that read 16 lines past
> each function, so it also caught the NEXT function's docstring symbol, and it
> scanned only top-level `julia/*.jl`, missing graph packages. Re-counted by
> parsing each function body across every C++ package: msdfgen 3, clipper2 2,
> tinyxml2 2, fmt 1, hello_world 1, box2d **0**. bullet3's pre-fix wrapper was
> removed by the cold rebuild, so 93 is an upper bound, not re-checked.
> **HUB-WIDE AFTER THE FIX (2026-11-15, engine `d975de8`):** all 12 other C++
> packages rebuilt with deps kept; 0 `destroy_` wrappers bind D0 in any of them,
> and every package's tests pass (boostmath 70, box2d 15, clipper2 233,
> hello_world 40, imgui 202, llamacpp 33, msdfgen 26, onednn 141, pugixml 13,
> stl 35, tinyxml2 11; fmt has no tests and loads).
> **HUB PIN:** `test_deep.jl` does not free the box after
> `btBoxShape_destroy_btBoxShape`, and asserts the reason
> (`dlsym_e(lib, :_ZN10btBoxShapeD2Ev) == C_NULL`). Flip when fixed.
> **ENGINE AT:** RepliBuild.jl `d2e3cc2` (v4.5.0)

## Symptom

```julia
B.btBoxShape_destroy_btBoxShape(box)   # binds _ZN10btBoxShapeD0Ev
B.btAlignedFreeInternal(box)           # the storage it came from
```

ends in `signal 6 (-6): Aborted` (glibc double-free check). An earlier run of
the same test instead **hung for 8+ minutes**: every thread asleep on a futex,
a heap left inconsistent by the double free. Before the second free, the 8
bytes in front of the box (Bullet's aligned-allocator header) already held
glibc's free-list key rather than the real block pointer:

```
HDR body  gap=16
HDR box   gap=-102745264      # already freed by D0
HDR plane gap=16
```

The wrapper gives no sign of this. The docstring is the same as for a
non-deleting destructor:

```
btBoxShape_destroy_btBoxShape(this::Any) -> Cvoid
Wrapper for `btBoxShape::~btBoxShape()`
- Mangled symbol: `_ZN10btBoxShapeD0Ev`
```

while its neighbours bind D2 (`btStaticPlaneShape_destroy_…` →
`_ZN18btStaticPlaneShapeD2Ev`, `btRigidBody_destroy_…` → `D2`, …).

## Why this is not a TOML mistake

The library exports what C++ emits. `btBoxShape`'s destructor is implicit, so
the only variant in the `.so` is the deleting one the vtable needs:

```
$ nm -D julia/libbullet3.so | grep -E '_ZN10btBoxShapeD|_ZN18btStaticPlaneShapeD'
0000000000172ce0 W _ZN10btBoxShapeD0Ev
000000000009fc00 T _ZN18btStaticPlaneShapeD0Ev
00000000000a0024 T _ZN18btStaticPlaneShapeD1Ev
00000000000a0024 T _ZN18btStaticPlaneShapeD2Ev
```

## C++ source that produces it

Any polymorphic class without a user-declared destructor whose base has a
virtual one. `src/BulletCollision/CollisionShapes/btBoxShape.h:27` declares
no `~btBoxShape()`, while `btStaticPlaneShape.h:38` declares
`virtual ~btStaticPlaneShape();` and defines it in the `.cpp`.

## Pipeline stage

Read-only references:

- `src/Wrapper/Utils.jl:180` names every destructor `destroy_<X>`, so D0,
  D1 and D2 all map to `<X>_destroy_<X>(this::Any)`.
- `src/Wrapper/Utils.jl:2876-2879` (`_dtor_variant_group`): *"they collapse
  to one Julia method by construction, and dropping the extras is exactly
  right."* That assumes the variants are interchangeable. D0 is not: it also
  frees the object (`operator delete`, here Bullet's `btAlignedFree`).
- `src/Wrapper/Utils.jl:2894` `_dedup_method_chunks` keeps the last
  definition. With D2 present, D2 wins (the 2026-10-26 note at
  `GeneratorCpp.jl:966`); with only D0 present, D0 is the method.
- The finalizer path already knows the difference: `GeneratorCpp.jl:991-993`
  documents a D0 deleter as *"the deleting destructor (C++ `delete`)"*. The
  raw `destroy_` binding does not.

## Minimal reproduction

```cpp
struct Base { virtual ~Base(); int x; };
Base::~Base() {}
struct Derived : Base { Derived(); int y; };   // implicit ~Derived(): only D0 exported
Derived::Derived() : y(2) {}
```

Expected: `Derived_destroy_Derived` binds `_ZN7DerivedD0Ev`, and destroying
then freeing caller storage double-frees. **Not run here:** this session
cannot build fixture code (auto mode blocks it); the expectation comes from
the bullet3 symbols and wrappers above.

## Proposed fix (from this package's data)

Scoped to what this package shows. The general fix, and whether it holds for
every wrapped Hub package, arm64, Linux and Windows, is the engine side's call.

1. **Never bind D0 as `destroy_`.** Where the variant group has no D1/D2,
   name the D0 binding for what it does, e.g. `<X>_delete_<X>`, with a
   docstring saying it runs `~X()` and frees the object through the class's
   `operator delete`, so the object must come from that allocator (`new X`,
   or here `btAlignedAlloc`).
2. **Optionally, keep a non-freeing `destroy_`** for such classes by calling
   the object's own vtable destructor slot (the complete-object destructor sits
   next to D0 in the vtable under the Itanium ABI), so callers have one name
   that never frees. That needs the vtable machinery the vcall path has.
3. **Wrap report line** for each class whose only destructor is D0, so the
   difference is visible when a package is wrapped.

Tests this would want: the fixture above (binding named `delete_`, docstring
says it frees), and a class with an explicit out-of-line destructor that keeps
`destroy_` → D2 (no change). Existing Hub tests that call a D0-bound `destroy_`
would need checking. box2d's `b2World_destroy_b2World` is D2, so its test is
unaffected.

**Checked here:** bullet3 on Linux x86-64, Julia 1.13. Counted D0-bound
`destroy_` wrappers across every Hub wrapper (see the correction above):
msdfgen 3, clipper2 2, tinyxml2 2, fmt 1, hello_world 1, box2d 0, bullet3 at
most 93. No test in those packages calls any of those names (checked
2026-11-15), and all of them pass after the rebuild. **Not checked:**
- the `Managed*` finalizer path, which is documented as choosing D0 on purpose
  and is likely correct;
- arm64 and Windows (MSVC ABI has no D0/D1/D2: scalar/vector deleting
  destructors instead).
