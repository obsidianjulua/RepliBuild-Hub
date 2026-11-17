# Generator gap: a 1-byte enum passed by value through a thunk carries stack garbage

> **STATUS:** FIXED in RepliBuild.jl #115 (`01f1a05`); re-wrapped, ObjectSim calls `GetNumActiveBodies` again (gate in test.jl, behaviour in test_deep.jl)
> **PACKAGE:** jolt 5.7.0 (`cf16769`)
> **STAGE:** Tier-2 AOT thunks (MLIR lowering of a by-value enum argument)
> **BLOCKS:** every Tier-2 thunk that passes an `enum class : uint8` by value:
> 33 in this build (list below). They get the right byte and 7 bytes of stack
> garbage above it. A callee that reads only the low byte works by luck (the
> `BodyCreationSettings` constructor stores it); one that reads the register
> wider indexes or compares with garbage: `PhysicsSystem::GetNumActiveBodies`
> returns garbage and then segfaults, `BodyManager::GetNumActiveBodies` returns 0
> for 45 awake bodies.
> **HUB PIN (workaround in place):** none in this package. ObjectSim's Jolt
> backend (`examples/ObjectSim/src/backends/jolt/world.jl`, `_jnum_active`) reads
> `PhysicsSystem::mBodyManager.mNumActiveBodies[0]` in place instead of calling
> `GetNumActiveBodies`. **To retire:** call
> `JPH_PhysicsSystem_GetNumActiveBodies(ps, RigidBody)` there again; it must
> return the same count as the field.
> **ENGINE AT:** RepliBuild.jl `4deefe6` (main, #114)

## Symptom

```julia
P = w.phys                      # a PhysicsSystem with 45 awake bodies
off = _joff(J.PhysicsSystem, :mBodyManager) + _joff(J.BodyManager, :mNumActiveBodies)
unsafe_load(Ptr{UInt32}(P.ps + off))                           # 45   (the field)
J.JPH_BodyManager_GetNumActiveBodies(P.ps + 16, J.RigidBody)   # 0
J.JPH_PhysicsSystem_GetNumActiveBodies(P.ps, J.RigidBody)      # 1228931080
```

Called once per step, the `PhysicsSystem` form segfaults within a few calls:

```
signal 11: Segmentation fault
load at .../bits/atomic_base.h:518 [inlined]
GetNumActiveBodies at .../Jolt/Physics/Body/BodyManager.h:123
unknown function at .debug/mlir/jlcs_f7a243e2812ec681.mlir
invoke_aot_ptr at RepliBuild.jl/src/IRGen/JITManager.jl:753
JPH_PhysicsSystem_GetNumActiveBodies at lib/jolt/Jolt.jl:230039
```

## Source

The wrapper is right: `UInt8(inType)` goes in, and `_arg_marshal_plan`
passes a pointer to it. So is the MLIR thunk, which loads the record from that
pointer:

```mlir
func.func private @_ZNK3JPH11BodyManager18GetNumActiveBodiesENS_9EBodyTypeE(!llvm.ptr, !llvm.struct<"EBodyType", (i8)>) -> i32
...
%val_2 = llvm.load %val_ptr_2 : !llvm.ptr -> !llvm.struct<"EBodyType", (i8)>
%ret_val = jlcs.try_call %val_1, %val_2 { callee = @_ZNK3JPH11BodyManager18GetNumActiveBodiesENS_9EBodyTypeE } : (!llvm.ptr, !llvm.struct<"EBodyType", (i8)>) -> i32
```

The trouble is the lowered call. `libjolt_thunks.so`:

```
_ZNK3JPH11BodyManager18GetNumActiveBodiesENS_9EBodyTypeE_thunk:
  sub    $0x18,%rsp
  mov    (%rdi),%rax
  mov    0x8(%rdi),%rcx
  mov    (%rax),%rdi          ; this
  movzbl (%rcx),%eax          ; the enum's byte
  mov    %al,0x10(%rsp)       ; stored as 1 byte ...
  mov    0x10(%rsp),%rsi      ; ... and passed as 8: bytes 1-7 are whatever was there
  call   _ZNK3JPH11BodyManager18GetNumActiveBodiesENS_9EBodyTypeE@plt
```

The `{i8}` record is coerced through memory to an i64 argument with nothing
above the byte. The callee, compiled by clang from upstream's inline body,
takes the argument as `i8 zeroext`: it relies on the caller having
zero-extended the byte to 32 bits, as clang's callers always do.
`libjolt.so`:

```
_ZNK3JPH11BodyManager18GetNumActiveBodiesENS_9EBodyTypeE:
  mov    %rdi,%rbx
  mov    %esi,%r14d                   ; 32 bits of the argument
  ...
  mov    0xb0(%rbx,%r14,4),%eax       ; mNumActiveBodies[inType]
```

The offsets in `libjolt.so` agree with the wrapper's layout (`mNumActiveBodies`
at 176, `mBodyManager` at 16), so this is only the argument. A 4-byte enum
(`EActivation`, `{i32}`) is not affected, because the 32 bits the callee reads
are all set.

