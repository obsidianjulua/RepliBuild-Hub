# OdeLab

A stiff-ODE lab: **SUNDIALS CVODE** integrates, **raylib** draws in 3D, and
**Dear ImGui** holds the controls, all three through the Hub's generated
wrappers. Change a parameter, the method or a tolerance, and the run starts over
at once. An attractor's whole trail is re-integrated in the same frame, so its
shape follows the slider while you drag it.

```sh
examples/OdeLab/vendor.sh          # once, and after rebuilding sundials, raylib or imgui
examples/OdeLab/odelab             # the window, on Lorenz
examples/OdeLab/odelab robertson   # lorenz | rossler | pendulum | robertson
examples/OdeLab/odelab -f pendulum # stay attached to the terminal
```

From Julia:

```julia
using OdeLab
OdeLab.run(:robertson)               # the window
trajectory(:lorenz; T = 20)          # no window: t, u, flag, stats, ms
race()                               # Robertson with BDF and with Adams, every step
lyapunov(:lorenz)                    # ≈ 0.905 (Benettin's method)
drift(:pendulum; rtol = 1e-6)        # largest relative energy error over [0, 20]
```

## The systems

| System | What it shows |
|---|---|
| **Lorenz** | Two lobes, chaos above ρ ≈ 24.74. Turn on *second run* to watch two starts 10⁻⁸ apart separate exponentially. *Measure λ* gives the Lyapunov exponent (≈ 0.905). |
| **Rössler** | One fold. Sweep c from 2 to 6 to watch the period doubling. λ ≈ 0.07. |
| **Double pendulum** | Chaos you can see. A second pendulum started 10⁻⁶ rad away soon swings its own way. The energy drift readout is CVODE's own error: compare rtol 1e-10 with 1e-6. |
| **Robertson** | The standard stiff problem. BDF and Adams race from 0 to 4·10¹⁰ with the same Newton solver. BDF finishes in about 1,100 steps, its step growing from 10⁻⁷ to 10⁹. Adams spends its whole budget (20,000 steps) and gets to t ≈ 1,900, because the fastest reaction's stability limit holds its step down. |

## Layout

```
OdeLab/
├── vendor.sh        # copies the three wrappers into lib/
├── odelab           # launcher (detaches; log in ~/.cache/odelab/)
├── lib/             # generated wrappers + .so files, never edited (gitignored)
├── src/
│   ├── OdeLab.jl    # module: loads lib/, exports
│   ├── cvode.jl     # Cvode: one integrator; the only file that calls sundials
│   ├── systems.jl   # the four right-hand sides, parameters, invariants
│   ├── lab.jl       # trajectory, race, separation, lyapunov, drift
│   ├── gui.jl       # Dear ImGui on a raylib window (the platform glue)
│   ├── lines.jl     # trails as GPU line strips
│   └── window.jl    # the app
└── test/runtests.jl # julia --project=examples/OdeLab -e 'using Pkg; Pkg.test()'
```

## How the pieces meet

**CVODE calls back into Julia.** You give CVODE a right-hand side, and it calls
it from inside its own stack hundreds of times per solve. `Cvode` keeps the
Julia function in an `Rhs{F,P}` and passes it through CVODE's `user_data`
pointer. The `@cfunction` takes a `Ref{Rhs{F,P}}`, so it is compiled for each
concrete function, and the call into your `f!` is static.
`u` and `du` are `CVec`s, views onto the N_Vector memory, so an evaluation
allocates nothing (the tests check this over thousands of evaluations). If `f!`
throws, the exception is caught before it can unwind through C. CVODE gets a
failure code and stops, and the exception is rethrown in Julia as a
`CapturedException`.

**imgui on a raylib window.** The imgui package ships a GLFW platform backend,
and it can't be used here. raylib compiles its own GLFW in with hidden
visibility, while libimgui.so links `packages/glfw`'s libglfw.so. Those are two
GLFWs with separate global state, so a raylib window means nothing to imgui's
backend. Only imgui's OpenGL3 renderer is used: it draws into raylib's GL 3.3
context. `gui.jl` takes the platform backend's place, passing raylib's mouse,
wheel, keys and typed characters to imgui each frame as `ImGuiIO_Add*Event`
calls.

**Trails on the GPU.** One `DrawLine3D` call per segment measured about 16 ms a
frame for a 20,000-point trail. Instead, a trail is one vertex buffer (set up
through rlgl) drawn with a single `glDrawArrays(GL_LINE_STRIP)`. The fade along
the trail is computed in the vertex shader from `gl_VertexID`.

## Things found on the way

- **Changing tolerances mid-run crashes CVODE 7.9 unless you re-init.**
  `CVodeSStolerances` sets `cv_e_data = NULL` (cvode.c:724), and only the first
  step after an init sets it again (cvode.c:1128). Call it between steps and the
  next step passes NULL to `cvEwtSet`, which segfaults. `set_tolerances!` calls
  `CVodeReInit` at the current state for that reason. This is upstream
  behaviour, not the wrapper.
- **`advance!` overshoots.** In `CV_NORMAL` mode CVODE steps past `tout` and
  interpolates back. Change `p` after an `advance!` and the change takes effect
  from where CVODE had actually got to. Use `set_stop_time!` to change it at an
  exact time.
- **The context type changed in the wrapper.** The sundials wrapper in
  `packages/sundials/julia` (generated by RepliBuild 4.5.0 on Nov 14) types the
  context as `Ptr{SUNContext}`. `packages/sundials/test.jl` creates it as
  `Ref{Ptr{Cvoid}}`, which that wrapper rejects (MethodError in
  `unsafe_convert`). `test.jl` rewraps before it runs, so whether it fails
  depends on what the current RepliBuild generates.
- **Lyapunov δ.** With Benettin's method at δ = 1e-8, CVODE's own error is a
  few percent of δ each interval, and the Lorenz estimate came out near 1.0. At
  δ = 1e-6 it converges to 0.903–0.905.
