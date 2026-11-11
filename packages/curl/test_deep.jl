#!/usr/bin/env julia
# curl Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
# Everything here is OFFLINE: file:// and the URL API drive the same easy /
# multi / slist / escape machinery an HTTP transfer does, without a network
# dependency that would make this flaky.
#
#   - harvest canary: curl_version / curl_version_info must match the lean
#     checked-in curl_config.h (OpenSSL + zlib, no nghttp2/brotli/zstd/ssh).
#     A stale or foreign config.h compiles, links and wraps clean — it just
#     quietly stops being this curl. Only behaviour catches that.
#   - CURL_VERSION_* / CURL_GLOBAL_DEFAULT macro shims vs the runtime bits
#   - CURLoption numbering: div(option, 10000) is the C type tag the
#     four varargs overloads are keyed on
#   - Cstring policy: curl_version is STATIC; curl_easy_escape is malloc'd
#     and [wrap.cstring_owned] must curl_free after the Julia copy
#   - file:// setopt → write-callback → perform → getinfo, including RANGE
#     (STRINGPOINT) and INFILESIZE_LARGE (OFF_T / Clonglong)
#   - URL API parse / get / set / dup / malform
#   - slist append + walk
#   - multi: two file:// handles to DONE
#   - error paths, reset, strerror, mprintf, getdate
#   - Tier 1 is OFF (quarantined); this package is pure ccall
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/curl/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Curl.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const C = Curl
const OK = C.CURLE_OK

# ── C callbacks (must be top-level, non-closure, for @cfunction) ─────────────

const WRITE_SINK = IOBuffer()
reset_sink!() = (truncate(WRITE_SINK, 0); seekstart(WRITE_SINK); nothing)
function write_cb(ptr::Ptr{UInt8}, size::Csize_t, nmemb::Csize_t, ::Ptr{Cvoid})::Csize_t
    n = size * nmemb
    write(WRITE_SINK, unsafe_wrap(Array, ptr, n; own = false))
    return n
end

const WRITE_SEEN = Ref(0)
function write_abort_cb(ptr::Ptr{UInt8}, size::Csize_t, nmemb::Csize_t, ::Ptr{Cvoid})::Csize_t
    WRITE_SEEN[] += 1
    return Csize_t(0)   # short write → CURLE_WRITE_ERROR
end

# ── Helpers ──────────────────────────────────────────────────────────────────

function protocols(info)
    out = String[]
    p = info.protocols
    p == C_NULL && return out
    i = 1
    while true
        s = unsafe_load(p, i)
        s == C_NULL && break
        push!(out, unsafe_string(s))
        i += 1
    end
    return out
end

function feature_names(info)
    out = String[]
    p = info.feature_names
    p == C_NULL && return out
    i = 1
    while true
        s = unsafe_load(p, i)
        s == C_NULL && break
        push!(out, unsafe_string(s))
        i += 1
    end
    return out
end

function url_get(u, part; flags::Integer = 0)
    p = Ref{Ptr{UInt8}}(C_NULL)
    rc = C.curl_url_get(u, part, p, flags)
    rc != C.CURLUE_OK && return (rc, nothing)
    s = p[] == C_NULL ? nothing : unsafe_string(p[])
    p[] == C_NULL || C.curl_free(p[])
    return (rc, s)
end

function slist_values(head::Ptr{C.curl_slist})
    out = String[]
    p = head
    while p != C_NULL
        n = unsafe_load(p)
        n.data != C_NULL && push!(out, unsafe_string(n.data))
        p = n.next
    end
    return out
end

function with_file(f, payload::AbstractString)
    path = tempname()
    write(path, payload)
    try
        return f(path, "file://" * path)
    finally
        rm(path; force = true)
    end
end

@testset "curl Deep Tests" begin

