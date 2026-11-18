# CVODE from Julia: one integrator object over the generated Sundials wrapper.
#
# CVODE's contract is a callback. You hand it a right-hand side and it calls you
# from deep inside its own stack, hundreds of times per solve. Three things make
# that safe and fast here:
#
#  * The right-hand side lives in a `Rhs{F,P}` and reaches the C callback through
#    CVODE's `user_data` pointer. The @cfunction is declared with a `Ref{Rhs{F,P}}`
#    argument, so it is compiled once per concrete (function, parameters) pair
#    and the call into `f!` is static: no dynamic dispatch per evaluation.
#  * `u` and `du` are `CVec`s, views straight onto the N_Vector storage, so an
#    evaluation allocates nothing.
#  * An exception in `f!` must not unwind through C frames. It is caught, CVODE
#    is told the evaluation failed (it then returns CV_RHSFUNC_FAIL), and the
#    exception is rethrown once control is back in Julia.

const NVector = S._generic_N_Vector

"""
    CVec(ptr, n)

An `AbstractVector{Float64}` over memory CVODE owns (an N_Vector's data). Valid
only inside the callback that received it.
"""
struct CVec <: AbstractVector{Float64}
    ptr::Ptr{Float64}
    n::Int
end
Base.size(v::CVec) = (v.n,)
Base.IndexStyle(::Type{CVec}) = IndexLinear()
Base.@propagate_inbounds function Base.getindex(v::CVec, i::Int)
    @boundscheck checkbounds(v, i)
    return unsafe_load(v.ptr, i)
end
Base.@propagate_inbounds function Base.setindex!(v::CVec, x, i::Int)
    @boundscheck checkbounds(v, i)
    unsafe_store!(v.ptr, Float64(x), i)
    return v
end

mutable struct Rhs{F,P}
    f!::F            # f!(du, u, p, t)
    p::P
    n::Int
    err::Any         # (exception, backtrace) from the last failed evaluation
end

function _rhs_c(t::Cdouble, y::Ptr{NVector}, ydot::Ptr{NVector}, r::Rhs{F,P})::Cint where {F,P}
    try
        r.f!(CVec(S.N_VGetArrayPointer(ydot), r.n), CVec(S.N_VGetArrayPointer(y), r.n), r.p, t)
        return Cint(0)
    catch e
        r.err = (e, catch_backtrace())
        return Cint(-1)            # < 0: unrecoverable, CVode stops with CV_RHSFUNC_FAIL
    end
end
_rhs_ptr(::Rhs{F,P}) where {F,P} =
    @cfunction(_rhs_c, Cint, (Cdouble, Ptr{NVector}, Ptr{NVector}, Ref{Rhs{F,P}}))

"""
    Cvode(f!, u0, p; method = :bdf, rtol = 1e-8, atol = 1e-10, t0 = 0.0,
          maxsteps = 100_000, newton = method == :bdf, quiet = false)

A CVODE integrator for `du/dt = f(u, p, t)`, with `f!(du, u, p, t)` filling `du`.

- `method = :bdf` — backward differentiation formulas, orders 1–5, for stiff
  problems. Solved by Newton iteration with a dense linear solver and a
  difference-quotient Jacobian.
- `method = :adams` — Adams–Moulton, orders 1–12, for non-stiff problems. Solved
  by fixed-point iteration unless `newton = true`.

`p` is shared, not copied: change its entries and the next step sees them.
Note that with `advance!` CVODE has usually stepped past the `tout` it returned
at (it interpolates back), so the change takes effect from there; to change
`p` at an exact time, [`set_stop_time!`](@ref) there first, or [`reinit!`](@ref).
CVODE prints its errors to stderr; `quiet = true` removes that handler (the
returned flags still say what happened).
Advance with [`advance!`](@ref) or [`onestep!`](@ref); read the state with
[`state`](@ref) and the work done with [`stats`](@ref). [`free!`](@ref) releases
the C side now; a finalizer does it otherwise.
"""
mutable struct Cvode{R<:Rhs}
    ctx::Ptr{S.SUNContext}
    mem::Ptr{Cvoid}
    y::Ptr{NVector}
    A::Ptr{S._generic_SUNMatrix}
    LS::Ptr{S._generic_SUNLinearSolver}
    NLS::Ptr{S._generic_SUNNonlinearSolver}
    rhs::R
    method::Symbol
    newton::Bool
    t::Float64
    rtol::Float64
    atol::Float64
    maxsteps::Int
end

