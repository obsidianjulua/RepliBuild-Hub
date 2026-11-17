# The Jolt backend: a JPH::PhysicsSystem. Each Update runs on one thread, or
# on a JobSystemThreadPool once enough bodies are awake to make up for waking
# its workers (see JOLT_THREADS).
#
# Every C++ object is made the way `new T(...)` makes it, its constructor run
# in place on 64-byte aligned storage (see _jnew), and freed with its
# destructor. Every call is Jolt's own, Vec3/Quat by value included; the Hub
# shim adds only Factory/RegisterTypes and the ContactRecorder listener.
#
# How ObjectSim's model maps onto Jolt:
# - Bodies' poses and velocities are read straight from Jolt's Body and
#   MotionProperties (no lock: only between Updates, from this thread).
#   Body::mPosition is the centre of mass; the shape origin is recovered with
#   the offset measured when the body is made (0 for everything ObjectSim
#   centres, the mesh's own for static triangle meshes).
# - Collision layers: each distinct (group, mask, static?) becomes a Jolt
#   object layer, even ones on the NON_MOVING broad-phase layer and odd ones
#   on MOVING; the pair table is filled from the masks as layers appear.
# - Own gravity per body: gravity factor 0 and an impulse m·g·dt before each
#   step (Jolt has a factor, not a vector).
# - Triggers are sensors. Contacts come from the shim's ContactRecorder.
# - Smooth drawing: the pose before and after each fixed step is kept and the
#   drawn pose interpolated by the time left over, as bullet3's motion states do.
# - Not in Jolt: rolling friction (ignored, see `set_rolling_friction!`).

# Threads. Jolt takes its job system with every Update, so each step picks
# one: a step with fewer than JOLT_POOL_FROM[] awake bodies runs on this
# thread (waking workers costs more than they save there), a bigger one on a
# pool of JOLT_THREADS[] workers, made the first time it's needed. Measured on
# a 32-thread machine (a pile of boxes landing, µs per step):
#     awake      1 thread   2 workers   4 workers   8 workers   16 workers
#      300          106         76          88         107          119
#     1000          955        564         475         531          575
#     4000         7035       2893        2643        2706         3042
# Past 4 workers Jolt's solver gains nothing; 31 workers (all cores but one)
# made a 3-body scene 25× slower. JOLT_THREADS[] = 0: always one thread
# (deterministic run to run); -1 (default): 4, or the cores but one if fewer.
const JOLT_THREADS = Ref(-1)
const JOLT_POOL_FROM = Ref(250)

const _J_STATIC, _J_KINEMATIC, _J_DYNAMIC = 0x00, 0x01, 0x02     # EMotionType
const _J_ACTIVATE, _J_DONT_ACTIVATE = 0, 1                     # EActivation
const _J_LAYERS = 32                                           # object layers available
const _J_ROWS = 4096                                           # contact rows read per step

_jv(v) = J.Vec3(J.Vec3_anon1(reinterpret(NTuple{16,UInt8}, (Float32(v[1]), Float32(v[2]), Float32(v[3]), Float32(v[3])))))
_jq(q) = J.Quat(J.Vec4(J.Vec4_anon1(reinterpret(NTuple{16,UInt8}, Float32.((q[1], q[2], q[3], q[4]))))))
_jxyz(p::Ptr) = (p4 = unsafe_load(Ptr{NTuple{4,Float32}}(p)); (p4[1], p4[2], p4[3]))
_jxyz(v::J.Vec3) = (l = reinterpret(NTuple{4,Float32}, v._anon1.data); (l[1], l[2], l[3]))
_jquat(p::Ptr) = unsafe_load(Ptr{NTuple{4,Float32}}(p))

# Field offsets, so C++ objects are read and written in place.
_joff(T, f) = fieldoffset(T, findfirst(==(f), fieldnames(T)))
_jpoke!(p, T, f, v) = unsafe_store!(Ptr{fieldtype(T, f)}(Ptr{UInt8}(p) + _joff(T, f)), v)
_jpeek(p, T, f) = unsafe_load(Ptr{fieldtype(T, f)}(Ptr{UInt8}(p) + _joff(T, f)))

