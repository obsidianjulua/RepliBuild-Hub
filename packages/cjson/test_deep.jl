#!/usr/bin/env julia
# cJSON Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
# cJSON is the package where mixed-tier dispatch was first caught diverging on
# file-local state, so the canary gets top billing here:
#   - cJSON_Parse is Tier 1 (sliced llvmcall); cJSON_GetErrorPtr is Tier 3
#     (Cstring return can never be Tier 1). They read the SAME `static
#     global_error`, which static promotion now exports as one symbol. If the
#     two tiers ever saw separate copies again, the error-position tests below
#     go silently NULL — exactly the 2026-07-11 failure.
#   - full parse/print roundtrips, numbers, escapes, deep nesting
#   - tree mutation: add/insert/replace/detach/delete, references vs copies
#   - ownership: owned char* returns are copied and freed, references are not
#   - cJSON-Utils: JSON Pointer, patches, merge-patch, sort
#   - churn under GC pressure
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/cjson/test_deep.jl

using Test
using InteractiveUtils: code_typed

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Cjson.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const C = Cjson

# Parse, run `f` on the tree, always delete. Returns f's value.
function withjson(f, text::AbstractString)
    root = C.cJSON_Parse(text)
    root == C_NULL && error("parse failed: $(C.cJSON_GetErrorPtr())")
    try
        return f(root)
    finally
        C.cJSON_Delete(root)
    end
end

item(ptr) = unsafe_load(Ptr{C.cJSON}(ptr))
numval(ptr) = C.cJSON_GetNumberValue(ptr)
strval(ptr) = unsafe_string(item(ptr).valuestring)

@testset "cJSON Deep Tests" begin

@testset "Library identity" begin
    @test C.cJSON_Version() == "1.7.18"
end

@testset "Tier 1 is OFF — pure ccall" begin
    # WAS "Tier-1 slicing is live". cjson was the Hub's Tier-1 exerciser — 84
    # @generated kernels over 84 shipped slices — until 2026-08-22, when Tier 1
    # was unbolted from this package (`[wrap.tier1] enable = false`).
    #
    # INVERTED rather than deleted: this is the same guard pointed the other
    # way, and it fails loudly if slicing is ever switched back on here by
    # accident. A deleted testset would just go quiet.
    # The Tier-1 SURFACE is gated out entirely, not merely emptied. Before the
    # gate (2026-08-22) a tier1-off wrapper still defined an empty
    # `TIER1_FUNCTIONS`, an empty `TIER1_DECLARES`, an empty `_TIER1_KERNEL` and
    # an unreachable `_slice_symbols_resolve` — ~50 lines of llvmcall machinery
    # in a wrapper with no llvmcall. These names must now be ABSENT.
    for n in (:TIER1_FUNCTIONS, :TIER1_DECLARES, :_TIER1_KERNEL, :_slice_symbols_resolve)
        @test !isdefined(C, n)
    end

    # A tier1-off wrap CLEARS the stale slices dir rather than shipping orphans.
    @test !isdir(joinpath(PKG_DIR, "julia", "slices"))

    # The kernels are gone from the source entirely — they do not merely demote
    # at call time, which is the weaker property `dispatch_tier` alone proves.
    src = read(WRAPPER, String)
    @test !occursin("@generated function _TIER1_", src)
    @test !occursin("const _SLICE_", src)
    @test !occursin("llvmcall", src)
    # …and the runtime probe goes with them: with nothing to demote,
    # `dispatch_tier` is a plain table lookup, so no `code_typed` and no
    # `:deferred` output-mode refusal.
    @test !occursin("code_typed", src)
    @test !occursin(":deferred", src)

    # The dispatch table is gated too. With slicing off, C has no Tier-2 path at
    # all, so every function is necessarily Tier 3 — `DISPATCH_TIER` was 100 rows
    # of `=> :tier3` and `dispatch_tier` a lookup that could return only `:tier3`
    # or `:unknown`. One fact repeated once per function. The generator now emits
    # a sentence instead, keyed on the table being UNIFORM rather than on the
    # language (C++ keeps its table, where a tier2/tier3 mix is real).
    @test !isdefined(C, :DISPATCH_TIER)
    @test !isdefined(C, :dispatch_tier)
    @test occursin("Every function in this module dispatches through Tier 3", src)

    # Static promotion is a BUILD-stage pass on a DIFFERENT knob
    # (`[link] promote_statics`), so it still runs with slicing off and
    # global_error is still a single promoted symbol. Pinned deliberately:
    # "slicing off" and "promotion off" are separate, and only one moved here.
    promoted = joinpath(PKG_DIR, "build", "promoted_symbols.json")
    @test isfile(promoted)
    @test occursin("global_error", read(promoted, String))
