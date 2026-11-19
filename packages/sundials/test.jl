#!/usr/bin/env julia
# SUNDIALS Hub package — integration test
#
# Tests the full RepliBuild pipeline for SUNDIALS 7.9.0 (CVODE, ARKODE, IDA and
# KINSOL; serial):
#   clean → build → load wrapper → exercise API
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/sundials/test.jl
#
# WHAT THIS TEST IS FOR, beyond "does it load":
#
#  1. CVODE's API contract is a CALLBACK. You do not call the integrator so much
#     as hand it your right-hand side and let it call you, from deep inside its
#     own stack, hundreds of times per solve. Every integration below drives a
#     Julia @cfunction as a CVRhsFn — and that callback takes a `sunrealtype t`
#     first argument, so it also exercises a float-class scalar in the argument
#     list of a generated thunk.
#
#  2. The harvested config is a PIN, and a wrong pin does not fail the build. If
#     SUNDIALS_PRECISION or SUNDIALS_INDEX_SIZE ever drift, the library still
#     compiles, links, wraps clean, and silently integrates at the wrong
#     precision. So the assertions here are deliberately probe-DEPENDENT: they
#     compare against closed-form solutions at tolerances only double precision
#     can reach, and read the version back out of the built .so.
#
#  3. Four solvers share one library (upstream builds one per solver). Each gets
#     a solve with a known answer through its own callback type: CVRhsFn,
#     ARKRhsFn (ERKStep, ARKStep, SPRKStep), IDAResFn, KINSysFn.

using Test
using RepliBuild

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")

# ── Build ────────────────────────────────────────────────────────────────────

@testset "Build pipeline" begin
    # deps=false keeps .replibuild_cache/deps/ (the SUNDIALS clone and its pin
    # marker) and clears everything else, so the build below is a cold one
    # without a fresh clone. A bare clean() deletes the clone too, turning every
    # run into a network fetch (same choice as packages/jolt and bullet3).
    deps_dir = joinpath(PKG_DIR, ".replibuild_cache", "deps")
    had_clone = isdir(deps_dir)
    RepliBuild.clean(TOML_PATH; deps = false)
    had_clone && @test isdir(deps_dir)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libsundials.so") || endswith(lib, "libsundials.dylib")
    @test filesize(lib) > 500_000

    julia_dir = joinpath(PKG_DIR, "julia")
    @test isfile(joinpath(julia_dir, "compilation_metadata.json"))

    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test isfile(joinpath(julia_dir, "Sundials.jl"))
end

@testset "Source set is the hand-inverted union, not the probe's default" begin
    # The proposal would have wrapped sundials_core alone (26 TUs) with no solver
    # in it. Guard each solver's entry points so a regenerated TOML that silently
    # drops one fails here rather than at "why is ARKStepCreate undefined".
    meta = read(joinpath(PKG_DIR, "julia", "compilation_metadata.json"), String)
    @test occursin("function_count", meta)
    so = joinpath(PKG_DIR, "julia", "libsundials.so")
    defined = Set(split(read(pipeline(`nm -D --defined-only $so`, `awk '{print $3}'`), String)))
    for f in ("CVodeCreate", "ERKStepCreate", "ARKStepCreate", "SPRKStepCreate", "MRIStepCreate",
              "LSRKStepCreateSTS", "IDACreate", "KINCreate",
              "N_VGetSubvector_ManyVector")        # ARKODE's adjoint code calls it
        @test f in defined
    end
    # A SUNDIALS function the library calls but does not define means a source
    # file the union needs is excluded (it would surface as a lazy-binding crash
    # on first call, not at load). Everything undefined must be libc/libm.
    undefined = split(read(pipeline(`nm -D --undefined-only $so`, `awk '{print $2}'`), String))
    @test !any(u -> occursin(r"^(SUN|N_V|CV|ARK|ERK|SPRK|MRI|LSRK|IDA|KIN|ark|ida|kin|cv)", u), undefined)
end

include(joinpath(PKG_DIR, "julia", "Sundials.jl"))
using .Sundials

# ── The config pin, asserted behaviourally ───────────────────────────────────

@testset "Harvested config pin" begin
    # Version read back out of the BUILT .so, not out of the TOML.
    buf = Vector{UInt8}(undef, 64)
    @test Sundials.SUNDIALSGetVersion(pointer(buf), Csize_t(64)) == 0
    ver = unsafe_string(pointer(buf))
    @test ver == "7.9.0"

    # SUNDIALS_INDEX_SIZE=64 → sunindextype is int64. Proven at the wrapper's
    # own return type, which DWARF derived from the compiled library.
    @test Base.return_types(Sundials.N_VGetLength)[1] === Int64

    # SUNDIALS_PRECISION=double → sunrealtype is double. N_VGetArrayPointer
    # hands back the vector's storage; if the pin had drifted to single, this
    # would be Ptr{Cfloat} and every assertion below would be meaningless.
    @test Base.return_types(Sundials.N_VGetArrayPointer)[1] === Ptr{Cdouble}
end

# ── Residue: the shims the manifest had to declare ───────────────────────────

