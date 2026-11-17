# ObjectSim tests. Everything but the last testset runs headless; that one opens
# a window for 30 frames when a display is present (set OBJECTSIM_NO_WINDOW=1
# to skip it).
#
#   julia --project=examples/ObjectSim -e 'using Pkg; Pkg.test()'
#
# Every world is made with the default backend: Jolt, or bullet3 with
# OBJECTSIM_BACKEND=bullet3. The few checks that read an engine's own internals
# run only on that engine (BULLET).

using Test
using ObjectSim
using ObjectSim: box_mesh, sphere_mesh, capsule_mesh, cylinder_mesh, cone_mesh,
                 render_arrays, transform_mesh, rotation_matrix, vadd, vsub, vnorm, vscale, _rotate

const ROOT = dirname(@__DIR__)
const BULLET = ObjectSim.DEFAULT_BACKEND[] == "bullet3"
@info "ObjectSim tests on the $(ObjectSim.DEFAULT_BACKEND[]) backend"
asset(f) = joinpath(ROOT, "assets", f)
scene(f) = joinpath(ROOT, "scenes", f)
≈₃(a, b; atol = 1e-4) = all(isapprox.(a, b; atol))

# A scene from inline TOML, assets resolving against assets/.
toml(s) = parse_scene(ObjectSim.TOML.parse(s); dir = joinpath(ROOT, "assets"), name = "t")
floor_toml = """
[[object]]
name = "floor"
shape = "box"
size = [20, 1, 20]
position = [0, -0.5, 0]
mass = 0
"""

@testset "ObjectSim" begin

@testset "geometry" begin
    b = box_mesh((0.5f0, 1f0, 1.5f0))
    @test length(b.faces) == 12
    @test aabb(b) == ((-0.5f0, -1f0, -1.5f0), (0.5f0, 1f0, 1.5f0))
    @test centroid(transform_mesh(b; offset = (3, 4, 5))) ≈₃ (3, 4, 5)
    # Closed primitives: centroid at the origin (the cone's is not: a solid
    # cone's centre of mass is a quarter of the way up from the base).
    for m in (sphere_mesh(0.7), capsule_mesh(0.3, 0.5), cylinder_mesh(0.4, 0.6))
        @test centroid(m) ≈₃ (0, 0, 0) atol = 1e-3
    end
    @test centroid(cone_mesh(0.5, 2.0))[2] ≈ -1 + 0.5 atol = 1e-2
    # Outward winding: positive enclosed volume means the centroid formula and
    # face normals agree.
    for m in (b, sphere_mesh(1), capsule_mesh(0.3, 0.5), cylinder_mesh(1, 1), cone_mesh(1, 1))
        vol = sum(f -> ObjectSim.vdot(m.vertices[f[1]], ObjectSim.vcross(m.vertices[f[2]], m.vertices[f[3]])), m.faces) / 6
        @test vol > 0
    end
    @test sum(f -> ObjectSim.vdot(sphere_mesh(1).vertices[f[1]], ObjectSim.vcross(sphere_mesh(1).vertices[f[2]], sphere_mesh(1).vertices[f[3]])), sphere_mesh(1).faces) / 6 ≈ 4π / 3 rtol = 0.03
    pos, nrm = render_arrays(b)
    @test length(pos) == length(nrm) == 9 * 12
    # Mirroring flips winding so the volume stays positive.
    mir = transform_mesh(b; scale = (-1, 1, 1))
    @test sum(f -> ObjectSim.vdot(mir.vertices[f[1]], ObjectSim.vcross(mir.vertices[f[2]], mir.vertices[f[3]])), mir.faces) > 0
end

@testset "asset loading" begin
    ramp = load_mesh(asset("ramp.obj"))
    @test length(ramp.vertices) == 6
    @test length(ramp.faces) == 3 * 2 + 2           # three quads, two triangles
    stl = load_mesh(asset("ramp.stl"))               # binary, welded back to 6 vertices
    @test length(stl.vertices) == 6 && length(stl.faces) == 8
    @test aabb(stl) == aabb(ramp)
    rock = load_mesh(asset("rock.obj"))
    @test length(rock.vertices) == 42 && length(rock.faces) == 80

    mktempdir() do d
        # v/vt/vn tokens, negative indices, comments, a quad
        p = joinpath(d, "q.obj")
        write(p, "# quad\nv 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nvt 0 0\nf -4/1/1 -3/1/1 -2//1 -1\n")
        q = load_mesh(p)
        @test q.faces == [(1, 2, 3), (1, 3, 4)]
        write(p, "v 0 0 0\nf 1 2 3\n")
        @test_throws ErrorException load_mesh(p)
        s = joinpath(d, "t.stl")
        write(s, """solid t
          facet normal 0 0 1
            outer loop
              vertex 0 0 0
              vertex 1 0 0
              vertex 0 1 0
            endloop
          endfacet
        endsolid t
        """)
        @test length(load_mesh(s).faces) == 1
        @test_throws ErrorException load_mesh(joinpath(d, "x.ply"))
        # save → load round trip
        save_obj(joinpath(d, "r.obj"), rock)
        r2 = load_mesh(joinpath(d, "r.obj"))
        @test r2.faces == rock.faces
        @test all(≈₃(a, b) for (a, b) in zip(r2.vertices, rock.vertices))
    end
end

@testset "scene files" begin
    s = load_scene(scene("tumble.toml"))
    @test length(s.objects) == 48
    @test count(o -> o.mass == 0, s.objects) == 3
    @test count(o -> startswith(o.name, "crate["), s.objects) == 15
    @test s.objects[1].color == (0x3a, 0x3f, 0x4b)
    @test s.camera.distance == 22
    @test isfile(only(o.asset for o in s.objects if o.name == "bowl"))

    bad(str) = @test_throws ErrorException toml(str)
    bad("[[object]]\nshape = \"box\"\nsizee = [1,1,1]\n")              # typo'd key
    bad("[[object]]\nshape = \"blob\"\n")                               # unknown shape
    bad("[[object]]\nshape = \"mesh\"\nasset = \"bowl.obj\"\nmass = 2\n")  # moving mesh
    bad("[[object]]\nshape = \"hull\"\nasset = \"nope.obj\"\n")         # missing asset
    bad("[[object]]\nshape = \"capsule\"\nradius = 1\nheight = 1\n")    # too short
    bad("[[object]]\nshape = \"box\"\ncolor = \"red\"\n")
    bad("[world]\nhz = 0\n")
    r = toml("[[object]]\nshape = \"box\"\nposition = [1, 0, 0]\nrepeat = [2, 3, 1]\n")
    @test length(r.objects) == 6
    @test r.objects[end].position == (2f0, 2f0, 0f0)        # default spacing = size
end

@testset "free fall matches the integrator" begin
    with_world(toml("""
        [world]
        hz = 60
        [[object]]
        name = "box"
        shape = "box"
        position = [0, 10, 0]
        """)) do w
        b = body(w, "box")
        step!(w, 30)
        dt = 1 / 60; n = 30; g = 9.81
        # bullet3 integrates semi-implicit Euler: y = y0 - g·dt²·n(n+1)/2
        @test position(b)[2] ≈ 10 - g * dt^2 * n * (n + 1) / 2 atol = 1e-3
        @test velocity(b)[2] ≈ -g * dt * n atol = 1e-3
        @test sim_time(w) ≈ 0.5 atol = 1e-6       # the step is 1/60 rounded to Float32
    end
end

@testset "primitives come to rest at their size" begin
    for (shape, extra, rest_y) in (("box", "size = [1, 2, 1]", 1.0),
                                   ("sphere", "radius = 0.4\nrolling_friction = 0.1", 0.4),
                                   ("capsule", "radius = 0.3\nheight = 2.0", 1.0),
                                   ("cylinder", "radius = 0.5\nheight = 1.2", 0.6),
                                   ("cone", "radius = 0.5\nheight = 1.0", 0.5))
        with_world(toml(floor_toml * """
            [[object]]
            name = "it"
            shape = "$shape"
            $extra
            position = [0, 3, 0]
            """)) do w
            simulate!(w, 4)
            b = body(w, "it")
            # Collision margins (0.04 m) may lift convex shapes slightly;
            # Jolt lets resting contacts sink by its penetration slop (0.02 m).
            sink = BULLET ? 0.01 : 0.025
            @test rest_y - sink < position(b)[2] < rest_y + 0.06
            @test vnorm(velocity(b)) < 0.05
            @test position(body(w, "floor")) == (0f0, -0.5f0, 0f0)   # static never moves
        end
    end
end

