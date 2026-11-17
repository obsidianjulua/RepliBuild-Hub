# Orbital mechanics: N bodies under Newtonian gravity, integrated in Float64
# with OrdinaryDiffEq (the ODE solvers of DifferentialEquations.jl). No bullet3
# here: at solar-system scale its single-precision floats and fixed steps are
# the wrong tool, and nothing here needs contact physics. The raylib window for
# it is in orbit_viewer.jl; bullet3 handles collisions and debris at human /
# rubble-pile scale (fields.jl).
#
# Units, `units = "solar"` (default): AU, days, solar masses, so G is the
# Gaussian gravitational constant squared, k² = 0.01720209895².
# `units = "nbody"`: G = 1, for dimensionless problems (the figure-eight).
#
#   [system]
#   units = "solar"
#   softening = 0.0            # AU; smooths close passes (0 = exact Newton)
#   barycentric = true         # move to the centre-of-mass frame at the start
#   merge = true               # bodies that touch merge (else the run stops)
#   [view]
#   days_per_second = 30       # starting speed in the window
#   exaggerate = 800           # drawn radius = real radius × this …
#   scale = 10                 # … and 1 AU = this many drawing units
#   distance = 4               # starting camera distance (AU); default fits everything
#
#   [[body]]
#   name = "Earth"
#   mass = 3.003e-6            # solar masses (nbody: any)
#   radius = 4.26e-5           # AU: for collisions and drawing
#   display_radius = 0.05      # AU, optional: draw at this size instead
#   color = "#3d8bd9"
#   position = [1, 0, 0]       # either a state …
#   velocity = [0, 0.0172, 0]
#   orbit = { around = "Sun", a = 1.0, e = 0.0167, i = 0, node = 0, peri = 102.9, M = 0 }
#                              # … or elements around an earlier body (degrees)

using OrdinaryDiffEq: SecondOrderODEProblem, init, solve, terminate!,
                      DiscreteCallback, reinit!
using OrdinaryDiffEqRKN: DPRKN12          # the RKN solvers live in their own sub-package in OrdinaryDiffEq 7
import OrdinaryDiffEq

const GAUSS_K = 0.01720209895
const G_SOLAR = GAUSS_K^2                 # AU³ / (M☉ · day²)

const Vec3d = NTuple{3,Float64}

struct OrbitBody
    name::String
    mass::Float64
    radius::Float64
    display_radius::Union{Nothing,Float64}
    color::NTuple{3,UInt8}
end

struct OrbitSystem
    name::String
    G::Float64
    units::Symbol
    softening::Float64
    merge::Bool
    bodies::Vector{OrbitBody}
    x0::Vector{Float64}                   # 3N positions
    v0::Vector{Float64}                   # 3N velocities
    days_per_second::Float64
    exaggerate::Float64
    scale::Float64
    view_distance::Union{Nothing,Float64}
end

Base.show(io::IO, s::OrbitSystem) = print(io, "OrbitSystem(\"", s.name, "\", ", length(s.bodies),
    " bodies, ", s.units, " units)")

# ── orbital elements → state ─────────────────────────────────────────────────

"""
    kepler_E(M, e) -> E

Solve Kepler's equation M = E − e·sin E for the eccentric anomaly (radians),
by Newton's method. Elliptic orbits (e < 1) only.
"""
function kepler_E(M::Real, e::Real)
    0 <= e < 1 || error("ObjectSim: only elliptic orbits (0 ≤ e < 1), got e = $e")
    M = mod2pi(M)
    E = e < 0.8 ? M : π
    for _ in 1:50
        dE = (E - e * sin(E) - M) / (1 - e * cos(E))
        E -= dE
        abs(dE) < 1e-15 && break
    end
    return E
end

