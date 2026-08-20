#!/usr/bin/env julia
# packages/box2d/test.jl — exercise the Box2D 2.4.1 (C++) wrapper
#
# The headline test is a real simulation: build a world (raw C++ ctor — see
# note), drop a dynamic body with a circle fixture, step 60 frames of
# Tier-2-dispatched physics, and assert gravity did its job. Along the way it
# exercises the C++-specific machinery: Tier-2 method thunks, a REAL compiler
# vtable driven through a hand-planted vptr (CreateFixture virtual-Clones the
# shape), enum exports, varargs dump shims (file round-trip), and value-macro
# shims.
#
# Construction note: b2World has no factory function, so the wrapper leaves it
# as raw bindings (documented GeneratorCpp policy for ctor-only C++ classes).
# The test constructs via the public C2 ctor symbol + metadata byte_size —
# the same pattern the tinyxml2 verification used. All struct offsets come
# from compilation_metadata.json at runtime, so layout drift fails loudly
# here instead of corrupting silently.

using Test
using Libdl
using JSON

include(joinpath(@__DIR__, "julia", "Box2d.jl"))
using .Box2d

const LIB  = Box2d.LIBRARY_PATH
const META = JSON.parsefile(joinpath(@__DIR__, "julia", "compilation_metadata.json"))

# Emitted by the wrapper now (STRUCT_SIZES / STRUCT_OFFSETS), read from the
# same DWARF the module was generated from — one derivation, not two.
field_off(sname, mname) = Box2d.member_offset(sname, mname)
struct_size(sname) = Box2d.struct_size(sname)

@testset "Box2D 2.4.1 (C++)" begin

    # ── Value-macro shims ───────────────────────────────────────────────────
    @testset "macro shims" begin
        @test Box2d.b2_pi() ≈ Float32(π)
        @test Box2d.b2_maxPolygonVertices() == 8
        @test Box2d.b2_lengthUnitsPerMeter() == 1.0f0
        @test Box2d.b2_maxManifoldPoints() == 2
    end

    # ── Enums ───────────────────────────────────────────────────────────────
    @testset "enums" begin
        @test Int(Box2d.b2_staticBody) == 0
        @test Int(Box2d.b2_kinematicBody) == 1
        @test Int(Box2d.b2_dynamicBody) == 2
        @test Int(Box2d.e_revoluteJoint) == 1
    end

    # ── Varargs dump shims: file round-trip ─────────────────────────────────
    @testset "varargs b2Dump shims" begin
        dumppath = tempname()
        Box2d.b2OpenDump(dumppath)
        Box2d.b2Dump_Cint("test int %d\n", Int32(42))
        # Variadic Cstring args are typed strictly — convert explicitly
        arg_s = "x"
        GC.@preserve arg_s begin
            Box2d.b2Dump_Cstring_Cint("pair %s %d\n",
                                      Base.unsafe_convert(Cstring, arg_s), Int32(7))
        end
        Box2d.b2CloseDump()
        txt = read(dumppath, String)
        rm(dumppath, force=true)
        @test contains(txt, "test int 42")
        @test contains(txt, "pair x 7")
    end

    # ── The simulation: world → body → fixture → 60 steps → gravity ────────
    @testset "falling body simulation" begin
        world_mem = zeros(UInt8, struct_size("b2World"))
        bd_mem    = zeros(UInt8, struct_size("b2BodyDef"))
        shape_mem = zeros(UInt8, struct_size("b2CircleShape"))
        gravity   = Ref(Box2d.b2Vec2(0.0f0, -10.0f0))

        GC.@preserve world_mem bd_mem shape_mem gravity begin
            # b2World: raw C++ ctor on caller-allocated storage (see header note)
            wp = Ptr{Cvoid}(pointer(world_mem))
            ccall((:_ZN7b2WorldC2ERK6b2Vec2, LIB), Cvoid,
                  (Ptr{Cvoid}, Ptr{Box2d.b2Vec2}),
                  wp, Base.unsafe_convert(Ptr{Box2d.b2Vec2}, gravity))

            # b2BodyDef: byte-built at DWARF offsets, replicating the inline
            # C++ default ctor (awake/enabled/allowSleep true, gravityScale 1)
            pbd = pointer(bd_mem)
            unsafe_store!(Ptr{Int32}(pbd + field_off("b2BodyDef", "type")), Int32(Box2d.b2_dynamicBody))
            unsafe_store!(Ptr{Cfloat}(pbd + field_off("b2BodyDef", "position")), 0.0f0)       # x
            unsafe_store!(Ptr{Cfloat}(pbd + field_off("b2BodyDef", "position") + 4), 10.0f0)  # y
            for f in ("allowSleep", "awake", "enabled")
                unsafe_store!(Ptr{UInt8}(pbd + field_off("b2BodyDef", f)), 0x01)
            end
            unsafe_store!(Ptr{Cfloat}(pbd + field_off("b2BodyDef", "gravityScale")), 1.0f0)

            body = Box2d.b2World_CreateBody(wp, Ptr{Cvoid}(pbd))   # Tier-2 thunk
            @test body != C_NULL
            bp = Ptr{Cvoid}(body)
            @test unsafe_load(Ptr{Int32}(bp + field_off("b2Body", "m_type"))) == Int32(2)

            # b2CircleShape: hand-planted REAL vtable (address point = symbol
            # + 16 past offset-to-top and RTTI). CreateFixture virtual-calls
            # Clone() through this vptr — compiler-vtable dispatch, live.
            libh = Libdl.dlopen(LIB)
            vt = Libdl.dlsym(libh, :_ZTV13b2CircleShape)
            ps = pointer(shape_mem)
            unsafe_store!(Ptr{Ptr{Cvoid}}(ps), vt + 16)
            unsafe_store!(Ptr{Int32}(ps + field_off("b2Shape", "m_type")), Int32(0))   # e_circle
            unsafe_store!(Ptr{Cfloat}(ps + field_off("b2Shape", "m_radius")), 0.5f0)
            # m_p stays (0,0)

            fixture = Box2d.b2Body_CreateFixture(body, Ptr{Cvoid}(ps), 1.0f0)
            @test fixture != C_NULL

            # 60 Tier-2 steps = 1 simulated second of free fall
            for _ in 1:60
                Box2d.b2World_Step(wp, Float32(1/60), Int32(6), Int32(2))
            end

            # Position readback straight from b2Body.m_xf (GetPosition is a
            # header inline — not a symbol). Free fall from y=10 under
            # g=-10: expect roughly y ≈ 5, definitely below 9 and above 0.
            xf = field_off("b2Body", "m_xf")
            px = unsafe_load(Ptr{Cfloat}(bp + xf))
            py = unsafe_load(Ptr{Cfloat}(bp + xf + 4))
            @test abs(px) < 1e-4
            @test 0.0f0 < py < 9.0f0

            # Teardown: Tier-2 dtor thunk (frees bodies/fixtures internally)
            Box2d.b2World_destroy_b2World(wp)
            Libdl.dlclose(libh)
        end
    end
end

println("✓ box2d test passed")