end

@testset "THE CANARY — parse writes global_error, error read sees it" begin
    # HISTORY, and why this testset exists at all: cJSON_Parse writes the failure
    # position into `static global_error`, and cJSON_GetErrorPtr reads it. Under
    # whole-module Tier-1 embedding those were two DIFFERENT objects — the
    # llvmcall'd parse wrote the embedded module's copy while the ccall'd reader
    # saw the .so's — and every assertion below came back NULL/empty. That is the
    # cJSON divergence class this package is named for in the devlog.
    #
    # Since 2026-08-22 both sides are Tier 3, so the split cannot occur by
    # construction and these assertions are no longer load-bearing for tier
    # coherence. KEPT because they still verify real behaviour (a failed parse
    # leaves a readable error position), and because they are the regression net
    # if slicing is ever switched back on here.
    # NOTE: cJSON_Parse is deliberately lenient about trailing content
    # (require_null_terminated = 0), so every entry here has to be malformed
    # within the value itself, not merely followed by junk.
    for (bad, marker) in [("{\"a\":}",        "}"),
                          ("[1,2,",           ""),
                          ("{\"unterminated", ""),
                          ("tru",             ""),
                          ("[1,2,3",          "")]
        @test C.cJSON_Parse(bad) == C_NULL
        err = C.cJSON_GetErrorPtr()
        @test err !== nothing                       # the read reached the write
        @test err === nothing || isempty(marker) || startswith(err, marker)
    end

    # The error pointer points INTO the caller's buffer, so its tail identifies
    # the exact failure offset — a much stronger claim than "non-NULL".
    src = "{\"ok\":1, \"bad\":@}"
    @test C.cJSON_Parse(src) == C_NULL
    @test C.cJSON_GetErrorPtr() == "@}"

    # A successful parse must CLEAR the error state, again across the tiers.
    ok = C.cJSON_Parse("{\"a\":1}")
    @test ok != C_NULL
    @test C.cJSON_GetErrorPtr() in (nothing, "")
    C.cJSON_Delete(ok)

    # Alternating good/bad parses many times: a stale copy would desynchronize.
    for i in 1:200
        good = C.cJSON_Parse("[$i]")
        @test good != C_NULL
        C.cJSON_Delete(good)
        @test C.cJSON_Parse("[$i,") == C_NULL
        @test C.cJSON_GetErrorPtr() !== nothing
    end
end

@testset "Parse / print roundtrip" begin
    src = """{"name":"cjson","n":42,"pi":3.5,"ok":true,"nil":null,"xs":[1,2,3]}"""
    withjson(src) do root
        @test C.cJSON_IsObject(root) != 0
        out = C.cJSON_PrintUnformatted(root)
        @test out !== nothing
        # Re-parsing the printed form must give an equal tree (cJSON_Compare is
        # the library's own structural equality — an independent check of print).
        reparsed = C.cJSON_Parse(out)
        @test reparsed != C_NULL
        @test C.cJSON_Compare(root, reparsed, 1) == 1
        C.cJSON_Delete(reparsed)

        # Formatted print differs textually but not structurally.
        pretty = C.cJSON_Print(root)
        @test occursin("\n", pretty)
        @test !occursin("\n", out)
        p2 = C.cJSON_Parse(pretty)
        @test C.cJSON_Compare(root, p2, 1) == 1
        C.cJSON_Delete(p2)
    end
end

