#!/usr/bin/env julia
# Lua Hub package — deep integration test
#
# Assumes the wrapper is already built (run test.jl first, or it builds here as
# a fallback). Where test.jl proves the pipeline, this file leans on the wrapper:
#   - value-macro constants pinned against real header values
#   - lua_gc varargs overloads (GCSTEP / GCGEN / GCINC)
#   - registry references (luaL_ref / luaL_unref, LUA_RIDX_GLOBALS)
#   - coroutines: lua_newthread / lua_resume with Ref{Cint} out-param
#   - Julia @cfunction callbacks: lua_register, upvalue closures,
#     luaL_error longjmp across a Julia frame, pcall message handlers
#   - bytecode roundtrip: lua_dump writer → luaL_loadbufferx in a fresh state
#   - binary-safe strings (embedded NULs), userdata + metatables, lua_next,
#     stack gymnastics, integer edge cases, GC stress
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/lua/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Lua.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

# ── Callbacks (must be top-level, non-closure, for @cfunction) ───────────────

# lua_CFunction: doubles its integer argument
function jl_double(Lp::Ptr{Cvoid})::Cint
    n = Lua.lua_tointeger(Lp, 1)
    Lua.lua_pushinteger(Lp, 2n)
    return Cint(1)
end

# lua_CFunction closure: increments and persists its integer upvalue
function jl_counter(Lp::Ptr{Cvoid})::Cint
    idx = Lua.lua_upvalueindex(1)
    n = Lua.lua_tointeger(Lp, idx)
    Lua.lua_pushinteger(Lp, n + 1)
    Lua.lua_copy(Lp, -1, idx)
    return Cint(1)
end

# lua_CFunction that raises a Lua error via luaL_error (longjmps back to pcall)
function jl_fail(Lp::Ptr{Cvoid})::Cint
    detail = "deliberate failure"
    GC.@preserve detail begin
        Lua.luaL_error_Cstring(Lp, "callback says: %s", Cstring(pointer(detail)))
    end
    return Cint(0)  # unreachable
end

# pcall message handler: prefixes the error message
function jl_msgh(Lp::Ptr{Cvoid})::Cint
    msg = Lua.lua_tostring(Lp, 1)
    Lua.lua_pushstring(Lp, "handled: " * something(msg, "?"))
    return Cint(1)
end

# lua_Writer: accumulates dumped bytecode into DUMP_BUF
const DUMP_BUF = UInt8[]
function jl_writer(Lp::Ptr{Cvoid}, p::Ptr{UInt8}, sz::Csize_t, ud::Ptr{Cvoid})::Cint
    sz == 0 && return Cint(0)
    append!(DUMP_BUF, unsafe_wrap(Vector{UInt8}, p, Int(sz)))
    return Cint(0)
end

# ── Tests ────────────────────────────────────────────────────────────────────

@testset "Lua Deep Tests" begin

@testset "Value-macro constants match lua.h" begin
    # Status codes
    @test Lua.LUA_OK() == 0
    @test Lua.LUA_YIELD() == 1
    @test Lua.LUA_ERRRUN() == 2
    @test Lua.LUA_ERRSYNTAX() == 3
    @test Lua.LUA_ERRMEM() == 4
    @test Lua.LUA_ERRERR() == 5

    # Type tags
    @test Lua.LUA_TNONE() == -1
    @test Lua.LUA_TNIL() == 0
    @test Lua.LUA_TBOOLEAN() == 1
    @test Lua.LUA_TLIGHTUSERDATA() == 2
    @test Lua.LUA_TNUMBER() == 3
    @test Lua.LUA_TSTRING() == 4
    @test Lua.LUA_TTABLE() == 5
    @test Lua.LUA_TFUNCTION() == 6
    @test Lua.LUA_TUSERDATA() == 7
    @test Lua.LUA_TTHREAD() == 8

    # Registry / sentinels
    @test Lua.LUA_REGISTRYINDEX() == -1_001_000
    @test Lua.LUA_RIDX_MAINTHREAD() == 1
    @test Lua.LUA_RIDX_GLOBALS() == 2
    @test Lua.LUA_MULTRET() == -1
    @test Lua.LUA_NOREF() == -2
    @test Lua.LUA_REFNIL() == -1
    @test Lua.LUA_MINSTACK() == 20
    @test Lua.LUA_VERSION_NUM() == 504
end

