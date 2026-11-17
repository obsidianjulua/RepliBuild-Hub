# Pushing bodies around and looking into the world: velocities, impulses,
# gravity, raycasts, live material and mass changes. The engine work is the
# backend's (`_be_*`, see physics.jl); each setter here also keeps the body's
# ObjectSpec in step, so what the viewer shows, a restart's copy and the menu
# all agree.

"""Mass in kg (0 for static bodies)."""
mass(b::Body) = b.spec.mass

"""Wake a sleeping body so the next step moves it."""
wake!(b::Body) = (_be_wake!(_phys(b), b); b)

"""
    set_velocity!(b, v; spin = nothing)

Set the linear velocity (m/s) and, optionally, the angular velocity (rad/s),
and wake the body. Static bodies are left alone.
"""
function set_velocity!(b::Body, v; spin = nothing)
    isstatic(b) && return b
    _be_set_velocity!(_phys(b), b, Float32.(Tuple(v)), spin === nothing ? nothing : Float32.(Tuple(spin)))
    return wake!(b)
end

"""
    apply_impulse!(b, impulse; at = nothing)

An instant push, in N·s: the velocity changes by `impulse / mass`. With `at`
(a world point), the push also spins the body about its centre of mass.
"""
function apply_impulse!(b::Body, impulse; at = nothing)
    isstatic(b) && return b
    _be_impulse!(_phys(b), b, Float32.(Tuple(impulse)), at === nothing ? nothing : Float32.(Tuple(at)))
    return wake!(b)
end

"""An instant twist, in N·m·s, about the centre of mass."""
function apply_angular_impulse!(b::Body, T)
    isstatic(b) && return b
    _be_angular_impulse!(_phys(b), b, Float32.(Tuple(T)))
    return wake!(b)
end

"""
    set_gravity!(w, g)

Change gravity for the whole world (every body, including ones added later)
and wake everything so the change shows at once. Bodies with their own
gravity keep it.
"""
function set_gravity!(w::World, g)
    _check(w)
    w.gravity = Float32.(Tuple(g))
    _be_set_gravity!(w.phys, w.gravity)
    foreach(b -> isstatic(b) || wake!(b), w.bodies)
    return w
end

"""
    explode!(w, center; radius = 4, speed = 12) -> Int

Blast every moving body within `radius` m of `center` outward (and a little
upward). A body at the centre gains `speed` m/s, falling off linearly to zero
at the edge, whatever its mass. Returns how many bodies were hit.
"""
function explode!(w::World, center; radius::Real = 4, speed::Real = 12)
    _check(w)
    c = Float32.(Tuple(center)); n = 0
    for b in w.bodies
        isstatic(b) && continue
        d = vsub(position(b), c)
        dist = vnorm(d)
        dist >= radius && continue
        dir = vunit(vadd(vunit(d), (0f0, 0.6f0, 0f0)))
        apply_impulse!(b, vscale(dir, Float32(mass(b) * speed * (1 - dist / radius))))
        n += 1
    end
    return n
end

"""
    raycast(w, from, to) -> NamedTuple or nothing

The first thing the segment `from → to` hits: `(body, point, normal, fraction)`,
`fraction` being how far along the segment (0–1). `nothing` if it hits nothing.
"""
function raycast(w::World, from, to)
    _check(w)
    return _be_raycast(w.phys, w, Float32.(Tuple(from)), Float32.(Tuple(to)))
end

"""
    spawn!(w, spec) -> Body

[`add!`](@ref) for objects created while the world runs: the name gets a
running number so every spawned body has its own.
"""
function spawn!(w::World, s::ObjectSpec)
    w.spawned += 1
    return add!(w, _with(s; name = "$(s.name)#$(w.spawned)"))
end

# ── changing a body's material and mass while it runs ────────────────────────

"""
    set_mass!(b, m)

Change a moving body's mass (kg), with its inertia scaled for its shape.
Static bodies stay static.
"""
function set_mass!(b::Body, m::Real)
    isstatic(b) && return b
    m = Float32(max(m, 1f-4))
    _be_set_mass!(_phys(b), b, m)
    b.spec = _with(b.spec; mass = m)
    return wake!(b)
end

"""Surface friction (0 = ice, ~1 = rubber)."""
function set_friction!(b::Body, f::Real)
    _be_set_friction!(_phys(b), b, Float32(f))
    b.spec = _with(b.spec; friction = Float32(f)); return wake!(b)
end

"""Bounciness, 0 (dead) to 1 (keeps all its speed)."""
function set_restitution!(b::Body, e::Real)
    _be_set_restitution!(_phys(b), b, Float32(e))
    b.spec = _with(b.spec; restitution = Float32(e)); return wake!(b)
end

"""How much rolling is resisted (balls and drums stop instead of rolling forever)."""
function set_rolling_friction!(b::Body, f::Real)
    _be_set_rolling_friction!(_phys(b), b, Float32(f))
    b.spec = _with(b.spec; rolling_friction = Float32(f)); return wake!(b)
end

"""Air drag on moving (linear) and turning (angular), 0-1 per second."""
function set_damping!(b::Body, lin::Real, ang::Real)
    isstatic(b) && return b
    _be_set_damping!(_phys(b), b, Float32(lin), Float32(ang))
    b.spec = _with(b.spec; damping = (Float32(lin), Float32(ang))); return wake!(b)
end

"""Change how a body looks and shines; nothing physical."""
set_look!(b::Body; kw...) = (b.spec = _with(b.spec; kw...); b)

"""Solver passes per step (more: stiffer stacks and joints, slower)."""
function set_solver_iterations!(w::World, n::Integer)
    _check(w)
    _be_set_iterations!(w.phys, Int(n))
    return w
end
solver_iterations(w::World) = _be_iterations(w.phys)

"""
    set_mutual_gravity!(w, G)

Turn every-object-attracts-every-other gravity on (G > 0), change its
strength, or turn it off (0). While it is on, bodies are kept awake.
"""
function set_mutual_gravity!(w::World, G::Real)
    _check(w)
    w.mutual === nothing || filter!(f -> f !== w.mutual, w.forces)
    w.mutual = nothing; w.mutual_G = Float64(G)
    if G > 0
        w.mutual = add_force!(w, mutual_gravity(G))
        foreach(b -> isstatic(b) || _be_keep_awake!(w.phys, b, true), w.bodies)
    else
        foreach(b -> isstatic(b) || !b.spec.sleep || _be_keep_awake!(w.phys, b, false), w.bodies)
    end
    return w
end