@testset "Harvest pin — lean curl_config.h" begin
    # The header is a snapshot of THIS machine's feature probes. A wrong
    # USE_* compiles, wraps, and still returns a version string — just not
    # this library. The version line is the runtime twin of the checked-in
    # defines.
    v = C.curl_version()
    @test v isa AbstractString
    @test occursin("libcurl/8.21.0", v)
    @test occursin("OpenSSL", v)
    @test occursin("zlib", v)
    @test !occursin("nghttp2", v)
    @test !occursin("libssh2", v)
    @test !occursin("brotli", v)
    @test !occursin("zstd", lowercase(v))

    # CURLVERSION_NOW is a #define alias of the latest enumerator; DWARF
    # has the enumerators, not the alias. TWELFTH is NOW in 8.21.0.
    info = unsafe_load(C.curl_version_info(C.CURLVERSION_TWELFTH))
    # Git checkouts of a tagged curl report "8.21.0-DEV"; the numeric
    # triple is the pin that does not grow a suffix.
    @test startswith(unsafe_string(info.version), "8.21.0")
    @test info.version_num == 0x081500
    @test info.ssl_version != C_NULL
    @test occursin("OpenSSL", unsafe_string(info.ssl_version))
    @test info.libz_version != C_NULL
    @test !isempty(unsafe_string(info.libz_version))
    @test info.nghttp2_version == C_NULL
    @test info.brotli_version == C_NULL
    @test info.zstd_version == C_NULL
    @test info.libssh_version == C_NULL

    feats = Int(info.features)
    @test feats & C.CURL_VERSION_SSL()  != 0
    @test feats & C.CURL_VERSION_LIBZ() != 0
    @test feats & C.CURL_VERSION_HTTP2()  == 0
    @test feats & C.CURL_VERSION_BROTLI() == 0
    @test feats & C.CURL_VERSION_ZSTD()   == 0

    names = feature_names(info)
    @test "SSL" in names
    @test "libz" in names
    @test !("HTTP2" in names)
    @test !("brotli" in names)
    @test !("zstd" in names)

    protos = protocols(info)
    @test "http" in protos
    @test "https" in protos
    @test "file" in protos
    @test "ftp" in protos
    @test !("ldaps" in protos)
    @test !("scp" in protos)
    @test !("sftp" in protos)

    # Macro shims. CURL_GLOBAL_DEFAULT is SSL|WIN32 = 3 on this header.
    @test C.CURL_GLOBAL_DEFAULT() == 3
    @test C.CURL_ERROR_SIZE() == 256
    @test C.CURL_VERSION_SSL()    == 1 << 2
    @test C.CURL_VERSION_LIBZ()   == 1 << 3
    @test C.CURL_VERSION_HTTP2()  == 1 << 16
    @test C.CURL_VERSION_BROTLI() == 1 << 23
    @test C.CURL_VERSION_ZSTD()   == 1 << 26
    @test C.CURL_VERSION_IPV6()   == 1 << 0
end

@testset "Tier 1 is OFF — pure ccall" begin
    for n in (:TIER1_FUNCTIONS, :TIER1_DECLARES, :_TIER1_KERNEL, :_slice_symbols_resolve)
        @test !isdefined(C, n)
    end
    @test !isdir(joinpath(PKG_DIR, "julia", "slices"))
    src = read(WRAPPER, String)
    @test !occursin("@generated function _TIER1_", src)
    @test !occursin("const _SLICE_", src)
    @test !occursin("llvmcall", src)
    @test !isdefined(C, :DISPATCH_TIER)
    @test !isdefined(C, :dispatch_tier)
    @test occursin("Every function in this module dispatches through Tier 3", src)
end

