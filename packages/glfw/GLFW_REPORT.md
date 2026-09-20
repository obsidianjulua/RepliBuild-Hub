# GLFW 3.5.1 Hub wrap

Pinned: tag `3.5.1` → commit `d9d6f0f1f967807ffade6598ea9a631ebaf37a56`
(annotated tag object `70a9bb3881fe80fd483236e2b203cb451c6ecf40`).
Package: `packages/glfw/`. Engine (`RepliBuild.jl/src/`) was not patched.

The distro `libglfw.so.3.5` has **no** `.debug_info`. This wrap is a source
build with RepliBuild's auto-`-g`. `readelf -S` on the Hub `.so` shows
`.debug_info` + `.debug_abbrev`; the same command on `/usr/lib/libglfw.so.3.5`
prints nothing.

## Platform decision: X11-only

**Chose X11-only** (`-D_GLFW_X11`). Did **not** harvest Wayland.

GLFW 3.5.1's Wayland backend is a **build-time code generator**:
`src/CMakeLists.txt` `add_custom_command`s `wayland-scanner` over nine XML
files under `deps/wayland/` to emit `*-client-protocol.h`. Those headers are
not in git. RepliBuild's resolver cannot run a generator, and a cmake
configure-only harvest is empty here because the custom commands run at
*build*, not at generate. That is the same class the Hub treats as out of
scope for `cmake_probe` (libpng-style build-rule generation).

X11 needs no generated headers. `_GLFW_X11` is the single platform gate
GLFW requires — compiling every platform's TUs at once will not link.
`DISPLAY=:1` (Xwayland) is up on this box; the imgui backends probe already
ran under `GLFW_PLATFORM=x11`.

Wayland TUs excluded by substring `"wl_"`. Win32 / WGL / macOS time likewise.
The **null** backend stays — it is part of GLFW's always-compiled core, not
an alternate platform.

Native APIs (`glfw3native.h`) were **not** opted into via public compile
defines. They still appear for X11/GLX/EGL/OSMesa because GLFW's own
`platform.h` sets `GLFW_EXPOSE_NATIVE_X11` / `_GLX` / `_EGL` / `_OSMESA`
when `_GLFW_X11` is on. Win32/Cocoa/Wayland natives are absent (those
backends were not compiled).

## Manifest

`packages/glfw/replibuild.toml`

- `[compile] flags`: `-O2 -fPIC -std=c99 -D_GLFW_X11 -D_DEFAULT_SOURCE`
  (`_DEFAULT_SOURCE` is what upstream injects on Linux so `-std=c99` does
  not hide POSIX 2008). **No** `-fvisibility=hidden` (GLFWAPI is a
  visibility attribute only under `_GLFW_BUILD_DLL`; the flag without that
  define hides the whole API).
- `include_dirs`: clone `include/` first, so `GLFW/glfw3.h` is not the
  distro copy at `/usr/include/GLFW/glfw3.h`.
- `link_libraries = ["m", "pthread", "dl", "rt"]`. X11/GLX/GL are dlopened
  at runtime (`posix_module.c`). The linker `--as-needed`'d pthread/dl/rt
  away; `readelf` NEEDED is `libm.so.6` + `libc.so.6` (same shape as the
  distro `.so`).
- `[wrap] exclude_symbols = ["_glfw*"]`. Without hidden visibility DWARF
  sees 393 functions; 235 of those are `_glfw*` internals. Filtered at wrap
  time, no recompile.
- 18 `[wrap.macros.*]` value macros the test actually calls. Key-code soup
  (`GLFW_KEY_A`, …) is omitted; add a name when a caller needs it. Macro
  shims compile as a 24th TU (`replibuild_shims.c`).

23 GLFW TUs compiled (core + null + posix + linux joystick + X11/GLX/xkb).
`sources: 24` with the shim TU.

## Wrapped function count vs the 124

`glfw3.h` has **124** `GLFWAPI` functions. **124 / 124 present. All Tier 3
`ccall`.** Zero Tier 2, zero Tier 1.

