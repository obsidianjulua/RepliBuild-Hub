"""
    BoxWorld

A small physics-sandbox package built on the RepliBuild-generated Box2D 2.4.1
wrapper — the reference example for **driving a wrapped C++ library from a
real Julia package** rather than a verify script.

The layering discipline demonstrated here:

- `lib/` holds RepliBuild's build + wrap output (`Box2d.jl`, `libbox2d.so`,
  `compilation_metadata.json`, `thunk_manifest.json`) exactly as `wrap()`
  produced it. It is the ABI layer; it is never edited.
- `src/BoxWorld.jl` (this file) is the ergonomic layer: Julia-idiomatic types,
  lifecycles, and defaults. Every C++-ism the wrapper cannot hide — ctor-only
  classes, header-inline defaults, abstract shape vtables — is encapsulated
  here, ONCE, behind ordinary Julia functions.

See the RepliBuild documentation page "Using a wrapper in your package" for
the patterns this package pins down (JIT lifecycle, precompilation, pointer
conventions, finalizer discipline).
"""
module BoxWorld

using JSON
using Libdl
using RepliBuild   # the wrapper dispatches Tier 2 through RepliBuild.JITManager

# ── ABI layer: the generated wrapper ──────────────────────────────────────────
# The generated module resolves its shared library sibling-first, so the copy
# in lib/ is self-contained. Its __init__ registers this binary's JIT engine.
include(joinpath(@__DIR__, "..", "lib", "Box2d.jl"))
using .Box2d

export World, destroy!, add_ball!, add_ground!, step!, simulate!,
       body_position, body_velocity, run_demo

# ── Layout facts from DWARF metadata ─────────────────────────────────────────
# Offsets are read from the wrapper's own compilation_metadata.json — never
# hardcoded — so layout drift between wrapper and app fails loudly. Parsed at
# precompile time (the metadata ships inside the package, so baking is safe).
const _META = JSON.parsefile(joinpath(@__DIR__, "..", "lib", "compilation_metadata.json"))

function _field_off(sname::String, mname::String)::Int
    for m in _META["struct_definitions"][sname]["members"]
        m["name"] == mname && return parse(Int, m["offset"])
    end
    error("BoxWorld: member $sname.$mname missing from wrapper metadata — regenerate the wrapper")
end
_struct_size(sname::String) = parse(Int, _META["struct_definitions"][sname]["byte_size"])

const _SZ_WORLD        = _struct_size("b2World")
const _SZ_BODYDEF      = _struct_size("b2BodyDef")
const _SZ_CIRCLE       = _struct_size("b2CircleShape")
const _SZ_POLYGON      = _struct_size("b2PolygonShape")
const _OFF_BD_TYPE     = _field_off("b2BodyDef", "type")
const _OFF_BD_POS      = _field_off("b2BodyDef", "position")
const _OFF_BD_SLEEP    = _field_off("b2BodyDef", "allowSleep")
const _OFF_BD_AWAKE    = _field_off("b2BodyDef", "awake")
const _OFF_BD_ENABLED  = _field_off("b2BodyDef", "enabled")
const _OFF_BD_GRAVSC   = _field_off("b2BodyDef", "gravityScale")
const _OFF_SHAPE_TYPE  = _field_off("b2Shape", "m_type")
const _OFF_SHAPE_RAD   = _field_off("b2Shape", "m_radius")
const _OFF_BODY_XF     = _field_off("b2Body", "m_xf")
const _OFF_BODY_LINVEL = _field_off("b2Body", "m_linearVelocity")

# ── Runtime-only state (never baked into the precompile image) ───────────────
# Vtable address points are process addresses: they MUST be resolved in
# __init__, not at top level, or the precompiled image would carry stale
# pointers. Same discipline as the wrapper's own JIT initialization.
const _CIRCLE_VT = Ref(C_NULL)
const _POLY_VT   = Ref(C_NULL)

function __init__()
    h = Libdl.dlopen(Box2d.LIBRARY_PATH)
    # +16 = past offset-to-top and RTTI to the Itanium vtable address point
    _CIRCLE_VT[] = Libdl.dlsym(h, :_ZTV13b2CircleShape) + 16
    _POLY_VT[]   = Libdl.dlsym(h, :_ZTV14b2PolygonShape) + 16

    # Warm the destructor thunk. World finalizers may fire from GC, and a cold
    # Tier-2 lookup takes a lock on its slow path — warming here keeps the
    # finalizer on the lock-free fast path.
    try
        RepliBuild.JITManager._lookup_cached("_mlir_ciface__ZN7b2WorldD2Ev_thunk")
    catch
        # Tier 2 unavailable (JIT init failed) — destroy! will surface it.
    end
    return nothing
end

# ── World lifecycle ──────────────────────────────────────────────────────────