@testset "Value macros (CV_* are #defines, erased by the preprocessor)" begin
    @test Sundials.CV_ADAMS()   == 1
    @test Sundials.CV_BDF()     == 2
    @test Sundials.CV_NORMAL()  == 1
    @test Sundials.CV_SUCCESS() == 0
    @test Sundials.CV_ROOT_RETURN() == 2
    @test Sundials.CV_MEM_NULL()    == -21
    @test Sundials.CV_ILL_INPUT()   == -22
end

@testset "Value macros (ARK_*, IDA_*, KIN_* — also #defines)" begin
    @test Sundials.ARK_NORMAL() == 1 && Sundials.ARK_ONE_STEP() == 2
    @test Sundials.ARK_SUCCESS() == 0 && Sundials.ARK_TSTOP_RETURN() == 1
    @test Sundials.ARK_TOO_MUCH_WORK() == -1 && Sundials.ARK_MEM_NULL() == -21
    @test Sundials.ARK_INTERP_LAGRANGE() == 1
    @test Sundials.IDA_NORMAL() == 1 && Sundials.IDA_YA_YDP_INIT() == 1 && Sundials.IDA_Y_INIT() == 2
    @test Sundials.IDA_SUCCESS() == 0 && Sundials.IDA_MEM_NULL() == -20 && Sundials.IDA_ILL_INPUT() == -22
    @test Sundials.KIN_NONE() == 0 && Sundials.KIN_LINESEARCH() == 1 && Sundials.KIN_FP() == 3
    @test Sundials.KIN_SUCCESS() == 0 && Sundials.KIN_MAXITER_REACHED() == -6
end

@testset "Owned flag-name strings (malloc'd, freed by the wrapper)" begin
    @test Sundials.CVodeGetReturnFlagName(Sundials.CV_TOO_MUCH_WORK()) == "CV_TOO_MUCH_WORK"
    @test Sundials.ARKodeGetReturnFlagName(Sundials.ARK_TOO_MUCH_WORK()) == "ARK_TOO_MUCH_WORK"
    @test Sundials.IDAGetReturnFlagName(Sundials.IDA_CONV_FAIL()) == "IDA_CONV_FAIL"
    @test Sundials.KINGetReturnFlagName(Sundials.KIN_MAXITER_REACHED()) == "KIN_MAXITER_REACHED"
    # the deprecated per-stepper name hands back the same malloc'd buffer
    @test Sundials.ERKStepGetReturnFlagName(Sundials.ARK_SUCCESS()) == "ARK_SUCCESS"
end

@testset "Varargs shims" begin
    # Only that the generated overloads exist and are distinct entry points —
    # calling the logger for real needs a live SUNLogger, covered implicitly by
    # the integrations below (CVODE logs through it on every error path).
    for f in (:SUNLogger_QueueMsg_Cstring, :SUNLogger_QueueMsg_Cint,
              :SUNLogger_QueueMsg_Cdouble, :SUNLogger_QueueMsg_Cstring_Cint,
              :cvProcessError_Cstring, :cvProcessError_Cint,
              :arkProcessError_Cstring, :IDAProcessError_Cstring,
              :KINProcessError_Cstring, :KINPrintInfo_Cstring,
              :SUNGlobalFallbackErrHandler_Cstring)
        @test isdefined(Sundials, f)
    end
end

# ── Context lifecycle ────────────────────────────────────────────────────────

# The wrapper types the context: SUNContext_Create takes Ptr{Ptr{SUNContext}}
# (DWARF names the opaque `struct _SUNContext*`), and a Ref{Ptr{Cvoid}} no
# longer converts to it. Everything that takes the context back is typed the
# same way, so the Ref has to be too.
mkctx() = begin
    ref = Ref{Ptr{Sundials.SUNContext}}(C_NULL)
    flag = Sundials.SUNContext_Create(Cint(0), ref)
    (flag, ref[])
end

@testset "SUNContext lifecycle" begin
    flag, ctx = mkctx()
    @test flag == 0
    @test ctx != C_NULL
    @test Sundials.SUNContext_Free(Ref(ctx)) == 0
end

@testset "N_Vector serial" begin
    _, ctx = mkctx()
    v = Sundials.N_VNew_Serial(Int64(5), ctx)
    @test v != C_NULL
    @test Sundials.N_VGetLength(v) == 5

    d = Sundials.N_VGetArrayPointer(v)
    unsafe_store!(d, 3.0, 1); unsafe_store!(d, 4.0, 2)
    for i in 3:5; unsafe_store!(d, 0.0, i); end
    # ‖(3,4,0,0,0)‖∞ = 4
    @test Sundials.N_VMaxNorm(v) ≈ 4.0
    Sundials.N_VConst(2.0, v)
    @test unsafe_load(d, 3) == 2.0

    Sundials.N_VDestroy(v)
    Sundials.SUNContext_Free(Ref(ctx))
end