@testset "CURLoption numbering is the varargs type tag" begin
    # CURLOPT(name, type, n) → name = type + n. The four overloads in
    # [wrap.varargs] are keyed on div(option, 10000).
    @test Int(C.CURLOPT_FOLLOWLOCATION) == 52          # LONG
    @test Int(C.CURLOPT_URL)            == 10002       # STRINGPOINT
    @test Int(C.CURLOPT_RANGE)          == 10007       # STRINGPOINT
    @test Int(C.CURLOPT_WRITEFUNCTION)  == 20011       # FUNCTIONPOINT
    @test Int(C.CURLOPT_WRITEDATA)      == 10001       # OBJECTPOINT
    @test Int(C.CURLOPT_INFILESIZE_LARGE) == 30115     # OFF_T
    @test Int(C.CURLINFO_SIZE_DOWNLOAD_T) == 0x600000 + 8
    @test Int(C.CURLE_OK) == 0
    @test div(Int(C.CURLOPT_FOLLOWLOCATION), 10000) == 0
    @test div(Int(C.CURLOPT_URL), 10000)            == 1
    @test div(Int(C.CURLOPT_WRITEFUNCTION), 10000)  == 2
    @test div(Int(C.CURLOPT_INFILESIZE_LARGE), 10000) == 3
end

@testset "Layout of the public aggregates" begin
    @test C.struct_size(:curl_slist) == 16
    @test C.member_offset(:curl_slist, :data) == 0
    @test C.member_offset(:curl_slist, :next) == 8
    @test fieldnames(C.curl_slist) === (:data, :next)

    @test C.struct_size(:curl_version_info_data) == 216
    @test C.member_offset(:curl_version_info_data, :version) == 8
    @test C.member_offset(:curl_version_info_data, :features) == 32
    @test C.member_offset(:curl_version_info_data, :protocols) == 64

    @test C.struct_size(:curl_blob) == 24
    @test C.member_offset(:curl_blob, :data) == 0
    @test C.member_offset(:curl_blob, :len) == 8

    @test C.struct_size(:CURLMsg) == 24
end

@testset "global init uses the shimmed default" begin
    @test C.curl_global_init(C.CURL_GLOBAL_DEFAULT()) == OK
    C.curl_global_cleanup()
    @test C.curl_global_init(C.CURL_GLOBAL_DEFAULT()) == OK
end

@testset "easy handle lifecycle + reset" begin
    h = C.curl_easy_init()
    @test h != C_NULL
    h2 = C.curl_easy_duphandle(h)
    @test h2 != C_NULL && h2 != h
    C.curl_easy_reset(h)
    C.curl_easy_cleanup(h2)
    C.curl_easy_cleanup(h)
end

@testset "strerror is a real string table" begin
    s0 = C.curl_easy_strerror(OK)
    @test s0 isa AbstractString && !isempty(s0)
    s1 = C.curl_easy_strerror(C.CURLE_URL_MALFORMAT)
    s2 = C.curl_easy_strerror(C.CURLE_WRITE_ERROR)
    @test s1 != s0
    @test s2 != s0
    @test s1 != s2
    @test C.curl_url_strerror(C.CURLUE_MALFORMED_INPUT) isa AbstractString
    @test C.curl_multi_strerror(C.CURLM_BAD_HANDLE) isa AbstractString
end

@testset "escape/unescape — owned char* via curl_free" begin
    h = C.curl_easy_init()
    try
        esc = C.curl_easy_escape(h, "a b&c", 0)
        @test esc == "a%20b%26c"
        # NUL inside the input is length-bounded, not C-string-bounded.
        raw = Vector{UInt8}("x\0y")
        esc2 = C.curl_easy_escape(h, raw, 3)
        @test esc2 == "x%00y"
        back = C.curl_easy_unescape(h, esc, 0, C_NULL)
        @test back == "a b&c"
        # _ptr sibling still exists so a caller who wants the C buffer
        # (and will curl_free it themselves) can.
        @test isdefined(C, :curl_easy_escape_ptr)
        p = C.curl_easy_escape_ptr(h, "a b", 0)
        @test p != C_NULL
        @test unsafe_string(p) == "a%20b"
        C.curl_free(Ptr{Cvoid}(p))
    finally
        C.curl_easy_cleanup(h)
    end
end