@testset "Type predicates and accessors" begin
    withjson("""{"s":"str","i":7,"f":1.5,"t":true,"f2":false,"n":null,"a":[],"o":{}}""") do root
        g(k) = C.cJSON_GetObjectItemCaseSensitive(root, k)
        @test C.cJSON_IsString(g("s")) != 0
        @test strval(g("s")) == "str"
        @test C.cJSON_IsNumber(g("i")) != 0
        @test numval(g("i")) == 7.0
        @test item(g("i")).valueint == 7
        @test numval(g("f")) == 1.5
        @test C.cJSON_IsTrue(g("t")) != 0
        @test C.cJSON_IsBool(g("t")) != 0
        @test C.cJSON_IsFalse(g("f2")) != 0
        @test C.cJSON_IsBool(g("f2")) != 0
        @test C.cJSON_IsNull(g("n")) != 0
        @test C.cJSON_IsArray(g("a")) != 0
        @test C.cJSON_IsObject(g("o")) != 0

        # Case sensitivity really differs between the two lookups.
        @test C.cJSON_GetObjectItem(root, "S") != C_NULL
        @test C.cJSON_GetObjectItemCaseSensitive(root, "S") == C_NULL
        @test C.cJSON_HasObjectItem(root, "s") != 0
        @test C.cJSON_HasObjectItem(root, "nope") == 0

        # A missing item is NULL, and predicates on NULL are false, not a crash.
        @test C.cJSON_GetObjectItemCaseSensitive(root, "missing") == C_NULL
        @test C.cJSON_IsString(C_NULL) == 0
        @test C.cJSON_IsInvalid(C_NULL) == 0
    end
end

@testset "Numbers, escapes, unicode" begin
    withjson("""{"neg":-17,"exp":1e3,"frac":-2.25e-2,"zero":0,"big":1e300}""") do root
        g(k) = C.cJSON_GetObjectItemCaseSensitive(root, k)
        @test numval(g("neg")) == -17.0
        @test numval(g("exp")) == 1000.0
        @test numval(g("frac")) ≈ -0.0225
        @test numval(g("zero")) == 0.0
        @test numval(g("big")) == 1e300
        # valueint saturates to INT_MAX for out-of-range doubles (documented).
        @test item(g("big")).valueint == typemax(Cint)
    end

    # Escape sequences must survive parse and re-print.
    withjson("""{"e":"a\\"b\\\\c\\/d\\ne\\tf"}""") do root
        s = strval(C.cJSON_GetObjectItemCaseSensitive(root, "e"))
        @test s == "a\"b\\c/d\ne\tf"
        out = C.cJSON_PrintUnformatted(root)
        again = C.cJSON_Parse(out)
        @test strval(C.cJSON_GetObjectItemCaseSensitive(again, "e")) == s
        C.cJSON_Delete(again)
    end

    # \\u escapes, including a surrogate pair, decode to UTF-8.
    withjson("""{"u":"\\u00e9\\u4e2d\\ud83d\\ude00"}""") do root
        s = strval(C.cJSON_GetObjectItemCaseSensitive(root, "u"))
        @test s == "é中😀"
        @test length(s) == 3
    end

    # Raw UTF-8 in, raw UTF-8 out.
    withjson("""{"k":"naïve — 日本語"}""") do root
        @test strval(C.cJSON_GetObjectItemCaseSensitive(root, "k")) == "naïve — 日本語"
    end
end

@testset "Arrays" begin
    withjson("[10,20,30,40]") do root
        @test C.cJSON_GetArraySize(root) == 4
        @test numval(C.cJSON_GetArrayItem(root, 0)) == 10.0
        @test numval(C.cJSON_GetArrayItem(root, 3)) == 40.0
        @test C.cJSON_GetArrayItem(root, 4) == C_NULL
        @test C.cJSON_GetArrayItem(root, -1) == C_NULL

        # Walk the sibling chain by hand — the struct layout must be right.
        vals = Float64[]
        cur = item(root).child
        while cur != C_NULL
            push!(vals, numval(cur))
            cur = item(cur).next
        end
        @test vals == [10.0, 20.0, 30.0, 40.0]

        # ...and backwards via prev from the last element.
        last = C.cJSON_GetArrayItem(root, 3)
        back = Float64[]
        cur = last
        while cur != C_NULL
            push!(back, numval(cur))
            cur = item(cur).prev
            cur == last && break        # cJSON's child->prev points at the tail
        end
        @test back == [40.0, 30.0, 20.0, 10.0]
    end

    # Typed array constructors.
    ints = Cint[1, 2, 3]
    a = C.cJSON_CreateIntArray(ints, 3)
    @test C.cJSON_GetArraySize(a) == 3
    @test numval(C.cJSON_GetArrayItem(a, 2)) == 3.0
    C.cJSON_Delete(a)

    ds = [1.5, 2.5]
    d = C.cJSON_CreateDoubleArray(ds, 2)
    @test numval(C.cJSON_GetArrayItem(d, 1)) == 2.5
    C.cJSON_Delete(d)

    fs = Cfloat[0.5, 0.25]
    f = C.cJSON_CreateFloatArray(fs, 2)
    @test numval(C.cJSON_GetArrayItem(f, 0)) == 0.5
    C.cJSON_Delete(f)
