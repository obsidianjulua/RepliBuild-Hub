# Joints and mouse picking, shared by both backends.
#
# Every joint is described in world coordinates at the moment it is made (a
# pivot point and, for hinges and sliders, an axis); here that becomes each
# body's own frame, and the backend builds its engine's constraint from it.
#
#   point   ball-and-socket: shares one point, turns freely
#   hinge   turns about one axis; optional limits and motor
#   slider  moves along one axis, no turning; limits, motor
#   fixed   welded together (breakable glue with break_impulse)
#   spring  pulled back toward the starting offset (ObjectSim's own force,
#           below; the engine's constraint only locks the turning)

"""
    Joint

A constraint between body `a` and body `b` (or the world, when `b` is
`nothing`). `pivot_a` / `pivot_b` are the shared point in each body's own
frame (`pivot_b` is a world point when there is no `b`), kept for drawing.
`h` is the backend's handle (`nothing` once freed).
"""
mutable struct Joint
    name::String
    kind::Symbol
    h::Any
    a::Body
    b::Union{Nothing,Body}
    pivot_a::Vec3
    pivot_b::Vec3
    motor::Union{Nothing,NTuple{2,Float32}}   # the scene's [speed, strength], for set_motors!
    spring::Union{Nothing,NTuple{2,Float32}}  # a spring's (stiffness, damping) as asked for
    k_now::Float32                            # … and what it runs with (the same: no caps)
    c_now::Float32
    warned::UInt8                             # 1: "too stiff to ring at this hz" already logged
    break_impulse::Float32
end

Base.show(io::IO, j::Joint) = print(io, "Joint(\"", j.name, "\", ", j.kind, ", ", j.a.name, " ↔ ",
    j.b === nothing ? "world" : j.b.name, broken(j) ? ", broken" : "", ")")

# ── frames ───────────────────────────────────────────────────────────────────
_transpose(R) = ((R[1][1], R[2][1], R[3][1]), (R[1][2], R[2][2], R[3][2]), (R[1][3], R[2][3], R[3][3]))
function _matmul(A, Bm)
    Bt = _transpose(Bm)
    row(r) = (vdot(r, Bt[1]), vdot(r, Bt[2]), vdot(r, Bt[3]))
    return (row(A[1]), row(A[2]), row(A[3]))
end
"""World point → the body's own frame."""
function _to_local(b::Body, p)
    R, o = transform(b)
    return _rotate(_transpose(R), vsub(Float32.(Tuple(p)), o))
end
"""World direction → the body's own frame."""
_dir_to_local(b::Body, d) = _rotate(_transpose(transform(b)[1]), Float32.(Tuple(d)))
"""Body frame point → world (physics pose / drawn pose)."""
function _to_world(b::Body, p)
    R, o = transform(b)
    return vadd(o, _rotate(R, p))
end
function _render_to_world(b::Body, p)
    R, o = render_transform(b)
    return vadd(o, _rotate(R, p))
end

# A rotation whose X axis is `axis` (sliders move along their frame's X), as
# rows; its columns are the axis and two normals to it.
function _frame_rows(axis)
    x = vunit(axis)
    up = abs(x[2]) < 0.9f0 ? (0f0, 1f0, 0f0) : (1f0, 0f0, 0f0)
    z = vunit(vcross(x, up)); y = vcross(z, x)
    return ((x[1], y[1], z[1]), (x[2], y[2], z[2]), (x[3], y[3], z[3]))   # columns x, y, z
end

# ── creating joints ──────────────────────────────────────────────────────────

"""
    add_joint!(w, spec::JointSpec) -> Joint

Make one joint between two named bodies (or a body and the world) from its
world-space description.
"""
function add_joint!(w::World, s::JointSpec)
    _check(w)
    a = body(w, s.a)
    b = isempty(s.b) ? nothing : body(w, s.b)
    s.kind in (:fixed,) && b === nothing && error("ObjectSim: joint '$(s.name)': a fixed joint needs two bodies")
    pa = _to_local(a, s.pivot)
    pb = b === nothing ? s.pivot : _to_local(b, s.pivot)
    j = Joint(s.name, s.kind, nothing, a, b, pa, pb, s.motor,
              s.kind == :spring ? (s.stiffness, s.damping) : nothing, s.stiffness, s.damping, 0x00,
              s.break_impulse)
    j.h = _be_add_joint!(w.phys, w, s, j)
    # Motors keep pushing, so their bodies must not fall asleep mid-turn. Nor
    # may a spring's: an engine puts a body to sleep once it has moved slowly
    # for a while, which froze a damped spring partway through its last
    # bounces (a hanging 2 kg box stopped 5% below where Hooke's law puts it).
    if s.motor !== nothing || s.kind == :spring
        for x in (a, b)
            x === nothing || isstatic(x) || _be_keep_awake!(w.phys, x, true)
        end
    end
    push!(w.joints, j)
    wake!(a); b === nothing || wake!(b)
    return j