function Cvode(f!::F, u0::AbstractVector{<:Real}, p::P; method::Symbol = :bdf,
               rtol::Real = 1e-8, atol::Real = 1e-10, t0::Real = 0.0,
               maxsteps::Integer = 100_000, newton::Bool = method == :bdf,
               quiet::Bool = false) where {F,P}
    method in (:bdf, :adams) || throw(ArgumentError("method must be :bdf or :adams, got :$method"))
    n = length(u0)
    n > 0 || throw(ArgumentError("u0 is empty"))
    ctxr = Ref{Ptr{S.SUNContext}}(C_NULL)
    S.SUNContext_Create(Cint(0), ctxr) == 0 || error("SUNContext_Create failed")
    ctx = ctxr[]
    quiet && S.SUNContext_ClearErrHandlers(ctx)
    y = S.N_VNew_Serial(Int64(n), ctx)
    y == C_NULL && error("N_VNew_Serial($n) failed")
    _load!(y, u0)
    mem = S.CVodeCreate(method == :bdf ? S.CV_BDF() : S.CV_ADAMS(), ctx)
    mem == C_NULL && error("CVodeCreate failed")
    cv = Cvode(ctx, mem, y, Ptr{S._generic_SUNMatrix}(C_NULL), Ptr{S._generic_SUNLinearSolver}(C_NULL),
               Ptr{S._generic_SUNNonlinearSolver}(C_NULL), Rhs(f!, p, n, nothing), method, newton,
               Float64(t0), Float64(rtol), Float64(atol), Int(maxsteps))
    finalizer(free!, cv)
    _check(S.CVodeInit(mem, _rhs_ptr(cv.rhs), Float64(t0), y), "CVodeInit")
    _check(S.CVodeSetUserData(mem, pointer_from_objref(cv.rhs)), "CVodeSetUserData")
    _check(S.CVodeSStolerances(mem, cv.rtol, cv.atol), "CVodeSStolerances")
    _check(S.CVodeSetMaxNumSteps(mem, cv.maxsteps), "CVodeSetMaxNumSteps")
    # CVODE warns (to stderr) every time t + h == t; ten of those say nothing a
    # returned flag does not.
    S.CVodeSetMaxHnilWarns(mem, Cint(-1))
    if newton
        cv.A = S.SUNDenseMatrix(Int64(n), Int64(n), ctx)
        cv.LS = S.SUNLinSol_Dense(y, cv.A, ctx)
        _check(S.CVodeSetLinearSolver(mem, cv.LS, cv.A), "CVodeSetLinearSolver")
    else
        # Always attach SOME nonlinear solver. CVODE's default is Newton, and
        # Newton with no linear solver dereferences a NULL lsolve (upstream
        # behaviour; packages/sundials/test.jl has the note).
        cv.NLS = S.SUNNonlinSol_FixedPoint(y, Cint(0), ctx)
        _check(S.CVodeSetNonlinearSolver(mem, cv.NLS), "CVodeSetNonlinearSolver")
    end
    return cv
end

Base.show(io::IO, cv::Cvode) = print(io, "Cvode(", cv.method, cv.newton ? "+newton" : "+fixedpoint",
    ", n = ", cv.rhs.n, ", t = ", cv.t, cv.mem == C_NULL ? ", freed" : "", ")")

function _load!(y::Ptr{NVector}, u)
    d = S.N_VGetArrayPointer(y)
    for i in eachindex(u)
        unsafe_store!(d, Float64(u[i]), i)
    end
end

_flagname(flag) = something(S.CVodeGetReturnFlagName(flag), "flag $flag")
_check(flag, what) = flag == 0 ? flag : error("OdeLab: $what returned $(_flagname(flag))")

_alive(cv::Cvode) = cv.mem == C_NULL ? error("OdeLab: this Cvode has been freed") : cv

"""Release the CVODE memory, solvers, vector and context. Safe to call twice."""
function free!(cv::Cvode)
    cv.mem == C_NULL && return nothing
    S.CVodeFree(Ref(cv.mem)); cv.mem = C_NULL
    cv.LS == C_NULL || (S.SUNLinSolFree(cv.LS); cv.LS = C_NULL)
    cv.A == C_NULL || (S.SUNMatDestroy(cv.A); cv.A = C_NULL)
    cv.NLS == C_NULL || (S.SUNNonlinSolFree(cv.NLS); cv.NLS = C_NULL)
    S.N_VDestroy(cv.y); cv.y = C_NULL
    S.SUNContext_Free(Ref(cv.ctx)); cv.ctx = C_NULL
    return nothing
end

function _rethrow_rhs(cv::Cvode)
    err = cv.rhs.err
    err === nothing && return
    cv.rhs.err = nothing
    throw(CapturedException(err[1], err[2]))
end

