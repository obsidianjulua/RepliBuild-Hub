# The bullet3 side: a dynamics world and the bodies in it.
#
# Every C++ object lives on storage from Bullet's own aligned allocator
# (btAlignedAllocInternal), which is what Bullet's class-level operator new
# uses. That is why `<Class>_delete_<Class>` (the deleting destructor, which
# frees through the same allocator) is the right way to free shapes, bodies
# and mesh interfaces: every class used here inherits BT_DECLARE_ALIGNED_ALLOCATOR
# from btCollisionShape, btCollisionObject or btStridingMeshInterface.
#
# Header-inline constructors have no symbol in the library (btDefaultMotionState,
# btSphereShape, btRigidBodyConstructionInfo), so: no motion states (a body's
# world transform is read straight from the object), spheres are a one-sphere
# btMultiSphereShape, and the construction info is filled field by field with
# upstream's defaults, as packages/bullet3/test_deep.jl does.

const _OFF_XFORM  = B.member_offset(:btCollisionObject, :m_worldTransform)
const _OFF_ACTIVE = B.member_offset(:btCollisionObject, :m_activationState1)
const _OFF_LINVEL = B.member_offset(:btRigidBody, :m_linearVelocity)
const _OFF_ANGVEL = B.member_offset(:btRigidBody, :m_angularVelocity)

# btCollisionObject.h activation states
const ACTIVE_TAG = 1
const ISLAND_SLEEPING = 2
const DISABLE_DEACTIVATION = 4

_alloc(cls::Symbol) = B.btAlignedAllocInternal(B.struct_size(cls), 16)
_btv(v) = B.btVector3((Float32(v[1]), Float32(v[2]), Float32(v[3]), 0f0))
_tuple(v::B.btVector3) = (v.m_floats[1], v.m_floats[2], v.m_floats[3])
_delete(cls::Symbol, p::Ptr) = getfield(B, Symbol(cls, "_delete_", cls))(p)

"""
    rotation_matrix(degrees) -> rows

Rotation about X, then Y, then Z (R = Rz·Ry·Rx), as three row tuples.
"""
function rotation_matrix(deg)
    x, y, z = deg2rad.(Float64.(deg))
    cx, sx, cy, sy, cz, sz = cos(x), sin(x), cos(y), sin(y), cos(z), sin(z)
    return (v3(cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx),
            v3(sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx),
            v3(-sy, cy * sx, cy * cx))
end
_rotate(R, v) = (vdot(R[1], v), vdot(R[2], v), vdot(R[3], v))

"""
    Body

One rigid body. `mesh` is its geometry in the body's own frame, which for
`hull` objects is centred on the centre of mass. `ptr` is the btRigidBody.
"""
mutable struct Body
    name::String
    spec::ObjectSpec
    ptr::Ptr{Cvoid}
    shape::Ptr{Cvoid}
    shape_class::Symbol
    iface::Ptr{Cvoid}          # btTriangleIndexVertexArray for `mesh`, else C_NULL
    mesh::TriMesh
    keep::Vector{Any}          # buffers bullet3 points into but does not copy
end

Base.show(io::IO, b::Body) = print(io, "Body(\"", b.name, "\", ", b.spec.shape,
    b.spec.mass == 0 ? ", static" : ", $(b.spec.mass) kg", ")")

"""
    World(scene::SceneSpec)
    World(path::AbstractString)

A btDiscreteDynamicsWorld with every object of the scene in it. Call
[`destroy!`](@ref) when done; nothing is freed by the garbage collector.
"""
mutable struct World
    scene::SceneSpec
    cfg::Ptr{Cvoid}
    disp::Ptr{Cvoid}
    bp::Ptr{Cvoid}
    solver::Ptr{Cvoid}
    world::Ptr{Cvoid}
    bodies::Vector{Body}
    dt::Float32
    steps::Int
    alive::Bool
end

World(path::AbstractString) = World(load_scene(path))

function World(scene::SceneSpec)
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
    B.btDiscreteDynamicsWorld_setGravity(world, Ref(_btv(scene.world.gravity)))

    w = World(scene, cfg, disp, bp, solver, world, Body[], 1f0 / scene.world.hz, 0, true)
    try
        foreach(s -> add!(w, s), scene.objects)
    catch
        destroy!(w)
        rethrow()
    end
    return w
end

