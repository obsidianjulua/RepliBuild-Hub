# The four systems the lab ships: what they are, their parameters, and how a
# state is drawn. Plain Julia, no library calls; the right-hand sides are what
# CVODE calls back into.

"""A slider: name, default, range, and whether it moves on a log scale."""
struct Param
    name::String
    default::Float64
    lo::Float64
    hi::Float64
    log::Bool
end
Param(name, default, lo, hi) = Param(name, default, lo, hi, false)

"""
    System

One ODE system: `rhs!(du, u, p, t)`, its parameters and starting state, the
method and tolerances it starts with, and how the window shows it (`kind`):

- `:attractor` — a trajectory in 3D (`view(u)` maps a state to drawing space)
- `:pendulum`  — the double pendulum, drawn as one, with its bob's trail
- `:chemistry` — Robertson's kinetics, drawn as charts over log time
"""
struct System
    key::Symbol
    title::String
    blurb::String
    kind::Symbol
    rhs!::Function
    params::Vector{Param}
    u0::Vector{Float64}
    method::Symbol
    rtol::Float64
    atol::Float64
    dt::Float64          # spacing between drawn points (time units)
    speed::Float64       # starting time units per second in the window
    trail::Int           # starting trail length (points)
    view::Function       # state -> (x, y, z) in drawing space, y up
    invariant::Union{Nothing,Function}   # (u, p) -> a quantity the exact flow conserves
    invariant_name::String
end

defaults(sys::System) = [q.default for q in sys.params]

# ── Lorenz ──────────────────────────────────────────────────────────────────

function lorenz!(du, u, p, t)
    σ, ρ, β = p[1], p[2], p[3]
    x, y, z = u[1], u[2], u[3]
    du[1] = σ * (y - x)
    du[2] = x * (ρ - z) - y
    du[3] = x * y - β * z
    return nothing
end

const LORENZ = System(:lorenz, "Lorenz",
    "Convection in a fluid layer heated from below, cut down to three modes (Lorenz, 1963). " *
    "At σ = 10, β = 8/3 the flow settles to a fixed point for ρ < 24.74 and turns chaotic " *
    "above it: two lobes, never repeating, and neighbouring starts separate like e^(0.9 t).",
    :attractor, lorenz!,
    [Param("sigma", 10.0, 0.1, 30.0), Param("rho", 28.0, 0.1, 100.0), Param("beta", 8 / 3, 0.05, 6.0)],
    [1.0, 1.0, 1.0], :adams, 1e-9, 1e-11, 0.01, 4.0, 6000,
    u -> (u[1] / 10, (u[3] - 25) / 10, u[2] / 10), nothing, "")

# ── Rössler ─────────────────────────────────────────────────────────────────

function rossler!(du, u, p, t)
    a, b, c = p[1], p[2], p[3]
    x, y, z = u[1], u[2], u[3]
    du[1] = -y - z
    du[2] = x + a * y
    du[3] = b + z * (x - c)
    return nothing
end

const ROSSLER = System(:rossler, "Rössler",
    "One fold instead of two (Rössler, 1976): the trajectory spirals out in the x–y plane, " *
    "lifts in z and is folded back in. Raise c from 2 to 6 and the orbit doubles its period " *
    "again and again on its way into chaos.",
    :attractor, rossler!,
    [Param("a", 0.2, 0.0, 0.4), Param("b", 0.2, 0.01, 2.0), Param("c", 5.7, 1.0, 14.0)],
    [1.0, 1.0, 0.0], :adams, 1e-9, 1e-11, 0.02, 8.0, 6000,
    u -> (u[1] / 5, u[3] / 5 - 1.5, u[2] / 5), nothing, "")

# ── Double pendulum ─────────────────────────────────────────────────────────
#
# State (θ₁, θ₂, ω₁, ω₂), angles from straight down. Point masses on massless
# rods; the equations are the standard Lagrangian ones.

function pendulum!(du, u, p, t)
    m1, m2, l1, l2, g = p[1], p[2], p[3], p[4], p[5]
    θ1, θ2, ω1, ω2 = u[1], u[2], u[3], u[4]
    Δ = θ1 - θ2
    sΔ, cΔ = sincos(Δ)
    den = 2m1 + m2 - m2 * cos(2Δ)
    du[1] = ω1
    du[2] = ω2
    du[3] = (-g * (2m1 + m2) * sin(θ1) - m2 * g * sin(θ1 - 2θ2) -
             2sΔ * m2 * (ω2^2 * l2 + ω1^2 * l1 * cΔ)) / (l1 * den)
    du[4] = 2sΔ * (ω1^2 * l1 * (m1 + m2) + g * (m1 + m2) * cos(θ1) + ω2^2 * l2 * m2 * cΔ) / (l2 * den)
    return nothing
