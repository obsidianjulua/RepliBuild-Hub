// RepliBuild-Hub shims for Jolt: WORKAROUNDS, each tied to a report.
//
// 1. By-value SIMD math (GENERATOR-simd-by-value-trapped.md)
//    JPH::Vec3, Vec4, Quat (and RVec3 = Vec3 here) wrap one __m128. SysV passes
//    and returns them in a single SSE register, and the wrapper's thunks can't
//    do that, so every function taking or returning one by value is an
//    "ABI Safety Trap" in Jolt.jl (~1,000 of them). The engine's trap message
//    suggests a shim that takes the record by pointer or reference, which these
//    are. Each one forwards to the upstream function of the same name, no logic
//    added. In-place constructors follow the build's own convention:
//    `Class_Class(this, args...)`, where `this` comes from the class's own
//    `operator new` (Jolt's allocator), as upstream's `new BoxShape(...)` does.
//    Covered: what upstream HelloWorld uses, plus the everyday BodyInterface
//    vector calls. Retire this section when the trap is gone.
//
// 2. Not wrapped, by design (not a bug report):
//    * JPH::Factory has only an implicit default constructor; the forced-ctor
//      pass skips those ("an implicit constructor, never declared").
//    * JPH::RegisterTypes() is an inline free function that passes
//      JPH_VERSION_ID, a value derived from this build's defines. Forwarding
//      it here gives Julia exactly the library's own ID.
#include <Jolt/Jolt.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <new>

namespace JoltHub {

using namespace JPH;

// ── 2. setup ──
void RegisterTypes()                 { JPH::RegisterTypes(); }
uint64 VersionID()                   { return JPH_VERSION_ID; }
Factory *Factory_New()               { return new Factory(); }
void Factory_Delete(Factory *f)      { delete f; }

// ── 1. constructors whose upstream form takes Vec3/Quat by value ──
void BoxShape_BoxShape(BoxShape *self, const Vec3 &inHalfExtent, float inConvexRadius)
{
	::new (self) BoxShape(inHalfExtent, inConvexRadius);
}

void BodyCreationSettings_BodyCreationSettings(BodyCreationSettings *self, const Shape *inShape,
	const RVec3 &inPosition, const Quat &inRotation, EMotionType inMotionType, ObjectLayer inObjectLayer)
{
	::new (self) BodyCreationSettings(inShape, inPosition, inRotation, inMotionType, inObjectLayer);
}

// ── 1. BodyInterface ──
void BodyInterface_GetCenterOfMassPosition(const BodyInterface *bi, BodyID id, RVec3 *out)	{ *out = bi->GetCenterOfMassPosition(id); }
void BodyInterface_GetPosition(const BodyInterface *bi, BodyID id, RVec3 *out)				{ *out = bi->GetPosition(id); }
void BodyInterface_GetRotation(const BodyInterface *bi, BodyID id, Quat *out)					{ *out = bi->GetRotation(id); }
void BodyInterface_GetLinearVelocity(const BodyInterface *bi, BodyID id, Vec3 *out)			{ *out = bi->GetLinearVelocity(id); }
void BodyInterface_GetAngularVelocity(const BodyInterface *bi, BodyID id, Vec3 *out)			{ *out = bi->GetAngularVelocity(id); }
void BodyInterface_SetPosition(BodyInterface *bi, BodyID id, const RVec3 &p, EActivation a)	{ bi->SetPosition(id, p, a); }
void BodyInterface_SetRotation(BodyInterface *bi, BodyID id, const Quat &q, EActivation a)	{ bi->SetRotation(id, q, a); }
void BodyInterface_SetLinearVelocity(BodyInterface *bi, BodyID id, const Vec3 &v)				{ bi->SetLinearVelocity(id, v); }
void BodyInterface_SetAngularVelocity(BodyInterface *bi, BodyID id, const Vec3 &w)			{ bi->SetAngularVelocity(id, w); }
void BodyInterface_AddForce(BodyInterface *bi, BodyID id, const Vec3 &f)						{ bi->AddForce(id, f); }
void BodyInterface_AddImpulse(BodyInterface *bi, BodyID id, const Vec3 &j)					{ bi->AddImpulse(id, j); }
void BodyInterface_AddTorque(BodyInterface *bi, BodyID id, const Vec3 &t)						{ bi->AddTorque(id, t); }

// ── 1. PhysicsSystem ──
void PhysicsSystem_SetGravity(PhysicsSystem *ps, const Vec3 &g)								{ ps->SetGravity(g); }
void PhysicsSystem_GetGravity(const PhysicsSystem *ps, Vec3 *out)								{ *out = ps->GetGravity(); }

} // namespace JoltHub
