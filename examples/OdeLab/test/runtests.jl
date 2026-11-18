# OdeLab tests.
#
#   julia --project=examples/OdeLab -e 'using Pkg; Pkg.test()'
#
# The integrator layer is checked against closed forms and published reference
# values; the window, when there is a display, by running each system hidden.

using Test
using OdeLab
import OdeLab: S

@testset "OdeLab" begin

@testset "Cvode against a closed form" begin
    # y' = -λy  ⇒  y = e^(-λt), with both methods
    for method in (:bdf, :adams)
        cv = Cvode((du, u, p, t) -> (du[1] = -p[1] * u[1]), [1.0], [2.5]; method, rtol = 1e-11, atol = 1e-14)
        for tout in (0.5, 1.0, 2.0)
            @test advance!(cv, tout) == 0
            @test cv.t ≈ tout
            @test state(cv)[1] ≈ exp(-2.5tout) rtol = 1e-8
        end
        st = stats(cv)
        @test st.steps > 0 && st.rhs > st.steps
        @test (st.jac > 0) == (method == :bdf)       # only Newton builds Jacobians
        free!(cv)
    end
end

@testset "Parameters are shared, not copied" begin
    p = [1.0]
    cv = Cvode((du, u, p, t) -> (du[1] = p[1]), [0.0], p; method = :adams, rtol = 1e-12, atol = 1e-14)
    # CV_NORMAL steps past tout and interpolates back, so without a stop time
    # CVODE would already be beyond t = 1 (measured: t ≈ 1.66) on the old p.
    set_stop_time!(cv, 1.0)
    @test advance!(cv, 1.0) >= 0
    p[1] = 3.0                                       # the next step sees it
    @test advance!(cv, 2.0) == 0
    @test state(cv)[1] ≈ 1.0 + 3.0 atol = 1e-9
    free!(cv)
end

@testset "reinit!, tolerances, stop time" begin
    cv = Cvode(lorenz!, [1.0, 1.0, 1.0], defaults(system(:lorenz)); method = :adams, rtol = 1e-10, atol = 1e-12)
    advance!(cv, 3.0); a = state(cv)
    reinit!(cv, [1.0, 1.0, 1.0], 0.0)
    @test cv.t == 0.0
    advance!(cv, 3.0)
    @test state(cv) ≈ a rtol = 1e-12                   # same start, same path
    set_tolerances!(cv, 1e-6, 1e-8)
    @test (cv.rtol, cv.atol) == (1e-6, 1e-8)
    set_stop_time!(cv, 3.5)
    while true
        f = onestep!(cv, 10.0)
        f == S.CV_TSTOP_RETURN() && break
        @test f == 0
    end
    @test cv.t ≈ 3.5
    @test_throws DimensionMismatch reinit!(cv, [1.0, 2.0])
    free!(cv)
end

@testset "A right-hand side that throws" begin
    cv = Cvode((du, u, p, t) -> error("boom at t = $t"), [1.0], nothing; method = :adams, quiet = true)
    err = try
        advance!(cv, 1.0); nothing
    catch e
        e
    end
    @test err isa CapturedException
    @test occursin("boom", sprint(showerror, err))
    @test cv.rhs.err === nothing                     # handed over, not left behind
    free!(cv)
end

@testset "free! and use after free" begin
    cv = Cvode(lorenz!, [1.0, 1.0, 1.0], defaults(system(:lorenz)); method = :adams)
    free!(cv); free!(cv)                             # twice is fine
    @test cv.mem == C_NULL
    @test_throws ErrorException advance!(cv, 1.0)
    @test_throws ArgumentError Cvode(lorenz!, [1.0], [1.0]; method = :rk4)
end

@testset "The callback allocates nothing per evaluation" begin
    cv = Cvode(lorenz!, [1.0, 1.0, 1.0], defaults(system(:lorenz)); method = :adams, rtol = 1e-10, atol = 1e-12)
    advance!(cv, 0.1)                                # compile
    a1 = @allocated advance!(cv, 1.0)
    s1 = stats(cv).rhs
    a2 = @allocated advance!(cv, 20.0)
    s2 = stats(cv).rhs
    @test s2 - s1 > 1000                             # thousands of callbacks …
    @test a2 <= a1 + 64                              # … and no more allocation than a few
    free!(cv)
end

@testset "Lorenz: tolerances agree until chaos takes over" begin
    a = trajectory(:lorenz; T = 5.0, rtol = 1e-10, atol = 1e-12)
    b = trajectory(:lorenz; T = 5.0, rtol = 1e-12, atol = 1e-14)
    @test a.flag == 0 && b.flag == 0
    @test maximum(abs.(a.u[:, end] .- b.u[:, end])) < 1e-5
    s = separation(:lorenz; δ = 1e-9, T = 50.0)
    @test s.d[1] ≈ 1e-9 rtol = 1e-6                  # 1 + 1e-9 is not exact in Float64
    @test maximum(s.d) > 1                           # the two runs end up on different lobes
end

@testset "Largest Lyapunov exponent of Lorenz ≈ 0.9056" begin
    λ = lyapunov(:lorenz; T = 600.0)
    @test 0.86 < λ < 0.95
end

@testset "Robertson: reference values at t = 40" begin
    # SUNDIALS' own cvRoberts_dns example: y(40) = (0.7158270, 9.185535e-6, 0.2841639)
    r = trajectory(:robertson; T = 40.0, dt = 1.0, rtol = 1e-8, atol = 1e-14)
    @test r.flag == 0
    @test r.u[1, end] ≈ 0.7158270 rtol = 1e-5
    @test r.u[2, end] ≈ 9.185535e-6 rtol = 1e-4
    @test r.u[3, end] ≈ 0.2841639 rtol = 1e-5
end

@testset "Robertson: the race" begin
    rc = race(; maxsteps = 20_000)
    @test rc.bdf.flag == 0
    @test rc.bdf.reached ≈ 4e10
    @test rc.bdf.stats.steps < 3000
    @test maximum(rc.bdf.h) > 1e8                     # the step grew by ten orders
    @test all(abs.(sum(rc.bdf.y; dims = 1) .- 1) .< 1e-6)   # mass is conserved
    @test rc.adams.flag == S.CV_TOO_MUCH_WORK()
    @test rc.adams.reached < 1e5                      # nowhere near 4e10
    @test length(rc.adams.t) == 20_000
end

@testset "Double pendulum: energy drift follows the tolerance" begin
    tight = drift(:pendulum; T = 20.0)
    loose = drift(:pendulum; T = 20.0, rtol = 1e-6, atol = 1e-8)
    @test tight < 1e-6
    @test loose > 100 * tight
end

@testset "The window" begin
    if !haskey(ENV, "DISPLAY")
        @info "no DISPLAY: window tests skipped"
    else
        for k in (:lorenz, :rossler, :pendulum, :robertson)
            r = OdeLab.run(k; frames = 30, visible = false)
            @test r.frames == 30
            @test r.system == k
            @test r.imgui_vertices > 1000             # the panel was drawn
            if k == :robertson
                @test r.race == (bdf = 0, adams = Int(S.CV_TOO_MUCH_WORK()))
            else
                @test r.flag == 0
                @test r.points > 1
                @test r.t > 0
            end
        end
    end
end

end
