#!/usr/bin/env julia
# Dear ImGui Hub package — deep integration test
#
# Assumes the wrapper is already built (run test.jl first, or it builds here as
# a fallback). Where test.jl proves the pipeline, this file leans on the wrapper:
#   - imgui's OWN ABI self-check (DebugCheckVersionAndDataLayout) driven from
#     RepliBuild's DWARF metadata — the library agrees with the wrapper or aborts
#   - synthetic input: mouse position/button and character events fed through
#     ImGuiIO, driving a real Button press and a Checkbox toggle across frames
#   - keyboard edges, the ID stack, the style-color stack, popups, tables,
#     child windows and scrolling
#   - ImDrawData walked as data: ImDrawList → ImDrawCmd → ImDrawVert through the
#     generated ImVector structs, with per-command element counts reconciled
#     against TotalIdxCount
#   - C++ objects on caller-owned storage sized from compilation_metadata.json
#     (ImGuiListClipper, ImGuiTextFilter), torn down with the real D2 destructor
#   - ini settings surviving a context teardown, and the whole demo window
#     rendering headless
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/imgui/test_deep.jl
#
# HEADLESS: there is no backend (replibuild.toml excludes backends/ and
# examples/), so each context sets ImGuiBackendFlags_RendererHasTextures — which
# is what lets ImFontAtlas build itself with no renderer — plus DisplaySize and
# DeltaTime, and nulls IniFilename so nothing writes imgui.ini into the repo.
#
# TWO WRAPPER-SHAPE FINDINGS ARE PINNED HERE, both logged for the engine repo
# rather than worked around:
#
#   1. A `::Ref{ImVec2}` parameter must be handed a raw `Ptr{ImVec2}`, never a
#      `Base.RefValue`. JITManager.invoke wraps every argument in its own `Ref`,
#      so a RefValue arrives as a pointer to the boxed object and the thunk's
#      second load reads the ImVec2's own bytes as an address — segfault inside
#      ImGui::ButtonEx. `Ptr{T} <: Ref{T}`, so the annotation accepts the
#      pointer form; `withref` below is the safe spelling.
#
#   2. Overload collision, same class as the pugixml verifier's: imgui declares
#      both `GetColorU32(ImGuiCol, float)` and `GetColorU32(ImU32, float)`.
#      They collapse to one Julia signature and last-definition-wins binds the
#      ImU32 form, so passing a style index returns the index back. The
#      "GetColorU32 binds the ImU32 overload" testset asserts that behaviour so
#      a regeneration that changes it is visible; style lookups here go through
#      the unambiguous ImGui_GetStyleColorVec4.
#
# NOTE: imgui is compiled without NDEBUG, so IM_ASSERT is live. A layout
# mismatch or a malformed frame sequence aborts the process instead of failing
# an @test — loud, which is the right outcome for both.

using Test
using JSON

const PKG_DIR   = @__DIR__
const WRAPPER   = joinpath(PKG_DIR, "julia", "Imgui.jl")
const META_PATH = joinpath(PKG_DIR, "julia", "compilation_metadata.json")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

# ── Harness ──────────────────────────────────────────────────────────────────
# Defined before the testsets: @testset bodies are local scopes, so `const` is
# not allowed inside them.

const META = JSON.parsefile(META_PATH)

# DWARF sizes/offsets arrive as hex strings
_num(v) = v isa Integer ? Int(v) :
          startswith(v, "0x") ? parse(Int, v[3:end], base = 16) : parse(Int, v)

meta_size(s::AbstractString) = _num(META["struct_definitions"][s]["byte_size"])
function meta_offset(s::AbstractString, member::AbstractString)
    for m in META["struct_definitions"][s]["members"]
        m["name"] == member && return _num(m["offset"])
    end
    error("no member $member in $s")
end

const IO_BACKEND_FLAGS = meta_offset("ImGuiIO", "BackendFlags")
const IO_DISPLAY_SIZE  = meta_offset("ImGuiIO", "DisplaySize")
const IO_DELTA_TIME    = meta_offset("ImGuiIO", "DeltaTime")
const IO_INI_FILENAME  = meta_offset("ImGuiIO", "IniFilename")
const IO_FONTS         = meta_offset("ImGuiIO", "Fonts")

vec2(x, y) = Imgui.ImVec2(Cfloat(x), Cfloat(y))
vec4(x, y, z, w) = Imgui.ImVec4(Cfloat(x), Cfloat(y), Cfloat(z), Cfloat(w))

# Call `f` with a pointer to a stack-pinned copy of `v` — see finding (1) above.
withref(f, v::T) where {T} = (r = Ref(v); GC.@preserve r f(Base.unsafe_convert(Ptr{T}, r)))

# Labels cross the ABI as `char*`. Interning them in a global keeps the bytes
# rooted for the process, so call sites don't each need a GC.@preserve.
const _PINNED = Dict{String,String}()
cs(s::AbstractString) = pointer(get!(_PINNED, String(s), String(s)))

cstr(x) = (p = reinterpret(Ptr{UInt8}, x); p == C_NULL ? "" : unsafe_string(p))

