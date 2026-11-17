#!/usr/bin/env julia
# bullet3 Hub package — cold rebuild
#
# DESTRUCTIVE: clean() wipes build/, julia/ and the cache, but deps=false keeps
# the bulletphysics/bullet3 clone (~460 MB). Then build + wrap + the gates the
# hub-wrap recipe asks for, then the deep test against the fresh wrapper.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/bullet3/test.jl

using Test
using RepliBuild
using JSON

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")
const JULIA_DIR = joinpath(PKG_DIR, "julia")

@testset "bullet3 Hub Package" begin

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH; deps=false)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libbullet3.so")
    @test filesize(lib) > 2_000_000
    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test endswith(wrapper, "Bullet3.jl")
    # [compile] aot_thunks: the Tier-2 thunks are compiled at build time, and
    # the wrapper loads them from the sibling .so instead of JIT-compiling.
    thunks = joinpath(JULIA_DIR, "libbullet3_thunks.so")
    @test isfile(thunks)
    src = read(wrapper, String)
    @test occursin("libbullet3_thunks.so", src)
end

@testset "what was compiled and wrapped" begin
    meta = JSON.parsefile(joinpath(JULIA_DIR, "compilation_metadata.json"))
    # LinearMath + BulletCollision + BulletDynamics (153) and the build's two
    # generated units: replibuild_records.cpp ([types] records, #107: makes
    # btDefaultMotionState visible) and replibuild_ctors.cpp (#105/#108: the
    # header-only constructors and member functions no library .cpp defines).
    # No package shims any more. Nothing else.
    srcs = meta["source_files"]
    @test length(srcs) == 155
    @test any(s -> endswith(s, "replibuild_records.cpp"), srcs)
    @test any(s -> endswith(s, "replibuild_ctors.cpp"), srcs)
    @test !any(s -> occursin("shims/", s), srcs)             # the retired hand-written shims
    @test !isdir(joinpath(PKG_DIR, "shims"))
    # The three HelloWorld needs, now the build's: real C2 constructors.
    syms = read(`nm -D --defined-only $(joinpath(JULIA_DIR, "libbullet3.so"))`, String)
    for s in ("_ZN13btSphereShapeC2Ef",
              "_ZN20btDefaultMotionStateC2ERK11btTransformS2_",
              "_ZN11btRigidBody27btRigidBodyConstructionInfoC2EfP13btMotionStateP16btCollisionShapeRK9btVector3")
        @test occursin(" $s\n", syms)
    end
    @test !occursin("bt_new_", syms)
    # Header-inline member functions no library .cpp calls (#108): the ones an
    # application needs every day are now real symbols.
    for s in ("_ZN11btRigidBody19applyCentralImpulseERK9btVector3",
              "_ZN11btRigidBody17setLinearVelocityERK9btVector3",
              "_ZN17btHingeConstraint8setLimitEfffff",
              "_ZN17btHingeConstraint18enableAngularMotorEbff",
              "_ZN23btPoint2PointConstraint9setPivotBERK9btVector3",
              "_ZN15btDynamicsWorld23setInternalTickCallbackEPFvPS_fEPvb",
              "_ZN20btPersistentManifold15getContactPointEi",
              "_ZNK20btDefaultMotionState17getWorldTransformER11btTransform")
        @test occursin(" $s\n", syms)
    end
    methods = meta["inline_methods"]["forced"]
    @test length(methods) > 1500                             # 2009 at 3.25 / RepliBuild ee7e2cf
    @test all(r -> r["emitted"] == true, methods)
    forced = meta["inline_constructors"]["forced"]          # every planned row
    emitted = filter(r -> r["emitted"] == true, forced)
    @test length(emitted) > 400                             # 496 of 502 at 3.25 / RepliBuild f7e843f
    for cls in ("btSphereShape", "btDefaultMotionState", "btRigidBodyConstructionInfo")
        @test any(r -> r["class"] == cls, emitted)
    end
    @test !any(s -> occursin("/Bullet3", s) || occursin("BulletSoftBody", s) ||
                    occursin("Extras/", s) || occursin("All.cpp", s), srcs)
    # Real signatures, not zero-arg inference (the Bucket B smell). 33 entries
    # say parameters_source = "inferred" today, and every one really takes no
    # arguments: an Itanium `v` parameter list (`_Z9btMachEpsv`,
    # `_ZN11btMatrix3x311getIdentityEv`) or upstream's three unmangled
    # `bt*Probe()` functions. A function WITH parameters inferred as zero-arg
    # would mangle to something else and fail here.
    @test meta["function_count"] > 2500
    inferred = filter(f -> get(f, "parameters_source", "") == "inferred", meta["functions"])
    @test all(f -> endswith(f["mangled"], "v") || !startswith(f["mangled"], "_Z"), inferred)
    @test length(meta["struct_definitions"]) > 600
end

end

# Behaviour: the HelloWorld simulation, layouts, teardown.
include(joinpath(PKG_DIR, "test_deep.jl"))