@testset "mesh assets: hull and static triangle mesh" begin
    # Hull: `position` places the asset's own origin; the body sits at the
    # centre of mass, offset from it by the (scaled, rotated) centroid.
    with_world(toml("""
        [world]
        gravity = [0, 0, 0]
        [[object]]
        name = "rock"
        shape = "hull"
        asset = "rock.obj"
        scale = 2
        position = [1, 2, 3]
        rotation = [0, 0, 90]
        """)) do w
        b = body(w, "rock")
        c = centroid(transform_mesh(load_mesh(asset("rock.obj")); scale = (2, 2, 2)))
        @test position(b) ≈₃ vadd((1f0, 2f0, 3f0), _rotate(rotation_matrix((0, 0, 90)), c)) atol = 1e-5
        @test centroid(b.mesh) ≈₃ (0, 0, 0) atol = 1e-4
    end
    # Dropped rock settles with its lowest point on the floor.
    with_world(toml(floor_toml * """
        [[object]]
        name = "rock"
        shape = "hull"
        asset = "rock.obj"
        position = [0, 2, 0]
        rotation = [20, 0, 35]
        rolling_friction = 0.1
        """)) do w
        simulate!(w, 5)
        b = body(w, "rock")
        rows, o = transform(b)
        low = minimum(vadd(o, _rotate(rows, v))[2] for v in b.mesh.vertices)
        @test -0.01 < low < 0.06
        @test vnorm(velocity(b)) < 0.05
    end
    # Concave static mesh: a ball dropped off-centre into the bowl ends up
    # near the bottom (the bowl's lowest point is its centre, y = 0).
    with_world(toml(floor_toml * """
        [[object]]
        name = "bowl"
        shape = "mesh"
        asset = "bowl.obj"
        [[object]]
        name = "ball"
        shape = "sphere"
        radius = 0.3
        position = [2.0, 3, 1.0]
        rolling_friction = 0.1
        """)) do w
        b = body(w, "ball")
        simulate!(w, 12)
        p = position(b)
        if BULLET                                   # rolling friction stops it at the bottom
            @test vnorm(velocity(b)) < 0.05
            @test hypot(p[1], p[3]) < 0.5
            @test 0.25 < p[2] < 0.45
        else                                        # Jolt has no rolling friction: still rolling, inside the bowl
            @test hypot(p[1], p[3]) < 2.5 && 0.25 < p[2] < 2.0
        end
        @test isstatic(body(w, "bowl")) && (!BULLET || length(body(w, "bowl").h.keep) == 2)   # buffers held (bullet3)
    end
end

BULLET && @testset "header-only constructors (bullet3 shims)" begin
    with_world(toml(floor_toml * """
        [world]
        hz = 60
        [[object]]
        name = "ball"
        shape = "sphere"
        radius = 0.5
        position = [0, 5, 0]
        friction = 0.9
        restitution = 0.25
        damping = [0.1, 0.2]
        """)) do w
        b = body(w, "ball")
        B = ObjectSim.B
        @test b.h.shape_class == :btSphereShape
        @test B.btSphereShape_getName(b.h.shape) == "SPHERE"
        @test b.h.motion != C_NULL && body(w, "floor").h.motion == C_NULL
        # The construction info came from the real constructor, with the
        # scene's values over upstream's defaults.
        off(f) = B.member_offset(:btCollisionObject, f)
        @test unsafe_load(Ptr{Float32}(b.h.ptr + off(:m_friction))) == 0.9f0
        @test unsafe_load(Ptr{Float32}(b.h.ptr + off(:m_restitution))) == 0.25f0
        @test unsafe_load(Ptr{Float32}(b.h.ptr + B.member_offset(:btRigidBody, :m_linearDamping))) == 0.1f0
        # The body started where the motion state said.
        @test position(b) == (0f0, 5f0, 0f0) == render_transform(b)[2]

        # bullet3's latency interpolation (btDiscreteDynamicsWorld's default):
        # the drawn pose is at (last step − dt + leftover), between the
        # previous fixed step and the current one. After whole steps the
        # leftover is 0, so it is the previous step's pose.
        step!(w, 10)
        y_prev = position(b)[2]
        step!(w, 1)
        @test render_transform(b)[2][2] ≈ y_prev atol = 2e-4
        @test render_transform(b)[2][2] > position(b)[2]       # falling: behind is higher

        # A variable timestep of 1.5 steps: one fixed step runs and half a step
        # is left over, so the drawn pose is half a step behind the body.
        y_prev = position(b)[2]
        before = w.steps
        @test advance!(w, 1.5 * w.dt) == 1
        @test w.steps == before + 1
        drawn, now = render_transform(b)[2][2], position(b)[2]
        @test now < drawn < y_prev
        @test drawn ≈ (y_prev + now) / 2 atol = 2e-3
        # The leftover half step completes on the next call.
        @test advance!(w, 0.5 * w.dt) == 1
        @test render_transform(b)[2][2] ≈ now atol = 2e-4

        simulate!(w, 6)
        @test 0.49 < position(b)[2] < 0.53          # a true sphere rests at its radius
    end
end

@testset "initial velocity and spin" begin
    with_world(toml("""
        [world]
        gravity = [0, 0, 0]
        [[object]]
        name = "b"
        shape = "sphere"
        velocity = [1.5, 0, -2]
        spin = [0, 3, 0]
        """)) do w
        b = body(w, "b")
        simulate!(w, 2)
        @test position(b) ≈₃ (3, 0, -4) atol = 1e-3
        @test spin(b) ≈₃ (0, 3, 0) atol = 1e-4
    end
end

@testset "determinism and teardown" begin
    run() = with_world(scene("tumble.toml")) do w
        simulate!(w, 2); snapshot(w)
    end
    a, b = run(), run()
    @test [s.position for s in a] == [s.position for s in b]
    w = World(scene("tumble.toml"))
    step!(w, 10)
    destroy!(w); destroy!(w)                       # idempotent
    @test !w.alive && isempty(w.bodies)
    @test_throws ErrorException step!(w)
    snap = run_headless(scene("tumble.toml"); seconds = 1, io = devnull)
    @test length(snap) == 45
end

@testset "pushing bodies: velocity, impulses, gravity, blasts" begin
    zero_g = "[world]\ngravity = [0, 0, 0]\n"
    with_world(toml(zero_g * """
        [[object]]
        name = "b"
        shape = "box"
        mass = 2
        """)) do w
        b = body(w, "b")
        set_velocity!(b, (1, 0, 0); spin = (0, 0.5, 0))
        @test velocity(b) == (1f0, 0f0, 0f0) && spin(b) == (0f0, 0.5f0, 0f0)
        # Central impulse: Δv = J / m, no spin change.
        apply_impulse!(b, (0, 4, 0))
        @test velocity(b) ≈₃ (1, 2, 0)
        @test spin(b) ≈₃ (0, 0.5, 0)
        # Off-centre impulse: Δω = I⁻¹ (r × J). A 1 m cube of 2 kg has
        # I = m/6 = 1/3 on each axis; J = (0, 0, 3) at r = (0.5, 0, 0) gives
        # torque (0, -1.5, 0), so Δω = (0, -4.5, 0).
        apply_impulse!(b, (0, 0, 3); at = vadd(position(b), (0.5f0, 0f0, 0f0)))
        @test velocity(b) ≈₃ (1, 2, 1.5)
        @test spin(b) ≈₃ (0, 0.5 - 4.5, 0) atol = 1e-4
        @test mass(b) == 2
    end
    with_world(toml("""
        [[object]]
        name = "b"
        shape = "sphere"
        position = [0, 50, 0]
        """)) do w
        set_gravity!(w, (0, 0, 0))
        simulate!(w, 1)
        @test position(body(w, "b")) ≈₃ (0, 50, 0)
        set_gravity!(w, (2, 0, 0))                      # sideways gravity
        simulate!(w, 1)
        @test velocity(body(w, "b"))[1] ≈ 2 atol = 1e-3
        @test velocity(body(w, "b"))[2] ≈ 0 atol = 1e-5
    end
    with_world(toml(zero_g * """
        [[object]]
        name = "near"
        shape = "sphere"
        position = [1, 0, 0]
        [[object]]
        name = "far"
        shape = "sphere"
        position = [10, 0, 0]
        """)) do w
        @test explode!(w, (0, 0, 0); radius = 4, speed = 8) == 1
        v = velocity(body(w, "near"))
        @test v[1] > 0 && v[2] > 0                       # outward and up
        @test vnorm(v) ≈ 8 * (1 - 1 / 4) rtol = 1e-4     # falls off linearly with distance
        @test velocity(body(w, "far")) == (0f0, 0f0, 0f0)
    end
end

@testset "raycasts" begin
    with_world(toml(floor_toml * """
        [[object]]
        name = "crate"
        shape = "box"
        position = [3, 0.5, 0]
        mass = 0
        """)) do w
        h = raycast(w, (3, 10, 0), (3, -10, 0))
        @test h.body.name == "crate"
        @test h.point ≈₃ (3, 1, 0) atol = 1e-4
        @test h.normal ≈₃ (0, 1, 0) atol = 1e-4
        @test h.fraction ≈ 9 / 20 atol = 1e-4
        h = raycast(w, (0, 10, 0), (0, -10, 0))
        @test h.body.name == "floor" && isapprox(h.point[2], 0; atol = 1e-4)
        @test raycast(w, (0, 10, 0), (0, 20, 0)) === nothing     # pointing at the sky
    end
