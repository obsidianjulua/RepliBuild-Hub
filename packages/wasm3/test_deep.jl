#!/usr/bin/env julia
# wasm3 Hub package — deep test: Julia hosts WebAssembly.
#
# fixtures/guest.c is compiled to a real .wasm module here (clang's wasm32
# target + wasm-ld), loaded into a wasm3 runtime, and driven from Julia. Proves:
#   - parse/load/find/call/results end to end, for every wasm value type:
#     i32, i64, f32 (passed as double through the varargs, read back as
#     Float32), f64, and a mixed (i32, f64) signature;
#   - both calling paths: the m3_CallV/m3_GetResultsV varargs overloads and
#     the argptrs arrays of m3_Call/m3_GetResults;
#   - signature introspection (arg/ret counts and types);
#   - errors are VALUES: a divide-by-zero trap, a stack-overflow trap, an
#     unknown function, a malformed module — each a returned string, and the
#     runtime keeps working after each;
#   - linear memory: Julia writes a string into the guest's buffer, the guest
#     transforms it, Julia reads it back; a checksum agrees with Julia's;
#   - a Julia function linked in as the guest's import (m3_LinkRawFunction):
#     reading its argument and writing its result on wasm3's stack, and
#     trapping by returning an error string;
#   - WASI (wasm3's simple POSIX build): the guest's fd_write reaches stdout.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/wasm3/test_deep.jl
# Needs clang with the wasm32 target, and wasm-ld (LLVM's lld).

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Wasm3.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)
import .Wasm3 as W

# ── The guest module ─────────────────────────────────────────────────────────

const WASM = let out = joinpath(mktempdir(), "guest.wasm")
    for tool in ("clang", "wasm-ld")
        Sys.which(tool) === nothing && error("$tool not found: the test compiles fixtures/guest.c to wasm32")
    end
    run(`clang --target=wasm32 -O2 -nostdlib -Wl,--no-entry -o $out $(joinpath(PKG_DIR, "fixtures", "guest.c"))`)
    read(out)    # wasm3 keeps pointers into these bytes: they must outlive the module
end

ok(r) = r === nothing || error("wasm3: $r")

# ── The host function the guest imports as env.jl_scale, signature i(i) ─────
# M3RawCall: one 8-byte slot per value on wasm3's stack, return slot first.
const REFUSAL = Vector{UInt8}("jl_scale refused a negative\0")
function jl_scale(rt::Ptr{Cvoid}, ctx::Ptr{Cvoid}, sp::Ptr{UInt64}, mem::Ptr{Cvoid})::Ptr{Cvoid}
    x = unsafe_load(Ptr{Int32}(sp + 8))               # argument 1 at sp[1]
    x < 0 && return pointer(REFUSAL)                  # an error string = a trap
    unsafe_store!(Ptr{Int32}(sp), x * Int32(10))      # result at sp[0]
    return C_NULL                                     # m3Err_none
end

@testset "wasm3 Deep Tests" begin

@testset "version" begin
    @test W.M3_VERSION() == "0.9.0"
    @test (W.M3_VERSION_MAJOR(), W.M3_VERSION_MINOR(), W.M3_VERSION_REV()) == (0, 9, 0)
    @test WASM[1:4] == b"\0asm"
end

env = W.m3_NewEnvironment()
rt  = W.m3_NewRuntime(env, UInt32(256 * 1024), C_NULL)   # wasm3 stack: ~1000-deep fits, 10M does not
@test env != C_NULL && rt != C_NULL

modref = Ref{Ptr{W.M3Module}}(C_NULL)
ok(W.m3_ParseModule(env, modref, WASM, UInt32(length(WASM))))
mod = modref[]
ok(W.m3_LoadModule(rt, mod))                          # the runtime now owns the module
ok(W.m3_LinkRawFunction(mod, "env", "jl_scale", "i(i)",
                        @cfunction(jl_scale, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{UInt64}, Ptr{Cvoid}))))
ok(W.m3_LinkWASI(mod))

function fn(name)
    f = Ref{Ptr{W.M3Function}}(C_NULL)
    ok(W.m3_FindFunction(f, rt, name))
    return f[]
end
result(f, ::Type{T}) where {T} = (r = Ref{T}(0); ok(W.m3_GetResultsV_PtrCvoid(f, r)); r[])

@testset "every value type through the varargs" begin
    add = fn("add")
    ok(W.m3_CallV_Cint_Cint(add, 40, 2));                 @test result(add, Int32) == 42
    ok(W.m3_CallV_Cint_Cint(add, typemax(Int32), 1));     @test result(add, Int32) == typemin(Int32)  # wraps, as wasm i32 does
    m = fn("mul64")
    ok(W.m3_CallV_Clonglong_Clonglong(m, 3_000_000_000, 3)); @test result(m, Int64) == 9_000_000_000
    h = fn("hyp")
    ok(W.m3_CallV_Cdouble_Cdouble(h, 3.0, 4.0));          @test result(h, Float64) == 5.0
    hf = fn("halff")                                       # f32: in as double, out as Float32
    ok(W.m3_CallV_Cdouble(hf, 3.0));                      @test result(hf, Float32) === 1.5f0
    s = fn("scale")
    ok(W.m3_CallV_Cint_Cdouble(s, 4, 2.5));               @test result(s, Float64) == 10.0
    f = fn("fib")
    ok(W.m3_CallV_Cint(f, 25));                           @test result(f, Int32) == 75025
