// RepliBuild-Hub shims for Jolt: what the wrapper can't give by design.
// (The by-value Vec3/Quat forwards that used to open this file are retired:
// GENERATOR-simd-by-value-trapped.md is fixed, and those calls are wrapped
// under Jolt's own names.)
//
// 1. Not wrapped, by design (not a bug report):
//    * JPH::Factory has only an implicit default constructor; the forced-ctor
//      pass skips those ("an implicit constructor, never declared").
//    * JPH::RegisterTypes() is an inline free function that passes
//      JPH_VERSION_ID, a value derived from this build's defines. Forwarding
//      it here gives Julia exactly the library's own ID.
//
// 2. A listener Julia cannot be (not a bug report):
//    Jolt reports contacts only to a ContactListener subclass, from inside
//    PhysicsSystem::Update and, with JobSystemThreadPool, from its worker
//    threads at the same time. A Julia @cfunction there would run on threads
//    Julia doesn't own while the calling thread sits in the ccall, so a GC
//    triggered by one of them could never complete. ContactRecorder is a
//    plain C++ listener that copies each contact into a buffer under a mutex;
//    Julia clears it before Update and reads it after.
#include <Jolt/Jolt.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Collision/ContactListener.h>
#include <Jolt/Physics/Body/Body.h>
#include <mutex>
#include <vector>

namespace JoltHub {

using namespace JPH;

// ── 1. setup ──
void RegisterTypes()                 { JPH::RegisterTypes(); }
uint64 VersionID()                   { return JPH_VERSION_ID; }
Factory *Factory_New()               { return new Factory(); }
void Factory_Delete(Factory *f)      { delete f; }

// ── 2. ContactRecorder ──
// One row per contact manifold that is new or still touching this step:
// ids[2i], ids[2i+1] = the two BodyID values (GetIndexAndSequenceNumber);
// f[8i..8i+7] = world contact point (the first point on body 1), the normal
// (pointing from body 1 to body 2), penetration depth, and the speed at
// which the bodies approach along the normal at that point (m/s, > 0 when
// closing); flags[i] bit 0 = either body is a sensor, bit 1 = new this step.
class ContactRecorder final : public ContactListener
{
public:
	struct Row { uint32 id1, id2; float f[8]; uint32 flags; };

	void OnContactAdded(const Body &b1, const Body &b2, const ContactManifold &m, ContactSettings &s) override	{ Record(b1, b2, m, s, 2u); }
	void OnContactPersisted(const Body &b1, const Body &b2, const ContactManifold &m, ContactSettings &s) override	{ Record(b1, b2, m, s, 0u); }

	std::mutex			mMutex;
	std::vector<Row>	mRows;

private:
	void Record(const Body &b1, const Body &b2, const ContactManifold &m, const ContactSettings &s, uint32 flags)
	{
		Row r;
		r.id1 = b1.GetID().GetIndexAndSequenceNumber();
		r.id2 = b2.GetID().GetIndexAndSequenceNumber();
		RVec3 p = m.mRelativeContactPointsOn1.empty() ? m.mBaseOffset : m.GetWorldSpaceContactPointOn1(0);
		Vec3 n = m.mWorldSpaceNormal;
		float closing = (b1.GetPointVelocity(p) - b2.GetPointVelocity(p)).Dot(n);
		r.f[0] = float(p.GetX()); r.f[1] = float(p.GetY()); r.f[2] = float(p.GetZ());
		r.f[3] = n.GetX(); r.f[4] = n.GetY(); r.f[5] = n.GetZ();
		r.f[6] = m.mPenetrationDepth; r.f[7] = closing;
		r.flags = flags | ((s.mIsSensor || b1.IsSensor() || b2.IsSensor()) ? 1u : 0u);
		std::lock_guard<std::mutex> lock(mMutex);
		mRows.push_back(r);
	}
};

ContactRecorder *ContactRecorder_New()								{ return new ContactRecorder(); }
void ContactRecorder_Delete(ContactRecorder *r)						{ delete r; }
ContactListener *ContactRecorder_AsListener(ContactRecorder *r)		{ return r; }
void ContactRecorder_Clear(ContactRecorder *r)						{ std::lock_guard<std::mutex> lock(r->mMutex); r->mRows.clear(); }
int ContactRecorder_Count(ContactRecorder *r)						{ std::lock_guard<std::mutex> lock(r->mMutex); return int(r->mRows.size()); }
// Copies up to `max` rows into ids (2 per row), f (8 per row) and flags (1 per
// row); returns how many it copied.
int ContactRecorder_Read(ContactRecorder *r, uint32 *ids, float *f, uint32 *flags, int max)
{
	std::lock_guard<std::mutex> lock(r->mMutex);
	int n = int(r->mRows.size()) < max ? int(r->mRows.size()) : max;
	for (int i = 0; i < n; ++i)
	{
		const ContactRecorder::Row &row = r->mRows[i];
		ids[2 * i] = row.id1; ids[2 * i + 1] = row.id2;
		for (int k = 0; k < 8; ++k) f[8 * i + k] = row.f[k];
		flags[i] = row.flags;
	}
	return n;
}

} // namespace JoltHub
