using Test
using BoxWorld
using RepliBuild

@testset "BoxWorld (app on RepliBuild wrapper)" begin

    @testset "JIT engine registered for the vendored library" begin
        engines = RepliBuild.JITManager.GLOBAL_JIT.engines
        @test length(engines) == 1
        @test engines[1].init_error === nothing
        @test occursin("libbox2d", engines[1].binary_path)
    end

    @testset "free fall matches semi-implicit Euler" begin
        w = World()
        ball = add_ball!(w, 0.0, 10.0)
        n = 60
        simulate!(w, n)
        # Box2D integrates semi-implicitly: drop after n steps is
        # g·dt²·n(n+1)/2 with g=10, dt=1/60.
        expected_y = 10.0 - 10.0 * (1 / 60)^2 * n * (n + 1) / 2
        x, y = body_position(ball)
        @test abs(x) < 1e-4
        @test isapprox(y, expected_y; atol=0.05)
        vx, vy = body_velocity(ball)
        @test vy < -5.0          # falling fast after 1 s
        destroy!(w)
    end

    @testset "balls come to rest on the ground" begin
        w = World()
        add_ground!(w; y=0.0)
        b1 = add_ball!(w, -1.0, 5.0; radius=0.5)
        b2 = add_ball!(w, 1.0, 8.0; radius=0.5)
        simulate!(w, 300)
        for b in (b1, b2)
            x, y = body_position(b)
            # rest height = ground half-thickness (0.5) + ball radius (0.5),
            # with contact-solver skin tolerance
            @test isapprox(y, 1.0; atol=0.08)
            vx, vy = body_velocity(b)
            @test abs(vy) < 0.05
        end
        destroy!(w)
    end

    @testset "stacking: second ball rests on the first" begin
        w = World()
        add_ground!(w; y=0.0)
        bottom = add_ball!(w, 0.0, 2.0; radius=0.5)
        top    = add_ball!(w, 0.0, 4.0; radius=0.5)
        simulate!(w, 400)
        yb = body_position(bottom)[2]
        yt = body_position(top)[2]
        @test isapprox(yb, 1.0; atol=0.1)
        @test yt > yb + 0.7      # sits on the bottom ball, not inside it
        destroy!(w)
    end

    @testset "lifecycle: destroy is idempotent, worlds are sequential" begin
        w1 = World()
        add_ball!(w1, 0.0, 3.0)
        simulate!(w1, 10)
        destroy!(w1)
        destroy!(w1)                       # idempotent
        @test_throws ErrorException step!(w1)

        w2 = World(; gravity=(0.0, -3.0))  # a second world after teardown
        ball = add_ball!(w2, 0.0, 5.0)
        simulate!(w2, 30)
        @test body_position(ball)[2] < 5.0
        destroy!(w2)
    end

    @testset "finalizer path survives GC" begin
        function make_and_drop()
            w = World()
            add_ball!(w, 0.0, 2.0)
            simulate!(w, 5)
            return nothing   # world goes unreachable; finalizer must clean up
        end
        make_and_drop()
        GC.gc(); GC.gc()
        @test true           # no crash, no hang
    end
end

println("✓ BoxWorld app tests passed")