@testset "GC control (varargs overloads)" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    # Base wrapper: no-data ops
    @test Lua.lua_gc(L, Lua.LUA_GCISRUNNING()) == 1
    @test Lua.lua_gc(L, Lua.LUA_GCSTOP()) >= 0
    @test Lua.lua_gc(L, Lua.LUA_GCISRUNNING()) == 0
    @test Lua.lua_gc(L, Lua.LUA_GCRESTART()) >= 0
    @test Lua.lua_gc(L, Lua.LUA_GCISRUNNING()) == 1
    @test Lua.lua_gc(L, Lua.LUA_GCCOLLECT()) == 0
    @test Lua.lua_gc(L, Lua.LUA_GCCOUNT()) > 0

    # GCSTEP with step size (1 variadic int)
    @test Lua.lua_gc_Cint(L, Lua.LUA_GCSTEP(), Cint(10)) in (0, 1)

    # Mode switches return the previous mode:
    # GCGEN takes (minormul, majormul), GCINC takes (pause, stepmul, stepsize)
    prev = Lua.lua_gc_Cint_Cint(L, Lua.LUA_GCGEN(), Cint(0), Cint(0))
    @test prev == Lua.LUA_GCINC()
    prev = Lua.lua_gc_Cint_Cint_Cint(L, Lua.LUA_GCINC(), Cint(0), Cint(0), Cint(0))
    @test prev == Lua.LUA_GCGEN()

    Lua.lua_close(L)
end

@testset "Registry references" begin
    L = Lua.luaL_newstate()
    REG = Lua.LUA_REGISTRYINDEX()

    # Globals table lives at RIDX_GLOBALS
    @test Lua.lua_rawgeti(L, REG, Lua.LUA_RIDX_GLOBALS()) == Lua.LUA_TTABLE()
    Lua.lua_pop(L, 1)

    # ref → rawgeti roundtrip
    Lua.lua_pushstring(L, "pinned value")
    ref = Lua.luaL_ref(L, REG)
    @test ref > 0
    @test Lua.lua_gettop(L) == 0
    @test Lua.lua_rawgeti(L, REG, ref) == Lua.LUA_TSTRING()
    @test Lua.lua_tostring(L, -1) == "pinned value"
    Lua.lua_pop(L, 1)
    Lua.luaL_unref(L, REG, ref)

    # ref of nil is the LUA_REFNIL sentinel
    Lua.lua_pushnil(L)
    @test Lua.luaL_ref(L, REG) == Lua.LUA_REFNIL()

    Lua.lua_close(L)
end

@testset "Coroutines (lua_newthread / lua_resume)" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    co = Lua.lua_newthread(L)
    @test co != C_NULL
    @test Lua.lua_isthread(L, -1) != 0

    @test Lua.luaL_loadstring(co, "coroutine.yield(11); return 22") == Lua.LUA_OK()

    nres = Ref{Cint}(0)
    @test Lua.lua_resume(co, L, 0, nres) == Lua.LUA_YIELD()
    @test nres[] == 1
    @test Lua.lua_tointeger(co, -1) == 11
    @test Lua.lua_status(co) == Lua.LUA_YIELD()
    @test Lua.lua_isyieldable(L) == 0  # main thread can't yield
    Lua.lua_pop(co, 1)

    @test Lua.lua_resume(co, L, 0, nres) == Lua.LUA_OK()
    @test nres[] == 1
    @test Lua.lua_tointeger(co, -1) == 22
    @test Lua.lua_status(co) == Lua.LUA_OK()

    # xmove: values hop between states sharing a global_State
    top_before = Lua.lua_gettop(co)
    Lua.lua_pushstring(L, "moved")
    Lua.lua_pushinteger(L, 7)
    Lua.lua_xmove(L, co, 2)
    @test Lua.lua_gettop(co) == top_before + 2
    @test Lua.lua_tointeger(co, -1) == 7
    @test Lua.lua_tostring(co, -2) == "moved"

    @test Lua.lua_closethread(co, L) == Lua.LUA_OK()
    Lua.lua_close(L)
end

