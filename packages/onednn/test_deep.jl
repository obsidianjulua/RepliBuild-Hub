#!/usr/bin/env julia
# onednn Hub package — deep test (wrapper already built; this does not rebuild).
#
# What this pins, beyond "the .so loads":
#   - harvested OpenCL-GPU + OpenMP-CPU identity, read back from the library
#   - every [wrap.macros] shim returns the header value (argument indices,
#     sentinels, the function-like post-op index)
#   - a real primitive, not the BLAS shortcut: matmul, eltwise ReLU, binary
#     add, a layout reorder, and a matmul with a ReLU post-op
#   - the error path (bad engine index, bad rank, mismatched K)
#   - the experimental ukernel: f32 brgemm of the same product
#   - a GPU engine, and a ReLU executed on it when the device accepts one
#
# Usage: julia --project=/path/to/RepliBuild.jl packages/onednn/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Onednn.jl")
const SO      = joinpath(PKG_DIR, "julia", "libonednn.so")

@assert isfile(SO)      "libonednn.so missing — build first"
@assert isfile(WRAPPER) "Onednn.jl missing — wrap first"

include(WRAPPER)
using .Onednn
const D = Onednn

"Throw with the library's own status string. `dnnl_success` is the only ok."
function check(st, what)
    st == D.dnnl_success && return st
    why = D.dnnl_status2str(st)
    error("$what: $(why === nothing ? st : why)")
end

function with_engine(f, kind)
    eng = Ref{Ptr{D.dnnl_engine}}(C_NULL)
    check(D.dnnl_engine_create(eng, kind, 0), "dnnl_engine_create")
    try
        return f(eng[])
    finally
        D.dnnl_engine_destroy(eng[])
    end
end

function with_stream(f, eng)
    stream = Ref{Ptr{D.dnnl_stream}}(C_NULL)
    check(D.dnnl_stream_create(stream, eng, Cuint(D.dnnl_stream_in_order)),
          "dnnl_stream_create")
    try
        return f(stream[])
    finally
        D.dnnl_stream_destroy(stream[])
    end
end

"Memory descriptor for `dims` in format `tag`. Caller destroys it."
function md_tag(dims::Vector{Int64}, dt, tag)
    md = Ref{Ptr{D.dnnl_memory_desc}}(C_NULL)
    check(D.dnnl_memory_desc_create_with_tag(md, length(dims), dims, dt, tag),
          "dnnl_memory_desc_create_with_tag")
    return md[]
end

"Memory over a caller-owned buffer. The buffer must outlive execute."
function mem_buf(md, eng, buf::Array)
    mem = Ref{Ptr{D.dnnl_memory}}(C_NULL)
    check(D.dnnl_memory_create(mem, md, eng, pointer(buf)), "dnnl_memory_create")
    return mem[]
end

"Memory the library allocates. Caller destroys it."
function mem_alloc(md, eng)
    mem = Ref{Ptr{D.dnnl_memory}}(C_NULL)
    check(D.dnnl_memory_create(mem, md, eng, D.DNNL_MEMORY_ALLOCATE()),
          "dnnl_memory_create(ALLOCATE)")
    return mem[]
end

function execarg(idx::Integer, mem)
    D.dnnl_exec_arg_t(Cint(idx), ntuple(_ -> 0x00, 4), mem)
end

"Create, execute, wait, destroy. `args` is `{index, memory}`."
function run_primitive(pd_create::Function, eng, stream, args)
    pd = Ref{Ptr{D.dnnl_primitive_desc}}(C_NULL)
    prim = Ref{Ptr{D.dnnl_primitive}}(C_NULL)
    check(pd_create(pd), "primitive_desc_create")
    try
        check(D.dnnl_primitive_create(prim, pd[]), "dnnl_primitive_create")
        try
            cargs = D.dnnl_exec_arg_t[execarg(i, m) for (i, m) in args]
            check(D.dnnl_primitive_execute(prim[], stream, length(cargs), cargs),
                  "dnnl_primitive_execute")
            check(D.dnnl_stream_wait(stream), "dnnl_stream_wait")
            return D.dnnl_primitive_desc_query_s32(pd[], D.dnnl_query_num_of_inputs_s32, 0),
                   D.dnnl_primitive_desc_query_s32(pd[], D.dnnl_query_num_of_outputs_s32, 0)
        finally
            prim[] == C_NULL || D.dnnl_primitive_destroy(prim[])
        end
    finally
        pd[] == C_NULL || D.dnnl_primitive_desc_destroy(pd[])
    end