end

@testset "argptrs arrays: m3_Call / m3_GetResults" begin
    add = fn("add")
    a = Ref{Int32}(7); b = Ref{Int32}(8)
    args = Ptr{Cvoid}[Base.unsafe_convert(Ptr{Int32}, a), Base.unsafe_convert(Ptr{Int32}, b)]
    GC.@preserve a b args ok(W.m3_Call(add, UInt32(2), args))
    r = Ref{Int32}(0)
    rets = Ptr{Cvoid}[Base.unsafe_convert(Ptr{Int32}, r)]
    GC.@preserve r rets ok(W.m3_GetResults(add, UInt32(1), rets))
    @test r[] == 15
end

@testset "signatures" begin
    @test W.m3_GetArgCount(fn("add")) == 2 && W.m3_GetRetCount(fn("add")) == 1
    @test W.m3_GetArgType(fn("add"), UInt32(0)) == W.c_m3Type_i32
    @test W.m3_GetArgType(fn("mul64"), UInt32(1)) == W.c_m3Type_i64
    @test W.m3_GetArgType(fn("halff"), UInt32(0)) == W.c_m3Type_f32
    @test W.m3_GetRetType(fn("hyp"), UInt32(0)) == W.c_m3Type_f64
    @test W.m3_GetArgCount(fn("hello")) == 0
end

@testset "errors are values, and the runtime survives them" begin
    d = fn("idiv")
    @test W.m3_CallV_Cint_Cint(d, 7, 0) == "[trap] integer divide by zero"
    @test W.m3_CallV_Cint_Cint(d, 7, 2) === nothing && result(d, Int32) == 3
    dp = fn("deep")
    @test W.m3_CallV_Cint(dp, 1000) === nothing && result(dp, Int32) == 1000
    @test W.m3_CallV_Cint(dp, 10_000_000) == "[trap] stack overflow"
    @test W.m3_CallV_Cint(dp, 10) === nothing && result(dp, Int32) == 10
    @test W.m3_FindFunction(Ref{Ptr{W.M3Function}}(C_NULL), rt, "no_such_export") == "function lookup failed"
    bad = UInt8[0x00, 0x61, 0x73, 0x6d, 0x07, 0x00, 0x00, 0x00]  # right magic, wrong version
    @test W.m3_ParseModule(env, Ref{Ptr{W.M3Module}}(C_NULL), bad, UInt32(length(bad))) isa String
end

@testset "linear memory shared with Julia" begin
    size = Ref{UInt32}(0)
    mem = W.m3_GetMemory(rt, size, UInt32(0))
    @test mem != C_NULL && size[] >= 65536 && size[] % 65536 == 0     # whole wasm pages
    bf = fn("buffer")
    ok(W.m3_Call(bf, UInt32(0), C_NULL))
    off = result(bf, Int32)                                            # a guest pointer: an offset
    @test 0 < off < size[]
    text = "hello, wasm from julia"
    view = unsafe_wrap(Vector{UInt8}, mem + off, length(text))
    copyto!(view, codeunits(text))                                     # Julia writes guest memory
    ok(W.m3_CallV_Cint(fn("upcase"), length(text)))                    # the guest rewrites it
    @test String(copy(view)) == uppercase(text)                        # Julia reads it back
    ck = fn("checksum")
    ok(W.m3_CallV_Cint(ck, length(text)))
    @test reinterpret(UInt32, result(ck, Int32)) ==
          foldl((s, c) -> s * UInt32(31) + UInt32(c), codeunits(uppercase(text)); init = UInt32(0))
end

@testset "a Julia function as the guest's import" begin
    ch = fn("call_host")
    ok(W.m3_CallV_Cint(ch, 4));  @test result(ch, Int32) == 41        # jl_scale(4)*… = 40, +1
    @test W.m3_CallV_Cint(ch, -1) == "jl_scale refused a negative"     # the host trapped
    ok(W.m3_CallV_Cint(ch, 7));  @test result(ch, Int32) == 71        # and the guest still runs
end

@testset "WASI: the guest writes to stdout" begin
    path = tempname()
    open(path, "w") do io
        redirect_stdout(io) do
            ok(W.m3_Call(fn("hello"), UInt32(0), C_NULL))
            Libc.flush_cstdio()
        end
    end
    @test read(path, String) == "hello from wasm\n"
    rm(path)
    @test result(fn("hello"), Int32) == 16                             # bytes fd_write reported
end

@testset "teardown" begin
    W.m3_FreeRuntime(rt)
    W.m3_FreeEnvironment(env)
    @test true
end

end
