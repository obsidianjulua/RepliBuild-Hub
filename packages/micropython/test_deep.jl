#!/usr/bin/env julia
# MicroPython Hub package — deep test of the embed API from Julia.
#
# Julia hosts a MicroPython interpreter: hands it Python source, reads results
# back out of its globals, lets Python call a Julia function, and checks the
# interpreter's own safety nets (exceptions, recursion limit, GC) hold inside a
# Julia process. Proves:
#   - init with the REAL thread stack top (pthread_getattr_np) and a stack
#     limit set before any Python runs (see mpconfigport.h on why both matter);
#   - the object encoding shims (representation A): small ints and interned
#     strings in the pointer, the None/True/False singletons, small-int bounds;
#   - results read back without ever raising: mp_globals_get → its map →
#     mp_map_lookup (NULL for a missing name), then predicate-guarded
#     conversions (int, float, str, bool, None, a 2**100 bigint as text);
#   - uncaught errors print a traceback and leave the interpreter usable;
#   - runaway recursion is a Python RuntimeError, not a dead process;
#   - the GC reclaims many times its heap, scanning the C stack up to Julia's;
#   - Python calling a Julia function (a builtin built in Julia memory);
#   - the variadics: mp_printf to stdout, an exception object made with
#     mp_obj_new_exception_msg_varg and raised by Python.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/micropython/test_deep.jl

using Test, Libdl

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Micropython.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first (run harvest_embed.sh before that)"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)
import .Micropython as M
const LIB = dlopen(M.LIBRARY_PATH)

# ── Host setup ───────────────────────────────────────────────────────────────

"Top (highest address) and size of the calling thread's stack, from glibc."
function thread_stack()
    attr = zeros(UInt8, 64)                  # pthread_attr_t: 56 bytes on x86-64 glibc
    @assert ccall(:pthread_getattr_np, Cint, (UInt, Ptr{UInt8}),
                  ccall(:pthread_self, UInt, ()), attr) == 0
    addr = Ref{Ptr{Cvoid}}(C_NULL); size = Ref{Csize_t}(0)
    ccall(:pthread_attr_getstack, Cint, (Ptr{UInt8}, Ref{Ptr{Cvoid}}, Ref{Csize_t}), attr, addr, size)
    ccall(:pthread_attr_destroy, Cint, (Ptr{UInt8},), attr)
    return addr[] + size[], size[]
end

const HEAP = zeros(UInt8, 1 << 20)           # MicroPython's GC heap: 1 MiB, Julia-owned

"Run Python source; return what it printed to stdout."
function py(src)
    path = tempname()
    open(path, "w") do io
        redirect_stdout(io) do
            M.mp_embed_exec_str(src)
            Libc.flush_cstdio()
        end
    end
    out = read(path, String)
    rm(path)
    return out
end

"A global's object, or `nothing` if the name is unbound. Never raises."
function getglobal(name)
    d = M.mp_globals_get()
    map = Ptr{M._mp_map_t}(Ptr{UInt8}(d) + M.member_offset(:_mp_obj_dict_t, :map))
    e = M.mp_map_lookup(map, M.MP_OBJ_NEW_QSTR(M.qstr_from_str(name)), M.MP_MAP_LOOKUP)
    return e == C_NULL ? nothing : unsafe_load(e).value
end

pystr(o) = (@assert M.mp_obj_is_str(o) == 1; M.mp_obj_str_get_data(o, Ref{Csize_t}(0)))

# A Julia function Python can call: jlmul(a, b) = a*b + 1 on small ints, else
# None. It must not raise (a raise would jump across this Julia frame), so it
# checks with predicates instead of converting blindly.
function jl_mul(a::Ptr{Cvoid}, b::Ptr{Cvoid})::Ptr{Cvoid}
    (M.mp_obj_is_small_int(a) == 1 && M.mp_obj_is_small_int(b) == 1) || return M.mp_const_none()
    return M.MP_OBJ_NEW_SMALL_INT(M.MP_OBJ_SMALL_INT_VALUE(a) * M.MP_OBJ_SMALL_INT_VALUE(b) + 1)
end
# mp_obj_fun_builtin_fixed_t { mp_obj_base_t base (type*); union fun } built in
# Julia memory: outside MicroPython's heap, so its GC leaves it alone.
const JLMUL_OBJ = UInt[0, 0]

@testset "MicroPython Deep Tests" begin

@testset "object encoding shims (representation A)" begin
    o = M.MP_OBJ_NEW_SMALL_INT(21)
    @test UInt(o) == (21 << 1) | 1
    @test M.mp_obj_is_small_int(o) == 1 && M.MP_OBJ_SMALL_INT_VALUE(o) == 21
    @test M.MP_OBJ_SMALL_INT_VALUE(M.MP_OBJ_NEW_SMALL_INT(-5)) == -5
    @test M.MP_SMALL_INT_MAX() == 2^62 - 1 && M.MP_SMALL_INT_MIN() == -2^62
    @test M.MP_SMALL_INT_FITS(2^62 - 1) == 1 && M.MP_SMALL_INT_FITS(2^62) == 0
    @test length(unique([M.mp_const_none(), M.mp_const_true(), M.mp_const_false()])) == 3
    # An object pointer has its low two bits clear; immediates do not. Holds
    # whichever way this config encodes the singletons (py/obj.h:926-932).
    for o in (M.mp_const_none(), M.mp_const_true(), M.MP_OBJ_NEW_SMALL_INT(3))
        @test M.mp_obj_is_obj(o) == (UInt(o) & 3 == 0)
    end
    @test M.mp_obj_is_small_int(M.mp_const_none()) == 0
    @test sizeof(M._mp_map_elem_t) == 16 && M.member_offset(:_mp_obj_dict_t, :map) == 8
