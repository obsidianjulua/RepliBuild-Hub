#!/usr/bin/env julia
# LMDB Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
#   - library identity + the MDB_VERSION_* macro shim (the canary for header
#     resolution: a bare "lmdb.h" falls through to system liblmdb)
#   - MDB_val / MDB_stat layout — header-only aggregates that need
#     -fstandalone-debug; empty structs would fail here, not at wrap time
#   - env open with MDB_NOSUBDIR, mapsize, put/get round-trip
#   - missing key, NOOVERWRITE duplicate, delete
#   - cursor walk in key order
#   - read-only txn, stats, error strings
#   - Tier 1 is OFF (quarantined); this package is pure ccall
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/lmdb/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Lmdb.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const L = Lmdb

"Open an LMDB env at a temp MDB_NOSUBDIR file, run `f(env)`, always close."
function withenv(f; mapsize::Integer = 1 << 20)
    dir = mktempdir()
    path = joinpath(dir, "data.mdb")
    penv = Ref{Ptr{L.MDB_env}}(C_NULL)
    rc = L.mdb_env_create(penv)
    rc == L.MDB_SUCCESS() || error("mdb_env_create: $(L.mdb_strerror(rc))")
    env = penv[]
    try
        rc = L.mdb_env_set_mapsize(env, mapsize)
        rc == L.MDB_SUCCESS() || error("set_mapsize: $(L.mdb_strerror(rc))")
        rc = L.mdb_env_open(env, path, L.MDB_NOSUBDIR(), 0o600)
        rc == L.MDB_SUCCESS() || error("mdb_env_open: $(L.mdb_strerror(rc))")
        return f(env)
    finally
        L.mdb_env_close(env)
        rm(dir; recursive=true, force=true)
    end
end

"Begin a txn, run `f(txn)`, abort if the callback does not commit."
function withtxn(f, env; flags::Integer = 0, commit::Bool = true)
    ptxn = Ref{Ptr{L.MDB_txn}}(C_NULL)
    rc = L.mdb_txn_begin(env, C_NULL, flags, ptxn)
    rc == L.MDB_SUCCESS() || error("mdb_txn_begin: $(L.mdb_strerror(rc))")
    txn = ptxn[]
    committed = false
    try
        r = f(txn)
        if commit
            rc = L.mdb_txn_commit(txn)
            rc == L.MDB_SUCCESS() || error("mdb_txn_commit: $(L.mdb_strerror(rc))")
            committed = true
        end
        return r
    finally
        committed || L.mdb_txn_abort(txn)
    end
end

opendbi(txn; flags = L.MDB_CREATE()) = begin
    pdbi = Ref{Cuint}(0)
    rc = L.mdb_dbi_open(txn, C_NULL, flags, pdbi)
    rc == L.MDB_SUCCESS() || error("mdb_dbi_open: $(L.mdb_strerror(rc))")
    pdbi[]
end

function mdbput!(txn, dbi, key::AbstractString, val::AbstractString; flags::Integer = 0)
    kb = Vector{UInt8}(codeunits(key))
    vb = Vector{UInt8}(codeunits(val))
    GC.@preserve kb vb begin
        k = Ref(L.MDB_val(sizeof(kb), pointer(kb)))
        v = Ref(L.MDB_val(sizeof(vb), pointer(vb)))
        return L.mdb_put(txn, dbi, k, v, flags)
    end
end

function mdbget(txn, dbi, key::AbstractString)
    kb = Vector{UInt8}(codeunits(key))
    data = Ref(L.MDB_val())
    GC.@preserve kb begin
        k = Ref(L.MDB_val(sizeof(kb), pointer(kb)))
        rc = L.mdb_get(txn, dbi, k, data)
        rc != L.MDB_SUCCESS() && return (rc, nothing)
        d = data[]
        return (rc, unsafe_string(Ptr{UInt8}(d.mv_data), d.mv_size))
    end
end

function mdbdel!(txn, dbi, key::AbstractString)
    kb = Vector{UInt8}(codeunits(key))
    GC.@preserve kb begin
        k = Ref(L.MDB_val(sizeof(kb), pointer(kb)))
        return L.mdb_del(txn, dbi, k, C_NULL)
    end
end

@testset "LMDB Deep Tests" begin

