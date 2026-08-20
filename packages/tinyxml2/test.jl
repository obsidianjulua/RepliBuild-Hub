#!/usr/bin/env julia
# packages/tinyxml2/test.jl — exercise the tinyxml2 10.0.0 (C++) wrapper.
#
# Parses a real XML document and walks the DOM through Tier-2 method thunks,
# asserting on values (not isdefined):
#   • FirstChildElement — declared on XMLNode, dispatched with class-local
#     coordinates (document*/element* both alias their XMLNode base at off 0)
#   • Value / GetText / Attribute — Cstring returns
#   • IntAttribute — Cint return with a default-value arg
# Plus an XMLError success-vs-malformed path.
#
# Construction note: the generated XMLDocument() only zero-inits the storage,
# so — as with the box2d verification — we call the real C++ ctor
# (XMLDocument(bool, Whitespace)) on caller-owned bytes sized from
# compilation_metadata.json, and tear down with the NON-deleting dtor D1 (the
# Managed path uses the deleting D0, which would free() Julia-owned memory).
# All struct sizing comes from metadata at runtime, so layout drift fails
# loudly here instead of corrupting silently.

using Test
using JSON

include(joinpath(@__DIR__, "julia", "Tinyxml2.jl"))
using .Tinyxml2

const LIB  = Tinyxml2.LIBRARY_PATH
const META = JSON.parsefile(joinpath(@__DIR__, "julia", "compilation_metadata.json"))

# Emitted by the wrapper (STRUCT_SIZES), from the DWARF it was generated from.
struct_size(s) = Tinyxml2.struct_size(s)

# Cstring return → Julia String ("" on NULL)
# A `char*` return arrives as `Union{String,Nothing}` — the wrapper applies
# the NULL/copy policy itself now, on Tier 2 as well as on ccall (2026-08-12).
# The pointer arms stay for values read out of blobs by hand, and for the
# `<name>_ptr` variants.
cstr(x::AbstractString) = String(x)
cstr(::Nothing) = ""
cstr(cs) = (p = reinterpret(Ptr{UInt8}, cs); p == C_NULL ? "" : unsafe_string(p))

# XMLDocument on caller-owned storage via the real ctor (processEntities=true,
# PRESERVE_WHITESPACE=0). Returns the document pointer.
function make_doc(mem::Vector{UInt8})
    dp = Ptr{Cvoid}(pointer(mem))
    ccall((:_ZN8tinyxml211XMLDocumentC1EbNS_10WhitespaceE, LIB), Cvoid,
          (Ptr{Cvoid}, Bool, Cint), dp, true, Int32(0))
    return dp
end
destroy_doc(dp) = ccall((:_ZN8tinyxml211XMLDocumentD1Ev, LIB), Cvoid, (Ptr{Cvoid},), dp)

@testset "tinyxml2 10.0.0 (C++)" begin

    @testset "enums exported" begin
        @test Int(Tinyxml2.XML_SUCCESS) == 0
        @test Int(Tinyxml2.PRESERVE_WHITESPACE) == 0
    end

    @testset "parse + DOM navigation" begin
        xml   = "<library><book id=\"42\" title=\"RepliBuild\">hello</book></library>"
        title = "title"; idn = "id"
        doc_mem = zeros(UInt8, struct_size("XMLDocument"))
        GC.@preserve doc_mem xml title idn begin
            dp = make_doc(doc_mem)

            err = tinyxml2_XMLDocument_Parse(dp, Base.unsafe_convert(Cstring, xml), sizeof(xml))
            @test err == Tinyxml2.XML_SUCCESS

            root = tinyxml2_XMLNode_FirstChildElement(dp, C_NULL)      # <library>
            @test root != C_NULL
            @test cstr(tinyxml2_XMLNode_Value(root)) == "library"

            book = tinyxml2_XMLNode_FirstChildElement(root, C_NULL)    # <book>
            @test book != C_NULL
            @test cstr(tinyxml2_XMLNode_Value(book)) == "book"

            @test cstr(tinyxml2_XMLElement_GetText(book)) == "hello"
            @test cstr(tinyxml2_XMLElement_Attribute(book,
                        Base.unsafe_convert(Cstring, title), C_NULL)) == "RepliBuild"
            @test tinyxml2_XMLElement_IntAttribute(book,
                        Base.unsafe_convert(Cstring, idn), Int32(0)) == 42

            destroy_doc(dp)
        end
    end

    @testset "error path: mismatched element" begin
        bad = "<root><unclosed></root>"
        doc_mem = zeros(UInt8, struct_size("XMLDocument"))
        GC.@preserve doc_mem bad begin
            dp  = make_doc(doc_mem)
            err = tinyxml2_XMLDocument_Parse(dp, Base.unsafe_convert(Cstring, bad), sizeof(bad))
            @test err != Tinyxml2.XML_SUCCESS
            destroy_doc(dp)
        end
    end
end

println("✓ tinyxml2 test passed")
