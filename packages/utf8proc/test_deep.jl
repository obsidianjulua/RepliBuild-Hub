#!/usr/bin/env julia
# utf8proc Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
#   - library identity + UTF8PROC_VERSION_* macro shim (the canary: a bare
#     "utf8proc.h" falls through to system libutf8proc, common next to Julia)
#   - utf8proc_property_struct is 24 bytes with bitfields; category is a
#     named accessor, not a Julia field
#   - iterate / encode round-trip of 1/2/3/4-byte UTF-8
#   - NFC / NFD / NFKC / casefold against Unicode identities
#   - category, case, charwidth, grapheme break
#   - invalid UTF-8 errors
#   - Tier 1 is OFF (quarantined); this package is pure ccall
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/utf8proc/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Utf8proc.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const U = Utf8proc

"Copy a malloc'd UTF-8 buffer to a Julia String and free it."
function take_utf8(p::Ptr{UInt8})
    p == C_NULL && return nothing
    s = unsafe_string(p)
    Libc.free(p)
    return s
end

function iterate_all(s::AbstractString)
    bytes = Vector{UInt8}(codeunits(s))
    cps = Int32[]
    i = 0
    GC.@preserve bytes begin
        while i < length(bytes)
            cp = Ref{Int32}(0)
            n = U.utf8proc_iterate(pointer(bytes) + i, Cptrdiff_t(length(bytes) - i), cp)
            n > 0 || return (n, cps)
            push!(cps, cp[])
            i += Int(n)
        end
    end
    return (Cptrdiff_t(0), cps)
end

@testset "utf8proc Deep Tests" begin

@testset "Library identity" begin
    @test U.UTF8PROC_VERSION_MAJOR() == 2
    @test U.UTF8PROC_VERSION_MINOR() == 11
    @test U.UTF8PROC_VERSION_PATCH() == 3
    @test U.utf8proc_version() == "2.11.3"
    # Runtime twin of the shim — disagreement means the shim compiled against
    # a DIFFERENT utf8proc.h (system libutf8proc vs the vendored header).
    @test U.utf8proc_version() == "$(U.UTF8PROC_VERSION_MAJOR()).$(U.UTF8PROC_VERSION_MINOR()).$(U.UTF8PROC_VERSION_PATCH())"
    @test U.utf8proc_unicode_version() == "17.0.0"

    @test U.UTF8PROC_ERROR_NOMEM() == -1
    @test U.UTF8PROC_ERROR_OVERFLOW() == -2
    @test U.UTF8PROC_ERROR_INVALIDUTF8() == -3
    @test U.UTF8PROC_ERROR_NOTASSIGNED() == -4
    @test U.UTF8PROC_ERROR_INVALIDOPTS() == -5
    @test occursin("Invalid UTF-8", U.utf8proc_errmsg(Cptrdiff_t(U.UTF8PROC_ERROR_INVALIDUTF8())))
    @test U.utf8proc_errmsg(Cptrdiff_t(U.UTF8PROC_ERROR_NOMEM())) !== nothing
end

@testset "Tier 1 is OFF — pure ccall" begin
    for n in (:TIER1_FUNCTIONS, :TIER1_DECLARES, :_TIER1_KERNEL, :_slice_symbols_resolve)
        @test !isdefined(U, n)
    end
    @test !isdir(joinpath(PKG_DIR, "julia", "slices"))
    src = read(WRAPPER, String)
    @test !occursin("@generated function _TIER1_", src)
    @test !occursin("const _SLICE_", src)
    @test !occursin("llvmcall", src)
    @test !isdefined(U, :DISPATCH_TIER)
    @test !isdefined(U, :dispatch_tier)
    @test occursin("Every function in this module dispatches through Tier 3", src)
end

@testset "Layout of utf8proc_property_struct" begin
    @test U.struct_size(:utf8proc_property_struct) == 24
    @test U.member_offset(:utf8proc_property_struct, :category) == 0
    @test U.member_offset(:utf8proc_property_struct, :titlecase_seqindex) == 16
    # Bitfields are packed after the named 16-bit members; the Julia type is
    # a 24-byte blob with get_* accessors, not named fields for the bits.
    p = unsafe_load(U.utf8proc_get_property(Int32('A')))
    @test U.get_category(p) == Int16(U.UTF8PROC_CATEGORY_LU)
    @test U.get_charwidth(p) == 1
    p2 = unsafe_load(U.utf8proc_get_property(Int32('a')))
    @test U.get_category(p2) == Int16(U.UTF8PROC_CATEGORY_LL)
end