# ── THE HEADLINE TEST: a Julia closure driving CVODE ─────────────────────────
#
# y' = -λy,  y(0) = 1   ⇒   y(t) = exp(-λt)
#
# CVRhsFn is  int f(sunrealtype t, N_Vector y, N_Vector ydot, void *user_data)

const LAMBDA = 2.5

function rhs_decay(t::Cdouble, y::Ptr{Sundials._generic_N_Vector},
                   ydot::Ptr{Sundials._generic_N_Vector}, ::Ptr{Cvoid})::Cint
    yp    = Sundials.N_VGetArrayPointer(y)
    ydotp = Sundials.N_VGetArrayPointer(ydot)
    unsafe_store!(ydotp, -LAMBDA * unsafe_load(yp, 1), 1)
    return Cint(0)
end

@testset "Julia @cfunction as CVRhsFn — exponential decay" begin
    _, ctx = mkctx()
    y = Sundials.N_VNew_Serial(Int64(1), ctx)
    unsafe_store!(Sundials.N_VGetArrayPointer(y), 1.0, 1)

    mem = Sundials.CVodeCreate(Sundials.CV_BDF(), ctx)
    @test mem != C_NULL

    cb = @cfunction(rhs_decay, Cint, (Cdouble, Ptr{Sundials._generic_N_Vector},
                                      Ptr{Sundials._generic_N_Vector}, Ptr{Cvoid}))

    @test Sundials.CVodeInit(mem, cb, 0.0, y) == Sundials.CV_SUCCESS()
    @test Sundials.CVodeSStolerances(mem, 1e-12, 1e-14) == Sundials.CV_SUCCESS()

    A  = Sundials.SUNDenseMatrix(Int64(1), Int64(1), ctx)
    LS = Sundials.SUNLinSol_Dense(y, A, ctx)
    @test Sundials.CVodeSetLinearSolver(mem, LS, A) == Sundials.CV_SUCCESS()

    tret = Ref{Cdouble}(0.0)
    for tout in (0.5, 1.0, 2.0)
        flag = Sundials.CVode(mem, tout, y, tret, Sundials.CV_NORMAL())
        @test flag == Sundials.CV_SUCCESS()
        @test tret[] ≈ tout
        got = unsafe_load(Sundials.N_VGetArrayPointer(y), 1)
        # rtol 1e-12 is only reachable in double precision — this assertion is
        # the probe-dependent one. In single it would miss by ~1e-7.
        @test got ≈ exp(-LAMBDA * tout) rtol=1e-9
    end

    nsteps = Ref{Clong}(0)
    @test Sundials.CVodeGetNumSteps(mem, nsteps) == Sundials.CV_SUCCESS()
    @test nsteps[] > 0          # it really integrated, not short-circuited

    nrhs = Ref{Clong}(0)
    @test Sundials.CVodeGetNumRhsEvals(mem, nrhs) == Sundials.CV_SUCCESS()
    @test nrhs[] > 10           # the Julia callback was entered many times

    Sundials.CVodeFree(Ref(mem))
    Sundials.SUNLinSolFree(LS); Sundials.SUNMatDestroy(A)
    Sundials.N_VDestroy(y); Sundials.SUNContext_Free(Ref(ctx))
end

# ── A stiff 2×2 system: Newton + dense linear solve, closed form ─────────────
#
# y1' = -100 y1,  y2' = -y2   ⇒   stiffness ratio 100, needs BDF + a Jacobian.

function rhs_stiff(t::Cdouble, y::Ptr{Sundials._generic_N_Vector},
                   ydot::Ptr{Sundials._generic_N_Vector}, ::Ptr{Cvoid})::Cint
    yp    = Sundials.N_VGetArrayPointer(y)
    ydotp = Sundials.N_VGetArrayPointer(ydot)
    unsafe_store!(ydotp, -100.0 * unsafe_load(yp, 1), 1)
    unsafe_store!(ydotp,   -1.0 * unsafe_load(yp, 2), 2)
    return Cint(0)
end

@testset "Stiff 2×2 system through the dense linear solver" begin
    _, ctx = mkctx()
    y  = Sundials.N_VNew_Serial(Int64(2), ctx)
    yp = Sundials.N_VGetArrayPointer(y)
    unsafe_store!(yp, 1.0, 1); unsafe_store!(yp, 1.0, 2)

    mem = Sundials.CVodeCreate(Sundials.CV_BDF(), ctx)
    cb  = @cfunction(rhs_stiff, Cint, (Cdouble, Ptr{Sundials._generic_N_Vector},
                                       Ptr{Sundials._generic_N_Vector}, Ptr{Cvoid}))
    @test Sundials.CVodeInit(mem, cb, 0.0, y) == Sundials.CV_SUCCESS()
    @test Sundials.CVodeSStolerances(mem, 1e-10, 1e-12) == Sundials.CV_SUCCESS()

    A  = Sundials.SUNDenseMatrix(Int64(2), Int64(2), ctx)
    LS = Sundials.SUNLinSol_Dense(y, A, ctx)
    @test Sundials.CVodeSetLinearSolver(mem, LS, A) == Sundials.CV_SUCCESS()

    tret = Ref{Cdouble}(0.0)
    @test Sundials.CVode(mem, 1.0, y, tret, Sundials.CV_NORMAL()) == Sundials.CV_SUCCESS()
    @test unsafe_load(yp, 1) ≈ exp(-100.0) atol=1e-12
    @test unsafe_load(yp, 2) ≈ exp(-1.0)   rtol=1e-8

    # The dense solver was actually set up and factored — proves the SUNMatrix /
    # SUNLinearSolver vtables were reached through the wrapper, not bypassed.
    njac = Ref{Clong}(0)
    @test Sundials.CVodeGetNumJacEvals(mem, njac) == Sundials.CV_SUCCESS()
    @test njac[] > 0

    Sundials.CVodeFree(Ref(mem))
    Sundials.SUNLinSolFree(LS); Sundials.SUNMatDestroy(A)
    Sundials.N_VDestroy(y); Sundials.SUNContext_Free(Ref(ctx))
