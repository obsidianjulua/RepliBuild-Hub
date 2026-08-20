#!/usr/bin/env julia
# mpack Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
#   - the Write API against the MessagePack SPEC ENCODING itself: for the
#     fixed-layout cases the exact bytes are asserted, which is an oracle
#     independent of mpack's own reader
#   - the Node/tree read API round-tripping everything the writer produces
#   - growable writers and their malloc'd buffer ownership (mpack_writer_destroy
#     hands the buffer over; mpack exports no free wrapper, so libc free it)
#   - error propagation: mpack latches the first error and every later call is
#     a no-op, which is the property that makes its "no error checks needed"
#     style safe — so it has to actually hold
#   - Tier-1 liveness and churn under GC pressure
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/mpack/test_deep.jl

using Test
using InteractiveUtils: code_typed

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Mpack.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const P = Mpack

"""
Run `f(writer_ref)` against a growable writer and return the encoded bytes.

mpack_writer_init_growable hands ownership of a malloc'd buffer to the caller
at destroy time. mpack allocates it through MPACK_MALLOC, which is plain
`malloc` in this build, and exports no `mpack_free` wrapper — so the caller
releases it with libc `free`. Skipping that leaks on every single call.
"""
function encode(f)
    w = Ref(P.mpack_writer_t())
    data = Ref{Ptr{UInt8}}(C_NULL)
    size = Ref{Csize_t}(0)
    P.mpack_writer_init_growable(w, data, size)
    f(w)
    err = P.mpack_writer_destroy(w)
    err == P.mpack_ok || error("writer error: $(P.mpack_error_to_string(err))")
    @assert data[] != C_NULL
    bytes = copy(unsafe_wrap(Vector{UInt8}, data[], Int(size[]); own = false))
    Libc.free(data[])
    return bytes
end

"""
Read a str node's text safely.

`mpack_node_str` returns a `const char*` that points INTO the msgpack buffer and
is **not NUL-terminated** — the length lives in `mpack_node_strlen`. The
generated wrapper marshals `const char*` returns with `unsafe_string(ptr)`,
which keeps reading until it happens to find a zero byte, so
`mpack_node_str(n)` silently returns the right text plus trailing garbage
(observed live: "bottom\\x7f"). Always pair the raw pointer with the length.
"""
function nodestr(node)
    p = P.mpack_node_str_ptr(node)
    p == C_NULL && return nothing
    return unsafe_string(Ptr{UInt8}(p), Int(P.mpack_node_strlen(node)))
end

"Parse `bytes` into a tree, run `f(root)`, always destroy."
function decode(f, bytes::Vector{UInt8})
    tree = Ref(P.mpack_tree_t())
    GC.@preserve bytes begin
        P.mpack_tree_init_data(tree, bytes, length(bytes))
        P.mpack_tree_parse(tree)
        try
            return f(P.mpack_tree_root(tree))
        finally
            P.mpack_tree_destroy(tree)
        end
    end
end

@testset "mpack Deep Tests" begin

@testset "Tier-1 slicing is live" begin
    @test !isempty(P.TIER1_FUNCTIONS)
    slices_dir = joinpath(PKG_DIR, "julia", "slices")
    @test isdir(slices_dir)
    lls = filter(f -> endswith(f, ".ll"), readdir(slices_dir))
    @test length(lls) == length(P.TIER1_FUNCTIONS)
    @test length(lls) > 100
    for f in first(sort(lls), 20)
        @test occursin("define", read(joinpath(slices_dir, f), String))
    end
end

