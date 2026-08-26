#!/usr/bin/env julia
# pcre2 Hub package — integration test
#
# Tests the full RepliBuild pipeline for PCRE2 10.45:
#   clean → build → wrap → load wrapper → exercise API
#
# pcre2 is the Hub's first package unblocked by harvested cmake configure
# output: config.h, the public pcre2.h and pcre2_chartables.c do not exist in a
# bare checkout (see harvest.jl and config/SYSCONFIG.md). So the assertions below
# are doing double duty — they check the wrapper, and they check that a library
# built against a config header RepliBuild did not itself generate is a real,
# correct libpcre2 rather than a self-consistently wrong one. A build with a
# wrong SIZEOF_* or a missing SUPPORT_UNICODE compiles, links and wraps clean;
# it just quietly stops being pcre2. Only behaviour catches that, which is why
# the Unicode property and byte-offset assertions are here.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/pcre2/test.jl

using Test
using RepliBuild

const PKG_DIR   = @__DIR__
const TOML_PATH = joinpath(PKG_DIR, "replibuild.toml")

# ── Build ────────────────────────────────────────────────────────────────────

@testset "PCRE2 Hub Package" begin

@testset "Harvested configure output" begin
    # These three are checked in, not cloned. Without them the build cannot run
    # at all, so assert their presence before anything tries to compile.
    cfg = joinpath(PKG_DIR, "config")
    @test isfile(joinpath(cfg, "config.h"))
    @test isfile(joinpath(cfg, "pcre2.h"))
    @test isfile(joinpath(cfg, "pcre2_chartables.c"))
    @test isfile(joinpath(cfg, "SYSCONFIG.md"))

    # The feature probes the build depends on. SUPPORT_UNICODE in particular is
    # asserted behaviourally further down.
    conf = read(joinpath(cfg, "config.h"), String)
    @test occursin("SUPPORT_UNICODE", conf)
    @test occursin("HAVE_MEMMOVE", conf)

    # The harvested public header must be the one the build sees, NOT the
    # distro's /usr/include/pcre2.h — this machine has both.
    hdr = read(joinpath(cfg, "pcre2.h"), String)
    @test occursin("#define PCRE2_MAJOR           10", hdr)
    @test occursin("#define PCRE2_MINOR           45", hdr)
end

@testset "Build pipeline" begin
    RepliBuild.clean(TOML_PATH)
    lib = RepliBuild.build(TOML_PATH)
    @test isfile(lib)
    @test endswith(lib, "libpcre2.so") || endswith(lib, "libpcre2.dylib")
    @test filesize(lib) > 500_000

    julia_dir = joinpath(PKG_DIR, "julia")
    @test isfile(joinpath(julia_dir, "compilation_metadata.json"))

    wrapper = RepliBuild.wrap(TOML_PATH)
    @test isfile(wrapper)
    @test isfile(joinpath(julia_dir, "Pcre2.jl"))
end

@testset "Compilation metadata" begin
    meta = joinpath(PKG_DIR, "julia", "compilation_metadata.json")
    md = read(meta, String)
    # 29 TUs is the pcre2-8-shared target exactly; the generated chartables TU
    # is one of them and comes from config/, not from the clone.
    @test occursin("pcre2_chartables.c", md)
    @test occursin("pcre2_compile_8", md)
end

# ── Load wrapper ─────────────────────────────────────────────────────────────

include(joinpath(PKG_DIR, "julia", "Pcre2.jl"))
using .Pcre2

