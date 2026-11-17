# The bullet3 backend: a btDiscreteDynamicsWorld and the bodies in it.
#
# Every C++ object lives on storage from Bullet's own aligned allocator
# (btAlignedAllocInternal), which is what Bullet's class-level operator new
# uses. That is why `<Class>_delete_<Class>` (the deleting destructor, which
# frees through the same allocator) is the right way to free shapes, bodies
# and mesh interfaces: every class used here inherits BT_DECLARE_ALIGNED_ALLOCATOR
# from btCollisionShape, btCollisionObject or btStridingMeshInterface.
#
# btSphereShape, btDefaultMotionState and btRigidBodyConstructionInfo have
# header-inline constructors only. Since RepliBuild.jl #105 the build defines
# them, and they construct in place in storage from btAlignedAllocInternal like
# any other constructor here. The construction info therefore starts from
# upstream's real defaults, and ObjectSim overrides only what a scene sets.
#
# Two transforms per moving body:
# - the body's own world transform: the physics state after the last fixed
#   step. `transform`, `position`, tests and snapshots read this.
# - its btDefaultMotionState's graphics transform: what bullet3 writes back
#   after each stepSimulation. btDiscreteDynamicsWorld defaults to *latency*
#   interpolation: the pose at (last step - dt + time left over), i.e. between
#   the previous fixed step and the current one, never extrapolated past it
#   (so nothing is drawn inside a floor it is about to hit). `render_transform`
#   reads this and the viewer draws with it.
#
# Per-object rules: own gravity is btRigidBody::setGravity flagged
# BT_DISABLE_WORLD_GRAVITY; layers are addRigidBody(body, group, mask);
# triggers are CF_NO_CONTACT_RESPONSE; contact reports are the dispatcher's
# persistent manifolds; force hooks run from the internal pre-tick callback.

const _OFF_XFORM  = B.member_offset(:btCollisionObject, :m_worldTransform)
# btDefaultMotionState's second argument (centerOfMassOffset) defaults to the
# identity in C++; the wrapper takes it explicitly.
const _IDENTITY_XF = B.btTransform(
    B.btMatrix3x3((B.btVector3((1f0, 0f0, 0f0, 0f0)), B.btVector3((0f0, 1f0, 0f0, 0f0)),
                   B.btVector3((0f0, 0f0, 1f0, 0f0)))),
    B.btVector3((0f0, 0f0, 0f0, 0f0)))
const _OFF_GFX    = B.member_offset(:btDefaultMotionState, :m_graphicsWorldTrans)
const _OFF_NUM_ITERS = B.member_offset(:btContactSolverInfoData, :m_numIterations)
const _OFF_LINVEL = B.member_offset(:btRigidBody, :m_linearVelocity)
const _OFF_ANGVEL = B.member_offset(:btRigidBody, :m_angularVelocity)
const _OFF_RAY_HITOBJ = B.member_offset(:RayResultCallback, :m_collisionObject)
const _OFF_RAY_FRAC   = B.member_offset(:RayResultCallback, :m_closestHitFraction)
const _OFF_RAY_POINT  = B.member_offset(:ClosestRayResultCallback, :m_hitPointWorld)
const _OFF_RAY_NORMAL = B.member_offset(:ClosestRayResultCallback, :m_hitNormalWorld)
const _OFF_MP_NORMAL = B.member_offset(:btManifoldPoint, :m_normalWorldOnB)

# btCollisionObject.h activation states, btRigidBody / btCollisionObject flags
const ACTIVE_TAG = 1
const ISLAND_SLEEPING = 2
const DISABLE_DEACTIVATION = 4
const BT_DISABLE_WORLD_GRAVITY = 1
const CF_NO_CONTACT_RESPONSE = 4

