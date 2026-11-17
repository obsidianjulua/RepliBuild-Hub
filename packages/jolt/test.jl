#!/usr/bin/env julia
# jolt Hub package: cold rebuild
#
# DESTRUCTIVE: clean() wipes build/, julia/ and the cache, but deps=false keeps
# the jrouwe/JoltPhysics clone. Then build + wrap (about 14 minutes), the gates
# below, and the deep test against the fresh wrapper.
#
# Three gates pin the package's WORKAROUNDS. Each names its GENERATOR report,
# and each flips when the engine fix lands, as a reminder to retire it.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/jolt/test.jl

using Test
using RepliBuild
using JSON

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")
const JULIA_DIR = joinpath(PKG_DIR, "julia")

@testset "jolt Hub Package" begin

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH; deps=false)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libjolt.so")
    @test filesize(lib) > 10_000_000                       # 24 MB at v5.7.0
    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test endswith(wrapper, "Jolt.jl")
    # [compile] aot_thunks: Tier-2 thunks compiled at build time.
    @test isfile(joinpath(JULIA_DIR, "libjolt_thunks.so"))
    @test occursin("libjolt_thunks.so", read(wrapper, String))
end

META = JSON.parsefile(joinpath(JULIA_DIR, "compilation_metadata.json"))
SRCS = META["source_files"]
SRC  = read(joinpath(JULIA_DIR, "Jolt.jl"), String)
SYMS = read(`nm -D --defined-only $(joinpath(JULIA_DIR, "libjolt.so"))`, String)

@testset "what was compiled" begin
    # Jolt/ (138 .cpp after the recipe's exclusions), the package's shim, and
    # the build's two generated units ([types] records, #107; forced inline
    # constructors and member functions, #105/#108).
    @test count(s -> occursin("/deps/jolt/Jolt/", s), SRCS) == 138
    @test length(SRCS) == 141
    @test any(s -> endswith(s, "shims/jolt_hub.cpp"), SRCS)
    @test any(s -> endswith(s, "replibuild_records.cpp"), SRCS)
    @test any(s -> endswith(s, "replibuild_ctors.cpp"), SRCS)
    for bad in ("/Compute/DX12/", "/Compute/VK/", "/Samples/", "/TestFramework/",
                "/UnitTests/", "/HelloWorld/", "/JoltViewer/", "/PerformanceTest/")
        @test !any(s -> occursin(bad, s), SRCS)
    end
    @test META["function_count"] > 10_000                  # 13,592 at v5.7.0 / a875932
    @test length(META["struct_definitions"]) > 1000        # 1,310
end

@testset "header-only constructors are real symbols" begin
    # What upstream HelloWorld constructs, and the layer tables standing in for
    # its hand-written subclasses ([types] records makes those visible).
    for s in ("_ZN3JPH11SphereShapeC2EfPKNS_15PhysicsMaterialE",
              "_ZN3JPH8BoxShapeC2ENS_4Vec3EfPKNS_15PhysicsMaterialE",
              "_ZN3JPH20BodyCreationSettingsC2EPKNS_5ShapeENS_4Vec3ENS_4QuatENS_11EMotionTypeEt",
              "_ZN3JPH17TempAllocatorImplC2Em",
              "_ZN3JPH23JobSystemSingleThreadedC2Ej",
              "_ZN3JPH29BroadPhaseLayerInterfaceTableC2Ejj",
              "_ZN3JPH26ObjectLayerPairFilterTableC2Ej",
              "_ZN3JPH34ObjectVsBroadPhaseLayerFilterTableC2ERKNS_24BroadPhaseLayerInterfaceEjRKNS_21ObjectLayerPairFilterEj")
        @test occursin(" $s\n", SYMS)
    end
    forced = META["inline_constructors"]["forced"]
    @test count(r -> r["emitted"] == true, forced) > 1500  # 1,749 of 2,007
    methods = META["inline_methods"]["forced"]
    @test length(methods) > 4000                           # 5,171
    @test all(r -> r["emitted"] == true, methods)
end

@testset "WORKAROUND gates (flip when the engine fix lands)" begin
    # GENERATOR-uint64-enum-overflow.md: overrides/ shadows upstream's
    # LargeIslandSplitter.h, so the uint64 enum never reaches the wrap.
    @test isfile(joinpath(PKG_DIR, "overrides", "Jolt", "Physics", "LargeIslandSplitter.h"))
    @test !occursin("EIterationStatus", SRC)

    # GENERATOR-fragment-header-in-forced-unit.md: no CPU compute backend, so
    # WrapShaderBegin.h never enters the forced unit, and no row is declined
    # for the namespace it leaks.
    @test !any(s -> occursin("/Compute/CPU/", s) || endswith(s, "HairWrapper.cpp"), SRCS)
    skipped = META["inline_constructors"]["skipped"]
    @test !any(r -> occursin("ShaderWrappers", r["reason"]), skipped)

    # GENERATOR-simd-by-value-trapped.md: by-value Vec3/Quat is still a trap,
    # and the shim's by-reference forms exist. When this first test fails,
    # the engine passes __m128 records: retire the shim's by-value section.
    @test occursin("cannot call 'JPH_BodyInterface_GetCenterOfMassPosition'", SRC)
    for f in ("JoltHub_BodyInterface_GetCenterOfMassPosition", "JoltHub_BodyInterface_SetLinearVelocity",
              "JoltHub_BoxShape_BoxShape", "JoltHub_BodyCreationSettings_BodyCreationSettings",
              "JoltHub_PhysicsSystem_SetGravity", "JoltHub_Factory_New", "JoltHub_RegisterTypes")
        @test occursin("function $f(", SRC)
    end
end

end

# Behaviour: upstream HelloWorld, bit-for-bit against C++; the shim calls.
include(joinpath(PKG_DIR, "test_deep.jl"))