@testset "Julia @cfunction callbacks" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    # Plain registered C function
    cf = @cfunction(jl_double, Cint, (Ptr{Cvoid},))
    Lua.lua_register(L, "jldouble", cf)
    @test Lua.luaL_dostring(L, "cb_result = jldouble(21)") == Lua.LUA_OK()
    Lua.lua_getglobal(L, "cb_result")
    @test Lua.lua_tointeger(L, -1) == 42
    Lua.lua_pop(L, 1)

    # Closure with a persistent integer upvalue
    ccf = @cfunction(jl_counter, Cint, (Ptr{Cvoid},))
    Lua.lua_pushinteger(L, 100)
    Lua.lua_pushcclosure(L, ccf, 1)
    Lua.lua_setglobal(L, "deepcounter")
    @test Lua.luaL_dostring(L, "c1 = deepcounter(); c2 = deepcounter()") == Lua.LUA_OK()
    Lua.lua_getglobal(L, "c1")
    Lua.lua_getglobal(L, "c2")
    @test Lua.lua_tointeger(L, -2) == 101
    @test Lua.lua_tointeger(L, -1) == 102  # upvalue persisted across calls
    Lua.lua_pop(L, 2)

    Lua.lua_close(L)
end

@testset "luaL_error longjmp through a Julia frame" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    fcf = @cfunction(jl_fail, Cint, (Ptr{Cvoid},))
    Lua.lua_pushcfunction(L, fcf)
    rc = Lua.lua_pcall(L, 0, 0, 0)
    @test rc == Lua.LUA_ERRRUN()
    err = Lua.lua_tostring(L, -1)
    @test occursin("callback says: deliberate failure", err)
    Lua.lua_pop(L, 1)
    @test Lua.lua_gettop(L) == 0

    Lua.lua_close(L)
end

@testset "pcall with message handler" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    mh = @cfunction(jl_msgh, Cint, (Ptr{Cvoid},))
    Lua.lua_pushcfunction(L, mh)          # handler at index 1
    @test Lua.luaL_loadstring(L, "error('kaboom')") == Lua.LUA_OK()
    rc = Lua.lua_pcall(L, 0, 0, 1)
    @test rc == Lua.LUA_ERRRUN()
    err = Lua.lua_tostring(L, -1)
    @test startswith(err, "handled: ")
    @test occursin("kaboom", err)
    Lua.lua_settop(L, 0)

    # Syntax errors come back as LUA_ERRSYNTAX from the loader
    @test Lua.luaL_loadstring(L, "this is (not) lua ][") == Lua.LUA_ERRSYNTAX()
    Lua.lua_settop(L, 0)

    Lua.lua_close(L)
end

@testset "Bytecode roundtrip (lua_dump → luaL_loadbufferx)" begin
    L = Lua.luaL_newstate()
    @test Lua.luaL_loadstring(L, "return 6 * 7") == Lua.LUA_OK()

    empty!(DUMP_BUF)
    wcf = @cfunction(jl_writer, Cint, (Ptr{Cvoid}, Ptr{UInt8}, Csize_t, Ptr{Cvoid}))
    @test Lua.lua_dump(L, wcf, C_NULL, 0) == 0
    @test length(DUMP_BUF) > 16
    @test DUMP_BUF[1] == 0x1b  # LUA_SIGNATURE starts with ESC
    Lua.lua_close(L)

    # Load the dumped chunk in a completely fresh state, binary mode only
    L2 = Lua.luaL_newstate()
    @test Lua.luaL_loadbufferx(L2, DUMP_BUF, length(DUMP_BUF), "=dumped", "b") == Lua.LUA_OK()
    @test Lua.lua_pcall(L2, 0, 1, 0) == Lua.LUA_OK()
    @test Lua.lua_tointeger(L2, -1) == 42
    Lua.lua_close(L2)
end

@testset "Binary-safe strings (embedded NULs)" begin
    L = Lua.luaL_newstate()

    s = "a\0b\0c"
    Lua.lua_pushlstring(L, s, sizeof(s))
    @test Lua.lua_rawlen(L, -1) == 5

    len = Ref{Csize_t}(0)
    Lua.lua_tolstring(L, -1, len)
    @test len[] == 5

    # Two lstrings with identical bytes are the same interned string
    Lua.lua_pushlstring(L, "a\0b\0c", 5)
    @test Lua.lua_rawequal(L, -1, -2) == 1
    Lua.lua_settop(L, 0)

    Lua.lua_close(L)
end

