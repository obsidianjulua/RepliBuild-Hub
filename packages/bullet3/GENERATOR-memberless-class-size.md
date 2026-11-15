# Generator gap: a class whose bytes all come from its bases has no size

> **STATUS:** FIXED — RepliBuild.jl #101 (`e276627` "Every defined library
> record has a struct_definitions entry"), verified on a cold bullet3 rebuild
> at `d975de8` (2026-11-15): all 39 classes below now have entries,
> `struct_size(:btBoxShape) == 0x50`, and `btQuaternion` / `btVector4` are
> laid out as `m_floats::NTuple{4,Cfloat}`. test.jl 10/10, test_deep.jl 25/25.
> **PACKAGE:** bullet3 3.25 (`2c204c4`)
> **STAGE:** wrap (DWARF → `struct_definitions` → `STRUCT_SIZES`)
> **BLOCKS:** constructing any such class from Julia without knowing its size
> some other way. 39 Bullet classes, among them `btBoxShape`, `btSphereShape`,
> `btQuaternion`, `btVector4`, `btContactSolverInfo`.
> **HUB PIN:** `test_deep.jl` sizes the box from its base
> (`new_storage(:btPolyhedralConvexShape)`, 0x50) and asserts
> `!haskey(B.STRUCT_SIZES, :btBoxShape)`. Flip both when this is fixed.
> **ENGINE AT:** RepliBuild.jl `d2e3cc2` (v4.5.0)

## Symptom

```julia
julia> B.struct_size(:btBoxShape)
ERROR: struct_size: no layout for btBoxShape. 609 struct(s) known; see STRUCT_SIZES.
```

The wrapper still binds `btBoxShape`'s constructor
(`btBoxShape_btBoxShape(this, halfExtents)`), so it is a constructor whose
storage the caller cannot size. `btSphereShape` and `btQuaternion` are emitted
as `struct btSphereShape end` / `struct btQuaternion end`.

## Why this is not a TOML mistake

The DWARF in `libbullet3.so` has full definitions. They are built with
`-fstandalone-debug` (needed for Bullet's header-only value types), so they
are not declaration stubs:

```
$ llvm-dwarfdump --name=btBoxShape --name=btSphereShape julia/libbullet3.so
DW_TAG_class_type  DW_AT_name ("btBoxShape")    DW_AT_byte_size (0x50)
DW_TAG_class_type  DW_AT_name ("btSphereShape") DW_AT_byte_size (0x48)
```

Nothing in the TOML controls which records get an entry.

## C++ source that produces it

A derived class that adds methods (and virtual overrides) but no data member:

```cpp
// src/BulletCollision/CollisionShapes/btBoxShape.h:27
ATTRIBUTE_ALIGNED16(class) btBoxShape : public btPolyhedralConvexShape
{ public: ... btBoxShape(const btVector3& boxHalfExtents); ... };      // no fields

// src/LinearMath/btQuaternion.h:49
class btQuaternion : public btQuadWord { ... };                       // no fields
```

This is a very common C++ shape: Bullet's `btCapsuleShapeX/Z`, `btConeShapeX/Z`
and `btCylinderShapeX/Z` are the same, and so are policy subclasses and
interface implementations in general.

## Pipeline stage

`src/Builder/Compiler.jl:7463-7473` (read-only):

```julia
# A record with no member of its own has no entry, with one
# exception: a toolchain record whose bytes come from its
# non-virtual bases ... A library record keeps the old rule;
# its Julia type has no fields to give.
from_bases = isempty(resolved_members) && drops_type(type_info) && any(... "inheritance" ...)
if !isempty(resolved_members) || from_bases
```

No entry means no `byte_size` reaches the generator, so `STRUCT_SIZES`
(`src/Wrapper/Utils.jl:2727`) and `struct_size` have nothing for the class.

Full list for this package: 603 `bt*` records have a defining DIE with
`DW_AT_byte_size`, and 39 of them are missing from `struct_definitions`:

```
bt32BitAxisSweep3 btActivatingCollisionAlgorithm btAxisSweep3 btBoxShape
btBroadphasePairSortPredicate btCapsuleShapeX btCapsuleShapeZ
btCharacterControllerInterface btConeShapeX btConeShapeZ btContactArray
btContactSolverInfo btConvexShape btCylinderShapeX btCylinderShapeZ
btEmptyAlgorithm btFixedConstraint btGeometryUtil btGjkEpaPenetrationDepthSolver
btGjkEpaSolver2 btMinkowskiPenetrationDepthSolver btOptimizedBvh
btOverlappingPairCache btPairSet btPersistentManifoldSortPredicate
btPersistentManifoldSortPredicateDeterministic btPlaneShape
btPolyhedralContactClipping btQuaternion btSortConstraintOnIslandPredicate
btSortConstraintOnIslandPredicate2 btSortMultiBodyConstraintOnIslandPredicate
btSphereShape btTaskSchedulerSequential btTetrahedronShapeEx btTransformUtil
btTriangleShapeEx btUnionFindElementSortPredicate btVector4
```

## Minimal reproduction

```cpp
struct Base { float v[4]; virtual ~Base(); };
struct Derived : Base { Derived(float x); float sum() const; };   // no fields
```

Expected after a C++ build and wrap: `struct_size(:Derived)` errors while
`struct_size(:Base)` is 24. **Not run here:** this session cannot build
upstream or fixture code (auto mode blocks it), so the fixture is derived
from the rule at `Compiler.jl:7463` and the 39 Bullet cases, not observed.

## Proposed fix (from this package's data)

Scoped to what this package shows. Whether it holds for every wrapped Hub
package, arm64, Linux and Windows is the engine side's call.

1. **Every defined record gets a size.** At `Compiler.jl:7473`, give a
   library record with no member of its own an entry too: `kind`,
   `byte_size`, `members = []` and its `base_classes`. That is enough for
   `STRUCT_SIZES` and `struct_size`, which are what a caller needs to construct
   one, and it leaves the Julia type as it is today (opaque, with no fields).
2. **Value types laid out from their bases.** For a record whose bases are all
   non-virtual, the layout already exists: it is the bases' members at their
   base offsets. `_promote_toolchain_records!` (`Compiler.jl:8394`) does exactly
   this for `std::tuple`/`std::optional`. Opening it to library records would
   make `btQuaternion` a 16-byte `m_floats::NTuple{4,Cfloat}` like `btVector3`,
   so it can be passed by value. This is the bigger change, and step 1 is
   useful without it.
3. **Generator guard.** A bound constructor whose class has no
   `STRUCT_SIZES` entry is exactly this case, so the wrap report could
   name it (today it is silent).

Tests this would want: the fixture above (`STRUCT_SIZES[:Derived] == 24`, and
with step 2 `fieldoffset(Derived, 1) == 8`), a stateless class (`struct P {
bool operator()(int,int) const; };`, size 1), and a class with a **virtual**
base, which should keep today's behaviour.

**Checked here:** bullet3 only, Linux x86-64, Julia 1.13, clang/LLVM 23, single
precision. Sizing the box from its base and constructing it through the bound
constructor works: the box falls, lands and rests correctly (`test_deep.jl`).
**Not checked:**
- other Hub C++ packages (box2d, imgui, msdfgen, pugixml, tinyxml2, fmt,
  clipper2, onednn, llamacpp) re-wrapped with this change. Their metadata
  would gain entries;
- the effect on the type registry and `type_manifest.json` (graph imports);
- arm64 and Windows (PE/COFF, CodeView vs DWARF);
- virtual and multiple inheritance.