end

@testset "Tree mutation" begin
    root = C.cJSON_CreateObject()
    @test root != C_NULL

    @test C.cJSON_AddStringToObject(root, "s", "hello") != C_NULL
    @test C.cJSON_AddNumberToObject(root, "n", 3.25) != C_NULL
    @test C.cJSON_AddTrueToObject(root, "t") != C_NULL
    @test C.cJSON_AddFalseToObject(root, "f") != C_NULL
    @test C.cJSON_AddNullToObject(root, "z") != C_NULL
    @test C.cJSON_AddBoolToObject(root, "b", 1) != C_NULL
    arr = C.cJSON_AddArrayToObject(root, "a")
    obj = C.cJSON_AddObjectToObject(root, "o")
    @test arr != C_NULL && obj != C_NULL

    for v in 1:3
        @test C.cJSON_AddItemToArray(arr, C.cJSON_CreateNumber(v)) == 1
    end
    @test C.cJSON_GetArraySize(arr) == 3

    # Insert shifts, replace substitutes in place.
    @test C.cJSON_InsertItemInArray(arr, 1, C.cJSON_CreateNumber(99)) == 1
    @test numval(C.cJSON_GetArrayItem(arr, 1)) == 99.0
    @test C.cJSON_GetArraySize(arr) == 4
    @test C.cJSON_ReplaceItemInArray(arr, 0, C.cJSON_CreateNumber(-1)) == 1
    @test numval(C.cJSON_GetArrayItem(arr, 0)) == -1.0
    @test C.cJSON_GetArraySize(arr) == 4

    # Detach hands ownership back to us; the tree shrinks and we must free it.
    det = C.cJSON_DetachItemFromArray(arr, 1)
    @test det != C_NULL
    @test numval(det) == 99.0
    @test C.cJSON_GetArraySize(arr) == 3
    C.cJSON_Delete(det)

    # Delete frees in place.
    C.cJSON_DeleteItemFromArray(arr, 0)
    @test C.cJSON_GetArraySize(arr) == 2

    @test C.cJSON_ReplaceItemInObjectCaseSensitive(root, "s", C.cJSON_CreateString("bye")) == 1
    @test strval(C.cJSON_GetObjectItemCaseSensitive(root, "s")) == "bye"
    C.cJSON_DeleteItemFromObjectCaseSensitive(root, "z")
    @test C.cJSON_GetObjectItemCaseSensitive(root, "z") == C_NULL

    # DetachItemViaPointer with the item we already hold.
    n = C.cJSON_GetObjectItemCaseSensitive(root, "n")
    dp = C.cJSON_DetachItemViaPointer(root, n)
    @test dp == n
    @test C.cJSON_GetObjectItemCaseSensitive(root, "n") == C_NULL
    C.cJSON_Delete(dp)

    C.cJSON_Delete(root)
end