end

@testset "onednn Hub package" begin

@testset "library identity" begin
    @test isfile(D.LIBRARY_PATH)
    @test filesize(D.LIBRARY_PATH) > 10_000_000
    p = D.dnnl_version()
    @test p != C_NULL
    v = unsafe_load(p)
    @test v.major == 3
    @test v.minor == 11
    @test v.patch == 3
    @test unsafe_string(v.hash) == "74d04752d9eaefff6a9ff62466c4d20b155e5bca"
    @test v.gpu_runtime == 0x100   # DNNL_RUNTIME_OCL
    @test v.cpu_runtime == 2       # DNNL_RUNTIME_OMP
    @test D.dnnl_engine_get_count(D.dnnl_cpu) == 1
    @test D.dnnl_engine_get_count(D.dnnl_gpu) == 1
    cpu_isa = D.dnnl_get_effective_cpu_isa()
    @test cpu_isa isa D.dnnl_cpu_isa_t
    @test UInt32(cpu_isa) >= UInt32(D.dnnl_cpu_isa_sse41)
    # Aliases are the same enumerator, not a second enum that shadowed it.
    @test D.dnnl_cpu_isa_avx512_core_fp16 === D.dnnl_cpu_isa_avx10_1_512
    @test D.dnnl_nchw === D.dnnl_abcd
    @test D.dnnl_nhwc === D.dnnl_acdb
    @test D.dnnl_data_type_size(D.dnnl_f32) == 4
    @test D.dnnl_data_type_size(D.dnnl_s8) == 1
    @test D.dnnl_data_type_size(D.dnnl_f64) == 8
    @test D.dnnl_status2str(D.dnnl_success) == "success"
    @test D.dnnl_status2str(D.dnnl_invalid_arguments) == "invalid_arguments"
    @test D.dnnl_status2str(D.dnnl_unimplemented) == "unimplemented"
    @test D.dnnl_set_verbose(0) == D.dnnl_success
end