@testset "Userdata, uservalues, metatables" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    # Metatable with an __index method table
    @test Lua.luaL_newmetatable(L, "DeepTest.Box") == 1
    @test Lua.luaL_dostring(L, "DeepBoxIndex = { kind = function() return 'box' end }") == Lua.LUA_OK()
    Lua.lua_getglobal(L, "DeepBoxIndex")
    Lua.lua_setfield(L, -2, "__index")
    Lua.lua_pop(L, 1)

    # Userdata with a payload and 2 uservalue slots
    ud = Lua.lua_newuserdatauv(L, 16, 2)
    @test ud != C_NULL
    unsafe_store!(Ptr{UInt64}(ud), 0xdeadbeefcafebabe)
    @test Lua.lua_type(L, -1) == Lua.LUA_TUSERDATA()

    Lua.luaL_setmetatable(L, "DeepTest.Box")
    @test Lua.lua_getmetatable(L, -1) == 1
    Lua.luaL_getmetatable(L, "DeepTest.Box")
    @test Lua.lua_rawequal(L, -1, -2) == 1
    Lua.lua_pop(L, 2)

    # Uservalue slots are independent
    Lua.lua_pushstring(L, "slot one")
    @test Lua.lua_setiuservalue(L, -2, 1) == 1
    Lua.lua_pushinteger(L, 99)
    @test Lua.lua_setiuservalue(L, -2, 2) == 1
    @test Lua.lua_getiuservalue(L, -1, 1) == Lua.LUA_TSTRING()
    @test Lua.lua_tostring(L, -1) == "slot one"
    Lua.lua_pop(L, 1)
    @test Lua.lua_getiuservalue(L, -1, 2) == Lua.LUA_TNUMBER()
    @test Lua.lua_tointeger(L, -1) == 99
    Lua.lua_pop(L, 1)

    # Payload pointer survives, method dispatch through __index works
    @test Lua.lua_touserdata(L, -1) == ud
    @test unsafe_load(Ptr{UInt64}(ud)) == 0xdeadbeefcafebabe
    Lua.lua_setglobal(L, "deepbox")
    @test Lua.luaL_dostring(L, "box_kind = deepbox:kind()") == Lua.LUA_OK()
    Lua.lua_getglobal(L, "box_kind")
    @test Lua.lua_tostring(L, -1) == "box"
    Lua.lua_settop(L, 0)

    Lua.lua_close(L)
end

@testset "Table iteration and raw access" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)

    @test Lua.luaL_dostring(L, "iter_t = { alpha = 1, beta = 2, gamma = 3 }") == Lua.LUA_OK()
    Lua.lua_getglobal(L, "iter_t")

    # lua_next walk counts all pairs
    seen = Dict{String,Int}()
    Lua.lua_pushnil(L)
    while Lua.lua_next(L, -2) != 0
        seen[Lua.lua_tostring(L, -2)] = Int(Lua.lua_tointeger(L, -1))
        Lua.lua_pop(L, 1)
    end
    @test seen == Dict("alpha" => 1, "beta" => 2, "gamma" => 3)
    Lua.lua_pop(L, 1)

    # rawseti / rawgeti / seti / geti on an array table
    Lua.lua_newtable(L)
    for i in 1:5
        Lua.lua_pushinteger(L, 10i)
        Lua.lua_rawseti(L, -2, i)
    end
    @test Lua.lua_rawlen(L, -1) == 5
    @test Lua.lua_rawgeti(L, -1, 3) == Lua.LUA_TNUMBER()
    @test Lua.lua_tointeger(L, -1) == 30
    Lua.lua_pop(L, 1)
    Lua.lua_pushinteger(L, 60)
    Lua.lua_seti(L, -2, 6)
    @test Lua.lua_geti(L, -1, 6) == Lua.LUA_TNUMBER()
    @test Lua.lua_tointeger(L, -1) == 60
    Lua.lua_settop(L, 0)

    # __len metamethod: lua_len honors it, lua_rawlen bypasses it
    @test Lua.luaL_dostring(L, """
        len_t = setmetatable({1, 2, 3}, { __len = function() return 99 end })
    """) == Lua.LUA_OK()
    Lua.lua_getglobal(L, "len_t")
    Lua.lua_len(L, -1)
    @test Lua.lua_tointeger(L, -1) == 99
    Lua.lua_pop(L, 1)
    @test Lua.lua_rawlen(L, -1) == 3
    Lua.lua_settop(L, 0)

    Lua.lua_close(L)
end