end

@testset "spawning and removing at run time" begin
    with_world(toml(floor_toml)) do w
        s = ObjectSpec(; name = "box", shape = :box, position = (0f0, 3f0, 0f0))
        a = spawn!(w, s); b = spawn!(w, s)
        @test (a.name, b.name) == ("box#1", "box#2")
        simulate!(w, 2)
        @test isapprox(position(a)[2], 0.5; atol = 0.05) || isapprox(position(b)[2], 0.5; atol = 0.05)
        n = length(w.bodies)
        remove!(w, a)
        @test length(w.bodies) == n - 1 && !isalive(a)
        @test raycast(w, (0, 10, 0), (0, -10, 0)).body !== a
        @test_throws ErrorException remove!(w, a)
        simulate!(w, 1)                                  # the world carries on
    end
end

@testset "picking: carry a body with the mouse" begin
    with_world(toml(floor_toml * """
        [[object]]
        name = "crate"
        shape = "box"
        position = [0, 0.5, 0]
        """)) do w
        b = body(w, "crate")
        simulate!(w, 0.5)
        @test sleeping(b) || vnorm(velocity(b)) < 0.01
        # Look straight down at it from 5 m up.
        p = grab!(w, (0, 5, 0), (0, -1, 0))
        @test p !== nothing && p.body === b
        @test p.distance ≈ 4 atol = 1e-3                 # from the eye to the top face
        # Raise the hand 2 m: the crate follows and is held there.
        drag!(w, (0, 7, 0), (0, -1, 0))
        simulate!(w, 2)
        @test position(b)[2] ≈ 2.5 atol = 0.15
        @test !sleeping(b)
        release!(w)
        @test w.pick === nothing
        simulate!(w, 2)
        @test position(b)[2] ≈ 0.5 atol = 0.05           # dropped back onto the floor
        @test grab!(w, (0, 5, 0), (1, 0, 0)) === nothing # aiming at nothing
        @test grab!(w, (5, 5, 5), (0, -1, 0)) === nothing  # the floor is static: no grab
    end
end

@testset "joints" begin
    # Point joint = pendulum. A sphere of radius r on a massless rod of length L
    # (pivot to centre) is a physical pendulum: T₀ = 2π√((L² + ⅖r²)/(gL)),
    # and a 10° swing is slower by (1 + θ²/16). At bullet3's default 10 solver
    # passes the period comes out ~1% long for a swing along X (0.1% along Z:
    # the solver takes the joint's axes in order); 50 passes converge on it.
    L, r, θ = 1.5, 0.1, deg2rad(10)
    with_world(toml("""
        [world]
        hz = 240
        iterations = 50
        [[object]]
        name = "bob"
        shape = "sphere"
        radius = $r
        position = [$(L * sin(θ)), $(5 - L * cos(θ)), 0]
        sleep = false
        [[joint]]
        type = "point"
        a = "bob"
        pivot = [0, 5, 0]
        """)) do w
        b = body(w, "bob")
        T = 2π * sqrt((L^2 + 0.4r^2) / (9.81L)) * (1 + θ^2 / 16)
        crossings = Float64[]; last = position(b)[1]
        while length(crossings) < 9 && sim_time(w) < 30
            step!(w, 1)
            x = position(b)[1]
            sign(x) != sign(last) && push!(crossings, sim_time(w)); last = x
        end
        measured = 2 * (crossings[end] - crossings[1]) / (length(crossings) - 1)
        @test measured ≈ T rtol = 0.002
        # The rod keeps its length.
        @test vnorm(vsub(position(b), (0f0, 5f0, 0f0))) ≈ L atol = 2e-3
        # Carrying it doesn't undo `sleep = false`.
        grab!(w, (position(b)[1], 10, 0), (0, -1, 0)); release!(w)
        simulate!(w, 6)
        @test !sleeping(b)
    end
    # Without `sleep = false`, bullet3 freezes the same slow pendulum mid-swing:
    # it never goes faster than 0.8 m/s or turns faster than 1 rad/s. (Jolt's
    # sleep test is on points moving under 0.03 m/s: it keeps swinging.)
    BULLET && with_world(toml("""
        [[object]]
        name = "bob"
        shape = "sphere"
        radius = $r
        position = [$(L * sin(θ)), $(5 - L * cos(θ)), 0]
        [[joint]]
        type = "point"
        a = "bob"
        pivot = [0, 5, 0]
        """)) do w
        simulate!(w, 6)
        @test sleeping(body(w, "bob"))
        @test abs(position(body(w, "bob"))[1]) > 0.01      # stopped off-centre
    end

    # Hinge with a motor turns at its speed, then stops at its limit.
    with_world(toml("""
        [[object]]
        name = "door"
        shape = "box"
        size = [1, 2, 0.1]
        position = [0.5, 1, 0]
        [[joint]]
        name = "h"
        type = "hinge"
        a = "door"
        pivot = [0, 1, 0]
        axis = [0, 1, 0]
        limit = [-45, 45]
        motor = [30, 10]
        """)) do w
        h = joint(w, "h")
        angle() = (R = transform(body(w, "door"))[1]; rad2deg(atan(R[3][1], R[1][1])))   # turn about y
        simulate!(w, 1)
        @test abs(angle()) ≈ 30 atol = 0.5
        simulate!(w, 3)
        @test abs(angle()) ≈ 45 atol = 1
        @test position(body(w, "door"))[2] ≈ 1 atol = 1e-3       # gravity can't drop it off the hinge
        @test !broken(h)
    end

    # Slider: gravity can't pull it off its rail, a push moves it along, the
    # limit stops it.
    with_world(toml("""
        [[object]]
        name = "car"
        shape = "box"
        size = [0.5, 0.5, 0.5]
        position = [0, 2, 0]
        [[joint]]
        type = "slider"
        a = "car"
        pivot = [0, 2, 0]
        axis = [1, 0, 0]
        limit = [-1, 1]
        """)) do w
        c = body(w, "car")
        simulate!(w, 1)
        @test position(c) ≈₃ (0, 2, 0) atol = 1e-3
        # Frictionless, so it bounces between the limits (they have bullet3's
        # default 0.7 restitution): check how far it gets, not where it is.
        set_velocity!(c, (3, 0, 0))
        reach = 0f0; off_rail = 0f0
        for _ in 1:240
            step!(w, 1)
            reach = max(reach, abs(position(c)[1]))
            off_rail = max(off_rail, abs(position(c)[2] - 2), abs(position(c)[3]))
        end
        @test 0.97 < reach < 1.03
        @test off_rail < 1e-3
    end

    # Fixed: two boxes glued side by side fall and land as one.
    with_world(toml(floor_toml * """
        [[object]]
        name = "l"
        shape = "box"
        position = [-0.5, 3, 0]
        rotation = [0, 0, 20]
        [[object]]
        name = "r"
        shape = "box"
        position = [0.5, 3.36397, 0]
        rotation = [0, 0, 20]
        [[joint]]
        type = "fixed"
        a = "l"
        b = "r"
        pivot = [0, 3.18, 0]
        """)) do w
        d0 = vnorm(vsub(position(body(w, "r")), position(body(w, "l"))))
        simulate!(w, 4)
        @test vnorm(vsub(position(body(w, "r")), position(body(w, "l")))) ≈ d0 atol = 0.01
        @test transform(body(w, "l"))[1] == transform(body(w, "l"))[1]    # finite
        R1, R2 = transform(body(w, "l"))[1], transform(body(w, "r"))[1]
        @test all(≈₃(a, b; atol = 0.01) for (a, b) in zip(R1, R2))         # same orientation
    end

    # Spring: a hanging box settles m·g/k below its starting point. (This used
    # to come out 2.5-8% low: the box fell asleep before its bounces died out.)
    with_world(toml("""
        [world]
        hz = 240
        [[object]]
        name = "box"
        shape = "box"
        size = [0.4, 0.4, 0.4]
        mass = 2
        position = [0, 3, 0]
        [[joint]]
        type = "spring"
        a = "box"
        pivot = [0, 4, 0]
        stiffness = 100
        damping = 5
        """)) do w
        simulate!(w, 15)
        sag = 3 - position(body(w, "box"))[2]
        @test sag ≈ 2 * 9.81 / 100 rtol = 0.001
        @test abs(velocity(body(w, "box"))[2]) < 0.01            # settled
    end

    # break_impulse: a joint that must hold more than its limit snaps.
    with_world(toml("""
        [[object]]
        name = "heavy"
        shape = "box"
        mass = 50
        position = [0, 3, 0]
        [[joint]]
        name = "weak"
        type = "point"
        a = "heavy"
        pivot = [0, 3.5, 0]
        break_impulse = 0.5
        [[object]]
        name = "light"
        shape = "box"
        mass = 0.1
        position = [3, 3, 0]
        [[joint]]
        name = "strong"
        type = "point"
        a = "light"
        pivot = [3, 3.5, 0]
        break_impulse = 0.5
        """)) do w
        simulate!(w, 1)
        @test broken(joint(w, "weak"))          # 50 kg · g per step is far over 0.5 N·s
        @test !broken(joint(w, "strong"))
        @test position(body(w, "heavy"))[2] < 0
        @test position(body(w, "light"))[2] ≈ 3 atol = 0.01
    end