"""
    elements_to_state(μ; a, e, i, node, peri, M) -> (r, v)

Position and velocity relative to the central body for an elliptic orbit.
`μ = G·(M_central + m)`; angles in degrees; `M` is the mean anomaly.
"""
function elements_to_state(μ::Real; a::Real, e::Real = 0, i::Real = 0, node::Real = 0,
                           peri::Real = 0, M::Real = 0)
    a > 0 || error("ObjectSim: semi-major axis must be > 0")
    E = kepler_E(deg2rad(M), e)
    # in the orbital plane, periapsis along +x
    xp = a * (cos(E) - e); yp = a * sqrt(1 - e^2) * sin(E)
    n = sqrt(μ / a^3)
    rdot = n * a / (1 - e * cos(E))
    vxp = -rdot * sin(E); vyp = rdot * sqrt(1 - e^2) * cos(E)
    Ω, ω, inc = deg2rad(node), deg2rad(peri), deg2rad(i)
    cΩ, sΩ, cω, sω, ci, si = cos(Ω), sin(Ω), cos(ω), sin(ω), cos(inc), sin(inc)
    # perifocal → reference frame (z up = ecliptic north)
    P = (cΩ * cω - sΩ * sω * ci, sΩ * cω + cΩ * sω * ci, sω * si)
    Q = (-cΩ * sω - sΩ * cω * ci, -sΩ * sω + cΩ * cω * ci, cω * si)
    r = ntuple(k -> xp * P[k] + yp * Q[k], 3)
    v = ntuple(k -> vxp * P[k] + vyp * Q[k], 3)
    return r, v
end

"""
    state_to_elements(μ, r, v) -> (a, e)

Semi-major axis (vis-viva) and eccentricity (from the eccentricity vector).
"""
function state_to_elements(μ::Real, r, v)
    rn = sqrt(sum(abs2, r)); v2 = sum(abs2, v)
    a = 1 / (2 / rn - v2 / μ)
    h = (r[2] * v[3] - r[3] * v[2], r[3] * v[1] - r[1] * v[3], r[1] * v[2] - r[2] * v[1])
    vxh = (v[2] * h[3] - v[3] * h[2], v[3] * h[1] - v[1] * h[3], v[1] * h[2] - v[2] * h[1])
    evec = ntuple(k -> vxh[k] / μ - r[k] / rn, 3)
    return a, sqrt(sum(abs2, evec))
end

"""Orbital period of a two-body orbit, T = 2π √(a³/μ)."""
kepler_period(μ::Real, a::Real) = 2π * sqrt(a^3 / μ)

# ── scene files ──────────────────────────────────────────────────────────────

"""
    load_orbits(path) -> OrbitSystem

Read an orbit scene (see the top of src/orbits.jl for every key).
"""
function load_orbits(path::AbstractString)
    isfile(path) || error("ObjectSim: orbit scene not found: $path")
    parse_orbits(TOML.parsefile(path); name = splitext(basename(path))[1])
end