@testset "Module structure" begin
    # Core lifecycle
    @test isdefined(Pcre2, :pcre2_compile_8)
    @test isdefined(Pcre2, :pcre2_code_free_8)
    @test isdefined(Pcre2, :pcre2_match_8)
    @test isdefined(Pcre2, :pcre2_match_data_create_from_pattern_8)
    @test isdefined(Pcre2, :pcre2_match_data_free_8)
    @test isdefined(Pcre2, :pcre2_get_ovector_pointer_8)
    @test isdefined(Pcre2, :pcre2_get_error_message_8)

    # Wider surface
    @test isdefined(Pcre2, :pcre2_substitute_8)
    @test isdefined(Pcre2, :pcre2_substring_get_bynumber_8)
    @test isdefined(Pcre2, :pcre2_substring_number_from_name_8)
    @test isdefined(Pcre2, :pcre2_pattern_info_8)
    @test isdefined(Pcre2, :pcre2_dfa_match_8)
    @test isdefined(Pcre2, :pcre2_config_8)

    # Value macros (constants shimmed from pcre2.h)
    @test isdefined(Pcre2, :PCRE2_CASELESS)
    @test isdefined(Pcre2, :PCRE2_MULTILINE)
    @test isdefined(Pcre2, :PCRE2_UTF)
    @test isdefined(Pcre2, :PCRE2_UCP)
    @test isdefined(Pcre2, :PCRE2_ZERO_TERMINATED)
    @test isdefined(Pcre2, :PCRE2_ERROR_NOMATCH)
    @test isdefined(Pcre2, :PCRE2_INFO_CAPTURECOUNT)

    # DWARF recovered real signatures, not zero-arg placeholders.
    @test length(methods(pcre2_compile_8)) >= 1
    @test length(first(methods(pcre2_compile_8)).sig.parameters) == 7  # self + 6 args
end

@testset "Shimmed constants carry the header's values" begin
    # Wrong types here are silent corruption, not an error: PCRE2_ANCHORED is
    # 0x80000000u and wraps to a negative Int if shimmed as `int`, and
    # PCRE2_ZERO_TERMINATED is ~(size_t)0 which becomes -1 the same way.
    @test PCRE2_CASELESS()  == 0x00000008
    @test PCRE2_MULTILINE() == 0x00000400
    @test PCRE2_DOTALL()    == 0x00000020
    @test PCRE2_UTF()       == 0x00080000
    @test PCRE2_ANCHORED()  == 0x80000000
    @test PCRE2_ANCHORED()  > 0
    @test PCRE2_ZERO_TERMINATED() == typemax(Csize_t)
    @test PCRE2_UNSET()           == typemax(Csize_t)
    @test PCRE2_ERROR_NOMATCH()   == -1
    @test PCRE2_ERROR_PARTIAL()   == -2
    @test PCRE2_INFO_CAPTURECOUNT() == 4
end

# ── Behaviour ────────────────────────────────────────────────────────────────

# Compile a pattern or fail the test with pcre2's own diagnostic.
function compile_or_fail(pat::String, options::UInt32=UInt32(0))
    ec = Ref{Cint}(0); eo = Ref{Csize_t}(0)
    code = pcre2_compile_8(pat, ncodeunits(pat), options, ec, eo, C_NULL)
    if code == C_NULL
        buf = Vector{UInt8}(undef, 256)
        n = pcre2_get_error_message_8(ec[], buf, length(buf))
        error("pcre2_compile_8 failed on $(repr(pat)) at offset $(eo[]): " *
              String(buf[1:max(n, 0)]))
    end
    return code
end

# Return the matched groups as byte ranges, or nothing on PCRE2_ERROR_NOMATCH.
function match_groups(code, subj::String; start::Int=0, options::UInt32=UInt32(0))
    md = pcre2_match_data_create_from_pattern_8(code, C_NULL)
    try
        rc = pcre2_match_8(code, subj, ncodeunits(subj), start, options, md, C_NULL)
        rc == PCRE2_ERROR_NOMATCH() && return nothing
        rc < 0 && error("pcre2_match_8 returned $rc")
        ov = pcre2_get_ovector_pointer_8(md)
        return [(Int(unsafe_load(ov, 2i + 1)), Int(unsafe_load(ov, 2i + 2))) for i in 0:rc-1]
    finally
        pcre2_match_data_free_8(md)
    end
end

@testset "Compile and match" begin
    code = compile_or_fail("(\\d+)-(\\d+)")
    try
        subj = "order 123-456 shipped"
        g = match_groups(code, subj)
        @test g !== nothing
        @test length(g) == 3                      # whole match + 2 groups
        @test subj[g[1][1]+1:g[1][2]] == "123-456"
        @test subj[g[2][1]+1:g[2][2]] == "123"
        @test subj[g[3][1]+1:g[3][2]] == "456"
        @test g[1] == (6, 13)                     # byte offsets, not char indices

        @test match_groups(code, "nothing here") === nothing

        # capture count read back through the API
        n = Ref{UInt32}(0)
        rc = pcre2_pattern_info_8(code, PCRE2_INFO_CAPTURECOUNT(), n)
        @test rc == 0
        @test n[] == 2
    finally
        pcre2_code_free_8(code)
    end