end

function _free_joint!(w::World, j::Joint)
    j.h === nothing && return
    _be_free_joint!(w.phys, w, j)
    j.h = nothing
end

"""
    remove_joint!(w, j)

Take a joint out of the world and free it; the bodies stay.
"""
function remove_joint!(w::World, j::Joint)
    _check(w)
    _free_joint!(w, j)
    filter!(x -> x !== j, w.joints)
    return nothing
end

joint(w::World, name::AbstractString) = (i = findfirst(j -> j.name == name, w.joints);
    i === nothing ? error("ObjectSim: no joint named '$name'") : w.joints[i])

"""Whether the joint has snapped (its break impulse was exceeded)."""
broken(j::Joint) = j.h === nothing || _be_broken(j.h.phys, j)

"""
    joint_points(j) -> (pa, pb)

Where the joint's pivot is on each side, in world coordinates, at the drawn
(interpolated) pose. They coincide while the joint holds; a spring's spread
apart as it stretches.
"""
joint_points(j::Joint) = (_render_to_world(j.a, j.pivot_a),
                          j.b === nothing ? j.pivot_b : _render_to_world(j.b, j.pivot_b))

# ── picking: hold a body with the mouse ─────────────────────────────────────

"""What is being held: the body, the backend's handle, the grab distance."""
mutable struct Pick
    body::Body
    h::Any
    distance::Float32
    point::Vec3          # where the held point is being pulled to (world)
    local_point::Vec3    # the held point in the body's own frame
    awake::Bool          # whether the body was kept awake before it was picked up
end

"""
    grab!(w, from, dir; reach = 200) -> Pick or nothing

Cast a ray from `from` along `dir`; if it hits a moving body, hold it at the
hit point (a point constraint to the mouse, the classic Bullet demo picker).
The body is kept awake while held.
"""
function grab!(w::World, from, dir; reach::Real = 200)
    release!(w)
    d = vunit(Float32.(Tuple(dir))); f = Float32.(Tuple(from))
    hit = raycast(w, f, vadd(f, vscale(d, Float32(reach))))
    (hit === nothing || isstatic(hit.body)) && return nothing
    b = hit.body
    lp = _to_local(b, hit.point)
    awake = !b.spec.sleep || w.mutual_G != 0 ||
            any(j -> (j.a === b || j.b === b) && (j.motor !== nothing || j.spring !== nothing), w.joints)
    h = _be_grab!(w.phys, w, b, lp, hit.point)
    _be_keep_awake!(w.phys, b, true)
    w.pick = Pick(b, h, vnorm(vsub(hit.point, f)), hit.point, lp, awake)
    return w.pick
end

"""
    drag!(w, from, dir; distance = nothing)

Move the held point to `from + dir · distance` (the grab distance unless given).
"""
function drag!(w::World, from, dir; distance = nothing)
    p = w.pick
    p === nothing && return nothing
    distance === nothing || (p.distance = max(0.5f0, Float32(distance)))
    p.point = vadd(Float32.(Tuple(from)), vscale(vunit(Float32.(Tuple(dir))), p.distance))
    _be_drag!(w.phys, w, p, p.point)
    return p
end

"""Let go of whatever is held."""
function release!(w::World)
    p = w.pick
    p === nothing && return nothing
    _be_release!(w.phys, w, p)
    if isalive(p.body)          # back to how it was: never-sleep stays never-sleep
        _be_keep_awake!(w.phys, p.body, p.awake)
        wake!(p.body)
    end
    w.pick = nothing
    return nothing
end

"""
    set_motors!(w, factor)

Run every motor at `factor` × the speed its scene gave it: 0 stops them
(holding still, with the same strength), negative runs them backwards.
Returns how many motors there are.
"""
function set_motors!(w::World, factor::Real)
    n = 0
    for j in w.joints
        (j.motor === nothing || broken(j)) && continue
        n += 1
        _be_set_motor!(w.phys, j, Float32(factor))
        wake!(j.a); j.b === nothing || wake!(j.b)
    end
    return n
