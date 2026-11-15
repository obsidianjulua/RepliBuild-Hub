#!/usr/bin/env julia
# QuickJS Hub package — deep test of the embedding API.
#
# A runtime and context are made, and JavaScript is evaluated through the
# wrapper. Results come back as JSValue: a 16-byte record { JSValueUnion u;
# int64_t tag; } returned BY VALUE from nearly every call. Proves:
#   - ints, doubles and strings cross back correctly, and the tag is read at
#     its DWARF offset;
#   - errors: a syntax error is an exception value, JS_GetException returns it,
#     and its message names the error; strict mode changes behaviour;
#   - JS_Call with a JSValue array argument, and JSValues passed BY VALUE;
#   - a Julia function registered with JS_NewCFunction2 and called from JS
#     (JSValue by value in both directions across a @cfunction);
#   - the header inlines shimmed in [wrap.macros] (JS_FreeValue, JS_IsException,
#     JS_NewInt32, JS_UNDEFINED, the JS_EVAL_* flags);
#   - quickjs-libc's helpers (console, print) are installed;
#   - teardown: JS_FreeRuntime asserts that no GC object leaked (an abort, not
#     an exception), so reaching the end at all proves every value taken was
#     released through the JS_FreeValue shim.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/quickjs/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Quickjs.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)
import .Quickjs as Q

# quickjs.h tags (enum at quickjs.h:78-95)
const TAG_STRING = -7; const TAG_OBJECT = -1; const TAG_INT = 0
const TAG_BOOL = 1; const TAG_UNDEFINED = 3; const TAG_EXCEPTION = 6; const TAG_FLOAT64 = 8
const TAG_FUNCTION_BYTECODE = -2
const BC_VERSION = 5                     # quickjs.c:37388 — bytecode format of this release

const TAG_OFF = Q.member_offset(:JSValue, :tag)          # 8, from DWARF
bytes(v::Q.JSValue) = collect(v._data)
tag(v::Q.JSValue) = reinterpret(Int64, bytes(v)[TAG_OFF+1:TAG_OFF+8])[1]
int32(v::Q.JSValue) = reinterpret(Int32, bytes(v)[1:4])[1]

function jsstring(ctx, v)
    p = Q.JS_ToCStringLen2_ptr(ctx, C_NULL, v, 0)
    p == C_NULL && return nothing
    s = unsafe_string(p)
    # The `_ptr` variant returns a Cstring, but JS_FreeCString(ctx, const char*)
    # is typed Ptr{UInt8}, and Julia has no Cstring → Ptr{UInt8} conversion.
    Q.JS_FreeCString(ctx, Ptr{UInt8}(p))
    return s
end

eval_js(ctx, src; flags = Q.JS_EVAL_TYPE_GLOBAL()) =
    Q.JS_Eval(ctx, src, sizeof(src), "<test>", flags)

# A Julia function JavaScript can call: jl_mul(a, b) = a*b + 1.
function jl_mul(ctx::Ptr{Q.JSContext}, this::Q.JSValue, argc::Cint, argv::Ptr{Q.JSValue})::Q.JSValue
    argc == 2 || return Q.JS_NewInt32(ctx, -1)
    a = Ref{Int32}(0); b = Ref{Int32}(0)
    Q.JS_ToInt32(ctx, a, unsafe_load(argv, 1))
    Q.JS_ToInt32(ctx, b, unsafe_load(argv, 2))
    return Q.JS_NewInt32(ctx, a[] * b[] + Int32(1))
end

# A Julia function that throws a JS RangeError through a varargs overload.
function jl_throw(ctx::Ptr{Q.JSContext}, this::Q.JSValue, argc::Cint, argv::Ptr{Q.JSValue})::Q.JSValue
    return Q.JS_ThrowRangeError_Cint(ctx, "n=%d too big", argc)
end

@testset "QuickJS Deep Tests" begin

@testset "layout and shims" begin
    @test sizeof(Q.JSValue) == 16 == Q.struct_size(:JSValue)
    @test TAG_OFF == 8
    @test Q.JS_EVAL_TYPE_GLOBAL() == 0
    @test Q.JS_EVAL_TYPE_MODULE() == 1
    @test Q.JS_EVAL_FLAG_STRICT() == 8
    @test tag(Q.JS_UNDEFINED()) == TAG_UNDEFINED