end

"""Total energy of the double pendulum (kinetic + potential, pivot at height 0)."""
function pendulum_energy(u, p)
    m1, m2, l1, l2, g = p[1], p[2], p[3], p[4], p[5]
    θ1, θ2, ω1, ω2 = u[1], u[2], u[3], u[4]
    T = 0.5 * m1 * (l1 * ω1)^2 + 0.5 * m2 * ((l1 * ω1)^2 + (l2 * ω2)^2 + 2l1 * l2 * ω1 * ω2 * cos(θ1 - θ2))
    V = -(m1 + m2) * g * l1 * cos(θ1) - m2 * g * l2 * cos(θ2)
    return T + V
end

"""Bob positions (x, y) of the double pendulum, pivot at the origin, y up."""
function pendulum_bobs(u, p)
    l1, l2 = p[3], p[4]
    x1, y1 = l1 * sin(u[1]), -l1 * cos(u[1])
    return (x1, y1), (x1 + l2 * sin(u[2]), y1 - l2 * cos(u[2]))
end

const PENDULUM = System(:pendulum, "Double pendulum",
    "Two rods, two point masses, no friction. Energy is all it keeps: started high enough the " *
    "lower bob never settles into a pattern, and a second pendulum started a millionth of a " *
    "radian away soon swings its own way. The energy drift is CVODE's error, made visible.",
    :pendulum, pendulum!,
    [Param("m1", 1.0, 0.1, 5.0), Param("m2", 1.0, 0.1, 5.0), Param("l1", 1.0, 0.2, 2.0),
     Param("l2", 1.0, 0.2, 2.0), Param("g", 9.81, 0.0, 30.0)],
    [deg2rad(120), deg2rad(150), 0.0, 0.0], :adams, 1e-10, 1e-12, 0.005, 1.0, 1500,
    u -> (0.0, 0.0, 0.0), pendulum_energy, "energy")

# ── Robertson ───────────────────────────────────────────────────────────────
#
# Three species, three reactions (Robertson, 1966):
#   A → B (k₁),  B + B → C + B (k₂),  B + C → A + C (k₃)
# Rate constants nine orders of magnitude apart make it the standard stiff test:
# an explicit-style method must keep its step under the fastest timescale long
# after that timescale has stopped mattering.

function robertson!(du, u, p, t)
    k1, k2, k3 = p[1], p[2], p[3]
    y1, y2, y3 = u[1], u[2], u[3]
    du[1] = -k1 * y1 + k3 * y2 * y3
    du[2] = k1 * y1 - k3 * y2 * y3 - k2 * y2^2
    du[3] = k2 * y2^2
    return nothing
end

const ROBERTSON = System(:robertson, "Robertson (stiff)",
    "Three chemical species with rate constants from 0.04 to 3·10⁷. Everything interesting " *
    "happens within a second, then the system creeps for 10¹⁰ more. BDF lengthens its step " *
    "to match; Adams cannot, because its stability limit, not accuracy, sets its step.",
    :chemistry, robertson!,
    [Param("k1", 0.04, 1e-3, 1.0, true), Param("k2", 3e7, 1e5, 1e9, true), Param("k3", 1e4, 1e2, 1e6, true)],
    [1.0, 0.0, 0.0], :bdf, 1e-6, 1e-12, 0.0, 0.0, 0,
    u -> (0.0, 0.0, 0.0), (u, p) -> u[1] + u[2] + u[3], "y1 + y2 + y3")

const SYSTEMS = [LORENZ, ROSSLER, PENDULUM, ROBERTSON]

"""The lab's system named `key` (`:lorenz`, `:rossler`, `:pendulum`, `:robertson`)."""
function system(key::Symbol)
    i = findfirst(s -> s.key == key, SYSTEMS)
    i === nothing && throw(ArgumentError("no system :$key; have $(join((":" * string(s.key) for s in SYSTEMS), ", "))"))
    return SYSTEMS[i]
end