function parse_orbits(d::AbstractDict; name::AbstractString = "orbits")
    _known(d, ("system", "view", "body"), "top level")
    s = get(d, "system", Dict{String,Any}())
    _known(s, ("units", "G", "softening", "barycentric", "merge"), "[system]")
    units = Symbol(get(s, "units", "solar"))
    units in (:solar, :nbody) || error("ObjectSim: [system] units must be \"solar\" or \"nbody\"")
    G = Float64(get(s, "G", units == :solar ? G_SOLAR : 1.0))
    v = get(d, "view", Dict{String,Any}())
    _known(v, ("days_per_second", "exaggerate", "scale", "distance"), "[view]")

    bodies = OrbitBody[]; xs = Vec3d[]; vs = Vec3d[]
    index = Dict{String,Int}()
    for (i, b) in enumerate(get(d, "body", Any[]))
        b isa AbstractDict || error("ObjectSim: [[body]] #$i is not a table")
        nm = String(get(b, "name", "body$i"))
        what = "body '$nm'"
        _known(b, ("name", "mass", "radius", "display_radius", "color", "position", "velocity", "orbit"), what)
        haskey(index, nm) && error("ObjectSim: two bodies are named '$nm'")
        m = Float64(get(b, "mass", 0.0)); m >= 0 || error("ObjectSim: $what mass must be ≥ 0")
        rad = Float64(get(b, "radius", 0.0))
        if haskey(b, "orbit")
            (haskey(b, "position") || haskey(b, "velocity")) &&
                error("ObjectSim: $what: give an orbit or a position/velocity, not both")
            o = b["orbit"]
            _known(o, ("around", "a", "e", "i", "node", "peri", "M"), "$what orbit")
            parent = String(get(o, "around", ""))
            haskey(index, parent) || error("ObjectSim: $what orbits '$parent', which must be listed before it")
            k = index[parent]
            μ = G * (bodies[k].mass + m)
            r, vel = elements_to_state(μ; a = Float64(o["a"]), e = Float64(get(o, "e", 0)),
                i = Float64(get(o, "i", 0)), node = Float64(get(o, "node", 0)),
                peri = Float64(get(o, "peri", 0)), M = Float64(get(o, "M", 0)))
            push!(xs, xs[k] .+ r); push!(vs, vs[k] .+ vel)
        else
            push!(xs, Float64.(Tuple(_vec3(get(b, "position", [0, 0, 0]), "$what position"))))
            push!(vs, Float64.(Tuple(_vec3(get(b, "velocity", [0, 0, 0]), "$what velocity"))))
        end
        dr = haskey(b, "display_radius") ? Float64(b["display_radius"]) : nothing
        push!(bodies, OrbitBody(nm, m, rad, dr, _color(get(b, "color", nothing), i, what)))
        index[nm] = length(bodies)
    end
    isempty(bodies) && error("ObjectSim: an orbit scene needs at least one [[body]]")
    if Bool(get(s, "barycentric", true))
        M = sum(b.mass for b in bodies)
        if M > 0
            com = ntuple(k -> sum(bodies[i].mass * xs[i][k] for i in eachindex(bodies)) / M, 3)
            vcm = ntuple(k -> sum(bodies[i].mass * vs[i][k] for i in eachindex(bodies)) / M, 3)
            xs = [x .- com for x in xs]; vs = [w .- vcm for w in vs]
        end
    end
    return OrbitSystem(String(name), G, units, Float64(get(s, "softening", 0.0)),
        Bool(get(s, "merge", true)), bodies,
        collect(Iterators.flatten(xs)), collect(Iterators.flatten(vs)),
        Float64(get(v, "days_per_second", 30.0)), Float64(get(v, "exaggerate", 800.0)),
        Float64(get(v, "scale", 10.0)), haskey(v, "distance") ? Float64(v["distance"]) : nothing)
end

# ── the equations of motion ──────────────────────────────────────────────────

# a_i = Σ_j G m_j (x_j − x_i) / (|x_j − x_i|² + ε²)^{3/2}
function _accel!(a, v, x, p, t)
    G, m, eps2 = p.G, p.m, p.eps2
    N = length(m)
    fill!(a, 0.0)
    @inbounds for i in 1:N - 1
        xi, yi, zi = x[3i - 2], x[3i - 1], x[3i]
        for j in i + 1:N
            dx = x[3j - 2] - xi; dy = x[3j - 1] - yi; dz = x[3j] - zi
            r2 = dx * dx + dy * dy + dz * dz + eps2
            inv3 = G / (r2 * sqrt(r2))
            fi = m[j] * inv3; fj = m[i] * inv3
            a[3i - 2] += fi * dx; a[3i - 1] += fi * dy; a[3i] += fi * dz
            a[3j - 2] -= fj * dx; a[3j - 1] -= fj * dy; a[3j] -= fj * dz
        end
    end
    return nothing
end

"""
    energy(sys_or_sim, x, v; masses) -> Float64

Total energy, kinetic + potential (softened like the forces).
"""
function nbody_energy(G, m, x, v, eps2 = 0.0)
    N = length(m); E = 0.0
    @inbounds for i in 1:N
        E += 0.5 * m[i] * (v[3i - 2]^2 + v[3i - 1]^2 + v[3i]^2)
        for j in i + 1:N
            r = sqrt((x[3j - 2] - x[3i - 2])^2 + (x[3j - 1] - x[3i - 1])^2 + (x[3j] - x[3i])^2 + eps2)
            E -= G * m[i] * m[j] / r
        end
    end
    return E
