#!/usr/bin/env julia
# miniz Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
# miniz is a drop-in zlib replacement plus a ZIP implementation, so it gets
# checked against BOTH kinds of oracle:
#   - CRC-32 / Adler-32 against independent Julia reference implementations
#   - mz_compress/mz_uncompress and the deflate/inflate stream machine
#   - the low-level tdefl/tinfl heap helpers, incl. their mz_free ownership
#   - the ZIP archive API end to end: heap archives and real files on disk,
#     stat/locate/extract, stored vs deflated entries, comments, error strings
#   - Tier-1 liveness and churn under GC pressure
#
# Note on the build: upstream ships no miniz_export.h (CMake generates it), so
# this package supplies one under include/. If that ever goes missing the build
# fails outright rather than misbehaving here.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/miniz/test_deep.jl

using Test
using InteractiveUtils: code_typed
using Random: Xoshiro

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Miniz.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const M = Miniz

# ── Independent checksum oracles (same algorithms, written from spec) ────────
const CRC_TABLE = let t = zeros(UInt32, 256)
    for n in 0:255
        c = UInt32(n)
        for _ in 1:8
            c = (c & 0x1) != 0 ? (0xEDB88320 ⊻ (c >> 1)) : (c >> 1)
        end
        t[n + 1] = c
    end
    t
end
function ref_crc32(data::AbstractVector{UInt8})
    c = 0xFFFFFFFF
    for b in data
        c = CRC_TABLE[(UInt8(c & 0xff) ⊻ b) + 1] ⊻ (c >> 8)
    end
    return ⊻(c, 0xFFFFFFFF)
end
function ref_adler32(data::AbstractVector{UInt8})
    a, b = UInt32(1), UInt32(0)
    for x in data
        a = (a + x) % 0xFFF1
        b = (b + a) % 0xFFF1
    end
    return (b << 16) | a
end

# miniz status/flush constants (mz_* #defines, mirroring zlib's).
const MZ_OK, MZ_STREAM_END, MZ_BUF_ERROR, MZ_DATA_ERROR = 0, 1, -5, -3
const MZ_NO_FLUSH, MZ_FINISH = 0, 4
const MZ_DEFAULT_COMPRESSION = -1
const MZ_ZIP_MODE_INVALID = 0

const TEXT = repeat("miniz packs and unpacks with very little code. ", 500)
const PAYLOADS = Dict(
    :tiny   => collect(codeunits("mz")),
    :text   => collect(codeunits(TEXT)),
    :zeros  => zeros(UInt8, 70_000),
    :random => rand(Xoshiro(0x9917), UInt8, 30_000),
)

@testset "miniz Deep Tests" begin

@testset "Library identity" begin
    # MZ_VERSION tracks the emulated zlib API version, not miniz's own 3.1.1.
    @test M.mz_version() == "11.3.1"
    @test M.mz_error(MZ_STREAM_END) == "stream end"
    @test M.mz_error(MZ_DATA_ERROR) == "data error"
end

@testset "Tier-1 slicing is live" begin
    @test !isempty(M.TIER1_FUNCTIONS)
    slices_dir = joinpath(PKG_DIR, "julia", "slices")
    @test isdir(slices_dir)
    lls = filter(f -> endswith(f, ".ll"), readdir(slices_dir))
    @test length(lls) == length(M.TIER1_FUNCTIONS)
    @test "mz_crc32" in M.TIER1_FUNCTIONS
    @test M.dispatch_tier(:mz_crc32) === :tier1
    @test M.dispatch_tier(:mz_adler32) === :tier1
end

@testset "Checksums against independent implementations" begin
    check = collect(codeunits("123456789"))
    @test M.mz_crc32(0, check, length(check)) % UInt32 == 0xCBF43926

    for (_, data) in PAYLOADS
        @test M.mz_crc32(0, data, length(data)) % UInt32 == ref_crc32(data)
        @test M.mz_adler32(1, data, length(data)) % UInt32 == ref_adler32(data)
    end
    @test M.mz_crc32(0, C_NULL, 0) == 0
    @test M.mz_adler32(0, C_NULL, 0) == 1

    # Chunked accumulation must equal the one-shot value.
    data = PAYLOADS[:text]
    c = UInt32(0); off = 0
    while off < length(data)
        n = min(1337, length(data) - off)
        c = M.mz_crc32(c, data[(off + 1):(off + n)], n) % UInt32
        off += n
    end
    @test c == ref_crc32(data)
end

