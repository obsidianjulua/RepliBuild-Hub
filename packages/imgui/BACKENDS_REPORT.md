# imgui GLFW + OpenGL3 backends

Pinned upstream: Dear ImGui **v1.92.9b**
(`f1cc2ae15e53a861a874c3034aae6798fde194ab`).
Package dir: `packages/imgui/`. Engine was not patched.

## What changed in the manifest, and why

File: `packages/imgui/replibuild.toml`.

**1. `[dependencies.imgui] exclude` — drop the blanket `"backends"`.**

Exclude matching is `file == ex || startswith(rel, ex) || endswith(rel, ex) || occursin(ex, rel)` against the path relative to the clone root. A bare `"backends"` therefore dropped *every* file under `backends/`, including the two TUs we want.

Replaced with `examples`, `misc/freetype` (unchanged), plus the 17 backend `.cpp` files that need SDKs not on this box:

`imgui_impl_allegro5.cpp`, `imgui_impl_android.cpp`, `imgui_impl_dx9.cpp`,
`imgui_impl_dx10.cpp`, `imgui_impl_dx11.cpp`, `imgui_impl_dx12.cpp`,
`imgui_impl_glut.cpp`, `imgui_impl_null.cpp`, `imgui_impl_opengl2.cpp`,
`imgui_impl_sdl2.cpp`, `imgui_impl_sdl3.cpp`, `imgui_impl_sdlgpu3.cpp`,
`imgui_impl_sdlrenderer2.cpp`, `imgui_impl_sdlrenderer3.cpp`,
`imgui_impl_vulkan.cpp`, `imgui_impl_wgpu.cpp`, `imgui_impl_win32.cpp`.

Kept (not listed): `backends/imgui_impl_glfw.cpp`, `backends/imgui_impl_opengl3.cpp`.
Metal is `.mm` and is never a compile candidate. `examples/` is also a walkdir skip.

**2. `[compile] include_dirs` — put `backends/` on the include path.**

The resolver auto-adds `<clone>`, `<clone>/include`, `<clone>/src` only. The two backend TUs `#include "imgui_impl_glfw.h"` / `"imgui_impl_opengl3.h"` from `backends/`. Path is package-relative because `build()` cds there:

```toml
include_dirs = [".replibuild_cache/deps/imgui/backends"]
```

`imgui.h` still resolves from the clone root. GLFW's own headers come from the system (`/usr/include/GLFW/glfw3.h` after `pacman -S glfw`). The OpenGL3 backend ships `imgui_impl_opengl3_loader.h`; no glad/GLEW/glbinding was added.

**3. `[link] link_libraries = ["glfw", "GL"]`.**

Uniform flag set, so this is how `libimgui.so` grows a runtime dependency on both. Consequence: a caller who only wanted headless widgets now `dlopen`s `libglfw.so.3` and `libGL.so.1` with the imgui library. Headless `test_deep.jl` still loads and passes (see below); it just pulls those two `.so`s in.

`[compile] flags` stayed `["-O2", "-fPIC", "-std=c++17"]`. No `-fvisibility=hidden`.

**Environment:** GLFW was not installed. Installed `glfw 1:3.5.1-1` (`sudo pacman -S glfw`). GL headers were already present (mesa 26.2.3 + libglvnd). X11 and Wayland headers are present, so `imgui_impl_glfw.cpp` did **not** define `IMGUI_IMPL_GLFW_DISABLE_X11` / `_WAYLAND`.

## Build / wrap

`RepliBuild.build` + `wrap` run twice against this toml, Julia
`--project=/home/john/Desktop/Projects/RepliBuild.jl`.

Pass 1 compiled **9** TUs (was 7: the six imgui sources + `imgui_stdlib` + `binary_to_compressed_c`, plus the two backends):

```
sources: 9  includes: 2
compile: 9 files
link: libimgui.so (6.76 MB)
dwarf: 1411 functions, 256 types
aot: libimgui_thunks.so (931.5 KB)
```

Wrap then refused, as expected for an AOT surface change:

