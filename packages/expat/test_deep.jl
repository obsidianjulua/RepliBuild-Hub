#!/usr/bin/env julia
# expat — deep verifier. Exercises an ALREADY-BUILT wrapper; builds nothing.
# (`test.jl` is the cold rebuild driver and then runs this file.)
#
#   julia --project=<RepliBuild.jl> packages/expat/test_deep.jl
#
# What it leans on, beyond "does it load":
#   * C → Julia callbacks re-entering C (XML_StopParser from inside a handler)
#   * suspend / resume across XML_Parse calls
#   * zero-copy input through XML_GetBuffer / XML_ParseBuffer, byte-at-a-time
#   * a Julia-implemented allocator (XML_ParserCreate_MM) driving every expat malloc
#   * GC collections forced from inside C-invoked callbacks, over a large document
#   * by-value struct return (XML_ExpatVersionInfo), struct arrays (XML_GetFeatureList)
#   * harvested-config assertions: the features expat_config.h switched on must be
#     observable in the built library, or the harvest is not the library

using Test

include(joinpath(@__DIR__, "julia", "Expat.jl"))
import .Expat as X          # never `using` a wrapper — see the Hub notes

const XML_TRUE  = 0x01
const XML_FALSE = 0x00

# ── shared handler state ─────────────────────────────────────────────────────
mutable struct SaxState
    starts::Int
    ends::Int
    text::IOBuffer
    names::Vector{String}
    attrs::Vector{Pair{String,String}}
    depth::Int
    maxdepth::Int
    stop_at::Int            # call XML_StopParser on the Nth start tag (0 = never)
    resumable::Bool
    parser::Ptr{Cvoid}
    gc_every::Int           # force a GC every N start tags (0 = never)
    caught::Vector{String}  # exceptions caught inside callbacks
end
SaxState() = SaxState(0, 0, IOBuffer(), String[], Pair{String,String}[], 0, 0, 0, true,
                      C_NULL, 0, String[])

const STATE = Ref{SaxState}(SaxState())

function on_start(ud::Ptr{Cvoid}, name::Ptr{UInt8}, atts::Ptr{Ptr{UInt8}})::Cvoid
    try
        st = ud == C_NULL ? STATE[] : unsafe_pointer_to_objref(ud)::SaxState
        st.starts += 1
        st.depth += 1
        st.maxdepth = max(st.maxdepth, st.depth)
        length(st.names) < 64 && push!(st.names, unsafe_string(name))
        i = 1
        while true
            k = unsafe_load(atts, i); k == C_NULL && break
            v = unsafe_load(atts, i + 1)
            length(st.attrs) < 64 && push!(st.attrs, unsafe_string(k) => unsafe_string(v))
            i += 2
        end
        if st.gc_every > 0 && st.starts % st.gc_every == 0
            GC.gc(false)
        end
        if st.stop_at > 0 && st.starts == st.stop_at
            X.XML_StopParser(st.parser, st.resumable ? XML_TRUE : XML_FALSE)
        end
    catch e
        # A Julia exception must never unwind through expat's C frames.
        push!((ud == C_NULL ? STATE[] : unsafe_pointer_to_objref(ud)::SaxState).caught,
              sprint(showerror, e))
    end
    return nothing
end

function on_end(ud::Ptr{Cvoid}, name::Ptr{UInt8})::Cvoid
    st = ud == C_NULL ? STATE[] : unsafe_pointer_to_objref(ud)::SaxState
    st.ends += 1
    st.depth -= 1
    return nothing
end

function on_text(ud::Ptr{Cvoid}, s::Ptr{UInt8}, len::Cint)::Cvoid
    st = ud == C_NULL ? STATE[] : unsafe_pointer_to_objref(ud)::SaxState
    unsafe_write(st.text, s, len)
    return nothing
end

const START_CB = @cfunction(on_start, Cvoid, (Ptr{Cvoid}, Ptr{UInt8}, Ptr{Ptr{UInt8}}))
const END_CB   = @cfunction(on_end,   Cvoid, (Ptr{Cvoid}, Ptr{UInt8}))
const TEXT_CB  = @cfunction(on_text,  Cvoid, (Ptr{Cvoid}, Ptr{UInt8}, Cint))

