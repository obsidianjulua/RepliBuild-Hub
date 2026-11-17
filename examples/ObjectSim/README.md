# ObjectSim

A rigid-body object simulator: **bullet3** or **Jolt** runs the physics and
**raylib** draws it, all through the Hub's generated wrappers. Scenes are TOML files, and objects
are either primitives or mesh files (`.obj`, `.stl`). Without a window, the
45-body sample scene runs 30–75× faster than real time, depending on the run.

```sh
examples/ObjectSim/vendor.sh        # once, and after rebuilding bullet3 or raylib
objectsim                           # the playground
objectsim night                     # any scene by name (physics or orbits)
objectsim -f solar_system           # -f: stay attached to the terminal
objectsim --bullet3 mars            # the physics on bullet3 instead of Jolt
objectsim --record night            # record an MP4 to recordings/night.mp4 (ESC ends it)
```

`objectsim` is `~/.local/bin/objectsim`, a link to [objectsim](objectsim) here. It
detaches like `llamagui` and logs to `~/.cache/objectsim/objectsim.log`. In the
window, **ESC opens the menu**; its Scenes tab moves between scenes. From Julia:
`ObjectSim.app("night")`.

| Scene | What's in it |
|---|---|
| `playground` | an open floor with a tower, balls, pins and a ramp: for trying the controls |
| `wrecking_ball` | a 10 kg ball on a 10-link chain swings into a crate wall |
| `bridge` | twelve planks hinged into a rope bridge; crates and balls drop onto it |
| `machines` | a motorised sweeper, a glued tower that snaps, three springs, a pendulum wave |
| `springs` | four masses on one spring (T ∝ √m), one spring at five dampings (ζ 0 – 3), two masses in series, a bead chain in zero g: pull any of them and let go |
| `tumble` | primitives, mesh assets as hulls, a concave bowl and an STL ramp |
| `variables` | objects with their own gravity, collision layers, a trigger gate |
| `night` | moonlight, coloured lamps and a swinging lantern lighting the room |
| `rubble` | 216 rocks in space pull themselves into a spinning rubble pile (mutual gravity) |
| `impact` | two self-gravitating rubble clumps collide off-centre |
| `mars` | NASA's Perseverance (chassis, six motorised wheels, RTG) drives itself over rocks in Mars gravity; the camera follows it |
| `harbor` | sea water: a steamship, crates, barrels and moored buoys float by density; a 6 t anchor sinks |
| `nebulae` | NASA's Chandra models in zero g: the Crab's pulsar jets with stones orbiting the pulsar, and the Tycho supernova remnant (outer and inner) rejoined from its print halves |

