#!/usr/bin/env julia
# Bullet3 Hub package — deep test of the C++ rigid-body pipeline.
#
# The headline is upstream's own HelloWorld, built through the wrapper: a
# collision configuration, dispatcher, broadphase, solver and dynamics world;
# a static ground plane; a 1 kg box dropped from y = 10. Every object is a real
# C++ object made by its real constructor (C2 thunk) on storage from Bullet's
# own aligned allocator, which is what Bullet's class-level operator new does.
#
# What it pins, and why:
#   - every Julia struct's layout against the DWARF tables in the same wrapper
#     (a by-value record that is off by one field corrupts silently);
#   - a record crossing BY REFERENCE into a constructor: the box is built from
#     a btRigidBodyConstructionInfo whose start transform puts it at y = 10;
#   - a record RETURNED by value (getGravity → btVector3);
#   - an out-parameter written by C++ (calculateLocalInertia);
#   - the physics itself, against an independent oracle: Bullet integrates
#     semi-implicit Euler at a fixed 1/60 s step, so after n free-fall steps
#     y = 10 - g·dt²·n(n+1)/2 exactly (up to Float32 rounding). Then the box
#     must land and come to rest on the plane at its half-extent, 0.5.
#
# btDefaultMotionState, btSphereShape and btRigidBodyConstructionInfo's
# constructors are header inlines with no symbol of their own; the package
# compiles them in (shims/inline_ctors.cpp: bt_new_SphereShape,
# bt_new_DefaultMotionState, bt_new_RigidBodyConstructionInfo, each building in
# place). The box scenario still fills its construction info by hand, which
# checks a Julia-built record crossing into a constructor; the sphere scenario
# uses the real constructors throughout, as upstream's HelloWorld does, and
# checks the hand-written defaults against the real ones.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/bullet3/test_deep.jl

using Test, Libdl

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Bullet3.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)
import .Bullet3 as B          # never `using` a C++ wrapper — see the Hub notes

v3(x, y, z) = B.btVector3((Float32(x), Float32(y), Float32(z), 0.0f0))
xyz(v::B.btVector3) = (v.m_floats[1], v.m_floats[2], v.m_floats[3])
const IDENTITY = B.btMatrix3x3((v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1)))

# Storage for one C++ object of `name`, from Bullet's allocator (16-aligned).
new_storage(name) = B.btAlignedAllocInternal(B.struct_size(name), 16)

origin(body) = unsafe_load(Ptr{B.btVector3}(body +
    B.member_offset(:btCollisionObject, :m_worldTransform) +
    B.member_offset(:btTransform, :m_origin)))
linvel(body) = unsafe_load(Ptr{B.btVector3}(body + B.member_offset(:btRigidBody, :m_linearVelocity)))

@testset "Bullet3 Deep Tests" begin

@testset "layouts agree with DWARF" begin
    bad = String[]
    for (sname, offs) in B.STRUCT_OFFSETS
        isdefined(B, sname) || continue
        T = getfield(B, sname)
        (T isa DataType && isstructtype(T) && fieldcount(T) > 0) || continue
        for (i, f) in enumerate(fieldnames(T))
            haskey(offs, f) && fieldoffset(T, i) != offs[f] &&
                push!(bad, "$sname.$f julia=$(fieldoffset(T, i)) dwarf=$(offs[f])")
        end
        haskey(B.STRUCT_SIZES, sname) && sizeof(T) != B.STRUCT_SIZES[sname] &&
            push!(bad, "$sname sizeof julia=$(sizeof(T)) dwarf=$(B.STRUCT_SIZES[sname])")
    end
    @test isempty(bad)
    # Single precision, 4-float vectors (the w lane is padding).
    @test sizeof(B.btVector3) == 16
    @test sizeof(B.btTransform) == 64
    @test sizeof(B.btRigidBodyConstructionInfo) == B.struct_size(:btRigidBodyConstructionInfo)
end