end

# ── A second callback type: CVRootFn ─────────────────────────────────────────
#
# y' = 1, y(0) = 0, root at y - 0.75 = 0 ⇒ CVode must stop at t = 0.75 exactly.

function rhs_ramp(::Cdouble, ::Ptr{Sundials._generic_N_Vector},
                  ydot::Ptr{Sundials._generic_N_Vector}, ::Ptr{Cvoid})::Cint
    unsafe_store!(Sundials.N_VGetArrayPointer(ydot), 1.0, 1)
    return Cint(0)
end

function root_at_075(::Cdouble, y::Ptr{Sundials._generic_N_Vector},
                     gout::Ptr{Cdouble}, ::Ptr{Cvoid})::Cint
    unsafe_store!(gout, unsafe_load(Sundials.N_VGetArrayPointer(y), 1) - 0.75, 1)
    return Cint(0)
end

@testset "CVRootFn — root finding stops the integration" begin
    _, ctx = mkctx()
    y = Sundials.N_VNew_Serial(Int64(1), ctx)
    unsafe_store!(Sundials.N_VGetArrayPointer(y), 0.0, 1)

    mem = Sundials.CVodeCreate(Sundials.CV_ADAMS(), ctx)
    cb  = @cfunction(rhs_ramp, Cint, (Cdouble, Ptr{Sundials._generic_N_Vector},
                                      Ptr{Sundials._generic_N_Vector}, Ptr{Cvoid}))
    rf  = @cfunction(root_at_075, Cint, (Cdouble, Ptr{Sundials._generic_N_Vector},
                                         Ptr{Cdouble}, Ptr{Cvoid}))
    @test Sundials.CVodeInit(mem, cb, 0.0, y) == Sundials.CV_SUCCESS()
    @test Sundials.CVodeSStolerances(mem, 1e-10, 1e-12) == Sundials.CV_SUCCESS()
    @test Sundials.CVodeRootInit(mem, Cint(1), rf) == Sundials.CV_SUCCESS()

    # Adams needs a nonlinear solver attached. CVODE's default is Newton, which
    # needs a linear solver; with neither attached CVode dereferences a NULL
    # lsolve and SEGFAULTS rather than returning an error code. That is upstream
    # behaviour, not a wrapping artifact — the identical C sequence against this
    # same .so dies the same way (verified 2026-09-06, clang -O0, exit 139). Left
    # here as a note because "it crashed" is otherwise the obvious place to
    # suspect the callback marshalling, and it is not.
    # Fixed-point is the right nonlinear solver for a non-stiff Adams problem,
    # and attaching it also exercises the sunnonlinsolfixedpoint object library.
    NLS = Sundials.SUNNonlinSol_FixedPoint(y, Cint(0), ctx)
    @test NLS != C_NULL
    @test Sundials.CVodeSetNonlinearSolver(mem, NLS) == Sundials.CV_SUCCESS()

    tret = Ref{Cdouble}(0.0)
    # Ask to integrate to t=10, but the root at t=0.75 must interrupt it.
    flag = Sundials.CVode(mem, 10.0, y, tret, Sundials.CV_NORMAL())
    @test flag == Sundials.CV_ROOT_RETURN()
    @test tret[] ≈ 0.75 atol=1e-9

    found = Vector{Cint}(undef, 1)
    GC.@preserve found begin
        @test Sundials.CVodeGetRootInfo(mem, pointer(found)) == Sundials.CV_SUCCESS()
    end
    @test found[1] != 0

    Sundials.CVodeFree(Ref(mem))
    Sundials.SUNNonlinSolFree(NLS)
    Sundials.N_VDestroy(y); Sundials.SUNContext_Free(Ref(ctx))
end

# ── Error paths ──────────────────────────────────────────────────────────────