Orbit scenes (`scenes/orbits/`, run with `orbits.jl`, see [Orbits](#orbits)):
`solar_system`, `figure_eight`, `cluster`.

### In the window

The screen stays clear: only "ESC menu" in a corner, and short messages that fade.
**ESC** opens the menu down the right-hand side:

| Tab | What's in it |
|---|---|
| World | gravity presets (Earth, Moon, Mars, Jupiter, zero) and x/y/z sliders, time speed, pause and step, physics steps per second, solver passes, mutual gravity on/off and its G; motors (speed, stop, reverse) when the scene has any; water on/off, the liquid (fresh, sea, oil, honey, mercury), surface height, density, thickness |
| View | sun strength, direction and height, sky light, sky colour; shadows, bloom (strength, threshold); show joints, contact points, sleeping bodies, stats; camera follows the selected object |
| Object | the selected body, changed live: its volume and density (and whether it floats), mass, friction, bounce, rolling friction, air and spin drag, its own gravity; colour, glow, light reach and brightness; stop, launch, delete, duplicate |
| Spawn | what 1-7 drop: shape, size, mass, glow, light; the model library (every file in `assets/` and `assets/models/<folder>/`), one click drops a model |
| Scenes | every scene, physics and orbits; restart; quit |
| Help | every mouse and key control, and live stats |

Click an object to select it; drag it to carry it. The keys still work as
shortcuts: F throw · 1–7 drop · E blast · X delete · G gravity · T slow motion ·
SPACE pause · N step · R restart · O camera · Z/J/C overlays · L shadows · B bloom ·
H help. Drop an `.obj` or `.stl` file on the window to add it. The orbit window has
the same menu, with View (speed, size, names, trails, bloom), Bodies (follow any
body; its mass, distance and speed; the collision log), Scenes and Help.

The window runs at the monitor's refresh rate and shows the GPU it draws on; it
logs the average frame rate when it closes.

| Command (after `sim.jl SCENE`) | What it does |
|---|---|
| *(nothing)* | window, real time: bullet3 gets each frame's time and the drawn poses are interpolated |
| `--headless --seconds 8 --verbose` | no window: progress every simulated second, final positions |
| `--frames 200 --screenshot out.png` | window for exactly 200 frames (fixed stepping, same every run), save the last one |
| `--presim 3` | simulate 3 s before the first frame |

From Julia:

```julia
using ObjectSim
run_headless("scenes/tumble.toml"; seconds = 5)
run_window("scenes/tumble.toml")

with_world("scenes/playground.toml") do w      # destroys the world afterwards
    ball = body(w, "ball[1]")
    apply_impulse!(ball, (0, 5, 0))                # N·s: a 1 kg ball gains 5 m/s
    simulate!(w, 2.0)
    hit = raycast(w, (0, 10, 0), (0, -10, 0))      # what's straight below (0, 10, 0)?
    position(ball), hit.body.name
end
```

Also: `set_velocity!`, `set_gravity!`, `explode!`, `spawn!`, `remove!`,
`add_joint!`, `remove_joint!`, `broken`, `grab!` / `drag!` / `release!`,
`set_body_gravity!`, `contacts`, `touching`, `add_force!`, and the live setters
`set_mass!`, `set_friction!`, `set_restitution!`, `set_rolling_friction!`,
`set_damping!`, `set_look!`, `set_solver_iterations!`, `set_mutual_gravity!`.

A force hook runs your own Julia before every physics step:

```julia
with_world("scenes/playground.toml") do w
    ball = body(w, "ball[1]")
    add_force!(w, (w, dt) -> apply_impulse!(ball, (0, 15 * mass(ball) * dt, 0)))   # a rocket
    simulate!(w, 3)
    [(c.a.name, c.b.name, c.impulse) for c in contacts(w)]
end
```

## Scenes

```toml
[world]
gravity = [0, -9.81, 0]
hz = 120                       # fixed physics steps per simulated second
iterations = 10                # solver passes per step: raise for heavy chains, tall stacks
mutual_gravity = 0             # G > 0: every object attracts every other

[lighting]                     # optional
sun = 1.0                      # main light (casts the shadows); ~0.1 for night
ambient = 1.0
sky = "#1b1d23"

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
repeat = [3, 5, 1]             # a 3 × 5 stack (or: repeat = 10, step = [dx, dy, dz])
friction = 0.7
color = "#c98a3d"
gravity = [0, -1.62, 0]        # its own gravity (here the Moon's), whatever the world's
layer = "debris"               # collision layer …
ignore = ["debris"]            # … and layers it passes through
trigger = false                # true: nothing bounces off it, contacts still reported
glow = 0.0                     # 0-1: self-lit; at 1 it shines and blooms (lamps, lava, stars)
light = 0.0                    # > 0: a point light of its colour reaching this far (m)
light_intensity = 1.5

[[joint]]
type = "hinge"                 # point | hinge | slider | fixed | spring
a = "door"                     # b = "…" for a second body; omit to fix to the world
pivot = [0, 1, 0]              # world coordinates
axis = [0, 1, 0]
limit = [-90, 90]              # degrees (slider: metres)
motor = [45, 10]               # deg/s, strength
break_impulse = 20             # snaps above this

[[joint]]
type = "point"
chain = "link"                 # link[1]–link[2]–… joined at their midpoints
ends = "first"                 # and the first link pinned to the world
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

## Orbits

```sh
julia --project=examples/ObjectSim examples/ObjectSim/orbits.jl examples/ObjectSim/scenes/orbits/solar_system.toml
julia --project=examples/ObjectSim examples/ObjectSim/orbits.jl examples/ObjectSim/scenes/orbits/figure_eight.toml --headless
```

Orbits don't use bullet3. They're Newtonian N-body problems integrated in Float64 by
OrdinaryDiffEq (the ODE solvers of DifferentialEquations.jl) with `DPRKN12`, a
12th-order Runge–Kutta–Nyström method for second-order equations, at 1e-13
tolerances. raylib draws them; bullet3 is for contact physics at human or
rubble-pile scale. Its single-precision floats and fixed steps are the wrong
tool for orbits.

```toml
[system]
units = "solar"                # AU, days, solar masses (G = k²); or "nbody" (G = 1)
merge = true                   # bodies that touch merge, keeping mass and momentum

[[body]]
name = "Earth"
mass = 3.0034e-6
radius = 4.26e-5               # AU, for collisions
orbit = { around = "Sun", a = 1.0, e = 0.0167, i = 0, node = 0, peri = 102.9, M = 357.5 }
# or: position = [...], velocity = [...]
```

| Key | Does |
|---|---|
| SPACE | pause |
| `[` `]` | half / double speed |
| TAB | follow the next body (then back to the centre of mass) |
| L, T | labels, trails |
| B | bloom (the Sun and bright stars glow) |
| drag, wheel | orbit, zoom |

From Julia: `s = OrbitSim(load_orbits(path)); advance_orbits!(s, 365.25)`, then
`orbit_positions(s)`, `energy_drift(s)`, `s.mergers`. Also `elements_to_state`,
`state_to_elements` and `kepler_period`.

How close it gets, measured:
- one Kepler period brings a planet back to within 1e-9 AU of its start;
- energy and angular momentum hold to 1e-10 over 100 orbits;
- the figure-eight returns to its start after its period to within 1e-5.

## Rendering

Both windows share one renderer ([src/render.jl](src/render.jl)), written as GLSL
shaders on top of raylib:

- **Instancing.** Objects that share a mesh, colour and glow are drawn in one
  `DrawMeshInstanced` call (the tumble scene's 48 bodies take 10 calls; the orbit
  window's 3,000 background stars take 3).
- **Shadows.** A depth pass from the light into a 4096² shadow map each frame. It's
  orthographic, centred on what the camera looks at, and sized to the zoom. The main
  shader samples it with 5×5 PCF for soft edges. Off in the orbit window, which has
  no ground to cast onto.
- **Bloom.** The finished frame (4× MSAA) is blitted into a texture, which resolves
  the anti-aliasing; its bright parts are extracted at half resolution, blurred
  (separable Gaussian, three rounds) and added back. The HUD is drawn afterwards,
  so text stays sharp. `glow` objects and the Sun are what bloom most.
- **Lighting.** The physics window uses a slanted directional light (`[lighting] sun`),
  plus up to 16 point lights from objects with `light = range`: each lights everything
  within range in its own colour, fading to nothing at the edge, and moves with its
  object. With more than 16, the ones nearest the camera's target are used. Point
  lights cast no shadows, so lamp light goes through walls; a shadow map per point
  light would be six extra depth renders each. In the orbit window a sun (a body
  ≥ 10× heavier than the next) is a point light at its position.

`run_window(...; shadows = false, bloom = false)` starts without either. On the
RTX 5060 both windows hold 120 fps at 120 Hz with everything on.

## Getting models

ObjectSim reads `.obj` and `.stl` (positions and faces). Put them in a folder under
`assets/models/` and they appear in Spawn → Models. Or drop a file on the window, or
use it in a scene with `shape = "hull"` (moving) or `shape = "mesh"` (static). A
dropped or library model is scaled so its longest side is 1.5 m × the spawn size, and
weighs 500 kg/m³ (it floats) unless the spawn mass is set. Each file is read once a
session, however many copies are made.

In `assets/models/` now (all from NASA 3D Resources except the ship). The folder is
not in git (about 115 MB of third-party files); fetch the models from the sources
below, and the scenes that use them (`mars`, `nebulae`, `harbor`, …) load again:

| Folder | What | Notes |
|---|---|---|
| `perseverance/` | the 40-part Mars 2020 rover print kit | millimetres; parts are in their print positions, not assembled. `mars.toml` assembles the chassis, wheels and RTG at `scale = 0.012` |
| `space/` | Crab Nebula jets 1 and 2; Tycho supernova remnant, outer and inner, left and right halves | millimetres. The two Crab jets share their origin (the pulsar). Each Tycho half lies cut-face down on z = 0; the right half joins the left turned 180° about y, then moved (+3.84, +55.69, 0) mm |
| `ships/` | the steamship Schaarhörn (`schaarhoern.stl`) | z-up, keel at z = 0; `rotation = [-90, 0, 0]` stands it up |

| Where | What | Licence |
|---|---|---|
| NASA 3D Resources (science.nasa.gov/3d-resources) | spacecraft, asteroids, moons, rovers; STL and glTF | NASA media, generally free to use |
| NASA PDS Small Bodies Node | measured shape models of real asteroids and comets (Bennu, Eros, Itokawa, 67P …) | public data |
| DAMIT (Database of Asteroid Models from Inversion Techniques) | thousands of asteroid shapes, convex: exactly what `hull` uses | free for research use; cite |
| Smithsonian 3D (3d.si.edu) | scanned fossils, artefacts, aircraft | many CC0 |
| Kenney (kenney.nl), Quaternius (quaternius.com) | low-poly game kits: furniture, vehicles, nature | CC0 |
| Printables, Thingiverse | anything made for 3D printing; STL | mixed, mostly Creative Commons |
| Morgan McGuire's Computer Graphics Archive (casual-effects.com/data) | the classic test models in OBJ: Stanford bunny, dragon, Sponza … | per model |
| Sketchfab | very large; filter by "downloadable" | per model |

Things to know:
- **Units.** STL files are usually millimetres, so a 50 mm part needs `scale = 0.001`.
  Dropping a file on the window rescales anything far from ~1.5 m automatically.
- **Concave moving objects collide as their convex hull** (a mug's inside is filled).
  Exact concave collision for moving bodies needs convex decomposition (VHACD), which
  is in Bullet's `Extras/` and not in the Hub's build. Static `mesh` scenery uses the
  exact triangles.
- **Textures and materials are ignored.** Colour comes from the scene's `color`.
- **glTF/GLB isn't read yet.** Blender (File → Export → Wavefront OBJ) converts it.
  Very dense scans load slowly with the simple OBJ reader, so decimate them in
  Blender first (Decimate modifier).
- **Keep licences with the files.** CC-BY models need credit, so a `SOURCES.md` next
  to the files is enough.

## Water

A scene with a `[water]` table (or World → Water in the menu) fills everything below
`level` with a liquid of `density` kg/m³. It is a force hook, like mutual gravity:

- Each moving body is split once into small cubes (a grid over its own mesh, about four
  across its thinnest side, at most 400; cubes whose centre is inside the mesh are kept,
  each carrying an equal share of the mesh's volume). Copies of the same shape share one set.
- Before each fixed step, every cube under the surface is pushed up by the weight of the
  water it displaces, ρ·V·g, at its own position, so a body floating tilted is turned
  back upright (or capsized, if it is top-heavy). A cube that straddles the surface
  counts only the part under.
- The same cubes feel drag, ½·ρ·C·A·|v|·v on their own velocity (spin included), so
  things settle instead of bobbing forever and sinking things reach a terminal speed.

Whether something floats is its density, mass ÷ volume, against the liquid's: a 1 m
crate of 1000 kg is neutral in fresh water. The Object tab shows both, and how much of
it is under. Measured: a 500 kg/m³ cube floats with its centre within 5 cm of the
surface; a ball of 194 kg/m³ rides 19% under, as the sphere-cap volume says; a tilted
plank rights itself; the steamship at 40% of its volume floats upright and recovers
from a shove. The cubes follow the visible mesh, not the convex collision hull, so a
ship's hollow-looking hull still displaces only its own solid volume. Waves and
splashing aren't simulated: the surface is flat.

```toml
[water]
level = 0          # surface height, m
density = 1025     # kg/m³ (fresh 1000, sea 1025, oil 900, mercury 13534)
drag = 1.0         # thickness; honey is ~40
color = "#2a6f97"
clarity = 0.55     # 0 clear … 1 opaque
```

From Julia: `set_water!(w, WaterSpec(; level = 0f0, density = 1025f0))`,
`set_water!(w, nothing)` to drain it, and `volume`, `body_volume`, `density`,
`buoyancy_cells`.

## Springs

A spring joint pulls its two pivot points together with F = −k·d − (damper),
computed by ObjectSim before every fixed step and pushed through the bodies'
centres of mass. bullet3's own spring (`btGeneric6DofSpring2Constraint` with
`enableSpring`) was used before, and measuring it showed three problems:

- **Coupled springs ran soft.** bullet3 asks its solver for the velocity the spring
  force would give, and other springs' pushes on the same body count toward it, so a
  spring between two moving masses acted at half its stiffness: two masses on three
  springs ran their opposed mode at ω² = 200 instead of 300, at any number of solver
  passes. Its `BT_6DOF_FLAGS_USE_INFINITE_ERROR` fixes that, but then a damped spring
  applies the larger of its spring and damper forces instead of their sum, and a
  ζ = 0.5 spring stopped bouncing altogether.
- **Hanging masses stopped 2.5–8% low.** That was sleep: bullet3 froze the body
  during its last slow bounces. Springs now keep their bodies awake, as motors do.
- **Stiff springs were softened silently**, with no message.

Measured now (1 kg, 120 Hz unless noted; `test/runtests.jl` "springs" checks these):

| What | Result |
|---|---|
| Period, k = 10 – 900 N/m | 2π√(m/k) within 0.03% |
| Amplitude after 10 s undamped | kept to 0.1%; deviation from a pure sine 3·10⁻⁶ of the amplitude |
| Hanging sag | m·g/k to 0.01%, any mass, stiffness, pivot offset, step rate |
| Stretch 0.2 m and release, undamped | swings ±0.2 m about the rest point at the right period |
| Decay rate, ζ = 0.01 – 0.8 | c/2m exactly (the damper is integrated as e^(−c·dt/m), so it can't overshoot) |
| Damped frequency | 3% high at ζ = 0.5 (from integrating spring and damper one after the other; halves with each doubling of hz) |
| Overdamped creep back | exact while the damping time m/c is ≥ 10 steps; below 3 steps (implicit) within 1% of the exact solution, ζ = 20 at 120 Hz |
| Too stiff for the step (k = 20 000 N/m, 1 kg, 120 Hz: ω·dt = 1.2) | stable, never past v/ω; the ringing dies out within a few steps |
| Sag, k = 20 000 and 10⁶ N/m | m·g/k to 0.1% |
| Two masses, three springs | in-step mode T = 0.6281 s (ideal 0.6283), opposed 0.3624 s (0.3628); one mass started alone splits 0.0502 / 0.0501 into the two modes (0.05 / 0.05), so the energy beats between them |
| Coupled statics, any damping | where the spring matrix says, to 10⁻⁴ m |
| At rest | speeds fall to 10⁻⁹ m/s and below; no jitter |

Stiff and heavily damped springs: no caps, a linear solve instead. Most springs run
as above (explicit, symplectic Euler), which is what keeps periods and energy exact.
A spring that step can't take stably is solved implicitly instead:

- **stiff**: ω·dt over 1/√2, bounded for the whole network (twice the largest Σk/m on
  either of its bodies), well inside symplectic Euler's limit of 2. At 120 Hz that is
  from 7 200 N/m for 1 kg on one spring;
- **heavily damped**: c·dt/m over 0.3 (the damping time shorter than about 3 steps).

All implicit springs are solved together, one linear system over the bodies they touch,
for the push that also accounts for the velocity it causes this step:
(M + Σ wₛ·Lₛ) Δv = b, with wₛ = θ·h²·k + h·c and Lₛ each spring's graph Laplacian.
θ = (a − 1)/a, a being the spring's bound on (ω·dt)², makes the step stable at any
stiffness, and gravity is in the right-hand side, so it settles exactly at m·g/k. A
spring here is isotropic with zero rest length (F = −k·d), so the matrix is the same
for x, y and z and doesn't change with the state. It is factorised once, by Cholesky
(LAPACK while small, CHOLMOD's sparse one above 48 bodies, from Julia's LinearAlgebra
and SparseArrays), until a spring, a mass or the step rate changes, and each step
costs one solve with three right-hand sides. What a too-stiff spring gives up is the
ringing faster than the step can show: it dies out within a few steps. The log says
so once, with the hz that would show it (4·√(k/m)), and World → physics steps per
second raises it live. Before this, ObjectSim capped stiffness at m/(16·dt²) and
damping at m/dt per body, so a stiff spring ran softer than asked (a 20 000 N/m
spring at 120 Hz ran at 900 N/m).

A sweep found no run that gained energy, on either engine: 720 runs each, stiffness
10 – 10⁶ N/m, damping 0 – 1 000 N·s/m, masses 1:1, 1:20, 20:1 and 0.02 kg beads,
60 – 240 Hz, one or ten bodies in a chain, random starting velocities. From Julia,
`spring_stiffness(j)` and `spring_damping(j)` give what a spring runs with (the scene's
values), `spring_implicit(w, j)` whether it is solved implicitly, and
`set_spring!(w, j; stiffness, damping)` changes it live. `scenes/springs.toml` has all
of it to stretch by hand: four masses on one spring, five dampings, two in series and a
bead chain in zero g.

## Per-object rules

| Key | bullet3 | Notes |
|---|---|---|
| `gravity` | `btRigidBody::setGravity` + `BT_DISABLE_WORLD_GRAVITY` | the world's gravity and `set_gravity!` leave it alone |
| `layer`, `ignore` | `addRigidBody(body, group, mask)` | each layer name gets a filter bit; a pair collides only if neither ignores the other |
| `trigger` | `CF_NO_CONTACT_RESPONSE` | contacts are found and reported (`contacts`, C in the window), nothing is pushed |
| `[world] mutual_gravity` | a pre-tick force hook | `gravity_mass` lets a static body attract; such worlds keep every body awake. A tiny `gravity_mass` (`1e-6`) makes a body that is pulled but barely pulls: test particles |
| `[camera] follow` | — | the viewer selects this body and keeps it in the middle (View → camera follows) |

### Mutual gravity

Before every fixed step the hook gathers each body with a gravitating mass
(`gravity_mass`, else `mass`), sums a = G·Σ mⱼ·d/r³ for each in Float64 (no
softening; pairs at r = 0 are skipped) and pushes every moving body by m·a·dt.
Two ways of summing, in [gravity_tree.jl](src/gravity_tree.jl):

- below 2000 bodies, directly: every pair, one SIMD loop per body;
- from 2000, a Barnes–Hut octree rebuilt every step. Each leaf, a group of up to
  32 nearby bodies, walks the tree once. A node of side s is taken whole, as one
  point at its centre of mass, when that point is further than s/θ + δ from the
  whole group (δ: how far the centre of mass sits from the node's middle). A
  nearer node is opened, and a nearer leaf is summed body by body. θ = 0.5.

Both run on threads from 512 bodies when Julia has them, and reuse their buffers,
so once warm the sum allocates nothing (only `Threads.@threads`' tasks).
`ObjectSim.GRAVITY_TREE_FROM[]` moves the switch (1: always the tree; `typemax(Int)`: never)
and `ObjectSim.GRAVITY_THETA[]` sets θ (smaller: closer to the direct sum, slower).

Measured on Jolt, 32 threads, N spheres in a ball in zero g (µs, best of 15–50 runs):

| bodies | gravity, direct | gravity, tree | whole step, direct | whole step, tree |
|---|---|---|---|---|
| 256 | 61 | 74 | 169 | 177 |
| 1024 | 220 | 273 | 437 | 486 |
| 1536 | 337 | 374 | 696 | 658 |
| 2048 | 571 | 524 | 995 | 794 |
| 4096 | 1717 | 1046 | 2753 | 2145 |
| 8192 | 6242 | 2408 | 7539 | 3571 |

On one thread the tree pays from about 800 bodies, and at 8192 it takes 11.7 ms
where the direct sum takes 49 ms.

The tree's error against the direct sum at θ = 0.5, |a_tree − a|/|a| per body:

| bodies | arrangement | median | worst |
|---|---|---|---|
| 1000 | uniform ball | 0.09 % | 1.2 % |
| 8192 | uniform ball | 0.26 % | 4.5 % |
| 1000 | five clumps | 0.02 % | 0.6 % |
| 8192 | five clumps | 0.06 % | 0.7 % |

The worst cases are bodies near a ball's middle, where the pulls nearly cancel
and a small absolute error is a large relative one. At θ = 0.3 the 8192-body
ball's errors are 0.05 % median and 2.1 % worst; at θ = 0.7 they are 0.6 % and 19 %.
The tree's pulls are not exactly equal and opposite, as the direct sum's are, so
total momentum drifts slightly. In a 150-body cloud it stays under 1 % of Σ m|v|.

## Joints

| type | bullet3 class | what it does |
|---|---|---|
| `point` | `btPoint2PointConstraint` | ball and socket: one shared point, free to turn |
| `hinge` | `btHingeConstraint` | turns about one axis; `limit` in degrees, `motor = [deg/s, max impulse]` |
| `slider` | `btSliderConstraint` | moves along one axis without turning; `limit` in metres, `motor = [m/s, max force]` |
| `fixed` | `btFixedConstraint` | welds two bodies; with `break_impulse`, breakable glue |
| `spring` | ObjectSim's own force, on a `btGeneric6DofSpring2Constraint` that keeps the bodies' turning locked | pulls back toward the starting offset; `stiffness` (N/m), `damping` (N·s/m); see Springs below |

A joint's pivot and axis are given in world coordinates as the scene starts, and
ObjectSim converts them into each body's own frame.

Motors keep their scene speed as the reference: `set_motors!(w, f)` (World → Motors)
runs every motor at f × that speed, 0 holding still and negative reversing. The rover
in `mars.toml` is six motorised hinges on a rigid chassis (no rocker-bogie
suspension), so it rocks over bumps rather than keeping all six wheels down.

How close to the textbook it gets, measured:
- **Pendulums** match T = 2π√((L² + ⅖r²)/(gL))·(1 + θ²/16) to 0.1% or better
  with `iterations = 50`. At bullet3's default of 10 solver passes a pendulum
  swinging along X runs ~1% slow, while one swinging along Z is still within
  0.1%: the solver takes the joint's axes in turn. More passes or a smaller
  step remove the difference. The default favours speed, and `iterations` is
  the dial for accuracy.
- **Springs** match Hooke's law and the damped-oscillator solution; see Springs below.
- **Sleep:** bullet3 stops simulating a body that has moved slower than
  0.8 m/s and 1 rad/s for 2 s. That saves work on piles at rest, but it can
  freeze a slow pendulum mid-swing. Give such objects `sleep = false`; Z in the
  window shows what is asleep.

## Physics engines

Two backends, kept apart in `src/backends/`: `jolt/` (the default) and `bullet3/`.
Each one is its engine used its own way; neither imitates the other. Everything
else (scenes, the window, water, springs, mutual gravity, force hooks, layers)
sits on top and talks to whichever one runs through a small set of `_be_*`
functions listed at the top of [physics.jl](src/physics.jl).

Pick one with `[world] backend = "bullet3"` in a scene, `World(scene; backend = "bullet3")`,
`OBJECTSIM_BACKEND=bullet3`, `objectsim --bullet3`, or World → Physics engine in the
menu (it restarts the scene on the other engine). Jolt is the default: in side-by-side
runs its springs keep ringing when other things touch them and a pulled stack falls
naturally, where bullet3's boxes jump apart at a touch.

Speed on Jolt (µs per fixed step, 32-thread machine; before → after the
type-stable backend, the per-step job system choice, the springs' solve and the
SIMD mutual gravity):

| scene | bodies awake | before | after |
|---|---|---|---|
| nebulae | 3 | 95 | 3 |
| night | 7 | 111 | 12.5 |
| springs | 23 | 185 | 17 |
| wrecking_ball | 51 | 207 | 156 |
| rubble (mutual gravity) | 216 | 712 | 330 |
| impact | 128 | 739 | 369 |

The "before" column ran every step on a pool of all cores but one; Jolt's workers
only pay for themselves from a few hundred awake bodies, and past 4 of them its
solver gains nothing (see `JOLT_THREADS` in [backends/jolt/world.jl](src/backends/jolt/world.jl)).

What differs, as each engine does it:

| | bullet3 | Jolt |
|---|---|---|
| threads | one | one thread for small steps, a pool of 4 workers once 250 bodies are awake (`ObjectSim.JOLT_THREADS[]`, `JOLT_POOL_FROM[]`; `JOLT_THREADS[] = 0`: always one thread, deterministic) |
| resting contact | at the surface | sunk by Jolt's penetration slop, 2 cm |
| combining materials | friction a·b, bounce a·b | friction √(a·b), bounce max(a, b) |
| rolling friction | yes | no (the setting is kept and ignored) |
| sleep | under 0.8 m/s for 2 s (freezes slow pendulums) | points under 0.03 m/s for 0.5 s |
| contact reports | every manifold point, kept while bodies sleep, with solver impulses | one row per manifold, awake bodies only; impulse estimated from the closing speed |
| cones | a cone shape | a convex hull of the cone |
| breakable joints | `setBreakingImpulseThreshold` | ObjectSim checks the joint's impulse after each step |
| joined bodies not colliding | per constraint | a group filter table |
| picking | point-to-point constraint, impulse-capped | point constraint to the world, its anchor moved |

Springs, water, mutual gravity and own gravity per body are ObjectSim's own forces,
so they behave the same on both. Every test runs on both engines
(`OBJECTSIM_BACKEND=jolt` for Jolt); the few that check one engine's behaviour or
internals are marked for it.

Jolt goes through its wrapper as Jolt's samples do in C++, every call Jolt's
own, `Vec3`/`Quat` by value included. Contacts come from the Hub shim's
`ContactRecorder`, a C++ listener: Jolt calls listeners from its worker threads,
where a Julia callback can't safely run. Two wrapper details the backend relies on:
- Objects are allocated 64-byte aligned. Some Jolt classes are cache-line
  aligned, and with 16-byte storage their constructors' aligned stores
  segfaulted whenever a block happened not to land on a 64-byte boundary.
- Constraint settings are built as structs with their class's vtable pointer set,
  because the wrapper calls `Create` through the vtable, as C++ does.

## Layout

```
ObjectSim/
├── lib/              bullet3, Jolt and raylib wrappers, copied by vendor.sh (not tracked)
├── src/
│   ├── geometry.jl   TriMesh, primitives, centroid — plain Julia
│   ├── assets.jl     OBJ / STL loading — plain Julia
│   ├── scene.jl      TOML → SceneSpec — plain Julia
│   ├── physics.jl    World, Body, and the backend interface (_be_*)
│   ├── backends/bullet3/  world.jl, joints.jl: the bullet3 engine
│   ├── backends/jolt/     world.jl, joints.jl: the Jolt engine
│   ├── water.jl      buoyancy and drag
│   ├── control.jl    impulses, velocities, gravity, raycasts, spawning
│   ├── interactions.jl  per-object gravity, layers, triggers, contacts, force hooks
│   ├── orbits.jl     N-body orbits (OrdinaryDiffEq, Float64), mergers
│   ├── orbit_viewer.jl  the raylib window for orbits
│   ├── joints.jl     joints and mouse picking
│   ├── render.jl     shaders, instanced batches, shadow map, bloom
│   ├── ui.jl         the immediate-mode menu toolkit (panels, sliders, buttons)
│   ├── app.jl        app(): open scenes by name, move between them
│   ├── viewer.jl     the raylib window for physics scenes
│   └── headless.jl   run_headless
├── scenes/  assets/  test/  sim.jl
```

## Notes on the wrappers

- **Header-only constructors.** `btSphereShape`, `btDefaultMotionState` and
  `btRigidBodyConstructionInfo` are defined only in Bullet's headers. Since
  RepliBuild.jl #105 the build defines them, and they wrap like any constructor
  (`btSphereShape_btSphereShape`, …), each building its object in place.
  So spheres are real `btSphereShape`s, and the construction info starts from
  upstream's own defaults; ObjectSim overrides only what a scene sets.
- **Two transforms per moving body.** `transform` / `position` give the physics
  state after the last fixed step. `render_transform` reads the body's
  `btDefaultMotionState`, which the viewer draws with. bullet3 defaults to
  *latency* interpolation: the drawn pose sits between the previous step and the
  current one, at (last step − dt + leftover time). It is never projected past the
  current step, so nothing is drawn inside a floor it is about to hit. Drawn poses
  run up to one fixed step behind the physics (1/120 s in the sample scene).
  `advance!(w, seconds)` is the variable-timestep call the real-time viewer uses;
  `step!` and `--frames` take whole steps.
- **Inline methods.** `applyCentralImpulse`, `setLinearVelocity`, hinge
  `setLimit` / `enableAngularMotor`, `setPivotB`, `setInternalTickCallback`, the
  contact-manifold accessors and about 2000 others are defined in Bullet's headers
  and called by no library `.cpp`. Since RepliBuild.jl #108 the build defines them,
  and ObjectSim calls them by name. C++ default arguments don't carry over, so
  `setLimit` takes all five. The only fields still written directly are public data
  members that C++ also writes directly (`m_setting` on the picking constraint,
  `getSolverInfo().m_numIterations`).
- **Ahead-of-time thunks.** Every bullet3 method reaches the library through a
  small adapter (a Tier-2 thunk: C++ `this`, references, structs by value). The
  bullet3 recipe sets `[compile] aot_thunks = true`, so they're compiled at build
  time into `libbullet3_thunks.so`, which `vendor.sh` copies alongside. Measured:
  loading ObjectSim takes 2.6 s instead of 11.1 s, and a call costs 7.5 ns with no
  allocation instead of 42 ns. Bullet's own code was always native; raylib is C and
  needs no thunks.
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
julia --project=examples/ObjectSim -e 'using Pkg; Pkg.test()'                         # bullet3
OBJECTSIM_BACKEND=jolt julia --project=examples/ObjectSim -e 'using Pkg; Pkg.test()'  # Jolt
```

314 tests on bullet3, 282 on Jolt (without the bullet3-only checks), the same
physics expectations on both. Below is what they cover.

About 25 s each:
- free fall against the integrator's closed form;
- the header-only constructors: a real sphere, scene values over the real
  defaults, and motion-state interpolation for whole and fractional steps;
- every primitive comes to rest at its own size;
- hull placement and resting contact;
- a ball settles into the concave bowl mesh;
- impulses against Δv = J/m and Δω = I⁻¹(r × J), gravity changes, blasts;
- raycasts (hit point, normal, fraction, misses), spawning and removing;
- picking: a crate carried 2 m up and dropped again;
- joints against physics:
  - a pendulum's period against the physical-pendulum formula;
  - a hinge motor's angle, then its limit;
  - a slider staying on its rail inside its limits;
  - a glued pair landing as one;
  - a spring's sag;
  - one joint snapping at its break impulse while another holds;
- the scene format's joints, chains, line repeats and its errors;
- per-object gravity (Moon vs Earth free fall, balloons), layers passing
  through each other, a trigger reporting contacts, a resting box's contact
  impulses adding up to its weight;
- force hooks, two bodies under mutual gravity (G·m/d², fixed centre of mass),
  a moon's orbit round a static planet in bullet3's single precision;
- the Barnes–Hut tree against the direct sum on random balls and clumps (exact
  as θ → 0; at θ = 0.5 median error under 0.5 %, worst under 10 %), coincident
  bodies, no allocations once warm, and a world forced onto the tree: two bodies
  falling together and a cloud's momentum staying near zero;
- orbits: elements ↔ state, Kepler's third law, energy and angular momentum
  over 100 orbits, the figure-eight's return, a merger keeping mass and
  momentum, ten years of the solar system;
- every scene in `scenes/` runs, and the wrecking ball's chain doesn't stretch;
- determinism and teardown;
- the matrix layout;
- the live setters (a mass change measured through Δv = J/m, bounce heights,
  drag, solver passes, mutual gravity on and off) and scene lookup by name;
- window runs with screenshots: the physics window with shadows and bloom, again
  with both off, every menu tab (the Object tab with a body selected), and the
  orbit window with its menu. They're skipped without a display or with
  `OBJECTSIM_NO_WINDOW=1`.