end

rt = Q.JS_NewRuntime()
@test rt != C_NULL
ctx = Q.JS_NewContext(rt)
@test ctx != C_NULL

@testset "values come back by value" begin
    v = eval_js(ctx, "1 + 2 * 3")
    @test tag(v) == TAG_INT
    @test int32(v) == 7
    r = Ref{Int32}(0)
    @test Q.JS_ToInt32(ctx, r, v) == 0 && r[] == 7

    d = eval_js(ctx, "Math.sqrt(2)")
    @test tag(d) == TAG_FLOAT64
    f = Ref{Float64}(0)
    Q.JS_ToFloat64(ctx, f, d)
    @test f[] == sqrt(2.0)

    s = eval_js(ctx, "['a','b','c'].map(c => c.toUpperCase()).join('-')")
    @test tag(s) == TAG_STRING
    @test jsstring(ctx, s) == "A-B-C"
    @test jsstring(ctx, eval_js(ctx, "'héllo ' + 'wörld'")) == "héllo wörld"   # UTF-8 both ways

    b = eval_js(ctx, "[1,2,3].includes(2)")
    @test tag(b) == TAG_BOOL && int32(b) == 1
    Q.JS_FreeValue(ctx, s)          # the only refcounted one of these
end

@testset "JSON round trip" begin
    j = eval_js(ctx, "JSON.stringify({a: [1, 2, {b: 'c'}], n: null})")
    @test jsstring(ctx, j) == """{"a":[1,2,{"b":"c"}],"n":null}"""
    Q.JS_FreeValue(ctx, j)
    src = """{"x": 41}"""
    o = Q.JS_ParseJSON(ctx, src, sizeof(src), "<json>")
    @test tag(o) == TAG_OBJECT
    x = Q.JS_GetPropertyStr(ctx, o, "x")
    @test int32(x) == 41
    Q.JS_FreeValue(ctx, o)
end

@testset "errors are exception values" begin
    e = eval_js(ctx, "1 +")
    @test tag(e) == TAG_EXCEPTION
    @test Q.JS_IsException(e) == 1
    @test Q.JS_IsException(eval_js(ctx, "0")) == 0
    exc = Q.JS_GetException(ctx)
    msg = jsstring(ctx, exc)
    @test startswith(msg, "SyntaxError")
    Q.JS_FreeValue(ctx, exc)

    thrown = eval_js(ctx, "throw new RangeError('out of range: ' + 42)")
    @test Q.JS_IsException(thrown) == 1
    exc = Q.JS_GetException(ctx)
    @test jsstring(ctx, exc) == "RangeError: out of range: 42"
    Q.JS_FreeValue(ctx, exc)

    # Sloppy mode creates a global; strict mode refuses.
    @test tag(eval_js(ctx, "sloppyGlobal = 1")) == TAG_INT
    strict = eval_js(ctx, "strictGlobal = 1"; flags = Q.JS_EVAL_TYPE_GLOBAL() | Q.JS_EVAL_FLAG_STRICT())
    @test Q.JS_IsException(strict) == 1
    exc = Q.JS_GetException(ctx)
    @test startswith(jsstring(ctx, exc), "ReferenceError")
    Q.JS_FreeValue(ctx, exc)
end

@testset "JS_Call with JSValue arguments" begin
    fn = eval_js(ctx, "(function (a, b) { return a * 10 + b; })")
    @test Q.JS_IsFunction(ctx, fn) == 1
    argv = [Q.JS_NewInt32(ctx, 4), Q.JS_NewInt32(ctx, 2)]
    r = GC.@preserve argv Q.JS_Call(ctx, fn, Q.JS_UNDEFINED(), 2, pointer(argv))
    @test tag(r) == TAG_INT && int32(r) == 42
    Q.JS_FreeValue(ctx, fn)
end

@testset "a Julia function called from JavaScript" begin
    cf = @cfunction(jl_mul, Q.JSValue, (Ptr{Q.JSContext}, Q.JSValue, Cint, Ptr{Q.JSValue}))
    fn = Q.JS_NewCFunction2(ctx, cf, "jlmul", 2, Q.JS_CFUNC_generic, 0)
    @test tag(fn) == TAG_OBJECT
    g = Q.JS_GetGlobalObject(ctx)
    @test Q.JS_SetPropertyStr(ctx, g, "jlmul", fn) == 1      # takes ownership of fn
    Q.JS_FreeValue(ctx, g)
    r = eval_js(ctx, "jlmul(6, 7)")
    @test int32(r) == 43
    # Called in a loop from JS: Julia is on the hot path, the totals must agree.
    r = eval_js(ctx, "let s = 0; for (let i = 0; i < 1000; i++) s += jlmul(i, 2); s")
    @test int32(r) == sum(i * 2 + 1 for i in 0:999)