_alloc(cls::Symbol) = B.btAlignedAllocInternal(B.struct_size(cls), 16)
_btv(v) = B.btVector3((Float32(v[1]), Float32(v[2]), Float32(v[3]), 0f0))
_tuple(v::B.btVector3) = (v.m_floats[1], v.m_floats[2], v.m_floats[3])
_delete(cls::Symbol, p::Ptr) = getfield(B, Symbol(cls, "_delete_", cls))(p)
# A method returning `const btVector3&` may come back as the value or as a
# pointer to it; take either.
_btvec(v::B.btVector3) = v
_btvec(p::Ptr) = unsafe_load(Ptr{B.btVector3}(p))

mutable struct Bullet3Physics <: Physics
    cfg::Ptr{Cvoid}
    disp::Ptr{Cvoid}
    bp::Ptr{Cvoid}
    solver::Ptr{Cvoid}
    world::Ptr{Cvoid}
    ray::Ptr{Cvoid}                      # storage for one ClosestRayResultCallback
    index::Dict{Ptr{Cvoid},Body}         # btCollisionObject* → Body, for raycasts and contacts
end

"""A body in the bullet3 backend: the btRigidBody and what it owns."""
mutable struct Bullet3Body
    phys::Bullet3Physics
    ptr::Ptr{Cvoid}
    motion::Ptr{Cvoid}         # btDefaultMotionState for moving bodies, else C_NULL
    shape::Ptr{Cvoid}
    shape_class::Symbol
    iface::Ptr{Cvoid}          # btTriangleIndexVertexArray for `mesh`, else C_NULL
    keep::Vector{Any}          # buffers bullet3 points into but does not copy
end

_be_name(::Bullet3Physics) = "bullet3"
_rbp(b::Body) = (b.h::Bullet3Body).ptr

function _be_world(::Val{:bullet3}, w::World)
    scene = w.scene
    info = Ref(B.btDefaultCollisionConstructionInfo(C_NULL, C_NULL, 4096, 4096, 0, 1))
    cfg = _alloc(:btDefaultCollisionConfiguration)
    B.btDefaultCollisionConfiguration_btDefaultCollisionConfiguration(cfg, info)
    disp = _alloc(:btCollisionDispatcher)
    B.btCollisionDispatcher_btCollisionDispatcher(disp, cfg)
    bp = _alloc(:btDbvtBroadphase)
    B.btDbvtBroadphase_btDbvtBroadphase(bp, C_NULL)
    solver = _alloc(:btSequentialImpulseConstraintSolver)
    B.btSequentialImpulseConstraintSolver_btSequentialImpulseConstraintSolver(solver)
    world = _alloc(:btDiscreteDynamicsWorld)
    B.btDiscreteDynamicsWorld_btDiscreteDynamicsWorld(world, disp, bp, solver, cfg)
    P = Bullet3Physics(cfg, disp, bp, solver, world, _alloc(:ClosestRayResultCallback), Dict{Ptr{Cvoid},Body}())
    _be_set_gravity!(P, scene.world.gravity)
    _be_set_iterations!(P, scene.world.iterations)
    _bt_install_tick!(P, w)
    return P
end

function _be_destroy!(P::Bullet3Physics, w::World)
    empty!(P.index)
    delete!(_BT_WORLDS, P.world)
    # The ray callback was built in place and its destructor does nothing:
    # free the storage only (its deleting destructor would use ::operator delete).
    B.btAlignedFreeInternal(P.ray)
    B.btDiscreteDynamicsWorld_destroy_btDiscreteDynamicsWorld(P.world)
    B.btSequentialImpulseConstraintSolver_destroy_btSequentialImpulseConstraintSolver(P.solver)
    B.btDbvtBroadphase_destroy_btDbvtBroadphase(P.bp)
    B.btCollisionDispatcher_destroy_btCollisionDispatcher(P.disp)
    B.btDefaultCollisionConfiguration_destroy_btDefaultCollisionConfiguration(P.cfg)
    foreach(B.btAlignedFreeInternal, (P.world, P.solver, P.bp, P.disp, P.cfg))
end

