#!/usr/bin/env julia
# Lua Hub package — integration test
#
# Tests the full RepliBuild pipeline for Lua 5.4.7:
#   clean → build (with LTO) → load wrapper → exercise API
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/lua/test.jl

using Test
using RepliBuild

const PKG_DIR = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")

# ── Build ────────────────────────────────────────────────────────────────────

@testset "Lua Hub Package" begin

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "liblua.so") || endswith(lib, "liblua.dylib")

    julia_dir = joinpath(PKG_DIR, "julia")
    @test isfile(joinpath(julia_dir, "compilation_metadata.json"))

    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test isfile(joinpath(julia_dir, "Lua.jl"))
end

@testset "LTO bitcode generation" begin
    julia_dir = joinpath(PKG_DIR, "julia")
    @test isfile(joinpath(julia_dir, "lua_lto.bc"))
    @test isfile(joinpath(julia_dir, "lua_lto.ll"))

    # Verify the bitcode is non-trivial
    bc_size = filesize(joinpath(julia_dir, "lua_lto.bc"))
    @test bc_size > 100_000  # should be ~600KB
end

# ── Load wrapper ─────────────────────────────────────────────────────────────

include(joinpath(PKG_DIR, "julia", "Lua.jl"))

@testset "Module structure" begin
    @test isdefined(Lua, :luaL_newstate)
    @test isdefined(Lua, :luaL_openlibs)
    @test isdefined(Lua, :luaL_dostring)
    @test isdefined(Lua, :lua_close)
    @test isdefined(Lua, :lua_pushinteger)
    @test isdefined(Lua, :lua_pushnumber)
    @test isdefined(Lua, :lua_pushstring)
    @test isdefined(Lua, :lua_gettop)
    @test isdefined(Lua, :lua_settop)
    @test isdefined(Lua, :lua_type)
    @test isdefined(Lua, :lua_typename)

    # Macro shims
    @test isdefined(Lua, :lua_pop)
    @test isdefined(Lua, :lua_newtable)
    @test isdefined(Lua, :lua_tostring)
    @test isdefined(Lua, :lua_tonumber)
    @test isdefined(Lua, :lua_tointeger)
    @test isdefined(Lua, :lua_pcall)
    @test isdefined(Lua, :lua_isfunction)
    @test isdefined(Lua, :lua_istable)
    @test isdefined(Lua, :lua_isnil)
    @test isdefined(Lua, :luaL_dostring)
    @test isdefined(Lua, :luaL_dofile)
    @test isdefined(Lua, :luaL_checkstring)
    @test isdefined(Lua, :luaL_typename)

    # Varargs overloads
    @test isdefined(Lua, :lua_pushfstring)
    @test isdefined(Lua, :lua_pushfstring_Cstring)
    @test isdefined(Lua, :lua_pushfstring_Cint)
    @test isdefined(Lua, :lua_pushfstring_Cdouble)

    # Metadata
    @test haskey(Lua.METADATA, "llvm_version")
    @test haskey(Lua.METADATA, "target_triple")
    @test Lua.METADATA["function_count"] >= 100
end

# ── API tests ────────────────────────────────────────────────────────────────

@testset "State lifecycle" begin
    L = Lua.luaL_newstate()
    @test L != C_NULL
    Lua.luaL_openlibs(L)
    Lua.lua_close(L)
end

@testset "Stack operations" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    # Stack starts empty
    @test Lua.lua_gettop(L) == 0

    # Push values
    Lua.lua_pushinteger(L, 42)
    @test Lua.lua_gettop(L) == 1

    Lua.lua_pushnumber(L, 3.14)
    @test Lua.lua_gettop(L) == 2

    Lua.lua_pushstring(L, "hello")
    @test Lua.lua_gettop(L) == 3

    Lua.lua_pushboolean(L, 1)
    @test Lua.lua_gettop(L) == 4

    Lua.lua_pushnil(L)
    @test Lua.lua_gettop(L) == 5

    # Read values back (Lua stack is 1-indexed)
    @test Lua.lua_tointeger(L, 1) == 42
    @test Lua.lua_tonumber(L, 2) ≈ 3.14
    @test Lua.lua_tostring(L, 3) == "hello"
    @test Lua.lua_toboolean(L, 4) == 1
    @test Lua.lua_isnil(L, 5) != 0

    # Type checking macros
    @test Lua.lua_isfunction(L, 1) == 0
    @test Lua.lua_istable(L, 1) == 0
    @test Lua.lua_isboolean(L, 4) != 0
    @test Lua.lua_isnone(L, 10) != 0
    @test Lua.lua_isnoneornil(L, 10) != 0

    # lua_pop macro
    Lua.lua_pop(L, 2)
    @test Lua.lua_gettop(L) == 3

    # lua_settop to clear
    Lua.lua_settop(L, 0)
    @test Lua.lua_gettop(L) == 0

    Lua.lua_close(L)
end