# ImGuiIO is a 3048-byte blob (106 members) and ImGui_GetIO() hands back a
# Ptr{Cvoid}, so fields are poked at their DWARF offsets. Offsets come from
# metadata, so layout drift fails here instead of corrupting silently.
function headless_context(; width = 1024, height = 768, dt = 1/60)
    ctx = Imgui.ImGui_CreateContext(C_NULL)
    # CreateContext RESTORES the previously current context if there was one, so
    # the new context is not automatically current. Without this the second
    # context in a session would be configured through the first one's IO.
    Imgui.ImGui_SetCurrentContext(ctx)
    io  = Imgui.ImGui_GetIO()
    unsafe_store!(Ptr{Ptr{UInt8}}(io + IO_INI_FILENAME), C_NULL)
    unsafe_store!(Ptr{Cuint}(io + IO_BACKEND_FLAGS),
                  unsafe_load(Ptr{Cuint}(io + IO_BACKEND_FLAGS)) |
                  Cuint(Imgui.ImGuiBackendFlags_RendererHasTextures))
    unsafe_store!(Ptr{Cfloat}(io + IO_DISPLAY_SIZE),     Cfloat(width))
    unsafe_store!(Ptr{Cfloat}(io + IO_DISPLAY_SIZE + 4), Cfloat(height))
    unsafe_store!(Ptr{Cfloat}(io + IO_DELTA_TIME),       Cfloat(dt))
    return ctx, io
end

# NewFrame → body → Render, returning the frame's ImDrawData by value
function frame(body)
    Imgui.ImGui_NewFrame()
    body()
    Imgui.ImGui_Render()
    return unsafe_load(Imgui.ImGui_GetDrawData())
end

set_next_window_pos(v)  = withref(v) do p
    withref(vec2(0, 0)) do pivot
        Imgui.ImGui_SetNextWindowPos(p, Cint(Imgui.ImGuiCond_Always), pivot)
    end
end
set_next_window_size(v) = withref(v) do p
    Imgui.ImGui_SetNextWindowSize(p, Cint(Imgui.ImGuiCond_Always))
end

item_center() = (mn = Imgui.ImGui_GetItemRectMin(); mx = Imgui.ImGui_GetItemRectMax();
                 vec2((mn.x + mx.x) / 2, (mn.y + mx.y) / 2))

style_color(idx) = unsafe_load(
    Ptr{Imgui.ImVec4}(Imgui.ImGui_GetStyleColorVec4(Cint(idx))))

# ── Tests ────────────────────────────────────────────────────────────────────

@testset "Dear ImGui Deep Tests" begin

@testset "ABI layout contract" begin
    # Julia's view of each struct, DWARF's view, and the compiled library's own
    # view all have to agree. The first two are checked here; the third is
    # imgui's IMGUI_CHECKVERSION() self-check, fed the metadata sizes.
    @test sizeof(Imgui.ImVec2)     == meta_size("ImVec2")     == 8
    @test sizeof(Imgui.ImVec4)     == meta_size("ImVec4")     == 16
    @test sizeof(Imgui.ImDrawVert) == meta_size("ImDrawVert") == 20
    @test sizeof(Imgui.ImDrawCmd)  == meta_size("ImDrawCmd")
    @test sizeof(Imgui.ImDrawData) == meta_size("ImDrawData")
    @test sizeof(Imgui.ImGuiListClipper) == meta_size("ImGuiListClipper")

    # ImDrawIdx as the wrapper models it: the IdxBuffer element type
    idx_type = eltype(fieldtype(Imgui.ImVector_unsigned_short, :Data))
    @test sizeof(idx_type) == 2

    ctx, _ = headless_context()
    # A mismatch trips IM_ASSERT and aborts the process rather than returning
    # false — imgui's own choice, and the right noise level for layout drift.
    @test Imgui.ImGui_DebugCheckVersionAndDataLayout(
            cs("1.92.9b"),
            meta_size("ImGuiIO"), meta_size("ImGuiStyle"),
            meta_size("ImVec2"), meta_size("ImVec4"),
            meta_size("ImDrawVert"), sizeof(idx_type))
    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Context lifecycle and isolation" begin
    @test Imgui.ImGui_GetCurrentContext() == C_NULL

    ctx1, io1 = headless_context(width = 800, height = 600)
    @test Imgui.ImGui_GetCurrentContext() == ctx1
    frame() do
        Imgui.ImGui_Begin(cs("first"), C_NULL, Cint(0)); Imgui.ImGui_End()
    end
    frame() do
        Imgui.ImGui_Begin(cs("first"), C_NULL, Cint(0)); Imgui.ImGui_End()
    end
    @test Imgui.ImGui_GetFrameCount() == 2

    # A second context starts from scratch and does not see the first's frames
    ctx2, io2 = headless_context(width = 1920, height = 1080)
    @test ctx2 != ctx1
    @test io2  != io1
    @test Imgui.ImGui_GetCurrentContext() == ctx2
    dd2 = frame() do
        Imgui.ImGui_Begin(cs("second"), C_NULL, Cint(0)); Imgui.ImGui_End()
    end
    @test Imgui.ImGui_GetFrameCount() == 1
    @test dd2.DisplaySize == vec2(1920, 1080)

    # Switching back restores the first context's state
    Imgui.ImGui_SetCurrentContext(ctx1)
    @test Imgui.ImGui_GetCurrentContext() == ctx1
    @test Imgui.ImGui_GetFrameCount() == 2

    Imgui.ImGui_DestroyContext(ctx2)
    Imgui.ImGui_SetCurrentContext(ctx1)
    Imgui.ImGui_DestroyContext(ctx1)
    @test Imgui.ImGui_GetCurrentContext() == C_NULL
