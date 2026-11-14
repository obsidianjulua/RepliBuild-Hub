#!/usr/bin/env julia
# hello_world Hub package — graph mode + cross-library type identity.
#
# Two C++ shared libraries from one CMake project (see CMakeLists.txt):
# `hello` owns hw::Vec2, hw::Mood (enum class) and hw::Greeter (polymorphic);
# `world` links hello and uses those types every way a second library can.
# Proves, against RepliBuild #80 (one Julia type per C++ type in a graph):
#   - the graph manifest: two libraries, load order hello → world
#   - identity: World.Vec2 / Mood / Greeter ARE Hello's (===), not copies,
#     and World's wrapper defines none of them
#   - layouts world owns built from hello's types: Entity embeds Vec2 twice +
#     Mood; Shouter flattens Greeter's vptr/mood_ and packs volume_ into its
#     tail padding (Itanium); Crowd points at Hello.Greeter
#   - values cross both ways: hello's Vec2/Mood into world's functions (Tier 2
#     thunks needing hello's layout), world's results back as hello's types
#   - virtual dispatch across the boundary: hello's `greet` on an object world
#     made reaches world's override, also through a record world returned
#   - the original Tier-2 exerciser in hello, including a C++ throw
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/hello_world/test_deep.jl

using Test, TOML

const PKG_DIR = @__DIR__
const GRAPH = joinpath(PKG_DIR, "julia", "HelloWorld.jl")

if !isfile(GRAPH)
    @info "Graph wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(GRAPH)
const H = HelloWorld.Hello
const W = HelloWorld.World

@testset "hello_world graph" begin

@testset "Graph manifest and type manifests" begin
    m = TOML.parsefile(joinpath(PKG_DIR, "julia", "graph.toml"))
    libs = m["libraries"]
    @test [l["name"] for l in libs] == ["hello", "world"]      # load order
    @test [l["module"] for l in libs] == ["Hello", "World"]
    @test all(l -> l["bucket"] == "cpp", libs)

    # World imported hello's types (the thunk sidecar exists only for an
    # importer); hello imported nothing.
    @test isfile(joinpath(PKG_DIR, "julia", "world", "lib", "type_imports.json"))
    @test !isfile(joinpath(PKG_DIR, "julia", "hello", "lib", "type_imports.json"))
end

@testset "One Julia type per C++ type" begin
    @test W.Vec2 === H.Vec2
    @test W.Mood === H.Mood
    @test W.Greeter === H.Greeter
    # An imported enum brings its enumerators too (RepliBuild.jl #88): World
    # aliases Hello's values, so World.Happy IS Hello.Happy.
    @test W.Happy === H.Happy
    @test W.Happy isa W.Mood
    @test :Happy in names(W)
    # World's layout table lists its own records only.
    @test !haskey(W.STRUCT_SIZES, :Vec2) && haskey(H.STRUCT_SIZES, :Vec2)
    @test haskey(W.STRUCT_SIZES, :Entity)
end

@testset "World's records built from Hello's types" begin
    @test fieldtypes(W.Entity) == (H.Vec2, H.Vec2, Int32, H.Mood)
    @test sizeof(W.Entity) == 24
    @test fieldnames(W.Shouter) == (:_vptr_Greeter, :mood_, :volume_)
    @test fieldtype(W.Shouter, :mood_) === H.Mood
    @test sizeof(W.Shouter) == 16                  # volume_ in Greeter's tail pad
    @test fieldtype(W.Crowd, :leader) === Ptr{H.Greeter}
end

@testset "Values cross the library boundary" begin
    v = H.hw_vec2(1f0, 2f0)
    @test v isa H.Vec2 && (v.x, v.y) == (1f0, 2f0)

    # hello's Vec2/Mood into world, world's Entity (embedding them) back.
    e = W.hw_spawn(Int32(7), v, H.hw_vec2(3f0, 4f0), H.Happy)
    @test e isa W.Entity
    @test e.id == 7 && e.mood === H.Happy
    @test (e.pos.x, e.pos.y, e.vel.x, e.vel.y) == (1f0, 2f0, 3f0, 4f0)

    # world's step calls hello's vec2_add/vec2_scale internally.
    e2 = W.hw_step(e, 0.5f0)
    @test (e2.pos.x, e2.pos.y) == (2.5f0, 4f0)
    p = W.hw_entity_pos(e2)
    @test p isa H.Vec2 && (p.x, p.y) == (2.5f0, 4f0)

    @test W.hw_travel(H.hw_vec2(0f0, 0f0), H.hw_vec2(3f0, 4f0)) == 5f0
    @test H.hw_vec2_dot(p, H.hw_vec2(2f0, 1f0)) == 9f0

    # Scoped enum both ways, and a world result into a hello function.
    @test W.hw_louder(H.Calm) === H.Happy
    @test H.hw_mood_level(W.hw_louder(H.Happy)) == 30
end

@testset "Virtual dispatch across the boundary" begin
    g = H.hw_make_greeter(H.Calm)
    @test H.hw_greet(g) == "Hello, World!"

    s = W.hw_spawn_shouter(11)                     # a Shouter, typed as hello's Greeter*
    @test H.hw_greet(s) == "HELLO, WORLD!"         # hello's virtual call → world's override
    @test H.hw_Greeter_mood(s) === H.Loud

    c = W.hw_gather(s, Int32(3))
    @test c.size == 3 && c.leader isa Ptr{H.Greeter}
    @test W.hw_crowd_says(c) == "HELLO, WORLD!"    # world → hello's greet → world's override

    H.hw_destroy_greeter(s)                        # virtual ~Greeter runs ~Shouter
end

@testset "Tier-2 exerciser (hello)" begin
    @test H.hello_message() == "Hello, World!"
    @test H.add_scaled(2, 3, 4) == 20
    @test H.blend(0.0, 10.0, 0.25) == 2.5
    @test H.mix_widths(Int32(5), 1.5) == 1505
    @test H.checked_div(9, 3) == 3
    @test_throws Exception H.checked_div(1, 0)     # C++ throw surfaces in Julia
end

end