@testset "HelloWorld: a box falls onto a plane" begin
    lib = Libdl.dlopen(B.LIBRARY_PATH)

    # ── The world ─────────────────────────────────────────────────────────
    # btDefaultCollisionConstructionInfo's defaults (btDefaultCollisionConfiguration.h)
    info = Ref(B.btDefaultCollisionConstructionInfo(C_NULL, C_NULL, 4096, 4096, 0, 1))
    cfg = new_storage(:btDefaultCollisionConfiguration)
    B.btDefaultCollisionConfiguration_btDefaultCollisionConfiguration(cfg, info)
    disp = new_storage(:btCollisionDispatcher)
    B.btCollisionDispatcher_btCollisionDispatcher(disp, cfg)
    bp = new_storage(:btDbvtBroadphase)
    B.btDbvtBroadphase_btDbvtBroadphase(bp, C_NULL)
    solver = new_storage(:btSequentialImpulseConstraintSolver)
    B.btSequentialImpulseConstraintSolver_btSequentialImpulseConstraintSolver(solver)
    world = new_storage(:btDiscreteDynamicsWorld)
    B.btDiscreteDynamicsWorld_btDiscreteDynamicsWorld(world, disp, bp, solver, cfg)
    @test all(!=(C_NULL), (cfg, disp, bp, solver, world))

    # The real constructor ran: the object's vptr is the class's vtable
    # address point (two words past the symbol: offset-to-top, RTTI).
    @test unsafe_load(Ptr{Ptr{Cvoid}}(world)) ==
          Libdl.dlsym(lib, :_ZTV23btDiscreteDynamicsWorld) + 16

    B.btDiscreteDynamicsWorld_setGravity(world, Ref(v3(0, -10, 0)))
    @test xyz(B.btDiscreteDynamicsWorld_getGravity(world)) == (0.0f0, -10.0f0, 0.0f0)

    # ── The ground: static plane y = 0, mass 0, 4-argument constructor ────
    plane = new_storage(:btStaticPlaneShape)
    B.btStaticPlaneShape_btStaticPlaneShape(plane, Ref(v3(0, 1, 0)), 0.0f0)
    ground = new_storage(:btRigidBody)
    B.btRigidBody_btRigidBody(ground, 0.0f0, C_NULL, plane, Ref(v3(0, 0, 0)))
    B.btDiscreteDynamicsWorld_addRigidBody(world, ground)

    # ── The box: 1 kg, half-extent 0.5, from a construction info ──────────
    # btBoxShape adds methods but no data members to btPolyhedralConvexShape.
    # Since RepliBuild 2026-11-14 (GENERATOR-memberless-class-size.md, fixed)
    # such a record has its own entry: its size is its base's, 0x50, and its
    # Julia type carries the base's fields.
    @test B.struct_size(:btBoxShape) == 0x50
    @test B.struct_size(:btBoxShape) == B.struct_size(:btPolyhedralConvexShape)
    @test sizeof(B.btBoxShape) == 0x50
    box = new_storage(:btBoxShape)
    B.btBoxShape_btBoxShape(box, Ref(v3(0.5, 0.5, 0.5)))
    @test B.btBoxShape_getName(box) == "Box"
    @test unsafe_load(Ptr{Ptr{Cvoid}}(box)) == Libdl.dlsym(lib, :_ZTV10btBoxShape) + 16

    inertia = Ref(v3(0, 0, 0))
    B.btBoxShape_calculateLocalInertia(box, 1.0f0, inertia)
    # mass/12 · (ly² + lz²) with l = 2 · half-extent = 1  →  1/6 on each axis
    @test all(isapprox.(xyz(inertia[]), 1 / 6; atol = 1e-6))

    # btRigidBodyConstructionInfo's inline constructor, spelled out.
    ci = Ref(B.btRigidBodyConstructionInfo(
        1.0f0, ntuple(_ -> 0x00, 4),
        Ptr{B.btMotionState}(C_NULL),
        B.btTransform(IDENTITY, v3(0, 10, 0)),          # start at y = 10
        Ptr{B.btCollisionShape}(box),
        inertia[],
        0.0f0, 0.0f0,          # linear / angular damping
        0.5f0, 0.0f0, 0.0f0,   # friction, rolling, spinning
        0.0f0,                 # restitution
        0.8f0, 1.0f0,          # sleeping thresholds
        false, ntuple(_ -> 0x00, 3),
        0.005f0, 0.01f0, 0.01f0, 0.01f0,
        ntuple(_ -> 0x00, 4)))
    body = new_storage(:btRigidBody)
    B.btRigidBody_btRigidBody(body, ci)
    @test xyz(origin(body)) == (0.0f0, 10.0f0, 0.0f0)
    B.btDiscreteDynamicsWorld_addRigidBody(world, body)

    # ── Free fall, against the integrator's closed form ──────────────────
    dt = 1.0f0 / 60
    substeps = [B.btDiscreteDynamicsWorld_stepSimulation(world, dt, 1, dt) for _ in 1:30]
    @test all(==(1), substeps)
    n = 30
    @test origin(body).m_floats[2] ≈ 10 - 10 * dt^2 * n * (n + 1) / 2  atol = 1e-3   # 8.7083
    @test linvel(body).m_floats[2] ≈ -10 * dt * n  atol = 1e-3               # -5.0
    @test abs(origin(body).m_floats[1]) < 1e-5 && abs(origin(body).m_floats[3]) < 1e-5
    @test origin(ground).m_floats[2] == 0.0f0          # static: never moves

    # ── Landing: rest on the plane at the half-extent ─────────────────────
    for _ in 1:210                                     # 4 s simulated in all
        B.btDiscreteDynamicsWorld_stepSimulation(world, dt, 1, dt)
    end
    y = origin(body).m_floats[2]
    @test 0.45f0 < y < 0.55f0
    @test all(abs.(xyz(linvel(body))) .< 0.05f0)

    # ── Teardown, in upstream's order ─────────────────────────────────────
    B.btDiscreteDynamicsWorld_removeRigidBody(world, body)
    B.btDiscreteDynamicsWorld_removeRigidBody(world, ground)
    B.btRigidBody_destroy_btRigidBody(body)
    B.btRigidBody_destroy_btRigidBody(ground)
    # btBoxShape's destructor is implicit: the library holds only the deleting
    # variant (D0, the vtable's), no D1/D2. Since RepliBuild 2026-11-14
    # (GENERATOR-deleting-dtor-as-destroy.md, fixed) that binding is
    # `btBoxShape_delete_btBoxShape`: it runs ~btBoxShape() AND frees the
    # storage through Bullet's operator delete (btAlignedFree, the allocator
    # new_storage used), so the box is not freed again below. There is no
    # `btBoxShape_destroy_btBoxShape`.
    @test Libdl.dlsym_e(lib, :_ZN10btBoxShapeD2Ev) == C_NULL
    @test Libdl.dlsym_e(lib, :_ZN10btBoxShapeD0Ev) != C_NULL
    @test !isdefined(B, :btBoxShape_destroy_btBoxShape)
    B.btBoxShape_delete_btBoxShape(box)         # destroys and frees
    B.btStaticPlaneShape_destroy_btStaticPlaneShape(plane)
    B.btDiscreteDynamicsWorld_destroy_btDiscreteDynamicsWorld(world)
    B.btSequentialImpulseConstraintSolver_destroy_btSequentialImpulseConstraintSolver(solver)
    B.btDbvtBroadphase_destroy_btDbvtBroadphase(bp)
    B.btCollisionDispatcher_destroy_btCollisionDispatcher(disp)
    B.btDefaultCollisionConfiguration_destroy_btDefaultCollisionConfiguration(cfg)
    foreach(B.btAlignedFreeInternal, (body, ground, plane, world, solver, bp, disp, cfg))
    Libdl.dlclose(lib)
    @test true   # reached the end without a crash