end

@testset "ImDrawData walked as data" begin
    ctx, _ = headless_context()

    local dd
    # A window's first frame is hidden while it auto-fits, so geometry for it
    # only appears from the second frame on.
    for _ in 1:2
        dd = frame() do
            set_next_window_size(vec2(240, 160))
            Imgui.ImGui_Begin(cs("draw"), C_NULL, Cint(0))
            dl = Imgui.ImGui_GetWindowDrawList()
            withref(vec2(5, 5)) do a
                withref(vec2(50, 50)) do b
                    Imgui.ImDrawList_AddRectFilled(dl, a, b, Cuint(0xff123456),
                                                   Cfloat(0), Cint(0))
                end
            end
            Imgui.ImGui_End()
        end
    end

    @test dd.Valid
    @test dd.CmdListsCount == 1
    @test dd.TotalVtxCount > 0
    @test dd.TotalIdxCount > 0

    lists = unsafe_wrap(Array, dd.CmdLists.Data, dd.CmdListsCount)
    @test length(lists) == 1

    total_elems = 0
    total_vtx   = 0
    for lp in lists
        dl = unsafe_load(Ptr{Imgui.ImDrawList}(lp))
        @test dl.CmdBuffer.Size >= 1
        @test dl.VtxBuffer.Size > 0
        @test dl.IdxBuffer.Size > 0
        total_vtx += dl.VtxBuffer.Size

        cmds = unsafe_wrap(Array, dl.CmdBuffer.Data, dl.CmdBuffer.Size)
        for c in cmds
            @test c.ElemCount > 0
            @test c.ClipRect.z >= c.ClipRect.x
            @test c.ClipRect.w >= c.ClipRect.y
            @test c.UserCallback == C_NULL
            total_elems += Int(c.ElemCount)
        end

        # Vertices carry positions inside the display, and packed RGBA colors
        verts = unsafe_wrap(Array, dl.VtxBuffer.Data, dl.VtxBuffer.Size)
        @test all(v -> 0 <= v.pos.x <= 1024 && 0 <= v.pos.y <= 768, verts)
        @test any(v -> v.col != 0, verts)
    end

    # Every index in the buffer belongs to exactly one draw command
    @test total_elems == dd.TotalIdxCount
    @test total_vtx   == dd.TotalVtxCount

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Synthetic mouse drives a Button" begin
    ctx, io = headless_context()
    center  = Ref(vec2(0, 0))     # filled from the previous frame's item rect
    timeline = NamedTuple[]

    for f in 1:5
        f >= 2 && Imgui.ImGuiIO_AddMousePosEvent(io, center[].x, center[].y)
        f == 3 && Imgui.ImGuiIO_AddMouseButtonEvent(io, Cint(Imgui.ImGuiMouseButton_Left), true)
        f == 4 && Imgui.ImGuiIO_AddMouseButtonEvent(io, Cint(Imgui.ImGuiMouseButton_Left), false)

        frame() do
            set_next_window_pos(vec2(10, 10))
            set_next_window_size(vec2(200, 100))
            Imgui.ImGui_Begin(cs("buttons"), C_NULL, Cint(0))
            pressed = withref(vec2(80, 24)) do p
                Imgui.ImGui_Button(cs("Press"), p)
            end
            center[] = item_center()
            push!(timeline, (pressed = pressed,
                             hovered = Imgui.ImGui_IsItemHovered(Cint(0)),
                             active  = Imgui.ImGui_IsItemActive(),
                             clicked = Imgui.ImGui_IsItemClicked(Cint(0))))
            Imgui.ImGui_End()
        end
    end

    # f1: mouse still at the sentinel position, nothing under it
    @test timeline[1].hovered == false
    @test timeline[1].pressed == false
    # f2: cursor arrives over the button
    @test timeline[2].hovered == true
    @test timeline[2].active  == false
    # f3: button held — clicked fires on the press edge, not the press itself
    @test timeline[3].active  == true
    @test timeline[3].clicked == true
    @test timeline[3].pressed == false
    # f4: released over the item — this is where Button() returns true
    @test timeline[4].pressed == true
    @test timeline[4].active  == false
    # f5: nothing left to report
    @test timeline[5].pressed == false

    @test count(t -> t.pressed, timeline) == 1
    @test Imgui.ImGui_GetMousePos() == center[]

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Synthetic mouse toggles a Checkbox" begin
    ctx, io = headless_context()
    flag    = Ref(false)
    center  = Ref(vec2(0, 0))
    changed = Bool[]

    GC.@preserve flag begin
        for f in 1:5
            f >= 2 && Imgui.ImGuiIO_AddMousePosEvent(io, center[].x, center[].y)
            f == 3 && Imgui.ImGuiIO_AddMouseButtonEvent(io, Cint(0), true)
            f == 4 && Imgui.ImGuiIO_AddMouseButtonEvent(io, Cint(0), false)

            frame() do
                set_next_window_pos(vec2(10, 10))
                Imgui.ImGui_Begin(cs("checks"), C_NULL, Cint(0))
                push!(changed, Imgui.ImGui_Checkbox(cs("Toggle"),
                        Base.unsafe_convert(Ptr{Bool}, flag)))
                center[] = item_center()
                Imgui.ImGui_End()
            end
        end
    end

    @test changed == [false, false, false, true, false]
    @test flag[] == true          # the widget wrote through the Ptr{Bool}

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Character events reach InputText" begin
    ctx, io = headless_context()
    buf = zeros(UInt8, 64)
    seen = String[]

    GC.@preserve buf begin
        for f in 1:4
            if f == 3
                for c in "hi!"
                    Imgui.ImGuiIO_AddInputCharacter(io, Cuint(c))
                end
            end
            frame() do
                Imgui.ImGui_Begin(cs("input"), C_NULL, Cint(0))
                # Focus has to be requested before the item is submitted
                f <= 2 && Imgui.ImGui_SetKeyboardFocusHere(Cint(0))
                Imgui.ImGui_InputText(cs("field"), pointer(buf), length(buf),
                                      Cint(0), C_NULL, C_NULL)
                f == 2 && @test Imgui.ImGui_IsItemActive()
                push!(seen, unsafe_string(pointer(buf)))
                Imgui.ImGui_End()
            end
        end
    end

    @test seen[1] == ""
    @test seen[2] == ""
    @test seen[3] == "hi!"        # typed the frame the characters were queued
    @test seen[4] == "hi!"        # and it persists
    @test buf[1:3] == UInt8['h', 'i', '!']
    @test buf[4] == 0x00          # NUL-terminated in place

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Keyboard events and edges" begin
    ctx, io = headless_context()
    down = Bool[]; pressed = Bool[]

    for f in 1:4
        f == 2 && Imgui.ImGuiIO_AddKeyEvent(io, Imgui.ImGuiKey_A, true)
        f == 4 && Imgui.ImGuiIO_AddKeyEvent(io, Imgui.ImGuiKey_A, false)
        frame() do
            Imgui.ImGui_Begin(cs("keys"), C_NULL, Cint(0))
            push!(down,    Imgui.ImGui_IsKeyDown(Imgui.ImGuiKey_A))
            push!(pressed, Imgui.ImGui_IsKeyPressed(Imgui.ImGuiKey_A, false))
            Imgui.ImGui_End()
        end
    end

    @test down    == [false, true, true, false]
    @test pressed == [false, true, false, false]   # press is an edge, not a level
    @test cstr(Imgui.ImGui_GetKeyName(Imgui.ImGuiKey_A)) == "A"
    @test cstr(Imgui.ImGui_GetKeyName(Imgui.ImGuiKey_Space)) == "Space"

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "ID stack" begin
    ctx, _ = headless_context()

    frame() do
        Imgui.ImGui_Begin(cs("ids"), C_NULL, Cint(0))

        a  = Imgui.ImGui_GetID(cs("alpha"), C_NULL)
        b  = Imgui.ImGui_GetID(cs("beta"),  C_NULL)
        @test a != b
        @test a == Imgui.ImGui_GetID(cs("alpha"), C_NULL)   # deterministic

        # Pushing a scope changes the hash of the same label, popping restores it
        Imgui.ImGui_PushID(Cint(7))
        scoped = Imgui.ImGui_GetID(cs("alpha"), C_NULL)
        @test scoped != a
        Imgui.ImGui_PushID(Cint(7))
        @test Imgui.ImGui_GetID(cs("alpha"), C_NULL) != scoped   # nesting stacks
        Imgui.ImGui_PopID()
        @test Imgui.ImGui_GetID(cs("alpha"), C_NULL) == scoped
        Imgui.ImGui_PopID()
        @test Imgui.ImGui_GetID(cs("alpha"), C_NULL) == a

        # A submitted item carries the id its label hashes to
        withref(vec2(60, 20)) do p
            Imgui.ImGui_Button(cs("alpha"), p)
        end
        @test Imgui.ImGui_GetItemID() == a

        Imgui.ImGui_End()
    end

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Draw list primitives and the clip stack" begin
    ctx, _ = headless_context()

    frame() do
        set_next_window_size(vec2(240, 160))
        Imgui.ImGui_Begin(cs("prims"), C_NULL, Cint(0))
        dl = Imgui.ImGui_GetWindowDrawList()

        before = unsafe_load(Ptr{Imgui.ImDrawList}(dl))
        withref(vec2(20, 20)) do a
            withref(vec2(120, 90)) do b
                Imgui.ImDrawList_AddRectFilled(dl, a, b, Cuint(0xff00ff00), Cfloat(0), Cint(0))
                Imgui.ImDrawList_AddRect(dl, a, b, Cuint(0xffffffff), Cfloat(2), Cfloat(1), Cint(0))
                Imgui.ImDrawList_AddLine(dl, a, b, Cuint(0xff0000ff), Cfloat(2))
                Imgui.ImDrawList_AddCircle(dl, a, Cfloat(10), Cuint(0xffffffff), Cint(12), Cfloat(1))
            end
        end
        after = unsafe_load(Ptr{Imgui.ImDrawList}(dl))

        @test after.VtxBuffer.Size > before.VtxBuffer.Size
        @test after.IdxBuffer.Size > before.IdxBuffer.Size
        @test after.IdxBuffer.Size % 3 == 0        # everything is triangles

        # Clip rects nest: pushing narrows the header, popping restores it
        depth0 = after.VtxBuffer.Size   # keep `after` alive in the reader's head
        stack0 = after._ClipRectStack.Size
        outer  = after._CmdHeader.ClipRect
        withref(vec2(0, 0)) do a
            withref(vec2(10, 10)) do b
                Imgui.ImDrawList_PushClipRect(dl, a, b, false)
            end
        end
        pushed = unsafe_load(Ptr{Imgui.ImDrawList}(dl))
        @test pushed._ClipRectStack.Size == stack0 + 1
        @test pushed._CmdHeader.ClipRect == vec4(0, 0, 10, 10)
        Imgui.ImDrawList_PopClipRect(dl)
        popped = unsafe_load(Ptr{Imgui.ImDrawList}(dl))
        @test popped._ClipRectStack.Size == stack0
        @test popped._CmdHeader.ClipRect == outer
        @test depth0 > 0

        Imgui.ImGui_End()
    end

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Per-window state storage" begin
    ctx, _ = headless_context()

    frame() do
        Imgui.ImGui_Begin(cs("storage"), C_NULL, Cint(0))
        st = Imgui.ImGui_GetStateStorage()
        @test st != C_NULL

        Imgui.ImGuiStorage_SetInt(st, Cuint(1234), Cint(99))
        @test Imgui.ImGuiStorage_GetInt(st, Cuint(1234), Cint(-1)) == 99
        @test Imgui.ImGuiStorage_GetInt(st, Cuint(4321), Cint(-1)) == -1   # default on miss

        Imgui.ImGuiStorage_SetFloat(st, Cuint(7), Cfloat(2.5))
        @test Imgui.ImGuiStorage_GetFloat(st, Cuint(7), Cfloat(0)) == 2.5f0

        Imgui.ImGuiStorage_SetBool(st, Cuint(8), true)
        @test Imgui.ImGuiStorage_GetBool(st, Cuint(8), false) == true
        @test Imgui.ImGuiStorage_GetBool(st, Cuint(9), true)  == true

        marker = Ptr{Cvoid}(UInt(0xdead0000))
        Imgui.ImGuiStorage_SetVoidPtr(st, Cuint(10), marker)
        @test Imgui.ImGuiStorage_GetVoidPtr(st, Cuint(10)) == marker

        # GetIntRef hands back a pointer into the storage — writes through it
        # are visible to the next GetInt
        ref = Imgui.ImGuiStorage_GetIntRef(st, Cuint(11), Cint(41))
        @test unsafe_load(Ptr{Cint}(ref)) == 41
        unsafe_store!(Ptr{Cint}(ref), Cint(42))
        @test Imgui.ImGuiStorage_GetInt(st, Cuint(11), Cint(-1)) == 42

        Imgui.ImGui_End()
    end

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "ImGuiListClipper on caller-owned storage" begin
    # ImGuiListClipper's real constructor is memset(this, 0, sizeof(*this)), so
    # zeroed storage sized from metadata IS a constructed object. Teardown goes
    # through the D2 (non-deleting) destructor — the deleting D0 would free()
    # Julia-owned memory.
    ctx, _ = headless_context()

    frame() do
        set_next_window_size(vec2(200, 120))
        Imgui.ImGui_Begin(cs("clipped"), C_NULL, Cint(0))

        mem = zeros(UInt8, meta_size("ImGuiListClipper"))
        GC.@preserve mem begin
            cp = Ptr{Cvoid}(pointer(mem))
            Imgui.ImGuiListClipper_Begin(cp, Cint(1000), Cfloat(-1))
            @test unsafe_load(Ptr{Imgui.ImGuiListClipper}(cp)).ItemsCount == 1000

            steps = 0
            rows  = 0
            while Imgui.ImGuiListClipper_Step(cp)
                c = unsafe_load(Ptr{Imgui.ImGuiListClipper}(cp))
                steps += 1
                @test c.DisplayStart >= 0
                @test c.DisplayEnd >= c.DisplayStart
                for _ in c.DisplayStart:(c.DisplayEnd - 1)
                    Imgui.ImGui_Text(cs("row"))
                    rows += 1
                end
                steps > 16 && break        # the clipper must terminate on its own
            end

            @test steps <= 16
            @test rows > 0
            @test rows < 1000              # the whole point: most rows are skipped

            Imgui.ImGuiListClipper_End(cp)
            @test unsafe_load(Ptr{Imgui.ImGuiListClipper}(cp)).ItemsCount == -1
            Imgui.ImGuiListClipper_destroy_ImGuiListClipper(cp)
        end

        Imgui.ImGui_End()
    end

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "ImGuiTextFilter on caller-owned storage" begin
    # Same shape: zeroed storage is a default-constructed filter (InputBuf[0]=0,
    # empty Filters vector, CountGrep=0). The pattern is written straight into
    # InputBuf at its DWARF offset, then Build() parses it.
    input_off = meta_offset("ImGuiTextFilter", "InputBuf")
    @test input_off == 0

    function with_filter(f, pattern::String)
        mem = zeros(UInt8, meta_size("ImGuiTextFilter"))
        GC.@preserve mem begin
            fp = Ptr{Cvoid}(pointer(mem))
            unsafe_copyto!(Ptr{UInt8}(fp + input_off), pointer(pattern), sizeof(pattern))
            Imgui.ImGuiTextFilter_Build(fp)
            try
                f(fp)
            finally
                Imgui.ImGuiTextFilter_destroy_ImGuiTextFilter(fp)
            end
        end
    end

    passes(fp, text) = Imgui.ImGuiTextFilter_PassFilter(fp, cs(text), C_NULL)

    with_filter("cat,-black") do fp
        @test passes(fp, "cat")
        @test passes(fp, "cathedral")       # substring, case-insensitive grep
        @test passes(fp, "CAT scan")
        @test passes(fp, "dog") == false    # no grep matched, CountGrep > 0
    end

    # Exclusions are evaluated in order, so a leading `-` term wins
    with_filter("-black") do fp
        @test passes(fp, "black cat") == false
        @test passes(fp, "dog")                # nothing excluded, no greps
    end

    with_filter("") do fp
        @test passes(fp, "anything")           # an empty filter passes everything
    end
