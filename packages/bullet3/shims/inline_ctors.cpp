// Bullet constructors that exist only inline in its headers, compiled into
// libbullet3 so Julia can call them. See replibuild.toml [compile] source_files.
//
// Each builds the object IN PLACE in caller-supplied storage and returns that
// pointer. The storage must be at least struct_size(:T) bytes and 16-byte
// aligned (Bullet's own operator new uses btAlignedAlloc(size, 16)); from Julia,
// btAlignedAllocInternal(struct_size(:T), 16) gives exactly that.
//
// Placement new: btSphereShape and btDefaultMotionState declare their own
// operator new(size_t, void*) via BT_DECLARE_ALIGNED_ALLOCATOR (btScalar.h);
// btRigidBodyConstructionInfo is a plain struct and uses the standard one from
// <new>. References in the C++ signatures are pointers here; default arguments
// are the upstream defaults.

#include <new>
#include "btBulletDynamicsCommon.h"

#define RB_EXPORT extern "C" __attribute__((used, visibility("default")))

// btSphereShape(btScalar radius)                          btSphereShape.h:29
RB_EXPORT void *bt_new_SphereShape(void *storage, btScalar radius)
{
    return new (storage) btSphereShape(radius);
}

// btDefaultMotionState(const btTransform& startTrans = identity,
//                      const btTransform& centerOfMassOffset = identity)
//                                                          btDefaultMotionState.h:17
RB_EXPORT void *bt_new_DefaultMotionState(void *storage, const btTransform *startTrans)
{
    return new (storage) btDefaultMotionState(*startTrans);
}

// btRigidBody::btRigidBodyConstructionInfo(btScalar mass, btMotionState*,
//     btCollisionShape*, const btVector3& localInertia = btVector3(0, 0, 0))
//                                                          btRigidBody.h:144
RB_EXPORT void *bt_new_RigidBodyConstructionInfo(void *storage, btScalar mass,
                                                 btMotionState *motionState,
                                                 btCollisionShape *collisionShape,
                                                 const btVector3 *localInertia)
{
    return new (storage) btRigidBody::btRigidBodyConstructionInfo(
        mass, motionState, collisionShape, *localInertia);
}
