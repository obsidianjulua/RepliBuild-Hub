"""
    OdeLab

A stiff-ODE lab: SUNDIALS CVODE integrates, raylib draws in 3D, Dear ImGui
holds the controls, all three through the Hub's generated wrappers.

```julia
using OdeLab
OdeLab.run()                        # the window: Lorenz, Rössler, double pendulum, Robertson
OdeLab.run(:robertson)              # start on one system
trajectory(:lorenz; T = 20)         # no window: t, u, flag, stats
race()                              # Robertson with BDF and with Adams, every step
lyapunov(:lorenz)                  # ≈ 0.906
```

Layers:
- `lib/` — the generated sundials, raylib and imgui wrappers, copied in by
  `vendor.sh`. Never edited.
- `cvode.jl` — `Cvode`: one CVODE integrator, a Julia right-hand side, the
  calls the lab needs. The only file that touches sundials.
- `systems.jl`, `lab.jl` — the four systems and the windowless API.
- `gui.jl`, `lines.jl`, `window.jl` — the window. Only `run` touches raylib or
  imgui, so everything above runs without a display.
"""
module OdeLab

using Libdl
using RepliBuild   # the generated wrappers dispatch through its JIT

const _LIB = joinpath(@__DIR__, "..", "lib")
for (pkg, file) in (("sundials", "Sundials.jl"), ("raylib", "Raylib.jl"), ("imgui", "Imgui.jl"))
    isfile(joinpath(_LIB, pkg, file)) ||
        error("OdeLab: lib/$pkg/$file is missing — run examples/OdeLab/vendor.sh")
end

include(joinpath(_LIB, "sundials", "Sundials.jl"))
include(joinpath(_LIB, "raylib", "Raylib.jl"))
include(joinpath(_LIB, "imgui", "Imgui.jl"))
import .Sundials as S          # never `using` a generated wrapper: thousands of names
import .Raylib as R
import .Imgui as G

include("cvode.jl")
include("systems.jl")
include("lab.jl")
include("gui.jl")
include("lines.jl")
include("window.jl")

# `run` is not exported: it would shadow Base.run for anyone who says `using OdeLab`.
export Cvode, advance!, onestep!, reinit!, set_tolerances!, set_stop_time!, state, state!, stats,
       free!, flagname, System, Param, SYSTEMS, system, defaults,
       lorenz!, rossler!, pendulum!, robertson!, pendulum_energy, pendulum_bobs,
       trajectory, race, separation, lyapunov, drift

end