# `new T(args...)` / `delete p`. Storage is 64-byte aligned: some Jolt classes
# are cache-line aligned (JobSystemThreadPool), C++ would use the aligned
# operator new for them (its align_val_t form is a trap in the wrapper), and
# the class's plain operator new gives 16 bytes, on which the constructor's
# aligned stores fault whenever the block happens to land off a 64-byte
# boundary. Jolt's default allocator is libc's (Allocate/AlignedAllocate free
# with free()), so a shape Jolt frees itself when its last reference goes is
# fine on this storage too.
function _jnew(T::Symbol, ctor, args...)
    pp = Ref{Ptr{Cvoid}}(C_NULL)
    ccall(:posix_memalign, Cint, (Ptr{Ptr{Cvoid}}, Csize_t, Csize_t), pp, 64, J.struct_size(T)) == 0 ||
        error("ObjectSim: could not allocate a Jolt $T")
    ctor(pp[], args...)
    return Ptr{getfield(J, T)}(pp[])
end
function _jdelete(T::Symbol, p)
    getfield(J, Symbol("JPH_", T, "_destroy_", T))(p)
    Libc.free(Ptr{Cvoid}(p))
end

# Quaternion (x, y, z, w) ↔ rotation rows.
function _jrows(q)
    x, y, z, w = q
    return ((1 - 2(y^2 + z^2), 2(x * y - z * w), 2(x * z + y * w)),
            (2(x * y + z * w), 1 - 2(x^2 + z^2), 2(y * z - x * w)),
            (2(x * z - y * w), 2(y * z + x * w), 1 - 2(x^2 + y^2)))