_be_set_gravity!(P::Bullet3Physics, g) = B.btDiscreteDynamicsWorld_setGravity(P.world, Ref(_btv(g)))
# getSolverInfo().m_numIterations, as in C++ (a public member, no setter)
_iters_ptr(P::Bullet3Physics) = Ptr{Int32}(Ptr{Cvoid}(B.btDynamicsWorld_getSolverInfo(P.world)) + _OFF_NUM_ITERS)
_be_set_iterations!(P::Bullet3Physics, n) = unsafe_store!(_iters_ptr(P), Int32(n))
_be_iterations(P::Bullet3Physics) = Int(unsafe_load(_iters_ptr(P)))

# ── the pre-tick callback ────────────────────────────────────────────────────
# bullet3 calls this before each internal fixed step, from inside
# stepSimulation; it finds the World by its btDynamicsWorld pointer.
const _BT_WORLDS = Dict{Ptr{Cvoid},World}()
const _BT_PRETICK = Ref{Ptr{Cvoid}}(C_NULL)

function _bt_pretick(world::Ptr{Cvoid}, dt::Cfloat)::Cvoid
    w = get(_BT_WORLDS, world, nothing)
    w === nothing || _pre_step!(w, Float32(dt))
    return nothing
end

function _bt_install_tick!(P::Bullet3Physics, w::World)
    _BT_PRETICK[] == C_NULL && (_BT_PRETICK[] = @cfunction(_bt_pretick, Cvoid, (Ptr{Cvoid}, Cfloat)))
    _BT_WORLDS[P.world] = w
    B.btDynamicsWorld_setInternalTickCallback(P.world, _BT_PRETICK[], C_NULL, true)
end

_be_step!(P::Bullet3Physics, w::World) = B.btDiscreteDynamicsWorld_stepSimulation(P.world, w.dt, 1, w.dt)
_be_advance!(P::Bullet3Physics, w::World, seconds, max_substeps) =
    Int(B.btDiscreteDynamicsWorld_stepSimulation(P.world, seconds, max_substeps, w.dt))

# ── bodies ───────────────────────────────────────────────────────────────────

# The collision shape for a body: shape, its class, mesh interface, kept buffers.
function _bt_shape(s::ObjectSpec, mesh::TriMesh)
    keep = Any[]; iface = C_NULL
    if s.shape == :box
        cls = :btBoxShape; p = _alloc(cls)
        B.btBoxShape_btBoxShape(p, Ref(_btv(vscale(s.size, 0.5f0))))
    elseif s.shape == :sphere
        cls = :btSphereShape; p = _alloc(cls)
        B.btSphereShape_btSphereShape(p, s.radius)
    elseif s.shape == :capsule
        cls = :btCapsuleShape; p = _alloc(cls)
        B.btCapsuleShape_btCapsuleShape(p, s.radius, s.height - 2s.radius)   # distance between sphere centres
    elseif s.shape == :cylinder
        cls = :btCylinderShape; p = _alloc(cls)
        B.btCylinderShape_btCylinderShape(p, Ref(_btv((s.radius, s.height / 2, s.radius))))
    elseif s.shape == :cone
        cls = :btConeShape; p = _alloc(cls)
        B.btConeShape_btConeShape(p, s.radius, s.height)
    elseif s.shape == :hull
        pts = reinterpret(Float32, mesh.vertices) |> collect   # copied by the constructor
        cls = :btConvexHullShape; p = _alloc(cls)
        GC.@preserve pts B.btConvexHullShape_btConvexHullShape(p, pointer(pts), length(mesh.vertices), 12)
        B.btConvexHullShape_optimizeConvexHull(p)           # keep only the hull's own points
        B.btConvexHullShape_setLocalScaling(p, Ref(_btv((1, 1, 1))))   # recomputes the cached AABB
    elseif s.shape == :mesh
        verts = collect(reinterpret(Float32, mesh.vertices))
        idx = Int32[i - 1 for f in mesh.faces for i in f]
        push!(keep, verts, idx)                  # bullet3 keeps these pointers: hold them
        iface = _alloc(:btTriangleIndexVertexArray)
        B.btTriangleIndexVertexArray_btTriangleIndexVertexArray(iface, length(mesh.faces),
            pointer(idx), 12, length(mesh.vertices), pointer(verts), 12)
        cls = :btBvhTriangleMeshShape; p = _alloc(cls)
        B.btBvhTriangleMeshShape_btBvhTriangleMeshShape(p, iface, true, true)
    else
        error("ObjectSim: unknown shape $(s.shape)")
    end
    return p, cls, iface, keep
