# The lab without a window: whole trajectories, the stiffness race, the
# separation of neighbouring starts. Everything the window shows can be had
# from here, and the tests use these.

"""
    trajectory(key; p = defaults, u0 = system's, T = 20, dt = system's,
               method, rtol, atol, maxsteps = 100_000) -> NamedTuple

Integrate system `key` from 0 to `T`, keeping a point every `dt`. Returns
`t` (vector), `u` (n × length(t) matrix), `flag` (0 if it got to `T`) and
`stats` (see [`stats`](@ref)) and `ms` (wall time of the integration).
"""
function trajectory(key::Symbol; p = defaults(system(key)), u0 = system(key).u0, T::Real = 20.0,
                    dt::Real = system(key).dt > 0 ? system(key).dt : T / 1000,
                    method::Symbol = system(key).method, rtol::Real = system(key).rtol,
                    atol::Real = system(key).atol, maxsteps::Integer = 100_000)
    sys = system(key)
    cv = Cvode(sys.rhs!, collect(Float64, u0), collect(Float64, p); method, rtol, atol, maxsteps)
    try
        ts = collect(0.0:dt:T)
        U = Matrix{Float64}(undef, length(u0), length(ts))
        U[:, 1] = u0
        flag = 0
        t0 = time_ns()
        k = 1
        for i in 2:length(ts)
            flag = advance!(cv, ts[i])
            flag < 0 && break
            state!(view(U, :, i), cv)
            k = i
        end
        ms = (time_ns() - t0) / 1e6
        return (t = ts[1:k], u = U[:, 1:k], flag, stats = stats(cv), ms)
    finally
        free!(cv)
    end
end

"""
    race(; p = Robertson's defaults, tend = 4e10, maxsteps = 20_000,
         rtol = 1e-6, atol = 1e-12) -> (bdf = …, adams = …)

Robertson's problem, from y = (1, 0, 0), with BDF and with Adams (Newton
iteration for both, so only the method differs). Each result has every step:
`t`, `h` (step size), `y` (3 × steps), and `flag` (0 if it reached `tend`),
`reached` (last t), `stats`, `ms`. Adams is expected to run out of steps.
"""
function race(; p = defaults(ROBERTSON), tend::Real = 4e10, maxsteps::Integer = 20_000,
              rtol::Real = 1e-6, atol::Real = 1e-12)
    go(method) = _stepwise(ROBERTSON, collect(Float64, p), method, tend, maxsteps, rtol, atol)
    return (bdf = go(:bdf), adams = go(:adams))
end

function _stepwise(sys::System, p, method, tend, maxsteps, rtol, atol)
    cv = Cvode(sys.rhs!, sys.u0, p; method, rtol, atol, newton = true, maxsteps = 1000)
    try
        set_stop_time!(cv, tend)
        ts = Float64[]; hs = Float64[]; Y = Float64[]
        u = similar(sys.u0)
        flag = 0
        t0 = time_ns()
        for _ in 1:maxsteps
            flag = onestep!(cv, tend)
            flag < 0 && break
            push!(ts, cv.t); push!(hs, stats(cv).h)
            append!(Y, state!(u, cv))
            flag == S.CV_TSTOP_RETURN() && break
        end
        ms = (time_ns() - t0) / 1e6
        done = flag == S.CV_TSTOP_RETURN()
        return (t = ts, h = hs, y = reshape(Y, 3, :), flag = done ? 0 : (flag < 0 ? flag : Int(S.CV_TOO_MUCH_WORK())),
                reached = cv.t, stats = stats(cv), ms, method)
    finally
        free!(cv)
    end
end

"""
    separation(key; δ = 1e-9, T = 30, p = defaults) -> NamedTuple

Run system `key` twice, the second start moved by `δ` in its first coordinate,
and record the distance `d` between them every `dt`, at tight tolerances so the
growth is the system's and not the integrator's. On a chaotic attractor log d
climbs in a straight line, slope = the largest Lyapunov exponent, until d is as
big as the attractor; [`lyapunov`](@ref) measures that slope properly.
"""
function separation(key::Symbol; δ::Real = 1e-9, T::Real = 30.0, p = defaults(system(key)),
                    rtol::Real = 1e-12, atol::Real = 1e-14)
    sys = system(key)
    u0b = copy(sys.u0); u0b[1] += δ
    a = trajectory(key; p, T, rtol, atol)
    b = trajectory(key; p, u0 = u0b, T, rtol, atol)
    n = min(length(a.t), length(b.t))
    d = [sqrt(sum(abs2, view(a.u, :, i) .- view(b.u, :, i))) for i in 1:n]
    return (t = a.t[1:n], d)
end

"""
    lyapunov(key; p = defaults, T = 1000, τ = 0.5, δ = 1e-6, skip = 20) -> Float64

The largest Lyapunov exponent by Benettin's method: two runs `δ` apart; every
`τ` the distance d is measured, log(d/δ) is added up, and the second run is
pulled back to distance δ along the same direction (a `reinit!`), so it never
leaves the linear regime. The first `skip` time units only bring the start
onto the attractor. Lorenz at (10, 28, 8/3): ≈ 0.906. Rössler at
(0.2, 0.2, 5.7): ≈ 0.07, which needs a longer `T` to settle.

`δ` has to stay well above the integration error. At δ = 1e-8 and rtol 1e-11,
CVODE's own error is a few percent of δ every interval and the estimate comes
out near 1.0 for Lorenz (measured); at 1e-6 it converges to 0.903–0.905.
"""
function lyapunov(key::Symbol; p = defaults(system(key)), T::Real = 1000.0, τ::Real = 0.5,
                  δ::Real = 1e-6, skip::Real = 20.0, rtol::Real = 1e-11, atol::Real = 1e-13)
    sys = system(key)
    pp = collect(Float64, p)
    a = Cvode(sys.rhs!, sys.u0, pp; method = :adams, rtol, atol)
    b = nothing
    try
        advance!(a, skip) == 0 || error("OdeLab: $(sys.title) did not reach t = $skip")
        ua = state(a)
        ub = copy(ua); ub[1] += δ
        b = Cvode(sys.rhs!, ub, pp; method = :adams, rtol, atol, t0 = skip)
        sum_log = 0.0; t = Float64(skip)
        while t < skip + T - 1e-9
            t += τ
            (advance!(a, t) == 0 && advance!(b, t) == 0) || error("OdeLab: integration failed at t = $t")
            state!(ua, a); state!(ub, b)
            d = sqrt(sum(abs2, ub .- ua))
            sum_log += log(d / δ)
            reinit!(b, ua .+ (δ / d) .* (ub .- ua), t)
        end
        return sum_log / T
    finally
        free!(a); b === nothing || free!(b)
    end
end

"""
    drift(key; T = 20, rtol, atol, method) -> Float64

Largest relative change of the system's invariant over `[0, T]`: the energy for
the pendulum, y1 + y2 + y3 for Robertson. Systems without one throw.
"""
function drift(key::Symbol; T::Real = 20.0, kw...)
    sys = system(key)
    sys.invariant === nothing && throw(ArgumentError("$(sys.title) has no invariant"))
    r = trajectory(key; T, kw...)
    p = get(kw, :p, defaults(sys))
    I0 = sys.invariant(r.u[:, 1], p)
    return maximum(abs(sys.invariant(view(r.u, :, i), p) - I0) for i in axes(r.u, 2)) / abs(I0)
end