end

"""Total angular momentum vector Σ mᵢ (xᵢ × vᵢ)."""
function nbody_angular_momentum(m, x, v)
    L = [0.0, 0.0, 0.0]
    @inbounds for i in eachindex(m)
        xi = (x[3i - 2], x[3i - 1], x[3i]); vi = (v[3i - 2], v[3i - 1], v[3i])
        L[1] += m[i] * (xi[2] * vi[3] - xi[3] * vi[2])
        L[2] += m[i] * (xi[3] * vi[1] - xi[1] * vi[3])
        L[3] += m[i] * (xi[1] * vi[2] - xi[2] * vi[1])
    end
    return Tuple(L)
end

# ── a running simulation ─────────────────────────────────────────────────────

"""One collision: who, when (in the system's time unit), and what they became."""
struct Merger
    t::Float64
    a::String
    b::String
    into::String
end

"""
    OrbitSim(sys; alg = DPRKN12(), abstol = 1e-13, reltol = 1e-13)

A live integration of an OrbitSystem. Advance it with [`advance_orbits!`](@ref);
read [`orbit_positions`](@ref) / [`orbit_velocities`](@ref). Bodies that touch
(distance < sum of radii) merge into one, conserving mass and momentum, and
the integration restarts from the merged state; each event is in `mergers`.
"""
mutable struct OrbitSim
    sys::OrbitSystem
    bodies::Vector{OrbitBody}
    m::Vector{Float64}
    integ::Any
    alg::Any
    abstol::Float64
    reltol::Float64
    E0::Float64
    mergers::Vector{Merger}
end

function OrbitSim(sys::OrbitSystem; alg = DPRKN12(), abstol = 1e-13, reltol = 1e-13)
    s = OrbitSim(sys, copy(sys.bodies), [b.mass for b in sys.bodies], nothing, alg, abstol, reltol,
                 0.0, Merger[])
    _start!(s, copy(sys.x0), copy(sys.v0), 0.0)
    s.E0 = orbit_energy(s)
    return s
end

Base.show(io::IO, s::OrbitSim) = print(io, "OrbitSim(\"", s.sys.name, "\", ", length(s.bodies),
    " bodies, t = ", round(orbit_time(s); digits = 3), ")")

function _touching(s::OrbitSim, x)
    N = length(s.bodies)
    @inbounds for i in 1:N - 1, j in i + 1:N
        rr = s.bodies[i].radius + s.bodies[j].radius
        rr > 0 || continue
        d2 = (x[3j - 2] - x[3i - 2])^2 + (x[3j - 1] - x[3i - 1])^2 + (x[3j] - x[3i])^2
        d2 < rr^2 && return (i, j)
    end
    return nothing
end

function _start!(s::OrbitSim, x, v, t0)
    p = (G = s.sys.G, m = s.m, eps2 = s.sys.softening^2)
    cb = DiscreteCallback((u, t, integ) -> _touching(s, u.x[2]) !== nothing, terminate!;
                          save_positions = (false, false))
    prob = SecondOrderODEProblem(_accel!, v, x, (t0, Inf), p)
    s.integ = init(prob, s.alg; abstol = s.abstol, reltol = s.reltol, save_everystep = false,
                   save_start = false, callback = cb, dt = 1e-3)
    return s
end

"""Current time (days in solar units)."""
orbit_time(s::OrbitSim) = s.integ.t
"""Positions as a 3×N matrix."""
orbit_positions(s::OrbitSim) = reshape(copy(s.integ.u.x[2]), 3, :)
"""Velocities as a 3×N matrix."""
orbit_velocities(s::OrbitSim) = reshape(copy(s.integ.u.x[1]), 3, :)
"""Total energy now."""
orbit_energy(s::OrbitSim) = nbody_energy(s.sys.G, s.m, s.integ.u.x[2], s.integ.u.x[1], s.sys.softening^2)
"""Relative energy change since the start (or since the last merger), (E − E₀)/|E₀|."""
energy_drift(s::OrbitSim) = (orbit_energy(s) - s.E0) / abs(s.E0)
orbit_body(s::OrbitSim, name) = (i = findfirst(b -> b.name == name, s.bodies);
    i === nothing ? error("ObjectSim: no body named '$name'") : i)

