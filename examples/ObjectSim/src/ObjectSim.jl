"""
    ObjectSim

A rigid-body object simulator: bullet3 or Jolt runs the physics, raylib draws it.

```julia
using ObjectSim
ObjectSim.run_headless("scenes/tumble.toml"; seconds = 5)   # no window
ObjectSim.run_window("scenes/tumble.toml")                  # window
```

Scenes are TOML files (see `src/scene.jl` for every key). Objects are
primitives (box, sphere, capsule, cylinder, cone) or mesh assets (`.obj`,
`.stl`) used as a convex hull (moving) or a triangle mesh (static).

Layers:
- `lib/` — the generated bullet3, Jolt and raylib wrappers, copied in by
  `vendor.sh`. Never edited.
- `geometry.jl`, `assets.jl`, `scene.jl` — plain Julia: meshes, file loading,
  scene parsing. No library calls.
- `physics.jl` — World and Body, and the backend interface (`_be_*`).
- `backends/bullet3/`, `backends/jolt/` — the two physics engines, kept apart;
  a World uses one (`[world] backend`, `World(scene; backend = "jolt")`).
- `control.jl` — impulses, velocities, gravity, raycasts, live setters.
- `interactions.jl` — collision layers, contact reports, force hooks, mutual gravity.
- `joints.jl` — joints (point, hinge, slider, fixed, spring), springs, picking.
- `water.jl` — buoyancy and drag.
- `orbits.jl`, `orbit_viewer.jl` — N-body orbits in Float64 with OrdinaryDiffEq,
  drawn by raylib (no bullet3: wrong scale and precision for it).
- `viewer.jl` — the raylib window. Only `run_window` touches raylib, so everything
  else runs without a display.
"""
module ObjectSim

using Libdl
using TOML
import LinearAlgebra: cholesky, Symmetric, ldiv!   # the implicit springs' solve (joints.jl)
import SparseArrays: sparse
using RepliBuild   # the generated wrappers dispatch through its JIT

const _LIB = joinpath(@__DIR__, "..", "lib")
for (pkg, file) in (("bullet3", "Bullet3.jl"), ("jolt", "Jolt.jl"), ("raylib", "Raylib.jl"))
    isfile(joinpath(_LIB, pkg, file)) ||
        error("ObjectSim: lib/$pkg/$file is missing — run examples/ObjectSim/vendor.sh")
end

include(joinpath(_LIB, "bullet3", "Bullet3.jl"))
include(joinpath(_LIB, "jolt", "Jolt.jl"))
include(joinpath(_LIB, "raylib", "Raylib.jl"))
import .Bullet3 as B          # never `using` a generated wrapper: thousands of names
import .Jolt as J
import .Raylib as R

include("geometry.jl")
include("assets.jl")
include("scene.jl")
include("physics.jl")
include("control.jl")
include("gravity_tree.jl")
include("interactions.jl")
include("water.jl")
include("joints.jl")
include(joinpath("backends", "bullet3", "world.jl"))
include(joinpath("backends", "bullet3", "joints.jl"))
include(joinpath("backends", "jolt", "world.jl"))
include(joinpath("backends", "jolt", "joints.jl"))
include("render.jl")
include("ui.jl")
include("viewer.jl")
include("headless.jl")
include("orbits.jl")
include("orbit_viewer.jl")
include("app.jl")

function __init__()
    b = get(ENV, "OBJECTSIM_BACKEND", "")
    isempty(b) || (b in BACKENDS ? (DEFAULT_BACKEND[] = b) :
                   @warn "ObjectSim: OBJECTSIM_BACKEND=$b is not one of $(join(BACKENDS, ", ")); using $(DEFAULT_BACKEND[])")
end

export TriMesh, load_mesh, save_obj, centroid, aabb,
       SceneSpec, ObjectSpec, load_scene, parse_scene,
       JointSpec, Joint,
       World, Body, add!, spawn!, remove!, step!, advance!, simulate!, destroy!, with_world, sim_time,
       backend, isalive, apply_angular_impulse!,
       transform, render_transform, velocity, spin, sleeping, isstatic, body, snapshot, mass,
       wake!, set_velocity!, apply_impulse!, set_gravity!, explode!, raycast,
       add_joint!, remove_joint!, joint, broken, joint_points, set_motors!, motor_count, spring_stiffness, spring_damping, spring_implicit, set_spring!, grab!, drag!, release!,
       set_body_gravity!, body_gravity, set_mass!, set_friction!, set_restitution!, set_rolling_friction!,
       set_damping!, set_look!, set_solver_iterations!, solver_iterations, set_mutual_gravity!, istrigger, Contact, contacts, touching, add_force!, mutual_gravity,
       WaterSpec, set_water!, water, water_force, volume, body_volume, density, buoyancy_cells,
       OrbitSystem, OrbitBody, OrbitSim, load_orbits, parse_orbits, advance_orbits!, orbit_time,
       orbit_positions, orbit_velocities, orbit_energy, energy_drift, orbit_body, run_orbits,
       run_orbits_window, elements_to_state, state_to_elements, kepler_period, nbody_energy,
       nbody_angular_momentum, G_SOLAR,
       run_headless, run_window, app, find_scene, is_orbit_scene

end