end

@testset "header-only constructors: a sphere with a motion state" begin
    lib = Libdl.dlopen(B.LIBRARY_PATH)

    # A world, as above.
    info = Ref(B.btDefaultCollisionConstructionInfo(C_NULL, C_NULL, 4096, 4096, 0, 1))
    cfg = new_storage(:btDefaultCollisionConfiguration)
    B.btDefaultCollisionConfiguration_btDefaultCollisionConfiguration(cfg, info)
    disp = new_storage(:btCollisionDispatcher);  B.btCollisionDispatcher_btCollisionDispatcher(disp, cfg)
    bp = new_storage(:btDbvtBroadphase);         B.btDbvtBroadphase_btDbvtBroadphase(bp, C_NULL)
    solver = new_storage(:btSequentialImpulseConstraintSolver)
    B.btSequentialImpulseConstraintSolver_btSequentialImpulseConstraintSolver(solver)
    world = new_storage(:btDiscreteDynamicsWorld)
    B.btDiscreteDynamicsWorld_btDiscreteDynamicsWorld(world, disp, bp, solver, cfg)
    B.btDiscreteDynamicsWorld_setGravity(world, Ref(v3(0, -10, 0)))
    plane = new_storage(:btStaticPlaneShape)
    B.btStaticPlaneShape_btStaticPlaneShape(plane, Ref(v3(0, 1, 0)), 0.0f0)
    ground = new_storage(:btRigidBody)
    B.btRigidBody_btRigidBody(ground, 0.0f0, C_NULL, plane, Ref(v3(0, 0, 0)))
    B.btDiscreteDynamicsWorld_addRigidBody(world, ground)

    # ── btSphereShape(1.0): its inline constructor, compiled in ──────────
    @test B.struct_size(:btSphereShape) == 72
    sphere = new_storage(:btSphereShape)
    @test B.bt_new_SphereShape(sphere, 1.0f0) == sphere              # built in place
    @test unsafe_load(Ptr{Ptr{Cvoid}}(sphere)) == Libdl.dlsym(lib, :_ZTV13btSphereShape) + 16
    @test B.btSphereShape_getName(sphere) == "SPHERE"
    inertia = Ref(v3(0, 0, 0))
    B.btSphereShape_calculateLocalInertia(sphere, 1.0f0, inertia)
    @test all(isapprox.(xyz(inertia[]), 0.4; atol = 1e-6))           # 2/5 · m · r²

    # ── btDefaultMotionState(start at y = 20) ─────────────────────────────
    ms = new_storage(:btDefaultMotionState)
    start = Ref(B.btTransform(IDENTITY, v3(0, 20, 0)))
    @test B.bt_new_DefaultMotionState(ms, start) == ms
    @test unsafe_load(Ptr{Ptr{Cvoid}}(ms)) == Libdl.dlsym(lib, :_ZTV20btDefaultMotionState) + 16
    got = Ref(B.btTransform(IDENTITY, v3(0, 0, 0)))
    B.btDefaultMotionState_getWorldTransform(ms, got)
    @test xyz(got[].m_origin) == (0.0f0, 20.0f0, 0.0f0)

    # ── btRigidBodyConstructionInfo(1, ms, sphere, inertia): the REAL defaults
    ci = new_storage(:btRigidBodyConstructionInfo)
    @test B.bt_new_RigidBodyConstructionInfo(ci, 1.0f0, ms, sphere, inertia) == ci
    c = unsafe_load(Ptr{B.btRigidBodyConstructionInfo}(ci))
    @test c.m_mass == 1 && c.m_motionState == Ptr{B.btMotionState}(ms)
    @test c.m_collisionShape == Ptr{B.btCollisionShape}(sphere)
    @test xyz(c.m_localInertia) == xyz(inertia[])
    # The values the box scenario typed in by hand are upstream's defaults.
    @test (c.m_linearDamping, c.m_angularDamping) == (0.0f0, 0.0f0)
    @test (c.m_friction, c.m_rollingFriction, c.m_spinningFriction) == (0.5f0, 0.0f0, 0.0f0)
    @test c.m_restitution == 0.0f0
    @test (c.m_linearSleepingThreshold, c.m_angularSleepingThreshold) == (0.8f0, 1.0f0)
    @test c.m_additionalDamping == false
    @test (c.m_additionalDampingFactor, c.m_additionalLinearDampingThresholdSqr,
           c.m_additionalAngularDampingThresholdSqr, c.m_additionalAngularDampingFactor) ==
          (0.005f0, 0.01f0, 0.01f0, 0.01f0)
    @test c.m_startWorldTransform.m_basis == IDENTITY

    # ── The body takes its start from the motion state, as in HelloWorld ──
    body = new_storage(:btRigidBody)
    B.btRigidBody_btRigidBody(body, Ptr{B.btRigidBodyConstructionInfo}(ci))
    @test xyz(origin(body)) == (0.0f0, 20.0f0, 0.0f0)
    B.btDiscreteDynamicsWorld_addRigidBody(world, body)

    dt = 1.0f0 / 60
    for _ in 1:300                                     # 5 s
        B.btDiscreteDynamicsWorld_stepSimulation(world, dt, 1, dt)
    end
    # The world wrote the body's pose back into the motion state, and the
    # sphere rests on the plane at its radius.
    B.btDefaultMotionState_getWorldTransform(ms, got)
    @test 0.95f0 < got[].m_origin.m_floats[2] < 1.05f0
    @test got[].m_origin.m_floats[2] ≈ origin(body).m_floats[2]  atol = 1e-4

    # ── Teardown ──────────────────────────────────────────────────────────
    B.btDiscreteDynamicsWorld_removeRigidBody(world, body)
    B.btDiscreteDynamicsWorld_removeRigidBody(world, ground)
    B.btRigidBody_destroy_btRigidBody(body)
    B.btRigidBody_destroy_btRigidBody(ground)
    # Both have implicit destructors, so only D0 exists: `delete_` destroys
    # AND frees (Bullet's operator delete, btAlignedFree — new_storage's).
    B.btSphereShape_delete_btSphereShape(sphere)
    B.btDefaultMotionState_delete_btDefaultMotionState(ms)
    B.btStaticPlaneShape_destroy_btStaticPlaneShape(plane)
    B.btDiscreteDynamicsWorld_destroy_btDiscreteDynamicsWorld(world)
    B.btSequentialImpulseConstraintSolver_destroy_btSequentialImpulseConstraintSolver(solver)
    B.btDbvtBroadphase_destroy_btDbvtBroadphase(bp)
    B.btCollisionDispatcher_destroy_btCollisionDispatcher(disp)
    B.btDefaultCollisionConfiguration_destroy_btDefaultCollisionConfiguration(cfg)
    # The construction info is a trivially destructible struct: just free it.
    foreach(B.btAlignedFreeInternal, (ci, body, ground, plane, world, solver, bp, disp, cfg))
    Libdl.dlclose(lib)
    @test true
end

end