"""
    World(; gravity = (0.0f0, -10.0f0))

A Box2D world with caller-owned storage.

`b2World` is a ctor-only C++ class (no factory function), so the wrapper
exposes raw bindings only. This constructor owns the pattern once: allocate
`sizeof(b2World)` bytes from the DWARF metadata, invoke the real C++
constructor symbol on that storage, and register a finalizer that runs the
Tier-2 destructor thunk. Call [`destroy!`](@ref) for deterministic teardown;
the finalizer is the safety net.
"""
mutable struct World
    mem::Vector{UInt8}
    ptr::Ptr{Cvoid}
    alive::Bool
    bodies::Vector{Ptr{Cvoid}}

    function World(; gravity::Tuple{Real,Real} = (0.0f0, -10.0f0))
        mem = zeros(UInt8, _SZ_WORLD)
        w = new(mem, C_NULL, false, Ptr{Cvoid}[])
        g = Ref(Box2d.b2Vec2(Float32(gravity[1]), Float32(gravity[2])))
        GC.@preserve mem g begin
            w.ptr = Ptr{Cvoid}(pointer(mem))
            ccall((:_ZN7b2WorldC2ERK6b2Vec2, Box2d.LIBRARY_PATH), Cvoid,
                  (Ptr{Cvoid}, Ptr{Box2d.b2Vec2}),
                  w.ptr, Base.unsafe_convert(Ptr{Box2d.b2Vec2}, g))
        end
        w.alive = true
        finalizer(destroy!, w)
        return w
    end
end

"""
    destroy!(w::World)

Run the C++ destructor (Tier-2 thunk) on the world's storage. Idempotent —
safe to call explicitly and again from the finalizer. Destroys all bodies and
fixtures the world owns.
"""
function destroy!(w::World)
    w.alive || return nothing
    w.alive = false
    empty!(w.bodies)
    Box2d.b2World_destroy_b2World(w.ptr)
    return nothing
end

_check_alive(w::World) = w.alive || error("BoxWorld: world has been destroyed")

# ── Body creation ────────────────────────────────────────────────────────────

# b2BodyDef's default constructor is header-inline — it does not exist as a
# symbol in the compiled library, so its defaults cannot be reached through
# any binding. The app layer replicates them at DWARF offsets (awake, enabled,
# allowSleep true; gravityScale 1), which is exactly what the C++ inline ctor
# compiles to at a call site.
function _bodydef(type::Int32, x::Float32, y::Float32)
    bd = zeros(UInt8, _SZ_BODYDEF)
    p = pointer(bd)
    GC.@preserve bd begin
        unsafe_store!(Ptr{Int32}(p + _OFF_BD_TYPE), type)
        unsafe_store!(Ptr{Cfloat}(p + _OFF_BD_POS), x)
        unsafe_store!(Ptr{Cfloat}(p + _OFF_BD_POS + 4), y)
        unsafe_store!(Ptr{UInt8}(p + _OFF_BD_SLEEP), 0x01)
        unsafe_store!(Ptr{UInt8}(p + _OFF_BD_AWAKE), 0x01)
        unsafe_store!(Ptr{UInt8}(p + _OFF_BD_ENABLED), 0x01)
        unsafe_store!(Ptr{Cfloat}(p + _OFF_BD_GRAVSC), 1.0f0)
    end
    return bd
end

"""
    add_ball!(w::World, x, y; radius=0.5, density=1.0) -> body::Ptr{Cvoid}

Add a dynamic circle body at `(x, y)`. Returns the raw `b2Body*` handle
(owned by the world — do not free it yourself).
"""
function add_ball!(w::World, x::Real, y::Real; radius::Real=0.5, density::Real=1.0)
    _check_alive(w)
    bd = _bodydef(Int32(Box2d.b2_dynamicBody), Float32(x), Float32(y))
    body = GC.@preserve bd Box2d.b2World_CreateBody(w.ptr, Ptr{Cvoid}(pointer(bd)))
    body == C_NULL && error("b2World_CreateBody returned NULL")

    # b2CircleShape is an abstract-base-derived class whose ctor is inline;
    # CreateFixture virtually Clone()s the shape through its vptr. Plant the
    # REAL compiler vtable (resolved in __init__) on zeroed storage.
    shape = zeros(UInt8, _SZ_CIRCLE)
    ps = pointer(shape)
    GC.@preserve shape begin
        unsafe_store!(Ptr{Ptr{Cvoid}}(ps), _CIRCLE_VT[])
        unsafe_store!(Ptr{Int32}(ps + _OFF_SHAPE_TYPE), Int32(0))       # e_circle
        unsafe_store!(Ptr{Cfloat}(ps + _OFF_SHAPE_RAD), Float32(radius))
        fixture = Box2d.b2Body_CreateFixture(body, Ptr{Cvoid}(ps), Float32(density))
        fixture == C_NULL && error("b2Body_CreateFixture returned NULL")
    end
    push!(w.bodies, body)
    return body
