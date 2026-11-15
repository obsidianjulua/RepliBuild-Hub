# ObjectSim

A rigid-body object simulator: **bullet3** runs the physics and **raylib** draws
it, both through the Hub's generated wrappers. Scenes are TOML files, and objects
are either primitives or mesh files (`.obj`, `.stl`). Without a window it runs
about 30× faster than real time with 45 bodies.

```sh
examples/ObjectSim/vendor.sh                       # once, and after rebuilding bullet3 or raylib
julia --project=examples/ObjectSim examples/ObjectSim/sim.jl examples/ObjectSim/scenes/tumble.toml
```

| Command (after `sim.jl SCENE`) | What it does |
|---|---|
| *(nothing)* | window, real time. SPACE pause, R restart, O auto-orbit, drag/wheel camera, ESC quit |
| `--headless --seconds 8 --verbose` | no window: progress every simulated second, final positions |
| `--frames 200 --screenshot out.png` | window for exactly 200 frames (fixed stepping, same every run), save the last one |
| `--presim 3` | simulate 3 s before the first frame |

From Julia:

```julia
using ObjectSim
run_headless("scenes/tumble.toml"; seconds = 5)
run_window("scenes/tumble.toml")

with_world("scenes/tumble.toml") do w      # destroys the world afterwards
    simulate!(w, 2.0)
    position(body(w, "thrown")), velocity(body(w, "thrown"))
end
```

## Scenes

```toml
[world]
gravity = [0, -9.81, 0]
hz = 120                       # fixed physics steps per simulated second

[camera]                       # optional; fitted to the scene otherwise
target = [0, 1.5, 0]
distance = 22
yaw = 15
pitch = 28

[[object]]
name = "crate"
shape = "box"                  # box | sphere | capsule | cylinder | cone | hull | mesh
size = [0.8, 0.8, 0.8]
position = [1, 0.4, 4]
repeat = [3, 5, 1]             # a 3 × 5 stack
friction = 0.7
color = "#c98a3d"
```

Every key is listed at the top of [src/scene.jl](src/scene.jl). Unknown keys are
errors, so a typo doesn't get silently ignored.

## Objects and assets

| shape | from | collision shape | moving? |
|---|---|---|---|
| `box`, `sphere`, `capsule`, `cylinder`, `cone` | `size` / `radius` / `height` | the matching bullet3 primitive | yes |
| `hull` | `asset` (`.obj`/`.stl`) | `btConvexHullShape` of the mesh's points | yes |
| `mesh` | `asset` | `btBvhTriangleMeshShape`, the exact triangles | static only |

- **One copy of the geometry.** Each object's `TriMesh` builds the collision shape
  and is the mesh the viewer uploads. A mesh file is read once, in plain Julia
  ([src/assets.jl](src/assets.jl)), so headless runs never need a GPU.
- **`hull` objects are recentred on their centre of mass.** `position` still
  places the asset's own origin, and the body sits at the centroid offset from it.
  A concave asset used as a `hull` collides as its convex hull: dents get filled.
- **`mesh` objects point bullet3 at Julia arrays.** `btTriangleIndexVertexArray`
  doesn't copy its buffers, so each `Body` holds them in `keep` until the world
  is destroyed.

The sample assets come from [assets/make_assets.jl](assets/make_assets.jl), except
`ramp.obj`, which is written by hand.

## Layout

```
ObjectSim/
├── lib/              bullet3 + raylib wrappers, copied by vendor.sh (not tracked)
├── src/
│   ├── geometry.jl   TriMesh, primitives, centroid — plain Julia
│   ├── assets.jl     OBJ / STL loading — plain Julia
│   ├── scene.jl      TOML → SceneSpec — plain Julia
│   ├── physics.jl    the bullet3 world and bodies
│   ├── viewer.jl     the raylib window (the only file that calls raylib)
│   └── headless.jl   run_headless
├── scenes/  assets/  test/  sim.jl
```

## Notes on the wrappers

- **Constructors that exist only in headers have no symbol.** That covers
  `btDefaultMotionState`, `btSphereShape` and `btRigidBodyConstructionInfo`, so
  ObjectSim works around them:
  - bodies have no motion state, and transforms are read straight from the body;
  - spheres are a one-sphere `btMultiSphereShape`;
  - the construction info is filled field by field with upstream's defaults.
- **Freeing.** Every C++ object is allocated with `btAlignedAllocInternal` and
  freed with `<Class>_delete_<Class>`, which runs the destructor and then
  `btAlignedFree`. Nothing relies on the garbage collector, so call `destroy!`
  or use `with_world`.
- **Matrix layout.** raylib's `Matrix` lists its fields row by row (`m0, m4, m8,
  m12, …`), and so does bullet3's `btMatrix3x3`. A body transform therefore copies
  field for field. A test checks this against raylib's own `Vector3Transform` and
  `MatrixMultiply`.
- **Screenshots.** raylib holds 2D draws (the text overlay) in a batch until
  `EndDrawing`. The viewer flushes that batch with `rlDrawRenderBatchActive` before
  `LoadImageFromScreen`, or the text would be missing from the capture.

## Tests

```sh
julia --project=examples/ObjectSim -e 'using Pkg; Pkg.test()'
```

77 tests:
- free fall against the integrator's closed form;
- every primitive comes to rest at its own size;
- hull placement and resting contact;
- a ball settles into the concave bowl mesh;
- determinism and teardown;
- the matrix layout;
- a 30-frame window run with a screenshot. It's skipped without a display or
  with `OBJECTSIM_NO_WINDOW=1`.
