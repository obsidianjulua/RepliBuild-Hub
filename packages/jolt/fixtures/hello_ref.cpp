// Reference for test_deep.jl: upstream HelloWorld/HelloWorld.cpp's scene, in
// C++, linked against the same libjolt.so the Julia wrapper loads.
//
// Differences from upstream, all mirrored on the Julia side:
//   * the three hand-written layer classes are the header-only *Table classes;
//   * JobSystemSingleThreaded, so the trajectory is one fixed sequence;
//   * a fixed step count, no listeners, and every value printed as its exact
//     bit pattern (%08x) so the comparison is bit-for-bit, not to a tolerance.
//
// Build (test_deep.jl does this):
//   clang++ <the recipe's -std/-m/-D flags> -I<jolt clone> hello_ref.cpp -L<lib dir> -ljolt
#include <Jolt/Jolt.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Core/JobSystemSingleThreaded.h>
#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Collision/BroadPhase/BroadPhaseLayerInterfaceTable.h>
#include <Jolt/Physics/Collision/BroadPhase/ObjectVsBroadPhaseLayerFilterTable.h>
#include <Jolt/Physics/Collision/ObjectLayerPairFilterTable.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>

using namespace JPH;

static uint32_t bits(float f) { uint32_t u; std::memcpy(&u, &f, 4); return u; }

int main(int argc, char **argv)
{
	const int steps = argc > 1 ? std::atoi(argv[1]) : 120;

	RegisterDefaultAllocator();
	Factory::sInstance = new Factory();
	RegisterTypes();

	TempAllocatorImpl temp_allocator(10 * 1024 * 1024);
	JobSystemSingleThreaded job_system(cMaxPhysicsJobs);

	// Object layers 0 = NON_MOVING, 1 = MOVING; broad-phase layers the same.
	ObjectLayerPairFilterTable pairs(2);
	pairs.EnableCollision(0, 1);
	pairs.EnableCollision(1, 1);
	BroadPhaseLayerInterfaceTable bp(2, 2);
	bp.MapObjectToBroadPhaseLayer(0, BroadPhaseLayer(0));
	bp.MapObjectToBroadPhaseLayer(1, BroadPhaseLayer(1));
	ObjectVsBroadPhaseLayerFilterTable ovb(bp, 2, pairs, 2);

	PhysicsSystem physics_system;
	physics_system.Init(1024, 0, 1024, 1024, bp, ovb, pairs);
	BodyInterface &bi = physics_system.GetBodyInterface();

	BodyCreationSettings floor_settings(new BoxShape(Vec3(100.0f, 1.0f, 100.0f)), RVec3(0.0f, -1.0f, 0.0f), Quat::sIdentity(), EMotionType::Static, 0);
	BodyID floor_id = bi.CreateAndAddBody(floor_settings, EActivation::DontActivate);

	BodyCreationSettings sphere_settings(new SphereShape(0.5f), RVec3(0.0f, 2.0f, 0.0f), Quat::sIdentity(), EMotionType::Dynamic, 1);
	BodyID sphere_id = bi.CreateAndAddBody(sphere_settings, EActivation::Activate);
	bi.SetLinearVelocity(sphere_id, Vec3(0.0f, -5.0f, 0.0f));

	physics_system.OptimizeBroadPhase();

	for (int step = 1; step <= steps; ++step)
	{
		RVec3 p = bi.GetCenterOfMassPosition(sphere_id);
		Vec3 v = bi.GetLinearVelocity(sphere_id);
		std::printf("%d %08x %08x %08x %08x %08x %08x %d\n", step,
			bits(p.GetX()), bits(p.GetY()), bits(p.GetZ()),
			bits(v.GetX()), bits(v.GetY()), bits(v.GetZ()),
			bi.IsActive(sphere_id) ? 1 : 0);
		physics_system.Update(1.0f / 60.0f, 1, &temp_allocator, &job_system);
	}

	bi.RemoveBody(sphere_id);
	bi.DestroyBody(sphere_id);
	bi.RemoveBody(floor_id);
	bi.DestroyBody(floor_id);
	UnregisterTypes();
	delete Factory::sInstance;
	Factory::sInstance = nullptr;
	return 0;
}