## Why this is not a TOML mistake

No setting changes how a by-value enum crosses a thunk. The enum is a plain
`enum class EBodyType : uint8`, and the function is an ordinary const member
(`PhysicsSystem::GetNumActiveBodies` is upstream's inline forward to
`BodyManager`'s).

## Pipeline stage

Tier-2 thunk generation. A by-value enum becomes `!llvm.struct<"E", (i8)>` in
the callee's declaration and in `jlcs.try_call`. Lowered, that record is passed
as a register filled from memory, with no `zeroext`, while the callee's real C
signature has `i8 zeroext`.

## Minimal reproduction

Every thunk in this build that passes an `(i8)` record by value (33; no `(i16)`
records appear):

```
BodyCreationSettings::BodyCreationSettings(Shape const*, Vec3, Quat, EMotionType, unsigned short)
BodyCreationSettings::BodyCreationSettings(ShapeSettings const*, Vec3, Quat, EMotionType, unsigned short)
BodyInterface::SetMotionQuality(BodyID const&, EMotionQuality)
BodyInterface::SetMotionType(BodyID const&, EMotionType, EActivation)
BodyManager::GetActiveBodies(EBodyType, Array<BodyID>&) const
BodyManager::GetActiveBodiesUnsafe(EBodyType) const
BodyManager::GetNumActiveBodies(EBodyType) const
BodyManager::SetMotionQuality(Body&, EMotionQuality)
Body::SetMotionType(EMotionType)
CollisionDispatch::sRegisterCastShape(EShapeSubType, EShapeSubType, ...)
CollisionDispatch::sRegisterCollideShape(EShapeSubType, EShapeSubType, ...)
CompoundShape::CompoundShape(EShapeSubType)
ConvexShape::ConvexShape(EShapeSubType)
ConvexShape::ConvexShape(EShapeSubType, PhysicsMaterial const*)
DecoratedShape::DecoratedShape(EShapeSubType)
DecoratedShape::DecoratedShape(EShapeSubType, DecoratedShapeSettings const&, Result<Ref<Shape>>&)
DecoratedShape::DecoratedShape(EShapeSubType, Shape const*)
MotionProperties::SetMassProperties(EAllowedDOFs, MassProperties const&)
MotorSettings::MotorSettings(ESpringMode, float, float)
MotorSettings::MotorSettings(ESpringMode, float, float, float, float)
operator|(EAllowedDOFs, EAllowedDOFs)
PhysicsSystem::GetActiveBodies(EBodyType, Array<BodyID>&) const
PhysicsSystem::GetActiveBodiesUnsafe(EBodyType) const
PhysicsSystem::GetNumActiveBodies(EBodyType) const
PhysicsSystem::SaveState(StateRecorder&, EStateRecorderState, StateRecorderFilter const*) const
RayCastSettings::SetBackFaceMode(EBackFaceMode)
ShapeCastSettings::SetBackFaceMode(EBackFaceMode)
ShapeFunctions::sGet(EShapeSubType)
Shape::Shape(EShapeType, EShapeSubType)
Shape::Shape(EShapeType, EShapeSubType, ShapeSettings const&, Result<Ref<Shape>>&)
SpringSettings::SpringSettings(ESpringMode, float, float)
SwingTwistConstraintPart::SetSwingType(ESwingType)
replibuild_default::d3646(PhysicsSystem const*, StateRecorder&, EStateRecorderState)
```

The script that showed it (any scene with moving bodies):

```julia
using ObjectSim; const O = ObjectSim; const J = O.J
O.with_world(O.load_scene(O.find_scene("tumble")); backend = "jolt") do w
    P = w.phys
    off = O._joff(J.PhysicsSystem, :mBodyManager) + O._joff(J.BodyManager, :mNumActiveBodies)
    @show unsafe_load(Ptr{UInt32}(P.ps + off))                                 # 45
    @show J.JPH_BodyManager_GetNumActiveBodies(P.ps + O._joff(J.PhysicsSystem, :mBodyManager), J.RigidBody)   # 0
end
```

## Proposed fix (from this package's data)

Pass a by-value enum with an integer underlying type narrower than 32 bits the
way clang does: as that integer type with `zeroext`, or `signext` for a signed
one such as `enum : int8`. Alternatively, extend it to i32 before the call. The
record form can stay for enums of 32 bits and more, where the callee reads
nothing that isn't set. A check that would have caught it: a thunk for any
`f(E)` with `E : uint8` must compile to a zero-extending move (`movzbl`, or
`movzx` into `%esi`/`%edi`, …) into the argument register, never a 64-bit load
from a spilled byte.
