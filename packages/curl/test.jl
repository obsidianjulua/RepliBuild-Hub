#!/usr/bin/env julia
# packages/curl/test.jl — exercise the libcurl 8.21.0 (C) wrapper.
#
# Everything here is OFFLINE. libcurl's `file://` protocol drives the same
# easy-handle machinery an HTTP transfer does — setopt → perform → write
# callback → getinfo — so the full path is covered without a network
# dependency that would make this test flaky in CI.
#
# What each testset is really asserting:
#   • varargs         — curl_easy_setopt/getinfo are variadic, and libcurl is
#                       STRICT about the argument's C type per option. curl's
#                       own numbering encodes it: div(option, 10000) is 0 for
#                       long, 1 for pointer/string, 2 for function pointer,
#                       3 for curl_off_t, 4 for blob. Four overloads cover
#                       every option in the library.
#   • Cstring policy  — curl_version() returns a STATIC string (never freed)
#                       while curl_easy_escape() returns a malloc'd one that
#                       MUST be curl_free()d. Two char* returns, opposite
#                       ownership, and the wrapper has to get both right.
#   • error path      — a perform with no URL set must fail loudly.

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Curl.jl")

include(WRAPPER)
using .Curl
const C = Curl

# The wrapper types these properly: options are `CURLoption`, results are
# `CURLcode`, info keys are `CURLINFO`. Use the enums — passing a raw Cint is
# a MethodError, which is the wrapper doing its job.
const OK = C.CURLE_OK

@testset "libcurl 8.21.0 (C)" begin

    @testset "version + build identity" begin
        v = C.curl_version()
        @test v isa AbstractString
        @test occursin("libcurl/8.21.0", v)
        # The lean config: OpenSSL and zlib in, everything else deliberately out.
        @test occursin("OpenSSL", v)
        @test occursin("zlib", v)
        # Dropped by the lean cmake config — if these come back, the checked-in
        # curl_config.h was regenerated with different -D flags.
        @test !occursin("nghttp2", v)
        @test !occursin("libssh2", v)
    end

    # CURLoption is a macro-expanded enum — `CURLOPT(CURLOPT_URL,
    # CURLOPTTYPE_STRINGPOINT, 2)` expands to `CURLOPT_URL = 10002` inside the
    # typedef, so DWARF sees real enumerators and no [wrap.macros] is needed.
    # Asserted separately from the transfer below: if these are missing the
    # transfer fails for a reason that has nothing to do with transfers.
    @testset "CURLoption/CURLINFO enums survived DWARF" begin
        @test Int(C.CURLOPT_URL)            == 10002   # STRINGPOINT   + 2
        @test Int(C.CURLOPT_WRITEFUNCTION)  == 20011   # FUNCTIONPOINT + 11
        @test Int(C.CURLOPT_FOLLOWLOCATION) == 52      # LONG          + 52
        @test Int(C.CURLINFO_SIZE_DOWNLOAD_T) == 0x600000 + 8
        @test Int(C.CURLE_OK) == 0
    end

    @testset "global init/cleanup lifecycle" begin
        @test C.curl_global_init(3) == OK   # CURL_GLOBAL_DEFAULT
        C.curl_global_cleanup()
        @test C.curl_global_init(3) == OK   # re-init must work
    end

    @testset "easy handle lifecycle" begin
        h = C.curl_easy_init()
        @test h != C_NULL
        h2 = C.curl_easy_duphandle(h)
        @test h2 != C_NULL
        C.curl_easy_cleanup(h2)
        C.curl_easy_cleanup(h)
    end

    @testset "strerror is a real string table" begin
        s = C.curl_easy_strerror(OK)
        @test s isa AbstractString
        @test !isempty(s)
        # Distinct codes must give distinct messages — a stub returning one
        # string for everything would pass an isempty check.
        @test C.curl_easy_strerror(C.CURLE_URL_MALFORMAT) != s
    end

    @testset "escape/unescape — malloc'd char*, curl_free ownership" begin
        h = C.curl_easy_init()
        esc = C.curl_easy_escape(h, "a b&c", Cint(0))
        @test esc isa AbstractString
        @test esc == "a%20b%26c"
        C.curl_easy_cleanup(h)
    end

    @testset "file:// transfer — setopt/perform/getinfo end to end" begin
        payload = "RepliBuild curl wrapper transfer test\n" ^ 4
        path = tempname()
        write(path, payload)

        sink = IOBuffer()
        # size*nmemb bytes at `ptr`; return the count consumed or curl aborts.
        # This CAPTURES `sink`, so it is a closure and needs @cfunction's `$`
        # form — the plain form only accepts a top-level function and silently
        # produces a pointer curl cannot call.
        writer = (ptr::Ptr{UInt8}, size::Csize_t, nmemb::Csize_t, ud::Ptr{Cvoid}) -> begin
            n = size * nmemb
            write(sink, unsafe_wrap(Array, ptr, n; own = false))
            return n
        end
        # The `$` form yields a Base.CFunction (a GC-tracked handle), not a raw
        # pointer — unsafe_convert gets the pointer, and the handle must stay
        # alive for as long as curl may call it.
        cb = @cfunction($writer, Csize_t, (Ptr{UInt8}, Csize_t, Csize_t, Ptr{Cvoid}))

        h = C.curl_easy_init()
        @test h != C_NULL
        GC.@preserve sink writer cb begin
            # STRINGPOINT → the Cstring overload; a plain String is accepted
            # because the variadic slot's signature is widened to a Union.
            @test C.curl_easy_setopt_Cstring(h, C.CURLOPT_URL, "file://" * path) == OK
            # FUNCTIONPOINT → the pointer overload
            @test C.curl_easy_setopt_PtrCvoid(h, C.CURLOPT_WRITEFUNCTION, Base.unsafe_convert(Ptr{Cvoid}, cb)) == OK
            # LONG → the Clong overload. Passing an int where curl wants a long
            # is the classic libcurl misuse; the option's number encodes which.
            @test C.curl_easy_setopt_Clong(h, C.CURLOPT_FOLLOWLOCATION, 1) == OK

            @test C.curl_easy_perform(h) == OK
        end
        @test String(take!(sink)) == payload

        got = Ref{Clonglong}(0)
        GC.@preserve got begin
            @test C.curl_easy_getinfo_PtrCvoid(h, C.CURLINFO_SIZE_DOWNLOAD_T,
                Ptr{Cvoid}(Base.unsafe_convert(Ptr{Clonglong}, got))) == OK
        end
        @test got[] == length(payload)

        C.curl_easy_cleanup(h)
        rm(path; force = true)
    end

    @testset "error path: perform with no URL" begin
        h = C.curl_easy_init()
        rc = C.curl_easy_perform(h)
        @test rc != OK          # CURLE_URL_MALFORMAT
        msg = C.curl_easy_strerror(rc)
        @test msg isa AbstractString && !isempty(msg)
        C.curl_easy_cleanup(h)
    end

    C.curl_global_cleanup()
end

println("✓ curl test passed")