@testset "iterate / encode round-trip" begin
    # ASCII, 2-byte (U+00E9), 3-byte (U+20AC euro), 4-byte (U+1F600 grin)
    samples = ['A', '\u00e9', '\u20ac', '\U1f600']
    for ch in samples
        @test U.utf8proc_codepoint_valid(Int32(ch))
        buf = zeros(UInt8, 8)
        n = U.utf8proc_encode_char(Int32(ch), buf)
        @test n > 0
        encoded = buf[1:Int(n)]
        @test encoded == collect(codeunits(string(ch)))
        cp = Ref{Int32}(0)
        n2 = U.utf8proc_iterate(encoded, Cptrdiff_t(length(encoded)), cp)
        @test n2 == n
        @test cp[] == Int32(ch)
    end

    rc, cps = iterate_all("café")
    @test rc == 0
    @test cps == Int32['c', 'a', 'f', '\u00e9']

    # Invalid continuation
    bad = UInt8[0xC3, 0x28]   # 2-byte starter, not a continuation
    cp = Ref{Int32}(-1)
    n = U.utf8proc_iterate(bad, Cptrdiff_t(2), cp)
    @test n == Cptrdiff_t(U.UTF8PROC_ERROR_INVALIDUTF8())
    @test !U.utf8proc_codepoint_valid(Int32(0xD800))  # surrogate
    @test !U.utf8proc_codepoint_valid(Int32(0x110000))
end

@testset "NFC / NFD / NFKC / casefold" begin
    # e + combining acute → composed é
    @test take_utf8(U.utf8proc_NFC("e\u0301")) == "\u00e9"
    @test take_utf8(U.utf8proc_NFD("\u00e9")) == "e\u0301"
    # Already-composed NFC is a no-op
    @test take_utf8(U.utf8proc_NFC("\u00e9")) == "\u00e9"
    # Compatibility: ﬁ (U+FB01) → fi
    @test take_utf8(U.utf8proc_NFKC("\ufb01")) == "fi"
    @test take_utf8(U.utf8proc_NFKD("\ufb01")) == "fi"
    # German ß casefold
    folded = take_utf8(U.utf8proc_NFKC_Casefold("Straße"))
    @test folded == "strasse"
    # Empty
    @test take_utf8(U.utf8proc_NFC("")) == ""
end

@testset "category, case, width, grapheme" begin
    @test U.utf8proc_category(Int32('A')) == U.UTF8PROC_CATEGORY_LU
    @test U.utf8proc_category(Int32('a')) == U.UTF8PROC_CATEGORY_LL
    @test U.utf8proc_category(Int32('1')) == U.UTF8PROC_CATEGORY_ND
    @test U.utf8proc_category_string(Int32('A')) == "Lu"
    @test U.utf8proc_category_string(Int32(' ')) == "Zs"

    @test U.utf8proc_tolower(Int32('A')) == Int32('a')
    @test U.utf8proc_toupper(Int32('a')) == Int32('A')
    @test U.utf8proc_totitle(Int32('a')) == Int32('A')
    @test U.utf8proc_isupper(Int32('A')) == 1
    @test U.utf8proc_islower(Int32('a')) == 1
    @test U.utf8proc_isupper(Int32('a')) == 0
    @test U.utf8proc_tolower(Int32('1')) == Int32('1')

    @test U.utf8proc_charwidth(Int32('A')) == 1
    @test U.utf8proc_charwidth(Int32('\n')) == 0
    @test U.utf8proc_charwidth(Int32('\u3000')) == 2   # ideographic space
    @test U.utf8proc_charwidth(Int32('\U1f600')) == 2  # emoji
    @test U.utf8proc_charwidth_ambiguous(Int32('A')) == false

    # g + combining acute is one grapheme (no break)
    @test U.utf8proc_grapheme_break(Int32('g'), Int32(0x0301)) == false
    @test U.utf8proc_grapheme_break(Int32('a'), Int32('b')) == true
    state = Ref{Int32}(0)
    @test U.utf8proc_grapheme_break_stateful(Int32('a'), Int32('b'), state) == true
end

@testset "utf8class table" begin
    cls = U.utf8proc_utf8class()
    @test cls[0x00 + 1] == 1
    @test cls[0x7F + 1] == 1
    @test cls[0xC2 + 1] == 2
    @test cls[0xE0 + 1] == 3
    @test cls[0xF0 + 1] == 4
    @test cls[0x80 + 1] == 0   # continuation, not a starter
end

@testset "churn under GC pressure" begin
    for i in 1:120
        s = take_utf8(U.utf8proc_NFC("cafe\u0301 $i"))
        @test s == "café $i"
        i % 13 == 0 && GC.gc(false)
    end
    rc, cps = iterate_all(repeat("é", 50))
    @test rc == 0
    @test length(cps) == 50
    @test all(==(Int32('\u00e9')), cps)
end

end