@testset "References do not own their target" begin
    # A reference item shares the referenced subtree; deleting the referencing
    # container must NOT free it. A double free here would abort the process.
    owner = C.cJSON_CreateObject()
    shared = C.cJSON_CreateString("shared value")
    C.cJSON_AddItemToObject(owner, "orig", shared)

    holder = C.cJSON_CreateArray()
    @test C.cJSON_AddItemReferenceToArray(holder, shared) == 1
    @test C.cJSON_GetArraySize(holder) == 1
    C.cJSON_Delete(holder)                     # must not touch `shared`

    @test strval(C.cJSON_GetObjectItemCaseSensitive(owner, "orig")) == "shared value"

    holder2 = C.cJSON_CreateObject()
    @test C.cJSON_AddItemReferenceToObject(holder2, "ref", shared) == 1
    C.cJSON_Delete(holder2)
    @test strval(C.cJSON_GetObjectItemCaseSensitive(owner, "orig")) == "shared value"

    C.cJSON_Delete(owner)

    # CreateStringReference borrows a caller-owned buffer.
    text = "borrowed"
    GC.@preserve text begin
        r = C.cJSON_CreateStringReference(pointer(text))
        @test C.cJSON_IsString(r) != 0
        @test strval(r) == "borrowed"
        C.cJSON_Delete(r)
    end
    @test text == "borrowed"
end

@testset "Duplicate and Compare" begin
    src = """{"a":[1,{"b":"c"}],"d":null,"e":1.5}"""
    withjson(src) do root
        deep = C.cJSON_Duplicate(root, 1)
        @test deep != C_NULL && deep != root
        @test C.cJSON_Compare(root, deep, 1) == 1

        # Mutating the copy must not touch the original.
        C.cJSON_AddNumberToObject(deep, "extra", 1)
        @test C.cJSON_Compare(root, deep, 1) == 0
        @test C.cJSON_GetObjectItemCaseSensitive(root, "extra") == C_NULL
        C.cJSON_Delete(deep)

        # Shallow duplicate drops the children.
        shallow = C.cJSON_Duplicate(root, 0)
        @test shallow != C_NULL
        @test item(shallow).child == C_NULL
        C.cJSON_Delete(shallow)

        # Compare is case-sensitivity aware on keys.
        upper = C.cJSON_Parse("""{"A":[1,{"b":"c"}],"d":null,"e":1.5}""")
        @test C.cJSON_Compare(root, upper, 1) == 0
        @test C.cJSON_Compare(root, upper, 0) == 1
        C.cJSON_Delete(upper)
    end
end

@testset "ParseWithLength / ParseWithOpts" begin
    # A buffer that is NOT NUL-terminated: only the length-aware entry point is
    # safe, and it must stop exactly at the given length.
    raw = collect(codeunits("[1,2,3]GARBAGE"))
    GC.@preserve raw begin
        t = C.cJSON_ParseWithLength(pointer(raw), 7)
        @test t != C_NULL
        @test C.cJSON_GetArraySize(t) == 3
        C.cJSON_Delete(t)

        # Handing it the whole buffer still SUCCEEDS: like cJSON_Parse, the
        # length-aware entry point stops at the end of the first value and
        # ignores the rest unless require_null_terminated is set.
        t2 = C.cJSON_ParseWithLength(pointer(raw), length(raw))
        @test t2 != C_NULL
        @test C.cJSON_GetArraySize(t2) == 3
        C.cJSON_Delete(t2)

        # With require_null_terminated the trailing garbage is fatal.
        @test C.cJSON_ParseWithLengthOpts(pointer(raw), length(raw), C_NULL, 1) == C_NULL
    end

    # require_null_terminated rejects trailing content.
    @test C.cJSON_ParseWithOpts("[1] trailing", C_NULL, 1) == C_NULL
    ok = C.cJSON_ParseWithOpts("[1] trailing", C_NULL, 0)
    @test ok != C_NULL
    C.cJSON_Delete(ok)

    # return_parse_end reports where parsing stopped.
    endp = Ref{Ptr{UInt8}}(C_NULL)
    doc = "[1,2]   rest"
    GC.@preserve doc begin
        t = C.cJSON_ParseWithOpts(doc, endp, 0)
        @test t != C_NULL
        @test endp[] != C_NULL
        @test unsafe_string(endp[]) == "   rest"
        C.cJSON_Delete(t)
    end
end