@testset "Comparison, arithmetic, concat" begin
    L = Lua.luaL_newstate()

    Lua.lua_pushinteger(L, 10)
    Lua.lua_pushinteger(L, 20)
    @test Lua.lua_compare(L, -2, -1, Lua.LUA_OPLT()) == 1
    @test Lua.lua_compare(L, -2, -1, Lua.LUA_OPEQ()) == 0
    @test Lua.lua_compare(L, -2, -1, Lua.LUA_OPLE()) == 1

    # lua_arith pops operands and pushes the result
    @test Lua.lua_gettop(L) == 2
    Lua.lua_arith(L, Lua.LUA_OPADD())
    @test Lua.lua_gettop(L) == 1
    @test Lua.lua_tointeger(L, -1) == 30
    Lua.lua_pushinteger(L, 3)
    Lua.lua_arith(L, Lua.LUA_OPMUL())
    @test Lua.lua_tointeger(L, -1) == 90
    Lua.lua_arith(L, Lua.LUA_OPUNM())
    @test Lua.lua_tointeger(L, -1) == -90
    Lua.lua_settop(L, 0)

    # lua_concat with number coercion
    Lua.lua_pushstring(L, "foo")
    Lua.lua_pushinteger(L, 42)
    Lua.lua_concat(L, 2)
    @test Lua.lua_tostring(L, -1) == "foo42"
    Lua.lua_settop(L, 0)

    Lua.lua_close(L)
end

@testset "lua_pushfstring overloads" begin
    L = Lua.luaL_newstate()

    @test Lua.lua_pushfstring(L, "plain") == "plain"
    @test Lua.lua_pushfstring_Cint(L, "n=%d", Cint(-7)) == "n=-7"
    @test Lua.lua_pushfstring_Cdouble(L, "f=%f", 2.5) == "f=2.5"

    name = "lua"
    ver = "5.4"
    GC.@preserve name ver begin
        @test Lua.lua_pushfstring_Cstring(L, "hi %s", Cstring(pointer(name))) == "hi lua"
        @test Lua.lua_pushfstring_Cstring_Cint(L, "%s #%d", Cstring(pointer(name)), Cint(3)) == "lua #3"
        @test Lua.lua_pushfstring_Cstring_Cstring(L, "%s-%s", Cstring(pointer(name)), Cstring(pointer(ver))) == "lua-5.4"
    end

    # %p through the Any overload — some nonzero address gets formatted
    s = Lua.lua_pushfstring_Any(L, "ptr: %p", Lua.lua_version)
    @test startswith(s, "ptr: 0x")

    # Everything pushed stays on the stack: 7 strings
    @test Lua.lua_gettop(L) == 7
    Lua.lua_settop(L, 0)

    Lua.lua_close(L)
end

@testset "String conversions and gsub" begin
    L = Lua.luaL_newstate()

    # lua_stringtonumber returns strlen+1 on success, 0 on failure
    @test Lua.lua_stringtonumber(L, "3.25") == 5
    @test Lua.lua_tonumber(L, -1) == 3.25
    @test Lua.lua_isinteger(L, -1) == 0
    Lua.lua_pop(L, 1)

    @test Lua.lua_stringtonumber(L, "0x10") == 5
    @test Lua.lua_tointeger(L, -1) == 16
    @test Lua.lua_isinteger(L, -1) == 1
    Lua.lua_pop(L, 1)

    @test Lua.lua_stringtonumber(L, "not a number") == 0
    @test Lua.lua_gettop(L) == 0

    @test Lua.luaL_gsub(L, "hello world, world", "world", "lua") == "hello lua, lua"
    Lua.lua_pop(L, 1)

    # lua_typename for every tag
    @test Lua.lua_typename(L, Lua.LUA_TNIL()) == "nil"
    @test Lua.lua_typename(L, Lua.LUA_TBOOLEAN()) == "boolean"
    @test Lua.lua_typename(L, Lua.LUA_TNUMBER()) == "number"
    @test Lua.lua_typename(L, Lua.LUA_TSTRING()) == "string"
    @test Lua.lua_typename(L, Lua.LUA_TTABLE()) == "table"
    @test Lua.lua_typename(L, Lua.LUA_TFUNCTION()) == "function"
    @test Lua.lua_typename(L, Lua.LUA_TTHREAD()) == "thread"

    Lua.lua_close(L)
end

