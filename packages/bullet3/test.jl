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
end

@testset "what was compiled and wrapped" begin
    meta = JSON.parsefile(joinpath(JULIA_DIR, "compilation_metadata.json"))
    # LinearMath + BulletCollision + BulletDynamics (153), plus the package's
    # header-only constructors (shims/inline_ctors.cpp), nothing else
    srcs = meta["source_files"]
    @test length(srcs) == 154
    @test any(s -> endswith(s, "shims/inline_ctors.cpp"), srcs)
    syms = read(`nm -D --defined-only $(joinpath(JULIA_DIR, "libbullet3.so"))`, String)
    for s in ("bt_new_SphereShape", "bt_new_DefaultMotionState", "bt_new_RigidBodyConstructionInfo")
        @test occursin(" $s\n", syms)
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