Base.show(io::IO, w::World) = print(io, "World(\"", w.scene.name, "\", ", length(w.bodies),
    " bodies, t = ", round(sim_time(w); digits = 3), " s", w.alive ? "" : ", destroyed", ")")

"""Simulated seconds so far."""
sim_time(w::World) = w.steps * Float64(w.dt)

# Build the collision shape for a spec. Returns the shape, its class, the
# body-local mesh, the offset from the spec's origin to the centre of mass
# (in the object's unrotated frame), the mesh interface and kept buffers.
function _shape(s::ObjectSpec)
    keep = Any[]; iface = C_NULL; com = (0f0, 0f0, 0f0)
    if s.shape == :box
        h = vscale(s.size, 0.5f0)
        cls = :btBoxShape; p = _alloc(cls)
        B.btBoxShape_btBoxShape(p, Ref(_btv(h)))
        mesh = box_mesh(h)
    elseif s.shape == :sphere
        cls = :btMultiSphereShape; p = _alloc(cls)
        B.btMultiSphereShape_btMultiSphereShape(p, Ref(_btv((0, 0, 0))), Ref(s.radius), 1)
        mesh = sphere_mesh(s.radius)
    elseif s.shape == :capsule
        straight = s.height - 2s.radius           # bullet3: distance between sphere centres
        cls = :btCapsuleShape; p = _alloc(cls)
        B.btCapsuleShape_btCapsuleShape(p, s.radius, straight)
        mesh = capsule_mesh(s.radius, straight / 2)
    elseif s.shape == :cylinder
        cls = :btCylinderShape; p = _alloc(cls)
        B.btCylinderShape_btCylinderShape(p, Ref(_btv((s.radius, s.height / 2, s.radius))))
        mesh = cylinder_mesh(s.radius, s.height / 2)
    elseif s.shape == :cone
        cls = :btConeShape; p = _alloc(cls)
        B.btConeShape_btConeShape(p, s.radius, s.height)
        mesh = cone_mesh(s.radius, s.height)
    elseif s.shape == :hull
        m = transform_mesh(load_mesh(s.asset); scale = s.scale)
        com = centroid(m)
        mesh = transform_mesh(m; offset = vscale(com, -1f0))
        pts = reinterpret(Float32, mesh.vertices) |> collect   # copied by the constructor
        cls = :btConvexHullShape; p = _alloc(cls)
        GC.@preserve pts B.btConvexHullShape_btConvexHullShape(p, pointer(pts), length(mesh.vertices), 12)
        B.btConvexHullShape_optimizeConvexHull(p)           # keep only the hull's own points
        B.btConvexHullShape_setLocalScaling(p, Ref(_btv((1, 1, 1))))   # recomputes the cached AABB
    elseif s.shape == :mesh
        mesh = transform_mesh(load_mesh(s.asset); scale = s.scale)
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
    return p, cls, mesh, com, iface, keep
end

function _inertia(cls::Symbol, p::Ptr, mass::Float32)
    inertia = Ref(_btv((0, 0, 0)))
    mass == 0 && return inertia[]
    f = cls == :btConvexHullShape ? B.btPolyhedralConvexShape_calculateLocalInertia :
        getfield(B, Symbol(cls, "_calculateLocalInertia"))
    f(p, mass, inertia)
    return inertia[]
end

"""
    add!(w, spec) -> Body

Create the shape and rigid body for one object and add it to the world.
"""
function add!(w::World, s::ObjectSpec)
    _check(w)
    p, cls, mesh, com, iface, keep = _shape(s)
    R = rotation_matrix(s.rotation)
    origin = vadd(s.position, _rotate(R, com))     # spec position is the asset's origin
    xf = B.btTransform(B.btMatrix3x3((_btv(R[1]), _btv(R[2]), _btv(R[3]))), _btv(origin))
    ci = Ref(B.btRigidBodyConstructionInfo(
        s.mass, ntuple(_ -> 0x00, 4),
        Ptr{B.btMotionState}(C_NULL), xf,
        Ptr{B.btCollisionShape}(p), _inertia(cls, p, s.mass),
        s.damping[1], s.damping[2],
        s.friction, s.rolling_friction, 0f0,      # friction, rolling, spinning
        s.restitution,
        0.8f0, 1.0f0,                             # sleeping thresholds
        false, ntuple(_ -> 0x00, 3),
        0.005f0, 0.01f0, 0.01f0, 0.01f0,
        ntuple(_ -> 0x00, 4)))
    body = _alloc(:btRigidBody)
    B.btRigidBody_btRigidBody(body, ci)
    if s.mass > 0
        unsafe_store!(Ptr{B.btVector3}(body + _OFF_LINVEL), _btv(s.velocity))
        unsafe_store!(Ptr{B.btVector3}(body + _OFF_ANGVEL), _btv(s.spin))
    end
    B.btDiscreteDynamicsWorld_addRigidBody(w.world, body)
    b = Body(s.name, s, body, p, cls, iface, mesh, keep)
    push!(w.bodies, b)
    return b