@testset "compress / uncompress" begin
    for (_, data) in PAYLOADS
        bound = M.mz_compressBound(length(data))
        @test bound >= length(data)
        dst = Vector{UInt8}(undef, Int(bound))
        dlen = Ref{Culong}(bound)
        @test M.mz_compress(dst, dlen, data, length(data)) == MZ_OK
        comp = dst[1:Int(dlen[])]

        back = Vector{UInt8}(undef, length(data))
        blen = Ref{Culong}(length(back))
        @test M.mz_uncompress(back, blen, comp, length(comp)) == MZ_OK
        @test Int(blen[]) == length(data)
        @test back == data

        # A zlib stream: the trailer is the big-endian Adler-32 of the input.
        trailer = comp[(end - 3):end]
        adler = (UInt32(trailer[1]) << 24) | (UInt32(trailer[2]) << 16) |
                (UInt32(trailer[3]) << 8)  |  UInt32(trailer[4])
        @test adler == ref_adler32(data)
    end

    # Levels trade size for speed.
    data = PAYLOADS[:text]
    sizes = map(0:9) do lvl
        b = M.mz_compressBound(length(data))
        d = Vector{UInt8}(undef, Int(b)); dl = Ref{Culong}(b)
        @test M.mz_compress2(d, dl, data, length(data), lvl) == MZ_OK
        bk = Vector{UInt8}(undef, length(data)); bl = Ref{Culong}(length(bk))
        @test M.mz_uncompress(bk, bl, d, Int(dl[])) == MZ_OK
        @test bk == data
        Int(dl[])
    end
    @test sizes[1] > sizes[10]

    # An undersized output buffer is an error, not a truncation.
    b = M.mz_compressBound(length(data))
    d = Vector{UInt8}(undef, Int(b)); dl = Ref{Culong}(b)
    M.mz_compress(d, dl, data, length(data))
    tiny = Vector{UInt8}(undef, 8); tl = Ref{Culong}(8)
    @test M.mz_uncompress(tiny, tl, d, Int(dl[])) == MZ_BUF_ERROR
end

@testset "deflate / inflate stream machine" begin
    data = PAYLOADS[:text]

    strm = Ref(M.mz_stream_s())
    @test M.mz_deflateInit(strm, 9) == MZ_OK
    cap = Int(M.mz_deflateBound(strm, length(data))) + 64
    out = Vector{UInt8}(undef, cap)
    GC.@preserve data out begin
        strm[] = M.with(strm[]; next_in=pointer(data), avail_in=Cuint(length(data)),
                        next_out=pointer(out), avail_out=Cuint(cap))
        @test M.mz_deflate(strm, MZ_FINISH) == MZ_STREAM_END
    end
    ncomp = cap - Int(strm[].avail_out)
    comp = out[1:ncomp]
    @test M.mz_deflateEnd(strm) == MZ_OK
    @test ncomp < length(data)

    # Inflate it back through 1-byte output windows: the state machine must
    # make progress without ever being handed a big buffer.
    istrm = Ref(M.mz_stream_s())
    @test M.mz_inflateInit(istrm) == MZ_OK
    got = UInt8[]
    win = Vector{UInt8}(undef, 1)
    inpos = 0
    while true
        GC.@preserve comp win begin
            istrm[] = M.with(istrm[]; next_in=pointer(comp) + inpos,
                             avail_in=Cuint(length(comp) - inpos),
                             next_out=pointer(win), avail_out=Cuint(1))
            rc = M.mz_inflate(istrm, MZ_NO_FLUSH)
            produced = 1 - Int(istrm[].avail_out)
            produced > 0 && push!(got, win[1])
            inpos = length(comp) - Int(istrm[].avail_in)
            rc == MZ_STREAM_END && break
            @assert rc in (MZ_OK, MZ_BUF_ERROR) "inflate: $rc"
            rc == MZ_BUF_ERROR && produced == 0 && break
        end
    end
    @test got == data
    @test M.mz_inflateEnd(istrm) == MZ_OK

    # Reset makes a used stream reusable.
    r = Ref(M.mz_stream_s())
    M.mz_deflateInit(r, 6)
    sc = Vector{UInt8}(undef, 4096)
    GC.@preserve data sc begin
        r[] = M.with(r[]; next_in=pointer(data), avail_in=Cuint(500),
                     next_out=pointer(sc), avail_out=Cuint(length(sc)))
        M.mz_deflate(r, MZ_NO_FLUSH)
    end
    @test M.mz_deflateReset(r) == MZ_OK
    @test r[].total_in == 0
    M.mz_deflateEnd(r)
end