"""
    advance_orbits!(s, dt) -> s

Integrate `dt` further (days in solar units). Collisions on the way merge
bodies and the integration carries on to the full `dt`.
"""
function advance_orbits!(s::OrbitSim, dt::Real)
    target = s.integ.t + dt
    while s.integ.t < target - 1e-12 * max(1, abs(target))
        OrdinaryDiffEq.step!(s.integ, target - s.integ.t, true)
        if s.integ.t < target - 1e-12 * max(1, abs(target))     # stopped by a collision
            x = copy(s.integ.u.x[2]); v = copy(s.integ.u.x[1])
            pair = _touching(s, x)
            pair === nothing && break
            s.sys.merge || error("ObjectSim: $(s.bodies[pair[1]].name) and $(s.bodies[pair[2]].name) collided at t = $(s.integ.t) (merge = false)")
            x, v = _merge!(s, pair..., x, v)
            _start!(s, x, v, s.integ.t)
            s.E0 = orbit_energy(s)
        end
    end
    return s
end

# Perfectly inelastic merger: mass adds, momentum and centre of mass are kept,
# volumes add (radius = ∛(r₁³ + r₂³)); the bigger body keeps its name and
# colour (who swallowed whom is in `mergers`).
function _merge!(s::OrbitSim, i, j, x, v)
    mi, mj = s.m[i], s.m[j]; M = mi + mj
    w(k, a, b) = M > 0 ? (mi * a[3i - 3 + k] + mj * b[3j - 3 + k]) / M : (a[3i - 3 + k] + b[3j - 3 + k]) / 2
    xc = ntuple(k -> w(k, x, x), 3); vc = ntuple(k -> w(k, v, v), 3)
    big, small = mi >= mj ? (i, j) : (j, i)
    bi, bs = s.bodies[big], s.bodies[small]
    merged = OrbitBody(bi.name, M, cbrt(bi.radius^3 + bs.radius^3), bi.display_radius, bi.color)
    push!(s.mergers, Merger(s.integ.t, s.bodies[i].name, s.bodies[j].name, merged.name))
    @info "ObjectSim: $(bs.name) fell into $(bi.name) at t = $(round(s.integ.t; digits = 3))"
    keep = [k for k in eachindex(s.bodies) if k != small]
    s.bodies[big] = merged; s.m[big] = M
    for k in 1:3
        x[3big - 3 + k] = xc[k]; v[3big - 3 + k] = vc[k]
    end
    s.bodies = s.bodies[keep]; s.m = s.m[keep]
    idx = [3k - 3 + c for k in keep for c in 1:3]
    return x[idx], v[idx]
end

"""
    run_orbits(scene; days = 365.25, every = 30, io = stdout) -> OrbitSim

Integrate without a window and print positions every `every` days.
"""
function run_orbits(scene; days::Real = 365.25, every::Real = 30, io::IO = stdout)
    sys = scene isa OrbitSystem ? scene : load_orbits(scene)
    s = OrbitSim(sys)
    println(io, "$(sys.name): $(length(sys.bodies)) bodies, $(sys.units) units, G = $(sys.G)")
    t0 = time_ns()
    while orbit_time(s) < days - 1e-9
        advance_orbits!(s, min(every, days - orbit_time(s)))
        println(io, "  t = ", rpad(round(orbit_time(s); digits = 2), 10), " energy drift ",
                round(energy_drift(s); sigdigits = 3), "   ", length(s.bodies), " bodies")
    end
    println(io, "  $(round((time_ns() - t0) / 1e9; digits = 3)) s wall; ",
            isempty(s.mergers) ? "no collisions" : "collisions: " * join(("$(m.a) + $(m.b) at t = $(round(m.t; digits = 2))" for m in s.mergers), ", "))
    return s
end