end

@testset "Tables" begin
    ctx, _ = headless_context()

    frame() do
        Imgui.ImGui_Begin(cs("tables"), C_NULL, Cint(0))
        opened = withref(vec2(0, 0)) do p
            Imgui.ImGui_BeginTable(cs("grid"), Cint(3),
                Cuint(Imgui.ImGuiTableFlags_Borders), p, Cfloat(0))
        end
        @test opened

        if opened
            for name in ("one", "two", "three")
                Imgui.ImGui_TableSetupColumn(cs(name), Cint(0), Cfloat(0), Cuint(0))
            end
            @test Imgui.ImGui_TableGetColumnCount() == 3

            for r in 0:2
                Imgui.ImGui_TableNextRow(Cint(0), Cfloat(0))
                for (c, name) in enumerate(("one", "two", "three"))
                    @test Imgui.ImGui_TableNextColumn()
                    @test Imgui.ImGui_TableGetColumnIndex() == c - 1
                    @test Imgui.ImGui_TableGetRowIndex() == r
                    @test cstr(Imgui.ImGui_TableGetColumnName(Cint(c - 1))) == name
                    Imgui.ImGui_Text(cs("cell"))
                end
            end
            Imgui.ImGui_EndTable()
        end
        Imgui.ImGui_End()
    end

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Popup lifecycle" begin
    ctx, _ = headless_context()
    body_ran = Bool[]
    is_open  = Bool[]

    for f in 1:3
        frame() do
            Imgui.ImGui_Begin(cs("popups"), C_NULL, Cint(0))
            f == 1 && Imgui.ImGui_OpenPopup(cs("menu"), Cint(0))
            push!(is_open, Imgui.ImGui_IsPopupOpen(cs("menu"), Cint(0)))
            ran = Imgui.ImGui_BeginPopup(cs("menu"), Cint(0))
            if ran
                Imgui.ImGui_Text(cs("item"))
                f == 2 && Imgui.ImGui_CloseCurrentPopup()
                Imgui.ImGui_EndPopup()
            end
            push!(body_ran, ran)
            Imgui.ImGui_End()
        end
    end

    @test is_open  == [true, true, false]
    @test body_ran == [true, true, false]

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Child windows and scrolling" begin
    ctx, _ = headless_context()
    maxima = Float32[]
    scrolls = Float32[]

    for f in 1:3
        frame() do
            set_next_window_size(vec2(200, 120))
            Imgui.ImGui_Begin(cs("scrolling"), C_NULL, Cint(0))
            opened = withref(vec2(150, 60)) do p
                Imgui.ImGui_BeginChild(cs("child"), p,
                    Cuint(Imgui.ImGuiChildFlags_Borders), Cuint(0))
            end
            @test opened
            if opened
                @test Imgui.ImGui_GetWindowSize() == vec2(150, 60)
                for _ in 1:30
                    Imgui.ImGui_Text(cs("row"))
                end
                f == 2 && Imgui.ImGui_SetScrollY(Cfloat(25))
                push!(maxima,  Imgui.ImGui_GetScrollMaxY())
                push!(scrolls, Imgui.ImGui_GetScrollY())
            end
            Imgui.ImGui_EndChild()   # unconditional, as imgui requires
            Imgui.ImGui_End()
        end
    end

    # Content size is only known once the child has been measured, so the
    # scroll range appears on the second frame
    @test maxima[1] == 0
    @test maxima[2] > 0
    @test scrolls[3] == 25f0       # the scroll set on f2 is observable on f3

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Style themes and the color stack" begin
    ctx, _ = headless_context()

    Imgui.ImGui_StyleColorsDark(C_NULL)
    dark_text = style_color(Imgui.ImGuiCol_Text)
    dark_bg   = style_color(Imgui.ImGuiCol_WindowBg)
    @test dark_text == vec4(1, 1, 1, 1)

    Imgui.ImGui_StyleColorsLight(C_NULL)
    @test style_color(Imgui.ImGuiCol_Text) == vec4(0, 0, 0, 1)
    @test style_color(Imgui.ImGuiCol_WindowBg) != dark_bg

    Imgui.ImGui_StyleColorsClassic(C_NULL)
    @test style_color(Imgui.ImGuiCol_Text) != dark_text

    Imgui.ImGui_StyleColorsDark(C_NULL)
    @test style_color(Imgui.ImGuiCol_Text) == dark_text

    @test cstr(Imgui.ImGui_GetStyleColorName(Cint(Imgui.ImGuiCol_Text))) == "Text"
    @test cstr(Imgui.ImGui_GetStyleColorName(Cint(Imgui.ImGuiCol_WindowBg))) == "WindowBg"

    frame() do
        Imgui.ImGui_Begin(cs("style"), C_NULL, Cint(0))
        Imgui.ImGui_PushStyleColor(Cint(Imgui.ImGuiCol_Text), Cuint(0xff00ff00))
        @test style_color(Imgui.ImGuiCol_Text) == vec4(0, 1, 0, 1)
        Imgui.ImGui_PopStyleColor(Cint(1))
        @test style_color(Imgui.ImGuiCol_Text) == dark_text
        Imgui.ImGui_End()
    end

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "GetColorU32 binds the ImU32 overload" begin
    # Finding (2) in the header: GetColorU32(ImGuiCol, float) and
    # GetColorU32(ImU32, float) collapse to one Julia signature and the ImU32
    # form wins. Asserted rather than avoided so a regeneration that changes the
    # binding shows up here instead of as a silently wrong colour.
    ctx, _ = headless_context()
    Imgui.ImGui_StyleColorsDark(C_NULL)

    frame() do
        Imgui.ImGui_Begin(cs("colors"), C_NULL, Cint(0))
        @test Imgui.ImGui_GetColorU32(Cuint(0xff00ff00), Cfloat(1.0)) == 0xff00ff00
        @test Imgui.ImGui_GetColorU32(Cuint(0xff00ff00), Cfloat(0.5)) == 0x7f00ff00
        # If the ImGuiCol form were bound, this would be the white text colour
        @test Imgui.ImGui_GetColorU32(Cuint(Imgui.ImGuiCol_Text), Cfloat(1.0)) == 0
        Imgui.ImGui_End()
    end

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Color conversions" begin
    h = Ref{Cfloat}(0); s = Ref{Cfloat}(0); v = Ref{Cfloat}(0)
    r = Ref{Cfloat}(0); g = Ref{Cfloat}(0); b = Ref{Cfloat}(0)

    GC.@preserve h s v r g b begin
        hp = Base.unsafe_convert(Ptr{Cfloat}, h)
        sp = Base.unsafe_convert(Ptr{Cfloat}, s)
        vp = Base.unsafe_convert(Ptr{Cfloat}, v)
        rp = Base.unsafe_convert(Ptr{Cfloat}, r)
        gp = Base.unsafe_convert(Ptr{Cfloat}, g)
        bp = Base.unsafe_convert(Ptr{Cfloat}, b)

        Imgui.ImGui_ColorConvertRGBtoHSV(Cfloat(1), Cfloat(0), Cfloat(0), hp, sp, vp)
        @test h[] == 0f0 && s[] == 1f0 && v[] == 1f0     # pure red

        Imgui.ImGui_ColorConvertRGBtoHSV(Cfloat(0.2), Cfloat(0.6), Cfloat(0.4), hp, sp, vp)
        Imgui.ImGui_ColorConvertHSVtoRGB(h[], s[], v[], rp, gp, bp)
        @test r[] ≈ 0.2f0 atol=1e-5
        @test g[] ≈ 0.6f0 atol=1e-5
        @test b[] ≈ 0.4f0 atol=1e-5
    end

    # ImVec4 (linear RGBA floats) ↔ packed ABGR ImU32, both directions
    packed = withref(vec4(1, 0, 0, 1)) do p
        Imgui.ImGui_ColorConvertFloat4ToU32(p)
    end
    @test packed == 0xff0000ff
    @test Imgui.ImGui_ColorConvertU32ToFloat4(packed) == vec4(1, 0, 0, 1)
    @test Imgui.ImGui_ColorConvertU32ToFloat4(
            withref(vec4(0, 1, 0, 0.5)) do p
                Imgui.ImGui_ColorConvertFloat4ToU32(p)
            end).y == 1f0