```
AOT thunks library is missing 29 of 1321 symbol(s)
The thunk manifest has been UPDATED (1307 → 1336 symbol(s))
```

The 29 missing names were the new backend thunks (28 `ImGui_Impl*` + `ImVector<ImGui_ImplGlfw_WindowToContext>::~ImVector`). Not a bug.

Pass 2: compile cache hit, AOT rebuilt `libimgui_thunks.so` (955.3 KB) from the updated manifest, wrap wrote `julia/Imgui.jl`.

No other backend `ImGui_Impl*` symbols in `libimgui.so` (`nm -D`).

## Counts

| | before (core only, `Imgui.jl.prev`) | after (core + glfw + opengl3) |
|---|---|---|
| DWARF functions | 1377 | **1411** (+34) |
| Tier-2 `invoke_aot_ptr` sites | 1323 | **1352** (+29) |
| `@ccall LIBRARY_PATH` (varargs / printf-family) | 85 | **85** (unchanged) |
| `test_deep.jl` | 202/202 | **202/202** (2.3s) |

The +34 DWARF functions split as:

- 20 `ImGui_ImplGlfw_*`
- 8 `ImGui_ImplOpenGL3_*`
- 5 `imgl3w*` (embedded GL loader from `imgui_impl_opengl3_loader.h`)
- 1 `ImVector<ImGui_ImplGlfw_WindowToContext>::~ImVector`

The +29 Tier-2 sites are exactly the 29 symbols the first wrap refused (28 `ImGui_Impl*` + the `ImVector` dtor). The 5 `imgl3w*` functions are **Tier 3** `ccall((:name, LIBRARY_PATH), …)` — not `@ccall`, so they do not move the 85-count. No backend `ImGui_Impl*` function is Tier 3.

## Backend surface in `julia/Imgui.jl`

Every `ImGui_ImplGlfw_*` / `ImGui_ImplOpenGL3_*` **function** is **Tier 2 AOT** (`invoke_aot_ptr`). Opaque `struct GLFWwindow end` / `struct GLFWmonitor end` are generated; methods take `window::Any` and the docs name `Ptr{GLFWwindow}`. Passing a `Ptr{Cvoid}` from `ccall(:glfwCreateWindow, …)` works — the AOT marshal boxes the pointer in a `Ref` and hands the thunk a `void**` slot.

### `ImGui_ImplGlfw_*` — 20 functions, all Tier 2

| Julia name | C++ signature |
|---|---|
| `ImGui_ImplGlfw_InitForOpenGL` | `(GLFWwindow*, bool) -> bool` |
| `ImGui_ImplGlfw_InitForVulkan` | `(GLFWwindow*, bool) -> bool` |
| `ImGui_ImplGlfw_InitForOther` | `(GLFWwindow*, bool) -> bool` |
| `ImGui_ImplGlfw_Shutdown` | `()` |
| `ImGui_ImplGlfw_NewFrame` | `()` |
| `ImGui_ImplGlfw_InstallCallbacks` | `(GLFWwindow*)` |
| `ImGui_ImplGlfw_RestoreCallbacks` | `(GLFWwindow*)` |
| `ImGui_ImplGlfw_SetCallbacksChainForAllWindows` | `(bool)` |
| `ImGui_ImplGlfw_WindowFocusCallback` | `(GLFWwindow*, int)` |
| `ImGui_ImplGlfw_CursorEnterCallback` | `(GLFWwindow*, int)` |
| `ImGui_ImplGlfw_CursorPosCallback` | `(GLFWwindow*, double, double)` |
| `ImGui_ImplGlfw_MouseButtonCallback` | `(GLFWwindow*, int, int, int)` |
| `ImGui_ImplGlfw_ScrollCallback` | `(GLFWwindow*, double, double)` |
| `ImGui_ImplGlfw_KeyCallback` | `(GLFWwindow*, int, int, int, int)` |
| `ImGui_ImplGlfw_CharCallback` | `(GLFWwindow*, unsigned)` |
| `ImGui_ImplGlfw_MonitorCallback` | `(GLFWmonitor*, int)` |
| `ImGui_ImplGlfw_Sleep` | `(int)` |
| `ImGui_ImplGlfw_GetContentScaleForWindow` | `(GLFWwindow*) -> float` |
| `ImGui_ImplGlfw_GetContentScaleForMonitor` | `(GLFWmonitor*) -> float` |
| `ImGui_ImplGlfw_KeyToImGuiKey` | `(int, int) -> ImGuiKey` (undocumented in the header, not `static`) |