@testset "macro shims" begin
    # Header values. These do not exist in DWARF; the shim is the only way
    # the wrapper can name them. A wrong ret/args in the toml shows up here
    # as the wrong integer, not as a missing function.
    expected = Dict{Symbol,Int}(
        :DNNL_ARG_UNDEF => 0,
        :DNNL_ARG_SRC_0 => 1, :DNNL_ARG_SRC => 1, :DNNL_ARG_SRC_LAYER => 1,
        :DNNL_ARG_FROM => 1,
        :DNNL_ARG_SRC_1 => 2, :DNNL_ARG_SRC_ITER => 2,
        :DNNL_ARG_SRC_2 => 3, :DNNL_ARG_SRC_ITER_C => 3,
        :DNNL_ARG_SRC_3 => 4, :DNNL_ARG_AUGRU_ATTENTION => 4,
        :DNNL_ARG_DST_0 => 17, :DNNL_ARG_DST => 17, :DNNL_ARG_TO => 17,
        :DNNL_ARG_DST_LAYER => 17,
        :DNNL_ARG_DST_1 => 18, :DNNL_ARG_DST_ITER => 18,
        :DNNL_ARG_DST_2 => 19, :DNNL_ARG_DST_ITER_C => 19,
        :DNNL_ARG_WEIGHTS_0 => 33, :DNNL_ARG_WEIGHTS => 33,
        :DNNL_ARG_WEIGHTS_LAYER => 33,
        :DNNL_ARG_WEIGHTS_1 => 34, :DNNL_ARG_WEIGHTS_ITER => 34,
        :DNNL_ARG_WEIGHTS_2 => 35, :DNNL_ARG_WEIGHTS_PEEPHOLE => 35,
        :DNNL_ARG_WEIGHTS_3 => 36, :DNNL_ARG_WEIGHTS_PROJECTION => 36,
        :DNNL_ARG_BIAS => 41, :DNNL_ARG_REDUCE => 42,
        :DNNL_ARG_MEAN => 49, :DNNL_ARG_VARIANCE => 50,
        :DNNL_ARG_SCALE => 51, :DNNL_ARG_SHIFT => 52,
        :DNNL_ARG_WORKSPACE => 64, :DNNL_ARG_SCRATCHPAD => 80,
        :DNNL_ARG_DIFF_SRC_0 => 129, :DNNL_ARG_DIFF_SRC => 129,
        :DNNL_ARG_DIFF_SRC_LAYER => 129,
        :DNNL_ARG_DIFF_SRC_1 => 130, :DNNL_ARG_DIFF_SRC_ITER => 130,
        :DNNL_ARG_DIFF_SRC_2 => 131, :DNNL_ARG_DIFF_SRC_ITER_C => 131,
        :DNNL_ARG_DIFF_SRC_3 => 132, :DNNL_ARG_DIFF_AUGRU_ATTENTION => 132,
        :DNNL_ARG_DIFF_DST_0 => 145, :DNNL_ARG_DIFF_DST => 145,
        :DNNL_ARG_DIFF_DST_LAYER => 145,
        :DNNL_ARG_DIFF_DST_1 => 146, :DNNL_ARG_DIFF_DST_ITER => 146,
        :DNNL_ARG_DIFF_DST_2 => 147, :DNNL_ARG_DIFF_DST_ITER_C => 147,
        :DNNL_ARG_DIFF_WEIGHTS_0 => 161, :DNNL_ARG_DIFF_WEIGHTS => 161,
        :DNNL_ARG_DIFF_WEIGHTS_LAYER => 161,
        :DNNL_ARG_DIFF_WEIGHTS_1 => 162, :DNNL_ARG_DIFF_WEIGHTS_ITER => 162,
        :DNNL_ARG_DIFF_WEIGHTS_2 => 163, :DNNL_ARG_DIFF_WEIGHTS_PEEPHOLE => 163,
        :DNNL_ARG_DIFF_WEIGHTS_3 => 164, :DNNL_ARG_DIFF_WEIGHTS_PROJECTION => 164,
        :DNNL_ARG_DIFF_BIAS => 169,
        :DNNL_ARG_DIFF_SCALE => 255, :DNNL_ARG_DIFF_SHIFT => 256,
        :DNNL_ARG_ATTR_DROPOUT_OFFSET => 507,
        :DNNL_ARG_ATTR_ROUNDING_SEED => 508,
        :DNNL_ARG_ATTR_DROPOUT_MASK => 509,
        :DNNL_ARG_ATTR_DROPOUT_PROBABILITY => 510,
        :DNNL_ARG_ATTR_DROPOUT_SEED => 511,
        :DNNL_ARG_ATTR_PRECOMPUTED_REDUCTIONS => 512,
        :DNNL_ARG_ATTR_OUTPUT_SCALES => 513,
        :DNNL_ARG_MULTIPLE_SRC => 1024, :DNNL_ARG_MULTIPLE_DST => 2048,
        :DNNL_ARG_ATTR_SCALES => 4096, :DNNL_ARG_ATTR_ZERO_POINTS => 8192,
        :DNNL_ARG_ATTR_POST_OP_DW => 16384,
        :DNNL_ARG_ATTR_MULTIPLE_POST_OP_BASE => 32768,
        :DNNL_MAX_NDIMS => 12,
    )
    for (name, want) in expected
        @test Int(getfield(D, name)()) == want
    end
    # #define DNNL_ARG_ATTR_MULTIPLE_POST_OP(idx) (BASE * ((idx) + 1))
    @test Int(D.DNNL_ARG_ATTR_MULTIPLE_POST_OP(0)) == 32768
    @test Int(D.DNNL_ARG_ATTR_MULTIPLE_POST_OP(1)) == 65536
    @test D.DNNL_RUNTIME_DIM_VAL() == typemin(Int64)
    @test D.DNNL_RUNTIME_S32_VAL() == typemin(Int32)
    @test D.DNNL_RUNTIME_SIZE_VAL() == reinterpret(UInt, typemin(Int64))
    @test reinterpret(UInt32, D.DNNL_RUNTIME_F32_VAL()) == 0x7fc000d0
    @test D.DNNL_MEMORY_NONE() == C_NULL
    @test D.DNNL_MEMORY_ALLOCATE() == Ptr{Cvoid}(typemax(UInt))
    # Bitflags are an integer alias so the OR is a value, not a MethodError.
    @test D.dnnl_use_scale | D.dnnl_use_shift == D.dnnl_normalization_flags_t(6)
    @test D.dnnl_fuse_norm_relu | D.dnnl_rms_norm == D.dnnl_normalization_flags_t(40)
    @test D.dnnl_stream_default_flags == D.dnnl_stream_in_order
    @test UInt32(D.dnnl_stream_in_order) == 1
    @test UInt32(D.dnnl_stream_out_of_order) == 2
