"""
    ObjectSim

A rigid-body object simulator: bullet3 runs the physics, raylib draws it.

```julia
using ObjectSim
ObjectSim.run_headless("scenes/tumble.toml"; seconds = 5)   # no window
ObjectSim.run_window("scenes/tumble.toml")                  # window
```

Scenes are TOML files (see `src/scene.jl` for every key). Objects are
primitives (box, sphere, capsule, cylinder, cone) or mesh assets (`.obj`,
`.stl`) used as a convex hull (moving) or a triangle mesh (static).

Layers:
- `lib/` — the generated bullet3 and raylib wrappers, copied in by `vendor.sh`.
  Never edited.
- `geometry.jl`, `assets.jl`, `scene.jl` — plain Julia: meshes, file loading,
  scene parsing. No library calls.
- `physics.jl` — the bullet3 world and bodies.
- `viewer.jl` — the raylib window. Only `run_window` touches raylib, so everything
  else runs without a display.
"""
module ObjectSim

using Libdl
using TOML
using RepliBuild   # the generated wrappers dispatch through its JIT

const _LIB = joinpath(@__DIR__, "..", "lib")
for (pkg, file) in (("bullet3", "Bullet3.jl"), ("raylib", "Raylib.jl"))
    isfile(joinpath(_LIB, pkg, file)) ||
        error("ObjectSim: lib/$pkg/$file is missing — run examples/ObjectSim/vendor.sh")
end

include(joinpath(_LIB, "bullet3", "Bullet3.jl"))
include(joinpath(_LIB, "raylib", "Raylib.jl"))
import .Bullet3 as B          # never `using` a generated wrapper: thousands of names
import .Raylib as R

include("geometry.jl")
include("assets.jl")
include("scene.jl")
include("physics.jl")
include("viewer.jl")
include("headless.jl")

export TriMesh, load_mesh, save_obj, centroid, aabb,
       SceneSpec, ObjectSpec, load_scene, parse_scene,
       World, Body, add!, step!, advance!, simulate!, destroy!, with_world, sim_time,
       transform, render_transform, velocity, spin, sleeping, isstatic, body, snapshot,
       run_headless, run_window

end