end

@testset "quickjs-libc helpers" begin
    @test jsstring(ctx, eval_js(ctx, "typeof console")) == "undefined"
    Q.js_std_add_helpers(ctx, 0, C_NULL)
    @test jsstring(ctx, eval_js(ctx, "typeof console.log")) == "function"
    @test jsstring(ctx, eval_js(ctx, "typeof print")) == "function"
end

@testset "bytecode: compile, save, load into a fresh runtime" begin
    # Compile without running, the way qjsc does.
    src = "function fib(n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); } fib(20)"
    fn = Q.JS_Eval(ctx, src, sizeof(src), "<bytecode>",
                   Q.JS_EVAL_TYPE_GLOBAL() | Q.JS_EVAL_FLAG_COMPILE_ONLY())
    @test Q.JS_IsException(fn) == 0
    @test tag(fn) == TAG_FUNCTION_BYTECODE
    size = Ref{Csize_t}(0)
    buf = Q.JS_WriteObject(ctx, size, fn, Q.JS_WRITE_OBJ_BYTECODE())
    @test buf != C_NULL && size[] > 0
    bytes = copy(unsafe_wrap(Vector{UInt8}, buf, size[]))
    Q.js_free(ctx, buf)
    Q.JS_FreeValue(ctx, fn)
    @test bytes[1] == BC_VERSION            # the writer's first byte (quickjs.c JS_WriteObjectAtoms)

    # Through a file, as a bytecode cache would.
    path = tempname()
    write(path, bytes)
    bytes = read(path)
    rm(path)

    # A different runtime: nothing of the source survives but these bytes.
    rt2 = Q.JS_NewRuntime(); ctx2 = Q.JS_NewContext(rt2)
    obj = GC.@preserve bytes Q.JS_ReadObject(ctx2, bytes, length(bytes), Q.JS_READ_OBJ_BYTECODE())
    @test Q.JS_IsException(obj) == 0
    r = Q.JS_EvalFunction(ctx2, obj)        # consumes obj
    @test tag(r) == TAG_INT && int32(r) == 6765

    # Bytecode is tied to the QuickJS release that wrote it.
    bad = copy(bytes); bad[1] = UInt8(BC_VERSION - 1)
    e = GC.@preserve bad Q.JS_ReadObject(ctx2, bad, length(bad), Q.JS_READ_OBJ_BYTECODE())
    @test Q.JS_IsException(e) == 1
    exc = Q.JS_GetException(ctx2)
    @test jsstring(ctx2, exc) == "SyntaxError: invalid version ($(BC_VERSION - 1) expected=$BC_VERSION)"
    Q.JS_FreeValue(ctx2, exc)

    Q.JS_FreeContext(ctx2)
    Q.JS_FreeRuntime(rt2)                   # asserts nothing leaked in rt2
end

@testset "[wrap.macros] shims: JSValue access" begin
    v = Q.JS_NewInt32(ctx, -12345)
    @test Q.JS_VALUE_GET_TAG(v) == tag(v) == TAG_INT
    @test Q.JS_VALUE_GET_NORM_TAG(v) == TAG_INT
    @test Q.JS_VALUE_GET_INT(v) == -12345
    m = Q.JS_MKVAL(TAG_INT, 99)
    @test tag(m) == TAG_INT && int32(m) == 99
    @test Q.JS_VALUE_GET_BOOL(Q.JS_TRUE()) == 1 && Q.JS_VALUE_GET_BOOL(Q.JS_FALSE()) == 0
    @test Q.JS_TAG_IS_FLOAT64(TAG_FLOAT64) == 1 && Q.JS_TAG_IS_FLOAT64(TAG_INT) == 0
    @test Q.JS_VALUE_IS_BOTH_INT(v, m) == 1
    f = Q.JS_NewFloat64(ctx, 2.5)
    @test Q.JS_VALUE_GET_FLOAT64(f) == 2.5
    @test Q.JS_VALUE_IS_BOTH_FLOAT(f, Q.JS_NewFloat64(ctx, -1.5)) == 1
    # A double that is an exact int32 comes back as an INT (quickjs.h:595-611);
    # -0.0 does not, since its bits differ from 0's.
    @test tag(Q.JS_NewFloat64(ctx, -1.0)) == TAG_INT
    @test tag(Q.JS_NewFloat64(ctx, -0.0)) == TAG_FLOAT64
    @test Q.JS_VALUE_IS_NAN(Q.JS_NewFloat64(ctx, NaN)) == 1
    @test Q.JS_VALUE_IS_NAN(f) == 0