end

@testset "rejected arguments" begin
    eng = Ref{Ptr{D.dnnl_engine}}(C_NULL)
    @test D.dnnl_engine_create(eng, D.dnnl_cpu, 7) == D.dnnl_invalid_arguments
    @test eng[] == C_NULL
    md = Ref{Ptr{D.dnnl_memory_desc}}(C_NULL)
    dims = Int64[2, 2]
    @test D.dnnl_memory_desc_create_with_tag(md, 13, dims, D.dnnl_f32, D.dnnl_ab) ==
          D.dnnl_invalid_arguments
    @test md[] == C_NULL
    with_engine(D.dnnl_cpu) do eng
        src = md_tag(Int64[2, 3], D.dnnl_f32, D.dnnl_ab)
        w = md_tag(Int64[4, 2], D.dnnl_f32, D.dnnl_ab)   # K does not match
        dst = md_tag(Int64[2, 2], D.dnnl_f32, D.dnnl_ab)
        pd = Ref{Ptr{D.dnnl_primitive_desc}}(C_NULL)
        try
            @test D.dnnl_matmul_primitive_desc_create(pd, eng, src, w, C_NULL, dst, C_NULL) ==
                  D.dnnl_invalid_arguments
            @test pd[] == C_NULL
        finally
            D.dnnl_memory_desc_destroy(src)
            D.dnnl_memory_desc_destroy(w)
            D.dnnl_memory_desc_destroy(dst)
        end
    end
end

@testset "memory descriptors" begin
    a = md_tag(Int64[2, 3], D.dnnl_f32, D.dnnl_ab)
    b = md_tag(Int64[2, 3], D.dnnl_f32, D.dnnl_ab)
    c = md_tag(Int64[2, 3], D.dnnl_f32, D.dnnl_ba)
    try
        @test D.dnnl_memory_desc_get_size(a) == 2 * 3 * 4
        @test D.dnnl_memory_desc_equal(a, b) == 1
        @test D.dnnl_memory_desc_equal(a, c) == 0
    finally
        D.dnnl_memory_desc_destroy(a)
        D.dnnl_memory_desc_destroy(b)
        D.dnnl_memory_desc_destroy(c)
    end
    with_engine(D.dnnl_cpu) do eng
        md = md_tag(Int64[4], D.dnnl_f32, D.dnnl_a)
        mem = mem_alloc(md, eng)
        try
            handle = Ref{Ptr{Cvoid}}(C_NULL)
            check(D.dnnl_memory_get_data_handle(mem, handle), "get_data_handle")
            @test handle[] != C_NULL
        finally
            D.dnnl_memory_destroy(mem)
            D.dnnl_memory_desc_destroy(md)
        end
    end
end