### `ImGui_ImplOpenGL3_*` — 8 functions, all Tier 2

| Julia name | C++ signature |
|---|---|
| `ImGui_ImplOpenGL3_Init` | `(char const* glsl_version) -> bool` |
| `ImGui_ImplOpenGL3_Shutdown` | `()` |
| `ImGui_ImplOpenGL3_NewFrame` | `()` |
| `ImGui_ImplOpenGL3_RenderDrawData` | `(ImDrawData*)` |
| `ImGui_ImplOpenGL3_CreateDeviceObjects` | `() -> bool` |
| `ImGui_ImplOpenGL3_DestroyDeviceObjects` | `()` |
| `ImGui_ImplOpenGL3_UpdateTexture` | `(ImTextureData*)` |
| `ImGui_ImplOpenGL3_InitLoader` | `() -> bool` (called by Init; not in the public header) |

**Backend function split: 28 Tier 2 / 0 Tier 3.**

No backend function is variadic. None needed a `[wrap.varargs]` entry.

### Extra wrap surface (not the documented imgui backend API)

The embedded loader is compiled into `libimgui.so` and DWARF therefore wraps it as **Tier 3 ccall**:

- `imgl3wInit`, `imgl3wInit2`, `imgl3wShutdown`, `imgl3wIsSupported`, `imgl3wGetProcAddress`
- plus globals/types `imgl3wProcs`, `ImGL3WProcs`, `ImGL3WProcs_gl`

Internal backend blobs also became Julia structs: `ImGui_ImplGlfw_Data` (256-byte blob), `ImGui_ImplGlfw_WindowToContext`, `ImGui_ImplOpenGL3_Data`, `ImGui_ImplOpenGL3_RenderState`. Normal use does not call these.

## Missing or unusable from Julia

| Entry | Status | Why |
|---|---|---|
| `ImGui_ImplGlfw_InstallEmscriptenCallbacks` | **absent** | `#ifdef __EMSCRIPTEN__` — this is Linux. Not a wrap gap. |
| `ImGui_ImplOpenGL3_GetRenderState` | **absent as a function** | `static inline` in the header; never a `.so` symbol. Equivalent: read `GetPlatformIO().Renderer_RenderState` during `RenderDrawData`. |
| GLFW itself (`glfwInit`, `glfwCreateWindow`, …) | **not wrapped** | Packaging, not engine. `libimgui.so` *links* libglfw; it does not re-export GLFW. A Julia caller ccalls `libglfw` (measured below). |
| `GLFWwindow*` / `GLFWmonitor*` | **opaque but usable** | Empty Julia structs. Pass the pointer `glfwCreateWindow` returned. Not a blocker. |
| `ImGui_ImplGlfw_InitForVulkan` | **wrapped, only half useful** | Inits the GLFW *platform* backend for a Vulkan client API. `imgui_impl_vulkan.cpp` is still excluded, so there is no renderer to pair it with. |
| Backend callbacks as *Julia* GLFW hooks | **usable two ways** | `InitForOpenGL(window, true)` installs imgui's C callbacks for you (this is what the probe did). `install_callbacks=false` means you must `ccall` `glfwSet*Callback` with `@cfunction` thunks that forward to `ImGui_ImplGlfw_*Callback` — GLFW API, not imgui. |
| `imgl3wInit2`'s `proc` callback | **awkward** | Generated `@cfunction` hint is wrong (`(Cvoid,)`). Don't call the loader yourself; `ImGui_ImplOpenGL3_Init` already does. |

Nothing in the backend headers is a `...` variadic, so there is no `[wrap.varargs]` hole here.

## A real window + GL frame from Julia