@testset "Encoding matches the MessagePack spec byte for byte" begin
    # These encodings are fixed by the format specification, so asserting the
    # exact bytes checks mpack against the SPEC rather than against itself.
    @test encode(w -> P.mpack_write_nil(w)) == UInt8[0xc0]
    @test encode(w -> P.mpack_write_bool(w, false)) == UInt8[0xc2]
    @test encode(w -> P.mpack_write_bool(w, true)) == UInt8[0xc3]

    # positive fixint 0..127
    @test encode(w -> P.mpack_write_u64(w, UInt64(0))) == UInt8[0x00]
    @test encode(w -> P.mpack_write_u64(w, UInt64(127))) == UInt8[0x7f]
    # uint8 marker
    @test encode(w -> P.mpack_write_u64(w, UInt64(128))) == UInt8[0xcc, 0x80]
    @test encode(w -> P.mpack_write_u64(w, UInt64(255))) == UInt8[0xcc, 0xff]
    # uint16 / uint32 / uint64, all big-endian
    @test encode(w -> P.mpack_write_u64(w, UInt64(256))) == UInt8[0xcd, 0x01, 0x00]
    @test encode(w -> P.mpack_write_u64(w, UInt64(65536))) ==
          UInt8[0xce, 0x00, 0x01, 0x00, 0x00]
    @test encode(w -> P.mpack_write_u64(w, typemax(UInt64))) ==
          vcat(UInt8[0xcf], fill(0xff, 8))

    # negative fixint -32..-1
    @test encode(w -> P.mpack_write_i64(w, Int64(-1))) == UInt8[0xff]
    @test encode(w -> P.mpack_write_i64(w, Int64(-32))) == UInt8[0xe0]
    # int8
    @test encode(w -> P.mpack_write_i64(w, Int64(-33))) == UInt8[0xd0, 0xdf]
    @test encode(w -> P.mpack_write_i64(w, Int64(-128))) == UInt8[0xd0, 0x80]
    # int16
    @test encode(w -> P.mpack_write_i64(w, Int64(-129))) == UInt8[0xd1, 0xff, 0x7f]

    # float64
    @test encode(w -> P.mpack_write_double(w, 1.5)) ==
          vcat(UInt8[0xcb], reverse(collect(reinterpret(UInt8, [1.5]))))

    # fixstr for short strings
    @test encode(w -> P.mpack_write_cstr(w, "abc")) ==
          vcat(UInt8[0xa3], collect(codeunits("abc")))
    # str8 once past 31 bytes
    long = "x"^40
    @test encode(w -> P.mpack_write_cstr(w, long)) ==
          vcat(UInt8[0xd9, 0x28], collect(codeunits(long)))

    # fixarray / fixmap headers
    @test encode(w -> begin
        P.mpack_start_array(w, UInt32(3))
        for i in 1:3
            P.mpack_write_i32(w, Int32(i))
        end
        P.mpack_finish_array(w)
    end) == UInt8[0x93, 0x01, 0x02, 0x03]

    @test encode(w -> begin
        P.mpack_start_map(w, UInt32(1))
        P.mpack_write_cstr(w, "k")
        P.mpack_write_i32(w, Int32(7))
        P.mpack_finish_map(w)
    end) == vcat(UInt8[0x81, 0xa1], collect(codeunits("k")), UInt8[0x07])

    # bin8
    payload = UInt8[0xde, 0xad, 0xbe, 0xef]
    @test encode(w -> P.mpack_write_bin(w, payload, UInt32(length(payload)))) ==
          vcat(UInt8[0xc4, 0x04], payload)
end

@testset "Round-trip through the node API" begin
    bytes = encode() do w
        P.mpack_start_map(w, UInt32(7))

        P.mpack_write_cstr(w, "nil");   P.mpack_write_nil(w)
        P.mpack_write_cstr(w, "yes");   P.mpack_write_bool(w, true)
        P.mpack_write_cstr(w, "int");   P.mpack_write_i64(w, Int64(-123456789))
        P.mpack_write_cstr(w, "uint");  P.mpack_write_u64(w, UInt64(18446744073709551615))
        P.mpack_write_cstr(w, "dbl");   P.mpack_write_double(w, 3.25)
        P.mpack_write_cstr(w, "text");  P.mpack_write_cstr(w, "hello mpack")

        P.mpack_write_cstr(w, "list")
        P.mpack_start_array(w, UInt32(4))
        for i in 1:4
            P.mpack_write_i32(w, Int32(i * 10))
        end
        P.mpack_finish_array(w)

        P.mpack_finish_map(w)
    end

    decode(bytes) do root
        @test P.mpack_node_type(root) == P.mpack_type_map
        @test Int(P.mpack_node_map_count(root)) == 7

        @test P.mpack_node_is_nil(P.mpack_node_map_cstr(root, "nil"))
        @test P.mpack_node_bool(P.mpack_node_map_cstr(root, "yes"))
        @test P.mpack_node_i64(P.mpack_node_map_cstr(root, "int")) == -123456789
        @test P.mpack_node_u64(P.mpack_node_map_cstr(root, "uint")) == typemax(UInt64)
        @test P.mpack_node_double(P.mpack_node_map_cstr(root, "dbl")) == 3.25
        @test nodestr(P.mpack_node_map_cstr(root, "text")) == "hello mpack"
        @test Int(P.mpack_node_strlen(P.mpack_node_map_cstr(root, "text"))) == 11

        list = P.mpack_node_map_cstr(root, "list")
        @test P.mpack_node_type(list) == P.mpack_type_array
        @test Int(P.mpack_node_array_length(list)) == 4
        @test [Int(P.mpack_node_i32(P.mpack_node_array_at(list, i))) for i in 0:3] ==
              [10, 20, 30, 40]

        # Key membership queries.
        @test P.mpack_node_map_contains_cstr(root, "text")
        @test !P.mpack_node_map_contains_cstr(root, "absent")

        # Walking by index must agree with lookup by key.
        n = Int(P.mpack_node_map_count(root))
        keys = [nodestr(P.mpack_node_map_key_at(root, i)) for i in 0:(n - 1)]
        @test "text" in keys && "list" in keys
        idx = findfirst(==("dbl"), keys) - 1
        @test P.mpack_node_double(P.mpack_node_map_value_at(root, idx)) == 3.25

        # An optional lookup on a missing key yields a "missing" node rather
        # than latching an error on the tree.
        miss = P.mpack_node_map_cstr_optional(root, "absent")
        @test P.mpack_node_is_missing(miss)
        @test P.mpack_node_error(root) == P.mpack_ok
    end