end

@testset "[wrap.macros] shims: constructors and predicates" begin
    # Small integers stay ints; larger ones become doubles (quickjs.h:570-590)
    @test tag(Q.JS_NewInt64(ctx, 7)) == TAG_INT
    big = Q.JS_NewInt64(ctx, 2^40)
    @test tag(big) == TAG_FLOAT64 && Q.JS_VALUE_GET_FLOAT64(big) == 2.0^40
    u = Q.JS_NewUint32(ctx, 0xffffffff)
    @test tag(u) == TAG_FLOAT64
    out = Ref{Cuint}(0)
    @test Q.JS_ToUint32(ctx, out, u) == 0 && out[] == 0xffffffff
    @test Q.JS_IsBool(Q.JS_NewBool(ctx, 1)) == 1
    @test Q.JS_IsNumber(Q.JS_NewFloat64(ctx, 1.25)) == 1
    @test Q.JS_IsNull(Q.JS_NULL()) == 1 && Q.JS_IsNull(Q.JS_UNDEFINED()) == 0
    @test Q.JS_IsUndefined(Q.JS_UNDEFINED()) == 1
    @test Q.JS_IsException(Q.JS_EXCEPTION()) == 1
    @test Q.JS_IsUninitialized(Q.JS_UNINITIALIZED()) == 1

    sym = eval_js(ctx, "Symbol('s')")
    @test Q.JS_IsSymbol(sym) == 1 && Q.JS_VALUE_HAS_REF_COUNT(sym) == 1
    Q.JS_FreeValue(ctx, sym)
    bi = eval_js(ctx, "2n ** 100n")
    @test Q.JS_IsBigInt(ctx, bi) == 1
    @test jsstring(ctx, bi) == string(big"2"^100)
    Q.JS_FreeValue(ctx, bi)
    @test Q.JS_VALUE_HAS_REF_COUNT(Q.JS_NewInt32(ctx, 1)) == 0

    # A Julia string into JS, and back.
    s = Q.JS_NewString(ctx, "from julia ✓")
    @test Q.JS_IsString(s) == 1
    p = Q.JS_ToCString_ptr(ctx, s)
    @test unsafe_string(p) == "from julia ✓"
    Q.JS_FreeCString(ctx, Ptr{UInt8}(p))
    # (The String-returning Q.JS_ToCString converts and drops the pointer, so
    # its C string is never handed back to JS_FreeCString: prefer the _ptr form.)

    # JS_DupValue really takes a reference: the count sits before the object.
    rc(v) = unsafe_load(Ptr{Cint}(Q.JS_VALUE_GET_PTR(v)) - 4)
    n = rc(s)
    s2 = Q.JS_DupValue(ctx, s)
    @test rc(s) == n + 1
    Q.JS_FreeValue(ctx, s2)
    @test rc(s) == n
    Q.JS_FreeValue(ctx, s)

    # The JS_NewCFunction shim, through JS_Call.
    cf = @cfunction(jl_mul, Q.JSValue, (Ptr{Q.JSContext}, Q.JSValue, Cint, Ptr{Q.JSValue}))
    fn = Q.JS_NewCFunction(ctx, cf, "jlmul2", 2)
    @test Q.JS_IsObject(fn) == 1 && Q.JS_IsFunction(ctx, fn) == 1
    argv = [Q.JS_NewInt32(ctx, 5), Q.JS_NewInt32(ctx, 5)]
    r = GC.@preserve argv Q.JS_Call(ctx, fn, Q.JS_UNDEFINED(), 2, pointer(argv))
    @test int32(r) == 26
    Q.JS_FreeValue(ctx, fn)
end