@testset "Library identity" begin
    @test L.MDB_VERSION_MAJOR() == 0
    @test L.MDB_VERSION_MINOR() == 9
    @test L.MDB_VERSION_PATCH() == 36
    @test L.MDB_VERSION_FULL() == ((0 << 24) | (9 << 16) | 36)
    @test L.MDB_VERSION_STRING() == "LMDB 0.9.36: (Aug 6, 2026)"

    maj = Ref{Cint}(0); minr = Ref{Cint}(0); pat = Ref{Cint}(0)
    vs = L.mdb_version(maj, minr, pat)
    @test maj[] == L.MDB_VERSION_MAJOR()
    @test minr[] == L.MDB_VERSION_MINOR()
    @test pat[] == L.MDB_VERSION_PATCH()
    # Runtime twin of the shim — disagreement means the shim compiled against
    # a DIFFERENT lmdb.h (a bare "lmdb.h" vs the in-clone subpath).
    @test vs == L.MDB_VERSION_STRING()

    @test L.MDB_SUCCESS() == 0
    @test L.MDB_KEYEXIST() == -30799
    @test L.MDB_NOTFOUND() == -30798
    @test L.MDB_MAP_FULL() == -30792
    @test L.MDB_INVALID() == -30793
    @test L.MDB_NOSUBDIR() == 0x4000
    @test L.MDB_RDONLY() == 0x20000
    @test L.MDB_CREATE() == 0x40000
    @test L.MDB_NOOVERWRITE() == 0x10
    @test L.mdb_strerror(L.MDB_NOTFOUND()) == "MDB_NOTFOUND: No matching key/data pair found"
    @test L.mdb_strerror(L.MDB_SUCCESS()) !== nothing
end

@testset "Tier 1 is OFF — pure ccall" begin
    for n in (:TIER1_FUNCTIONS, :TIER1_DECLARES, :_TIER1_KERNEL, :_slice_symbols_resolve)
        @test !isdefined(L, n)
    end
    @test !isdir(joinpath(PKG_DIR, "julia", "slices"))
    src = read(WRAPPER, String)
    @test !occursin("@generated function _TIER1_", src)
    @test !occursin("const _SLICE_", src)
    @test !occursin("llvmcall", src)
    @test !isdefined(L, :DISPATCH_TIER)
    @test !isdefined(L, :dispatch_tier)
    @test occursin("Every function in this module dispatches through Tier 3", src)
end

@testset "Layout of the public aggregates" begin
    # Header-only structs the caller fills. Empty here means
    # -fstandalone-debug was dropped.
    @test L.struct_size(:MDB_val) == 16
    @test L.member_offset(:MDB_val, :mv_size) == 0
    @test L.member_offset(:MDB_val, :mv_data) == 8
    @test fieldnames(L.MDB_val) === (:mv_size, :mv_data)

    @test L.struct_size(:MDB_stat) == 40
    @test L.member_offset(:MDB_stat, :ms_psize) == 0
    @test L.member_offset(:MDB_stat, :ms_entries) == 32
    @test fieldnames(L.MDB_stat) === (:ms_psize, :ms_depth, :ms_branch_pages,
                                      :ms_leaf_pages, :ms_overflow_pages, :ms_entries)

    @test L.struct_size(:MDB_envinfo) == 40
end

@testset "put / get round-trip" begin
    withenv() do env
        withtxn(env) do txn
            dbi = opendbi(txn)
            @test mdbput!(txn, dbi, "hello", "world") == L.MDB_SUCCESS()
            rc, val = mdbget(txn, dbi, "hello")
            @test rc == L.MDB_SUCCESS()
            @test val == "world"
        end
        withtxn(env; flags = L.MDB_RDONLY(), commit = false) do txn
            dbi = opendbi(txn; flags = 0)
            rc, val = mdbget(txn, dbi, "hello")
            @test rc == L.MDB_SUCCESS()
            @test val == "world"
            @test L.mdb_txn_env(txn) == env
        end
    end
end

@testset "missing key, overwrite, NOOVERWRITE, delete" begin
    withenv() do env
        withtxn(env) do txn
            dbi = opendbi(txn)
            @test mdbput!(txn, dbi, "k", "v1") == L.MDB_SUCCESS()
            rc, val = mdbget(txn, dbi, "missing")
            @test rc == L.MDB_NOTFOUND()
            @test val === nothing

            @test mdbput!(txn, dbi, "k", "v2") == L.MDB_SUCCESS()
            _, val = mdbget(txn, dbi, "k")
            @test val == "v2"

            @test mdbput!(txn, dbi, "k", "v3"; flags = L.MDB_NOOVERWRITE()) == L.MDB_KEYEXIST()
            _, val = mdbget(txn, dbi, "k")
            @test val == "v2"

            @test mdbdel!(txn, dbi, "k") == L.MDB_SUCCESS()
            rc, _ = mdbget(txn, dbi, "k")
            @test rc == L.MDB_NOTFOUND()
            @test mdbdel!(txn, dbi, "k") == L.MDB_NOTFOUND()
        end
    end
end