end

@testset "Binary data and embedded NULs" begin
    blob = UInt8[0x00, 0x01, 0xff, 0x00, 0x7f]
    withnul = "a\0b"

    bytes = encode() do w
        P.mpack_start_map(w, UInt32(2))
        P.mpack_write_cstr(w, "blob")
        P.mpack_write_bin(w, blob, UInt32(length(blob)))
        P.mpack_write_cstr(w, "s")
        P.mpack_write_str(w, withnul, UInt32(sizeof(withnul)))
        P.mpack_finish_map(w)
    end

    decode(bytes) do root
        b = P.mpack_node_map_cstr(root, "blob")
        @test P.mpack_node_type(b) == P.mpack_type_bin
        @test Int(P.mpack_node_bin_size(b)) == length(blob)
        buf = Vector{UInt8}(undef, length(blob))
        @test Int(P.mpack_node_copy_data(b, buf, length(buf))) == length(blob)
        @test buf == blob

        s = P.mpack_node_map_cstr(root, "s")
        @test P.mpack_node_type(s) == P.mpack_type_str
        # strlen is the authority: the NUL is data, not a terminator.
        @test Int(P.mpack_node_strlen(s)) == 3
        sbuf = Vector{UInt8}(undef, 3)
        @test Int(P.mpack_node_copy_data(s, sbuf, 3)) == 3
        @test sbuf == UInt8[UInt8('a'), 0x00, UInt8('b')]
    end
end

@testset "Deep nesting" begin
    depth = 30
    bytes = encode() do w
        for _ in 1:depth
            P.mpack_start_array(w, UInt32(1))
        end
        P.mpack_write_cstr(w, "bottom")
        for _ in 1:depth
            P.mpack_finish_array(w)
        end
    end

    decode(bytes) do root
        node = root
        for _ in 1:depth
            @test P.mpack_node_type(node) == P.mpack_type_array
            @test Int(P.mpack_node_array_length(node)) == 1
            node = P.mpack_node_array_at(node, 0)
        end
        @test nodestr(node) == "bottom"
    end
end

