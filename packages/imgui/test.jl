#!/usr/bin/env julia
# Dear ImGui Hub package — integration test
#
# Tests the full RepliBuild pipeline for Dear ImGui 1.92.9b (C++):
#   reset outputs → build → load wrapper → exercise API
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/imgui/test.jl
#
# NON-DESTRUCTIVE to the SOURCE. `reset_outputs!` below deletes only what this
# package generates — build/, julia/, .debug/ — and the content-hash marker. The
# vendored git clone under .replibuild_cache/deps/ is preserved, so this
# recompiles the six C++ translation units (~30s) without going back to GitHub
# and without needing the network. `RepliBuild.clean` would take the clone too.
# Reach for test_deep.jl when the question is only "does the wrapper work".
#
# imgui is a UI library with no backend here (backends/ and examples/ are
# excluded by replibuild.toml — they need GLFW/SDL/DX/Vulkan/GL headers), so
# every frame in this file runs HEADLESS:
#   • ImGuiBackendFlags_RendererHasTextures tells 1.92 that the caller manages
#     textures, which is what lets ImFontAtlas build itself with no renderer
#     attached. Without it NewFrame asserts on an unbuilt atlas.
#   • io.IniFilename = NULL keeps imgui from writing imgui.ini next to the repo.
#   • DisplaySize/DeltaTime are the only other NewFrame preconditions.
# Render() then fills ImDrawData, which is where the assertions land: geometry
# counts are the observable output of a UI library that is never displayed.
#
# NOTE (generator finding, logged not worked around): a `::Ref{ImVec2}`
# parameter must be handed a raw `Ptr{ImVec2}`, never a `Base.RefValue`.
# JITManager.invoke wraps every argument in its own `Ref`, so a RefValue arrives
# as a pointer to the boxed object rather than to the struct bytes, and the
# thunk's second load reads the ImVec2's own bytes as an address — a segfault
# inside ImGui::ButtonEx. `Ptr{T} <: Ref{T}`, so the annotation accepts the
# pointer form. `withref` below is the safe spelling.
#
# NOTE: imgui is compiled without NDEBUG, so IM_ASSERT is live — a malformed
# frame sequence (Begin without End, a second NewFrame without Render) aborts
# the process instead of failing a test.
#
# NOTE: the wrapper exports only Managed* types and field accessors, so every
# ImGui entry point is reached qualified (`Imgui.ImGui_Begin`). That is also the
# safe habit for a C++-derived wrapper — `using` one pulls whatever names the
# library happens to define into scope.

using Test
using JSON
using RepliBuild

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")
const META_PATH = joinpath(PKG_DIR, "julia", "compilation_metadata.json")

# ── Harness ──────────────────────────────────────────────────────────────────
# Everything here is defined before the testsets: @testset bodies are local
# scopes, so `const` is not allowed inside them.

# DWARF sizes/offsets arrive as hex strings
_num(v) = v isa Integer ? Int(v) :
          startswith(v, "0x") ? parse(Int, v[3:end], base = 16) : parse(Int, v)

# Metadata is only readable after the build, so it is loaded on first use.
const _META = Ref{Any}(nothing)
metadata() = (_META[] === nothing && (_META[] = JSON.parsefile(META_PATH)); _META[])

meta_size(s::AbstractString) = _num(metadata()["struct_definitions"][s]["byte_size"])
function meta_offset(s::AbstractString, member::AbstractString)
    for m in metadata()["struct_definitions"][s]["members"]
        m["name"] == member && return _num(m["offset"])
    end
    error("no member $member in $s")
end

"""
Delete this package's generated output, preserving the vendored upstream source.

Stands in for `RepliBuild.clean`, which also removes `.replibuild_cache/` — and
that holds `deps/imgui`, the git clone. Cleaning it turns every run into a fresh
clone from GitHub: slow, and it fails outright without network.

The content-hash marker has to go with the outputs. `build()` skips the whole
pipeline when the project is unchanged (`cache: project unchanged`), and that
hash covers replibuild.toml + sources + project git HEAD — **not** RepliBuild's
own source. So after an engine change the marker still matches, build() skips,
and the `build/imgui_linked.ll` assertions below would fail on artifacts nothing
regenerated. Deleting the marker is what makes this a real pipeline test rather
than a check on whatever was lying around.
"""
function reset_outputs!()
    for d in ("build", "julia", ".debug")
        p = joinpath(PKG_DIR, d)
        isdir(p) && rm(p; recursive = true)
    end
    marker = joinpath(PKG_DIR, ".replibuild_cache", "project_hash")
    isfile(marker) && rm(marker)