@testset "PrintPreallocated" begin
    withjson("""{"a":[1,2,3],"b":"xyz"}""") do root
        want = C.cJSON_PrintUnformatted(root)
        # cJSON's preallocated printer works against a CONSERVATIVE size
        # estimate, not the exact output length: an exactly-fitting buffer
        # (len+1 for the NUL) is rejected and leaves the text truncated. Give it
        # headroom, as upstream's own docs advise.
        buf = Vector{UInt8}(undef, length(want) + 64)
        @test C.cJSON_PrintPreallocated(root, buf, length(buf), 0) == 1
        @test unsafe_string(pointer(buf)) == want

        # The exact-fit case is the documented rejection, not a silent overflow.
        tight = Vector{UInt8}(undef, length(want) + 1)
        @test C.cJSON_PrintPreallocated(root, tight, length(tight), 0) == 0

        # An undersized buffer must fail rather than overflow.
        small = Vector{UInt8}(undef, 4)
        @test C.cJSON_PrintPreallocated(root, small, length(small), 0) == 0

        # PrintBuffered with a hint produces the same text.
        @test C.cJSON_PrintBuffered(root, 256, 0) == want
    end
end

@testset "Minify" begin
    # Minify rewrites the buffer IN PLACE, so it needs a mutable NUL-terminated
    # copy — a Julia String literal would be read-only.
    src = """
    {
        "a" : [1, 2],   // line comment
        /* block */
        "b" : "keep  spaces"
    }
    """
    buf = push!(collect(codeunits(src)), 0x00)
    GC.@preserve buf begin
        C.cJSON_Minify(pointer(buf))
        out = unsafe_string(pointer(buf))
        @test !occursin("//", out)
        @test !occursin("/*", out)
        @test !occursin("\n", out)
        @test occursin("keep  spaces", out)     # inside a string: untouched
        t = C.cJSON_Parse(out)
        @test t != C_NULL
        @test C.cJSON_GetArraySize(C.cJSON_GetObjectItemCaseSensitive(t, "a")) == 2
        C.cJSON_Delete(t)
    end
end

@testset "cJSON-Utils: pointers, patches, sort" begin
    doc = """{"foo":{"bar":[10,20,30]},"a/b":1,"m~n":2}"""
    withjson(doc) do root
        # JSON Pointer (RFC 6901), including the ~1 and ~0 escapes.
        @test numval(C.cJSONUtils_GetPointer(root, "/foo/bar/1")) == 20.0
        @test numval(C.cJSONUtils_GetPointerCaseSensitive(root, "/foo/bar/2")) == 30.0
        @test numval(C.cJSONUtils_GetPointer(root, "/a~1b")) == 1.0
        @test numval(C.cJSONUtils_GetPointer(root, "/m~0n")) == 2.0
        @test C.cJSONUtils_GetPointer(root, "/nope") == C_NULL
        @test C.cJSONUtils_GetPointer(root, "") == root

        # Reverse lookup returns an OWNED string (fixed via [wrap.cstring_owned]).
        target = C.cJSONUtils_GetPointer(root, "/foo/bar/1")
        @test C.cJSONUtils_FindPointerFromObjectTo(root, target) == "/foo/bar/1"
        @test C.cJSONUtils_FindPointerFromObjectTo(root, root) == ""
    end

    # GeneratePatches + ApplyPatches must round-trip one document into another.
    from = C.cJSON_Parse("""{"a":1,"b":{"c":2},"d":[1,2,3]}""")
    to   = C.cJSON_Parse("""{"a":9,"b":{"c":2,"e":5},"d":[1,3]}""")
    patches = C.cJSONUtils_GeneratePatchesCaseSensitive(from, to)
    @test patches != C_NULL
    @test C.cJSON_GetArraySize(patches) > 0
    @test C.cJSONUtils_ApplyPatchesCaseSensitive(from, patches) == 0
    @test C.cJSON_Compare(from, to, 1) == 1
    C.cJSON_Delete(patches); C.cJSON_Delete(from); C.cJSON_Delete(to)

    # Merge-patch (RFC 7386): null removes a key.
    target = C.cJSON_Parse("""{"a":1,"b":2}""")
    patch  = C.cJSON_Parse("""{"b":null,"c":3}""")
    merged = C.cJSONUtils_MergePatchCaseSensitive(target, patch)
    @test merged != C_NULL
    @test C.cJSON_GetObjectItemCaseSensitive(merged, "b") == C_NULL
    @test numval(C.cJSON_GetObjectItemCaseSensitive(merged, "a")) == 1.0
    @test numval(C.cJSON_GetObjectItemCaseSensitive(merged, "c")) == 3.0
    C.cJSON_Delete(merged); C.cJSON_Delete(patch)

    # GenerateMergePatch is the inverse direction.
    f2 = C.cJSON_Parse("""{"x":1,"y":2}""")
    t2 = C.cJSON_Parse("""{"x":1,"z":3}""")
    mp = C.cJSONUtils_GenerateMergePatchCaseSensitive(f2, t2)
    @test mp != C_NULL
    applied = C.cJSONUtils_MergePatchCaseSensitive(f2, mp)
    @test C.cJSON_Compare(applied, t2, 1) == 1
    C.cJSON_Delete(applied); C.cJSON_Delete(mp); C.cJSON_Delete(t2)

    # SortObject orders keys; walking the child chain must come out sorted.
    s = C.cJSON_Parse("""{"delta":1,"alpha":2,"charlie":3,"bravo":4}""")
    C.cJSONUtils_SortObjectCaseSensitive(s)
    keys = String[]
    cur = item(s).child
    while cur != C_NULL
        push!(keys, unsafe_string(item(cur).string))
        cur = item(cur).next
    end
    @test keys == sort(keys)
    @test keys == ["alpha", "bravo", "charlie", "delta"]
    C.cJSON_Delete(s)