end

function _bt_inertia(cls::Symbol, p::Ptr, mass::Float32)
    inertia = Ref(_btv((0, 0, 0)))
    mass == 0 && return inertia[]
    f = cls == :btConvexHullShape ? B.btPolyhedralConvexShape_calculateLocalInertia :
        getfield(B, Symbol(cls, "_calculateLocalInertia"))
    f(p, mass, inertia)
    return inertia[]
end

function _be_add_body!(P::Bullet3Physics, w::World, b::Body, com)
    s = b.spec
    p, cls, iface, keep = _bt_shape(s, b.mesh)
    R = rotation_matrix(s.rotation)
    origin = vadd(s.position, _rotate(R, com))     # spec position is the asset's origin
    xf = B.btTransform(B.btMatrix3x3((_btv(R[1]), _btv(R[2]), _btv(R[3]))), _btv(origin))

    # Static bodies never move, so only moving ones get a motion state. With
    # one, the body takes its start pose from it, not from the construction info.
    ms = C_NULL
    if s.mass > 0
        ms = _alloc(:btDefaultMotionState)
        B.btDefaultMotionState_btDefaultMotionState(ms, Ref(xf), Ref(_IDENTITY_XF))
    end

    # The real btRigidBodyConstructionInfo constructor fills upstream's
    # defaults; then the scene's own values replace the ones it sets.
    cip = _alloc(:btRigidBodyConstructionInfo)
    body = _alloc(:btRigidBody)
    try
        B.btRigidBody_btRigidBodyConstructionInfo_btRigidBodyConstructionInfo(cip, s.mass, ms, p, Ref(_bt_inertia(cls, p, s.mass)))
        ptr = Ptr{B.btRigidBodyConstructionInfo}(cip)
        unsafe_store!(ptr, _with(unsafe_load(ptr);
            m_startWorldTransform = xf,
            m_linearDamping = s.damping[1], m_angularDamping = s.damping[2],
            m_friction = s.friction, m_rollingFriction = s.rolling_friction,
            m_restitution = s.restitution))
        B.btRigidBody_btRigidBody(body, ptr)
    finally
        B.btAlignedFreeInternal(cip)          # plain struct: nothing to destroy
    end
    if s.mass > 0
        unsafe_store!(Ptr{B.btVector3}(body + _OFF_LINVEL), _btv(s.velocity))
        unsafe_store!(Ptr{B.btVector3}(body + _OFF_ANGVEL), _btv(s.spin))
        # bullet3 puts a body to sleep once it has moved slower than its
        # sleeping thresholds (0.8 m/s, 1 rad/s) for 2 s — which can freeze a
        # slow pendulum mid-swing. `sleep = false` opts out; so does everything
        # in a world with mutual gravity, where slow is normal.
        (s.sleep && w.mutual_G == 0) ||
            B.btCollisionObject_setActivationState(body, DISABLE_DEACTIVATION)
    end
    # addRigidBody gives every body the world's gravity unless it carries
    # BT_DISABLE_WORLD_GRAVITY; its own is set after.
    s.gravity === nothing ||
        B.btRigidBody_setFlags(body, B.btRigidBody_getFlags(body) | BT_DISABLE_WORLD_GRAVITY)
    s.trigger && B.btCollisionObject_setCollisionFlags(body,
        B.btCollisionObject_getCollisionFlags(body) | CF_NO_CONTACT_RESPONSE)
    group, mask = _filter(w, s)
    B.btDiscreteDynamicsWorld_addRigidBody(P.world, body, group, mask)
    s.gravity === nothing || B.btRigidBody_setGravity(body, Ref(_btv(s.gravity)))
    P.index[body] = b
    return Bullet3Body(P, body, ms, p, cls, iface, keep)