end

vec2(x, y) = Imgui.ImVec2(Cfloat(x), Cfloat(y))

# Call `f` with a pointer to a stack-pinned copy of `v` — see the Ref{T} note.
withref(f, v::T) where {T} = (r = Ref(v); GC.@preserve r f(Base.unsafe_convert(Ptr{T}, r)))

# Labels cross the ABI as `char*`. Interning them in a global keeps the bytes
# rooted for the process, so call sites don't each need a GC.@preserve.
const _PINNED = Dict{String,String}()
cs(s::AbstractString) = pointer(get!(_PINNED, String(s), String(s)))

# A `char*` return arrives as `Union{String,Nothing}` — the wrapper applies
# the NULL/copy policy itself now, on Tier 2 as well as on ccall (2026-08-12).
# The pointer arms stay for values read out of blobs by hand, and for the
# `<name>_ptr` variants.
cstr(x::AbstractString) = String(x)
cstr(::Nothing) = ""
cstr(x) = (p = reinterpret(Ptr{UInt8}, x); p == C_NULL ? "" : unsafe_string(p))

# ImGuiIO is a 3048-byte blob (106 members) and ImGui_GetIO() hands back a
# Ptr{Cvoid}, so the harness pokes fields at their DWARF offsets. Reading the
# offsets from metadata means layout drift fails here, loudly.
function headless_context(; width = 1280, height = 720, dt = 1/60)
    ini_off   = meta_offset("ImGuiIO", "IniFilename")
    flags_off = meta_offset("ImGuiIO", "BackendFlags")
    disp_off  = meta_offset("ImGuiIO", "DisplaySize")
    dt_off    = meta_offset("ImGuiIO", "DeltaTime")

    ctx = Imgui.ImGui_CreateContext(C_NULL)
    io  = Imgui.ImGui_GetIO()
    unsafe_store!(Ptr{Ptr{UInt8}}(io + ini_off), C_NULL)
    unsafe_store!(Ptr{Cuint}(io + flags_off),
                  unsafe_load(Ptr{Cuint}(io + flags_off)) |
                  Cuint(Imgui.ImGuiBackendFlags_RendererHasTextures))
    unsafe_store!(Ptr{Cfloat}(io + disp_off),     Cfloat(width))
    unsafe_store!(Ptr{Cfloat}(io + disp_off + 4), Cfloat(height))
    unsafe_store!(Ptr{Cfloat}(io + dt_off),       Cfloat(dt))
    return ctx, io
end

# NewFrame → body → Render, returning the frame's ImDrawData by value
function frame(body)
    Imgui.ImGui_NewFrame()
    body()
    Imgui.ImGui_Render()
    return unsafe_load(Imgui.ImGui_GetDrawData())
end

# style.Colors is an ImVec4[ImGuiCol_COUNT] array member
style_color(idx) = unsafe_load(
    Ptr{Imgui.ImVec4}(Imgui.ImGui_GetStyle() + meta_offset("ImGuiStyle", "Colors")),
    Int(idx) + 1)

# ── Build ────────────────────────────────────────────────────────────────────

@testset "Dear ImGui Hub Package" begin

@testset "Build pipeline" begin
    deps_dir = joinpath(PKG_DIR, ".replibuild_cache", "deps")
    had_clone = isdir(deps_dir)

    reset_outputs!()

    # The whole point of not calling RepliBuild.clean: if this ever regresses to
    # a destructive reset, the next run silently becomes a network-dependent
    # re-clone. Assert the source survived rather than trusting the helper.
    had_clone && @test isdir(deps_dir)

    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libimgui.so") || endswith(lib, "libimgui.dylib")

    julia_dir = joinpath(PKG_DIR, "julia")
    @test isfile(joinpath(julia_dir, "compilation_metadata.json"))

    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test isfile(joinpath(julia_dir, "Imgui.jl"))