end

@testset "scene joints, chains and line repeats" begin
    s = toml("""
        [[object]]
        name = "link"
        shape = "box"
        size = [0.5, 0.1, 0.1]
        position = [0, 5, 0]
        repeat = 4
        step = [0.5, -0.5, 0]
        [[joint]]
        name = "c"
        type = "point"
        chain = "link"
        ends = "both"
        """)
    @test [o.position for o in s.objects] == [(0f0, 5f0, 0f0), (0.5f0, 4.5f0, 0f0), (1f0, 4f0, 0f0), (1.5f0, 3.5f0, 0f0)]
    @test [j.name for j in s.joints] == ["c[start]", "c[1]", "c[2]", "c[3]", "c[end]"]
    @test s.joints[1].pivot == (-0.25f0, 5.25f0, 0f0) && s.joints[1].b == ""
    @test s.joints[2].pivot == (0.25f0, 4.75f0, 0f0) && (s.joints[2].a, s.joints[2].b) == ("link[1]", "link[2]")
    @test s.joints[end].pivot == (1.75f0, 3.25f0, 0f0)
    @test toml("[world]\niterations = 40\n").world.iterations == 40
    with_world(toml("[world]\niterations = 40\n")) do w
        @test solver_iterations(w) == 40
        if BULLET
            info = Ptr{Cvoid}(ObjectSim.B.btDynamicsWorld_getSolverInfo(w.phys.world))
            @test unsafe_load(Ptr{Int32}(info + ObjectSim._OFF_NUM_ITERS)) == 40
        end
    end
    two = "[[object]]\nname = \"a\"\nshape = \"box\"\n[[object]]\nname = \"b\"\nshape = \"box\"\nposition = [2, 0, 0]\n"
    bad(str) = @test_throws ErrorException toml(str)
    bad(two * "[[joint]]\ntype = \"rope\"\na = \"a\"\npivot = [0, 0, 0]\n")             # unknown type
    bad(two * "[[joint]]\ntype = \"point\"\na = \"zz\"\npivot = [0, 0, 0]\n")           # unknown body
    bad(two * "[[joint]]\ntype = \"point\"\na = \"a\"\n")                                # no pivot
    bad(two * "[[joint]]\ntype = \"hinge\"\na = \"a\"\npivot = [0, 0, 0]\n")             # hinge without axis
    bad(two * "[[joint]]\ntype = \"fixed\"\na = \"a\"\npivot = [0, 0, 0]\n")             # fixed to nothing
    bad(two * "[[joint]]\ntype = \"point\"\na = \"a\"\npivot = [0, 0, 0]\nmotor = [1, 1]\n")  # motor on a point
    bad(two * "[[joint]]\ntype = \"point\"\nchain = \"nope\"\n")                        # empty chain
    bad("[[object]]\nshape = \"box\"\nrepeat = 3\n")                                    # line repeat without step
    bad("[[object]]\nshape = \"box\"\nrepeat = [2, 1, 1]\nstep = [1, 0, 0]\n")          # grid repeat with step
    bad("[[object]]\nname = \"x\"\nshape = \"box\"\n[[object]]\nname = \"x\"\nshape = \"box\"\n")   # duplicate name
    @test toml("[[object]]\nshape = \"box\"\nglow = 1\n").objects[1].glow == 1f0
    @test toml("[[object]]\nshape = \"box\"\nglow = 7\n").objects[1].glow == 1f0     # clamped to 0-1
    @test toml("[[object]]\nshape = \"box\"\n").objects[1].glow == 0f0
    lt = toml("[lighting]\nsun = 0.2\nambient = 0.4\nsky = \"#000010\"\n[[object]]\nshape = \"sphere\"\nlight = 6\nlight_intensity = 2\n")
    @test (lt.camera.sun, lt.camera.ambient, lt.camera.sky) == (0.2f0, 0.4f0, (0x00, 0x00, 0x10))
    @test (lt.objects[1].light, lt.objects[1].light_intensity) == (6f0, 2f0)
    @test toml("[[object]]\nshape = \"box\"\n").objects[1].light == 0f0           # no light by default
    bad("[lighting]\nmoon = 1\n")
end

@testset "every scene loads and runs" begin
    for f in sort(filter(endswith(".toml"), readdir(joinpath(ROOT, "scenes"))))
        with_world(scene(f)) do w
            simulate!(w, 2)
            @test all(b -> all(isfinite, position(b)), w.bodies)
        end
    end
    with_world(scene("wrecking_ball.toml")) do w
        far = 0f0
        for _ in 1:300
            step!(w, 4)
            far = max(far, vnorm(vsub(position(body(w, "ball")), (0f0, 10f0, 0f0))))
        end
        @test far < 6.7 + 0.05                  # the chain does not stretch
    end
end

@testset "per-object gravity, layers, triggers, contacts" begin
    with_world(toml(floor_toml * """
        [[object]]
        name = "moon"
        shape = "sphere"
        position = [0, 20, 0]
        gravity = [0, -1.62, 0]
        [[object]]
        name = "earth"
        shape = "sphere"
        position = [3, 20, 0]
        [[object]]
        name = "balloon"
        shape = "sphere"
        mass = 0.2
        position = [6, 1, 0]
        gravity = [0, 2, 0]
        """)) do w
        m, e, bl = body(w, "moon"), body(w, "earth"), body(w, "balloon")
        @test body_gravity(m) ≈₃ (0, -1.62, 0)
        @test body_gravity(e) ≈₃ (0, -9.81, 0)
        simulate!(w, 1)
        @test 20 - position(m)[2] ≈ 0.5 * 1.62 rtol = 0.02
        @test 20 - position(e)[2] ≈ 0.5 * 9.81 rtol = 0.02
        @test position(bl)[2] > 1.9
        # The world's gravity changing leaves the moon's alone …
        set_gravity!(w, (0, 0, 0))
        @test body_gravity(m) ≈₃ (0, -1.62, 0)
        @test body_gravity(e) ≈₃ (0, 0, 0)
        # … until it is handed back.
        set_body_gravity!(w, m, nothing)
        @test body_gravity(m) ≈₃ (0, 0, 0)
    end

    with_world(toml(floor_toml * """
        [[object]]
        name = "g1"
        shape = "box"
        position = [0, 0.5, 0]
        layer = "ghost"
        ignore = ["ghost"]
        [[object]]
        name = "g2"
        shape = "box"
        position = [0.2, 3, 0]
        layer = "ghost"
        ignore = ["ghost"]
        [[object]]
        name = "solid"
        shape = "box"
        position = [3, 0.5, 0]
        [[object]]
        name = "onto_solid"
        shape = "box"
        position = [3.1, 3, 0]
        """)) do w
        simulate!(w, 3)
        # Ghosts pass through each other and both rest on the floor …
        @test position(body(w, "g2"))[2] ≈ 0.5 atol = 0.03
        @test position(body(w, "g1"))[2] ≈ 0.5 atol = 0.03
        # … ordinary boxes stack.
        @test position(body(w, "onto_solid"))[2] ≈ 1.5 atol = 0.05
        @test !touching(w, body(w, "g1"), body(w, "g2"))
        # bullet3 keeps the manifolds of sleeping bodies; Jolt reports contacts
        # of awake bodies only, and these are asleep by now.
        BULLET && @test touching(w, body(w, "g1"), body(w, "floor"))
    end

    with_world(toml(floor_toml * """
        [[object]]
        name = "zone"
        shape = "box"
        size = [2, 2, 2]
        position = [0, 3, 0]
        mass = 0
        trigger = true
        [[object]]
        name = "ball"
        shape = "sphere"
        radius = 0.3
        position = [0, 6, 0]
        """)) do w
        zone, ball = body(w, "zone"), body(w, "ball")
        @test istrigger(zone) && !istrigger(ball)
        seen = false
        for _ in 1:240
            step!(w, 1)
            seen |= touching(w, ball, zone)
        end
        @test seen                                   # reported while passing through …
        @test position(ball)[2] ≈ 0.3 atol = 0.03    # … and it fell right through to the floor
    end

    # A resting box: contacts with the floor, pointing up, carrying its weight.
    with_world(toml(floor_toml * """
        [world]
        hz = 120
        [[object]]
        name = "box"
        shape = "box"
        mass = 3
        position = [0, 0.5, 0]
        """)) do w
        simulate!(w, BULLET ? 1 : 0.2)                       # Jolt: before it falls asleep
        cs = filter(c -> c.a.name in ("box", "floor") && c.b.name in ("box", "floor"), contacts(w))
        @test all(c -> abs(c.normal[2]) > 0.99, cs)
        if BULLET
            @test length(cs) == 4                            # a box face on a box face: 4 points
            @test all(c -> abs(c.depth) < 0.01, cs)
            @test sum(c -> c.impulse, cs) ≈ 3 * 9.81 / 120 rtol = 0.1    # m·g·dt per step
        else                                                 # one row per manifold, sunk by the slop
            @test length(cs) == 1
            @test all(c -> -0.03 < c.depth < 0.01, cs)
        end
    end
