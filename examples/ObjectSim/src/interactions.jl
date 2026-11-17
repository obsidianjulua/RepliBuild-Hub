# Per-object rules and the world's own forces, shared by both backends:
#
# - collision layers   each layer name gets a group bit; `ignore` clears bits
#                      from the mask; a pair collides only if each one's group
#                      is in the other's mask. Backends turn (group, mask) into
#                      their own filters.
# - per-object gravity, triggers, contact reports: the backend's
# - force hooks        Julia functions run before every fixed step (_pre_step!)
# - mutual gravity     a force hook: Newtonian attraction between every pair

const FILTER_DEFAULT = Int32(1)
const FILTER_STATIC = Int32(2)
const FILTER_ALL = Int32(-1)
const _LAYER_BIT0 = 6                    # bits 0-5: bullet3's own filter groups

# ── layers ───────────────────────────────────────────────────────────────────

function _layer_bit!(w::World, name::AbstractString)
    get!(w.layers, String(name)) do
        k = length(w.layers)
        _LAYER_BIT0 + k <= 30 || error("ObjectSim: too many collision layers (at most $(31 - _LAYER_BIT0))")
        Int32(1) << (_LAYER_BIT0 + k)
    end
end

# The group and mask a body is added with: static bodies skip other static
# bodies, unless the spec has a layer or ignores some.
function _filter(w::World, s::ObjectSpec)
    static = s.mass == 0
    group = isempty(s.layer) ? (static ? FILTER_STATIC : FILTER_DEFAULT) : _layer_bit!(w, s.layer)
    mask = static ? FILTER_ALL ⊻ FILTER_STATIC : FILTER_ALL
    for l in s.ignore
        mask &= ~_layer_bit!(w, l)
    end
    return group, mask
end

# ── per-object gravity, triggers ────────────────────────────────────────────

"""
    set_body_gravity!(w, b, g)

Give one body its own gravity (m/s²), which the world's gravity no longer
overrides. `nothing` hands it back to the world's.
"""
function set_body_gravity!(w::World, b::Body, g)
    _be_set_body_gravity!(w.phys, w, b, g === nothing ? nothing : Float32.(Tuple(g)))
    return wake!(b)
end

"""The gravity acting on one body (its own, or the world's)."""
body_gravity(b::Body) = _be_body_gravity(_phys(b), b)

"""Whether the body is a trigger: things pass through it, contacts are still reported."""
istrigger(b::Body) = _be_istrigger(_phys(b), b)

# ── contacts ─────────────────────────────────────────────────────────────────

"""One contact point between two bodies, after the last step."""
struct Contact
    a::Body
    b::Body
    point::Vec3          # on a, world coordinates
    normal::Vec3         # from b towards a
    impulse::Float32     # N·s pushing them apart in the last step (0 for triggers;
                         # Jolt: estimated from the closing speed, see its backend)
    depth::Float32       # distance between the surfaces here: < 0 overlapping, ~0 resting
end

# Contact points further apart than this are dropped, closer ones are live
# contacts (bullet3's default contact breaking threshold).
const CONTACT_THRESHOLD = 0.02f0

Base.show(io::IO, c::Contact) = print(io, "Contact(", c.a.name, " ↔ ", c.b.name, ", impulse ",
    round(c.impulse; sigdigits = 3), ")")

"""
    contacts(w; within = CONTACT_THRESHOLD) -> Vector{Contact}

Every contact point after the last step whose surfaces are no further apart
than `within` metres.
"""
function contacts(w::World; within::Real = CONTACT_THRESHOLD)
    _check(w)
    return _be_contacts(w.phys, w, Float32(within))
end

"""Whether `a` and `b` are touching (within 1 cm) after the last step."""
touching(w::World, a::Body, b::Body; within::Real = 0.01) =
    any(c -> (c.a === a && c.b === b) || (c.a === b && c.b === a), contacts(w; within))

# ── force hooks ──────────────────────────────────────────────────────────────

# Before each fixed step, from whichever backend: springs, then the hooks. A
# backend may call this from inside the engine's step (bullet3's pre-tick
# callback), where an error cannot unwind through C, so it is kept and
# rethrown after the step.
function _pre_step!(w::World, dt::Float32)
    try
        _spring_forces!(w, w.phys, dt)          # w.phys passed in: compiled for this backend
        for f in w.forces
            f(w, dt)
        end
    catch e
        w.hook_error === nothing && (w.hook_error = CapturedException(e, catch_backtrace()))
    end
    return nothing
end

function _rethrow_hook_error!(w::World)
    e = w.hook_error
    e === nothing && return
    w.hook_error = nothing
    throw(e)
end

"""
    add_force!(w, f) -> f

Run `f(w, dt)` before every fixed physics step (`dt` in seconds) for as long as
the world lives: the place for forces the engine does not have (fields, drag,
thrust, mutual gravity). Push bodies with [`apply_impulse!`](@ref) by
`force · dt`; that is the same as a force held for the step.
"""
function add_force!(w::World, f)
    _check(w)
    push!(w.forces, f)
    return f
end

"""
    mutual_gravity(G) -> f

A force hook: every pair of bodies pulls on each other with G·m₁·m₂/r²
(between centres of mass). A body's gravitating mass is its `gravity_mass`, or
its mass; a static body with a `gravity_mass` attracts but does not move.
Summed pair by pair below `GRAVITY_TREE_FROM[]` sources, by a Barnes–Hut
octree (opening angle `GRAVITY_THETA[]`) from there on: see gravity_tree.jl.
"""
function mutual_gravity(G::Real)
    g = Float64(G)                       # a new name: rebinding G would box it in the closure
    x = Float64[]; y = Float64[]; z = Float64[]; gm = Float64[]; src = Body[]
    ax = Float64[]; ay = Float64[]; az = Float64[]
    tree = GravityTree()
    return function (w::World, dt)
        _mutual_gravity!(w, w.phys, g, dt, x, y, z, gm, src, ax, ay, az, tree)
    end
end

# Gather the sources (every body with a gravitating mass), sum their pulls
# (gravity_tree.jl), push the ones that move.
function _mutual_gravity!(w::World, P::Physics, G, dt, x, y, z, gm, src, ax, ay, az, tree::GravityTree)
    empty!(src); empty!(x); empty!(y); empty!(z); empty!(gm)
    for b in w.bodies
        m = b.spec.gravity_mass === nothing ? b.spec.mass : b.spec.gravity_mass
        m > 0 || continue
        p = _be_transform(P, b)[2]
        push!(src, b); push!(x, p[1]); push!(y, p[2]); push!(z, p[3]); push!(gm, m)
    end
    n = length(src)
    _gravity_accel!(tree, ax, ay, az, x, y, z, gm, G)
    for i in 1:n
        b = src[i]
        isstatic(b) && continue
        # Δv = a·dt as an impulse (m·a·dt), the way the engine applies any push.
        k = b.spec.mass * dt
        _be_impulse!(P, b, (Float32(ax[i] * k), Float32(ay[i] * k), Float32(az[i] * k)), nothing)
    end
    return nothing
end
