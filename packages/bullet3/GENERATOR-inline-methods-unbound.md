# Generator gap: header-inline member functions have no binding unless the library happens to emit them

> **STATUS:** FIXED — RepliBuild.jl #108 (the build defines declared-but-undefined
> inline member functions), merged at `ee7e2cf`. Verified 2026-11-15 on a cold
> bullet3 rebuild: 2009 inline methods of 190 classes forced and emitted, every
> method in the table below now bound (C++ default arguments still are not:
> `setLimit` takes all five); test.jl asserts eight of the symbols. ObjectSim's
> field-write stand-ins are replaced by the real calls (222 tests pass).
> **PACKAGE:** bullet3 3.25 (`2c204c4`), wrapper built 2026-11-15 17:41
> **STAGE:** build (which inline definitions get emitted) → wrap
> **BLOCKS:** the everyday rigid-body API. Velocities, impulses, forces,
> friction, activation state, hinge limits and motors, constraint breaking,
> picking. Callers fall back to writing fields at DWARF offsets
> (`member_offset`), which works but re-implements each method's body.
> **RELATED:** RepliBuild.jl #105 forces header-only *constructors* (this is
> the same problem for ordinary methods); `packages/clipper2/GENERATOR-header-inline-api.md`
> (OPEN) is the same gap seen from Clipper2's class API.
> **HUB PIN:** none. `examples/ObjectSim/src/physics.jl` does field writes for
> the methods it needs, each next to a comment naming the method it stands for.
> **ENGINE AT:** RepliBuild.jl `f7e843f` (main, #105), as of the last bullet3 build.

## Symptom

```julia
include("packages/bullet3/julia/Bullet3.jl"); import .Bullet3 as B
isdefined(B, :btRigidBody_applyCentralImpulse)   # false
isdefined(B, :btRigidBody_setLinearVelocity)     # false
isdefined(B, :btCollisionObject_getWorldTransform)  # true  — also inline
```

Whether an inline method is bound depends only on whether some library `.cpp`
odr-uses it, so that the compiler emits a weak copy that DWARF then describes:

```
$ nm -D --defined-only julia/libbullet3.so | grep -E 'getWorldTransformEv|applyCentralImpulse|17setLinearVelocity'
00000000001cfba8 W _ZNK17btCollisionObject17getWorldTransformEv     # emitted: a TU calls it
                                                                      # applyCentralImpulse, setLinearVelocity: absent
```

`btRigidBody.h:319` `void applyCentralImpulse(const btVector3&)` and
`btRigidBody.h:442` `inline void setLinearVelocity(const btVector3&)` are
defined in the class body, and nothing in `src/` calls them.

## Missing, checked one by one (all header-inline, none bound)

| Class | Methods |
|---|---|
| `btRigidBody` | `applyCentralImpulse`, `applyImpulse`, `applyTorqueImpulse`, `applyCentralForce`, `setLinearVelocity`, `setAngularVelocity`, `getLinearVelocity`, `getInvMass`, `getCenterOfMassTransform` |
| `btCollisionObject` | `setFriction`, `setRestitution`, `getActivationState`, `isActive` |
| `btTypedConstraint` | `setBreakingImpulseThreshold`, `isEnabled`, `getAppliedImpulse` |
| `btHingeConstraint` | `setLimit`, `enableAngularMotor` |
| `btSliderConstraint` | `setLowerLinLimit` (and the other limit setters), `setPoweredLinMotor` |
| `btPoint2PointConstraint` | `setPivotB` |
| `btCollisionWorld::RayResultCallback` | `hasHit` |
| `btTransform` | `inverse`, `getOrigin` |

Bound although inline (emitted by some TU): `btCollisionObject_getWorldTransform`,
`btHingeConstraint_getHingeAngle` (out of line), `btVector3_cross`,
`btDiscreteDynamicsWorld_getNumConstraints`.

## What the fix looks like

The same move as #105, extended from constructors to methods: for each
record the wrap surface covers, force the emission of every inline member
function the class declares and the library does not define (an explicit
instantiation-style TU that takes each member's address, or `-fkeep-inline-functions`
scoped to the library's own headers), so they land in the `.so` and in DWARF
and wrap like any other method.

Questions for the engine side, not answered here:
- scope: every inline method of every wrapped record (bullet3 alone has
  thousands; the size cost is real), or an opt-in list in the recipe
  (`[wrap] inline_methods = ["btRigidBody", …]`)?
- templates and `SIMD_FORCE_INLINE` members (`btVector3` operators) — whether
  `__attribute__((always_inline))` bodies can be emitted out of line at all.

Tests this would want: `btRigidBody_setLinearVelocity` then `getLinearVelocity`
round-trips; `applyCentralImpulse` on a 2 kg body changes velocity by
impulse / 2; `btHingeConstraint_setLimit` then `getLowerLimit`.