function new_parser(; ns::Union{Nothing,Char}=nothing, encoding=C_NULL)
    p = ns === nothing ? X.XML_ParserCreate(encoding) :
                         X.XML_ParserCreateNS(encoding, UInt8(ns))
    p == C_NULL && error("XML_ParserCreate returned NULL")
    X.XML_SetElementHandler(p, START_CB, END_CB)
    X.XML_SetCharacterDataHandler(p, TEXT_CB)
    return p
end

"Parse `doc` with a fresh parser whose user data is `st`."
function parse_with(st::SaxState, doc::AbstractString; ns=nothing)
    p = new_parser(; ns=ns)
    st.parser = Ptr{Cvoid}(p)
    status = GC.@preserve st begin
        X.XML_SetUserData(p, pointer_from_objref(st))
        X.XML_Parse(p, doc, sizeof(doc), 1)
    end
    err = X.XML_GetErrorCode(p)
    line = X.XML_GetCurrentLineNumber(p)
    col = X.XML_GetCurrentColumnNumber(p)
    X.XML_ParserFree(p)
    return (status, err, line, col)
end

@testset "expat (deep)" begin

    @testset "version: string and by-value struct agree" begin
        @test X.XML_ExpatVersion() == "expat_2.7.5"
        v = X.XML_ExpatVersionInfo()           # 12-byte struct returned in RAX:RDX
        @test (v.major, v.minor, v.micro) == (2, 7, 5)
    end

    @testset "harvested config is the library (feature list)" begin
        feats = Dict{X.XML_FeatureEnum,Tuple{String,Int}}()
        p = X.XML_GetFeatureList()
        @test p != C_NULL
        i = 1
        while true
            f = unsafe_load(p, i)
            f.feature == X.XML_FEATURE_END && break
            feats[f.feature] = (unsafe_string(f.name), Int(f.value))
            i += 1
            i > 64 && error("feature list not terminated")
        end
        # expat_config.h (harvested) defines XML_DTD, XML_NS, XML_GE and
        # XML_CONTEXT_BYTES 1024. If the harvest were wrong these would differ.
        @test haskey(feats, X.XML_FEATURE_DTD)
        @test haskey(feats, X.XML_FEATURE_NS)
        @test haskey(feats, X.XML_FEATURE_GE)
        @test feats[X.XML_FEATURE_CONTEXT_BYTES][2] == 1024
        @test feats[X.XML_FEATURE_SIZEOF_XML_CHAR][2] == 1
        @test !haskey(feats, X.XML_FEATURE_UNICODE)      # XML_UNICODE is off
        @test feats[X.XML_FEATURE_CONTEXT_BYTES][1] == "XML_CONTEXT_BYTES"
    end

    @testset "SAX: elements, attributes, text, user data" begin
        st = SaxState()
        doc = """<?xml version="1.0"?>
                 <root a="1" b="two"><item id="x">hello</item><item id="y"> world</item>
                 <empty/></root>"""
        (status, err, _, _) = parse_with(st, doc)
        @test status == X.XML_STATUS_OK
        @test err == X.XML_ERROR_NONE
        @test st.starts == 4 && st.ends == 4
        @test st.names == ["root", "item", "item", "empty"]
        @test st.attrs == ["a" => "1", "b" => "two", "id" => "x", "id" => "y"]
        @test occursin("hello world", String(take!(st.text)))
        @test st.maxdepth == 2 && st.depth == 0
        @test isempty(st.caught)
    end

    @testset "namespaces (ParserCreateNS)" begin
        st = SaxState()
        doc = """<r xmlns="urn:a" xmlns:b="urn:b"><b:c/></r>"""
        (status, _, _, _) = parse_with(st, doc; ns='|')
        @test status == X.XML_STATUS_OK
        @test st.names == ["urn:a|r", "urn:b|c"]
    end

    @testset "error path: code, message, position" begin
        st = SaxState()
        (status, err, line, col) = parse_with(st, "<a>\n  <b></a>")
        @test status == X.XML_STATUS_ERROR
        @test err == X.XML_ERROR_TAG_MISMATCH
        @test X.XML_ErrorString(err) == "mismatched tag"
        @test line == 2
        @test col == 7
        @test X.XML_ErrorString(X.XML_ERROR_NONE) === nothing   # NULL → nothing
    end

    @testset "suspend inside a callback, then resume" begin
        st = SaxState()
        st.stop_at = 3
        doc = "<r>" * join(["<i n=\"$k\"/>" for k in 1:10]) * "</r>"
        p = new_parser()
        st.parser = Ptr{Cvoid}(p)
        GC.@preserve st begin
            X.XML_SetUserData(p, pointer_from_objref(st))
            s1 = X.XML_Parse(p, doc, sizeof(doc), 1)
            @test s1 == X.XML_STATUS_SUSPENDED
            @test st.starts == 3
            ps = Ref(X.XML_ParsingStatus())
            X.XML_GetParsingStatus(p, ps)
            @test ps[].parsing == X.XML_SUSPENDED
            @test ps[].finalBuffer == XML_TRUE
            s2 = X.XML_ResumeParser(p)
            @test s2 == X.XML_STATUS_OK
            @test st.starts == 11 && st.ends == 11
            X.XML_GetParsingStatus(p, ps)
            @test ps[].parsing == X.XML_FINISHED
        end
        X.XML_ParserFree(p)
    end

    @testset "abort inside a callback" begin
        st = SaxState()
        st.stop_at = 2
        st.resumable = false
        (status, err, _, _) = parse_with(st, "<r><a/><b/><c/></r>")
        @test status == X.XML_STATUS_ERROR
        @test err == X.XML_ERROR_ABORTED
        @test st.starts == 2
    end

    @testset "zero-copy XML_GetBuffer / XML_ParseBuffer, one byte at a time" begin
        st = SaxState()
        doc = "<root>" * join(["<e k=\"v$k\">t$k</e>" for k in 1:200]) * "</root>"
        bytes = Vector{UInt8}(doc)
        p = new_parser()
        GC.@preserve st begin
            X.XML_SetUserData(p, pointer_from_objref(st))
            for (i, b) in enumerate(bytes)
                buf = X.XML_GetBuffer(p, 1)
                @assert buf != C_NULL
                unsafe_store!(Ptr{UInt8}(buf), b)
                s = X.XML_ParseBuffer(p, 1, i == length(bytes) ? 1 : 0)
                s == X.XML_STATUS_OK || error("ParseBuffer failed at byte $i: " *
                                              string(X.XML_ErrorString(X.XML_GetErrorCode(p))))
            end
        end
        X.XML_ParserFree(p)
        @test st.starts == 201
        @test st.attrs[end] == ("k" => "v64")   # attrs capped at 64 entries
        @test occursin("t200", String(take!(st.text)))
    end

    @testset "encoding: ISO-8859-1 input decodes to UTF-8" begin
        st = SaxState()
        doc = UInt8[codeunits("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><w>caf")...,
                    0xE9, codeunits("</w>")...]
        p = new_parser()
        GC.@preserve st doc begin
            X.XML_SetUserData(p, pointer_from_objref(st))
            @test X.XML_Parse(p, pointer(doc), length(doc), 1) == X.XML_STATUS_OK
        end
        X.XML_ParserFree(p)
        @test String(take!(st.text)) == "café"
    end

    @testset "billion laughs is refused" begin
        lol = """<?xml version="1.0"?>
        <!DOCTYPE lolz [
          <!ENTITY lol "lol">
          <!ENTITY lol1 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
          <!ENTITY lol2 "&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;">
          <!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">
          <!ENTITY lol4 "&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;">
          <!ENTITY lol5 "&lol4;&lol4;&lol4;&lol4;&lol4;&lol4;&lol4;&lol4;&lol4;&lol4;">
          <!ENTITY lol6 "&lol5;&lol5;&lol5;&lol5;&lol5;&lol5;&lol5;&lol5;&lol5;&lol5;">
          <!ENTITY lol7 "&lol6;&lol6;&lol6;&lol6;&lol6;&lol6;&lol6;&lol6;&lol6;&lol6;">
          <!ENTITY lol8 "&lol7;&lol7;&lol7;&lol7;&lol7;&lol7;&lol7;&lol7;&lol7;&lol7;">
          <!ENTITY lol9 "&lol8;&lol8;&lol8;&lol8;&lol8;&lol8;&lol8;&lol8;&lol8;&lol8;">
        ]>
        <lolz>&lol9;</lolz>"""
        st = SaxState()
        p = new_parser()
        @test X.XML_SetBillionLaughsAttackProtectionMaximumAmplification(p, 50.0) == XML_TRUE
        X.XML_ParserFree(p)
        (status, err, _, _) = parse_with(st, lol)
        @test status == X.XML_STATUS_ERROR
        @test err == X.XML_ERROR_AMPLIFICATION_LIMIT_BREACH
    end

    @testset "Julia allocator drives expat (XML_ParserCreate_MM)" begin
        counts = Dict(:malloc => 0, :realloc => 0, :free => 0)
        live = Set{UInt}()
        jl_malloc(sz::Csize_t)::Ptr{Cvoid} = begin
            counts[:malloc] += 1
            q = Libc.malloc(sz); push!(live, UInt(q)); q
        end
        jl_realloc(q::Ptr{Cvoid}, sz::Csize_t)::Ptr{Cvoid} = begin
            counts[:realloc] += 1
            q != C_NULL && delete!(live, UInt(q))
            r = Libc.realloc(q, sz); push!(live, UInt(r)); r
        end
        jl_free(q::Ptr{Cvoid})::Cvoid = begin
            if q != C_NULL
                counts[:free] += 1
                delete!(live, UInt(q))
            end
            Libc.free(q)
        end
        # closures: the CFunction objects must outlive the parser
        cfs = (@cfunction($jl_malloc, Ptr{Cvoid}, (Csize_t,)),
               @cfunction($jl_realloc, Ptr{Cvoid}, (Ptr{Cvoid}, Csize_t)),
               @cfunction($jl_free, Cvoid, (Ptr{Cvoid},)))
        suite = Ref(X.XML_Memory_Handling_Suite(Base.unsafe_convert(Ptr{Cvoid}, cfs[1]),
                                              Base.unsafe_convert(Ptr{Cvoid}, cfs[2]),
                                              Base.unsafe_convert(Ptr{Cvoid}, cfs[3])))
        st = SaxState()
        doc = "<r>" * join(["<n a=\"$(repeat("x", k % 97))\">$(k)</n>" for k in 1:3000]) * "</r>"
        GC.@preserve suite cfs st begin
            p = X.XML_ParserCreate_MM(C_NULL, suite, C_NULL)
            @test p != C_NULL
            X.XML_SetElementHandler(p, START_CB, END_CB)
            X.XML_SetCharacterDataHandler(p, TEXT_CB)
            X.XML_SetUserData(p, pointer_from_objref(st))
            @test X.XML_Parse(p, doc, sizeof(doc), 1) == X.XML_STATUS_OK
            # the parser's own allocator is reachable through the API too
            m = X.XML_MemMalloc(p, 128)
            @test m != C_NULL
            X.XML_MemFree(p, m)
            X.XML_ParserFree(p)
        end
        @test st.starts == 3001
        @test counts[:malloc] > 10
        @test isempty(live)                     # every block expat took, it gave back
    end

    @testset "GC pressure inside callbacks over a large document" begin
        st = SaxState()
        st.gc_every = 997
        n = 100_000
        io = IOBuffer()
        print(io, "<doc>")
        for k in 1:n
            print(io, "<r id=\"", k, "\"><v>", k * 3, "</v></r>")
        end
        print(io, "</doc>")
        doc = String(take!(io))
        t = @elapsed (status, err, _, _) = parse_with(st, doc)
        @test status == X.XML_STATUS_OK
        @test st.starts == 2n + 1
        @test st.ends == 2n + 1
        @test isempty(st.caught)
        println("    parsed $(round(sizeof(doc)/2^20, digits=2)) MiB, $(2n+1) elements in $(round(t, digits=2))s with forced GCs")
    end

    @testset "parser reuse via XML_ParserReset" begin
        p = new_parser()
        for k in 1:50
            st = SaxState()
            st.parser = Ptr{Cvoid}(p)
            doc = "<a>" * repeat("<b/>", k) * "</a>"
            GC.@preserve st begin
                X.XML_SetUserData(p, pointer_from_objref(st))
                @test X.XML_Parse(p, doc, sizeof(doc), 1) == X.XML_STATUS_OK
            end
            @test st.starts == k + 1
            @test X.XML_ParserReset(p, C_NULL) == XML_TRUE
            X.XML_SetElementHandler(p, START_CB, END_CB)
            X.XML_SetCharacterDataHandler(p, TEXT_CB)
        end
        X.XML_ParserFree(p)
    end

end