end

@testset "Ini settings survive a context teardown" begin
    ctx1, _ = headless_context()
    frame() do
        set_next_window_pos(vec2(77, 88))
        set_next_window_size(vec2(210, 130))
        Imgui.ImGui_Begin(cs("persisted"), C_NULL, Cint(0)); Imgui.ImGui_End()
    end

    size_out = Ref{Csize_t}(0)
    ini = GC.@preserve size_out cstr(Imgui.ImGui_SaveIniSettingsToMemory(
              Base.unsafe_convert(Ptr{Csize_t}, size_out)))
    @test size_out[] == sizeof(ini)
    @test occursin("[Window][persisted]", ini)
    @test occursin("Pos=77,88", ini)
    @test occursin("Size=210,130", ini)

    Imgui.ImGui_DestroyContext(ctx1)

    # A fresh context replays the same window from the saved text
    ctx2, _ = headless_context()
    GC.@preserve ini Imgui.ImGui_LoadIniSettingsFromMemory(pointer(ini), sizeof(ini))
    frame() do
        Imgui.ImGui_Begin(cs("persisted"), C_NULL, Cint(0))
        @test Imgui.ImGui_GetWindowPos()  == vec2(77, 88)
        @test Imgui.ImGui_GetWindowSize() == vec2(210, 130)
        Imgui.ImGui_End()
    end
    Imgui.ImGui_DestroyContext(ctx2)