end

function _be_free_body!(P::Bullet3Physics, w::World, b::Body)
    h = (b.h::Bullet3Body)
    delete!(P.index, h.ptr)
    B.btDiscreteDynamicsWorld_removeRigidBody(P.world, h.ptr)
    _delete(:btRigidBody, h.ptr)
    h.motion == C_NULL || _delete(:btDefaultMotionState, h.motion)
    _delete(h.shape_class, h.shape)
    h.iface == C_NULL || _delete(:btTriangleIndexVertexArray, h.iface)
    empty!(h.keep)
    h.ptr = C_NULL
end

function _rows_origin(t::B.btTransform)
    el = t.m_basis.m_el
    return (_tuple(el[1]), _tuple(el[2]), _tuple(el[3])), _tuple(t.m_origin)
end

_be_transform(::Bullet3Physics, b::Body) = _rows_origin(unsafe_load(Ptr{B.btTransform}(_rbp(b) + _OFF_XFORM)))
# The motion state's m_graphicsWorldTrans: what getWorldTransform returns when
# the centre-of-mass offset is identity (ObjectSim never sets one).
_be_render_transform(P::Bullet3Physics, b::Body) = (b.h::Bullet3Body).motion == C_NULL ? _be_transform(P, b) :
    _rows_origin(unsafe_load(Ptr{B.btTransform}((b.h::Bullet3Body).motion + _OFF_GFX)))

_be_velocity(::Bullet3Physics, b::Body) = _tuple(_btvec(B.btRigidBody_getLinearVelocity(_rbp(b))))
_be_spin(::Bullet3Physics, b::Body) = _tuple(_btvec(B.btRigidBody_getAngularVelocity(_rbp(b))))
_be_sleeping(::Bullet3Physics, b::Body) = B.btCollisionObject_getActivationState(_rbp(b)) == ISLAND_SLEEPING
_be_wake!(::Bullet3Physics, b::Body) = B.btCollisionObject_activate(_rbp(b), true)
_be_keep_awake!(::Bullet3Physics, b::Body, on::Bool) =
    B.btCollisionObject_setActivationState(_rbp(b), on ? DISABLE_DEACTIVATION : ACTIVE_TAG)

function _be_set_velocity!(::Bullet3Physics, b::Body, v, spin)
    B.btRigidBody_setLinearVelocity(_rbp(b), Ref(_btv(v)))
    spin === nothing || B.btRigidBody_setAngularVelocity(_rbp(b), Ref(_btv(spin)))
end

# applyCentralImpulse / applyImpulse(impulse, at − centre of mass)
_be_impulse!(::Bullet3Physics, b::Body, J, at) = at === nothing ?
    B.btRigidBody_applyCentralImpulse(_rbp(b), Ref(_btv(J))) :
    B.btRigidBody_applyImpulse(_rbp(b), Ref(_btv(J)), Ref(_btv(vsub(at, position(b)))))
_be_angular_impulse!(::Bullet3Physics, b::Body, T) = B.btRigidBody_applyTorqueImpulse(_rbp(b), Ref(_btv(T)))

function _be_set_mass!(::Bullet3Physics, b::Body, m)
    h = (b.h::Bullet3Body)
    B.btRigidBody_setMassProps(h.ptr, m, Ref(_bt_inertia(h.shape_class, h.shape, m)))
    B.btRigidBody_updateInertiaTensor(h.ptr)