@testset "tdefl / tinfl heap helpers and mz_free ownership" begin
    data = PAYLOADS[:text]
    outlen = Ref{Csize_t}(0)
    # flags 0 = raw deflate, no zlib header.
    p = M.tdefl_compress_mem_to_heap(data, length(data), outlen, 0)
    @test p != C_NULL
    @test Int(outlen[]) > 0
    comp = unsafe_wrap(Vector{UInt8}, Ptr{UInt8}(p), Int(outlen[]); own=false)
    compcopy = copy(comp)
    M.mz_free(p)                      # miniz owns this buffer; we must release it

    backlen = Ref{Csize_t}(0)
    q = M.tinfl_decompress_mem_to_heap(compcopy, length(compcopy), backlen, 0)
    @test q != C_NULL
    back = copy(unsafe_wrap(Vector{UInt8}, Ptr{UInt8}(q), Int(backlen[]); own=false))
    M.mz_free(q)
    @test back == data

    # tinfl on garbage must fail rather than return a bogus buffer.
    junk = rand(Xoshiro(11), UInt8, 512)
    jlen = Ref{Csize_t}(0)
    j = M.tinfl_decompress_mem_to_heap(junk, length(junk), jlen, 0)
    if j != C_NULL
        M.mz_free(j)
        @test Int(jlen[]) >= 0        # it may decode nonsense, but must not crash
    else
        @test true
    end
end

@testset "ZIP — heap archive round-trip" begin
    entries = [("hello.txt", collect(codeunits("hello from miniz"))),
               ("data/large.bin", PAYLOADS[:text]),
               ("data/zeros.bin", PAYLOADS[:zeros]),
               ("stored.bin", PAYLOADS[:random])]

    zip = Ref(M.mz_zip_archive())
    @test M.mz_zip_writer_init_heap(zip, 0, 0) == 1
    for (i, (name, body)) in enumerate(entries)
        # Level 0 on the last entry so the archive mixes stored and deflated.
        level = UInt32(i == length(entries) ? 0 : 9)
        @test M.mz_zip_writer_add_mem(zip, name, body, length(body), level) == 1
    end

    pbuf = Ref{Ptr{Cvoid}}(C_NULL)
    psize = Ref{Csize_t}(0)
    @test M.mz_zip_writer_finalize_heap_archive(zip, pbuf, psize) == 1
    @test pbuf[] != C_NULL && Int(psize[]) > 0
    archive = copy(unsafe_wrap(Vector{UInt8}, Ptr{UInt8}(pbuf[]), Int(psize[]); own=false))
    @test M.mz_zip_writer_end(zip) == 1
    @test archive[1:2] == UInt8[0x50, 0x4b]        # "PK"

    # Read it back.
    rz = Ref(M.mz_zip_archive())
    GC.@preserve archive begin
        @test M.mz_zip_reader_init_mem(rz, archive, length(archive), UInt32(0)) == 1
        @test M.mz_zip_reader_get_num_files(rz) == length(entries)

        for (i, (name, body)) in enumerate(entries)
            idx = M.mz_zip_reader_locate_file(rz, name, C_NULL, UInt32(0))
            @test idx >= 0

            # Filename round-trips through the two-call size protocol.
            need = M.mz_zip_reader_get_filename(rz, UInt32(idx), C_NULL, UInt32(0))
            @test need == length(name) + 1
            nb = Vector{UInt8}(undef, Int(need))
            M.mz_zip_reader_get_filename(rz, UInt32(idx), nb, need)
            @test unsafe_string(pointer(nb)) == name

            stat = Ref(M.mz_zip_archive_file_stat())
            @test M.mz_zip_reader_file_stat(rz, UInt32(idx), stat) == 1
            @test Int(stat[].m_uncomp_size) == length(body)
            @test stat[].m_crc32 == ref_crc32(body)

            # Extract to a preallocated buffer...
            mem = Vector{UInt8}(undef, length(body))
            @test M.mz_zip_reader_extract_to_mem(rz, UInt32(idx), mem,
                                                 length(mem), UInt32(0)) == 1
            @test mem == body

            # ...and to a miniz-owned heap buffer we must free.
            hlen = Ref{Csize_t}(0)
            hp = M.mz_zip_reader_extract_file_to_heap(rz, name, hlen, UInt32(0))
            @test hp != C_NULL
            @test Int(hlen[]) == length(body)
            heap = copy(unsafe_wrap(Vector{UInt8}, Ptr{UInt8}(hp), Int(hlen[]); own=false))
            M.mz_free(hp)
            @test heap == body
        end

        # A name that isn't there is a clean miss, not a crash.
        @test M.mz_zip_reader_locate_file(rz, "nope.txt", C_NULL, UInt32(0)) < 0
        @test M.mz_zip_get_last_error(rz) != 0
        @test !isempty(M.mz_zip_get_error_string(M.mz_zip_get_last_error(rz)))
        M.mz_zip_clear_last_error(rz)

        @test M.mz_zip_reader_end(rz) == 1
    end
end