end

top, stacksize = thread_stack()
M.mp_embed_init(HEAP, length(HEAP), top)
# Before ANY Python: the default limit is 0 (mpconfigport.h explains the hang).
M.mp_stack_set_limit(stacksize - 64 * 1024)

@testset "interned strings" begin
    q = M.qstr_from_str("hello")
    @test M.qstr_from_str("hello") == q                     # interned: same id
    s = M.MP_OBJ_NEW_QSTR(q)
    @test UInt(s) == (q << 3) | 2
    @test M.mp_obj_is_qstr(s) == 1 && M.MP_OBJ_QSTR_VALUE(s) == q
    @test M.mp_obj_is_str(s) == 1 && pystr(s) == "hello"
end

@testset "run Python, read its output" begin
    @test py("print('hello', 1 + 2)") == "hello 3\n"
    @test py("print([x * x for x in range(5)])") == "[0, 1, 4, 9, 16]\n"
    @test py("import math\nprint(math.sqrt(16.0), math.pi > 3)") == "4.0 True\n"
end

@testset "results come back through the globals" begin
    @test py("""
    x = sum(range(101))
    y = 1 / 8
    z = 'naïve'
    big = str(2 ** 100)
    flag = 10 > 3
    nothing_here = None
    """) == ""
    x = getglobal("x")
    @test M.mp_obj_is_small_int(x) == 1 && M.MP_OBJ_SMALL_INT_VALUE(x) == 5050
    @test M.mp_obj_is_int(x) == 1 && M.mp_obj_get_int(x) == 5050
    y = getglobal("y")
    @test M.mp_obj_is_float(y) == 1 && M.mp_obj_get_float(y) == 0.125
    @test pystr(getglobal("z")) == "naïve"
    @test pystr(getglobal("big")) == string(big"2"^100)
    @test getglobal("flag") == M.mp_const_true()
    @test getglobal("nothing_here") == M.mp_const_none()
    @test getglobal("never_assigned") === nothing             # NULL, no raise, no hang
    # A bigint is a heap object, not a small int: still an int.
    py("huge = 2 ** 80")
    h = getglobal("huge")
    @test M.mp_obj_is_small_int(h) == 0 && M.mp_obj_is_int(h) == 1
end

@testset "errors print and the interpreter survives" begin
    out = py("1 / 0")
    @test occursin("ZeroDivisionError", out) && occursin("Traceback", out)
    @test occursin("SyntaxError", py("def ("))
    @test occursin("NameError", py("undefined_name + 1"))
    @test py("print('still alive')") == "still alive\n"
end

@testset "runaway recursion is a Python error" begin
    @test py("""
    def g(n):
        return g(n + 1)
    try:
        g(0)
    except RuntimeError as e:
        print(e)
    """) == "maximum recursion depth exceeded\n"
    @test py("def f(n): return 0 if n == 0 else 1 + f(n - 1)\nprint(f(300))") == "300\n"
end

@testset "GC reclaims many times its heap" begin
    # ~3.2 MB of short-lived lists through a 1 MiB heap: only works if the
    # collector runs, scanning the C stack up to the top Julia gave it.
    @test py("""
    import gc
    total = 0
    for i in range(200):
        t = [i] * 2000
        total += len(t)
    gc.collect()
    print(total, gc.mem_free() > 0)
    """) == "400000 True\n"
end

@testset "Python calls a Julia function" begin
    JLMUL_OBJ[1] = UInt(dlsym(LIB, :mp_type_fun_builtin_2))
    JLMUL_OBJ[2] = UInt(@cfunction(jl_mul, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid})))
    fn = pointer(JLMUL_OBJ)
    @test UInt(fn) & 3 == 0                                 # an object pointer, not an immediate
    M.mp_obj_dict_store(M.mp_globals_get(), M.MP_OBJ_NEW_QSTR(M.qstr_from_str("jlmul")), fn)
    @test py("print(jlmul(6, 7))") == "43\n"
    @test py("print(jlmul('a', 1))") == "None\n"            # the Julia side refused, did not raise
    @test py("print(sum(jlmul(i, 2) for i in range(1000)))") == "$(sum(2i + 1 for i in 0:999))\n"
end

@testset "[wrap.varargs]" begin
    plat = dlsym(LIB, :mp_plat_print)
    out = let path = tempname()
        open(path, "w") do io
            redirect_stdout(io) do
                M.mp_printf_Cstring_Cint(plat, "%s=%d\n", "answer", 42)
                M.mp_printf_Cdouble(plat, "pi~%f\n", 3.25)
                Libc.flush_cstdio()
            end
        end
        s = read(path, String); rm(path); s
    end
    @test startswith(out, "answer=42\npi~3.25")
    # An exception object made in C, raised by Python.
    e = M.mp_obj_new_exception_msg_varg_Cstring_Cint(dlsym(LIB, :mp_type_ValueError),
                                                     "bad %s at %d", "arg", 3)
    M.mp_obj_dict_store(M.mp_globals_get(), M.MP_OBJ_NEW_QSTR(M.qstr_from_str("made_in_c")), e)
    @test py("""
    try:
        raise made_in_c
    except ValueError as err:
        print(type(err).__name__, err)
    """) == "ValueError bad arg at 3\n"
end

@testset "deinit" begin
    M.mp_embed_deinit()
    @test true
end

end
