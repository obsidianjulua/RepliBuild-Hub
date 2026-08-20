#!/usr/bin/env julia
# tomlc17 Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
#   - TOML v1.0 semantics: every scalar type, nested tables, arrays of tables,
#     dotted keys, multiline and literal strings, datetimes
#   - error reporting on malformed documents
#   - toml_seek / toml_get navigation, toml_equiv, toml_merge
#   - result ownership: toml_free must be paired with every successful parse
#   - Tier-1 liveness and churn under GC pressure
#
# LAYOUT NOTE:
# toml_datum_t and toml_result_t both embed an anonymous union. Until 2026-08-01
# the generator dropped the unnamed aggregate DIE and degraded the WHOLE
# enclosing struct to an opaque blob (_data::NTuple{40,…} / NTuple{256,…}), so
# this file read the documented byte offsets by hand. The generator now names
# anonymous aggregates and emits the union as a correctly-sized, correctly
# aligned opaque region, so every field below is a REAL named field and the
# accessors are one-liners. `Layout invariants` still pins sizes and offsets
# against the C declaration — the union arms alias each other, so a layout slip
# would misread values rather than raise.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/tomlc17/test_deep.jl

using Test
using InteractiveUtils: code_typed

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Tomlc17.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const T = Tomlc17

# ── Field accessors ─────────────────────────────────────────────────────────
# Named fields all the way down: `type` is spelled `type_` because the C
# generator renames members that collide with its reserved-identifier list, and
# `u` is the anonymous union, emitted as an opaque region whose `getproperty`
# reads each arm at its own type. `str`/`arr`/`tab`/`ts` are the union's own
# anonymous struct arms, named after the member that embeds them.

dtype(d) = d.type_
dflag(d) = d.flag
dint(d)  = d.u.int64
dfp(d)   = d.u.fp64
dbool(d) = d.u.boolean
dstrptr(d) = Ptr{UInt8}(d.u.str.ptr)
dstr(d)  = unsafe_string(dstrptr(d))
dstrlen(d) = d.u.str.len
darrsize(d) = d.u.arr.size
darrelem(d) = Ptr{T.toml_datum_t}(d.u.arr.elem)
dtabsize(d) = d.u.tab.size
dtabkey(d)  = d.u.tab.key
dtabvalue(d) = Ptr{T.toml_datum_t}(d.u.tab.value)
dts(d) = d.u.ts

rok(r)     = r.ok
rtoptab(r) = r.toptab
# errmsg is a fixed 200-byte buffer; the message is the NUL-terminated prefix.
function rerr(r)
    b = r.errmsg
    n = something(findfirst(==(0x00), b), length(b) + 1) - 1
    return String(UInt8[b[i] for i in 1:n])
end

"Index an array datum (0-based, as the C API is)."
arrat(d, i) = unsafe_load(darrelem(d), i + 1)
"Index a table datum's i-th value (0-based)."
tabat(d, i) = unsafe_load(dtabvalue(d), i + 1)
tabkeyat(d, i) = unsafe_string(unsafe_load(dtabkey(d), i + 1))

"Parse `src`, run `f(toptab)`, always free."
function withtoml(f, src::AbstractString)
    r = T.toml_parse(src, sizeof(src))
    try
        rok(r) || error("parse failed: $(rerr(r))")
        return f(rtoptab(r))
    finally
        T.toml_free(r)
    end
end

const DOC = """
title = "tomlc17 deep test"
answer = 42
ratio = 3.5
enabled = true
disabled = false
when = 1979-05-27T07:32:00Z
plainday = 1979-05-27
plaintime = 07:32:10
literal = 'C:\\path\\no\\escapes'
multi = \"\"\"
line one
line two\"\"\"
numbers = [1, 2, 3]
mixedish = ["a", "b"]
nested = [[1, 2], [3]]

[owner]
name = "john"
[owner.address]
city = "somewhere"

[dotted]
a.b.c = "deep"

[[products]]
name = "hammer"
sku = 738594937

[[products]]
name = "nail"
sku = 284758393
"""

@testset "tomlc17 Deep Tests" begin