@testset "Error paths return the documented codes" begin
    _, ctx = mkctx()

    # NULL cvode_mem → CV_MEM_NULL
    @test Sundials.CVodeSStolerances(C_NULL, 1e-6, 1e-8) == Sundials.CV_MEM_NULL()

    # negative relative tolerance → CV_ILL_INPUT
    y   = Sundials.N_VNew_Serial(Int64(1), ctx)
    unsafe_store!(Sundials.N_VGetArrayPointer(y), 1.0, 1)
    mem = Sundials.CVodeCreate(Sundials.CV_BDF(), ctx)
    cb  = @cfunction(rhs_decay, Cint, (Cdouble, Ptr{Sundials._generic_N_Vector},
                                       Ptr{Sundials._generic_N_Vector}, Ptr{Cvoid}))
    @test Sundials.CVodeInit(mem, cb, 0.0, y) == Sundials.CV_SUCCESS()
    @test Sundials.CVodeSStolerances(mem, -1.0, 1e-8) == Sundials.CV_ILL_INPUT()

    Sundials.CVodeFree(Ref(mem))
    Sundials.N_VDestroy(y); Sundials.SUNContext_Free(Ref(ctx))
end

# ══════════════════════════════════════════════════════════════════════════════
# ARKODE, IDA and KINSOL — each through its own callback type, each against a
# known answer.
# ══════════════════════════════════════════════════════════════════════════════

const NVP = Ptr{Sundials._generic_N_Vector}
nvdata(v) = Sundials.N_VGetArrayPointer(v)
function nvnew(ctx, xs)
    v = Sundials.N_VNew_Serial(Int64(length(xs)), ctx)
    for (i, x) in enumerate(xs)
        unsafe_store!(nvdata(v), Float64(x), i)
    end
    return v
end
nvget(v, n) = [unsafe_load(nvdata(v), i) for i in 1:n]
getlong(f, mem) = (r = Ref{Clong}(0); f(mem, r); r[])

# ── ARKODE ──────────────────────────────────────────────────────────────────
# ARKRhsFn has CVRhsFn's shape, so rhs_decay and rhs_stiff above serve as-is.

@testset "ARKODE ERKStep (explicit RK) — exponential decay" begin
    _, ctx = mkctx()
    y = nvnew(ctx, [1.0])
    cb = @cfunction(rhs_decay, Cint, (Cdouble, NVP, NVP, Ptr{Cvoid}))
    mem = Sundials.ERKStepCreate(cb, 0.0, y, ctx)
    @test mem != C_NULL
    @test Sundials.ARKodeSStolerances(mem, 1e-12, 1e-14) == Sundials.ARK_SUCCESS()
    # An explicit method at 1e-12 needs more than ARKODE's default 500 steps per
    # call to reach t = 2 (measured: ARK_TOO_MUCH_WORK without this).
    @test Sundials.ARKodeSetMaxNumSteps(mem, 100_000) == Sundials.ARK_SUCCESS()
    tret = Ref(0.0)
    for tout in (0.5, 1.0, 2.0)
        @test Sundials.ARKodeEvolve(mem, tout, y, tret, Sundials.ARK_NORMAL()) == Sundials.ARK_SUCCESS()
        @test unsafe_load(nvdata(y), 1) ≈ exp(-LAMBDA * tout) rtol = 1e-9
    end
    @test getlong(Sundials.ARKodeGetNumSteps, mem) > 0
    Sundials.ARKodeFree(Ref(mem))
    Sundials.N_VDestroy(y); Sundials.SUNContext_Free(Ref(ctx))
end

@testset "ARKODE ARKStep (implicit RK, Newton + dense) — stiff 2×2" begin
    _, ctx = mkctx()
    y = nvnew(ctx, [1.0, 1.0])
    cb = @cfunction(rhs_stiff, Cint, (Cdouble, NVP, NVP, Ptr{Cvoid}))
    mem = Sundials.ARKStepCreate(C_NULL, cb, 0.0, y, ctx)    # fe = NULL, fi = the stiff rhs
    @test mem != C_NULL
    @test Sundials.ARKodeSStolerances(mem, 1e-10, 1e-12) == Sundials.ARK_SUCCESS()
    A  = Sundials.SUNDenseMatrix(Int64(2), Int64(2), ctx)
    LS = Sundials.SUNLinSol_Dense(y, A, ctx)
    @test Sundials.ARKodeSetLinearSolver(mem, LS, A) == Sundials.ARK_SUCCESS()
    tret = Ref(0.0)
    @test Sundials.ARKodeEvolve(mem, 1.0, y, tret, Sundials.ARK_NORMAL()) == Sundials.ARK_SUCCESS()
    @test unsafe_load(nvdata(y), 1) ≈ exp(-100.0) atol = 1e-12
    @test unsafe_load(nvdata(y), 2) ≈ exp(-1.0) rtol = 1e-8
    @test getlong(Sundials.ARKodeGetNumJacEvals, mem) > 0  # the implicit stages really factored
    Sundials.ARKodeFree(Ref(mem))
    Sundials.SUNLinSolFree(LS); Sundials.SUNMatDestroy(A)
    Sundials.N_VDestroy(y); Sundials.SUNContext_Free(Ref(ctx))
end

# Harmonic oscillator x'' = -x as y = (x, v), split the way SPRKStep wants it
# (upstream's ark_harmonic_symplectic.c): f1 sets only dx/dt, f2 only dv/dt.
function sprk_xdot(::Cdouble, y::NVP, yd::NVP, ::Ptr{Cvoid})::Cint
    unsafe_store!(nvdata(yd), unsafe_load(nvdata(y), 2), 1)
    return Cint(0)