"""
    advance!(cv, tout) -> flag

Integrate to `tout` (CVODE steps past it and interpolates back). Returns CVODE's
flag: 0 on success, negative on failure (`CV_TOO_MUCH_WORK()` = -1 when
`maxsteps` ran out first). `cv.t` is where it actually got to.
"""
function advance!(cv::Cvode, tout::Real)
    _alive(cv)
    tret = Ref(cv.t)
    flag = GC.@preserve cv S.CVode(cv.mem, Float64(tout), cv.y, tret, S.CV_NORMAL())
    cv.t = tret[]
    _rethrow_rhs(cv)
    return Int(flag)
end

"""
    onestep!(cv, tout) -> flag

Take one internal step towards `tout` (it may overshoot). `cv.t` is the new time
and [`stats`](@ref)`(cv).h` the step just taken.
"""
function onestep!(cv::Cvode, tout::Real)
    _alive(cv)
    tret = Ref(cv.t)
    flag = GC.@preserve cv S.CVode(cv.mem, Float64(tout), cv.y, tret, S.CV_ONE_STEP())
    cv.t = tret[]
    _rethrow_rhs(cv)
    return Int(flag)
end

"""Restart from `u0` at `t0` (same method, tolerances and parameters)."""
function reinit!(cv::Cvode, u0::AbstractVector{<:Real}, t0::Real = 0.0)
    _alive(cv)
    length(u0) == cv.rhs.n || throw(DimensionMismatch("u0 has $(length(u0)) entries, the system $(cv.rhs.n)"))
    _load!(cv.y, u0)
    _check(S.CVodeReInit(cv.mem, Float64(t0), cv.y), "CVodeReInit")
    cv.t = Float64(t0)
    return cv
end

"""
    set_tolerances!(cv, rtol, atol)

Change the tolerances, carrying on from the current state and time. The method's
history starts over (order 1, a fresh first step), as after [`reinit!`](@ref).

That restart is not optional. CVodeSStolerances sets `cv_e_data = NULL` ("will
be set to cvode_mem in InitialSetup", cvode.c:724), and InitialSetup runs only
on the first step after an init (cvode.c:1128). Called mid-run on its own, the
next step hands NULL to cvEwtSet and the process segfaults (it did, here,
before this restart was added). CVodeReInit at the current state puts the
integrator back at step 0, so InitialSetup runs again.
"""
function set_tolerances!(cv::Cvode, rtol::Real, atol::Real)
    _alive(cv)
    _check(S.CVodeSStolerances(cv.mem, Float64(rtol), Float64(atol)), "CVodeSStolerances")
    _check(S.CVodeReInit(cv.mem, cv.t, cv.y), "CVodeReInit")
    cv.rtol, cv.atol = Float64(rtol), Float64(atol)
    return cv
end

"""Never step past `tstop` (the step that reaches it returns `CV_TSTOP_RETURN()` = 1)."""
set_stop_time!(cv::Cvode, tstop::Real) =
    (_check(S.CVodeSetStopTime(_alive(cv).mem, Float64(tstop)), "CVodeSetStopTime"); cv)

"""The current state as a new `Vector{Float64}`."""
state(cv::Cvode) = copy(unsafe_wrap(Array, S.N_VGetArrayPointer(_alive(cv).y), cv.rhs.n))
"""Write the current state into `out`."""
function state!(out::AbstractVector, cv::Cvode)
    d = S.N_VGetArrayPointer(_alive(cv).y)
    for i in 1:cv.rhs.n
        out[i] = unsafe_load(d, i)
    end
    return out
end

function _get(f, cv, T)
    r = Ref{T}(zero(T))
    f(cv.mem, r)
    return r[]
end

"""
    stats(cv) -> NamedTuple

Work done since the last (re)init: `steps`, `rhs` (right-hand side evaluations,
including the ones the difference-quotient Jacobian spent), `jac` (Jacobian
evaluations), `errfails` (rejected steps), `nlfails` (nonlinear-solver
convergence failures), `order` (current method order) and `h` (last step size).
"""
function stats(cv::Cvode)
    _alive(cv)
    rhs = _get(S.CVodeGetNumRhsEvals, cv, Clong)
    jac = 0
    if cv.newton
        rhs += _get(S.CVodeGetNumLinRhsEvals, cv, Clong)
        jac = Int(_get(S.CVodeGetNumJacEvals, cv, Clong))
    end
    return (steps = Int(_get(S.CVodeGetNumSteps, cv, Clong)), rhs = Int(rhs), jac = jac,
            errfails = Int(_get(S.CVodeGetNumErrTestFails, cv, Clong)),
            nlfails = Int(_get(S.CVodeGetNumNonlinSolvConvFails, cv, Clong)),
            order = Int(_get(S.CVodeGetCurrentOrder, cv, Cint)),
            h = _get(S.CVodeGetLastStep, cv, Cdouble))
end

"""CVODE's name for a return flag, e.g. `CV_TOO_MUCH_WORK`."""
flagname(flag::Integer) = _flagname(flag)