end

"""How many joints have a motor."""
motor_count(w::World) = count(j -> j.motor !== nothing, w.joints)

# ── springs ──────────────────────────────────────────────────────────────────
#
# A spring joint pulls its two pivot points together with F = −k·d − (damper),
# d being how far apart they have moved since the joint was made, worked out
# here before every fixed step and applied as impulses through the bodies'
# centres of mass. The engine's constraint underneath only keeps the bodies'
# orientations together.
#
# Why not bullet3's own spring (btGeneric6DofSpring2Constraint's enableSpring)?
# Measured, it gets coupled systems wrong: it asks the solver for the velocity
# the spring force would give, and other springs' pushes on the same body
# count toward that, so a spring between two moving masses acted at half its
# stiffness (two masses on three springs: the opposed mode ran at ω² = 200,
# not 300, at any number of solver passes). Its BT_6DOF_FLAGS_USE_INFINITE_ERROR
# fixes that but then a damped spring applies the larger of its spring and
# damper forces instead of their sum, so a ζ = 0.5 spring stopped bouncing.
#
# Here, two ways, picked per spring:
# - explicit (soft springs, the usual case): the spring force is exact (k·d),
#   symplectic Euler like the engines' own integration, so periods and
#   energy come out right; the damper takes off 1 − e^(−c·dt/m) of the
#   relative velocity per step (m: the mass it moves, or the reduced mass
#   m₁m₂/(m₁+m₂) between two bodies), the exact decay of a damper on its own.
# - implicit (stiff or heavily damped ones): a step that explicit integration
#   can't take stably. Every such spring's push is solved for together with
#   the velocity change it causes, one linear system over the bodies they
#   touch (below, `_SpringSystem`), so any stiffness and any damping is
#   stable. What a too-stiff spring loses is its ringing faster than the
#   step can show (it is damped out within a few steps, with a warning);
#   where it settles is exact.
# A spring is stiff when its ω·dt, bounded from above for the whole network
# (Gershgorin: twice the largest Σk/m of its bodies), passes 1/√2, well inside
# symplectic Euler's limit of 2; heavily damped when c·dt/m > 0.3.

# The mass a spring moves.
function _spring_mass(a::Body, b)
    (b === nothing || isstatic(b)) && return Float64(mass(a))
    isstatic(a) && return Float64(mass(b))
    ma, mb = Float64(mass(a)), Float64(mass(b))
    return ma * mb / (ma + mb)
end

"""
    spring_stiffness(j), spring_damping(j)

What a spring joint is running with (the scene's values: stiff and heavily
damped springs run implicitly instead of being softened).
"""
spring_stiffness(j::Joint) = j.k_now
spring_damping(j::Joint) = j.c_now

"""
    set_spring!(w, j; stiffness, damping)

Change a spring joint's stiffness (N/m) and/or damping (N·s/m) while it runs.
Its rest length stays the same.
"""
function set_spring!(w::World, j::Joint; stiffness::Real = j.spring[1], damping::Real = j.spring[2])
    j.spring === nothing && error("ObjectSim: joint '$(j.name)' is not a spring")
    (stiffness >= 0 && damping >= 0) || error("ObjectSim: stiffness and damping must be ≥ 0")
    j.spring = (Float32(stiffness), Float32(damping))
    j.k_now, j.c_now = j.spring
    j.warned = 0x00
    w.spring_key = UInt(0)                       # worked out again next step
    wake!(j.a); j.b === nothing || wake!(j.b)
    return j
end

"""Whether a spring joint is solved implicitly (stiff or heavily damped for the step rate)."""
spring_implicit(w::World, j::Joint) = w.springs isa _SpringSystem && any(x -> x === j, w.springs.implicit)