end

@testset "Deep nesting and malformed input" begin
    # cJSON caps nesting depth (CJSON_NESTING_LIMIT, 1000) rather than blowing
    # the C stack — the limit must actually engage.
    ok = C.cJSON_Parse("[" ^ 500 * "]" ^ 500)
    @test ok != C_NULL
    C.cJSON_Delete(ok)
    @test C.cJSON_Parse("[" ^ 5000 * "]" ^ 5000) == C_NULL
    @test C.cJSON_GetErrorPtr() !== nothing

    for bad in ["", "   ", "{", "}", "[", "]", "{\"a\"}", "{\"a\":1,}", "[1,]",
                "\"unterminated", "+1", ".5", "--1", "nul", "{'a':1}"]
        @test C.cJSON_Parse(bad) == C_NULL
    end

    # "01" is NOT in that list. Strict JSON forbids leading zeros, but cJSON's
    # number scanner hands the run to strtod, which happily reads "01" as 1 and
    # consumes both characters — so it parses even under require_null_terminated.
    # Documenting the real behaviour beats asserting the spec's.
    for (text, val) in [("01", 1.0), ("00", 0.0), ("-01", -1.0), ("0123", 123.0)]
        lead = C.cJSON_Parse(text)
        @test lead != C_NULL
        @test numval(lead) == val
        C.cJSON_Delete(lead)
        strict = C.cJSON_ParseWithOpts(text, C_NULL, 1)
        @test strict != C_NULL          # whole buffer consumed
        C.cJSON_Delete(strict)
    end

    # Valid documents that look odd but are legal JSON.
    for good in ["null", "true", "false", "0", "-0", "\"\"", "[]", "{}", "1e-5"]
        t = C.cJSON_Parse(good)
        @test t != C_NULL
        C.cJSON_Delete(t)
    end
end

@testset "Churn and GC stress" begin
    # Build/print/reparse/free in a tight loop with Julia GC interleaved. A slice
    # bound to a stale allocator or a duplicated static shows up as corruption.
    src = """{"k":[1,2,3],"s":"value","n":{"deep":{"deeper":true}}}"""
    for i in 1:2000
        root = C.cJSON_Parse(src)
        @assert root != C_NULL
        txt = C.cJSON_PrintUnformatted(root)
        again = C.cJSON_Parse(txt)
        @assert C.cJSON_Compare(root, again, 1) == 1
        C.cJSON_Delete(again)
        C.cJSON_Delete(root)
        iszero(i % 500) && GC.gc()
    end
    @test true

    # Interleave failing parses so the shared error state is churned too.
    for i in 1:1000
        @assert C.cJSON_Parse("[$i,") == C_NULL
        @assert C.cJSON_GetErrorPtr() !== nothing
        good = C.cJSON_Parse("[$i]")
        @assert good != C_NULL
        C.cJSON_Delete(good)
    end
    @test true
end

end  # top-level testset
