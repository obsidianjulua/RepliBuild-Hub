#!/usr/bin/env julia
# packages/pugixml/test.jl — exercise the pugixml 1.15 (C++) wrapper.
#
# pugixml's DOM is handle-based, so this verifier drives the by-value struct
# ABI through Tier-2 thunks in three shapes:
#   • xml_parse_result — 24-byte BY-VALUE (sret) return from load_string.
#     status lives at byte 0; the generated getproperty only exposes .offset,
#     so we read it directly.
#   • xml_node / xml_attribute — 8-byte single-pointer structs returned BY
#     VALUE in a register from first_child / first_attribute.
#   • by-value handle passed back as `this` (Ref -> Ptr) for name/value/as_int.
#
# Navigation is POSITIONAL on purpose. child(name) and attribute(name) each
# have both a const char* and a std::string_view (v1.15) overload that collapse
# to the same Julia signature (this::Any, arg1::Any); last-definition-wins binds
# the name to the string_view thunk, so a const char* argument would be an ABI
# mismatch (pointer vs 16-byte {ptr,len}). first_child/first_attribute are
# unambiguous. This overload collision is a generator finding, logged for the
# engine repo — not worked around in src/ from here.
#
# Construction/teardown go through the in-place ctor/dtor thunks (C2Ev / D2Ev,
# the non-deleting destructor — correct for caller-owned storage).

using Test
using JSON

include(joinpath(@__DIR__, "julia", "Pugixml.jl"))
using .Pugixml

const LIB  = Pugixml.LIBRARY_PATH
const META = JSON.parsefile(joinpath(@__DIR__, "julia", "compilation_metadata.json"))
# parse_cdata|parse_escapes|parse_wconv_attribute|parse_eol; attributes and
# non-whitespace PCDATA are parsed regardless of options.
const PARSE_DEFAULT = Cuint(0x74)

function struct_size(s::String)
    v = META["struct_definitions"][s]["byte_size"]
    v isa Integer ? Int(v) : (startswith(v, "0x") ? parse(Int, v[3:end], base=16) : parse(Int, v))
end

cstr(cs) = (p = reinterpret(Ptr{UInt8}, cs); p == C_NULL ? "" : unsafe_string(p))

# Call an accessor whose `this` must be a pointer to a by-value handle.
withptr(f, h) = (r = Ref(h); GC.@preserve r f(Base.unsafe_convert(Ptr{typeof(h)}, r)))

# status = first 4 bytes of the 24-byte xml_parse_result.
function parse_status(res::Pugixml.xml_parse_result)
    r = Ref(res)
    GC.@preserve r unsafe_load(Ptr{Int32}(Base.unsafe_convert(Ptr{Pugixml.xml_parse_result}, r)))
end

@testset "pugixml 1.15 (C++)" begin

    @testset "enums exported" begin
        @test Int(Pugixml.status_ok) == 0
        @test Int(Pugixml.node_element) == 2   # node_null=0, node_document=1, node_element=2
    end

    @testset "parse + handle navigation" begin
        xml = "<root a=\"7\"><child>hello</child></root>"
        doc_mem = zeros(UInt8, struct_size("xml_document"))
        GC.@preserve doc_mem xml begin
            dp = Ptr{Cvoid}(pointer(doc_mem))
            pugi_xml_document_xml_document(dp)                 # in-place ctor (C2Ev)

            res = pugi_xml_document_load_string(dp,            # 24-byte sret return
                    Base.unsafe_convert(Cstring, xml), PARSE_DEFAULT)
            @test parse_status(res) == Int(Pugixml.status_ok)

            root = pugi_xml_node_first_child(dp)               # 8-byte register return: <root>
            @test UInt(root._root) != 0
            @test cstr(withptr(pugi_xml_node_name, root)) == "root"

            attr = withptr(pugi_xml_node_first_attribute, root)   # a="7"
            @test UInt(attr._attr) != 0
            @test cstr(withptr(pugi_xml_attribute_name, attr))  == "a"
            @test cstr(withptr(pugi_xml_attribute_value, attr)) == "7"
            @test withptr(a -> pugi_xml_attribute_as_int(a, Cint(0)), attr) == 7

            child = withptr(pugi_xml_node_first_child, root)      # <child>
            @test UInt(child._root) != 0
            @test cstr(withptr(pugi_xml_node_name, child))        == "child"
            @test cstr(withptr(pugi_xml_node_child_value, child)) == "hello"

            pugi_xml_document_destroy_xml_document(dp)         # D2Ev (non-deleting)
        end
    end

    @testset "error path: mismatched element" begin
        bad = "<root><oops></root>"
        doc_mem = zeros(UInt8, struct_size("xml_document"))
        GC.@preserve doc_mem bad begin
            dp = Ptr{Cvoid}(pointer(doc_mem))
            pugi_xml_document_xml_document(dp)
            res = pugi_xml_document_load_string(dp,
                    Base.unsafe_convert(Cstring, bad), PARSE_DEFAULT)
            @test parse_status(res) != Int(Pugixml.status_ok)
            pugi_xml_document_destroy_xml_document(dp)
        end
    end
end

println("✓ pugixml test passed")