@testset "file:// transfer — setopt / write callback / getinfo" begin
    payload = "RepliBuild curl wrapper transfer test\n" ^ 4
    with_file(payload) do path, url
        reset_sink!()
        cb = @cfunction(write_cb, Csize_t, (Ptr{UInt8}, Csize_t, Csize_t, Ptr{Cvoid}))
        h = C.curl_easy_init()
        try
            @test C.curl_easy_setopt_Cstring(h, C.CURLOPT_URL, url) == OK
            @test C.curl_easy_setopt_PtrCvoid(h, C.CURLOPT_WRITEFUNCTION,
                Base.unsafe_convert(Ptr{Cvoid}, cb)) == OK
            @test C.curl_easy_setopt_Clong(h, C.CURLOPT_FOLLOWLOCATION, 1) == OK
            @test C.curl_easy_setopt_Clong(h, C.CURLOPT_VERBOSE, 0) == OK
            @test C.curl_easy_perform(h) == OK
            @test String(take!(WRITE_SINK)) == payload

            got = Ref{Clonglong}(0)
            @test C.curl_easy_getinfo_PtrCvoid(h, C.CURLINFO_SIZE_DOWNLOAD_T,
                Ptr{Cvoid}(Base.unsafe_convert(Ptr{Clonglong}, got))) == OK
            @test got[] == length(payload)

            scheme = Ref{Ptr{UInt8}}(C_NULL)
            @test C.curl_easy_getinfo_PtrCvoid(h, C.CURLINFO_SCHEME,
                Ptr{Cvoid}(Base.unsafe_convert(Ptr{Ptr{UInt8}}, scheme))) == OK
            @test unsafe_string(scheme[]) == "file"
        finally
            C.curl_easy_cleanup(h)
        end
    end
end

@testset "STRINGPOINT RANGE and OFF_T INFILESIZE_LARGE" begin
    payload = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    with_file(payload) do path, url
        reset_sink!()
        cb = @cfunction(write_cb, Csize_t, (Ptr{UInt8}, Csize_t, Csize_t, Ptr{Cvoid}))
        h = C.curl_easy_init()
        try
            @test C.curl_easy_setopt_Cstring(h, C.CURLOPT_URL, url) == OK
            @test C.curl_easy_setopt_PtrCvoid(h, C.CURLOPT_WRITEFUNCTION,
                Base.unsafe_convert(Ptr{Cvoid}, cb)) == OK
            # STRINGPOINT: "start-end" inclusive
            @test C.curl_easy_setopt_Cstring(h, C.CURLOPT_RANGE, "4-8") == OK
            # OFF_T overload — a real 64-bit slot, not a truncated long
            @test C.curl_easy_setopt_Clonglong(h, C.CURLOPT_INFILESIZE_LARGE,
                length(payload)) == OK
            @test C.curl_easy_perform(h) == OK
            @test String(take!(WRITE_SINK)) == "EFGHI"
        finally
            C.curl_easy_cleanup(h)
        end
    end
end

@testset "write callback abort" begin
    with_file("hello world") do path, url
        WRITE_SEEN[] = 0
        cb = @cfunction(write_abort_cb, Csize_t, (Ptr{UInt8}, Csize_t, Csize_t, Ptr{Cvoid}))
        h = C.curl_easy_init()
        try
            C.curl_easy_setopt_Cstring(h, C.CURLOPT_URL, url)
            C.curl_easy_setopt_PtrCvoid(h, C.CURLOPT_WRITEFUNCTION,
                Base.unsafe_convert(Ptr{Cvoid}, cb))
            rc = C.curl_easy_perform(h)
            @test rc == C.CURLE_WRITE_ERROR
            @test WRITE_SEEN[] >= 1
            @test !isempty(C.curl_easy_strerror(rc))
        finally
            C.curl_easy_cleanup(h)
        end
    end
end