@testset "Stack gymnastics" begin
    L = Lua.luaL_newstate()

    @test Lua.LUA_MINSTACK() == 20
    @test Lua.lua_checkstack(L, 5000) == 1

    Lua.lua_pushstring(L, "a")
    Lua.lua_pushstring(L, "b")
    Lua.lua_pushstring(L, "c")
    @test Lua.lua_absindex(L, -1) == 3

    # rotate top→bottom: a,b,c → c,a,b
    Lua.lua_rotate(L, 1, 1)
    @test Lua.lua_tostring(L, 1) == "c"
    @test Lua.lua_tostring(L, 2) == "a"
    @test Lua.lua_tostring(L, 3) == "b"

    # insert / remove / replace macro shims
    Lua.lua_pushstring(L, "d")
    Lua.lua_insert(L, 1)          # d,c,a,b
    @test Lua.lua_tostring(L, 1) == "d"
    Lua.lua_remove(L, 2)          # d,a,b
    @test Lua.lua_tostring(L, 2) == "a"
    Lua.lua_pushstring(L, "z")
    Lua.lua_replace(L, 1)         # z,a,b
    @test Lua.lua_tostring(L, 1) == "z"
    @test Lua.lua_gettop(L) == 3

    Lua.lua_copy(L, 1, 3)         # z,a,z
    @test Lua.lua_tostring(L, 3) == "z"

    # pushvalue duplicates
    Lua.lua_pushvalue(L, 2)
    @test Lua.lua_tostring(L, -1) == "a"
    @test Lua.lua_rawequal(L, -1, 2) == 1

    # Main thread pushes itself and reports as main
    @test Lua.lua_pushthread(L) == 1
    @test Lua.lua_tothread(L, -1) == L
    Lua.lua_settop(L, 0)

    Lua.lua_close(L)
end

@testset "Integer edge cases" begin
    L = Lua.luaL_newstate()

    # Full 64-bit range survives the roundtrip
    Lua.lua_pushinteger(L, typemax(Int64))
    @test Lua.lua_tointeger(L, -1) == typemax(Int64)
    @test Lua.lua_isinteger(L, -1) == 1
    Lua.lua_pushinteger(L, typemin(Int64))
    @test Lua.lua_tointeger(L, -1) == typemin(Int64)
    Lua.lua_pop(L, 2)

    # Non-integral float refuses integer conversion via isnum out-param
    Lua.lua_pushnumber(L, 2.5)
    isnum = Ref{Cint}(-1)
    @test Lua.lua_tointegerx(L, -1, isnum) == 0
    @test isnum[] == 0
    @test Lua.lua_isinteger(L, -1) == 0

    # Integral float converts fine
    Lua.lua_pushnumber(L, 2.0^53)
    @test Lua.lua_tointegerx(L, -1, isnum) == 2^53
    @test isnum[] == 1
    Lua.lua_settop(L, 0)

    Lua.lua_close(L)
end

@testset "LUA_MULTRET and multiple returns" begin
    L = Lua.luaL_newstate()

    @test Lua.luaL_loadstring(L, "return 1, 2, 3") == Lua.LUA_OK()
    @test Lua.lua_pcall(L, 0, Lua.LUA_MULTRET(), 0) == Lua.LUA_OK()
    @test Lua.lua_gettop(L) == 3
    @test Lua.lua_tointeger(L, 1) == 1
    @test Lua.lua_tointeger(L, 2) == 2
    @test Lua.lua_tointeger(L, 3) == 3
    Lua.lua_settop(L, 0)

    Lua.lua_close(L)
end

@testset "GC stress and state churn" begin
    L = Lua.luaL_newstate()
    Lua.luaL_openlibs(L)
    Lua.luaL_checkversion(L)

    # Allocate ~heavily, drop it, and verify a full collect reclaims the heap
    Lua.lua_gc(L, Lua.LUA_GCCOLLECT())
    base_kb = Lua.lua_gc(L, Lua.LUA_GCCOUNT())
    @test Lua.luaL_dostring(L, """
        stress = {}
        for i = 1, 100000 do stress[i] = ("x"):rep(40) .. i end
    """) == Lua.LUA_OK()
    grown_kb = Lua.lua_gc(L, Lua.LUA_GCCOUNT())
    @test grown_kb > base_kb + 1000  # tens of MB allocated
    @test Lua.luaL_dostring(L, "stress = nil") == Lua.LUA_OK()
    Lua.lua_gc(L, Lua.LUA_GCCOLLECT())
    Lua.lua_gc(L, Lua.LUA_GCCOLLECT())
    final_kb = Lua.lua_gc(L, Lua.LUA_GCCOUNT())
    @test final_kb < base_kb + 512  # heap came back down
    Lua.lua_close(L)

    # State churn: create/exercise/destroy many independent states
    for i in 1:200
        Ls = Lua.luaL_newstate()
        @assert Ls != C_NULL
        Lua.lua_pushinteger(Ls, i)
        @assert Lua.lua_tointeger(Ls, -1) == i
        Lua.lua_close(Ls)
    end
    @test true  # churn loop survived
end

end  # top-level testset