@testset "Error latching" begin
    # mpack's whole ergonomics rest on this: after the first error every later
    # call is a no-op and the error is still there at destroy time. If that
    # didn't hold, the "write without checking" style would corrupt silently.
    w = Ref(P.mpack_writer_t())
    buf = Vector{UInt8}(undef, 4)          # deliberately far too small
    P.mpack_writer_init(w, buf, length(buf))
    P.mpack_write_cstr(w, "x"^100)
    err = P.mpack_writer_error(w)
    @test err != P.mpack_ok
    # Further writes must not crash and must not clear the error.
    P.mpack_write_i32(w, Int32(1))
    P.mpack_write_nil(w)
    @test P.mpack_writer_error(w) == err
    @test P.mpack_writer_destroy(w) == err
    @test !isempty(P.mpack_error_to_string(err))

    # Type errors on the read side latch on the TREE, not just the node.
    bytes = encode(w2 -> P.mpack_write_cstr(w2, "not a number"))
    tree = Ref(P.mpack_tree_t())
    GC.@preserve bytes begin
        P.mpack_tree_init_data(tree, bytes, length(bytes))
        P.mpack_tree_parse(tree)
        root = P.mpack_tree_root(tree)
        @test P.mpack_node_type(root) == P.mpack_type_str
        _ = P.mpack_node_i64(root)         # wrong accessor for a string
        @test P.mpack_node_error(root) == P.mpack_error_type
        @test P.mpack_tree_destroy(tree) == P.mpack_error_type
    end

    # Truncated input is a parse error, not a crash or a partial tree.
    good = encode() do w3
        P.mpack_start_array(w3, UInt32(3))
        for i in 1:3
            P.mpack_write_i32(w3, Int32(i))
        end
        P.mpack_finish_array(w3)
    end
    truncated = good[1:(end - 1)]
    t2 = Ref(P.mpack_tree_t())
    GC.@preserve truncated begin
        P.mpack_tree_init_data(t2, truncated, length(truncated))
        P.mpack_tree_parse(t2)
        @test P.mpack_tree_destroy(t2) != P.mpack_ok
    end

    # Pure garbage.
    junk = UInt8[0xc1, 0xc1, 0xc1, 0xc1]   # 0xc1 is the never-used byte
    t3 = Ref(P.mpack_tree_t())
    GC.@preserve junk begin
        P.mpack_tree_init_data(t3, junk, length(junk))
        P.mpack_tree_parse(t3)
        @test P.mpack_tree_destroy(t3) != P.mpack_ok
    end
end

@testset "Numeric edge cases" begin
    for v in Int64[0, 1, -1, 127, 128, -32, -33, typemax(Int32), typemin(Int32),
                   typemax(Int64), typemin(Int64)]
        bytes = encode(w -> P.mpack_write_i64(w, v))
        decode(bytes) do root
            @test P.mpack_node_i64(root) == v
        end
    end

    for v in UInt64[0, 1, 255, 256, 65535, 65536, typemax(UInt32), typemax(UInt64)]
        bytes = encode(w -> P.mpack_write_u64(w, v))
        decode(bytes) do root
            @test P.mpack_node_u64(root) == v
        end
    end

    for v in [0.0, -0.0, 1.5, -2.25, 1e300, 1e-300, Inf, -Inf]
        bytes = encode(w -> P.mpack_write_double(w, v))
        decode(bytes) do root
            @test P.mpack_node_double(root) === v
        end
    end

    # NaN needs its own comparison.
    nanbytes = encode(w -> P.mpack_write_double(w, NaN))
    decode(nanbytes) do root
        @test isnan(P.mpack_node_double(root))
    end
end

@testset "Churn and GC stress" begin
    # Encode/decode in a tight loop; the growable writer mallocs and we free,
    # so a leaked or double-freed buffer surfaces here rather than silently.
    for i in 1:2000
        bytes = encode() do w
            P.mpack_start_map(w, UInt32(2))
            P.mpack_write_cstr(w, "i");   P.mpack_write_i32(w, Int32(i))
            P.mpack_write_cstr(w, "s");   P.mpack_write_cstr(w, "value $i")
            P.mpack_finish_map(w)
        end
        decode(bytes) do root
            @assert Int(P.mpack_node_i32(P.mpack_node_map_cstr(root, "i"))) == i
            @assert nodestr(P.mpack_node_map_cstr(root, "s")) == "value $i"
        end
        iszero(i % 500) && GC.gc()
    end
    @test true

    # Larger documents, to move the growable buffer through several reallocs.
    for i in 1:100
        n = 500
        bytes = encode() do w
            P.mpack_start_array(w, UInt32(n))
            for k in 1:n
                P.mpack_write_i64(w, Int64(k * i))
            end
            P.mpack_finish_array(w)
        end
        decode(bytes) do root
            @assert Int(P.mpack_node_array_length(root)) == n
            @assert P.mpack_node_i64(P.mpack_node_array_at(root, n - 1)) == n * i
        end
        iszero(i % 25) && GC.gc()
    end
    @test true
end

end  # top-level testset
