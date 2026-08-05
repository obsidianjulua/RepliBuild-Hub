#!/usr/bin/env julia
# Box2D 3.x Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
# Newtonian mechanics is the oracle: free fall, restitution, momentum and
# rotational inertia all have closed forms, so agreement is evidence about the
# wrapped solver rather than about the wrapper's opinion of it.
#   - the handle-based C17 API (b2WorldId / b2BodyId / b2ShapeId passed and
#     returned BY VALUE — the small-struct SysV ABI path)
#   - default-def structs returned by value, then mutated through `with`
#   - free fall against s = ½gt², velocity against v = gt
#   - static/dynamic/kinematic body semantics, fixed rotation, gravity scale
#   - collision: a falling box comes to rest on a static ground at the right
#     height, and restitution bounces it back proportionally
#   - mass and rotational inertia computed from density and geometry
#   - determinism: identical worlds must produce bit-identical trajectories
#   - Tier-1 liveness and churn under GC pressure
#
# NOTE: most of box2d3's surface takes or returns structs BY VALUE, which the
# Tier-1 shape gate keeps on Tier 3 — only ~27 functions slice. That asymmetry
# is expected and is asserted rather than papered over.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/box2d3/test_deep.jl

using Test
using InteractiveUtils: code_typed

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Box2d3.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const B = Box2d3

function kernel_emits_llvmcall(kernel)
    ms = collect(methods(kernel))
    isempty(ms) && error("no method for $kernel")
    argtypes = Base.tuple_type_tail(ms[1].sig)
    ct = code_typed(kernel, argtypes)
    isempty(ct) && error("code_typed empty for $kernel with $argtypes")
    return occursin("llvmcall", string(ct))
end

vec2(x, y) = B.b2Vec2(Float32(x), Float32(y))

"Create a world with the given gravity, run `f(worldId)`, always destroy."
function withworld(f; gravity = vec2(0, -10))
    wd = B.b2DefaultWorldDef()
    wd = B.with(wd; gravity = gravity)
    world = B.b2CreateWorld(Ref(wd))
    try
        return f(world)
    finally
        B.b2DestroyWorld(world)
    end
end

"Add a dynamic box of half-extents (hw,hh) at `pos`; returns its body id."
function addbox(world, pos; hw = 0.5, hh = 0.5, density = 1.0,
                type_ = B.b2_dynamicBody, restitution = 0.0, fixedRotation = false)
    bd = B.b2DefaultBodyDef()
    bd = B.with(bd; type_ = type_, position = pos, fixedRotation = fixedRotation)
    body = B.b2CreateBody(world, Ref(bd))

    sd = B.b2DefaultShapeDef()
    sd = B.with(sd; density = Float32(density),
                material = B.with(sd.material; restitution = Float32(restitution)))
    poly = B.b2MakeBox(Float32(hw), Float32(hh))
    B.b2CreatePolygonShape(body, Ref(sd), Ref(poly))
    return body
end

"Step the world `n` times at `dt`."
function stepn!(world, n; dt = 1 / 60, sub = 4)
    for _ in 1:n
        B.b2World_Step(world, Float32(dt), sub)
    end
end

@testset "Box2D 3.x Deep Tests" begin

@testset "Tier-1 surface is small here, and consistent" begin
    slices_dir = joinpath(PKG_DIR, "julia", "slices")
    lls = isdir(slices_dir) ? filter(f -> endswith(f, ".ll"), readdir(slices_dir)) : String[]
    @test length(lls) == length(B.TIER1_FUNCTIONS)
    # box2d3's API is overwhelmingly struct-by-value, which the llvmcall shape
    # gate rejects, so only a small minority slices. A LARGE number here would
    # mean the gate had stopped rejecting struct crossings.
    @test !isempty(B.TIER1_FUNCTIONS)
    @test length(lls) < 100
    for f in lls
        ir = read(joinpath(slices_dir, f), String)
        @test occursin("define", ir)
    end
end

@testset "Handle-based API: ids are values, not pointers" begin
    withworld() do world
        # b2WorldId is a 4-byte struct passed by value; a valid one has a
        # non-zero index1 (Box2D uses 1-based indices with 0 as "null").
        @test world isa B.b2WorldId
        @test world.index1 != 0

        b1 = addbox(world, vec2(0, 10))
        b2 = addbox(world, vec2(5, 10))
        @test b1 isa B.b2BodyId
        @test b1.index1 != 0
        @test b1.index1 != b2.index1        # distinct handles
        @test b1.world0 == b2.world0        # same world

        @test B.b2Body_IsValid(b1)
        @test B.b2World_IsValid(world)
    end