@testset "URL API parse / get / set / dup" begin
    u = C.curl_url()
    @test u != C_NULL
    try
        @test C.curl_url_set(u, C.CURLUPART_URL,
            "https://user:pass@example.com:8443/a/b?x=1&y=2#frag", 0) == C.CURLUE_OK
        @test url_get(u, C.CURLUPART_SCHEME) == (C.CURLUE_OK, "https")
        @test url_get(u, C.CURLUPART_USER)   == (C.CURLUE_OK, "user")
        @test url_get(u, C.CURLUPART_HOST)   == (C.CURLUE_OK, "example.com")
        @test url_get(u, C.CURLUPART_PORT)   == (C.CURLUE_OK, "8443")
        @test url_get(u, C.CURLUPART_PATH)   == (C.CURLUE_OK, "/a/b")
        @test url_get(u, C.CURLUPART_QUERY)  == (C.CURLUE_OK, "x=1&y=2")
        @test url_get(u, C.CURLUPART_FRAGMENT) == (C.CURLUE_OK, "frag")

        @test C.curl_url_set(u, C.CURLUPART_HOST, "other.test", 0) == C.CURLUE_OK
        @test url_get(u, C.CURLUPART_HOST) == (C.CURLUE_OK, "other.test")

        u2 = C.curl_url_dup(u)
        @test u2 != C_NULL && u2 != u
        try
            @test url_get(u2, C.CURLUPART_HOST) == (C.CURLUE_OK, "other.test")
        finally
            C.curl_url_cleanup(u2)
        end

        @test C.curl_url_set(u, C.CURLUPART_PORT, "99999", 0) == C.CURLUE_BAD_PORT_NUMBER
        @test C.curl_url_strerror(C.CURLUE_BAD_PORT_NUMBER) !=
              C.curl_url_strerror(C.CURLUE_OK)
    finally
        C.curl_url_cleanup(u)
    end
end

@testset "slist append + walk" begin
    list = C.curl_slist_append(C_NULL, "Accept: text/plain")
    @test list != C_NULL
    list = C.curl_slist_append(list, "X-Test: 1")
    list = C.curl_slist_append(list, "X-Test: 2")
    try
        @test slist_values(list) == ["Accept: text/plain", "X-Test: 1", "X-Test: 2"]
    finally
        C.curl_slist_free_all(list)
    end
end

@testset "multi: two file:// handles to DONE" begin
    a = "alpha-payload"
    b = "bravo-payload-longer"
    with_file(a) do _, url_a
        with_file(b) do _, url_b
            reset_sink!()
            cb = @cfunction(write_cb, Csize_t, (Ptr{UInt8}, Csize_t, Csize_t, Ptr{Cvoid}))
            ha = C.curl_easy_init()
            hb = C.curl_easy_init()
            m  = C.curl_multi_init()
            try
                C.curl_easy_setopt_Cstring(ha, C.CURLOPT_URL, url_a)
                C.curl_easy_setopt_PtrCvoid(ha, C.CURLOPT_WRITEFUNCTION,
                    Base.unsafe_convert(Ptr{Cvoid}, cb))
                C.curl_easy_setopt_Cstring(hb, C.CURLOPT_URL, url_b)
                C.curl_easy_setopt_PtrCvoid(hb, C.CURLOPT_WRITEFUNCTION,
                    Base.unsafe_convert(Ptr{Cvoid}, cb))
                @test C.curl_multi_add_handle(m, ha) == C.CURLM_OK
                @test C.curl_multi_add_handle(m, hb) == C.CURLM_OK

                still = Ref{Cint}(1)
                spins = 0
                while still[] > 0
                    rc = C.curl_multi_perform(m, still)
                    @test rc == C.CURLM_OK
                    spins += 1
                    spins > 100 && error("multi_perform did not drain")
                end

                nleft = Ref{Cint}(0)
                done = 0
                while true
                    msgp = C.curl_multi_info_read(m, nleft)
                    msgp == C_NULL && break
                    msg = unsafe_load(msgp)
                    @test msg.msg == C.CURLMSG_DONE
                    @test msg.data.result == OK
                    done += 1
                end
                @test done == 2
                body = String(take!(WRITE_SINK))
                @test occursin(a, body)
                @test occursin(b, body)
            finally
                C.curl_multi_remove_handle(m, ha)
                C.curl_multi_remove_handle(m, hb)
                C.curl_multi_cleanup(m)
                C.curl_easy_cleanup(ha)
                C.curl_easy_cleanup(hb)
            end
        end
    end
