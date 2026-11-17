# Generator gap: a record that is one 16-byte SIMD vector cannot cross by value

> **STATUS:** OPEN
> **PACKAGE:** jolt 5.7.0 (`cf16769`)
> **STAGE:** wrap (SysV record classification → FunctionGen trap)
> **BLOCKS:** about 1,000 Jolt functions are emitted as "ABI Safety Trap"
> stubs. Counted in `Jolt.jl` (first parameter or return named per trap):
> 592 take `const Vec3`, 149 return `Vec3`, 77 take `Vec3`, 37 take
> `const Quat`, 34/33 take/return `Vec4`, 30 return `Quat`, 22/18 `UVec4`,
> 7 `BVec16`. In practice that is all of Jolt's math-facing API:
> `BodyInterface::GetCenterOfMassPosition/GetLinearVelocity/SetLinearVelocity/
> AddForce/…`, `PhysicsSystem::SetGravity`, `BoxShape(Vec3, …)`,
> `BodyCreationSettings(shape, RVec3, Quat, …)`, `Quat::sIdentity()`, and
> every `Vec3`/`Quat`/`Mat44` operator. (The 657 `align_val_t` traps are the
> aligned `operator new`/`delete` overloads, a separate and harmless case.)
> **HUB PIN (workaround in place):** `shims/jolt_hub.cpp` (`[compile]
> source_files`) forwards the HelloWorld set and the everyday
> BodyInterface/PhysicsSystem vector calls by reference, wrapped as
> `JoltHub_*`. **To retire:** delete the by-value section of the shim (keep
> or drop its `Factory_New`/`RegisterTypes` part separately), point
> test_deep.jl at the upstream names, rebuild cold.
> **ENGINE AT:** RepliBuild.jl `a875932` (main, #111)

## Symptom

```julia
function JPH_BodyInterface_GetCenterOfMassPosition(this::Any, inBodyID::Any)
    Base.error("ABI Safety Trap: cannot call 'JPH_BodyInterface_GetCenterOfMassPosition'
      (...). It returns `Vec3` by value, which a thunk cannot pass the way SysV does
      (Vec3_anon1.mValue: a 16-byte SIMD vector, which SysV passes in one SSE register
      (SSE, SSEUP) that no call statement states), so no thunk could call it. Keep the
      function out with [wrap] exclude_symbols, or wrap a shim that takes the record by
      pointer or returns a `double`.")
```

(Quoted from the generated `Jolt.jl`, reflowed.)

## Source

`Jolt/Math/Vec3.h`, and the same pattern in `Vec4`, `Quat`, `UVec4`:

```cpp
class [[nodiscard]] alignas(JPH_VECTOR_ALIGNMENT) Vec3
{
    ...
    union { Type mValue; float mF32[4]; };   // Type = __m128 on x86-64
};
using Vec3Arg = const Vec3;                  // by value on SysV
```

On x86-64 SysV, clang passes and returns such a class as one `<4 x float>`
in an XMM register (eightbytes SSE, SSEUP). This is Jolt's whole calling
convention for math types. It is by design and documented upstream (`Vec3Arg`
is a value on every platform except Win32 x86).

## Why this is not a TOML mistake

Nothing in the recipe chooses how `Vec3` crosses. `JPH_DOUBLE_PRECISION` would
only make `RVec3` a `DVec3` (`__m256d`, worse). Turning off SSE is not an
option on x86-64, where Jolt requires at least SSE2 and `__m128`. The trap
text itself proposes the shim the Hub now carries.

## Pipeline stage

- `src/IRGen/ir_gen/SysVRecordABI.jl:31-35`: "16 bytes are one SSE register
  (SSE, SSEUP), which no call statement states, so the record is
  `:unstated`."
- `src/Wrapper/DispatchLogic.jl:159-178`: a record that `holds_vector` takes
  the thunk path, and FunctionGen then traps `:unstated`.
- The Tier-2 thunks are AOT-compiled here (`aot_thunks = true`) into
  `libjolt_thunks.so`.

## Minimal reproduction

```cpp
// lib.h
#include <immintrin.h>
struct alignas(16) V { union { __m128 m; float f[4]; }; };
V    add(V a, V b);     // by value both ways, as Jolt's Vec3Arg
float x(V a);
// lib.cpp
#include "lib.h"
V add(V a, V b) { V r; r.m = _mm_add_ps(a.m, b.m); return r; }
float x(V a) { return a.f[0]; }
```

Expected at `a875932`: both `add` and `x` are ABI Safety Traps. Derived from
the Jolt case. The fixture was not built here.

## Proposed fix (from this package's data)

Scoped to what this package shows. The general fix, and whether it holds for
every wrapped Hub package, arm64, Linux and Windows, is the engine side's call.

1. **State the SSE+SSEUP case as clang does.** When a record of 16 bytes
   classifies as (SSE, SSEUP) because it holds one 16-byte vector, coerce the
   thunk's parameter or return to that vector type: `<4 x float>` for
   `__m128`, `<2 x double>` for `__m128d`, `<2 x i64>` for `__m128i`. Pick the
   element type from the vector member's DWARF lane type. That is the
   "call statement" the comment says is missing: LLVM passes a vector argument
   in one XMM register under the C calling convention, and returns one in
   xmm0. Julia keeps passing the 16 bytes as it does now (the tuple of lanes,
   or `NTuple{16,UInt8}` for the union), and the thunk reinterprets them.
2. **Keep the >16-byte case trapped** (`DVec3`/`__m256d` with
   `JPH_DOUBLE_PRECISION`). Whether it goes in a YMM register depends on
   `-mavx`, as the comment says. The recipe's flags do state it here
   (`-mavx2`), but that is a separate step.
3. The `align_val_t` traps (657) need nothing for Jolt: those are allocator
   overloads, and the plain `operator new(size_t)` forms are wrapped.

Tests this would want:
- the fixture above: `add` round-trips four lanes and `x` returns lane 0;
- a `{float; float; float; float}` struct without a vector: still SSE,SSE,
  unchanged;
- Hub: jolt's test_deep with the shim's by-value section deleted, calling
  `JPH_BodyInterface_GetCenterOfMassPosition` etc. directly, gives the same
  bit-for-bit trajectory as the C++ reference.

**Checked here:** Linux x86-64, Julia 1.13, engine `a875932`, Jolt v5.7.0 built
`-mavx2 -mfma`. Trap counts are from the generated `Jolt.jl`.
**Not checked:**
- whether the AOT thunk compiler accepts a `<4 x float>` signature
  (proposal 1 assumes it does);
- arm64 (AAPCS64 HFA/HVA rules) and Win64 (vectors by reference);
- other Hub packages exposing `__m128` records (none known).