end

@testset "Free fall matches s = ½gt² and v = gt" begin
    g = 10.0
    dt = 1 / 60
    n = 60                                   # exactly one second

    withworld(gravity = vec2(0, -g)) do world
        # A body with no shape still falls; give it one so mass is well defined.
        body = addbox(world, vec2(0, 100))
        stepn!(world, n; dt = dt)

        p = B.b2Body_GetPosition(body)
        v = B.b2Body_GetLinearVelocity(body)

        # A semi-implicit Euler integrator lands within a step's worth of the
        # closed form, so compare with a tolerance scaled to g·dt.
        @test isapprox(v.y, -g * n * dt; atol = g * dt * 1.5)
        @test isapprox(p.y, 100 - 0.5 * g * (n * dt)^2; atol = g * dt)
        @test p.x ≈ 0.0f0 atol = 1e-4        # no horizontal drift
    end
end

@testset "Body types behave differently" begin
    withworld() do world
        dyn = addbox(world, vec2(0, 10))
        sta = addbox(world, vec2(3, 10); type_ = B.b2_staticBody)
        kin = addbox(world, vec2(6, 10); type_ = B.b2_kinematicBody)
        B.b2Body_SetLinearVelocity(kin, vec2(1, 0))

        y0_dyn = B.b2Body_GetPosition(dyn).y
        stepn!(world, 60)

        # Dynamic falls, static does not move at all, kinematic ignores gravity
        # but honours the velocity we set.
        @test B.b2Body_GetPosition(dyn).y < y0_dyn - 1
        @test B.b2Body_GetPosition(sta).y ≈ 10.0f0 atol = 1e-4
        @test B.b2Body_GetPosition(kin).y ≈ 10.0f0 atol = 1e-4
        @test B.b2Body_GetPosition(kin).x > 6.5

        @test B.b2Body_GetType(sta) == B.b2_staticBody
        @test B.b2Body_GetType(kin) == B.b2_kinematicBody
        @test B.b2Body_GetType(dyn) == B.b2_dynamicBody

        # A static body has zero mass by definition.
        @test B.b2Body_GetMass(sta) == 0.0f0
        @test B.b2Body_GetMass(dyn) > 0.0f0
    end
end

@testset "Mass and rotational inertia from density and geometry" begin
    withworld(gravity = vec2(0, 0)) do world
        # A 1×1 box (half-extents 0.5) at density 2 has mass = area × density.
        body = addbox(world, vec2(0, 0); hw = 0.5, hh = 0.5, density = 2.0)
        @test B.b2Body_GetMass(body) ≈ 2.0f0 atol = 1e-4

        # Doubling both half-extents quadruples the area, hence the mass.
        big = addbox(world, vec2(10, 0); hw = 1.0, hh = 1.0, density = 2.0)
        @test B.b2Body_GetMass(big) ≈ 8.0f0 atol = 1e-3

        # The solid-rectangle inertia about the centre is m(w²+h²)/12.
        md = B.b2Body_GetMassData(body)
        @test md.mass ≈ 2.0f0 atol = 1e-4
        want_I = 2.0 * (1.0^2 + 1.0^2) / 12
        @test md.rotationalInertia ≈ Float32(want_I) atol = 1e-3
        @test md.center.x ≈ 0.0f0 atol = 1e-5
        @test md.center.y ≈ 0.0f0 atol = 1e-5
    end
end

@testset "Momentum: an impulse produces v = J/m in zero gravity" begin
    withworld(gravity = vec2(0, 0)) do world
        body = addbox(world, vec2(0, 0); hw = 0.5, hh = 0.5, density = 1.0)
        m = B.b2Body_GetMass(body)
        @test m ≈ 1.0f0 atol = 1e-4

        B.b2Body_ApplyLinearImpulseToCenter(body, vec2(3, 4), true)
        v = B.b2Body_GetLinearVelocity(body)
        @test v.x ≈ 3.0f0 / m atol = 1e-3
        @test v.y ≈ 4.0f0 / m atol = 1e-3

        # With no gravity and no damping the velocity is conserved.
        stepn!(world, 60)
        v2 = B.b2Body_GetLinearVelocity(body)
        @test v2.x ≈ v.x atol = 1e-3
        @test v2.y ≈ v.y atol = 1e-3
        # ...and the position advanced by v·t.
        p = B.b2Body_GetPosition(body)
        @test p.x ≈ v.x * 1.0f0 atol = 0.1
        @test p.y ≈ v.y * 1.0f0 atol = 0.1
    end