@testset "CPU matmul" begin
    # Row-major ab. A is 2x2 [[1,2],[3,4]], B is [[5,6],[7,8]].
    # C = [[19,22],[43,50]].
    A = Float32[1, 2, 3, 4]
    B = Float32[5, 6, 7, 8]
    C = Float32[0, 0, 0, 0]
    with_engine(D.dnnl_cpu) do eng
        with_stream(eng) do stream
            src = md_tag(Int64[2, 2], D.dnnl_f32, D.dnnl_ab)
            w = md_tag(Int64[2, 2], D.dnnl_f32, D.dnnl_ab)
            dst = md_tag(Int64[2, 2], D.dnnl_f32, D.dnnl_ab)
            GC.@preserve A B C begin
                ms = mem_buf(src, eng, A)
                mw = mem_buf(w, eng, B)
                mc = mem_buf(dst, eng, C)
                try
                    nsrc, ndst = run_primitive(eng, stream, (
                        (D.DNNL_ARG_SRC(), ms),
                        (D.DNNL_ARG_WEIGHTS(), mw),
                        (D.DNNL_ARG_DST(), mc),
                    )) do pd
                        D.dnnl_matmul_primitive_desc_create(pd, eng, src, w, C_NULL, dst, C_NULL)
                    end
                    @test nsrc == 2
                    @test ndst == 1
                finally
                    D.dnnl_memory_destroy(ms)
                    D.dnnl_memory_destroy(mw)
                    D.dnnl_memory_destroy(mc)
                end
            end
            D.dnnl_memory_desc_destroy(src)
            D.dnnl_memory_desc_destroy(w)
            D.dnnl_memory_desc_destroy(dst)
        end
    end
    @test C == Float32[19, 22, 43, 50]
end

@testset "CPU matmul with ReLU post-op" begin
    # [1, -2] * [3, 4]^T = -5, then ReLU → 0.
    A = Float32[1, -2]
    B = Float32[3, 4]
    C = Float32[42]
    with_engine(D.dnnl_cpu) do eng
        with_stream(eng) do stream
            src = md_tag(Int64[1, 2], D.dnnl_f32, D.dnnl_ab)
            w = md_tag(Int64[2, 1], D.dnnl_f32, D.dnnl_ab)
            dst = md_tag(Int64[1, 1], D.dnnl_f32, D.dnnl_ab)
            po = Ref{Ptr{D.dnnl_post_ops}}(C_NULL)
            attr = Ref{Ptr{D.dnnl_primitive_attr}}(C_NULL)
            check(D.dnnl_post_ops_create(po), "post_ops_create")
            check(D.dnnl_post_ops_append_eltwise(po[], D.dnnl_eltwise_relu, 0f0, 0f0),
                  "append_eltwise")
            @test D.dnnl_post_ops_len(po[]) == 1
            check(D.dnnl_primitive_attr_create(attr), "attr_create")
            check(D.dnnl_primitive_attr_set_post_ops(attr[], po[]), "set_post_ops")
            GC.@preserve A B C begin
                ms = mem_buf(src, eng, A)
                mw = mem_buf(w, eng, B)
                mc = mem_buf(dst, eng, C)
                try
                    run_primitive(eng, stream, (
                        (D.DNNL_ARG_SRC(), ms),
                        (D.DNNL_ARG_WEIGHTS(), mw),
                        (D.DNNL_ARG_DST(), mc),
                    )) do pd
                        D.dnnl_matmul_primitive_desc_create(pd, eng, src, w, C_NULL, dst, attr[])
                    end
                finally
                    D.dnnl_memory_destroy(ms)
                    D.dnnl_memory_destroy(mw)
                    D.dnnl_memory_destroy(mc)
                end
            end
            D.dnnl_primitive_attr_destroy(attr[])
            D.dnnl_post_ops_destroy(po[])
            D.dnnl_memory_desc_destroy(src)
            D.dnnl_memory_desc_destroy(w)
            D.dnnl_memory_desc_destroy(dst)
        end
    end
    @test C == Float32[0]
end

@testset "CPU eltwise ReLU" begin
    src = Float32[-1, 0, 2, -4]
    dst = Float32[9, 9, 9, 9]
    with_engine(D.dnnl_cpu) do eng
        with_stream(eng) do stream
            md = md_tag(Int64[4], D.dnnl_f32, D.dnnl_a)
            GC.@preserve src dst begin
                ms = mem_buf(md, eng, src)
                mc = mem_buf(md, eng, dst)
                try
                    run_primitive(eng, stream, (
                        (D.DNNL_ARG_SRC(), ms),
                        (D.DNNL_ARG_DST(), mc),
                    )) do pd
                        D.dnnl_eltwise_forward_primitive_desc_create(
                            pd, eng, D.dnnl_forward_inference, D.dnnl_eltwise_relu,
                            md, md, 0f0, 0f0, C_NULL)
                    end
                finally
                    D.dnnl_memory_destroy(ms)
                    D.dnnl_memory_destroy(mc)
                end
            end
            D.dnnl_memory_desc_destroy(md)
        end
    end
    @test dst == Float32[0, 0, 2, 0]