end

@testset "Font atlas" begin
    ctx, io = headless_context()

    atlas = unsafe_load(Ptr{Ptr{Cvoid}}(io + IO_FONTS))
    @test atlas != C_NULL

    fonts_offset = meta_offset("ImFontAtlas", "Fonts")
    font_count() = Int(unsafe_load(
        Ptr{Imgui.ImVector_ImFont_star}(atlas + fonts_offset)).Size)

    # Fonts are added lazily — the default font materialises on the first
    # NewFrame, with no backend and no texture upload
    frame() do
        Imgui.ImGui_Begin(cs("fonts"), C_NULL, Cint(0)); Imgui.ImGui_End()
    end
    @test font_count() >= 1

    # Adding a font grows the atlas
    before = font_count()
    added  = Imgui.ImFontAtlas_AddFontDefault(atlas, C_NULL)
    @test added != C_NULL
    @test font_count() == before + 1

    frame() do
        Imgui.ImGui_Begin(cs("fonts"), C_NULL, Cint(0))
        @test Imgui.ImGui_GetFont() != C_NULL
        @test Imgui.ImGui_GetFontSize() > 0
        # Text measured through the real atlas, not a stub. The default font
        # (ProggyClean) is monospaced, so width tracks length exactly.
        one  = Imgui.ImGui_CalcTextSize(cs("w"),   C_NULL, false, Cfloat(-1))
        ten  = Imgui.ImGui_CalcTextSize(cs("wwwwwwwwww"), C_NULL, false, Cfloat(-1))
        @test one.x > 0
        @test ten.x ≈ 10 * one.x
        @test ten.y == one.y
        # Two lines are twice as tall as one
        @test Imgui.ImGui_CalcTextSize(cs("a\nb"), C_NULL, false, Cfloat(-1)).y ≈ 2 * one.y
        Imgui.ImGui_End()
    end

    # This is the flag that let the atlas build itself with no renderer attached
    @test unsafe_load(Ptr{Bool}(atlas + meta_offset("ImFontAtlas", "RendererHasTextures")))

    Imgui.ImGui_DestroyContext(ctx)