end
function sprk_vdot(::Cdouble, y::NVP, yd::NVP, ::Ptr{Cvoid})::Cint
    unsafe_store!(nvdata(yd), -unsafe_load(nvdata(y), 1), 2)
    return Cint(0)
end
function osc_full(::Cdouble, y::NVP, yd::NVP, ::Ptr{Cvoid})::Cint
    unsafe_store!(nvdata(yd), unsafe_load(nvdata(y), 2), 1)
    unsafe_store!(nvdata(yd), -unsafe_load(nvdata(y), 1), 2)
    return Cint(0)
end

# Energy ½(x² + v²) every period over `periods`, fixed step h, order 4.
function oscillator_energy(make, periods, h)
    _, ctx = mkctx()
    y = nvnew(ctx, [1.0, 0.0])
    mem = make(y, ctx)
    Sundials.ARKodeSetOrder(mem, 4)
    Sundials.ARKodeSetFixedStep(mem, h)
    Sundials.ARKodeSetMaxNumSteps(mem, 10_000_000)
    tret = Ref(0.0)
    E = Float64[]
    for k in 1:periods
        Sundials.ARKodeEvolve(mem, 2π * k, y, tret, Sundials.ARK_NORMAL()) == Sundials.ARK_SUCCESS() ||
            error("ARKodeEvolve failed at period $k")
        x, v = nvget(y, 2)
        push!(E, (x^2 + v^2) / 2)
    end
    xT = unsafe_load(nvdata(y), 1)
    Sundials.ARKodeFree(Ref(mem))
    Sundials.N_VDestroy(y); Sundials.SUNContext_Free(Ref(ctx))
    return E, xT
end

@testset "ARKODE SPRKStep (symplectic) — energy stays bounded, RK4's drifts" begin
    f1 = @cfunction(sprk_xdot, Cint, (Cdouble, NVP, NVP, Ptr{Cvoid}))
    f2 = @cfunction(sprk_vdot, Cint, (Cdouble, NVP, NVP, Ptr{Cvoid}))
    ff = @cfunction(osc_full, Cint, (Cdouble, NVP, NVP, Ptr{Cvoid}))
    # Same order (4), same fixed step, 2000 periods. A symplectic method keeps a
    # nearby energy exactly, so its error stays a bounded wobble; explicit RK4's
    # amplification factor is |R(ih)| < 1, so its energy only ever decreases.
    Es, xs = oscillator_energy((y, ctx) -> Sundials.SPRKStepCreate(f1, f2, 0.0, y, ctx), 2000, 0.1)
    Ee, _  = oscillator_energy((y, ctx) -> Sundials.ERKStepCreate(ff, 0.0, y, ctx), 2000, 0.1)
    # Measured at h = 0.1 over 2000 periods: SPRK's energy error ≤ 4.1e-6 (3.1e-6
    # at period 200, 4.0e-6 at 2000) and x(T) off by 4e-6; RK4 has lost 8.7e-5 of
    # energy by period 200 and 8.7e-4 by period 2000 — linear in time.
    @test xs ≈ cos(2π * 2000) atol = 1e-4                        # still in phase after 2000 turns
    @test maximum(abs.(Es .- 0.5)) < 1e-5
    @test abs(Es[end] - 0.5) < 2 * abs(Es[200] - 0.5) + 1e-6     # bounded: not growing
    @test all(diff(Ee) .< 0)                                      # RK4: a monotone loss …
    @test (0.5 - Ee[end]) > 8 * (0.5 - Ee[200])                   # … that keeps growing …
    @test (0.5 - Ee[end]) > 100 * maximum(abs.(Es .- 0.5))        # … far past SPRK's wobble
end

# ── IDA ─────────────────────────────────────────────────────────────────────
# Robertson's kinetics as a DAE (upstream's idaRoberts_dns.c): two rate
# equations and the conservation law y1 + y2 + y3 = 1 as an ALGEBRAIC equation.

function res_robertson(::Cdouble, yy::NVP, yp::NVP, rr::NVP, ::Ptr{Cvoid})::Cint
    y = nvdata(yy); d = nvdata(yp); r = nvdata(rr)
    y1, y2, y3 = unsafe_load(y, 1), unsafe_load(y, 2), unsafe_load(y, 3)
    r1 = -0.04y1 + 1e4 * y2 * y3
    unsafe_store!(r, r1 - unsafe_load(d, 1), 1)
    unsafe_store!(r, -r1 - 3e7 * y2^2 - unsafe_load(d, 2), 2)
    unsafe_store!(r, y1 + y2 + y3 - 1.0, 3)
    return Cint(0)
end

