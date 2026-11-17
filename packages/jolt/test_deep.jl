#!/usr/bin/env julia
# Jolt Physics Hub package: deep test.
#
# The headline is upstream's HelloWorld scene (HelloWorld/HelloWorld.cpp)
# driven through the wrapper: a static 200×2×200 box floor, a 0.5 m sphere
# dropped from y = 2 at -5 m/s, 1/60 s steps. The same scene, compiled in C++
# against the same libjolt.so (fixtures/hello_ref.cpp), is the oracle: with
# JobSystemSingleThreaded Jolt is deterministic, so the Julia trajectory must
# match it BIT FOR BIT (position, velocity, active flag) every step.
#
# Every C++ object is built in place by its real constructor, on storage from
# the class's own `operator new` (Jolt's allocator), as `new T(...)` does.
# The three layer classes upstream hand-writes as subclasses are Jolt's own
# header-only *Table classes, made visible by the recipe's [types] records.
#
# Workarounds this exercises, each with its GENERATOR report:
#   * JoltHub_* (shims/jolt_hub.cpp): every call that passes Vec3/Quat by value
#     (GENERATOR-simd-by-value-trapped.md), plus Factory_New / RegisterTypes;
#   * the build without CPU compute (GENERATOR-fragment-header-in-forced-unit.md)
#     is what makes SphereShape/BodyCreationSettings/TempAllocatorImpl/the
#     tables constructible at all;
#   * overrides/ LargeIslandSplitter.h (GENERATOR-uint64-enum-overflow.md) is
#     what lets the wrapper exist.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/jolt/test_deep.jl

using Test, Libdl, TOML

