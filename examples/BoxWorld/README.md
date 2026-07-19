# BoxWorld.jl

A small physics-sandbox package built on the RepliBuild-generated Box2D 2.4.1
wrapper — the reference example for **driving a wrapped C++ library from a real
Julia package** rather than a verify script.

```julia
using BoxWorld

w = World()                       # C++ b2World on caller-owned storage
add_ground!(w; y = 0.0)
ball = add_ball!(w, 0.0, 10.0; radius = 0.5)
simulate!(w, 120)                 # 120 Tier-2 MLIR thunk dispatches
body_position(ball)               # ≈ (0.0, 1.0) — resting on the floor
destroy!(w)                       # deterministic teardown (finalizer is the safety net)
```

Or just:

```julia
julia> BoxWorld.run_demo()
```

## Layout

```
BoxWorld/
├── Project.toml        # depends on RepliBuild (the wrapper dispatches through its JIT)
├── lib/                # vendored RepliBuild output — the ABI layer, never edited
│   ├── Box2d.jl
│   ├── libbox2d.so
│   ├── compilation_metadata.json
│   └── thunk_manifest.json
├── src/BoxWorld.jl     # the ergonomic layer — types, lifecycles, defaults
└── test/runtests.jl
```

The package precompiles normally; the wrapper's JIT engine initializes at load
time from its `__init__`. See the RepliBuild documentation page **"Using a
wrapper in your package"** for every pattern this package demonstrates: the
vendoring flow, the JIT lifecycle, precompilation rules, by-value handle
conventions, ctor-only classes, header-inline defaults, abstract-shape
vtables, and finalizer discipline.

## Setup

RepliBuild is not yet registered in General; develop it into the environment:

```julia
using Pkg
Pkg.activate("examples/BoxWorld")
Pkg.develop(path = "/path/to/RepliBuild.jl")
Pkg.instantiate()
Pkg.test()
```