end

@testset "share handle" begin
    sh = C.curl_share_init()
    @test sh != C_NULL
    try
        @test C.curl_share_setopt_Clong(sh, C.CURLSHOPT_SHARE,
            Int(C.CURL_LOCK_DATA_COOKIE)) == C.CURLSHE_OK
        h = C.curl_easy_init()
        try
            @test C.curl_easy_setopt_PtrCvoid(h, C.CURLOPT_SHARE, sh) == OK
        finally
            C.curl_easy_cleanup(h)
        end
    finally
        @test C.curl_share_cleanup(sh) == C.CURLSHE_OK
    end
end

@testset "easy option lookup + mime construct" begin
    opt = unsafe_load(C.curl_easy_option_by_name("URL"))
    @test opt.id == C.CURLOPT_URL
    opt2 = unsafe_load(C.curl_easy_option_by_id(C.CURLOPT_FOLLOWLOCATION))
    @test opt2.id == C.CURLOPT_FOLLOWLOCATION

    h = C.curl_easy_init()
    try
        mime = C.curl_mime_init(h)
        @test mime != C_NULL
        part = C.curl_mime_addpart(mime)
        @test part != C_NULL
        @test C.curl_mime_name(part, "field") == OK
        @test C.curl_mime_data(part, "value", 5) == OK
        @test C.curl_mime_type(part, "text/plain") == OK
        C.curl_mime_free(mime)
    finally
        C.curl_easy_cleanup(h)
    end
end

@testset "mprintf / msnprintf / getdate / strequal" begin
    s = C.curl_maprintf_Cstring_Cint("%s-%d", "rb", 8)
    @test s == "rb-8"

    buf = zeros(UInt8, 32)
    n = C.curl_msnprintf_Cstring(buf, Csize_t(length(buf)), "hello %s", "curl")
    @test n == length("hello curl")
    @test unsafe_string(pointer(buf)) == "hello curl"

    ts = C.curl_getdate("Tue, 19 Oct 2021 10:00:00 GMT", C_NULL)
    @test ts == 1634637600

    @test C.curl_strequal("abc", "abc") != 0
    @test C.curl_strequal("abc", "ABC") != 0   # case-insensitive
    @test C.curl_strequal("abc", "abd") == 0
    @test C.curl_strnequal("abcd", "abCE", 3) != 0
end

@testset "error path: perform with no URL" begin
    h = C.curl_easy_init()
    try
        rc = C.curl_easy_perform(h)
        @test rc == C.CURLE_URL_MALFORMAT
        @test !isempty(C.curl_easy_strerror(rc))
    finally
        C.curl_easy_cleanup(h)
    end
end

@testset "error path: missing file://" begin
    h = C.curl_easy_init()
    try
        C.curl_easy_setopt_Cstring(h, C.CURLOPT_URL, "file:///no/such/curl-deeptest-path")
        rc = C.curl_easy_perform(h)
        @test rc != OK
        @test !isempty(C.curl_easy_strerror(rc))
    finally
        C.curl_easy_cleanup(h)
    end
end

@testset "churn under GC pressure" begin
    payload = "gc-churn"
    with_file(payload) do _, url
        cb = @cfunction(write_cb, Csize_t, (Ptr{UInt8}, Csize_t, Csize_t, Ptr{Cvoid}))
        for i in 1:40
            reset_sink!()
            h = C.curl_easy_init()
            C.curl_easy_setopt_Cstring(h, C.CURLOPT_URL, url)
            C.curl_easy_setopt_PtrCvoid(h, C.CURLOPT_WRITEFUNCTION,
                Base.unsafe_convert(Ptr{Cvoid}, cb))
            @test C.curl_easy_perform(h) == OK
            @test String(take!(WRITE_SINK)) == payload
            C.curl_easy_cleanup(h)
            i % 7 == 0 && GC.gc(false)
        end
    end
end

C.curl_global_cleanup()

end