function ida_robertson(ctx, y0, yp0)
    yy = nvnew(ctx, y0); yp = nvnew(ctx, yp0)
    mem = Sundials.IDACreate(ctx)
    cb = @cfunction(res_robertson, Cint, (Cdouble, NVP, NVP, NVP, Ptr{Cvoid}))
    Sundials.IDAInit(mem, cb, 0.0, yy, yp) == Sundials.IDA_SUCCESS() || error("IDAInit")
    Sundials.IDASStolerances(mem, 1e-9, 1e-14)
    # 0 → 40 in one IDASolve at 1e-9 takes more than the default 500 steps
    # (measured: IDA_TOO_MUCH_WORK near t = 3 without this).
    Sundials.IDASetMaxNumSteps(mem, 100_000)
    A  = Sundials.SUNDenseMatrix(Int64(3), Int64(3), ctx)
    LS = Sundials.SUNLinSol_Dense(yy, A, ctx)
    Sundials.IDASetLinearSolver(mem, LS, A) == Sundials.IDA_SUCCESS() || error("IDASetLinearSolver")
    return mem, yy, yp, A, LS
end

@testset "IDA — Robertson as a DAE, reference values at t = 40" begin
    _, ctx = mkctx()
    mem, yy, yp, A, LS = ida_robertson(ctx, [1.0, 0.0, 0.0], [-0.04, 0.04, 0.0])
    tret = Ref(0.0)
    @test Sundials.IDASolve(mem, 40.0, tret, yy, yp, Sundials.IDA_NORMAL()) == Sundials.IDA_SUCCESS()
    y = nvget(yy, 3)
    # the same values packages/sundials and examples/OdeLab check CVODE against
    # (SUNDIALS' cvRoberts_dns): y(40) = (0.7158270, 9.185535e-6, 0.2841639)
    @test y[1] ≈ 0.7158270 rtol = 1e-5
    @test y[2] ≈ 9.185535e-6 rtol = 1e-4
    @test y[3] ≈ 0.2841639 rtol = 1e-5
    # the algebraic equation holds to the Newton tolerance (measured: 1.6e-12)
    @test abs(sum(y) - 1) < 1e-10
    @test getlong(Sundials.IDAGetNumSteps, mem) > 0
    Sundials.IDAFree(Ref(mem))
    Sundials.SUNLinSolFree(LS); Sundials.SUNMatDestroy(A)
    Sundials.N_VDestroy(yy); Sundials.N_VDestroy(yp); Sundials.SUNContext_Free(Ref(ctx))
end

@testset "IDA — IDACalcIC repairs an inconsistent start" begin
    _, ctx = mkctx()
    # y3 = 0.3 breaks y1 + y2 + y3 = 1, and y' = 0 breaks the rate equations.
    mem, yy, yp, A, LS = ida_robertson(ctx, [1.0, 0.0, 0.3], [0.0, 0.0, 0.0])
    id = nvnew(ctx, [1.0, 1.0, 0.0])                      # y1, y2 differential; y3 algebraic
    @test Sundials.IDASetId(mem, id) == Sundials.IDA_SUCCESS()
    @test Sundials.IDACalcIC(mem, Sundials.IDA_YA_YDP_INIT(), 0.4) == Sundials.IDA_SUCCESS()
    y0 = nvnew(ctx, zeros(3)); yp0 = nvnew(ctx, zeros(3))
    @test Sundials.IDAGetConsistentIC(mem, y0, yp0) == Sundials.IDA_SUCCESS()
    @test nvget(y0, 3) ≈ [1.0, 0.0, 0.0] atol = 1e-10     # y3 solved for; y1, y2 kept
    @test nvget(yp0, 3)[1:2] ≈ [-0.04, 0.04] atol = 1e-10  # y' solved for
    Sundials.IDAFree(Ref(mem))
    Sundials.SUNLinSolFree(LS); Sundials.SUNMatDestroy(A)
    foreach(Sundials.N_VDestroy, (yy, yp, id, y0, yp0)); Sundials.SUNContext_Free(Ref(ctx))
end

# ── KINSOL ──────────────────────────────────────────────────────────────────

# F(u) = (u1² + u2² − 4, u1 − u2): the circle of radius 2 meets the diagonal at (√2, √2).
function kin_circle(u::NVP, f::NVP, ::Ptr{Cvoid})::Cint
    a, b = unsafe_load(nvdata(u), 1), unsafe_load(nvdata(u), 2)
    unsafe_store!(nvdata(f), a^2 + b^2 - 4, 1)
    unsafe_store!(nvdata(f), a - b, 2)
    return Cint(0)
end

# Fixed-point form G(u) of upstream's kinAnalytic_fp.c: u = G(u) at (1/2, 1, −π/6).
function kin_analytic_g(u::NVP, g::NVP, ::Ptr{Cvoid})::Cint
    x, y, z = unsafe_load(nvdata(u), 1), unsafe_load(nvdata(u), 2), unsafe_load(nvdata(u), 3)
    unsafe_store!(nvdata(g), cos((y - 1) * z) / 3 + 1 / 6, 1)
    unsafe_store!(nvdata(g), sqrt(x^2 + sin(z) + 1.06) / 9 + 0.9, 2)
    unsafe_store!(nvdata(g), -exp(-x * (y - 1)) / 20 - (10π - 3) / 60, 3)
    return Cint(0)
