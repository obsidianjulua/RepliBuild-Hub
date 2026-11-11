#!/usr/bin/env julia
# argon2 Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
# Vectors are the upstream src/test.c KATs (PHC winner, version 0x13), using
# the m=8 (256 KiB) rows so the suite stays fast. The portable ref.c path is
# the one we compiled; agreement with those KATs is the proof it is the
# reference implementation, not a silently-wrong SIMD mix.
#   - ARGON2_MIN_* macro shims
#   - Argon2_Context layout (header-only aggregate, -fstandalone-debug)
#   - raw + encoded hash, verify, verify-mismatch, salt-too-short
#   - argon2i vs argon2id produce different digests
#   - error strings
#   - Tier 1 is OFF (quarantined); this package is pure ccall
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/argon2/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Argon2.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const A = Argon2

const OK = Cint(A.ARGON2_OK)
const V19 = UInt32(A.ARGON2_VERSION_NUMBER)

function hash_raw(type_::A.Argon2_type, pwd::AbstractString, salt::AbstractString;
                  t::Integer = 2, m::Integer = 8, p::Integer = 1, hashlen::Integer = 32)
    out = zeros(UInt8, hashlen)
    pb = Vector{UInt8}(codeunits(pwd))
    sb = Vector{UInt8}(codeunits(salt))
    GC.@preserve pb sb out begin
        rc = A.argon2_hash(UInt32(t), UInt32(1 << m), UInt32(p),
                           pointer(pb), length(pb), pointer(sb), length(sb),
                           pointer(out), length(out),
                           Ptr{UInt8}(C_NULL), 0,
                           type_, V19)
        return rc, out
    end
end

function hash_encoded(type_::A.Argon2_type, pwd::AbstractString, salt::AbstractString;
                      t::Integer = 2, m::Integer = 8, p::Integer = 1, hashlen::Integer = 32)
    n = Int(A.argon2_encodedlen(UInt32(t), UInt32(1 << m), UInt32(p),
                                UInt32(sizeof(salt)), UInt32(hashlen), type_))
    buf = zeros(UInt8, n + 1)
    pb = Vector{UInt8}(codeunits(pwd))
    sb = Vector{UInt8}(codeunits(salt))
    GC.@preserve pb sb buf begin
        rc = A.argon2_hash(UInt32(t), UInt32(1 << m), UInt32(p),
                           pointer(pb), length(pb), pointer(sb), length(sb),
                           Ptr{Cvoid}(C_NULL), hashlen,
                           pointer(buf), length(buf),
                           type_, V19)
        rc != OK && return rc, nothing
        return rc, unsafe_string(pointer(buf))
    end
end

@testset "argon2 Deep Tests" begin

@testset "Library identity" begin
    @test A.ARGON2_MIN_LANES() == 1
    @test A.ARGON2_MIN_THREADS() == 1
    @test A.ARGON2_MIN_OUTLEN() == 4
    @test A.ARGON2_MIN_SALT_LENGTH() == 8
    @test A.ARGON2_SYNC_POINTS() == 4
    @test A.ARGON2_DEFAULT_FLAGS() == 0
    @test A.ARGON2_FLAG_CLEAR_PASSWORD() == 1
    @test A.ARGON2_VERSION_10 == A.Argon2_version(0x10)
    @test A.ARGON2_VERSION_13 == A.Argon2_version(0x13)
    @test A.ARGON2_VERSION_NUMBER == A.Argon2_version(0x13)
    @test A.Argon2_i == A.Argon2_type(1)
    @test A.Argon2_id == A.Argon2_type(2)
    @test A.argon2_type2string(A.Argon2_i, 0) == "argon2i"
    @test A.argon2_type2string(A.Argon2_i, 1) == "Argon2i"
    @test A.argon2_type2string(A.Argon2_id, 0) == "argon2id"
    @test A.argon2_type2string(A.Argon2_d, 0) == "argon2d"
    @test A.argon2_error_message(Cint(A.ARGON2_DECODING_FAIL)) == "Decoding failed"
    @test A.argon2_error_message(Cint(A.ARGON2_OK)) == "OK"
    @test A.argon2_error_message(Cint(A.ARGON2_VERIFY_MISMATCH)) !== nothing
end

@testset "Tier 1 is OFF — pure ccall" begin
    for n in (:TIER1_FUNCTIONS, :TIER1_DECLARES, :_TIER1_KERNEL, :_slice_symbols_resolve)
        @test !isdefined(A, n)
    end
    @test !isdir(joinpath(PKG_DIR, "julia", "slices"))
    src = read(WRAPPER, String)
    @test !occursin("@generated function _TIER1_", src)
    @test !occursin("const _SLICE_", src)
    @test !occursin("llvmcall", src)
    @test !isdefined(A, :DISPATCH_TIER)
    @test !isdefined(A, :dispatch_tier)
    @test occursin("Every function in this module dispatches through Tier 3", src)
end

@testset "Layout of Argon2_Context" begin
    # Header-only aggregate the caller fills. Empty here means
    # -fstandalone-debug was dropped.
    @test A.struct_size(:Argon2_Context) == 120
    @test A.member_offset(:Argon2_Context, :out) == 0
    @test A.member_offset(:Argon2_Context, :pwd) == 16
    @test A.member_offset(:Argon2_Context, :salt) == 32
    @test A.member_offset(:Argon2_Context, :t_cost) == 76
    @test A.member_offset(:Argon2_Context, :m_cost) == 80
    @test A.member_offset(:Argon2_Context, :version) == 92
    @test A.member_offset(:Argon2_Context, :flags) == 112
    @test A.struct_size(:block) == 1024
end