end

@testset "Collision: a falling box rests on static ground" begin
    withworld() do world
        # Ground: a wide static box whose top surface sits at y = 0.
        ground = addbox(world, vec2(0, -1); hw = 20.0, hh = 1.0,
                        type_ = B.b2_staticBody)
        # Faller: half-height 0.5, dropped from y = 6. It should settle with its
        # centre at y ≈ 0.5 — the half-height above the ground surface.
        box = addbox(world, vec2(0, 6); hw = 0.5, hh = 0.5, fixedRotation = true)

        stepn!(world, 240)                  # four seconds: ample to settle

        p = B.b2Body_GetPosition(box)
        @test p.y ≈ 0.5f0 atol = 0.05
        @test abs(p.x) < 0.05
        v = B.b2Body_GetLinearVelocity(box)
        @test abs(v.y) < 0.05               # at rest, not still falling
        @test B.b2Body_GetPosition(ground).y ≈ -1.0f0 atol = 1e-4
    end
end

@testset "Restitution makes it bounce" begin
    withworld() do world
        addbox(world, vec2(0, -1); hw = 20.0, hh = 1.0, type_ = B.b2_staticBody)

        # A bouncy box must rise again after impact; a dead one must not.
        bouncy = addbox(world, vec2(0, 6); restitution = 0.8, fixedRotation = true)
        dead   = addbox(world, vec2(5, 6); restitution = 0.0, fixedRotation = true)

        # Track the peak height reached AFTER the first impact.
        peak_b, peak_d = -Inf, -Inf
        hit_b, hit_d = false, false
        for _ in 1:600
            B.b2World_Step(world, 1f0 / 60, 4)
            yb = B.b2Body_GetPosition(bouncy).y
            yd = B.b2Body_GetPosition(dead).y
            yb < 0.7 && (hit_b = true)
            yd < 0.7 && (hit_d = true)
            hit_b && (peak_b = max(peak_b, yb))
            hit_d && (peak_d = max(peak_d, yd))
        end
        @test hit_b && hit_d
        @test peak_b > 1.5                  # it clearly came back up
        @test peak_d < 0.7                  # it did not
        @test peak_b > peak_d
    end
end

@testset "Gravity scale and fixed rotation" begin
    withworld() do world
        # gravityScale = 0 makes a dynamic body float.
        bd = B.b2DefaultBodyDef()
        bd = B.with(bd; type_ = B.b2_dynamicBody, position = vec2(0, 10),
                    gravityScale = 0f0)
        floater = B.b2CreateBody(world, Ref(bd))
        sd = B.b2DefaultShapeDef()
        poly = B.b2MakeBox(0.5f0, 0.5f0)
        B.b2CreatePolygonShape(floater, Ref(sd), Ref(poly))

        stepn!(world, 120)
        @test B.b2Body_GetPosition(floater).y ≈ 10.0f0 atol = 1e-3

        # A fixed-rotation body ignores an applied torque.
        fixed = addbox(world, vec2(20, 10); fixedRotation = true)
        free  = addbox(world, vec2(30, 10); fixedRotation = false)
        B.b2Body_ApplyTorque(fixed, 50f0, true)
        B.b2Body_ApplyTorque(free, 50f0, true)
        stepn!(world, 30)
        @test B.b2Body_GetAngularVelocity(fixed) ≈ 0.0f0 atol = 1e-5
        @test abs(B.b2Body_GetAngularVelocity(free)) > 0.1
    end
end