| | count |
|---|---|
| DWARF functions (pre-filter) | 393 |
| dropped by `exclude_symbols = ["_glfw*"]` | 235 functions + 2 globals |
| `glfw*` in `libglfw.so` (`nm -D`) | 140 = 124 public + 16 native |
| `invoke_aot_ptr` sites | 0 |
| `test_deep.jl` | **38/38** |

Native symbols that *did* wrap (not in the 124, all Tier 3):

`glfwGetX11Display`, `glfwGetX11Window`, `glfwGetX11Adapter`,
`glfwGetX11Monitor`, `glfwSetX11SelectionString`, `glfwGetX11SelectionString`,
`glfwGetGLXContext`, `glfwGetGLXWindow`, `glfwGetGLXFBConfig`,
`glfwGetEGLDisplay`, `glfwGetEGLContext`, `glfwGetEGLSurface`,
`glfwGetEGLConfig`, `glfwGetOSMesaColorBuffer`, `glfwGetOSMesaDepthBuffer`,
`glfwGetOSMesaContext`.

Native symbols that did **not** (backend not compiled): Win32, WGL, Cocoa,
NSGL, Wayland (11 functions).

## Missing or unusable from Julia

Nothing in the 124 is missing as a Julia method. Caveats:

| Item | Status |
|---|---|
| `GLFW_KEY_*` / `GLFW_MOUSE_BUTTON_*` / most hint tokens | **not wrapped** — value macros, not functions. The 18 in the toml (`GLFW_VISIBLE`, `GLFW_TRUE`, platform ids, …) exist as `Glfw.GLFW_VISIBLE()::Cint`. The rest are header integers; add `[wrap.macros.NAME] ret = "int"` when needed. |
| Function-pointer *types* (`GLFWkeyfun`, …) | **no Julia typedef**. Parameters are `cbfun::Any` / `Ptr{Cvoid}`. The generated docstring says `function_ptr(void)*` for every callback, which is wrong. Real signatures are in `glfw3.h`. `@cfunction` with those signatures works — see below. |
| `glfwCreateWindow` return | `Ptr{Cvoid}`, not `Ptr{GLFWwindow}`. Convert: `Ptr{Glfw.GLFWwindow}(raw)`. Arguments that *take* a window already ccall as `Ptr{GLFWwindow}`. |
| `glfwGetMonitors` | returns `Ptr{Ptr{Cvoid}}` (array of opaque monitor pointers), not `Ptr{Ptr{GLFWmonitor}}`. Walk with `unsafe_load`. |
| Vulkan trio (`glfwCreateWindowSurface`, `glfwGetInstanceProcAddress`, `glfwGetPhysicalDevicePresentationSupport`, plus `glfwInitVulkanLoader`) | wrapped. `VkResult` is GLFW's own DWARF enum (no `vulkan.h` at compile). Needs a real Vulkan loader at the call site; not exercised here. |
| Window-size / framebuffer callbacks on a **never-mapped** window | GLFW/X11 does not send ConfigureNotify if `GLFW_VISIBLE=false` from creation. `glfwSetWindowSize` still updates the stored size (tested); the callback does not fire. Not a wrap bug. |
| `glfwGetKey(NULL, …)` | asserts (`NDEBUG` off, matching imgui). Programmer errors abort instead of returning. Use an invalid `glfwWindowHint` to exercise the error callback without aborting. |

## Callbacks: exact Julia spelling, and proof one fired

Every `glfwSet*Callback` takes the function pointer as `::Any` and ccalls it
as `Ptr{Cvoid}`. The function **must** be a top-level, non-closure method
(`@cfunction` rule).

Error callback — this is the one `test_deep.jl` fires:

```julia
function jl_error(code::Cint, desc::Cstring)::Cvoid
    # ...
    return nothing
end

ecb = @cfunction(jl_error, Cvoid, (Cint, Cstring))
Glfw.glfwSetErrorCallback(ecb)
Glfw.glfwWindowHint(Cint(-1), 0)   # GLFW_INVALID_ENUM, no assert
# ERR_HITS[] >= 1
```

Measured: **2/2 asserts in the "Error callback from Julia @cfunction" testset
passed.** `ERR_HITS >= 1` and `LAST_ERR != GLFW_NO_ERROR`.

Window-size callback (installs, does not fire while unmapped):