end

@testset "CPU binary add" begin
    a = Float32[1, 2, 3, 4]
    b = Float32[10, 20, 30, 40]
    c = zeros(Float32, 4)
    with_engine(D.dnnl_cpu) do eng
        with_stream(eng) do stream
            md = md_tag(Int64[4], D.dnnl_f32, D.dnnl_a)
            GC.@preserve a b c begin
                m0 = mem_buf(md, eng, a)
                m1 = mem_buf(md, eng, b)
                mc = mem_buf(md, eng, c)
                try
                    run_primitive(eng, stream, (
                        (D.DNNL_ARG_SRC(), m0),
                        (D.DNNL_ARG_SRC_1(), m1),
                        (D.DNNL_ARG_DST(), mc),
                    )) do pd
                        D.dnnl_binary_primitive_desc_create(
                            pd, eng, D.dnnl_binary_add, md, md, md, C_NULL)
                    end
                finally
                    D.dnnl_memory_destroy(m0)
                    D.dnnl_memory_destroy(m1)
                    D.dnnl_memory_destroy(mc)
                end
            end
            D.dnnl_memory_desc_destroy(md)
        end
    end
    @test c == Float32[11, 22, 33, 44]
end

@testset "CPU reorder ab to ba" begin
    # Logical [[1,2],[3,4]]. ab is that order; ba is the transpose layout.
    src = Float32[1, 2, 3, 4]
    dst = zeros(Float32, 4)
    with_engine(D.dnnl_cpu) do eng
        with_stream(eng) do stream
            md_ab = md_tag(Int64[2, 2], D.dnnl_f32, D.dnnl_ab)
            md_ba = md_tag(Int64[2, 2], D.dnnl_f32, D.dnnl_ba)
            GC.@preserve src dst begin
                ms = mem_buf(md_ab, eng, src)
                mc = mem_buf(md_ba, eng, dst)
                try
                    run_primitive(eng, stream, (
                        (D.DNNL_ARG_FROM(), ms),
                        (D.DNNL_ARG_TO(), mc),
                    )) do pd
                        D.dnnl_reorder_primitive_desc_create(
                            pd, md_ab, eng, md_ba, eng, C_NULL)
                    end
                finally
                    D.dnnl_memory_destroy(ms)
                    D.dnnl_memory_destroy(mc)
                end
            end
            D.dnnl_memory_desc_destroy(md_ab)
            D.dnnl_memory_desc_destroy(md_ba)
        end
    end
    @test dst == Float32[1, 3, 2, 4]
end

@testset "CPU sgemm" begin
    # Column-major BLAS shortcut, distinct from the primitive matmul above.
    A = Float32[1, 0, 0, 1]
    B = Float32[1, 2, 3, 4]
    C = zeros(Float32, 4)
    st = D.dnnl_sgemm(UInt8('N'), UInt8('N'), Int64(2), Int64(2), Int64(2),
                      1f0, A, Int64(2), B, Int64(2), 0f0, C, Int64(2))
    @test st == D.dnnl_success
    @test C == Float32[1, 2, 3, 4]
    st = D.dnnl_sgemm(UInt8('N'), UInt8('N'), Int64(-1), Int64(2), Int64(2),
                      1f0, A, Int64(2), B, Int64(2), 0f0, C, Int64(2))
    @test st == D.dnnl_invalid_arguments
end