end
_be_set_friction!(::Bullet3Physics, b::Body, f) = B.btCollisionObject_setFriction(_rbp(b), f)
_be_set_restitution!(::Bullet3Physics, b::Body, e) = B.btCollisionObject_setRestitution(_rbp(b), e)
_be_set_rolling_friction!(::Bullet3Physics, b::Body, f) = B.btCollisionObject_setRollingFriction(_rbp(b), f)
_be_set_damping!(::Bullet3Physics, b::Body, lin, ang) = B.btRigidBody_setDamping(_rbp(b), lin, ang)

function _be_set_body_gravity!(::Bullet3Physics, w::World, b::Body, g)
    p = _rbp(b)
    flags = B.btRigidBody_getFlags(p)
    if g === nothing
        B.btRigidBody_setFlags(p, flags & ~BT_DISABLE_WORLD_GRAVITY)
        B.btRigidBody_setGravity(p, Ref(_btv(w.gravity)))
    else
        B.btRigidBody_setFlags(p, flags | BT_DISABLE_WORLD_GRAVITY)
        B.btRigidBody_setGravity(p, Ref(_btv(g)))
    end
end
_be_body_gravity(::Bullet3Physics, b::Body) = _tuple(_btvec(B.btRigidBody_getGravity(_rbp(b))))
_be_istrigger(::Bullet3Physics, b::Body) = (B.btCollisionObject_getCollisionFlags(_rbp(b)) & CF_NO_CONTACT_RESPONSE) != 0

# ── queries ──────────────────────────────────────────────────────────────────

# btCollisionWorld::rayTest with a ClosestRayResultCallback.
function _be_raycast(P::Bullet3Physics, w::World, from, to)
    f = _btv(from); t = _btv(to)
    B.btCollisionWorld_ClosestRayResultCallback_ClosestRayResultCallback(P.ray, Ref(f), Ref(t))
    B.btCollisionWorld_rayTest(P.world, Ref(f), Ref(t), Ptr{B.RayResultCallback}(P.ray))
    B.btCollisionWorld_RayResultCallback_hasHit(P.ray) || return nothing
    hit = unsafe_load(Ptr{Ptr{Cvoid}}(P.ray + _OFF_RAY_HITOBJ))      # m_collisionObject: a public member
    b = get(P.index, hit, nothing)
    b === nothing && return nothing
    load(off) = _tuple(unsafe_load(Ptr{B.btVector3}(P.ray + off)))
    return (body = b, point = load(_OFF_RAY_POINT), normal = load(_OFF_RAY_NORMAL),
            fraction = unsafe_load(Ptr{Float32}(P.ray + _OFF_RAY_FRAC)))
end

# The dispatcher's persistent manifolds: a resting box's points sit at about
# zero distance, some a hair above it, and all of them carry its weight.
function _be_contacts(P::Bullet3Physics, w::World, within)
    out = Contact[]
    for i in 0:B.btCollisionDispatcher_getNumManifolds(P.disp) - 1
        m = B.btCollisionDispatcher_getManifoldByIndexInternal(P.disp, i)
        a = get(P.index, Ptr{Cvoid}(B.btPersistentManifold_getBody0(m)), nothing)
        b = get(P.index, Ptr{Cvoid}(B.btPersistentManifold_getBody1(m)), nothing)
        (a === nothing || b === nothing) && continue
        for j in 0:B.btPersistentManifold_getNumContacts(m) - 1
            pt = Ptr{Cvoid}(B.btPersistentManifold_getContactPoint(m, j))
            d = B.btManifoldPoint_getDistance(pt)
            d > within && continue
            push!(out, Contact(a, b, _tuple(_btvec(B.btManifoldPoint_getPositionWorldOnA(pt))),
                               _tuple(unsafe_load(Ptr{B.btVector3}(pt + _OFF_MP_NORMAL))),
                               B.btManifoldPoint_getAppliedImpulse(pt), d))
        end
    end
    return out
end