end

@testset "Demo window renders headless" begin
    # The demo window exercises most of the widget surface in one call — the
    # broadest stress available without writing a UI.
    ctx, _ = headless_context(width = 1600, height = 1000)
    open_flag = Ref(true)
    counts = Int[]

    GC.@preserve open_flag begin
        for _ in 1:4
            dd = frame() do
                Imgui.ImGui_ShowDemoWindow(Base.unsafe_convert(Ptr{Bool}, open_flag))
            end
            push!(counts, Int(dd.TotalVtxCount))
            @test dd.Valid
            @test dd.CmdListsCount >= 1
        end
    end

    @test open_flag[] == true          # nothing closed it
    @test all(>(0), counts)
    @test counts[3] == counts[4]       # steady state once laid out

    # And the metrics window, which walks imgui's own internal state
    metrics_open = Ref(true)
    GC.@preserve metrics_open begin
        frame() do
            Imgui.ImGui_ShowMetricsWindow(Base.unsafe_convert(Ptr{Bool}, metrics_open))
        end
        dd = frame() do
            Imgui.ImGui_ShowMetricsWindow(Base.unsafe_convert(Ptr{Bool}, metrics_open))
        end
        @test dd.TotalVtxCount > 0
    end

    Imgui.ImGui_DestroyContext(ctx)
end

end  # top-level testset

println("✓ imgui deep test passed")