@testset "cursor walk is sorted" begin
    withenv() do env
        withtxn(env) do txn
            dbi = opendbi(txn)
            for (k, v) in (("c", "3"), ("a", "1"), ("b", "2"), ("d", "4"))
                @test mdbput!(txn, dbi, k, v) == L.MDB_SUCCESS()
            end
            pc = Ref{Ptr{L.MDB_cursor}}(C_NULL)
            @test L.mdb_cursor_open(txn, dbi, pc) == L.MDB_SUCCESS()
            cur = pc[]
            try
                keys = String[]
                vals = String[]
                k = Ref(L.MDB_val())
                v = Ref(L.MDB_val())
                rc = L.mdb_cursor_get(cur, k, v, L.MDB_FIRST)
                while rc == L.MDB_SUCCESS()
                    push!(keys, unsafe_string(Ptr{UInt8}(k[].mv_data), k[].mv_size))
                    push!(vals, unsafe_string(Ptr{UInt8}(v[].mv_data), v[].mv_size))
                    rc = L.mdb_cursor_get(cur, k, v, L.MDB_NEXT)
                end
                @test rc == L.MDB_NOTFOUND()
                @test keys == ["a", "b", "c", "d"]
                @test vals == ["1", "2", "3", "4"]
                @test L.mdb_cursor_dbi(cur) == dbi
                @test L.mdb_cursor_txn(cur) == txn
            finally
                L.mdb_cursor_close(cur)
            end
        end
    end
end

@testset "stats, flags, maxkeysize" begin
    withenv() do env
        pflags = Ref{Cuint}(0)
        @test L.mdb_env_get_flags(env, pflags) == L.MDB_SUCCESS()
        @test pflags[] & L.MDB_NOSUBDIR() != 0

        @test L.mdb_env_get_maxkeysize(env) > 0

        ppath = Ref{Ptr{UInt8}}(C_NULL)
        @test L.mdb_env_get_path(env, ppath) == L.MDB_SUCCESS()
        @test occursin("data.mdb", unsafe_string(ppath[]))

        withtxn(env) do txn
            dbi = opendbi(txn)
            @test mdbput!(txn, dbi, "n", "1") == L.MDB_SUCCESS()
            st = Ref(L.MDB_stat())
            @test L.mdb_stat(txn, dbi, st) == L.MDB_SUCCESS()
            @test st[].ms_entries == 1
            @test st[].ms_psize > 0
            @test st[].ms_leaf_pages >= 1
        end

        info = Ref(L.MDB_envinfo())
        @test L.mdb_env_info(env, info) == L.MDB_SUCCESS()
        @test info[].me_mapsize >= 1 << 20
        @test info[].me_last_txnid >= 1
    end
end

@testset "NUL inside values and empty value" begin
    withenv() do env
        withtxn(env) do txn
            dbi = opendbi(txn)
            blob = UInt8[0x00, 0x01, 0x00, 0xff]
            kb = Vector{UInt8}(codeunits("bin"))
            empty = UInt8[]
            GC.@preserve kb blob empty begin
                k = Ref(L.MDB_val(sizeof(kb), pointer(kb)))
                v = Ref(L.MDB_val(sizeof(blob), pointer(blob)))
                @test L.mdb_put(txn, dbi, k, v, 0) == L.MDB_SUCCESS()
                out = Ref(L.MDB_val())
                @test L.mdb_get(txn, dbi, k, out) == L.MDB_SUCCESS()
                got = unsafe_wrap(Array, Ptr{UInt8}(out[].mv_data), out[].mv_size)
                @test got == blob

                ek = Vector{UInt8}(codeunits("empty"))
                GC.@preserve ek begin
                    ke = Ref(L.MDB_val(sizeof(ek), pointer(ek)))
                    ve = Ref(L.MDB_val(0, Ptr{Cvoid}(C_NULL)))
                    @test L.mdb_put(txn, dbi, ke, ve, 0) == L.MDB_SUCCESS()
                    oute = Ref(L.MDB_val())
                    @test L.mdb_get(txn, dbi, ke, oute) == L.MDB_SUCCESS()
                    @test oute[].mv_size == 0
                end
            end
        end
    end
end

@testset "abort discards writes" begin
    withenv() do env
        withtxn(env; commit = false) do txn
            dbi = opendbi(txn)
            @test mdbput!(txn, dbi, "gone", "yes") == L.MDB_SUCCESS()
        end
        withtxn(env; flags = L.MDB_RDONLY(), commit = false) do txn
            dbi = opendbi(txn; flags = 0)
            rc, _ = mdbget(txn, dbi, "gone")
            @test rc == L.MDB_NOTFOUND()
        end
    end
end

@testset "churn under GC pressure" begin
    withenv(; mapsize = 8 << 20) do env
        withtxn(env) do txn
            dbi = opendbi(txn)
            for i in 1:200
                @test mdbput!(txn, dbi, "k$i", "v$i") == L.MDB_SUCCESS()
                i % 17 == 0 && GC.gc(false)
            end
        end
        withtxn(env; flags = L.MDB_RDONLY(), commit = false) do txn
            dbi = opendbi(txn; flags = 0)
            for i in (1, 50, 200)
                rc, val = mdbget(txn, dbi, "k$i")
                @test rc == L.MDB_SUCCESS()
                @test val == "v$i"
            end
            st = Ref(L.MDB_stat())
            @test L.mdb_stat(txn, dbi, st) == L.MDB_SUCCESS()
            @test st[].ms_entries == 200
        end
    end
end

end