end

"""
    add_ground!(w::World; y=0.0, half_width=50.0, half_thickness=0.5) -> body

Add a static box body — a floor — centered at `(0, y)`.
"""
function add_ground!(w::World; y::Real=0.0, half_width::Real=50.0, half_thickness::Real=0.5)
    _check_alive(w)
    bd = _bodydef(Int32(Box2d.b2_staticBody), 0.0f0, Float32(y))
    body = GC.@preserve bd Box2d.b2World_CreateBody(w.ptr, Ptr{Cvoid}(pointer(bd)))
    body == C_NULL && error("b2World_CreateBody returned NULL")

    shape = zeros(UInt8, _SZ_POLYGON)
    ps = pointer(shape)
    GC.@preserve shape begin
        unsafe_store!(Ptr{Ptr{Cvoid}}(ps), _POLY_VT[])
        unsafe_store!(Ptr{Int32}(ps + _OFF_SHAPE_TYPE), Int32(2))       # e_polygon
        # b2PolygonShape's inline ctor sets m_radius = b2_polygonRadius
        # (2 * b2_linearSlop = 0.01 at 1 length-unit/meter)
        unsafe_store!(Ptr{Cfloat}(ps + _OFF_SHAPE_RAD),
                      0.01f0 * Box2d.b2_lengthUnitsPerMeter())
        Box2d.b2PolygonShape_SetAsBox(Ptr{Cvoid}(ps),
                                      Float32(half_width), Float32(half_thickness))
        fixture = Box2d.b2Body_CreateFixture(body, Ptr{Cvoid}(ps), 0.0f0)
        fixture == C_NULL && error("b2Body_CreateFixture returned NULL")
    end
    push!(w.bodies, body)
    return body
end

# ── Simulation ───────────────────────────────────────────────────────────────

"""
    step!(w::World; dt=1/60, velocity_iterations=6, position_iterations=2)

Advance the world one physics step (a Tier-2 MLIR thunk call).
"""
function step!(w::World; dt::Real=1/60, velocity_iterations::Integer=6,
               position_iterations::Integer=2)
    _check_alive(w)
    Box2d.b2World_Step(w.ptr, Float32(dt), Int32(velocity_iterations),
                       Int32(position_iterations))
    return w
end

"""
    simulate!(w::World, nsteps; kwargs...) -> w

Run `nsteps` physics steps.
"""
function simulate!(w::World, nsteps::Integer; kwargs...)
    for _ in 1:nsteps
        step!(w; kwargs...)
    end
    return w
end

# GetPosition/GetLinearVelocity are header-inline in Box2D — they never exist
# as symbols, so no wrapper can bind them. Read the members directly at their
# DWARF offsets instead (b2Transform's first member is the position b2Vec2).
"""
    body_position(body) -> (x, y)
"""
body_position(body::Ptr) =
    (unsafe_load(Ptr{Cfloat}(body + _OFF_BODY_XF)),
     unsafe_load(Ptr{Cfloat}(body + _OFF_BODY_XF + 4)))

"""
    body_velocity(body) -> (vx, vy)
"""
body_velocity(body::Ptr) =
    (unsafe_load(Ptr{Cfloat}(body + _OFF_BODY_LINVEL)),
     unsafe_load(Ptr{Cfloat}(body + _OFF_BODY_LINVEL + 4)))

# ── Demo ─────────────────────────────────────────────────────────────────────

"""
    run_demo(; nsteps=180)

Drop three balls onto a floor and print their descent as a tiny ASCII strip
chart. Pure Tier-2 physics: every step and every body creation dispatches
through the MLIR JIT.
"""
function run_demo(; nsteps::Integer=180)
    w = World()
    try
        add_ground!(w; y=0.0)
        balls = [add_ball!(w, -2.0, 8.0; radius=0.5),
                 add_ball!(w,  0.0, 6.0; radius=0.5),
                 add_ball!(w,  2.0, 10.0; radius=0.5)]
        println("step   ball1_y   ball2_y   ball3_y")
        for s in 1:nsteps
            step!(w)
            if s % 30 == 0
                ys = [body_position(b)[2] for b in balls]
                bars = [repeat("█", max(0, round(Int, y * 2))) for y in ys]
                println(rpad(s, 6),
                        join((rpad(string(round(y, digits=2)), 10) for y in ys)))
                for (i, bar) in enumerate(bars)
                    println("       ball$(i) |", bar)
                end
            end
        end
        ys = [body_position(b)[2] for b in balls]
        println("\nAt rest: ", join((string(round(y, digits=3)) for y in ys), ", "),
                "  (expected ≈ ball radius above the floor surface)")
        return ys
    finally
        destroy!(w)
    end
end

end # module BoxWorld
