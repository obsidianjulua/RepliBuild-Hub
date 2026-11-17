# The world and its bodies, whichever physics engine runs them.
#
# ObjectSim has two physics backends, kept apart in src/backends/:
#   jolt/      Jolt Physics' PhysicsSystem (the default)
#   bullet3/   btDiscreteDynamicsWorld
# Everything outside src/backends/ — scenes, the viewer, water, springs,
# mutual gravity, force hooks, picking logic, layers — is shared and talks to
# a backend only through the `_be_*` functions listed below. A World holds its
# backend's state in `w.phys` and each Body its backend handle in `b.h`.
#
# The backend interface (`P` is the backend's state, a subtype of Physics):
#   _be_world(::Val{name}, w) -> P          make the engine's world
#   _be_destroy!(P, w)                      free it (bodies and joints are gone already)
#   _be_set_gravity!(P, g)
#   _be_iterations(P), _be_set_iterations!(P, n)
#   _be_add_body!(P, w, spec, mesh, com) -> handle
#   _be_free_body!(P, w, b)
#   _be_step!(P, w)                         one fixed step of w.dt; calls _pre_step!(w, dt) first
#   _be_advance!(P, w, seconds, max_substeps) -> steps taken (real-time loop)
#   _be_transform(P, b), _be_render_transform(P, b) -> (rotation rows, origin)
#   _be_velocity(P, b), _be_spin(P, b), _be_set_velocity!(P, b, v, spin)
#   _be_impulse!(P, b, J, at)               at = nothing: through the centre of mass
#   _be_angular_impulse!(P, b, T)
#   _be_sleeping(P, b), _be_wake!(P, b), _be_keep_awake!(P, b, on::Bool)
#   _be_set_mass!(P, b, m), _be_set_friction!, _be_set_restitution!,
#   _be_set_rolling_friction!, _be_set_damping!(P, b, lin, ang)
#   _be_set_body_gravity!(P, w, b, g), _be_body_gravity(P, w, b), _be_istrigger(P, b)
#   _be_raycast(P, w, from, to) -> (body, point, normal, fraction) or nothing
#   _be_contacts(P, w, within) -> Vector{Contact}
#   _be_add_joint!(P, w, spec, a, b, pa, pb) -> handle
#   _be_free_joint!(P, w, j), _be_broken(P, j), _be_set_motor!(P, j, factor)
#   _be_grab!(P, w, b, local_point, world_point) -> handle
#   _be_drag!(P, w, pick, world_point), _be_release!(P, w, pick)
#   _be_name(P) -> "bullet3" / "jolt"

"""Physics engine state behind a World (one subtype per backend)."""
abstract type Physics end

const BACKENDS = ("bullet3", "jolt")

"""The backend a World uses when neither `World(…; backend)` nor the scene's
`[world] backend` names one. Starts as \$OBJECTSIM_BACKEND, else "jolt"."""
const DEFAULT_BACKEND = Ref("jolt")

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
`hull` objects is centred on the centre of mass. `h` is the backend's handle
(`nothing` once the body has been removed).
"""
mutable struct Body
    name::String
    spec::ObjectSpec
    h::Any
    mesh::TriMesh
end

Base.show(io::IO, b::Body) = print(io, "Body(\"", b.name, "\", ", b.spec.shape,
    b.spec.mass == 0 ? ", static" : ", $(b.spec.mass) kg", b.h === nothing ? ", removed" : "", ")")

"""Whether the body is still in its world (not removed or destroyed)."""
isalive(b::Body) = b.h !== nothing

"""
    World(scene; backend = nothing)
    World(path; backend = nothing)