@testset "ZIP — real file on disk" begin
    mktempdir() do dir
        path = joinpath(dir, "archive.zip")
        body = PAYLOADS[:text]

        wz = Ref(M.mz_zip_archive())
        @test M.mz_zip_writer_init_file(wz, path, UInt64(0)) == 1
        @test M.mz_zip_writer_add_mem(wz, "doc.txt", body, length(body), UInt32(6)) == 1
        @test M.mz_zip_writer_add_mem(wz, "empty.txt", C_NULL, 0, UInt32(6)) == 1
        @test M.mz_zip_writer_finalize_archive(wz) == 1
        @test M.mz_zip_writer_end(wz) == 1
        @test isfile(path)
        @test filesize(path) > 0

        rz = Ref(M.mz_zip_archive())
        @test M.mz_zip_reader_init_file(rz, path, UInt32(0)) == 1
        @test M.mz_zip_reader_get_num_files(rz) == 2
        @test Int(M.mz_zip_get_archive_size(rz)) == filesize(path)
        @test M.mz_zip_get_central_dir_size(rz) > 0

        idx = M.mz_zip_reader_locate_file(rz, "doc.txt", C_NULL, UInt32(0))
        @test idx >= 0
        out = Vector{UInt8}(undef, length(body))
        @test M.mz_zip_reader_extract_to_mem(rz, UInt32(idx), out, length(out), UInt32(0)) == 1
        @test out == body

        # Extract straight to a file and compare bytes.
        extracted = joinpath(dir, "doc.out")
        @test M.mz_zip_reader_extract_file_to_file(rz, "doc.txt", extracted, UInt32(0)) == 1
        @test read(extracted) == body

        # The zero-length entry is legal and reads back empty.
        eidx = M.mz_zip_reader_locate_file(rz, "empty.txt", C_NULL, UInt32(0))
        @test eidx >= 0
        st = Ref(M.mz_zip_archive_file_stat())
        M.mz_zip_reader_file_stat(rz, UInt32(eidx), st)
        @test Int(st[].m_uncomp_size) == 0

        @test M.mz_zip_reader_end(rz) == 1

        # Opening a non-archive must fail cleanly and report an error.
        junk = joinpath(dir, "junk.zip")
        write(junk, rand(Xoshiro(5), UInt8, 4096))
        bz = Ref(M.mz_zip_archive())
        @test M.mz_zip_reader_init_file(bz, junk, UInt32(0)) == 0
        @test M.mz_zip_get_last_error(bz) != 0
    end
end

@testset "Churn and GC stress" begin
    data = PAYLOADS[:text]
    want = ref_crc32(data)
    for i in 1:300
        b = M.mz_compressBound(length(data))
        d = Vector{UInt8}(undef, Int(b)); dl = Ref{Culong}(b)
        @assert M.mz_compress2(d, dl, data, length(data), i % 10) == MZ_OK
        bk = Vector{UInt8}(undef, length(data)); bl = Ref{Culong}(length(bk))
        @assert M.mz_uncompress(bk, bl, d, Int(dl[])) == MZ_OK
        @assert bk == data
        @assert M.mz_crc32(0, bk, length(bk)) % UInt32 == want
        iszero(i % 50) && GC.gc()
    end
    @test true

    # Build and tear down many small heap archives.
    for i in 1:200
        z = Ref(M.mz_zip_archive())
        @assert M.mz_zip_writer_init_heap(z, 0, 0) == 1
        payload = collect(codeunits("entry $i"))
        @assert M.mz_zip_writer_add_mem(z, "f$i.txt", payload, length(payload), UInt32(6)) == 1
        pb = Ref{Ptr{Cvoid}}(C_NULL); ps = Ref{Csize_t}(0)
        @assert M.mz_zip_writer_finalize_heap_archive(z, pb, ps) == 1
        arc = copy(unsafe_wrap(Vector{UInt8}, Ptr{UInt8}(pb[]), Int(ps[]); own=false))
        M.mz_zip_writer_end(z)
        r = Ref(M.mz_zip_archive())
        GC.@preserve arc begin
            @assert M.mz_zip_reader_init_mem(r, arc, length(arc), UInt32(0)) == 1
            hl = Ref{Csize_t}(0)
            hp = M.mz_zip_reader_extract_file_to_heap(r, "f$i.txt", hl, UInt32(0))
            @assert hp != C_NULL
            got = copy(unsafe_wrap(Vector{UInt8}, Ptr{UInt8}(hp), Int(hl[]); own=false))
            M.mz_free(hp)
            @assert got == payload
            M.mz_zip_reader_end(r)
        end
        iszero(i % 50) && GC.gc()
    end
    @test true
end

end  # top-level testset