```julia
function jl_winsize(window::Ptr{Glfw.GLFWwindow}, width::Cint, height::Cint)::Cvoid
    return nothing
end

cb = @cfunction(jl_winsize, Cvoid, (Ptr{Glfw.GLFWwindow}, Cint, Cint))
Glfw.glfwSetWindowSizeCallback(window, cb)
```

Key callback (same pattern; not fired in the test — no synthetic X11 keys):

```julia
function jl_key(window::Ptr{Glfw.GLFWwindow},
                key::Cint, scancode::Cint, action::Cint, mods::Cint)::Cvoid
    return nothing
end

kcb = @cfunction(jl_key, Cvoid, (Ptr{Glfw.GLFWwindow}, Cint, Cint, Cint, Cint))
Glfw.glfwSetKeyCallback(window, kcb)
```

`test_deep.jl` also: `glfwInit` → hidden 1280×720 window → `glfwGetWindowSize`
reads 1280×720 → `glfwSetWindowSize(640,480)` → `glfwGetWindowSize` reads
640×480 → destroy → terminate. **38/38**.

## Coupling with `packages/imgui`

**(a) Hub GLFW is standalone. imgui keeps linking the distro `libglfw.so.3`.**
Do not mix them in one process.

imgui's `[link] link_libraries = ["glfw", "GL"]` resolves to
`/usr/lib/libglfw.so.3`. Pointing imgui at the Hub `.so` would make imgui's
build order-dependent on this package and would change `libimgui.so`'s
DT_NEEDED / rpath. Not done.

Verified, one Julia process:

1. `include` Hub `Glfw.jl` → `/proc/<pid>/maps` has **only**
   `packages/glfw/julia/libglfw.so`.
2. Then `include` `Imgui.jl` → maps gain **`/usr/lib/libglfw.so.3.5`**.
   Both copies stay mapped.
3. `Glfw.glfwInit()` still returns 1 against the Hub copy;
   `Glfw.glfwGetPlatform()` is `GLFW_PLATFORM_X11` (0x00060004). That init
   does **not** initialise the copy `libimgui.so` is bound to. Passing a
   `GLFWwindow*` from one to `ImGui_ImplGlfw_InitForOpenGL` on the other is
   undefined.

`ldd` on `libimgui.so`: `libglfw.so.3 => /usr/lib/libglfw.so.3`.
`ldd` on Hub `libglfw.so`: no libglfw (it *is* glfw).

Use Hub `Glfw` **or** imgui's system GLFW, not both.

## `ldd` / `readelf -d` on the Hub `.so`

`packages/glfw/julia/libglfw.so` (854 KB):

```
NEEDED  libm.so.6
NEEDED  libc.so.6
```

`ldd` additionally shows `linux-vdso` and `ld-linux-x86-64.so.2`. X11/GL are
not NEEDED; they are `dlopen`'d. `.debug_info` is present.

## Engine limitations (described, not patched)

1. **Callback typedefs collapse to `Ptr{Cvoid}`** with a generated comment
   `function_ptr(void)*` that does not name the real argument list. DWARF
   has the signature (`FunctionPointers.jl` exists) but the C generator
   still emits `Any`/`Ptr{Cvoid}`. A `@cfunction` with the *header*
   signature works; the wrapper just does not tell you what that is. Same
   shape as sqlite's exec callback. Not GLFW-specific, not patched.

2. **Opaque pointer returns become `Ptr{Cvoid}`** (`glfwCreateWindow`,
   `glfwGetMonitors`) while parameters of the same C type ccall as
   `Ptr{GLFWwindow}`. Convert at the call site. Packaging cannot fix this.

3. **Value macros are shims, not DWARF.** They need a rebuild of
   `replibuild_shims.c`. Only names listed in the toml exist. This is the
   documented Hub residue path, not a bug.

4. **Unfiltered DWARF is 393 functions.** `_glfw*` internals are real
   symbols because we did not use `-fvisibility=hidden` (trap 6).
   `exclude_symbols` trims the Julia surface; `compilation_metadata.json`
   still has the full list. Correct.

5. **No AOT / no Tier 1.** GLFW is a flat C ABI; every public function is
   ccall. `aot_thunks` was left off. The two-pass AOT refusal did not apply.