@testset "Execute Lua code" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    # Simple expression
    @test Lua.luaL_dostring(L, "x = 2 + 3") == 0

    # Retrieve global
    Lua.lua_getglobal(L, "x")
    @test Lua.lua_tointeger(L, -1) == 5
    Lua.lua_pop(L, 1)

    # String result
    @test Lua.luaL_dostring(L, "greeting = 'hello from lua'") == 0
    Lua.lua_getglobal(L, "greeting")
    @test Lua.lua_tostring(L, -1) == "hello from lua"
    Lua.lua_pop(L, 1)

    # Math
    @test Lua.luaL_dostring(L, "pi_approx = math.pi") == 0
    Lua.lua_getglobal(L, "pi_approx")
    @test Lua.lua_tonumber(L, -1) ≈ π atol=1e-10
    Lua.lua_pop(L, 1)

    # Table creation and access
    @test Lua.luaL_dostring(L, """
        t = {1, 2, 3}
        t_len = #t
    """) == 0
    Lua.lua_getglobal(L, "t_len")
    @test Lua.lua_tointeger(L, -1) == 3
    Lua.lua_pop(L, 1)

    # Error handling — syntax error returns non-zero
    @test Lua.luaL_dostring(L, "this is not valid lua!!!") != 0
    Lua.lua_pop(L, 1)  # pop error message

    Lua.lua_close(L)
end

@testset "Table operations (macro shims)" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    # lua_newtable macro
    Lua.lua_newtable(L)
    @test Lua.lua_istable(L, -1) != 0

    # Set fields: t["name"] = "lua", t["version"] = 54
    Lua.lua_pushstring(L, "lua")
    Lua.lua_setfield(L, -2, "name")

    Lua.lua_pushinteger(L, 54)
    Lua.lua_setfield(L, -2, "version")

    # Read back
    Lua.lua_getfield(L, -1, "name")
    @test Lua.lua_tostring(L, -1) == "lua"
    Lua.lua_pop(L, 1)

    Lua.lua_getfield(L, -1, "version")
    @test Lua.lua_tointeger(L, -1) == 54
    Lua.lua_pop(L, 1)

    Lua.lua_pop(L, 1)  # pop table
    Lua.lua_close(L)
end

@testset "Global set/get" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    # Set a global from Julia
    Lua.lua_pushinteger(L, 999)
    Lua.lua_setglobal(L, "from_julia")

    # Read it back via Lua
    @test Lua.luaL_dostring(L, "result = from_julia * 2") == 0
    Lua.lua_getglobal(L, "result")
    @test Lua.lua_tointeger(L, -1) == 1998
    Lua.lua_pop(L, 1)

    Lua.lua_close(L)
end

@testset "lua_pcall macro" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    # Load a chunk and pcall it
    @test Lua.luaL_loadstring(L, "return 6 * 7") == 0
    @test Lua.lua_pcall(L, 0, 1, 0) == 0
    @test Lua.lua_tointeger(L, -1) == 42
    Lua.lua_pop(L, 1)

    # pcall with error — returns non-zero
    @test Lua.luaL_loadstring(L, "error('boom')") == 0
    @test Lua.lua_pcall(L, 0, 0, 0) != 0
    Lua.lua_pop(L, 1)  # pop error message

    Lua.lua_close(L)
end

@testset "Lua function calls" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    # Define a Lua function, call it from Julia via lua_call
    @test Lua.luaL_dostring(L, "function add(a, b) return a + b end") == 0

    Lua.lua_getglobal(L, "add")
    @test Lua.lua_isfunction(L, -1) != 0
    Lua.lua_pushinteger(L, 100)
    Lua.lua_pushinteger(L, 200)
    Lua.lua_call(L, 2, 1)
    @test Lua.lua_tointeger(L, -1) == 300
    Lua.lua_pop(L, 1)

    Lua.lua_close(L)
end

@testset "String operations" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    # luaL_dostring with string manipulation
    @test Lua.luaL_dostring(L, """
        s = string.rep("ab", 5)
        s_len = #s
    """) == 0

    Lua.lua_getglobal(L, "s")
    @test Lua.lua_tostring(L, -1) == "ababababab"
    Lua.lua_pop(L, 1)

    Lua.lua_getglobal(L, "s_len")
    @test Lua.lua_tointeger(L, -1) == 10
    Lua.lua_pop(L, 1)

    Lua.lua_close(L)
end

@testset "lua_version" begin
    L = Lua.luaL_newstate()
    ver = Lua.lua_version(L)
    @test ver == 504.0  # Lua 5.4
    Lua.lua_close(L)
end

@testset "Multiple states" begin
    L1 = Lua.luaL_newstate()
    L2 = Lua.luaL_newstate()
    @test L1 != C_NULL
    @test L2 != C_NULL
    @test L1 != L2

    Lua.luaL_openlibs(L1)
    Lua.luaL_openlibs(L2)

    # Independent state
    Lua.lua_pushinteger(L1, 111)
    Lua.lua_pushinteger(L2, 222)

    @test Lua.lua_tointeger(L1, -1) == 111
    @test Lua.lua_tointeger(L2, -1) == 222

    Lua.lua_close(L1)
    Lua.lua_close(L2)
end

@testset "luaL_typename macro" begin
    L = Lua.luaL_newstate()

    Lua.lua_pushinteger(L, 1)
    @test Lua.luaL_typename(L, -1) == "number"

    Lua.lua_pushstring(L, "test")
    @test Lua.luaL_typename(L, -1) == "string"

    Lua.lua_pushboolean(L, 0)
    @test Lua.luaL_typename(L, -1) == "boolean"

    Lua.lua_pop(L, 3)
    Lua.lua_close(L)
end

end  # top-level testset
