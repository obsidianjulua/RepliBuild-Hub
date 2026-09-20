# ImguiDemo

Dear ImGui driven entirely from Julia — window, GL context, widgets, and real
pixels — through the RepliBuild wrapper in `lib/`. No C++ host program.

```julia
julia --project=/path/to/RepliBuild.jl
julia> include("src/ImguiDemo.jl"); using .ImguiDemo
julia> ImguiDemo.main()                      # visible window, 120 frames
julia> ImguiDemo.main(visible = false)       # hidden; returns the pixel count
```

Needs a display. Under Hyprland that means Xwayland:
`GLFW_PLATFORM=x11 DISPLAY=:1`.

## What it demonstrates

`lib/libimgui.so` is Dear ImGui **v1.92.9b** core plus the upstream GLFW
platform backend and OpenGL3 renderer backend, compiled from source and wrapped
from DWARF. Every imgui call below is a Tier-2 MLIR AOT thunk; the GLFW and GL
calls are Tier-3 `ccall`s.

Measured on an Arc A750 / Mesa, 900×520, hidden window:

```
frames=90  vtx=292  idx=474  cmdlists=1  non-background pixels=27572
```

Two different claims, asserted separately in `test/`:

- `TotalVtxCount > 0` proves imgui **built** geometry — that the wrapper drove
  the API correctly.
- `glReadPixels` finding non-background pixels proves the GPU **drew** it —
  that the renderer backend and the GL context actually work.

They fail for different reasons, so the suite checks both.

## Two things that look like bugs and are not

**The first frame emits nothing.** `vtx == 0`, `cmdlists == 0`. imgui settles
its font atlas during frame 1; geometry appears from frame 2. This is upstream
behaviour and the test asserts it rather than working around it — if upstream
ever changes, the assertion says so instead of leaving a blank-first-frame
mystery.

**Widget state lives in the caller.** `_SLIDER` and `_CHECK` are `Ref`s that
imgui reads and writes every frame. That is the immediate-mode contract, not a
wrapper quirk: there is no retained widget tree to hold the value.

## Two Hub packages, one library

Both wrappers here are RepliBuild output: `Imgui.jl` over imgui core +
backends, and `Glfw.jl` over GLFW (124/124 of the public API). They share **one**
`libglfw.so`, and that is load-bearing rather than tidy.

GLFW keeps process-global state. Bind imgui to the distro `/usr/lib/libglfw.so.3`
while `Glfw.jl` drives its own copy and both map into the session — measured,
they did — with `glfwInit()` on one not initialising the other. A `GLFWwindow*`
created through the wrapper and handed to `ImGui_ImplGlfw_InitForOpenGL` (inside
libimgui.so, bound to the other copy) is undefined behaviour.

`packages/imgui` is therefore linked against `packages/glfw`'s output via
`[link] link_dirs`. **`-L` alone would not have been enough**: RepliBuild's
output carries no SONAME, so the recorded `DT_NEEDED` is a bare `libglfw.so` and
the loader finds `/usr/lib` first — the build succeeding against one copy while
the process runs against another, silently. `get_link_flags` now emits
`-Wl,-rpath` for every `link_dir` alongside `-L`, so runtime resolution follows
build-time resolution.

`$ORIGIN` leads the rpath and `Glfw.jl` resolves its library sibling-first, so
both land on `lib/libglfw.so` and this directory is self-contained. Verified:

```
libglfw copies mapped: 1
   examples/ImguiDemo/lib/libglfw.so
```

Check any time with `ldd lib/libimgui.so | grep glfw` — it must say `lib/`, not
`/usr/lib`.

One consequence: **imgui's build is now order-dependent on glfw.** Build
`packages/glfw` first, or imgui's link fails with `cannot find -lglfw`.

## Layout

```
ImguiDemo/
  src/ImguiDemo.jl   the app: Glfw wrapper, GL readback, frame loop, widgets
  test/runtests.jl   18 asserts; skips cleanly with no DISPLAY
  lib/               vendored RepliBuild output — gitignored
  Project.toml
```

`lib/` holds `Imgui.jl`, `libimgui.so`, `libimgui_thunks.so`, `Glfw.jl`,
`libglfw.so` and the metadata JSONs. It is build output and is never committed
— see the Hub `.gitignore`. Regenerate by building `packages/glfw` then
`packages/imgui` and copying both packages' artifacts here.