@testset "Transforms round-trip" begin
    withworld(gravity = vec2(0, 0)) do world
        body = addbox(world, vec2(0, 0))

        # b2MakeRot / b2Rot_GetAngle are `static inline` in math_functions.h,
        # so they have no symbol and no DWARF — they are not (and cannot be)
        # wrapped. b2Rot is just (cos, sin), so build and read it directly.
        makerot(θ) = B.b2Rot(Float32(cos(θ)), Float32(sin(θ)))
        rotangle(q) = atan(q.s, q.c)

        B.b2Body_SetTransform(body, vec2(3, 4), makerot(π / 2))
        p = B.b2Body_GetPosition(body)
        @test p.x ≈ 3.0f0 atol = 1e-5
        @test p.y ≈ 4.0f0 atol = 1e-5

        # b2Transform comes back BY VALUE — the small-struct ABI path.
        tf = B.b2Body_GetTransform(body)
        @test tf.p.x ≈ 3.0f0 atol = 1e-5
        @test tf.p.y ≈ 4.0f0 atol = 1e-5
        # A 90° rotation is (cos, sin) = (0, 1).
        @test tf.q.c ≈ 0.0f0 atol = 1e-5
        @test tf.q.s ≈ 1.0f0 atol = 1e-5
        @test rotangle(tf.q) ≈ Float32(π / 2) atol = 1e-5

        # Local↔world point transforms are inverses.
        world_pt = B.b2Body_GetWorldPoint(body, vec2(1, 0))
        local_pt = B.b2Body_GetLocalPoint(body, world_pt)
        @test local_pt.x ≈ 1.0f0 atol = 1e-4
        @test local_pt.y ≈ 0.0f0 atol = 1e-4
        # Rotated 90°, the body's local +x points along world +y.
        @test world_pt.x ≈ 3.0f0 atol = 1e-4
        @test world_pt.y ≈ 5.0f0 atol = 1e-4
    end
end

@testset "Determinism: identical worlds give identical trajectories" begin
    function trajectory()
        withworld() do world
            addbox(world, vec2(0, -1); hw = 20.0, hh = 1.0, type_ = B.b2_staticBody)
            b = addbox(world, vec2(0.1, 8); restitution = 0.5)
            ys = Float32[]
            for _ in 1:300
                B.b2World_Step(world, 1f0 / 60, 4)
                push!(ys, B.b2Body_GetPosition(b).y)
            end
            return ys
        end
    end

    a = trajectory()
    b = trajectory()
    # Bit-identical, not merely close: the solver is deterministic and nothing
    # in the wrapper may introduce run-to-run variation.
    @test a == b
    @test length(a) == 300
    @test a[1] > a[end]                     # it did in fact fall
end

@testset "World and body lifecycle" begin
    # Many worlds created and destroyed in sequence; handles must not be reused
    # in a way that lets a stale id look valid.
    ids = B.b2WorldId[]
    for _ in 1:50
        w = B.b2CreateWorld(Ref(B.b2DefaultWorldDef()))
        push!(ids, w)
        @test B.b2World_IsValid(w)
        B.b2DestroyWorld(w)
        @test !B.b2World_IsValid(w)         # the generation counter invalidates it
    end
    @test true

    withworld() do world
        bodies = [addbox(world, vec2(i, 10)) for i in 1:20]
        @test all(B.b2Body_IsValid, bodies)
        @test B.b2World_GetCounters(world).bodyCount == 20
        for b in bodies[1:10]
            B.b2DestroyBody(b)
        end
        @test B.b2World_GetCounters(world).bodyCount == 10
        @test all(!B.b2Body_IsValid, bodies[1:10])
        @test all(B.b2Body_IsValid, bodies[11:20])
        stepn!(world, 30)                   # still steps fine after deletions
        @test B.b2World_GetCounters(world).bodyCount == 10
    end
end

@testset "Churn and GC stress" begin
    # Build/simulate/tear down many worlds with Julia GC interleaved. Every id
    # here crosses the ABI by value, so a mis-marshalled small struct shows up
    # as a wrong handle and an immediate failure rather than as drift.
    for i in 1:100
        withworld() do world
            addbox(world, vec2(0, -1); hw = 20.0, hh = 1.0, type_ = B.b2_staticBody)
            b = addbox(world, vec2(0, 5 + (i % 5)))
            stepn!(world, 60)
            y = B.b2Body_GetPosition(b).y
            @assert y < 5 + (i % 5) "body did not fall (i=$i, y=$y)"
            @assert B.b2Body_IsValid(b)
        end
        iszero(i % 25) && GC.gc()
    end
    @test true

    # A single long-running world with many bodies and many steps.
    withworld() do world
        addbox(world, vec2(0, -1); hw = 50.0, hh = 1.0, type_ = B.b2_staticBody)
        bodies = [addbox(world, vec2(i * 1.5 - 15, 3 + i * 0.7)) for i in 1:20]
        for s in 1:600
            B.b2World_Step(world, 1f0 / 60, 4)
            iszero(s % 200) && GC.gc()
        end
        # Everything settled at or above the ground surface, nothing tunnelled.
        for b in bodies
            y = B.b2Body_GetPosition(b).y
            @test y > -1.0
            @test isfinite(y)
        end
    end
end

end  # top-level testset