end

@testset "force hooks and mutual gravity" begin
    # A hook that cancels gravity: the box hangs in the air.
    with_world(toml("""
        [[object]]
        name = "box"
        shape = "box"
        mass = 2
        position = [0, 5, 0]
        """)) do w
        b = body(w, "box")
        add_force!(w, (w, dt) -> apply_impulse!(b, (0, mass(b) * 9.81 * dt, 0)))
        simulate!(w, 2)
        @test position(b)[2] ≈ 5 atol = 1e-3
        advance!(w, 0.1)                                  # also through bullet3's own substeps
        @test position(b)[2] ≈ 5 atol = 1e-3
    end
    with_world(toml("[[object]]\nname = \"b\"\nshape = \"box\"\n")) do w
        add_force!(w, (w, dt) -> error("boom"))
        @test_throws Exception step!(w)                   # surfaces after the step
        empty!(w.forces)
        step!(w)                                          # and the world still works
    end

    # Two spheres in empty space attract: a = G·m/d² at the start, and the
    # centre of mass stays put.
    G, m, d = 0.5, 4.0, 4.0
    with_world(toml("""
        [world]
        gravity = [0, 0, 0]
        mutual_gravity = $G
        hz = 240
        [[object]]
        name = "a"
        shape = "sphere"
        radius = 0.5
        mass = $m
        position = [$(-d / 2), 0, 0]
        [[object]]
        name = "b"
        shape = "sphere"
        radius = 0.5
        mass = $m
        position = [$(d / 2), 0, 0]
        """)) do w
        a, b = body(w, "a"), body(w, "b")
        step!(w, 24)                                      # 0.1 s
        @test velocity(a)[1] ≈ G * m / d^2 * 0.1 rtol = 0.02
        @test velocity(b)[1] ≈ -G * m / d^2 * 0.1 rtol = 0.02
        simulate!(w, 5)
        @test touching(w, a, b)
        com = vscale(vadd(position(a), position(b)), 0.5f0)
        @test vnorm(com) < 1e-3
        @test !sleeping(a)                                # mutual gravity keeps bodies awake
    end

    # A moon on a circular orbit round a static planet that attracts by its
    # gravity_mass: in bullet3's single precision the radius holds to ~1%.
    G, M, r = 1.0, 100.0, 6.0
    v = sqrt(G * M / r)
    with_world(toml("""
        [world]
        gravity = [0, 0, 0]
        mutual_gravity = $G
        hz = 240
        [[object]]
        name = "planet"
        shape = "sphere"
        radius = 1
        mass = 0
        gravity_mass = $M
        [[object]]
        name = "moon"
        shape = "sphere"
        radius = 0.2
        mass = 0.01
        position = [$r, 0, 0]
        velocity = [0, 0, $v]
        """)) do w
        moon = body(w, "moon")
        T = 2π * r / v
        rmin, rmax = Inf, 0.0
        for _ in 1:round(Int, 2T * 240)
            step!(w, 1)
            rr = vnorm(position(moon)); rmin = min(rmin, rr); rmax = max(rmax, rr)
        end
        @test rmin > r * 0.99 && rmax < r * 1.01
        @test position(body(w, "planet")) == (0f0, 0f0, 0f0)        # static: pulls, doesn't move
    end
end

@testset "mutual gravity: Barnes–Hut tree" begin
    O = ObjectSim
    # Sources from a fixed LCG (no Random dependency): a uniform ball, or five
    # clumps of different sizes.
    function cloud(n, kind)
        s = UInt64(42)
        u() = (s = s * 6364136223846793005 + 1442695040888963407; (s >> 11) / 2.0^53)
        x, y, z, m = zeros(n), zeros(n), zeros(n), zeros(n)
        for i in 1:n
            if kind == :ball
                while true
                    p = (2u() - 1, 2u() - 1, 2u() - 1)
                    sum(abs2, p) <= 1 && ((x[i], y[i], z[i]) = 20 .* p; break)
                end
            else
                c, r = 10.0 * (i % 5), 0.5 + i % 3
                x[i], y[i], z[i] = c + r * (2u() - 1), r * (2u() - 1), r * (2u() - 1) - c / 2
            end
            m[i] = 0.5 + u()
        end
        return x, y, z, m
    end
    relerr(a, b, i) = hypot(a[1][i] - b[1][i], a[2][i] - b[2][i], a[3][i] - b[3][i]) /
                      hypot(a[1][i], a[2][i], a[3][i])
    t = O.GravityTree()
    for kind in (:ball, :clumps), n in (300, 3000)
        x, y, z, m = cloud(n, kind)
        d = (zeros(n), zeros(n), zeros(n)); b = (zeros(n), zeros(n), zeros(n))
        O._gravity_direct!(d..., x, y, z, m, 0.7)
        # θ → 0 opens every node: the same pairs as the direct sum.
        O._gravity_tree!(t, b..., x, y, z, m, 0.7, 1e-9)
        @test maximum(i -> relerr(d, b, i), 1:n) < 1e-10
        # The default θ = 0.5: measured median 0.03–0.4 %, worst 1–6 % (a body
        # near the middle of a ball, where the pulls nearly cancel).
        O._gravity_tree!(t, b..., x, y, z, m, 0.7, O.GRAVITY_THETA[])
        e = sort([relerr(d, b, i) for i in 1:n])
        @test e[n ÷ 2] < 5e-3
        @test e[end] < 0.1
    end
    # Coincident bodies (r = 0 pairs, more of them than a leaf holds), a lone
    # body, none: finite, and the lone body feels nothing.
    n = 100
    x, y, z, m = fill(1.0, n), fill(2.0, n), fill(3.0, n), ones(n)
    x[1] = 5.0
    b = (zeros(n), zeros(n), zeros(n))
    O._gravity_tree!(t, b..., x, y, z, m, 1.0, 0.5)
    @test all(isfinite, b[1]) && b[1][1] ≈ -(n - 1) / 16 && all(==(0.0), b[2][2:end])
    O._gravity_tree!(t, (zeros(1), zeros(1), zeros(1))..., [1.0], [2.0], [3.0], [1.0], 1.0, 0.5)
    O._gravity_tree!(t, Float64[], Float64[], Float64[], Float64[], Float64[], Float64[], Float64[], 1.0, 0.5)
    @test O._nnodes(t) == 0
    # Warm, a single-threaded sum allocates nothing.
    x, y, z, m = cloud(400, :clumps)
    a = (zeros(400), zeros(400), zeros(400))
    O._gravity_accel!(t, a..., x, y, z, m, 1.0)
    alloc(t, a, x, y, z, m) = @allocated O._gravity_tree!(t, a[1], a[2], a[3], x, y, z, m, 1.0, 0.5)
    alloc(t, a, x, y, z, m)
    @test alloc(t, a, x, y, z, m) == 0

    # A world on the tree from the first body: the two-sphere test again, and
    # a cloud whose total momentum stays near zero (the tree's pulls are not
    # exactly equal and opposite, as the direct sum's are).
    from = O.GRAVITY_TREE_FROM[]
    O.GRAVITY_TREE_FROM[] = 1
    try
        G, m, d = 0.5, 4.0, 4.0
        with_world(toml("""
            [world]
            gravity = [0, 0, 0]
            mutual_gravity = $G
            hz = 240
            [[object]]
            name = "a"
            shape = "sphere"
            radius = 0.5
            mass = $m
            position = [$(-d / 2), 0, 0]
            [[object]]
            name = "b"
            shape = "sphere"
            radius = 0.5
            mass = $m
            position = [$(d / 2), 0, 0]
            """)) do w
            a, b = body(w, "a"), body(w, "b")
            step!(w, 24)
            @test velocity(a)[1] ≈ G * m / d^2 * 0.1 rtol = 0.02
            @test velocity(b)[1] ≈ -G * m / d^2 * 0.1 rtol = 0.02
            simulate!(w, 5)
            @test touching(w, a, b)
            @test vnorm(vscale(vadd(position(a), position(b)), 0.5f0)) < 1e-3
        end
        x, y, z, _ = cloud(150, :ball)
        objs = join(("""
            [[object]]
            name = "r$i"
            shape = "sphere"
            radius = 0.3
            mass = $(1 + i % 3)
            position = [$(x[i]), $(y[i]), $(z[i])]
            """ for i in 1:150), "\n")
        with_world(toml("[world]\ngravity = [0, 0, 0]\nmutual_gravity = 2.0\nhz = 120\n" * objs)) do w
            simulate!(w, 3)
            ms = [mass(b) for b in w.bodies]; vs = [velocity(b) for b in w.bodies]
            P = ntuple(k -> sum(ms[i] * vs[i][k] for i in eachindex(ms)), 3)
            scale = sum(ms[i] * vnorm(vs[i]) for i in eachindex(ms))
            @test scale > 1                                  # the cloud did fall in
            @test vnorm(P) < 0.01 * scale
        end
    finally
        O.GRAVITY_TREE_FROM[] = from
    end