end

@testset "IR artifacts" begin
    build_dir = joinpath(PKG_DIR, "build")
    @test isfile(joinpath(build_dir, "imgui_linked.ll"))
    @test isfile(joinpath(build_dir, "imgui_opt.ll"))

    # imgui.cpp alone is ~15MB of IR; anything small means a TU was dropped
    @test filesize(joinpath(build_dir, "imgui_linked.ll")) > 10_000_000
end

# ── Load wrapper ─────────────────────────────────────────────────────────────

include(joinpath(PKG_DIR, "julia", "Imgui.jl"))

@testset "Module structure" begin
    # Context / frame lifecycle
    @test isdefined(Imgui, :ImGui_CreateContext)
    @test isdefined(Imgui, :ImGui_DestroyContext)
    @test isdefined(Imgui, :ImGui_GetCurrentContext)
    @test isdefined(Imgui, :ImGui_SetCurrentContext)
    @test isdefined(Imgui, :ImGui_GetIO)
    @test isdefined(Imgui, :ImGui_GetStyle)
    @test isdefined(Imgui, :ImGui_NewFrame)
    @test isdefined(Imgui, :ImGui_EndFrame)
    @test isdefined(Imgui, :ImGui_Render)
    @test isdefined(Imgui, :ImGui_GetDrawData)
    @test isdefined(Imgui, :ImGui_GetVersion)

    # Windows and widgets
    @test isdefined(Imgui, :ImGui_Begin)
    @test isdefined(Imgui, :ImGui_End)
    @test isdefined(Imgui, :ImGui_Text)
    @test isdefined(Imgui, :ImGui_TextUnformatted)
    @test isdefined(Imgui, :ImGui_Button)
    @test isdefined(Imgui, :ImGui_Checkbox)
    @test isdefined(Imgui, :ImGui_SliderFloat)
    @test isdefined(Imgui, :ImGui_InputText)
    @test isdefined(Imgui, :ImGui_BeginTable)
    @test isdefined(Imgui, :ImGui_EndTable)
    @test isdefined(Imgui, :ImGui_ShowDemoWindow)

    # Class methods (Tier-2 thunks with an explicit `this`)
    @test isdefined(Imgui, :ImGuiIO_AddMousePosEvent)
    @test isdefined(Imgui, :ImGuiIO_AddMouseButtonEvent)
    @test isdefined(Imgui, :ImGuiIO_AddKeyEvent)
    @test isdefined(Imgui, :ImGuiIO_AddInputCharacter)
    @test isdefined(Imgui, :ImDrawList_AddLine)
    @test isdefined(Imgui, :ImDrawList_AddRectFilled)
    @test isdefined(Imgui, :ImFontAtlas_AddFontDefault)
    @test isdefined(Imgui, :ImGuiStorage_SetInt)
    @test isdefined(Imgui, :ImGuiStorage_GetInt)
    @test isdefined(Imgui, :ImGuiListClipper_Begin)
    @test isdefined(Imgui, :ImGuiListClipper_Step)
    @test isdefined(Imgui, :ImGuiTextFilter_Build)
    @test isdefined(Imgui, :ImGuiTextFilter_PassFilter)

    # Struct types
    @test isdefined(Imgui, :ImVec2)
    @test isdefined(Imgui, :ImVec4)
    @test isdefined(Imgui, :ImDrawData)
    @test isdefined(Imgui, :ImDrawVert)
    @test isdefined(Imgui, :ImDrawCmd)
    @test isdefined(Imgui, :ImDrawList)
    @test isdefined(Imgui, :ImGuiListClipper)

    # Enums
    @test isdefined(Imgui, :ImGuiCol)
    @test isdefined(Imgui, :ImGuiCond)
    @test isdefined(Imgui, :ImGuiKey)
    @test isdefined(Imgui, :ImGuiDir)
    @test isdefined(Imgui, :ImGuiMouseButton)
    @test isdefined(Imgui, :ImGuiWindowFlags)
    @test isdefined(Imgui, :ImGuiTableFlags)
    @test isdefined(Imgui, :ImGuiBackendFlags)
    @test isdefined(Imgui, :ImGuiConfigFlags)
    @test isdefined(Imgui, :ImDrawFlags)

    @test Int(Imgui.ImGuiCol_Text) == 0
    @test Int(Imgui.ImGuiCond_Always) == 1
    @test Int(Imgui.ImGuiDir_None) == -1
    @test Int(Imgui.ImGuiMouseButton_Left) == 0
    @test Int(Imgui.ImGuiBackendFlags_RendererHasTextures) == 16

    # Metadata
    @test haskey(Imgui.METADATA, "llvm_version")
    @test haskey(Imgui.METADATA, "target_triple")
    @test Imgui.METADATA["function_count"] >= 1000