@testset "[wrap.macros] shims: atoms and properties" begin
    o = eval_js(ctx, "({ answer: 42 })")
    atom = Q.JS_NewAtom(ctx, "answer")
    @test int32(Q.JS_GetProperty(ctx, o, atom)) == 42
    @test Q.JS_SetProperty(ctx, o, atom, Q.JS_NewInt32(ctx, 7)) == 1
    @test int32(Q.JS_GetProperty(ctx, o, atom)) == 7
    p = Q.JS_AtomToCString_ptr(ctx, atom)
    @test unsafe_string(p) == "answer"
    Q.JS_FreeCString(ctx, Ptr{UInt8}(p))
    Q.JS_FreeAtom(ctx, atom)
    Q.JS_FreeValue(ctx, o)
end

@testset "[wrap.macros] value macros match quickjs.h" begin
    @test Q.JS_PROP_CONFIGURABLE() == 1 && Q.JS_PROP_WRITABLE() == 2 && Q.JS_PROP_ENUMERABLE() == 4
    @test Q.JS_PROP_C_W_E() == 7
    @test Q.JS_PROP_GETSET() == 1 << 4 && Q.JS_PROP_THROW_STRICT() == 1 << 15
    @test Q.JS_EVAL_FLAG_COMPILE_ONLY() == 1 << 5
    @test Q.JS_EVAL_FLAG_ASYNC() == 1 << 7
    @test Q.JS_EVAL_TYPE_MASK() == 3
    @test Q.JS_WRITE_OBJ_BYTECODE() == 1 && Q.JS_READ_OBJ_BYTECODE() == 1
    @test Q.JS_READ_OBJ_REFERENCE() == 1 << 3
    @test Q.JS_GPN_ENUM_ONLY() == 1 << 4
    @test Q.JS_STRIP_DEBUG() == 2
    @test Q.JS_DEF_CFUNC() == 0 && Q.JS_DEF_PROP_BOOL() == 11
    @test Q.JS_DEFAULT_STACK_SIZE() == 1024 * 1024
    @test Q.JS_ATOM_NULL() == 0 && Q.JS_INVALID_CLASS_ID() == 0
    @test Q.JS_LIMB_BITS() == 64 && Q.JS_SHORT_BIG_INT_BITS() == 64   # x86-64, __int128 available
end

@testset "[wrap.varargs] JS_Throw*Error" begin
    function thrown(e)
        @test Q.JS_IsException(e) == 1
        exc = Q.JS_GetException(ctx)
        msg = jsstring(ctx, exc)
        Q.JS_FreeValue(ctx, exc)
        return msg
    end
    @test thrown(Q.JS_ThrowTypeError_Cstring_Cint(ctx, "bad %s at %d", "arg", 3)) == "TypeError: bad arg at 3"
    @test thrown(Q.JS_ThrowRangeError_Cdouble(ctx, "x=%.2f", 1.5)) == "RangeError: x=1.50"
    @test thrown(Q.JS_ThrowSyntaxError_Cstring(ctx, "near %s", "eof")) == "SyntaxError: near eof"
    @test thrown(Q.JS_ThrowReferenceError_Cint(ctx, "slot %d", -1)) == "ReferenceError: slot -1"
    @test thrown(Q.JS_ThrowInternalError_Cstring_Cstring(ctx, "%s/%s", "a", "b")) == "InternalError: a/b"

    # Thrown from Julia inside a JS call, caught by JavaScript.
    cf = @cfunction(jl_throw, Q.JSValue, (Ptr{Q.JSContext}, Q.JSValue, Cint, Ptr{Q.JSValue}))
    g = Q.JS_GetGlobalObject(ctx)
    Q.JS_SetPropertyStr(ctx, g, "jlthrow", Q.JS_NewCFunction(ctx, cf, "jlthrow", 0))
    Q.JS_FreeValue(ctx, g)
    r = eval_js(ctx, "try { jlthrow(1, 2, 3) } catch (e) { e.name + ':' + e.message }")
    @test jsstring(ctx, r) == "RangeError:n=3 too big"
    Q.JS_FreeValue(ctx, r)
end

@testset "teardown (asserts no leaked GC object)" begin
    Q.JS_RunGC(rt)
    Q.JS_FreeContext(ctx)
    Q.JS_FreeRuntime(rt)
    @test true
end

end