# The implicit springs' system. Each implicit spring s between bodies a and b
# (b may be static or the world) adds, over a step h, the impulse
#     J = −h·k·(d + θ·h·(vr + Δvr)) − h·c·(vr + Δvr)
# to a (and −J to b): its stretch d and relative velocity vr at the pivots,
# Δvr the change the step brings, gravity's included (the engine adds h·g
# after this; left out, a spring would balance it short, by w·g/k). Gathering
# Δv over the moving bodies:
#     (M + Σₛ wₛ·Lₛ) Δv = b,   wₛ = θ·h²·k + h·c,
#     bₐ = mₐ·h·gₐ + explicit pushes + Σₛ ±(−h·k·d − wₛ·vr),
# and each body is pushed by mₐ·Δvₐ − mₐ·h·gₐ, gravity being the engine's.
# Lₛ the spring's graph Laplacian (a world anchor only adds to its body's
# diagonal). A spring here is isotropic and zero-length (F = −k·d), so the
# matrix is the same for x, y and z and doesn't depend on the state: it is
# factorised once (Cholesky: LAPACK while small, CHOLMOD's sparse one above
# 48 bodies) and each step costs one solve with three right-hand sides.
# θ = (a−1)/a for a stiff spring (a: its Gershgorin bound on (ω·dt)²) makes
# the step stable at any a; θ = 0 for a soft but heavily damped one.
struct _SpringSystem
    explicit::Vector{Joint}
    implicit::Vector{Joint}
    weight::Vector{Float64}          # wₛ per implicit spring
    nodes::Vector{Body}              # the moving bodies they touch
    index::IdDict{Body,Int}
    mass::Vector{Float64}
    F::Any                           # the Cholesky factor of M + Σ wₛ·Lₛ
    B::Matrix{Float64}               # n × 3: right-hand sides, then Δv
end

function _spring_system(w::World, dt::Float32)
    h = Float64(dt)
    springs = Joint[j for j in w.joints if j.spring !== nothing && !broken(j)]
    moving(x) = x !== nothing && !isstatic(x)
    K = IdDict{Body,Float64}()                      # Σk on each moving body
    for j in springs, x in (j.a, j.b)
        moving(x) && (K[x] = get(K, x, 0.0) + j.spring[1])
    end
    explicit = Joint[]; implicit = Joint[]; weight = Float64[]
    hz = round(Int, 1 / dt)
    for j in springs
        k, c = Float64.(j.spring)
        j.k_now, j.c_now = j.spring
        a = 0.0
        for x in (j.a, j.b)
            moving(x) && (a = max(a, 2 * h^2 * K[x] / mass(x)))
        end
        m = _spring_mass(j.a, j.b)
        θ = a <= 1 ? 0.0 : (a - 1) / a
        if θ == 0 && c * h / m <= 0.3
            push!(explicit, j)
            continue
        end
        push!(implicit, j); push!(weight, θ * h^2 * k + h * c)
        if θ > 0 && 4 * h * sqrt(k / m) > 1 && j.warned & 0x01 == 0
            j.warned |= 0x01
            f = round(sqrt(k / m) / 2π; sigdigits = 3)
            @warn "ObjectSim: spring '$(j.name)': $k N/m on $(round(m; sigdigits = 3)) kg rings at $f Hz, " *
                  "faster than $hz Hz steps can show, so it is solved implicitly: stable, and it settles " *
                  "where it should, but that ringing dies out within a few steps. To see it ring use " *
                  "[world] hz = $(ceil(Int, 4 * sqrt(k / m))) or more."
        end
    end
    isempty(implicit) && return _SpringSystem(explicit, implicit, weight, Body[], IdDict{Body,Int}(),
                                              Float64[], nothing, zeros(0, 3))
    nodes = Body[]; index = IdDict{Body,Int}()
    for j in implicit, x in (j.a, j.b)
        moving(x) && !haskey(index, x) && (push!(nodes, x); index[x] = length(nodes))
    end
    n = length(nodes)
    masses = Float64[mass(x) for x in nodes]
    I_ = collect(1:n); J_ = collect(1:n); V = copy(masses)
    for (s, j) in enumerate(implicit)
        ia = moving(j.a) ? index[j.a] : 0
        ib = moving(j.b) ? index[j.b] : 0
        ws = weight[s]
        ia > 0 && (push!(I_, ia); push!(J_, ia); push!(V, ws))
        ib > 0 && (push!(I_, ib); push!(J_, ib); push!(V, ws))
        if ia > 0 && ib > 0
            push!(I_, ia); push!(J_, ib); push!(V, -ws)
            push!(I_, ib); push!(J_, ia); push!(V, -ws)
        end
    end
    A = sparse(I_, J_, V, n, n)
    F = n <= 48 ? cholesky(Symmetric(Matrix(A))) : cholesky(Symmetric(A))
    return _SpringSystem(explicit, implicit, weight, nodes, index, masses, F, zeros(n, 3))