end

@testset "orbits (OrdinaryDiffEq, Float64)" begin
    # Elements → state → elements.
    μ = G_SOLAR * (1 + 3e-6)
    r, v = ObjectSim.elements_to_state(μ; a = 1.3, e = 0.25, i = 12, node = 40, peri = 77, M = 123)
    a, e = state_to_elements(μ, r, v)
    @test a ≈ 1.3 rtol = 1e-12
    @test e ≈ 0.25 rtol = 1e-10

    # Kepler's third law: one period later the planet is back where it started.
    sys = parse_orbits(ObjectSim.TOML.parse("""
        [[body]]
        name = "Sun"
        mass = 1.0
        [[body]]
        name = "Planet"
        mass = 3e-6
        orbit = { around = "Sun", a = 1.0, e = 0.2, M = 40 }
        """))
    s = OrbitSim(sys)
    rel(s) = (X = orbit_positions(s); X[:, 2] .- X[:, 1])
    r0 = rel(s)
    T = kepler_period(G_SOLAR * (1 + 3e-6), 1.0)
    @test 2π / ObjectSim.GAUSS_K ≈ 365.2568983 rtol = 1e-9     # the Gaussian year: a = 1 AU, massless
    @test T ≈ 2π / ObjectSim.GAUSS_K / sqrt(1 + 3e-6) rtol = 1e-12   # a planet's own mass shortens it
    advance_orbits!(s, T)
    @test maximum(abs.(rel(s) .- r0)) < 1e-9
    # 100 orbits: energy and angular momentum hold to round-off.
    L0 = nbody_angular_momentum(s.m, s.integ.u.x[2], s.integ.u.x[1])
    advance_orbits!(s, 99T)
    @test abs(energy_drift(s)) < 1e-10
    L1 = nbody_angular_momentum(s.m, s.integ.u.x[2], s.integ.u.x[1])
    @test maximum(abs.(L1 .- L0)) / maximum(abs.(L0)) < 1e-10

    # The figure-eight comes back to itself after its period.
    s8 = OrbitSim(load_orbits(joinpath(ROOT, "scenes", "orbits", "figure_eight.toml")))
    X0 = orbit_positions(s8)
    advance_orbits!(s8, 6.32591398)
    @test maximum(abs.(orbit_positions(s8) .- X0)) < 1e-5
    advance_orbits!(s8, 6.32591398 * 9)                      # ten turns
    @test maximum(abs.(orbit_positions(s8) .- X0)) < 1e-3
    @test abs(energy_drift(s8)) < 1e-10

    # A head-on collision merges the two, keeping mass and momentum.
    sm = OrbitSim(parse_orbits(ObjectSim.TOML.parse("""
        [system]
        units = "nbody"
        barycentric = false
        [[body]]
        name = "a"
        mass = 1
        radius = 0.1
        position = [-1, 0, 0]
        velocity = [0.5, 0.1, 0]
        [[body]]
        name = "b"
        mass = 3
        radius = 0.2
        position = [1, 0, 0]
        velocity = [-0.5, 0, 0]
        """)))
    p0 = sum(sm.m[i] .* orbit_velocities(sm)[:, i] for i in 1:2)
    advance_orbits!(sm, 5)
    @test length(sm.bodies) == 1 && length(sm.mergers) == 1
    @test sm.bodies[1].name == "b" && sm.m[1] == 4                 # the bigger keeps its name
    @test (sm.mergers[1].a, sm.mergers[1].b, sm.mergers[1].into) == ("a", "b", "b")
    @test sm.m[1] .* orbit_velocities(sm)[:, 1] ≈ p0 atol = 1e-9
    @test sm.bodies[1].radius ≈ cbrt(0.1^3 + 0.2^3)

    # The solar system scene: ten years, energy kept, Earth's year about right.
    ss = OrbitSim(load_orbits(joinpath(ROOT, "scenes", "orbits", "solar_system.toml")))
    k = orbit_body(ss, "Earth"); sun = orbit_body(ss, "Sun")
    e0 = orbit_positions(ss)[:, k] .- orbit_positions(ss)[:, sun]
    advance_orbits!(ss, 365.256)
    e1 = orbit_positions(ss)[:, k] .- orbit_positions(ss)[:, sun]
    @test maximum(abs.(e1 .- e0)) < 0.01                       # back within 0.01 AU after a year
    advance_orbits!(ss, 9 * 365.25)
    @test abs(energy_drift(ss)) < 1e-9
    @test isempty(ss.mergers)
end

@testset "changing bodies and the world while it runs" begin
    zero_g = "[world]\ngravity = [0, 0, 0]\n"
    with_world(toml(zero_g * "[[object]]\nname = \"b\"\nshape = \"box\"\nmass = 2\n")) do w
        b = body(w, "b")
        set_mass!(b, 4)
        @test mass(b) == 4
        BULLET && @test ObjectSim.B.btRigidBody_getInvMass(b.h.ptr) ≈ 0.25
        apply_impulse!(b, (0, 4, 0))
        @test velocity(b)[2] ≈ 1                          # Δv = J / m with the new mass
        set_damping!(b, 0.5, 0.5)
        simulate!(w, 1)
        @test 0.3 < velocity(b)[2] < 0.7                  # drag took about half
        set_friction!(b, 0.9); set_restitution!(b, 0.4); set_rolling_friction!(b, 0.1)
        BULLET && @test ObjectSim.B.btCollisionObject_getFriction(b.h.ptr) ≈ 0.9
        BULLET && @test ObjectSim.B.btCollisionObject_getRestitution(b.h.ptr) ≈ 0.4
        @test (b.spec.friction, b.spec.restitution, b.spec.rolling_friction) == (0.9f0, 0.4f0, 0.1f0)
        set_look!(b; glow = 1f0, light = 5f0)
        @test (b.spec.glow, b.spec.light) == (1f0, 5f0)
        set_solver_iterations!(w, 33)
        @test solver_iterations(w) == 33
        @test w.mutual === nothing
        set_mutual_gravity!(w, 0.5)
        @test w.mutual_G == 0.5 && w.mutual in w.forces
        set_mutual_gravity!(w, 2.0)
        @test count(f -> f === w.mutual, w.forces) == 1 && length(w.forces) == 1
        set_mutual_gravity!(w, 0)
        @test w.mutual === nothing && isempty(w.forces)
    end
    # Bounce: the same ball dropped with restitution 0 and 0.8.
    heights = map((0.0, 0.8)) do e
        with_world(toml(floor_toml * "[[object]]\nname = \"ball\"\nshape = \"sphere\"\nradius = 0.3\nposition = [0, 3, 0]\n")) do w
            # bullet3 multiplies the two restitutions, Jolt takes the larger
            b = body(w, "ball"); set_restitution!(b, e); set_restitution!(body(w, "floor"), BULLET ? 1 : 0)
            peak = 0f0; landed = false
            for _ in 1:360
                step!(w, 1)
                y = position(b)[2]
                landed |= y < 0.32
                landed && (peak = max(peak, y))
            end
            peak
        end
    end
    @test heights[1] < 0.35 && heights[2] > 1.5            # dead vs bouncy
    # Scenes by name.
    @test endswith(find_scene("night"), "scenes/night.toml")
    @test endswith(find_scene("solar_system"), "scenes/orbits/solar_system.toml")
    @test is_orbit_scene(find_scene("figure_eight")) && !is_orbit_scene(find_scene("bridge"))
    @test_throws ErrorException find_scene("no_such_scene")
end

