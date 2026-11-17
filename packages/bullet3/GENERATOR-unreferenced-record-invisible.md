# Generator gap: a header-only class no library source mentions is invisible to the build

> **STATUS:** FIXED — RepliBuild.jl #107 (`[types] records`), merged at `ee7e2cf`.
> Verified 2026-11-15 on a cold bullet3 rebuild: the recipe names
> `records = ["btDefaultMotionState"]`, shims/visible_records.cpp is retired,
> the class wraps with its constructor and methods; test.jl 32/32, test_deep 45/45.
> **PACKAGE:** bullet3 3.25 (`2c204c4`)
> **STAGE:** build (DWARF extraction → #105's forced inline constructors)
> **BLOCKS:** any class an application uses but the library's own code never
> mentions. In bullet3: `btDefaultMotionState`, the class upstream's
> HelloWorld and every Bullet application uses to receive a body's pose.
> Without it there is no type, no constructor, no `getWorldTransform`.
> **HUB PIN:** `shims/visible_records.cpp` declares one global
> `btDefaultMotionState *`, which puts the class definition in the DWARF;
> #105 then forces its constructor. `test.jl` asserts the file is among the
> sources and the class is among the emitted rows. Retire the file when the
> build can be told to make a record visible on its own.
> **ENGINE AT:** RepliBuild.jl `f7e843f` (main, #105)

## Symptom

With `shims/inline_ctors.cpp` retired (#105 makes it unnecessary for
`btSphereShape` and `btRigidBodyConstructionInfo`) and nothing in its place, a
cold build of bullet3 at `f7e843f`:

```
ctors: 501 inline constructor(s) of 330 class(es) declared in headers and defined nowhere
```

and in the result, for `btDefaultMotionState`: no `struct_definitions` entry,
no `record_abi` entry, no row in `inline_constructors`, no symbol in the `.so`
(`nm -D | grep -c btDefaultMotionState` → 0), no mention in `Bullet3.jl`.

With the one-line `shims/visible_records.cpp` added:

```
ctors: 502 inline constructor(s) of 331 class(es) …
```

and `btDefaultMotionState_btDefaultMotionState(this, startTrans, centerOfMassOffset)`
wraps, constructs, and works (test_deep's sphere scenario, ObjectSim 94/94).

PR #105's description ran with the old hand-written shim still compiled in,
which is what made the class visible there; its bullet3 numbers include it.

## Why this is not a TOML mistake

The recipe already has `-fstandalone-debug`, and the class's header is
reachable (`btBulletDynamicsCommon.h` includes it, and it is in
`shim_headers`). But debug info, standalone or not, describes types a
translation unit *uses*, and no `.cpp` under LinearMath, BulletCollision or
BulletDynamics uses `btDefaultMotionState`: it is an application convenience
class (`src/LinearMath/btDefaultMotionState.h`, header only). There is no TOML
key that names a record to be made visible: `[types] templates` comes closest,
but its stub writes `template class $t;` (`Compiler.jl:2572`), which is not
valid C++ for a class that is not a template.

## Pipeline stage

- `#105`'s plan reads the constructors a record's DWARF definition declares
  (`record_abi[...]["constructors"]`); a record with no definition in any CU
  has no entry to read. The PR says so ("the pass sees only what some CU's
  DWARF defines").
- `_write_template_tu` (`Compiler.jl:2559-2584`) already emits, per entry,
  `template void replibuild_force::tag<T, N>(T*);`. That line is valid for
  ANY class and is exactly an odr-use that makes T's definition appear. Only
  the `template class $t;` line before it restricts the stub to templates.

## Minimal reproduction

```cpp
// lib.h
struct Used   { Used(int); int v; };          // defined in lib.cpp
struct Unused { Unused(int x) : v(x) {} int v; };   // header-only, used nowhere
// lib.cpp
#include "lib.h"
Used::Used(int x) : v(x) {}
int get(const Used& u) { return u.v; }
```

Expected with `-fstandalone-debug`: `Used` wraps; `Unused` has no metadata
entry and no constructor, and #105 does not plan it. Adding
`Unused *keep;` to any compiled file makes #105 force `Unused::Unused(int)`.
Derived from the bullet3 case; the fixture was not built here.

## Proposed fix (from this package's data)

Scoped to what this package shows. The general fix, and whether it holds for
every wrapped Hub package, arm64, Linux and Windows, is the engine side's call.

1. **A TOML list of records to make visible.** For example
   `[types] records = ["btDefaultMotionState"]` (with `template_headers`, or
   `shim_headers`, supplying the includes). The stub writes, per entry, only
   the existing `template void replibuild_force::tag<T, N>(T*);` line, no
   `template class` line. That odr-uses `T*`, the CU carries T's definition
   under `-fstandalone-debug`, and #105's pass sees its constructors on the
   second extraction like any other record.
2. Or **accept non-template names in `[types] templates`**: write
   `template class $t;` only when `$t` is a template-id (contains `<`). Smaller
   change, but it overloads a key named for templates.
3. **Report a requested record that still has no definition** after the
   build (a typo, a header not included, plain `-g` under constructor homing)
   by name, instead of silently producing nothing.

Tests this would want: the fixture above with `records = ["Unused"]` →
`Unused_Unused` wraps and constructs; without it → absent (today's behaviour);
a misspelled name → named in the report. Hub: `packages/bullet3/test.jl`
drops `shims/visible_records.cpp` and still finds `btDefaultMotionState`
among the emitted rows.

**Checked here:** bullet3 on Linux x86-64, Julia 1.13, LLVM 23, engine
`f7e843f`. Without the file: class absent everywhere (above). With it: 502 rows
planned, 496 emitted, the three HelloWorld constructors exported as `C2`
symbols; bullet3 `test.jl` 21/21, `test_deep.jl` 45/45; ObjectSim (vendored
wrapper) 94/94. **Not checked:**
- how many other bullet3 application classes are in the same position (only
  `btDefaultMotionState` is used by the Hub's code);
- other C++ Hub packages (imgui, box2d, …) for header-only classes nothing in
  their library mentions;
- plain `-g` (constructor homing), arm64, Windows.