@testset "Layout invariants (guards the field accessors)" begin
    # Sizes and offsets against the C declaration. The union arms alias each
    # other, so a layout slip misreads values instead of raising — fail here,
    # loudly and in one place.
    @test sizeof(T.toml_datum_t) == 40
    @test sizeof(T.toml_result_t) == 256
    @test sizeof(T.toml_datum_t_u) == 32

    # Real named fields, not a byte blob. This is the regression that made the
    # wrapper unusable: 40 bytes of `_data` with nothing reachable.
    @test fieldnames(T.toml_datum_t) == (:type_, :flag, :u)
    @test [fieldoffset(T.toml_datum_t, i) for i in 1:3] == [0, 4, 8]
    @test !hasfield(T.toml_datum_t, :_data)
    @test !hasfield(T.toml_result_t, :_data)
    # toml_result_t: ok@0, toptab@8, errmsg@48, __internal@248
    @test fieldoffset(T.toml_result_t, findfirst(==(:toptab), fieldnames(T.toml_result_t))) == 8
    @test fieldoffset(T.toml_result_t, findfirst(==(:errmsg), fieldnames(T.toml_result_t))) == 48

    # The union region carries the C alignment (8), not NTuple{N,UInt8}'s 1 —
    # an align-1 stand-in would shift `u` and everything after it.
    @test Base.datatype_alignment(T.toml_datum_t_u) == 8

    # Re-derive from behaviour: parse a doc whose values we know, and check
    # each accessor lands on the right thing.
    withtoml("""i = 7\nf = 1.5\nb = true\ns = "abc"\n""") do top
        @test dtype(top) == T.TOML_TABLE
        @test dtabsize(top) == 4
        @test dint(T.toml_get(top, "i")) == 7
        @test dfp(T.toml_get(top, "f")) == 1.5
        @test dbool(T.toml_get(top, "b"))
        @test dstr(T.toml_get(top, "s")) == "abc"
        @test dstrlen(T.toml_get(top, "s")) == 3
    end
end

@testset "Tier-1 surface is empty here, and consistently so" begin
    # tomlc17 legitimately gets NO Tier-1 slices, and that is the correct
    # outcome rather than a build failure: nearly every entry point returns
    # toml_datum_t / toml_result_t BY VALUE, which the shape gate keeps on
    # Tier 3, and the one remaining candidate was Bool-shaped (Julia passes
    # Bool across llvmcall as i8, clang emits C _Bool as i1) so it demotes too.
    # What matters is that the surface and the files on disk AGREE — a
    # non-empty TIER1_FUNCTIONS with no .ll files, or the reverse, is the
    # drift this asserts against.
    slices_dir = joinpath(PKG_DIR, "julia", "slices")
    lls = isdir(slices_dir) ? filter(f -> endswith(f, ".ll"), readdir(slices_dir)) : String[]
    @test length(lls) == length(T.TIER1_FUNCTIONS)
    @test isempty(T.TIER1_FUNCTIONS)
    @test !occursin("@generated function _TIER1_", read(WRAPPER, String))
    for f in lls
        @test occursin("define", read(joinpath(slices_dir, f), String))
    end
end

@testset "Scalar types" begin
    withtoml(DOC) do top
        @test dtype(top) == T.TOML_TABLE

        s = T.toml_get(top, "title")
        @test dtype(s) == T.TOML_STRING
        @test dstr(s) == "tomlc17 deep test"

        i = T.toml_get(top, "answer")
        @test dtype(i) == T.TOML_INT64
        @test dint(i) == 42

        f = T.toml_get(top, "ratio")
        @test dtype(f) == T.TOML_FP64
        @test dfp(f) == 3.5

        @test dtype(T.toml_get(top, "enabled")) == T.TOML_BOOLEAN
        @test dbool(T.toml_get(top, "enabled"))
        @test !dbool(T.toml_get(top, "disabled"))

        # A missing key is TOML_UNKNOWN, not an error or a crash.
        miss = T.toml_get(top, "nope")
        @test dtype(miss) == T.TOML_UNKNOWN
    end
end

@testset "Strings: literal, multiline, escapes, unicode" begin
    withtoml(DOC) do top
        # Literal strings keep backslashes verbatim.
        @test dstr(T.toml_get(top, "literal")) == "C:\\path\\no\\escapes"
        # A multiline basic string trims the leading newline.
        @test dstr(T.toml_get(top, "multi")) == "line one\nline two"
    end

    withtoml("""esc = "tab\\there\\nnew"\nuni = "\\u00e9\\U0001F600"\n""") do top
        @test dstr(T.toml_get(top, "esc")) == "tab\there\nnew"
        @test dstr(T.toml_get(top, "uni")) == "é😀"
    end

    # Strings may carry embedded NULs; str.len is the authority, not strlen.
    withtoml("""s = "a\\u0000b"\n""") do top
        d = T.toml_get(top, "s")
        @test dstrlen(d) == 3
        ptr = dstrptr(d)
        @test unsafe_load(ptr, 2) == 0x00
        @test unsafe_load(ptr, 3) == UInt8('b')
    end
end