const PKG_DIR = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")
const WRAPPER = joinpath(PKG_DIR, "julia", "Jolt.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(TOML_PATH)
    RepliBuild.wrap(TOML_PATH)
end

include(WRAPPER)
import .Jolt as J            # never `using` a C++ wrapper: thousands of exports

# ── value types: Vec3/Quat are one __m128 each (16 opaque bytes in Julia) ──
# Jolt keeps a Vec3's w lane equal to z (Vec3.inl), so build them that way.
vec3(x, y, z) = J.Vec3(J.Vec3_anon1(reinterpret(NTuple{16,UInt8}, (Float32(x), Float32(y), Float32(z), Float32(z)))))
lanes(v::J.Vec3) = reinterpret(NTuple{4,Float32}, v._anon1.data)
xyz(v::J.Vec3) = lanes(v)[1:3]
bits(v::J.Vec3) = map(f -> reinterpret(UInt32, f), xyz(v))
const QUAT_IDENTITY = J.Quat(J.Vec4(J.Vec4_anon1(reinterpret(NTuple{16,UInt8}, (0f0, 0f0, 0f0, 1f0)))))

# Jolt/Physics/Body/MotionType.h, Jolt/Physics/EActivation.h
const STATIC, DYNAMIC = 0, 2
const ACTIVATE, DONT_ACTIVATE = 0, 1
const NON_MOVING, MOVING = UInt16(0), UInt16(1)
const DT = 1f0 / 60f0

# `new T(args...)`: the class's operator new, then its in-place constructor.
function cpp_new(T::Symbol, ctor, args...)
    p = getfield(J, Symbol("JPH_", T, "_operator_new"))(J.struct_size(T))
    @assert p != C_NULL && UInt(p) % 16 == 0
    ctor(p, args...)
    return Ptr{getfield(J, T)}(p)
end
# `delete p`: the complete destructor, then the class's operator delete.
function cpp_delete(T::Symbol, p)
    getfield(J, Symbol("JPH_", T, "_destroy_", T))(p)
    getfield(J, Symbol("JPH_", T, "_operator_delete"))(Ptr{Cvoid}(p))
end

const FACTORY_INSTANCE = Ptr{Ptr{Cvoid}}(dlsym(dlopen(J.LIBRARY_PATH), :_ZN3JPH7Factory9sInstanceE))

"Upstream HelloWorld's setup. Returns everything teardown needs."
function hello_world()
    temp = cpp_new(:TempAllocatorImpl, J.JPH_TempAllocatorImpl_TempAllocatorImpl, 10 * 1024 * 1024)
    jobs = cpp_new(:JobSystemSingleThreaded, J.JPH_JobSystemSingleThreaded_JobSystemSingleThreaded, 2048) # cMaxPhysicsJobs

    pairs = cpp_new(:ObjectLayerPairFilterTable, J.JPH_ObjectLayerPairFilterTable_ObjectLayerPairFilterTable, 2)
    J.JPH_ObjectLayerPairFilterTable_EnableCollision(pairs, NON_MOVING, MOVING)
    J.JPH_ObjectLayerPairFilterTable_EnableCollision(pairs, MOVING, MOVING)
    bp = cpp_new(:BroadPhaseLayerInterfaceTable, J.JPH_BroadPhaseLayerInterfaceTable_BroadPhaseLayerInterfaceTable, 2, 2)
    J.JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(bp, NON_MOVING, J.BroadPhaseLayer(0x00))
    J.JPH_BroadPhaseLayerInterfaceTable_MapObjectToBroadPhaseLayer(bp, MOVING, J.BroadPhaseLayer(0x01))
    ovb = cpp_new(:ObjectVsBroadPhaseLayerFilterTable, J.JPH_ObjectVsBroadPhaseLayerFilterTable_ObjectVsBroadPhaseLayerFilterTable,
                  Ptr{J.BroadPhaseLayerInterface}(bp), 2, Ptr{J.ObjectLayerPairFilter}(pairs), 2)

    ps = cpp_new(:PhysicsSystem, J.JPH_PhysicsSystem_PhysicsSystem)
    J.JPH_PhysicsSystem_Init(ps, 1024, 0, 1024, 1024, Ptr{J.BroadPhaseLayerInterface}(bp),
                             Ptr{J.ObjectVsBroadPhaseLayerFilter}(ovb), Ptr{J.ObjectLayerPairFilter}(pairs))
    bi = J.JPH_PhysicsSystem_GetBodyInterface(ps)

    floor_shape = cpp_new(:BoxShape, J.JoltHub_BoxShape_BoxShape, Ref(vec3(100, 1, 100)), 0.05f0) # cDefaultConvexRadius
    sphere_shape = cpp_new(:SphereShape, J.JPH_SphereShape_SphereShape, 0.5f0)

    ids = J.BodyID[]
    for (shape, pos, motion, layer, act) in ((floor_shape, vec3(0, -1, 0), STATIC, NON_MOVING, DONT_ACTIVATE),
                                             (sphere_shape, vec3(0, 2, 0), DYNAMIC, MOVING, ACTIVATE))
        bcs = cpp_new(:BodyCreationSettings, J.JoltHub_BodyCreationSettings_BodyCreationSettings,
                      shape, Ref(pos), Ref(QUAT_IDENTITY), motion, layer)
        push!(ids, J.JPH_BodyInterface_CreateAndAddBody(bi, bcs, act))
        cpp_delete(:BodyCreationSettings, bcs)       # the body keeps its own reference to the shape
    end
    floor_id, sphere_id = ids
    J.JoltHub_BodyInterface_SetLinearVelocity(bi, sphere_id, Ref(vec3(0, -5, 0)))
    J.JPH_PhysicsSystem_OptimizeBroadPhase(ps)
    return (; temp, jobs, pairs, bp, ovb, ps, bi, floor_id, sphere_id)
end

function state(w)
    p = Ref(vec3(0, 0, 0)); v = Ref(vec3(0, 0, 0))
    J.JoltHub_BodyInterface_GetCenterOfMassPosition(w.bi, w.sphere_id, p)
    J.JoltHub_BodyInterface_GetLinearVelocity(w.bi, w.sphere_id, v)
    return (p[], v[], J.JPH_BodyInterface_IsActive(w.bi, Ref(w.sphere_id)))
end

step!(w) = J.JPH_PhysicsSystem_Update(w.ps, DT, 1, w.temp, w.jobs)

function teardown(w)
    for id in (w.sphere_id, w.floor_id)
        J.JPH_BodyInterface_RemoveBody(w.bi, Ref(id))
        J.JPH_BodyInterface_DestroyBody(w.bi, Ref(id))   # last reference: the shape is freed too
    end
    cpp_delete(:PhysicsSystem, w.ps)
    cpp_delete(:ObjectVsBroadPhaseLayerFilterTable, w.ovb)
    cpp_delete(:BroadPhaseLayerInterfaceTable, w.bp)
    cpp_delete(:ObjectLayerPairFilterTable, w.pairs)
    cpp_delete(:JobSystemSingleThreaded, w.jobs)
    cpp_delete(:TempAllocatorImpl, w.temp)
end

# The C++ reference: compiled with the recipe's own flags and include dirs,
# linked against the wrapper's libjolt.so.
function reference_trajectory(steps)
    cfg = TOML.parsefile(TOML_PATH)["compile"]
    incs = ["-I" * joinpath(PKG_DIR, d) for d in cfg["include_dirs"]]
    flags = filter(f -> f != "-fstandalone-debug", cfg["flags"])
    libdir = dirname(J.LIBRARY_PATH)
    exe = joinpath(mktempdir(), "hello_ref")
    run(`clang++ $flags $incs $(joinpath(PKG_DIR, "fixtures", "hello_ref.cpp")) -L$libdir -ljolt -Wl,-rpath,$libdir -o $exe`)
    rows = Tuple{Int,NTuple{3,UInt32},NTuple{3,UInt32},Bool}[]
    for line in eachline(`$exe $steps`)
        f = split(line)
        h = [parse(UInt32, x; base=16) for x in f[2:7]]
        push!(rows, (parse(Int, f[1]), (h[1], h[2], h[3]), (h[4], h[5], h[6]), f[8] == "1"))
    end
    return rows
end

@testset "Jolt Deep Tests" begin

@testset "layouts agree with DWARF" begin
    bad = String[]
    for (sname, offs) in J.STRUCT_OFFSETS
        isdefined(J, sname) || continue
        T = getfield(J, sname)
        (T isa DataType && isstructtype(T) && fieldcount(T) > 0) || continue
        names = fieldnames(T)
        for (f, off) in offs
            # A member that shadows a base member of the same name (Jolt has 8:
            # BodyWithMotionProperties::mMotionProperties over Body's, and
            # Array<T, STLLocalAllocator>::mElements over the allocator's inline
            # storage) is the Julia field `<Struct>_<member>`; the bare name is
            # the base's. STRUCT_OFFSETS keys the derived one by the bare name.
            jf = Symbol(sname, "_", f) in names ? Symbol(sname, "_", f) : f
            i = findfirst(==(jf), names)
            i === nothing && continue
            fieldoffset(T, i) != off && push!(bad, "$sname.$jf julia=$(fieldoffset(T, i)) dwarf=$off")
        end
        haskey(J.STRUCT_SIZES, sname) && sizeof(T) != J.STRUCT_SIZES[sname] &&
            push!(bad, "$sname sizeof julia=$(sizeof(T)) dwarf=$(J.STRUCT_SIZES[sname])")
    end
    isempty(bad) || @info "layout mismatches" first(bad, 20)
    @test isempty(bad)
    # Single precision: RVec3 = Vec3, one __m128.
    @test sizeof(J.Vec3) == 16 && sizeof(J.Quat) == 16
    @test sizeof(J.BodyID) == 4
end

@testset "setup: allocator, factory, types" begin
    J.JPH_RegisterDefaultAllocator()
    # The library's own JPH_VERSION_ID: 5.7.0 in the low 24 bits; the bits
    # above encode the build's defines (RegisterTypes checks them).
    @test J.JoltHub_VersionID() & 0xffffff == 0x050700
    f = J.JoltHub_Factory_New()
    @test f != C_NULL
    unsafe_store!(FACTORY_INSTANCE, f)
    J.JoltHub_RegisterTypes()
    @test unsafe_load(FACTORY_INSTANCE) == Ptr{Cvoid}(f)
end

@testset "HelloWorld, bit-for-bit against the same scene in C++" begin
    N = 120
    ref = reference_trajectory(N)
    @test length(ref) == N
    w = hello_world()
    @test J.JPH_PhysicsSystem_GetNumBodies(w.ps) == 2
    mism = 0
    for step in 1:N
        p, v, active = state(w)
        r = ref[step]
        if (bits(p), bits(v), active) != (r[2], r[3], r[4])
            mism += 1
            mism == 1 && @info "first mismatch" step julia=(xyz(p), xyz(v), active) cpp=(reinterpret.(Float32, r[2]), reinterpret.(Float32, r[3]), r[4])
        end
        @test step!(w) == 0                          # EPhysicsUpdateError::None
    end
    @test mism == 0
    # Step 1 is the initial state exactly as set.
    @test reinterpret.(Float32, ref[1][2]) == (0f0, 2f0, 0f0)
    @test reinterpret.(Float32, ref[1][3]) == (0f0, -5f0, 0f0)

    # Run on until Jolt puts the sphere to sleep: it rests on the floor (top
    # at y = 0) at its radius less PhysicsSettings::mPenetrationSlop (0.02):
    # Jolt lets resting contacts interpenetrate by the slop, so 0.48.
    n = N
    while J.JPH_BodyInterface_IsActive(w.bi, Ref(w.sphere_id)) && n < 2000
        step!(w); n += 1
    end
    p, v, active = state(w)
    @test !active
    @test isapprox(xyz(p)[2], 0.5f0 - 0.02f0; atol=1f-3)
    @test abs(xyz(p)[1]) < 1f-4 && abs(xyz(p)[3]) < 1f-4
    @test all(abs.(xyz(v)) .< 1f-2)

    # The upstream by-reference getter agrees with the shim's.
    pos = Ref(vec3(9, 9, 9)); rot = Ref(J.Quat(J.Vec4(J.Vec4_anon1(ntuple(_ -> 0x00, 16)))))
    J.JPH_BodyInterface_GetPositionAndRotation(w.bi, Ref(w.sphere_id), pos, rot)
    @test xyz(pos[]) == xyz(p)
    teardown(w)
end

@testset "shimmed vector calls drive the body" begin
    w = hello_world()
    g = Ref(vec3(0, 0, 0))
    J.JoltHub_PhysicsSystem_GetGravity(w.ps, g)
    @test xyz(g[]) == (0f0, -9.81f0, 0f0)           # Jolt's default gravity
    J.JoltHub_PhysicsSystem_SetGravity(w.ps, Ref(vec3(0, 0, 0)))
    J.JoltHub_PhysicsSystem_GetGravity(w.ps, g)
    @test xyz(g[]) == (0f0, 0f0, 0f0)

    J.JoltHub_BodyInterface_SetLinearVelocity(w.bi, w.sphere_id, Ref(vec3(1.5, 0, -2)))
    _, v, _ = state(w)
    @test xyz(v) == (1.5f0, 0f0, -2f0)

    # An impulse J changes velocity by J/m. Sphere mass: density 1000 kg/m³
    # (BodyCreationSettings default) × 4/3·π·0.5³.
    m = 1000 * 4 / 3 * π * 0.5^3
    J.JoltHub_BodyInterface_AddImpulse(w.bi, w.sphere_id, Ref(vec3(0, 100, 0)))
    _, v, _ = state(w)
    @test isapprox(xyz(v)[2], 100 / m; rtol=1e-5)

    J.JoltHub_BodyInterface_SetAngularVelocity(w.bi, w.sphere_id, Ref(vec3(0, 3, 0)))
    av = Ref(vec3(0, 0, 0))
    J.JoltHub_BodyInterface_GetAngularVelocity(w.bi, w.sphere_id, av)
    @test xyz(av[]) == (0f0, 3f0, 0f0)

    J.JoltHub_BodyInterface_SetPosition(w.bi, w.sphere_id, Ref(vec3(4, 5, 6)), ACTIVATE)
    pos = Ref(vec3(0, 0, 0))
    J.JoltHub_BodyInterface_GetPosition(w.bi, w.sphere_id, pos)
    @test xyz(pos[]) == (4f0, 5f0, 6f0)

    # Zero gravity, no contacts: one step moves the sphere by v·dt, damped by
    # Jolt's default linear damping (0.05): v' = v·max(0, 1 - 0.05·dt).
    _, v0, _ = state(w)
    step!(w)
    p1, v1, _ = state(w)
    k = max(0f0, 1f0 - 0.05f0 * DT)
    @test all(isapprox.(xyz(v1), xyz(v0) .* k; rtol=1e-5))
    @test all(isapprox.(xyz(p1), (4f0, 5f0, 6f0) .+ xyz(v1) .* DT; rtol=1e-5, atol=1e-6))
    teardown(w)
end

@testset "teardown" begin
    J.JPH_UnregisterTypes()
    J.JoltHub_Factory_Delete(Ptr{J.Factory}(unsafe_load(FACTORY_INSTANCE)))
    unsafe_store!(FACTORY_INSTANCE, C_NULL)
    @test unsafe_load(FACTORY_INSTANCE) == C_NULL
end

end