end
function _jquat_from_rows(R)
    m00, m01, m02 = R[1]; m10, m11, m12 = R[2]; m20, m21, m22 = R[3]
    t = m00 + m11 + m22
    if t > 0
        s = sqrt(t + 1) * 2
        return ((m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, s / 4)
    elseif m00 > m11 && m00 > m22
        s = sqrt(1 + m00 - m11 - m22) * 2
        return (s / 4, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s)
    elseif m11 > m22
        s = sqrt(1 + m11 - m00 - m22) * 2
        return ((m01 + m10) / s, s / 4, (m12 + m21) / s, (m02 - m20) / s)
    else
        s = sqrt(1 + m22 - m00 - m11) * 2
        return ((m02 + m20) / s, (m12 + m21) / s, s / 4, (m10 - m01) / s)
    end
end

# ── one-time setup: allocator, factory, types ────────────────────────────────

const _J_READY = Ref(false)
function _jolt_init!()
    _J_READY[] && return
    J.JPH_RegisterDefaultAllocator()
    inst = Ptr{Ptr{Cvoid}}(Libdl.dlsym(Libdl.dlopen(J.LIBRARY_PATH), :_ZN3JPH7Factory9sInstanceE))
    unsafe_load(inst) == C_NULL && unsafe_store!(inst, Ptr{Cvoid}(J.JoltHub_Factory_New()))
    J.JoltHub_RegisterTypes()
    _J_READY[] = true
end
_jfixed_to_world() = Ptr{J.Body}(Libdl.dlsym(Libdl.dlopen(J.LIBRARY_PATH), :_ZN3JPH4Body13sFixedToWorldE))

# ── the world ────────────────────────────────────────────────────────────────

mutable struct JoltPhysics <: Physics
    temp::Ptr{Cvoid}
    single::Ptr{Cvoid}                    # JobSystemSingleThreaded
    pool::Ptr{Cvoid}                      # JobSystemThreadPool, C_NULL until a step needs it
    pairs::Ptr{Cvoid}                     # ObjectLayerPairFilterTable
    bp::Ptr{Cvoid}                        # BroadPhaseLayerInterfaceTable
    ovb::Ptr{Cvoid}                       # ObjectVsBroadPhaseLayerFilterTable
    ps::Ptr{Cvoid}                        # PhysicsSystem
    bi::Ptr{Cvoid}                        # its BodyInterface
    bl::Ptr{Cvoid}                        # its BodyLockInterfaceNoLock
    npq::Ptr{Cvoid}                       # its NarrowPhaseQuery
    recorder::Ptr{Cvoid}                  # JoltHub::ContactRecorder
    layers::Vector{Tuple{Int32,Int32,Bool}}   # object layer + 1 → (group, mask, static)
    index::Dict{UInt32,Body}              # BodyID → Body
    gravity::Vec3
    leftover::Float32                     # advance!: time not yet stepped
    dt::Float32                           # the last fixed step's length
    rows::Tuple{Vector{UInt32},Vector{Float32},Vector{UInt32}}
    nrows::Int
end

"""A body in the Jolt backend."""
mutable struct JoltBody
    phys::JoltPhysics
    id::J.BodyID
    idref::Base.RefValue{J.BodyID}        # the id as calls take it (const BodyID&), made once
    ptr::Ptr{Cvoid}                       # JPH::Body*
    mp::Ptr{Cvoid}                        # JPH::MotionProperties*, C_NULL for static
    offset::Vec3                          # shape origin − centre of mass, in the body's frame
    gravity::Union{Nothing,Vec3}          # its own gravity, or nothing for the world's
    prev::Tuple{NTuple{4,Float32},Vec3}   # (rotation, centre of mass) before the last step
    curr::Tuple{NTuple{4,Float32},Vec3}   # … and after it
    sensor::Bool
end

# The handles, typed: Body.h is `Any` (either backend's), and reading it
# through these keeps the code that uses it compiled for JoltBody.
_jh(b::Body) = b.h::JoltBody

_be_name(::JoltPhysics) = "jolt"

function _be_world(::Val{:jolt}, w::World)
    _jolt_init!()
    temp = _jnew(:TempAllocatorImpl, J.JPH_TempAllocatorImpl_TempAllocatorImpl, 32 * 1024 * 1024)
    single = _jnew(:JobSystemSingleThreaded, J.JPH_JobSystemSingleThreaded_JobSystemSingleThreaded, 2048)
    # Layer tables: every object layer starts colliding with everything so the
    # object-vs-broad-phase table (built once, from the pair table) lets every
    # pair through to the pair table, which then says no to most of them and
    # yes to the pairs the scene's layers allow, as they appear.
    pairs = _jnew(:ObjectLayerPairFilterTable, J.JPH_ObjectLayerPairFilterTable_ObjectLayerPairFilterTable, _J_LAYERS)
    bp = _jnew(:BroadPhaseLayerInterfaceTable, J.JPH_BroadPhaseLayerInterfaceTable_BroadPhaseLayerInterfaceTable, _J_LAYERS, 2)
    for l in 0:_J_LAYERS - 1
        J.JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(bp, UInt16(l), J.BroadPhaseLayer(UInt8(isodd(l))))
        for m in l:_J_LAYERS - 1
            J.JPH_ObjectLayerPairFilterTable_EnableCollision(pairs, UInt16(l), UInt16(m))
        end
    end
    ovb = _jnew(:ObjectVsBroadPhaseLayerFilterTable, J.JPH_ObjectVsBroadPhaseLayerFilterTable_ObjectVsBroadPhaseLayerFilterTable,
                Ptr{J.BroadPhaseLayerInterface}(bp), 2, Ptr{J.ObjectLayerPairFilter}(pairs), _J_LAYERS)
    for l in 0:_J_LAYERS - 1, m in l:_J_LAYERS - 1
        J.JPH_ObjectLayerPairFilterTable_DisableCollision(pairs, UInt16(l), UInt16(m))
    end
    ps = _jnew(:PhysicsSystem, J.JPH_PhysicsSystem_PhysicsSystem)
    J.JPH_PhysicsSystem_Init(ps, 65536, 0, 65536, 32768, Ptr{J.BroadPhaseLayerInterface}(bp),
                             Ptr{J.ObjectVsBroadPhaseLayerFilter}(ovb), Ptr{J.ObjectLayerPairFilter}(pairs))
    recorder = Ptr{Cvoid}(J.JoltHub_ContactRecorder_New())
    J.JPH_PhysicsSystem_SetContactListener(ps, J.JoltHub_ContactRecorder_AsListener(recorder))
    P = JoltPhysics(temp, single, C_NULL, pairs, bp, ovb, ps,
                    Ptr{Cvoid}(J.JPH_PhysicsSystem_GetBodyInterface(ps)),
                    Ptr{Cvoid}(J.JPH_PhysicsSystem_GetBodyLockInterfaceNoLock(ps)),
                    Ptr{Cvoid}(J.JPH_PhysicsSystem_GetNarrowPhaseQuery(ps)), recorder,
                    Tuple{Int32,Int32,Bool}[], Dict{UInt32,Body}(), w.scene.world.gravity, 0f0, w.dt,
                    (zeros(UInt32, 2_J_ROWS), zeros(Float32, 8_J_ROWS), zeros(UInt32, _J_ROWS)), -1)
    _be_set_gravity!(P, w.scene.world.gravity)
    _be_set_iterations!(P, w.scene.world.iterations)
    return P
end

function _be_destroy!(P::JoltPhysics, w::World)
    empty!(P.index)
    _jfree_groups!(P)
    J.JPH_PhysicsSystem_SetContactListener(P.ps, C_NULL)
    J.JoltHub_ContactRecorder_Delete(P.recorder)
    _jdelete(:PhysicsSystem, P.ps)
    _jdelete(:ObjectVsBroadPhaseLayerFilterTable, P.ovb)
    _jdelete(:BroadPhaseLayerInterfaceTable, P.bp)
    _jdelete(:ObjectLayerPairFilterTable, P.pairs)
    P.pool == C_NULL || _jdelete(:JobSystemThreadPool, P.pool)
    _jdelete(:JobSystemSingleThreaded, P.single)
    _jdelete(:TempAllocatorImpl, P.temp)
end

function _be_set_gravity!(P::JoltPhysics, g)
    P.gravity = Float32.(Tuple(g))
    J.JPH_PhysicsSystem_SetGravity(P.ps, _jv(g))
end

_jsettings(P::JoltPhysics) = unsafe_load(Ptr{J.PhysicsSettings}(J.JPH_PhysicsSystem_GetPhysicsSettings(P.ps)))
# Jolt's velocity steps are the solver passes (bullet3's iterations); its 2
# position steps stay as they are.
_be_iterations(P::JoltPhysics) = Int(_jsettings(P).mNumVelocitySteps)
_be_set_iterations!(P::JoltPhysics, n) =
    J.JPH_PhysicsSystem_SetPhysicsSettings(P.ps, Ref(_with(_jsettings(P); mNumVelocitySteps = UInt32(n))))

# ── layers ───────────────────────────────────────────────────────────────────

function _jlayer!(P::JoltPhysics, group::Int32, mask::Int32, static::Bool)
    key = (group, mask, static)
    i = findfirst(==(key), P.layers)
    i === nothing || return UInt16(i - 1)
    # static layers even (NON_MOVING broad phase), moving ones odd (MOVING)
    free(l) = l + 1 > length(P.layers) || P.layers[l + 1] == (Int32(0), Int32(0), true)
    i = findfirst(l -> free(l) && isodd(l) != static, 0:_J_LAYERS - 1)
    i === nothing && error("ObjectSim: too many different collision layers for the Jolt backend (at most $(_J_LAYERS ÷ 2) each for static and moving)")
    l = i - 1
    while length(P.layers) <= l
        push!(P.layers, (Int32(0), Int32(0), true))         # placeholder: never used
    end
    P.layers[l + 1] = key
    for (m, (g2, m2, s2)) in enumerate(P.layers)
        (g2 == 0 && m2 == 0) && continue
        static && s2 && continue                            # static never meets static
        ((group & m2) != 0 && (g2 & mask) != 0) &&
            J.JPH_ObjectLayerPairFilterTable_EnableCollision(P.pairs, UInt16(l), UInt16(m - 1))
    end
    return UInt16(l)
end

# ── shapes ───────────────────────────────────────────────────────────────────

# A Shape from ShapeSettings::Create: the Result keeps one reference for us
# (dropped once a body holds the shape, in _be_add_body!).
function _jresult_shape(res)
    res.mState[1] == 0x01 || error("ObjectSim: Jolt could not build the shape (result state $(res.mState[1]))")
    return unsafe_load(Ptr{Ptr{Cvoid}}(pointer_from_objref(Ref(res))))   # first word: the Ref<Shape>
end

# At most `n` points of the mesh that span its hull: the extreme vertex in
# each of n directions spread over the sphere. Jolt's hull builder takes up
# to 256 points; a scanned model's hull has thousands.
function _jhull_points(m::TriMesh; n = 200)
    length(m.vertices) <= 120 && return m.vertices
    golden = π * (3 - sqrt(5)); out = Set{Vec3}()
    for i in 0:n - 1
        y = 1 - 2(i + 0.5) / n; r = sqrt(1 - y^2); t = golden * i
        d = (r * cos(t), y, r * sin(t))
        push!(out, argmax(v -> vdot(v, d), m.vertices))
    end
    return collect(out)
end

function _jconvex_hull(points::Vector{Vec3}, radius)
    pts = [_jv(p) for p in points]
    s = _jnew(:ConvexHullShapeSettings, J.JPH_ConvexHullShapeSettings_ConvexHullShapeSettings, pts, length(pts), Float32(radius))
    try
        return GC.@preserve pts _jresult_shape(J.JPH_ConvexHullShapeSettings_Create(s))
    finally
        _jdelete(:ConvexHullShapeSettings, s)
    end
end

function _jtriangle_mesh(m::TriMesh)
    s = _jnew(:MeshShapeSettings, J.JPH_MeshShapeSettings_MeshShapeSettings)
    verts = J.Float3[J.Float3(v...) for v in m.vertices]
    tris = J.IndexedTriangle[J.IndexedTriangle((UInt32(f[1] - 1), UInt32(f[2] - 1), UInt32(f[3] - 1)), 0, 0) for f in m.faces]
    T = J.MeshShapeSettings
    VA = fieldtype(T, :mTriangleVertices); TA = fieldtype(T, :mIndexedTriangles)
    GC.@preserve verts tris begin
        # The settings' arrays point at these Julia buffers just for Create
        # (it copies them into the shape) and are emptied before the
        # destructor would free them.
        _jpoke!(s, T, :mTriangleVertices, VA(length(verts), length(verts), pointer(verts)))
        _jpoke!(s, T, :mIndexedTriangles, TA(length(tris), length(tris), pointer(tris)))
        try
            # what upstream's array constructor does: drop degenerate and
            # duplicate triangles (in place, so the buffers stay ours)
            J.JPH_MeshShapeSettings_Sanitize(s)
            return _jresult_shape(J.JPH_MeshShapeSettings_Create(s))
        finally
            _jpoke!(s, T, :mTriangleVertices, VA(0, 0, C_NULL))
            _jpoke!(s, T, :mIndexedTriangles, TA(0, 0, C_NULL))
            _jdelete(:MeshShapeSettings, s)
        end
    end
end

# Jolt rounds convex shapes by a convex radius; keep it well inside thin ones.
_jradius(extent) = min(0.05f0, 0.2f0 * Float32(extent))

function _jshape(s::ObjectSpec, mesh::TriMesh)
    if s.shape == :box
        h = vscale(s.size, 0.5f0)
        p = _jnew(:BoxShape, J.JPH_BoxShape_BoxShape, _jv(h), _jradius(minimum(h)))
    elseif s.shape == :sphere
        p = _jnew(:SphereShape, J.JPH_SphereShape_SphereShape, Float32(s.radius))
    elseif s.shape == :capsule
        p = _jnew(:CapsuleShape, J.JPH_CapsuleShape_CapsuleShape, Float32(max(1f-3, s.height / 2 - s.radius)), Float32(s.radius))
    elseif s.shape == :cylinder
        p = _jnew(:CylinderShape, J.JPH_CylinderShape_CylinderShape, Float32(s.height / 2), Float32(s.radius),
                  _jradius(min(s.height / 2, s.radius)))
    elseif s.shape == :cone || s.shape == :hull           # Jolt has no cone: its hull
        lo, hi = aabb(mesh)
        return _jconvex_hull(_jhull_points(mesh), _jradius(minimum(vsub(hi, lo)) / 2))
    elseif s.shape == :mesh
        return _jtriangle_mesh(mesh)
    else
        error("ObjectSim: unknown shape $(s.shape)")
    end
    return Ptr{Cvoid}(p)
end

# ── bodies ───────────────────────────────────────────────────────────────────

const _BCS = J.BodyCreationSettings

function _be_add_body!(P::JoltPhysics, w::World, b::Body, com)
    s = b.spec
    shape = _jshape(s, b.mesh)
    fresh = s.shape in (:cone, :hull, :mesh)              # from Create: we hold a reference
    R = rotation_matrix(s.rotation)
    origin = vadd(s.position, _rotate(R, com))
    q = _jquat_from_rows(R)
    static = s.mass == 0
    group, mask = _filter(w, s)
    layer = _jlayer!(P, group, mask, static)
    bcs = _jnew(:BodyCreationSettings, J.JPH_BodyCreationSettings_BodyCreationSettings,
                Ptr{J.Shape}(shape), _jv(origin), _jq(q), J.EMotionType(static ? _J_STATIC : _J_DYNAMIC), layer)
    local id
    try
        _jpoke!(bcs, _BCS, :mFriction, Float32(s.friction))
        _jpoke!(bcs, _BCS, :mRestitution, Float32(s.restitution))
        _jpoke!(bcs, _BCS, :mIsSensor, s.trigger)
        if !static
            _jpoke!(bcs, _BCS, :mLinearDamping, Float32(s.damping[1]))
            _jpoke!(bcs, _BCS, :mAngularDamping, Float32(s.damping[2]))
            _jpoke!(bcs, _BCS, :mLinearVelocity, _jv(s.velocity))
            _jpoke!(bcs, _BCS, :mAngularVelocity, _jv(s.spin))
            _jpoke!(bcs, _BCS, :mMaxLinearVelocity, 1000f0)
            _jpoke!(bcs, _BCS, :mMaxAngularVelocity, 1000f0)
            _jpoke!(bcs, _BCS, :mGravityFactor, s.gravity === nothing ? 1f0 : 0f0)
            _jpoke!(bcs, _BCS, :mAllowSleeping, s.sleep && w.mutual_G == 0)
            # the scene's mass, inertia from the shape (EOverrideMassProperties::CalculateInertia)
            _jpoke!(bcs, _BCS, :mOverrideMassProperties, J.EOverrideMassProperties(0x01))
            mp = _jpeek(bcs, _BCS, :mMassPropertiesOverride)
            _jpoke!(bcs, _BCS, :mMassPropertiesOverride, _with(mp; mMass = Float32(s.mass)))
        end
        id = J.JPH_BodyInterface_CreateAndAddBody(P.bi, bcs, J.EActivation(static ? _J_DONT_ACTIVATE : _J_ACTIVATE))
    finally
        _jdelete(:BodyCreationSettings, bcs)               # the body keeps its own reference
    end
    id.mID == typemax(UInt32) && error("ObjectSim: Jolt is out of bodies")
    fresh && _jrelease_shape!(shape)
    ptr = Ptr{Cvoid}(J.JPH_BodyLockInterface_TryGetBody(P.bl, Ref(id)))
    mp = Ptr{Cvoid}(_jpeek(ptr, J.Body, :mMotionProperties))
    # Body::mPosition is the centre of mass; the shape's origin sits `offset` from it.
    pos = Ref(_jv((0, 0, 0))); rot = Ref(_jq((0, 0, 0, 1)))
    J.JPH_BodyInterface_GetPositionAndRotation(P.bi, Ref(id), pos, rot)
    cm = _jxyz(ptr)
    offset = _rotate(_transpose(R), vsub(_jxyz(pos[]), cm))
    pose = (_jquat(ptr + _joff(J.Body, :mRotation)), cm)
    h = JoltBody(P, id, Ref(id), ptr, static ? C_NULL : mp, offset, s.gravity, pose, pose, s.trigger)
    P.index[id.mID] = b
    return h
end

# Drop the reference ShapeSettings::Create's result left with us (RefTarget's
# count, the word after the vtable pointer); the body holds its own.
function _jrelease_shape!(shape::Ptr{Cvoid})
    rc = Ptr{UInt32}(shape + 8)
    unsafe_store!(rc, unsafe_load(rc) - UInt32(1))
end

function _be_free_body!(P::JoltPhysics, w::World, b::Body)
    h = _jh(b)
    delete!(P.index, h.id.mID)
    J.JPH_BodyInterface_RemoveBody(P.bi, h.idref)
    J.JPH_BodyInterface_DestroyBody(P.bi, h.idref)   # last reference: the shape goes too
    h.ptr = C_NULL
end

# ── stepping ─────────────────────────────────────────────────────────────────

_jpool_size() = JOLT_THREADS[] < 0 ? clamp(Sys.CPU_THREADS - 1, 1, 4) : JOLT_THREADS[]

# How many rigid bodies are awake.
_jnum_active(P::JoltPhysics) = Int(J.JPH_PhysicsSystem_GetNumActiveBodies(P.ps, J.RigidBody))

# The job system for this step (see JOLT_THREADS).
function _jjobs(P::JoltPhysics)
    n = _jpool_size()
    (n == 0 || _jnum_active(P) < JOLT_POOL_FROM[]) && return P.single
    if P.pool == C_NULL
        P.pool = _jnew(:JobSystemThreadPool, J.JPH_JobSystemThreadPool_JobSystemThreadPool, 2048, 8, n)
    end
    return P.pool
end

function _jpose(h::JoltBody)
    return (_jquat(h.ptr + _joff(J.Body, :mRotation)), _jxyz(h.ptr))
end

function _be_step!(P::JoltPhysics, w::World)
    dt = w.dt
    P.dt = dt
    _pre_step!(w, dt)                      # springs and hooks read the state as the last step left it
    for b in w.bodies
        h = _jh(b)
        h.mp == C_NULL && continue
        h.prev = h.curr
        # own gravity: Jolt has a gravity factor, not a vector
        h.gravity === nothing || J.JPH_BodyInterface_AddImpulse(P.bi, h.idref, _jv(vscale(h.gravity, mass(b) * dt)))
    end
    J.JoltHub_ContactRecorder_Clear(P.recorder)
    err = J.JPH_PhysicsSystem_Update(P.ps, dt, 1, P.temp, _jjobs(P))
    for b in w.bodies
        h = _jh(b)
        h.mp == C_NULL || (h.curr = _jpose(h))
    end
    P.nrows = -1                                         # contacts read lazily
    _jbreak_joints!(P, w)
    return err
end

function _be_advance!(P::JoltPhysics, w::World, seconds, max_substeps)
    P.leftover += seconds
    n = 0
    while P.leftover >= w.dt && n < max_substeps
        _be_step!(P, w); P.leftover -= w.dt; n += 1
        _rethrow_hook_error!(w)
    end
    P.leftover >= w.dt && (P.leftover = mod(P.leftover, w.dt))   # a long frame: drop the rest
    return n
end

# ── poses and velocities ─────────────────────────────────────────────────────

function _jtransform(h::JoltBody, pose)
    q, cm = pose
    R = _jrows(q)
    return R, vadd(cm, _rotate(R, h.offset))
end

_be_transform(::JoltPhysics, b::Body) = _jtransform(_jh(b), _jpose(_jh(b)))

# The pose at (last step − dt + leftover): between the previous step and the
# current one, like bullet3's latency interpolation.
function _be_render_transform(P::JoltPhysics, b::Body)
    h = _jh(b)
    h.mp == C_NULL && return _be_transform(P, b)
    t = clamp(P.leftover / P.dt, 0f0, 1f0)
    (q0, c0), (q1, c1) = h.prev, h.curr
    vdot(q0, q1) < 0 && (q1 = .-q1)
    q = q0 .+ t .* (q1 .- q0); q = q ./ sqrt(sum(abs2, q))
    return _jtransform(h, (q, vadd(c0, vscale(vsub(c1, c0), t))))
end

_be_velocity(::JoltPhysics, b::Body) = _jh(b).mp == C_NULL ? (0f0, 0f0, 0f0) :
    _jxyz(_jh(b).mp + _joff(J.MotionProperties, :mLinearVelocity))
_be_spin(::JoltPhysics, b::Body) = _jh(b).mp == C_NULL ? (0f0, 0f0, 0f0) :
    _jxyz(_jh(b).mp + _joff(J.MotionProperties, :mAngularVelocity))
_be_sleeping(P::JoltPhysics, b::Body) = _jh(b).mp != C_NULL && !J.JPH_BodyInterface_IsActive(P.bi, _jh(b).idref)
_be_wake!(P::JoltPhysics, b::Body) = _jh(b).mp == C_NULL || J.JPH_BodyInterface_ActivateBody(P.bi, _jh(b).idref)
function _be_keep_awake!(P::JoltPhysics, b::Body, on::Bool)
    _jh(b).mp == C_NULL && return
    J.JPH_Body_SetAllowSleeping(_jh(b).ptr, !on)
    _be_wake!(P, b)
end

function _be_set_velocity!(P::JoltPhysics, b::Body, v, spin)
    J.JPH_BodyInterface_SetLinearVelocity(P.bi, _jh(b).idref, _jv(v))
    spin === nothing || J.JPH_BodyInterface_SetAngularVelocity(P.bi, _jh(b).idref, _jv(spin))
end

_be_impulse!(P::JoltPhysics, b::Body, Jv, at) = at === nothing ?
    J.JPH_BodyInterface_AddImpulse(P.bi, _jh(b).idref, _jv(Jv)) :
    J.JPH_BodyInterface_AddImpulse(P.bi, _jh(b).idref, _jv(Jv), _jv(at))
_be_angular_impulse!(P::JoltPhysics, b::Body, T) = J.JPH_BodyInterface_AddAngularImpulse(P.bi, _jh(b).idref, _jv(T))

# MotionProperties::ScaleToMass keeps the inertia's shape and scales it.
_be_set_mass!(::JoltPhysics, b::Body, m) = J.JPH_MotionProperties_ScaleToMass(_jh(b).mp, Float32(m))
_be_set_friction!(P::JoltPhysics, b::Body, f) = J.JPH_BodyInterface_SetFriction(P.bi, _jh(b).idref, Float32(f))
_be_set_restitution!(P::JoltPhysics, b::Body, e) = J.JPH_BodyInterface_SetRestitution(P.bi, _jh(b).idref, Float32(e))
# Jolt has no rolling friction; the setting is kept in the spec and ignored.
_be_set_rolling_friction!(::JoltPhysics, b::Body, f) = nothing
function _be_set_damping!(::JoltPhysics, b::Body, lin, ang)
    J.JPH_MotionProperties_SetLinearDamping(_jh(b).mp, Float32(lin))
    J.JPH_MotionProperties_SetAngularDamping(_jh(b).mp, Float32(ang))
end

function _be_set_body_gravity!(P::JoltPhysics, w::World, b::Body, g)
    _jh(b).mp == C_NULL && return
    _jh(b).gravity = g
    J.JPH_BodyInterface_SetGravityFactor(P.bi, _jh(b).idref, g === nothing ? 1f0 : 0f0)
end
_be_body_gravity(P::JoltPhysics, b::Body) = something(_jh(b).gravity, P.gravity)
_be_istrigger(::JoltPhysics, b::Body) = _jh(b).sensor

# ── queries ──────────────────────────────────────────────────────────────────

# NarrowPhaseQuery::CastRay, closest hit; the normal is the hit body's own
# (Body::GetWorldSpaceSurfaceNormal at the hit's sub-shape and point).
function _be_raycast(P::JoltPhysics, w::World, from, to)
    ray = J.RRayCast(_jv(from), _jv(vsub(to, from)))
    hit = Ref(J.RayCastResult(J.BodyID(typemax(UInt32)), 1f0 + eps(Float32), J.SubShapeID(typemax(UInt32))))
    J.JPH_NarrowPhaseQuery_CastRay(P.npq, Ref(ray), hit) || return nothing
    h = hit[]
    b = get(P.index, h.mBodyID.mID, nothing)
    b === nothing && return nothing
    p = vadd(from, vscale(vsub(to, from), h.mFraction))
    n = _jxyz(J.JPH_Body_GetWorldSpaceSurfaceNormal(_jh(b).ptr, Ref(h.mSubShapeID2), _jv(p)))
    return (body = b, point = p, normal = n, fraction = h.mFraction)
end

# Contacts are what Jolt's listener reported during the last Update (the
# shim's ContactRecorder): one row per contact manifold, with its first point,
# its normal (body 1 → body 2) and penetration depth. Jolt reports only pairs
# that involve an awake body, so a pile that has gone to sleep reports none.
# The impulse isn't available after solving; it is the reduced mass times the
# closing speed at that point (0 for resting contacts and sensors).
function _jread_contacts!(P::JoltPhysics)
    P.nrows >= 0 && return P.nrows
    ids, f, flags = P.rows
    n = J.JoltHub_ContactRecorder_Count(P.recorder)
    if n > length(flags)
        resize!(ids, 2n); resize!(f, 8n); resize!(flags, n)
    end
    P.nrows = GC.@preserve ids f flags J.JoltHub_ContactRecorder_Read(P.recorder, pointer(ids), pointer(f),
                                                                     pointer(flags), length(flags))
    return P.nrows
end

function _be_contacts(P::JoltPhysics, w::World, within)
    out = Contact[]
    ids, f, flags = P.rows
    for i in 1:_jread_contacts!(P)
        a = get(P.index, ids[2i - 1], nothing); b = get(P.index, ids[2i], nothing)
        (a === nothing || b === nothing) && continue
        k = 8(i - 1)
        depth = -f[k + 7]
        depth > within && continue
        m = (isstatic(a) ? 0.0 : 1 / mass(a)) + (isstatic(b) ? 0.0 : 1 / mass(b))
        impulse = (flags[i] & 0x1) != 0 || m == 0 ? 0f0 : Float32(max(f[k + 8], 0f0) / m)
        push!(out, Contact(a, b, (f[k + 1], f[k + 2], f[k + 3]), (-f[k + 4], -f[k + 5], -f[k + 6]), impulse, depth))
    end
    return out
end