end

function _spring_key(w::World, P::Physics, dt::Float32)
    h = hash(dt)
    for j in w.joints
        j = j::Joint                             # w.joints is a Vector{Any}
        (j.spring === nothing || j.h === nothing || _be_broken(P, j)) && continue
        k, c = j.spring::NTuple{2,Float32}
        h = hash(objectid(j), hash(k, hash(c, hash(mass(j.a), hash(j.b === nothing ? 0f0 : mass(j.b), h)))))
    end
    return h
end

# Before each fixed step (called from the pre-tick callback). Every spring's
# push is worked out from the same state before any is applied: applying one
# changes its body's velocity, which the next spring's damper would see (that
# made a damped chain settle off its equilibrium, by more the more damping).
#
# The push goes through the centre of mass, not the pivot. A spring joint
# locks the bodies' turning anyway, and a push at the pivot (0.15 m out on a
# small bead) made a torque that the iterative lock along a chain could not
# soak up fully; fed back step after step, a ten-bead chain blew up.
const _SPRING_PUSH = Tuple{Body,Vec3}[]

function _spring_forces!(w::World, P::Physics, dt::Float32)
    any(j -> (j::Joint).spring !== nothing, w.joints) || return
    key = _spring_key(w, P, dt)
    if key != w.spring_key || !(w.springs isa _SpringSystem)
        w.springs = _spring_system(w, dt); w.spring_key = key
    end
    S = w.springs::_SpringSystem
    h = Float64(dt)
    static(x) = x === nothing || isstatic(x)
    pivot(x, p) = x === nothing ? p : (t = _be_transform(P, x); vadd(t[2], _rotate(t[1], p)))
    function vel(x, p)
        static(x) && return (0.0, 0.0, 0.0)
        o = _be_transform(P, x)[2]
        return Float64.(vadd(_be_velocity(P, x), vcross(_be_spin(P, x), vsub(p, o))))
    end
    pushes = empty!(_SPRING_PUSH)
    B = S.B; fill!(B, 0.0)
    function push_on!(x, J)
        i = get(S.index, x, 0)
        if i == 0
            push!(pushes, (x, Float32.(J)))
        else
            B[i, 1] += J[1]; B[i, 2] += J[2]; B[i, 3] += J[3]
        end
    end
    for j in S.explicit
        a, b = j.a, j.b
        static(a) && static(b) && continue
        pa, pb = pivot(a, j.pivot_a), pivot(b, j.pivot_b)
        d = Float64.(vsub(pa, pb)); vr = vsub(vel(a, pa), vel(b, pb))
        m = _spring_mass(a, b)
        J = vscale(d, -Float64(j.k_now) * h)                              # Hooke, over the step
        j.c_now > 0 && (J = vsub(J, vscale(vr, m * -expm1(-Float64(j.c_now) * h / m))))
        static(a) || push_on!(a, J)
        static(b) || push_on!(b, vscale(J, -1))
    end
    if !isempty(S.implicit)
        for (s, j) in enumerate(S.implicit)
            a, b = j.a, j.b
            pa, pb = pivot(a, j.pivot_a), pivot(b, j.pivot_b)
            d = Float64.(vsub(pa, pb)); vr = vsub(vel(a, pa), vel(b, pb))
            g = vsub(vscale(d, -h * Float64(j.k_now)), vscale(vr, S.weight[s]))
            static(a) || push_on!(a, g)
            static(b) || push_on!(b, vscale(g, -1))
        end
        for (i, x) in enumerate(S.nodes)                                  # gravity, the engine's
            gx = _be_body_gravity(P, x); mh = S.mass[i] * h
            B[i, 1] += mh * gx[1]; B[i, 2] += mh * gx[2]; B[i, 3] += mh * gx[3]
        end
        ldiv!(S.F, B)                                                      # B ← Δv
        for (i, x) in enumerate(S.nodes)
            m = S.mass[i]; gx = _be_body_gravity(P, x)
            push!(pushes, (x, Float32.((m * (B[i, 1] - h * gx[1]), m * (B[i, 2] - h * gx[2]),
                                        m * (B[i, 3] - h * gx[3])))))
        end
    end
    for (x, J) in pushes
        _be_impulse!(P, x, J, nothing)
    end
end