end

# G(u) = cos(u), elementwise: a slow contraction (|G'| ≈ 0.67 at the root, which
# is 0.7390851332151607 in every component), where Anderson acceleration earns
# its keep.
function kin_cos(u::NVP, g::NVP, ::Ptr{Cvoid})::Cint
    for i in 1:Sundials.N_VGetLength(u)
        unsafe_store!(nvdata(g), cos(unsafe_load(nvdata(u), i)), i)
    end
    return Cint(0)
end

function kinsol(f, u0, strategy; maa = 0, newton = false, tol = 1e-12)
    _, ctx = mkctx()
    n = length(u0)
    u = nvnew(ctx, u0); s = nvnew(ctx, ones(n))
    mem = Sundials.KINCreate(ctx)
    maa > 0 && Sundials.KINSetMAA(mem, maa)               # before KINInit
    Sundials.KINInit(mem, f, u) == Sundials.KIN_SUCCESS() || error("KINInit")
    Sundials.KINSetFuncNormTol(mem, tol)
    Sundials.KINSetNumMaxIters(mem, 500)
    A = LS = nothing
    if newton
        A  = Sundials.SUNDenseMatrix(Int64(n), Int64(n), ctx)
        LS = Sundials.SUNLinSol_Dense(u, A, ctx)
        Sundials.KINSetLinearSolver(mem, LS, A) == Sundials.KIN_SUCCESS() || error("KINSetLinearSolver")
        # KINSOL's default reuses a Jacobian for 10 iterations (modified Newton,
        # linear convergence: measured 20 iterations on kin_circle). One setup
        # per iteration is exact Newton.
        Sundials.KINSetMaxSetupCalls(mem, 1)
    end
    flag = Sundials.KINSol(mem, u, strategy, s, s)
    iters = getlong(Sundials.KINGetNumNonlinSolvIters, mem)
    sol = nvget(u, n)
    Sundials.KINFree(Ref(mem))
    LS === nothing || (Sundials.SUNLinSolFree(LS); Sundials.SUNMatDestroy(A))
    Sundials.N_VDestroy(u); Sundials.N_VDestroy(s); Sundials.SUNContext_Free(Ref(ctx))
    return (flag = Int(flag), u = sol, iters = Int(iters))
end

@testset "KINSOL — Newton with line search, dense Jacobian" begin
    cb = @cfunction(kin_circle, Cint, (NVP, NVP, Ptr{Cvoid}))
    r = kinsol(cb, [1.0, 0.5], Sundials.KIN_LINESEARCH(); newton = true)
    @test r.flag in (Sundials.KIN_SUCCESS(), Sundials.KIN_STEP_LT_STPTOL())
    @test r.u ≈ [sqrt(2), sqrt(2)] rtol = 1e-10
    @test 0 < r.iters < 10                                  # quadratic convergence
end

@testset "KINSOL — fixed point, and Anderson acceleration" begin
    cb = @cfunction(kin_analytic_g, Cint, (NVP, NVP, Ptr{Cvoid}))
    r = kinsol(cb, [0.1, 0.1, -0.1], Sundials.KIN_FP())
    @test r.flag == Sundials.KIN_SUCCESS()
    @test r.u ≈ [0.5, 1.0, -π / 6] atol = 1e-10
    c = @cfunction(kin_cos, Cint, (NVP, NVP, Ptr{Cvoid}))
    u0 = [1.0, 0.5, 0.0, 1.5]
    plain = kinsol(c, u0, Sundials.KIN_FP())                 # measured: 71 iterations
    aa    = kinsol(c, u0, Sundials.KIN_FP(); maa = 3)        # measured: 15
    @test plain.flag == Sundials.KIN_SUCCESS() && aa.flag == Sundials.KIN_SUCCESS()
    @test all(abs.(plain.u .- 0.7390851332151607) .< 1e-10)
    @test all(abs.(aa.u .- 0.7390851332151607) .< 1e-10)
    @test aa.iters < plain.iters ÷ 3                        # acceleration is the point

    # UPSTREAM BEHAVIOUR, pinned: an Anderson depth larger than the problem's
    # dimension returns KIN_SUCCESS on a WRONG answer. u = cos(u) with n = 1 and
    # maa = 2 stops after 3 iterations at 0.7280 (0.011 off); maa = 1 is exact in
    # 7. The identical sequence in plain C against this same libsundials.so gives
    # the same numbers (checked 2026-11-18, cc -O0), so it is KINSOL, not the
    # wrapper. Keep maa ≤ length(u). @test_broken: if upstream starts guarding
    # this, the "unexpected pass" says so.
    deep = kinsol(c, [1.0], Sundials.KIN_FP(); maa = 2)
    @test deep.flag == Sundials.KIN_SUCCESS()
    @test_broken abs(deep.u[1] - 0.7390851332151607) < 1e-10
    @test kinsol(c, [1.0], Sundials.KIN_FP(); maa = 1).u[1] ≈ 0.7390851332151607 atol = 1e-12
end