end

@testset "Struct layouts match DWARF" begin
    @test sizeof(Imgui.ImVec2)     == meta_size("ImVec2")     == 8
    @test sizeof(Imgui.ImVec4)     == meta_size("ImVec4")     == 16
    @test sizeof(Imgui.ImDrawVert) == meta_size("ImDrawVert") == 20
    @test sizeof(Imgui.ImDrawData) == meta_size("ImDrawData")
end

# ── API tests ────────────────────────────────────────────────────────────────

@testset "Version" begin
    @test cstr(Imgui.ImGui_GetVersion()) == "1.92.9b"
end

@testset "Context lifecycle" begin
    @test Imgui.ImGui_GetCurrentContext() == C_NULL

    ctx, io = headless_context()
    @test ctx != C_NULL
    @test io  != C_NULL
    @test Imgui.ImGui_GetCurrentContext() == ctx

    Imgui.ImGui_DestroyContext(ctx)
    @test Imgui.ImGui_GetCurrentContext() == C_NULL
end

@testset "Headless frame produces geometry" begin
    ctx, _ = headless_context(width = 1024, height = 768)

    dd = frame() do
        withref(vec2(320, 200)) do p
            Imgui.ImGui_SetNextWindowSize(p, Cint(Imgui.ImGuiCond_Always))
        end
        @test Imgui.ImGui_Begin(cs("hello"), C_NULL, Cint(0))
        Imgui.ImGui_Text(cs("text from julia"))
        @test Imgui.ImGui_GetWindowSize() == vec2(320, 200)
        Imgui.ImGui_End()
    end

    @test dd.Valid
    @test dd.CmdListsCount >= 1
    @test dd.TotalVtxCount > 0
    @test dd.TotalIdxCount > 0
    @test dd.DisplaySize == vec2(1024, 768)
    @test Imgui.ImGui_GetFrameCount() == 1

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Widgets lay out and report" begin
    ctx, _ = headless_context()
    checked = Ref(false)

    frame() do
        Imgui.ImGui_Begin(cs("widgets"), C_NULL, Cint(0))

        # Nothing is clicked with no input fed, but the items must lay out
        pressed = withref(vec2(80, 24)) do p
            Imgui.ImGui_Button(cs("Press"), p)
        end
        @test pressed == false
        @test Imgui.ImGui_GetItemRectSize() == vec2(80, 24)

        GC.@preserve checked begin
            @test Imgui.ImGui_Checkbox(cs("Check"),
                    Base.unsafe_convert(Ptr{Bool}, checked)) == false
        end
        @test checked[] == false

        size = Imgui.ImGui_CalcTextSize(cs("hello"), C_NULL, false, Cfloat(-1))
        @test size.x > 0
        @test size.y > 0

        Imgui.ImGui_End()
    end

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Style themes" begin
    ctx, _ = headless_context()

    Imgui.ImGui_StyleColorsDark(C_NULL)
    dark_text = style_color(Imgui.ImGuiCol_Text)
    @test dark_text == Imgui.ImVec4(1f0, 1f0, 1f0, 1f0)

    Imgui.ImGui_StyleColorsLight(C_NULL)
    light_text = style_color(Imgui.ImGuiCol_Text)
    @test light_text == Imgui.ImVec4(0f0, 0f0, 0f0, 1f0)
    @test light_text != dark_text

    Imgui.ImGui_StyleColorsDark(C_NULL)
    @test style_color(Imgui.ImGuiCol_Text) == dark_text

    Imgui.ImGui_DestroyContext(ctx)
end

end  # top-level testset

println("✓ imgui test passed")