@testset "Numbers" begin
    withtoml("""
    dec = 1_000_000
    hex = 0xDEADBEEF
    oct = 0o755
    bin = 0b1010
    neg = -17
    pos = +99
    big = 9223372036854775807
    small = -9223372036854775808
    e = 1e3
    ne = -2.5e-2
    inf = inf
    ninf = -inf
    nan = nan
    """) do top
        @test dint(T.toml_get(top, "dec")) == 1_000_000
        @test dint(T.toml_get(top, "hex")) == 0xDEADBEEF
        @test dint(T.toml_get(top, "oct")) == 0o755
        @test dint(T.toml_get(top, "bin")) == 0b1010
        @test dint(T.toml_get(top, "neg")) == -17
        @test dint(T.toml_get(top, "pos")) == 99
        @test dint(T.toml_get(top, "big")) == typemax(Int64)
        @test dint(T.toml_get(top, "small")) == typemin(Int64)
        @test dfp(T.toml_get(top, "e")) == 1000.0
        @test dfp(T.toml_get(top, "ne")) ≈ -0.025
        @test isinf(dfp(T.toml_get(top, "inf"))) && dfp(T.toml_get(top, "inf")) > 0
        @test isinf(dfp(T.toml_get(top, "ninf"))) && dfp(T.toml_get(top, "ninf")) < 0
        @test isnan(dfp(T.toml_get(top, "nan")))
    end
end

@testset "Dates and times" begin
    withtoml(DOC) do top
        dt = dts(T.toml_get(top, "when"))
        @test dtype(T.toml_get(top, "when")) == T.TOML_DATETIMETZ
        @test dt.year == 1979
        @test dt.month == 5
        @test dt.day == 27
        @test dt.hour == 7
        @test dt.minute == 32
        @test dt.second == 0
        @test dt.tz == 0              # tz offset in minutes (Z)

        d = T.toml_get(top, "plainday")
        @test dtype(d) == T.TOML_DATE
        @test (dts(d).year, dts(d).month, dts(d).day) == (1979, 5, 27)

        t = T.toml_get(top, "plaintime")
        @test dtype(t) == T.TOML_TIME
        @test (dts(t).hour, dts(t).minute, dts(t).second) == (7, 32, 10)
    end

    # A non-zero timezone offset must survive as minutes.
    withtoml("x = 2024-01-02T03:04:05+05:30\n") do top
        x = T.toml_get(top, "x")
        @test dtype(x) == T.TOML_DATETIMETZ
        @test dts(x).tz == 330        # 5h30m
    end
end

@testset "Arrays" begin
    withtoml(DOC) do top
        ns = T.toml_get(top, "numbers")
        @test dtype(ns) == T.TOML_ARRAY
        @test darrsize(ns) == 3
        @test [dint(arrat(ns, i)) for i in 0:2] == [1, 2, 3]

        ss = T.toml_get(top, "mixedish")
        @test darrsize(ss) == 2
        @test dstr(arrat(ss, 0)) == "a"

        nested = T.toml_get(top, "nested")
        @test dtype(nested) == T.TOML_ARRAY
        @test darrsize(nested) == 2
        inner = arrat(nested, 0)
        @test dtype(inner) == T.TOML_ARRAY
        @test darrsize(inner) == 2
        @test dint(arrat(inner, 1)) == 2
        @test darrsize(arrat(nested, 1)) == 1
    end

    withtoml("empty = []\n") do top
        e = T.toml_get(top, "empty")
        @test dtype(e) == T.TOML_ARRAY
        @test darrsize(e) == 0
    end
end

@testset "Tables, dotted keys, arrays of tables" begin
    withtoml(DOC) do top
        owner = T.toml_get(top, "owner")
        @test dtype(owner) == T.TOML_TABLE
        @test dstr(T.toml_get(owner, "name")) == "john"

        addr = T.toml_get(owner, "address")
        @test dtype(addr) == T.TOML_TABLE
        @test dstr(T.toml_get(addr, "city")) == "somewhere"

        # Dotted keys build real nested tables.
        dotted = T.toml_get(top, "dotted")
        a = T.toml_get(dotted, "a")
        b = T.toml_get(a, "b")
        @test dstr(T.toml_get(b, "c")) == "deep"

        # [[products]] is an array of tables.
        prods = T.toml_get(top, "products")
        @test dtype(prods) == T.TOML_ARRAY
        @test darrsize(prods) == 2
        p0 = arrat(prods, 0)
        @test dtype(p0) == T.TOML_TABLE
        @test dstr(T.toml_get(p0, "name")) == "hammer"
        @test dint(T.toml_get(p0, "sku")) == 738594937
        @test dstr(T.toml_get(arrat(prods, 1), "name")) == "nail"

        # Walking a table by index must agree with lookup by key.
        n = dtabsize(owner)
        @test n == 2
        keys = [tabkeyat(owner, i) for i in 0:(n - 1)]
        @test "name" in keys && "address" in keys
        for i in 0:(n - 1)
            byidx = tabat(owner, i)
            bykey = T.toml_get(owner, keys[i + 1])
            @test dtype(byidx) == dtype(bykey)
        end
    end