@testset "upstream KAT — argon2i v19 m=8" begin
    # src/test.c, ARGON2_VERSION_NUMBER, t=2 m=8 p=1, password/somesalt
    rc, raw = hash_raw(A.Argon2_i, "password", "somesalt"; t=2, m=8, p=1)
    @test rc == OK
    @test bytes2hex(raw) == "89e9029f4637b295beb027056a7336c414fadd43f6b208645281cb214a56452f"

    rc, enc = hash_encoded(A.Argon2_i, "password", "somesalt"; t=2, m=8, p=1)
    @test rc == OK
    @test enc == "\$argon2i\$v=19\$m=256,t=2,p=1\$c29tZXNhbHQ\$iekCn0Y3spW+sCcFanM2xBT63UP2sghkUoHLIUpWRS8"

    pb = Vector{UInt8}(codeunits("password"))
    @test A.argon2i_verify(enc, pb, length(pb)) == OK
    @test A.argon2_verify(enc, pb, length(pb), A.Argon2_i) == OK

    # t=2 m=8 p=2
    rc, raw2 = hash_raw(A.Argon2_i, "password", "somesalt"; t=2, m=8, p=2)
    @test rc == OK
    @test bytes2hex(raw2) == "4ff5ce2769a1d7f4c8a491df09d41a9fbe90e5eb02155a13e4c01e20cd4eab61"
end

@testset "upstream KAT — argon2id v19 m=8" begin
    rc, raw = hash_raw(A.Argon2_id, "password", "somesalt"; t=2, m=8, p=1)
    @test rc == OK
    @test bytes2hex(raw) == "9dfeb910e80bad0311fee20f9c0e2b12c17987b4cac90c2ef54d5b3021c68bfe"

    rc, enc = hash_encoded(A.Argon2_id, "password", "somesalt"; t=2, m=8, p=1)
    @test rc == OK
    @test enc == "\$argon2id\$v=19\$m=256,t=2,p=1\$c29tZXNhbHQ\$nf65EOgLrQMR/uIPnA4rEsF5h7TKyQwu9U1bMCHGi/4"

    pb = Vector{UInt8}(codeunits("password"))
    @test A.argon2id_verify(enc, pb, length(pb)) == OK

    # Different type → different digest (the portable mix-up canary)
    rc_i, raw_i = hash_raw(A.Argon2_i, "password", "somesalt"; t=2, m=8, p=1)
    @test rc_i == OK
    @test raw != raw_i
end

@testset "typed convenience wrappers agree with argon2_hash" begin
    out = zeros(UInt8, 32)
    pwd = Vector{UInt8}(codeunits("password"))
    salt = Vector{UInt8}(codeunits("somesalt"))
    GC.@preserve pwd salt out begin
        rc = A.argon2i_hash_raw(UInt32(2), UInt32(256), UInt32(1),
                                pointer(pwd), length(pwd),
                                pointer(salt), length(salt),
                                pointer(out), length(out))
        @test rc == OK
        @test bytes2hex(out) == "89e9029f4637b295beb027056a7336c414fadd43f6b208645281cb214a56452f"

        fill!(out, 0)
        rc = A.argon2id_hash_raw(UInt32(2), UInt32(256), UInt32(1),
                                 pointer(pwd), length(pwd),
                                 pointer(salt), length(salt),
                                 pointer(out), length(out))
        @test rc == OK
        @test bytes2hex(out) == "9dfeb910e80bad0311fee20f9c0e2b12c17987b4cac90c2ef54d5b3021c68bfe"
    end
end

@testset "error paths" begin
    pwd = Vector{UInt8}(codeunits("password"))
    # Verify mismatch (encoded password is "passwore")
    bad = "\$argon2i\$v=19\$m=256,t=2,p=1\$c29tZXNhbHQ\$iekCn0Y3spW+sCcFanM2xBT63UP2sghkUoHLIUpWRS8"
    @test A.argon2i_verify(bad, Vector{UInt8}(codeunits("wrongpass")), 9) == Cint(A.ARGON2_VERIFY_MISMATCH)

    # Invalid encoding (missing \$ before salt)
    @test A.argon2_verify("\$argon2i\$v=19\$m=256,t=2,p=1c29tZXNhbHQ\$iekCn0Y3spW+sCcFanM2xBT63UP2sghkUoHLIUpWRS8",
                          pwd, length(pwd), A.Argon2_i) == Cint(A.ARGON2_DECODING_FAIL)

    # Salt too short (1 byte)
    out = zeros(UInt8, 32)
    salt = Vector{UInt8}(codeunits("s"))
    GC.@preserve pwd salt out begin
        rc = A.argon2_hash(UInt32(2), UInt32(1 << 12), UInt32(1),
                           pointer(pwd), length(pwd), pointer(salt), 1,
                           pointer(out), 32, Ptr{UInt8}(C_NULL), 0,
                           A.Argon2_id, V19)
        @test rc == Cint(A.ARGON2_SALT_TOO_SHORT)
    end

    # Memory too little (m_cost = 1)
    GC.@preserve pwd begin
        rc = A.argon2_hash(UInt32(2), UInt32(1), UInt32(1),
                           pointer(pwd), length(pwd),
                           pointer(Vector{UInt8}(codeunits("diffsalt"))), 8,
                           pointer(out), 32, Ptr{UInt8}(C_NULL), 0,
                           A.Argon2_id, V19)
        @test rc == Cint(A.ARGON2_MEMORY_TOO_LITTLE)
    end
end

@testset "churn under GC pressure" begin
    expected = "89e9029f4637b295beb027056a7336c414fadd43f6b208645281cb214a56452f"
    for i in 1:12
        rc, raw = hash_raw(A.Argon2_i, "password", "somesalt"; t=2, m=8, p=1)
        @test rc == OK
        @test bytes2hex(raw) == expected
        i % 4 == 0 && GC.gc(false)
    end
end

end