end

"""
    step!(w, n = 1) -> w

Advance `n` fixed steps of `1/hz` seconds each.
"""
function step!(w::World, n::Integer = 1)
    _check(w)
    for _ in 1:n
        B.btDiscreteDynamicsWorld_stepSimulation(w.world, w.dt, 1, w.dt)
    end
    w.steps += n
    return w
end

"""
    simulate!(w, seconds) -> w

Step until `seconds` more simulated time has passed.
"""
simulate!(w::World, seconds::Real) = step!(w, round(Int, seconds / w.dt))

"""The body's world transform as (rotation rows, origin of the centre of mass)."""
function transform(b::Body)
    t = unsafe_load(Ptr{B.btTransform}(b.ptr + _OFF_XFORM))
    el = t.m_basis.m_el
    return (_tuple(el[1]), _tuple(el[2]), _tuple(el[3])), _tuple(t.m_origin)
end

"""World position of the body's centre of mass. (A method of `Base.position`,
so `position(body)` works after `using ObjectSim` without a name clash.)"""
Base.position(b::Body) = transform(b)[2]
"""Linear velocity, m/s."""
velocity(b::Body) = _tuple(unsafe_load(Ptr{B.btVector3}(b.ptr + _OFF_LINVEL)))
"""Angular velocity, rad/s."""
spin(b::Body) = _tuple(unsafe_load(Ptr{B.btVector3}(b.ptr + _OFF_ANGVEL)))
"""Whether bullet3 has put the body to sleep (it stopped moving)."""
sleeping(b::Body) = unsafe_load(Ptr{Cint}(b.ptr + _OFF_ACTIVE)) == ISLAND_SLEEPING
isstatic(b::Body) = b.spec.mass == 0

body(w::World, name::AbstractString) =
    something(findfirst(b -> b.name == name, w.bodies), 0) |>
    i -> i == 0 ? error("ObjectSim: no body named '$name'") : w.bodies[i]

"""
    snapshot(w) -> Vector{NamedTuple}

Name, position, velocity and sleep state of every moving body.
"""
snapshot(w::World) = [(name = b.name, position = position(b), velocity = velocity(b),
                       sleeping = sleeping(b)) for b in w.bodies if !isstatic(b)]

_check(w::World) = w.alive || error("ObjectSim: the world has been destroyed")

"""
    destroy!(w)

Remove and free every body, shape and the world itself, in upstream's order.
Safe to call twice.
"""
function destroy!(w::World)
    w.alive || return nothing
    w.alive = false
    for b in reverse(w.bodies)
        B.btDiscreteDynamicsWorld_removeRigidBody(w.world, b.ptr)
        _delete(:btRigidBody, b.ptr)
        _delete(b.shape_class, b.shape)
        b.iface == C_NULL || _delete(:btTriangleIndexVertexArray, b.iface)
        empty!(b.keep)
    end
    empty!(w.bodies)
    B.btDiscreteDynamicsWorld_destroy_btDiscreteDynamicsWorld(w.world)
    B.btSequentialImpulseConstraintSolver_destroy_btSequentialImpulseConstraintSolver(w.solver)
    B.btDbvtBroadphase_destroy_btDbvtBroadphase(w.bp)
    B.btCollisionDispatcher_destroy_btCollisionDispatcher(w.disp)
    B.btDefaultCollisionConfiguration_destroy_btDefaultCollisionConfiguration(w.cfg)
    foreach(B.btAlignedFreeInternal, (w.world, w.solver, w.bp, w.disp, w.cfg))
    return nothing
end

"""
    with_world(f, scene_or_path)

Build a world, run `f(world)`, and destroy it afterwards even on error.
"""
function with_world(f, scene)
    w = World(scene)
    try
        return f(w)
    finally
        destroy!(w)
    end
end