A physics world with every object of the scene in it, run by `backend`
("jolt" or "bullet3"; default: the scene's `[world] backend`, else jolt).
Call [`destroy!`](@ref) when done; nothing is freed by the garbage collector.
"""
mutable struct World
    scene::SceneSpec
    phys::Physics                        # set right after construction
    bodies::Vector{Body}
    joints::Vector{Any}                  # Vector{Joint}; Joint is defined in joints.jl
    pick::Any                            # the Pick in progress, or nothing
    gravity::Vec3
    dt::Float32
    steps::Int
    spawned::Int                         # bodies added after the scene loaded
    layers::Dict{String,Int32}           # collision layer name → group bit
    forces::Vector{Any}                  # f(w, dt) run before every fixed step
    hook_error::Any                      # an error a force hook threw, rethrown after the step
    mutual::Any                          # the mutual-gravity hook in `forces`, or nothing
    mutual_G::Float64
    water::Any                           # (WaterSpec, its force hook), or nothing
    spring_key::UInt                     # what `springs` was last worked out for (joints.jl)
    springs::Any                         # the springs' _SpringSystem (joints.jl), or nothing
    alive::Bool
    # the bare struct; the public constructors below fill it
    World(scene::SceneSpec, ::Val{:bare}) = new(scene, _NoPhysics(), Body[], Any[], nothing, scene.world.gravity,
                                  1f0 / scene.world.hz, 0, 0, Dict{String,Int32}(), Any[], nothing,
                                  nothing, 0.0, nothing, UInt(0), nothing, true)
end

struct _NoPhysics <: Physics end

World(path::AbstractString; backend = nothing) = World(load_scene(path); backend)

function World(scene::SceneSpec; backend = nothing)
    name = String(something(backend, isempty(scene.world.backend) ? DEFAULT_BACKEND[] : scene.world.backend))
    name in BACKENDS || error("ObjectSim: unknown backend '$name' (one of: $(join(BACKENDS, ", ")))")
    w = World(scene, Val(:bare))
    w.phys = _be_world(Val(Symbol(name)), w)
    try
        scene.world.mutual_gravity > 0 && set_mutual_gravity!(w, scene.world.mutual_gravity)
        scene.world.water === nothing || set_water!(w, scene.world.water)
        foreach(s -> add!(w, s), scene.objects)
        foreach(j -> add_joint!(w, j), scene.joints)
    catch
        destroy!(w)
        rethrow()
    end
    return w
end

"""Which physics engine runs the world: "bullet3" or "jolt"."""
backend(w::World) = _be_name(w.phys)

Base.show(io::IO, w::World) = print(io, "World(\"", w.scene.name, "\", ", backend(w), ", ", length(w.bodies),
    " bodies, t = ", round(sim_time(w); digits = 3), " s", w.alive ? "" : ", destroyed", ")")

"""Simulated seconds so far."""
sim_time(w::World) = w.steps * Float64(w.dt)

# The body-local mesh for a spec and the offset from the spec's origin to its
# centre of mass (in the object's unrotated frame). Backends build their
# collision shape from the spec, and from this mesh for `hull` and `mesh`.
function _body_mesh(s::ObjectSpec)
    com = (0f0, 0f0, 0f0)
    mesh = if s.shape == :box
        box_mesh(vscale(s.size, 0.5f0))
    elseif s.shape == :sphere
        sphere_mesh(s.radius)
    elseif s.shape == :capsule
        capsule_mesh(s.radius, (s.height - 2s.radius) / 2)
    elseif s.shape == :cylinder
        cylinder_mesh(s.radius, s.height / 2)
    elseif s.shape == :cone
        cone_mesh(s.radius, s.height)
    elseif s.shape == :hull
        m = transform_mesh(load_mesh(s.asset); scale = s.scale)
        com = centroid(m)
        transform_mesh(m; offset = vscale(com, -1f0))
    elseif s.shape == :mesh
        transform_mesh(load_mesh(s.asset); scale = s.scale)
    else
        error("ObjectSim: unknown shape $(s.shape)")
    end
    return mesh, com
end

"""
    add!(w, spec) -> Body

Create the shape and rigid body for one object and add it to the world.
"""
function add!(w::World, s::ObjectSpec)
    _check(w)
    mesh, com = _body_mesh(s)
    b = Body(s.name, s, nothing, mesh)
    b.h = _be_add_body!(w.phys, w, b, com)
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
        _be_step!(w.phys, w)
        w.steps += 1
        _rethrow_hook_error!(w)
    end
    return w
end

"""
    advance!(w, seconds; max_substeps = 8) -> Int

A variable timestep, as a real-time loop has: runs as many fixed `1/hz` steps
as fit (at most `max_substeps`, dropping the rest of a long frame), keeps the
remainder for next time, and sets every moving body's
[`render_transform`](@ref) to its pose at (last step − dt + remainder),
between the previous step and the current one. Returns the steps taken.
"""
function advance!(w::World, seconds::Real; max_substeps::Integer = 8)
    _check(w)
    n = _be_advance!(w.phys, w, Float32(seconds), max_substeps)
    w.steps += n
    _rethrow_hook_error!(w)
    return Int(n)
end

"""
    simulate!(w, seconds) -> w

Step until `seconds` more simulated time has passed.
"""
simulate!(w::World, seconds::Real) = step!(w, round(Int, seconds / w.dt))

"""The body's world transform after the last fixed step, as (rotation rows,
origin of the centre of mass)."""
transform(b::Body) = _be_transform(_phys(b), b)

"""
    render_transform(b)

