# ObjectSim tests. Everything but the last testset runs headless; that one opens
# a window for 30 frames when a display is present (set OBJECTSIM_NO_WINDOW=1
# to skip it).
#
#   julia --project=examples/ObjectSim -e 'using Pkg; Pkg.test()'

using Test
using ObjectSim
using ObjectSim: box_mesh, sphere_mesh, capsule_mesh, cylinder_mesh, cone_mesh,
                 render_arrays, transform_mesh, rotation_matrix, vadd, vsub, vnorm, _rotate

const ROOT = dirname(@__DIR__)
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
            # Collision margins (0.04 m) may lift convex shapes slightly.
            @test rest_y - 0.01 < position(b)[2] < rest_y + 0.06
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
        rolling_friction = 0.02
        """)) do w
        b = body(w, "ball")
        simulate!(w, 10)
        p = position(b)
        @test hypot(p[1], p[3]) < 0.5
        @test 0.25 < p[2] < 0.45
        @test isstatic(body(w, "bowl")) && length(body(w, "bowl").keep) == 2   # buffers held
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
    @testset "window: 30 frames and a screenshot" begin
        mktempdir() do d
            png = joinpath(d, "shot.png")
            run_window(scene("tumble.toml"); width = 640, height = 360, frames = 30, screenshot = png)
            @test isfile(png) && filesize(png) > 1000
        end
    end
else
    @info "No display (or OBJECTSIM_NO_WINDOW=1): window test skipped"
end

end