@testset "water: buoyancy, drag, density" begin
    # Volume and cells of a unit cube: the mesh volume, cells inside, sum = volume.
    pts, cv, V = buoyancy_cells(box_mesh((0.5f0, 0.5f0, 0.5f0)))
    @test V ≈ 1.0 atol = 1e-5
    @test length(pts) == 64 && cv * length(pts) ≈ V
    @test all(p -> all(abs.(p) .< 0.5f0), pts)
    @test volume(sphere_mesh(1f0)) ≈ 4π / 3 rtol = 0.02
    # A ring (open in the middle): no cell centre in the hole.
    m = load_mesh(asset("bowl.obj"))
    pts2, _, _ = buoyancy_cells(m)
    @test !isempty(pts2)

    sc = toml("""
    [water]
    level = 0
    [[object]]
    name = "half"
    shape = "box"
    size = [1, 1, 1]
    mass = 500
    position = [-3, 2, 0]
    [[object]]
    name = "brick"
    shape = "box"
    size = [1, 1, 1]
    mass = 2000
    position = [0, 1, 0]
    [[object]]
    name = "cork"
    shape = "sphere"
    radius = 0.5
    mass = 100
    position = [3, -2, 0]
    sleep = false
    [[object]]
    name = "plank"
    shape = "box"
    size = [3, 0.3, 0.6]
    mass = 300
    position = [0, 0.5, 4]
    rotation = [0, 0, 70]
    """)
    @test sc.world.water.density == 1000
    with_world(sc) do w
        @test water(w).level == 0
        @test density(body(w, "half")) ≈ 500 rtol = 1e-4
        simulate!(w, 15)
        @test abs(position(body(w, "half"))[2]) < 0.1          # half under: centre at the surface
        @test position(body(w, "brick"))[2] < -10               # twice as dense: sinks
        # 19% of a sphere's volume is under: its centre ≈ 0.21 m above the surface
        @test position(body(w, "cork"))[2] ≈ 0.21 atol = 0.05
        @test vnorm(velocity(body(w, "cork"))) < 0.05           # drag settled it
        R, _ = transform(body(w, "plank"))
        @test R[2][2] > 0.99                                    # lies flat, righted itself
        # A sinking brick reaches a terminal speed instead of falling freely.
        v = velocity(body(w, "brick"))[2]
        @test -6 < v < -1
        # Drain it: the half-density crate falls.
        set_water!(w, nothing)
        @test water(w) === nothing
        y0 = position(body(w, "half"))[2]
        simulate!(w, 0.5)
        @test position(body(w, "half"))[2] < y0 - 0.5
        # Mercury: the brick (2000 kg/m³) would float in it.
        set_water!(w, WaterSpec(; level = 0f0, density = 13534f0))
        @test water(w).density == 13534
    end
    @test_throws ErrorException toml("[water]\ndensity = -1")
    @test_throws ErrorException toml("[water]\ncolour = 1")
end

@testset "motors, mesh cache, model library" begin
    with_world(scene("mars.toml")) do w
        @test motor_count(w) == 6
        z0 = position(body(w, "chassis"))[3]
        simulate!(w, 6)
        z1 = position(body(w, "chassis"))[3]
        @test z1 - z0 > 1.2                                     # drives forward
        @test transform(body(w, "chassis"))[1][2][2] > 0.95     # upright
        @test set_motors!(w, -1) == 6                           # reverse
        simulate!(w, 6)
        @test position(body(w, "chassis"))[3] < z1 - 1.0
        set_motors!(w, 0)                                       # stop: holds still
        simulate!(w, 2)
        z2 = position(body(w, "chassis"))[3]
        simulate!(w, 2)
        @test abs(position(body(w, "chassis"))[3] - z2) < 0.05
        @test count(broken, w.joints) == 0
    end
    f = joinpath(ROOT, "assets", "models", "perseverance", "chassis.stl")
    if isfile(f)
        a = load_mesh(f); b = load_mesh(f)
        @test a === b                                           # read once
    end
    lib = ObjectSim._model_library()
    @test first(lib)[1] == "basic"
    @test all(f -> lowercase(splitext(f)[2]) in (".obj", ".stl"), reduce(vcat, last.(lib)))
    d = ObjectSim._dropped_spec(asset("rock.obj"), (0f0, 0f0, 0f0), (0xff, 0, 0); size = 2f0)
    @test d.scale[1] ≈ 2                                        # 1.2 m rock: kept at 1 × size
    @test d.mass ≈ 500 * volume(load_mesh(asset("rock.obj"))) * 8 rtol = 1e-4
    # Follow camera from the scene.
    @test load_scene(scene("mars.toml")).camera.follow == "chassis"
end

@testset "springs: oscillation, damping, coupling, stability" begin
    # One mass on a spring in zero g (or two, or a chain), as a scene.
    function spring_world(; m = 1.0, k = 100.0, c = 0.0, hz = 120, g = (0, 0, 0))
        toml("""
        [world]
        gravity = [$(g[1]), $(g[2]), $(g[3])]
        hz = $hz
        [[object]]
        name = "m"
        shape = "box"
        size = [0.2, 0.2, 0.2]
        mass = $m
        [[joint]]
        type = "spring"
        a = "m"
        pivot = [0, 0, 0]
        stiffness = $k
        damping = $c
        """)
    end
    track(w, b, seconds; axis = 1) = [(step!(w); position(b)[axis]) for _ in 1:round(Int, seconds / w.dt)]
    function crossings(x, dt)                     # times x goes up through 0
        [(i + -x[i] / (x[i + 1] - x[i])) * dt for i in 1:length(x) - 1 if x[i] < 0 <= x[i + 1]]
    end
    peaks(x) = [abs(x[i]) for i in 2:length(x) - 1 if abs(x[i]) >= abs(x[i - 1]) && abs(x[i]) > abs(x[i + 1])]
    peak_times(x, dt) = [i * dt for i in 2:length(x) - 1 if abs(x[i]) >= abs(x[i - 1]) && abs(x[i]) > abs(x[i + 1])]

    # Undamped: period 2π√(m/k), amplitude kept, no jitter on the sine.
    with_world(spring_world(; m = 1, k = 100)) do w
        b = body(w, "m"); set_velocity!(b, (1, 0, 0))
        x = track(w, b, 10)
        T = sum(diff(crossings(x, w.dt))) / (length(crossings(x, w.dt)) - 1)
        @test T ≈ 2π / 10 rtol = 1e-3
        pk = peaks(x)
        @test pk[end] / pk[2] ≈ 1 atol = 0.005
        ts = (1:length(x)) .* w.dt; ω = 2π / T
        M = hcat(sin.(ω .* ts), cos.(ω .* ts), ones(length(x)))
        @test sqrt(sum(abs2, x .- M * (M \ x)) / length(x)) < 1e-4 * maximum(abs, x)
        @test maximum(abs, (p -> p[2]).(Ref(position(b)))) < 1e-6        # no drift off-axis
    end
    # Light damping: peaks decay as exp(−c/2m · t).
    with_world(spring_world(; m = 1, k = 100, c = 1.0)) do w
        b = body(w, "m"); set_velocity!(b, (1, 0, 0))
        x = track(w, b, 8); pk = peaks(x); tp = peak_times(x, w.dt)
        rate = log(pk[2] / pk[end]) / (tp[end] - tp[2])
        @test rate ≈ 0.5 rtol = 0.01                                   # c/2m
        set_spring!(w, w.joints[1]; damping = 4)                       # live change
        x = track(w, b, 2); pk = peaks(x); tp = peak_times(x, w.dt)
        @test log(pk[1] / pk[end]) / (tp[end] - tp[1]) ≈ 2 rtol = 0.01
    end
    # Stretch and release, overdamped (ζ = 2): creeps back as the exact solution.
    # (At 480 Hz: the damping time m/c is then 12 steps; at 120 Hz it is 3, and
    # the creep runs 7% fast, with a warning.)
    with_world(spring_world(; m = 1, k = 100, c = 40, g = (20, 0, 0), hz = 480)) do w   # held at 0.2 m
        b = body(w, "m"); simulate!(w, 6)
        A = position(b)[1]
        @test A ≈ 0.2 atol = 1e-4
        set_gravity!(w, (0, 0, 0))
        x = track(w, b, 3)
        s = sqrt(20^2 - 100); r1, r2 = -20 + s, -20 - s
        ex = [A * (r2 * exp(r1 * t) - r1 * exp(r2 * t)) / (r2 - r1) for t in (1:length(x)) .* w.dt]
        @test maximum(abs.(x .- ex)) < 0.02A
        @test minimum(x) > 0                                            # no overshoot
    end
    # Hanging under gravity: settles at m·g/k exactly, then rests without jitter.
    with_world(spring_world(; m = 2, k = 100, c = 5, g = (0, -9.81, 0))) do w
        b = body(w, "m"); simulate!(w, 15)
        @test -position(b)[2] ≈ 2 * 9.81 / 100 rtol = 1e-3
        @test vnorm(velocity(b)) < 1e-5
        @test !sleeping(b)                       # springs keep their bodies awake
    end
    # Two masses, three springs: both normal modes at their frequencies.
    coupled = toml("""
        [world]
        gravity = [0, 0, 0]
        [[object]]
        name = "p"
        shape = "box"
        size = [0.2, 0.2, 0.2]
        position = [-1, 0, 0]
        repeat = 2
        step = [2, 0, 0]
        [[joint]]
        type = "spring"
        chain = "p"
        ends = "both"
        stiffness = 100
        damping = 0
        """)
    # (bullet3's own spring, used before, ran the opposed mode at ω² = 200.)
    for (v1, v2, ω) in ((1, 1, 10.0), (1, -1, sqrt(300.0)))   # in step / opposed
        with_world(coupled) do w
            b1, b2 = body(w, "p[1]"), body(w, "p[2]")
            set_velocity!(b1, (v1, 0, 0)); set_velocity!(b2, (v2, 0, 0))
            x = track(w, b1, 6) .+ 1
            cs = crossings(x, w.dt)
            @test (cs[end] - cs[1]) / (length(cs) - 1) ≈ 2π / ω rtol = 2e-3
        end
    end
    # Held still by unequal loads, damped: settles exactly where the spring
    # matrix says ([2k −k; −k 2k]·x = m·g), whatever the damping.
    with_world(coupled) do w
        foreach(j -> set_spring!(w, j; damping = 20), w.joints)
        set_body_gravity!(w, body(w, "p[1]"), (20, 0, 0))
        simulate!(w, 10)
        @test position(body(w, "p[1]"))[1] + 1 ≈ 0.4 / 3 atol = 1e-4
        @test position(body(w, "p[2]"))[1] - 1 ≈ 0.2 / 3 atol = 1e-4
    end
    # Too stiff for the step rate (ω·dt = 1.2): solved implicitly, with a
    # warning. Never explodes or softens; the ringing the step can't show
    # dies out, and it hangs exactly where Hooke says.
    @test_logs (:warn, r"solved implicitly") match_mode = :any with_world(spring_world(; k = 20_000)) do w
        b = body(w, "m"); set_velocity!(b, (1, 0, 0))
        @test spring_implicit(w, w.joints[1]) || (step!(w); spring_implicit(w, w.joints[1]))
        x = track(w, b, 5)
        @test all(isfinite, x) && maximum(abs, x) < 1 / sqrt(20_000)     # never past v/ω
        @test maximum(abs, x[end - 60:end]) < 1e-6
        @test spring_stiffness(w.joints[1]) == 20_000                     # not softened
    end
    for k in (20_000, 1e6)                                                # sag m·g/k at any stiffness
        with_world(spring_world(; m = 2, k, g = (0, -9.81, 0))) do w
            simulate!(w, 3)
            @test -position(body(w, "m"))[2] ≈ 2 * 9.81 / k rtol = 1e-3
        end
    end
    # Heavily overdamped at 120 Hz (damping time m/c under a step): implicit,
    # creeps back as the exact solution.
    with_world(spring_world(; m = 1, k = 100, c = 400, g = (200, 0, 0))) do w   # held at 2 m
        b = body(w, "m"); simulate!(w, 45)
        A = position(b)[1]
        @test A ≈ 2 rtol = 1e-3
        set_gravity!(w, (0, 0, 0))
        x = track(w, b, 6)
        s = sqrt(200^2 - 100); r1, r2 = -200 + s, -200 - s
        ex = [A * (r2 * exp(r1 * t) - r1 * exp(r2 * t)) / (r2 - r1) for t in (1:length(x)) .* w.dt]
        @test maximum(abs.(x .- ex)) < 0.01A
        @test minimum(x) > 0
    end
    # Heavy damping on a body with several springs: solved implicitly, so
    # the dampers' sum stays stable at full strength (the explicit damper
    # needed a cap; bullet3's own per-spring cap blew up).
    heavy = toml("""
        [world]
        gravity = [0, 0, 0]
        [[object]]
        name = "p"
        shape = "box"
        size = [0.2, 0.2, 0.2]
        position = [-1, 0, 0]
        repeat = 2
        step = [2, 0, 0]
        [[joint]]
        type = "spring"
        chain = "p"
        ends = "both"
        stiffness = 900
        damping = 120
        """)
    with_world(heavy) do w
        set_velocity!(body(w, "p[1]"), (-1, 0, 0)); set_velocity!(body(w, "p[2]"), (1, 0, 0))
        simulate!(w, 5)
        @test all(b -> all(isfinite, position(b)) && vnorm(velocity(b)) < 1e-3, w.bodies)
        @test all(j -> spring_damping(j) == 120 && spring_implicit(w, j), w.joints)
    end
    # Light beads, default damping (2 N·s/m on 0.02 kg is far past m/dt): implicit, stable, settles.
    with_world(toml("""
        [world]
        gravity = [0, 0, 0]
        [[object]]
        name = "bead"
        shape = "sphere"
        radius = 0.05
        mass = 0.02
        repeat = 10
        step = [0.3, 0, 0]
        [[joint]]
        type = "spring"
        chain = "bead"
        ends = "both"
        stiffness = 100
        """)) do w
        set_velocity!(body(w, "bead[3]"), (0, 3, 0))
        simulate!(w, 6)
        @test all(j -> spring_stiffness(j) == 100 && spring_implicit(w, j), w.joints)   # not softened
        @test all(b -> all(isfinite, position(b)) && vnorm(velocity(b)) < 1e-3, w.bodies)
    end