The pose to draw: between the previous fixed step and the current one (it
trails [`transform`](@ref) by up to one step), so motion stays smooth when the
display rate isn't a multiple of the physics rate. [`advance!`](@ref) is what
makes the leftover time; static bodies return [`transform`](@ref).
"""
render_transform(b::Body) = _be_render_transform(_phys(b), b)

# A body's backend, reached through its handle (every handle knows its world's
# Physics), so body-only functions keep their one-argument form.
_phys(b::Body) = (b.h === nothing && error("ObjectSim: $(b.name) has been removed"); b.h.phys)

"""World position of the body's centre of mass. (A method of `Base.position`,
so `position(body)` works after `using ObjectSim` without a name clash.)"""
Base.position(b::Body) = transform(b)[2]
"""Linear velocity, m/s."""
velocity(b::Body) = _be_velocity(_phys(b), b)
"""Angular velocity, rad/s."""
spin(b::Body) = _be_spin(_phys(b), b)
"""Whether the engine has put the body to sleep (it stopped moving)."""
sleeping(b::Body) = _be_sleeping(_phys(b), b)
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

function _free_body!(w::World, b::Body)
    b.h === nothing && return
    _be_free_body!(w.phys, w, b)
    b.h = nothing
end

"""
    remove!(w, b)

Take a body out of the world and free it, with every joint attached to it.
"""
function remove!(w::World, b::Body)
    _check(w)
    i = findfirst(x -> x === b, w.bodies)
    i === nothing && error("ObjectSim: $(b.name) is not in this world")
    w.pick !== nothing && w.pick.body === b && release!(w)
    for j in filter(j -> j.a === b || j.b === b, w.joints)
        _free_joint!(w, j)
        filter!(x -> x !== j, w.joints)
    end
    deleteat!(w.bodies, i)
    _free_body!(w, b)
    return nothing
end

"""
    destroy!(w)

Remove and free every joint, body and the engine's world. Safe to call twice.
"""
function destroy!(w::World)
    w.alive || return nothing
    release!(w)
    foreach(j -> _free_joint!(w, j), reverse(w.joints))   # constraints before their bodies
    empty!(w.joints)
    foreach(b -> _free_body!(w, b), reverse(w.bodies))
    empty!(w.bodies)
    w.alive = false
    w.phys isa _NoPhysics || _be_destroy!(w.phys, w)
    return nothing
end

"""
    with_world(f, scene_or_path; backend = nothing)

Build a world, run `f(world)`, and destroy it afterwards even on error.
"""
function with_world(f, scene; backend = nothing)
    w = World(scene; backend)
    try
        return f(w)
    finally
        destroy!(w)
    end
end