end

@testset "Options actually take effect" begin
    plain    = compile_or_fail("hello")
    caseless = compile_or_fail("hello", PCRE2_CASELESS())
    try
        @test match_groups(plain, "say HELLO now")    === nothing
        @test match_groups(caseless, "say HELLO now") !== nothing
        @test match_groups(caseless, "say hello now") !== nothing
    finally
        pcre2_code_free_8(plain)
        pcre2_code_free_8(caseless)
    end

    # MULTILINE changes what ^ anchors to — a behavioural check on an option
    # bit, so a wrong constant value cannot pass by coincidence.
    one  = compile_or_fail("^b")
    many = compile_or_fail("^b", PCRE2_MULTILINE())
    try
        @test match_groups(one,  "a\nbc") === nothing
        @test match_groups(many, "a\nbc") !== nothing
    finally
        pcre2_code_free_8(one)
        pcre2_code_free_8(many)
    end
end

@testset "Unicode support is really compiled in" begin
    # config.h's SUPPORT_UNICODE is a harvested feature probe. If it were wrong,
    # the build would still succeed and \p{L} would fail to compile — exactly
    # the "self-consistently not pcre2" failure the harvest has to avoid.
    code = compile_or_fail("\\p{L}+", PCRE2_UTF() | PCRE2_UCP())
    try
        subj = "123 héllo 456"
        g = match_groups(code, subj)
        @test g !== nothing
        # é is 2 bytes in UTF-8, so this also pins the byte-offset semantics.
        s, e = g[1]
        @test String(codeunits(subj)[s+1:e]) == "héllo"
    finally
        pcre2_code_free_8(code)
    end
end

@testset "Substring extraction" begin
    code = compile_or_fail("(?<year>\\d{4})-(?<month>\\d{2})")
    try
        subj = "date 2026-08 end"
        md = pcre2_match_data_create_from_pattern_8(code, C_NULL)
        try
            rc = pcre2_match_8(code, subj, ncodeunits(subj), 0, UInt32(0), md, C_NULL)
            @test rc == 3

            # by number
            sp = Ref{Ptr{UInt8}}(C_NULL); sl = Ref{Csize_t}(0)
            @test pcre2_substring_get_bynumber_8(md, UInt32(1), sp, sl) == 0
            @test unsafe_string(sp[], sl[]) == "2026"
            pcre2_substring_free_8(sp[])

            # named groups resolve to the right numbers
            @test pcre2_substring_number_from_name_8(code, "year")  == 1
            @test pcre2_substring_number_from_name_8(code, "month") == 2
        finally
            pcre2_match_data_free_8(md)
        end
    finally
        pcre2_code_free_8(code)
    end
end

@testset "Error paths" begin
    # Unmatched paren — compile must fail and report a usable offset + message.
    ec = Ref{Cint}(0); eo = Ref{Csize_t}(0)
    bad = "(unclosed"
    code = pcre2_compile_8(bad, ncodeunits(bad), UInt32(0), ec, eo, C_NULL)
    @test code == C_NULL
    @test ec[] != 0
    buf = Vector{UInt8}(undef, 256)
    n = pcre2_get_error_message_8(ec[], buf, length(buf))
    @test n > 0
    @test occursin("missing closing parenthesis", lowercase(String(buf[1:n])))

    # A known error code round-trips to its documented text.
    n2 = pcre2_get_error_message_8(PCRE2_ERROR_NOMATCH(), buf, length(buf))
    @test lowercase(String(buf[1:n2])) == "no match"
end

@testset "Library identity" begin
    # pcre2_config_8 reports the version the .so was actually built from — the
    # last check that the harvested pcre2.h and the compiled sources agree.
    buf = Vector{UInt8}(undef, 64)
    n = pcre2_config_8(PCRE2_CONFIG_VERSION(), buf)
    @test n > 0
    ver = String(buf[1:n-1])          # NUL-terminated
    @test startswith(ver, "10.45")
end

end # testset
