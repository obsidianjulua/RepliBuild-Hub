# Generator gap: a fragment header in the forced unit declines every row after it

> **STATUS:** OPEN
> **PACKAGE:** jolt 5.7.0 (`cf16769`)
> **STAGE:** build (#105/#108 forced constructors and member functions,
> the probe loop at `src/Builder/Compiler.jl:3728`)
> **BLOCKS:** with upstream's default CPU compute backend, 1,944 of Jolt's
> header-only constructors, among them every one HelloWorld needs:
> `SphereShape(float, const PhysicsMaterial*)`,
> `BoxShape(Vec3, float, const PhysicsMaterial*)`,
> `BodyCreationSettings(const Shape*, RVec3, Quat, EMotionType, ObjectLayer)`,
> `TempAllocatorImpl(size_t)`, and the three layer-table classes.
> **HUB PIN (workaround in place):** the recipe leaves out the CPU compute
> backend (`exclude` gains `Jolt/Compute/CPU/`,
> `Jolt/Shaders/HairWrapper.cpp`, `Jolt/Shaders/TestComputeWrapper.cpp`, and
> `-DJPH_USE_CPU_COMPUTE` is dropped). Linux then has no compute backend, which
> only Jolt's Hair simulation uses. **To retire:** remove those three entries
> and restore `-DJPH_USE_CPU_COMPUTE`, rebuild cold. `test.jl` then still has to
> find the HelloWorld constructors among the emitted rows.
> **ENGINE AT:** RepliBuild.jl `a875932` (main, #111)

## Symptom

A cold build with `-DJPH_USE_CPU_COMPUTE` and Compute/CPU compiled. From
`compilation_metadata.json`, `inline_constructors.skipped`, grouped by reason:

```
1944  does not compile: no member named X in namespace 'JPH::ShaderWrappers::JPH'
  24  does not compile: 'HLSLToCPP' is not a class, namespace, or enumeration
   5  does not compile: 'JobSystem' is not a class, namespace, or enumeration
   3  does not compile: incomplete type 'JPH::ShaderWrappers::JPH::ConvexShape' …
   3  does not compile: 'PhysicsUpdateContext' is not a class, namespace, …
   2  does not compile: no member named X in namespace 'JPH::ShaderWrappers::std'
```

For example:
`SphereShape _ZN3JPH11SphereShapeC4EfPKNS_15PhysicsMaterialE does not compile:
no member named 'SphereShape' in namespace 'JPH::ShaderWrappers::JPH'`.
There is no namespace `JPH::ShaderWrappers::JPH` in Jolt. The final
`replibuild_ctors.cpp` no longer includes the culprit, because every row that
needed it was dropped too. So the unit left on disk compiles, and a probe with
its include list and `new JPH::SphereShape(1.0f)` compiles cleanly.

## Source

`Jolt/Compute/CPU/WrapShaderBegin.h` is not a self-contained header. It is
the first half of a pair that `Jolt/Shaders/HairWrapper.cpp` and
`TestComputeWrapper.cpp` include around each `.hlsl`:

```cpp
#include <Jolt/Compute/CPU/WrapShaderBegin.h>   // JPH_NAMESPACE_BEGIN
#include "HairTeleport.hlsl"                    //   namespace ShaderWrappers {
#include <Jolt/Compute/CPU/WrapShaderBindings.h>//     class …ShaderWrapper : … {
#include "HairTeleportBindings.h"
#include <Jolt/Compute/CPU/WrapShaderEnd.h>     // closes all three
```

Each `…ShaderWrapper` class's DWARF `decl_file` is `WrapShaderBegin.h`, so a
row for one of them lists that header. In the forced unit, everything
`#include`d after it sits inside `JPH::ShaderWrappers::<class>`, and every
following `JPH::Name` resolves against the wrong `JPH`. Confirmed here: the
final unit's include list plus `#include "Jolt/Compute/CPU/WrapShaderBegin.h"`
gives `expected '}'` at end of file. Before end of file, it gives the
"no member named … in namespace 'JPH::ShaderWrappers::JPH'" errors on the
rows that follow.

## Why this is not a TOML mistake

The recipe follows upstream's defaults (`JPH_USE_CPU_COMPUTE` is ON in
`Build/CMakeLists.txt`). No recipe key keeps one header out of the forced
unit, or keeps a class's rows out of the pass. `[wrap] exclude_symbols` acts at
wrap time, and this happens at build time.

## Pipeline stage

`src/Builder/Compiler.jl`, the probe loop:

- `3728-3750`: each round compiles the whole unit and attributes every error
  line to the row on that line (`_unit_bad_lines` → `_unit_row_of_line`). The
  leaked namespace puts the errors on the lines of innocent rows, so they are
  attributed there and dropped as "does not compile: …", round after round.
- `3753-3772`: the check that would catch this ("No row is named: a header
  does not compile on its own. Each header alone…", which then drops rows
  whose header fails) only runs when a round names no row. Here every round
  names rows, so it is reached only after the cascade has removed them, if
  at all.

## Minimal reproduction

```cpp
// lib.h
namespace N { struct A { A(int x) : v(x) {} int v; }; }
// open.h: a fragment, like WrapShaderBegin.h
namespace N { namespace Inner { struct W { W(int) {} 
// close.h
}; } }
// lib.cpp
#include "lib.h"
#include "open.h"
#include "close.h"
int use(N::A *a) { return a->v; }
```

Expected at `a875932` (with `-fstandalone-debug`):
- `Inner::W`'s row lists `open.h`;
- in the forced unit, `N::A::A(int)` fails as "no member named 'A' in
  namespace 'N::Inner::N'" (or similar), and is declined though it is fine.

Derived from the Jolt case. The fixture was not built here.

## Proposed fix (from this package's data)

Scoped to what this package shows. The general fix, and whether it holds for
every wrapped Hub package, arm64, Linux and Windows, is the engine side's call.

1. **Check each header alone before the first whole-unit round**, not only
   after a round that names no row. Do it once per distinct header, in
   parallel, as stage 1 already does. A header that does not compile alone
   (here: `expected '}'` at end of file) never enters the unit. Its rows are
   declined with "its header does not compile on its own", which is the
   accurate reason.
2. **Or check the include block by itself first**: compile the unit's
   `#include` lines with no rows. If that fails, the problem is a header, not
   a row, so go to the per-header check.
3. **Treat a diagnostic naming a namespace the library never declares**
   (`JPH::ShaderWrappers::JPH`) as a sign of a header problem, not a row
   problem. This is weaker than 1 or 2, so it is listed last.

Tests this would want:
- the fixture above: `N::A::A(int)` is forced and emitted, and `Inner::W`'s
  rows are declined for their header;
- Hub: `packages/jolt` with the CPU compute lines restored, where `test.jl`
  finds SphereShape/BoxShape/BodyCreationSettings/TempAllocatorImpl among the
  emitted rows.

**Checked here:** Linux x86-64, Julia 1.13, engine `a875932`, Jolt v5.7.0.
1,944 rows were declined for the leaked namespace with CPU compute on. The
probe above reproduces the leak with the culprit header added to the final
unit's includes.
**Not checked:**
- whether stage 1 would have caught `WrapShaderBegin.h` had it run first.
  It should fail alone (an unclosed namespace), but that was not run through
  the engine;
- other Hub packages with begin/end header pairs;
- the 55+ "cannot be spelled in C++" rows (function-local types). Those look
  correct and are unrelated.