end

if !BULLET
    @testset "jolt: awake count, thread pool" begin
        with_world(scene("tumble.toml")) do w
            P = w.phys
            step!(w, 30)
            @test ObjectSim._jnum_active(P) == count(b -> !isstatic(b) && !sleeping(b), w.bodies)
            @test P.pool == C_NULL                                   # small: one thread, no pool yet
            old = ObjectSim.JOLT_POOL_FROM[]
            try
                ObjectSim.JOLT_POOL_FROM[] = 1                       # every step on the pool
                step!(w, 120)
                @test P.pool != C_NULL
                @test all(b -> all(isfinite, position(b)), w.bodies)
            finally
                ObjectSim.JOLT_POOL_FROM[] = old
            end
        end
    end
end

@testset "raylib Matrix layout = bullet3 transform" begin
    # Check the field-for-field mapping in viewer.jl against raylib's own math:
    # transforming a point with the Matrix must equal R·p + o.
    R_ = ObjectSim.R
    rows = rotation_matrix((25, -40, 70)); o = (1.5f0, -2f0, 3f0)
    m = ObjectSim._matrix(rows, o)
    for p in ((1f0, 0f0, 0f0), (0f0, 1f0, 0f0), (0.3f0, -0.7f0, 2f0))
        q = R_.Vector3Transform(R_.Vector3(p...), m)
        @test (q.x, q.y, q.z) ≈₃ vadd(o, _rotate(rows, p)) atol = 1e-5
    end
    # And against raylib composing the same transform itself.
    rz = rotation_matrix((0, 0, 30))
    ref = R_.MatrixMultiply(R_.MatrixRotateZ(deg2rad(30)), R_.MatrixTranslate(1, 2, 3))
    mine = ObjectSim._matrix(rz, (1f0, 2f0, 3f0))
    @test all(isapprox(getfield(mine, f), getfield(ref, f); atol = 1e-6) for f in fieldnames(R_.Matrix))
end

if (haskey(ENV, "DISPLAY") || haskey(ENV, "WAYLAND_DISPLAY")) && get(ENV, "OBJECTSIM_NO_WINDOW", "") != "1"
    @testset "windows: shadows, bloom, instancing, orbits" begin
        mktempdir() do d
            png = joinpath(d, "shot.png")
            run_window(scene("tumble.toml"); width = 640, height = 360, frames = 30, screenshot = png)
            @test isfile(png) && filesize(png) > 1000
            # the same with shadows and bloom off (the plain path still works)
            png2 = joinpath(d, "plain.png")
            run_window(scene("playground.toml"); width = 640, height = 360, frames = 10, screenshot = png2,
                       shadows = false, bloom = false)
            @test isfile(png2) && filesize(png2) > 1000
            png4 = joinpath(d, "night.png")
            run_window(scene("night.toml"); width = 640, height = 360, frames = 20, screenshot = png4)
            @test isfile(png4) && filesize(png4) > 1000
            for tab in 1:6                                  # every menu tab draws
                run_window(scene("night.toml"); width = 640, height = 480, frames = 5, menu = true, tab,
                           select = tab == 3 ? "lantern" : "")
            end
            for tab in (1, 3, 4)                            # water, motors, density, models
                run_window(scene("harbor.toml"); width = 640, height = 480, frames = 5, menu = true, tab,
                           select = tab == 3 ? "ship" : "")
            end
            run_window(scene("mars.toml"); width = 640, height = 480, frames = 5, menu = true, tab = 1)
            png5 = joinpath(d, "nebulae.png")
            run_window(scene("nebulae.toml"); width = 640, height = 360, frames = 10, screenshot = png5)
            @test isfile(png5) && filesize(png5) > 1000
            run_orbits_window(joinpath(ROOT, "scenes", "orbits", "cluster.toml"); width = 640, height = 480,
                              frames = 5, menu = true)
            png3 = joinpath(d, "orbits.png")
            s = run_orbits_window(joinpath(ROOT, "scenes", "orbits", "solar_system.toml");
                                  width = 640, height = 360, frames = 30, screenshot = png3)
            @test isfile(png3) && filesize(png3) > 1000
            @test orbit_time(s) > 0
        end
    end
else
    @info "No display (or OBJECTSIM_NO_WINDOW=1): window test skipped"
end

end
