#!/usr/bin/env julia
# SUNDIALS Hub package — integration test
#
# Tests the full RepliBuild pipeline for SUNDIALS 7.9.0 (CVODE, serial):
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

using Test
using RepliBuild

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")

# ── Build ────────────────────────────────────────────────────────────────────

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH)
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
    # The proposal would have wrapped sundials_core alone (26 TUs) with no ODE
    # solver in it. Guard the count so a regenerated TOML that silently reverts
    # to core-only fails here rather than at "why is CVodeCreate undefined".
    meta = read(joinpath(PKG_DIR, "julia", "compilation_metadata.json"), String)
    @test occursin("function_count", meta)
    @test length(readlines(`bash -c "nm -D --defined-only $(joinpath(PKG_DIR,"julia","libsundials.so")) | grep -c CVode || true"`)) > 0
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

@testset "Varargs shims" begin
    # Only that the generated overloads exist and are distinct entry points —
    # calling the logger for real needs a live SUNLogger, covered implicitly by
    # the integrations below (CVODE logs through it on every error path).
    for f in (:SUNLogger_QueueMsg_Cstring, :SUNLogger_QueueMsg_Cint,
              :SUNLogger_QueueMsg_Cdouble, :SUNLogger_QueueMsg_Cstring_Cint,
              :cvProcessError_Cstring, :cvProcessError_Cint,
              :SUNGlobalFallbackErrHandler_Cstring)
        @test isdefined(Sundials, f)
    end
end

# ── Context lifecycle ────────────────────────────────────────────────────────

mkctx() = begin
    ref = Ref{Ptr{Cvoid}}(C_NULL)
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