@testset "CPU f32 brgemm ukernel" begin
    # Same product as the primitive matmul. f32 does not need B packing, so
    # lda/ldb/ldc are the row strides. Pack-type is queried with a direct
    # call: the generated wrapper passes dnnl_pack_type_t by value, but the
    # C function writes through a pointer.
    pack = Ref{D.dnnl_pack_type_t}(D.dnnl_pack_type_undef)
    st = ccall((:dnnl_brgemm_get_B_pack_type, D.LIBRARY_PATH), D.dnnl_status_t,
               (Ptr{D.dnnl_pack_type_t}, D.dnnl_data_type_t, D.dnnl_data_type_t),
               pack, D.dnnl_f32, D.dnnl_f32)
    @test st == D.dnnl_success
    @test pack[] == D.dnnl_pack_type_no_trans
    A = Float32[1, 2, 3, 4]
    B = Float32[5, 6, 7, 8]
    C = zeros(Float32, 4)
    brg = Ref{Ptr{D.dnnl_brgemm}}(C_NULL)
    check(D.dnnl_brgemm_create(brg, Int64(2), Int64(2), Int64(2), Int64(1),
                               Int64(2), Int64(2), Int64(2),
                               D.dnnl_f32, D.dnnl_f32, D.dnnl_f32),
          "brgemm_create")
    try
        check(D.dnnl_brgemm_finalize(brg[]), "brgemm_finalize")
        check(D.dnnl_brgemm_generate(brg[]), "brgemm_generate")
        scratch_n = Ref{Csize_t}(0)
        check(D.dnnl_brgemm_get_scratchpad_size(brg[], scratch_n), "scratchpad_size")
        scratch = zeros(UInt8, scratch_n[])
        offsets = Int64[0, 0]
        check(D.dnnl_brgemm_set_hw_context(brg[]), "set_hw_context")
        try
            GC.@preserve A B C scratch offsets begin
                spad = scratch_n[] == 0 ? C_NULL : pointer(scratch)
                check(D.dnnl_brgemm_execute(brg[], pointer(A), pointer(B),
                                            pointer(offsets), pointer(C), spad),
                      "brgemm_execute")
            end
        finally
            D.dnnl_brgemm_release_hw_context()
        end
    finally
        D.dnnl_brgemm_destroy(brg[])
    end
    @test C == Float32[19, 22, 43, 50]
end

@testset "GPU engine and ReLU" begin
    with_engine(D.dnnl_gpu) do eng
        # Same out-parameter bug as brgemm_get_B_pack_type: the wrapper takes
        # the enum by value, the C function writes through a pointer.
        kind = Ref{D.dnnl_engine_kind_t}(D.dnnl_any_engine)
        st = ccall((:dnnl_engine_get_kind, D.LIBRARY_PATH), D.dnnl_status_t,
                   (Ptr{D.dnnl_engine}, Ptr{D.dnnl_engine_kind_t}), eng, kind)
        @test st == D.dnnl_success
        @test kind[] == D.dnnl_gpu
        with_stream(eng) do stream
            md = md_tag(Int64[4], D.dnnl_f32, D.dnnl_a)
            src = mem_alloc(md, eng)
            dst = mem_alloc(md, eng)
            try
                mapped = Ref{Ptr{Cvoid}}(C_NULL)
                check(D.dnnl_memory_map_data(src, mapped), "map src")
                host = Float32[-1, 0, 3, -2]
                GC.@preserve host unsafe_copyto!(Ptr{Float32}(mapped[]), pointer(host), 4)
                check(D.dnnl_memory_unmap_data(src, mapped[]), "unmap src")
                run_primitive(eng, stream, (
                    (D.DNNL_ARG_SRC(), src),
                    (D.DNNL_ARG_DST(), dst),
                )) do pd
                    D.dnnl_eltwise_forward_primitive_desc_create(
                        pd, eng, D.dnnl_forward_inference, D.dnnl_eltwise_relu,
                        md, md, 0f0, 0f0, C_NULL)
                end
                out = Ref{Ptr{Cvoid}}(C_NULL)
                check(D.dnnl_memory_map_data(dst, out), "map dst")
                got = Vector{Float32}(undef, 4)
                unsafe_copyto!(pointer(got), Ptr{Float32}(out[]), 4)
                check(D.dnnl_memory_unmap_data(dst, out[]), "unmap dst")
                @test got == Float32[0, 0, 3, 0]
            finally
                D.dnnl_memory_destroy(src)
                D.dnnl_memory_destroy(dst)
                D.dnnl_memory_desc_destroy(md)
            end
        end
    end
end

end