**Yes.** One Julia process, no C++ host:

1. `ccall` GLFW (`libglfw`): `glfwInit` → hidden 1280×720 GL 3.3 core window → `glfwMakeContextCurrent`.
2. Wrapped imgui: `CreateContext` → `ImGui_ImplGlfw_InitForOpenGL(window, true)` → `ImGui_ImplOpenGL3_Init(C_NULL)`.
3. Two frames: `ImplOpenGL3_NewFrame` / `ImplGlfw_NewFrame` / `NewFrame` / `Begin`+`Text`+`Button` / `End` / `Render` / `ImplOpenGL3_RenderDrawData` / `glfwSwapBuffers`.

Measured (`GLFW_PLATFORM=x11`, `DISPLAY=:1`, window `GLFW_VISIBLE=false`):

```
ImplGlfw_InitForOpenGL -> true
ImplOpenGL3_Init      -> true
frame 1  Valid=true vtx=0   idx=0   cmds=0
frame 2  Valid=true vtx=142 idx=237 cmds=1
PROBE_RENDERED=yes
```

Frame 1 producing no geometry is upstream imgui (font atlas warm-up), same as the headless path. Not a bug. `RenderDrawData` did not crash on either frame.

What is still *not* a Hub package: GLFW. Constants (`GLFW_CONTEXT_VERSION_MAJOR`, …) and `glfwCreateWindow` were hand-spelled as `ccall`s. A full app also typically `glClear`s / `glViewport`s; this probe skipped those and the default framebuffer was enough for `RenderDrawData`. The leaked `imgl3w` procs are a possible GL entry if you want one without another library — they are not the documented path.

Headless still works: `test_deep.jl` **202/202**, no window, no backend init.

## `libimgui.so` runtime dependencies

`readelf -d` NEEDED (direct):

```
libglfw.so.3
libGL.so.1
libstdc++.so.6
libm.so.6
libgcc_s.so.1
libc.so.6
```

`ldd` additionally shows the GL/X11 chain pulled by those two: `libGLdispatch.so.0`, `libGLX.so.0`, `libX11.so.6`, `libxcb.so.1`, `libXau.so.6`, `libXdmcp.so.6`.

Before this change, `libglfw` and `libGL` were not on the NEEDED list. `libimgui_thunks.so` is a companion (955 KB); it rpaths to the same directory.

## Engine limitations (described, not patched)

1. **AOT two-pass after a surface change.** First wrap refused with 29 missing `_mlir_ciface_*_thunk` symbols and rewrote `julia/thunk_manifest.json` (1307 → 1336). Second `build()`+`wrap()` bound them. This is the documented `_assert_aot_thunks_present` behaviour, not an imgui special case.

2. **C++ backend functions are all Tier 2, including `Sleep(int)`.** The wrapper comment is the generic “Complex ABI / Packed / Union”; the real reason is C++ mangled ciface, not `GLFWwindow*`. Not a defect — the AOT path is what imgui already opted into with `aot_thunks = true`.

3. **DWARF wraps the embedded GL loader and backend-private structs.** `imgl3w*` and `ImGui_ImplGlfw_Data` et al. are not imgui's public API, but they have symbols/types, so they appear in `Imgui.jl`. `[wrap] exclude_symbols` could trim them at wrap time without recompiling; it was left alone so this report measures the raw surface.

4. **`parameters_source: inferred` on zero-arg backend functions** (`NewFrame`, `Shutdown`, `InitLoader`, `CreateDeviceObjects`, …). Wrappers are still zero-arg and correct. Same inference path core imgui already lives with.

5. **No library-specific workarounds were put in `RepliBuild.jl/src/`.** Pre-existing wrap warnings (unversioned `[wrap.varargs]`, `ImFormatString*` base-only, `ImGuiInputTextCallbackData` opaque, TreeNode overload collapse) are unchanged and unrelated to the backends.

6. **One `.so` now DT_NEEDs GLFW+GL.** That is the packaging choice the job asked for (backends call imgui core symbols directly). Splitting backends into a second library would be a different Hub package, not an engine fix.