end

@testset "toml_seek navigates multipart keys" begin
    withtoml(DOC) do top
        @test dstr(T.toml_seek(top, "owner.name")) == "john"
        @test dstr(T.toml_seek(top, "owner.address.city")) == "somewhere"
        @test dstr(T.toml_seek(top, "dotted.a.b.c")) == "deep"
        @test dint(T.toml_seek(top, "answer")) == 42

        # toml_seek walks TABLES only — the documented contract is a
        # dot-separated key path, with no array-index syntax. A numeric part is
        # just a key that isn't there, so arrays must be indexed by hand.
        @test dtype(T.toml_seek(top, "products.0.name")) == T.TOML_UNKNOWN
        prods = T.toml_seek(top, "products")
        @test dtype(prods) == T.TOML_ARRAY
        @test dstr(T.toml_get(arrat(prods, 0), "name")) == "hammer"
        @test dstr(T.toml_get(arrat(prods, 1), "name")) == "nail"

        # Misses are TOML_UNKNOWN, at every depth.
        @test dtype(T.toml_seek(top, "owner.missing")) == T.TOML_UNKNOWN
        @test dtype(T.toml_seek(top, "no.such.path")) == T.TOML_UNKNOWN
    end
end

@testset "Errors on malformed documents" begin
    for bad in ["x = ", "= 1", "[unclosed", "x = \"unterminated",
                "x = 01", "[a]\n[a]\n", "x = 1\nx = 2\n", "x = [1, 2",
                "x = 1979-13-45", "x = tru"]
        r = T.toml_parse(bad, sizeof(bad))
        @test !rok(r)
        msg = rerr(r)
        @test !isempty(msg)              # every failure carries a message
        T.toml_free(r)
    end

    # An empty document is VALID and yields an empty top table.
    r = T.toml_parse("", 0)
    @test rok(r)
    @test dtabsize(rtoptab(r)) == 0
    T.toml_free(r)

    # Comments and blank lines only: still valid, still empty.
    src = "# just a comment\n\n   \n"
    r2 = T.toml_parse(src, sizeof(src))
    @test rok(r2)
    @test dtabsize(rtoptab(r2)) == 0
    T.toml_free(r2)
end

@testset "toml_equiv and toml_merge" begin
    a = "x = 1\n[t]\ny = 2\n"
    b = "x = 1\n[t]\ny = 2\n"
    c = "x = 2\n[t]\ny = 2\n"

    ra = T.toml_parse(a, sizeof(a))
    rb = T.toml_parse(b, sizeof(b))
    rc = T.toml_parse(c, sizeof(c))
    @test rok(ra) && rok(rb) && rok(rc)

    # Identical documents are equivalent; a changed value is not.
    @test T.toml_equiv(Ref(ra), Ref(rb))
    @test !T.toml_equiv(Ref(ra), Ref(rc))

    # Upstream is explicit that "dictionary and array orders are sensitive",
    # so the same key/value set written in a different order is NOT equivalent.
    reordered = "[t]\ny = 2\n\nx = 1\n"
    rr = T.toml_parse(reordered, sizeof(reordered))
    @test rok(rr)
    @test !T.toml_equiv(Ref(ra), Ref(rr))
    T.toml_free(rr)

    T.toml_free(rc); T.toml_free(rb); T.toml_free(ra)
end

@testset "Result ownership and churn" begin
    # Every successful parse owns heap memory reachable only through
    # __internal; freeing must be safe and repeatable across many cycles.
    for i in 1:3000
        r = T.toml_parse(DOC, sizeof(DOC))
        @assert rok(r)
        top = rtoptab(r)
        @assert dint(T.toml_get(top, "answer")) == 42
        @assert dstr(T.toml_seek(top, "owner.address.city")) == "somewhere"
        T.toml_free(r)
        iszero(i % 500) && GC.gc()
    end
    @test true

    # Interleave failures so the error path's allocations churn too.
    for i in 1:2000
        bad = "x = [$i, "
        r = T.toml_parse(bad, sizeof(bad))
        @assert !rok(r)
        @assert !isempty(rerr(r))
        T.toml_free(r)
        good = "n = $i\n"
        r2 = T.toml_parse(good, sizeof(good))
        @assert rok(r2)
        @assert dint(T.toml_get(rtoptab(r2), "n")) == i
        T.toml_free(r2)
    end
    @test true

    # Freeing a failed result must also be safe (no toptab to walk).
    r = T.toml_parse("nope", 4)
    @test !rok(r)
    T.toml_free(r)
    @test true
end

end  # top-level testset
