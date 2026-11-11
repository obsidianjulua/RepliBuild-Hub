#!/usr/bin/env julia
# md4c Hub package — deep integration test
#
# Assumes the wrapper is already built (test.jl rebuilds; this only verifies).
#   - MD_FLAG_* / MD_DIALECT_* macro shims (the canary: GITHUB is the OR of
#     four flags; a shim compiled against a foreign md4c.h is the only way
#     those disagree)
#   - MD_PARSER layout — header-only aggregate the caller fills with
#     function pointers; needs -fstandalone-debug
#   - md_html round-trips: headings, emphasis, code, lists, links
#   - GitHub dialect: tables, strikethrough, task lists
#   - md_parse SAX callbacks driven BY C via @cfunction
#   - callback abort, empty input, HTML-off flag
#   - Tier 1 is OFF (quarantined); this package is pure ccall
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/md4c/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Md4c.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)

const M = Md4c

# ── C callbacks (must be top-level, non-closure, for @cfunction) ─────────────

const HTML_CHUNKS = Vector{String}()

function html_cb(text::Ptr{UInt8}, size::Cuint, ::Ptr{Cvoid})::Cvoid
    push!(HTML_CHUNKS, unsafe_string(text, size))
    return nothing
end

const BLOCKS_ENTER = Vector{M.MD_BLOCKTYPE}()
const BLOCKS_LEAVE = Vector{M.MD_BLOCKTYPE}()
const SPANS_ENTER  = Vector{M.MD_SPANTYPE}()
const TEXTS        = Vector{Tuple{M.MD_TEXTTYPE,String}}()
const PARSE_ABORT_AT = Ref(0)
const PARSE_SEEN = Ref(0)

function enter_block(typ::Cuint, ::Ptr{Cvoid}, ::Ptr{Cvoid})::Cint
    push!(BLOCKS_ENTER, M.MD_BLOCKTYPE(typ))
    PARSE_SEEN[] += 1
    return Cint(PARSE_ABORT_AT[] > 0 && PARSE_SEEN[] >= PARSE_ABORT_AT[] ? 1 : 0)
end
function leave_block(typ::Cuint, ::Ptr{Cvoid}, ::Ptr{Cvoid})::Cint
    push!(BLOCKS_LEAVE, M.MD_BLOCKTYPE(typ))
    return Cint(0)
end
function enter_span(typ::Cuint, ::Ptr{Cvoid}, ::Ptr{Cvoid})::Cint
    push!(SPANS_ENTER, M.MD_SPANTYPE(typ))
    return Cint(0)
end
function leave_span(::Cuint, ::Ptr{Cvoid}, ::Ptr{Cvoid})::Cint
    return Cint(0)
end
function text_cb(typ::Cuint, text::Ptr{UInt8}, size::Cuint, ::Ptr{Cvoid})::Cint
    push!(TEXTS, (M.MD_TEXTTYPE(typ), unsafe_string(text, size)))
    return Cint(0)
end
function debug_log(::Ptr{UInt8}, ::Ptr{Cvoid})::Cvoid
    return nothing
end

function render_html(src::AbstractString; parser_flags::Integer = 0, renderer_flags::Integer = 0)
    empty!(HTML_CHUNKS)
    bytes = Vector{UInt8}(codeunits(src))
    cb = @cfunction(html_cb, Cvoid, (Ptr{UInt8}, Cuint, Ptr{Cvoid}))
    GC.@preserve bytes begin
        rc = M.md_html(bytes, length(bytes), cb, C_NULL, parser_flags, renderer_flags)
        rc == 0 || error("md_html failed: $rc")
    end
    return join(HTML_CHUNKS)
end

function parse_sax(src::AbstractString; flags::Integer = 0)
    empty!(BLOCKS_ENTER); empty!(BLOCKS_LEAVE); empty!(SPANS_ENTER); empty!(TEXTS)
    PARSE_SEEN[] = 0
    parser = Ref(M.MD_PARSER(
        0, Cuint(flags),
        @cfunction(enter_block, Cint, (Cuint, Ptr{Cvoid}, Ptr{Cvoid})),
        @cfunction(leave_block, Cint, (Cuint, Ptr{Cvoid}, Ptr{Cvoid})),
        @cfunction(enter_span,  Cint, (Cuint, Ptr{Cvoid}, Ptr{Cvoid})),
        @cfunction(leave_span,  Cint, (Cuint, Ptr{Cvoid}, Ptr{Cvoid})),
        @cfunction(text_cb,     Cint, (Cuint, Ptr{UInt8}, Cuint, Ptr{Cvoid})),
        @cfunction(debug_log,   Cvoid, (Ptr{UInt8}, Ptr{Cvoid})),
        C_NULL,
    ))
    bytes = Vector{UInt8}(codeunits(src))
    GC.@preserve bytes parser begin
        return M.md_parse(bytes, length(bytes), parser, C_NULL)
    end
end

@testset "md4c Deep Tests" begin

@testset "Library identity and flag macros" begin
    @test M.MD_DIALECT_COMMONMARK() == 0
    @test M.MD_FLAG_TABLES() == 0x0100
    @test M.MD_FLAG_STRIKETHROUGH() == 0x0200
    @test M.MD_FLAG_TASKLISTS() == 0x0800
    @test M.MD_FLAG_COLLAPSEWHITESPACE() == 0x0001
    @test M.MD_FLAG_NOHTML() == (0x0020 | 0x0040)
    @test M.MD_HTML_FLAG_XHTML() == 0x0008
    @test M.MD_HTML_FLAG_DEBUG() == 0x0001
    @test M.MD_HTML_FLAG_VERBATIM_ENTITIES() == 0x0002

    # GITHUB is documented as the OR of four flags. A shim compiled against a
    # foreign md4c.h is the only way the pieces and the composite disagree.
    @test M.MD_DIALECT_GITHUB() == (M.MD_FLAG_PERMISSIVEAUTOLINKS() |
                                    M.MD_FLAG_TABLES() |
                                    M.MD_FLAG_STRIKETHROUGH() |
                                    M.MD_FLAG_TASKLISTS())

    @test M.MD_BLOCK_H == M.MD_BLOCKTYPE(6)
    @test M.MD_BLOCK_P == M.MD_BLOCKTYPE(9)
    @test M.MD_SPAN_EM == M.MD_SPANTYPE(0)
    @test M.MD_SPAN_STRONG == M.MD_SPANTYPE(1)
    @test M.MD_TEXT_NORMAL == M.MD_TEXTTYPE(0)
end

@testset "Tier 1 is OFF — pure ccall" begin
    for n in (:TIER1_FUNCTIONS, :TIER1_DECLARES, :_TIER1_KERNEL, :_slice_symbols_resolve)
        @test !isdefined(M, n)
    end
    @test !isdir(joinpath(PKG_DIR, "julia", "slices"))
    src = read(WRAPPER, String)
    @test !occursin("@generated function _TIER1_", src)
    @test !occursin("const _SLICE_", src)
    @test !occursin("llvmcall", src)
    @test !isdefined(M, :DISPATCH_TIER)
    @test !isdefined(M, :dispatch_tier)
    @test occursin("Every function in this module dispatches through Tier 3", src)
end

@testset "Layout of MD_PARSER" begin
    @test M.struct_size(:MD_PARSER) == 64
    @test M.member_offset(:MD_PARSER, :abi_version) == 0
    @test M.member_offset(:MD_PARSER, :flags) == 4
    @test M.member_offset(:MD_PARSER, :enter_block) == 8
    @test M.member_offset(:MD_PARSER, :text) == 40
    @test M.member_offset(:MD_PARSER, :syntax) == 56
    @test fieldnames(M.MD_PARSER) === (:abi_version, :flags, :enter_block,
                                       :leave_block, :enter_span, :leave_span,
                                       :text, :debug_log, :syntax)
    @test M.struct_size(:MD_ATTRIBUTE) == 32
    @test M.struct_size(:MD_BLOCK_H_DETAIL) == 4
end

@testset "md_html CommonMark round-trips" begin
    @test render_html("# Hello") == "<h1>Hello</h1>\n"
    @test render_html("## Sub") == "<h2>Sub</h2>\n"
    @test render_html("Hello **world**") == "<p>Hello <strong>world</strong></p>\n"
    @test render_html("*em* and `code`") == "<p><em>em</em> and <code>code</code></p>\n"
    @test occursin("<ul>", render_html("- a\n- b"))
    @test occursin("<li>a</li>", render_html("- a\n- b"))
    @test occursin("<a href=\"https://example.com\">link</a>",
                   render_html("[link](https://example.com)"))
    @test render_html("") == ""
    @test occursin("<hr>", render_html("---"))
    @test occursin("<blockquote>", render_html("> quoted"))
    @test occursin("<pre><code>", render_html("```\ncode\n```"))
end

@testset "GitHub dialect: tables, strike, tasks" begin
    flags = M.MD_DIALECT_GITHUB()
    table = """
    | a | b |
    |---|---|
    | 1 | 2 |
    """
    html = render_html(table; parser_flags = flags)
    @test occursin("<table>", html)
    @test occursin("<th>a</th>", html)
    @test occursin("<td>1</td>", html)

    @test occursin("<del>gone</del>",
                   render_html("~~gone~~"; parser_flags = flags))

    task = render_html("- [x] done\n- [ ] todo"; parser_flags = flags)
    @test occursin("type=\"checkbox\"", task)
    @test occursin("checked", task)

    # Same table under CommonMark is just a paragraph, not a table.
    plain = render_html(table; parser_flags = M.MD_DIALECT_COMMONMARK())
    @test !occursin("<table>", plain)
end

@testset "HTML-off and XHTML flags" begin
    raw = render_html("<div>raw</div>")
    @test occursin("<div>", raw)

    off = render_html("<div>raw</div>"; parser_flags = M.MD_FLAG_NOHTML())
    @test !occursin("<div>", off)

    xhtml = render_html("---"; renderer_flags = M.MD_HTML_FLAG_XHTML())
    @test occursin("<hr />", xhtml) || occursin("<hr/>", xhtml)
end

@testset "md_parse SAX callbacks" begin
    PARSE_ABORT_AT[] = 0
    rc = parse_sax("# Title\n\nHello **world**")
    @test rc == 0
    @test M.MD_BLOCK_DOC in BLOCKS_ENTER
    @test M.MD_BLOCK_H in BLOCKS_ENTER
    @test M.MD_BLOCK_P in BLOCKS_ENTER
    @test M.MD_SPAN_STRONG in SPANS_ENTER
    @test M.MD_BLOCK_DOC in BLOCKS_LEAVE
    @test any(t -> t[1] == M.MD_TEXT_NORMAL && t[2] == "Title", TEXTS)
    @test any(t -> t[1] == M.MD_TEXT_NORMAL && t[2] == "world", TEXTS)
    # enter/leave of DOC bookend the document
    @test BLOCKS_ENTER[1] == M.MD_BLOCK_DOC
    @test BLOCKS_LEAVE[end] == M.MD_BLOCK_DOC
end

@testset "callback abort stops parse" begin
    PARSE_ABORT_AT[] = 1   # abort on first enter_block (DOC)
    rc = parse_sax("# never")
    @test rc == 1
    @test BLOCKS_ENTER == [M.MD_BLOCK_DOC]
    @test isempty(TEXTS)
    PARSE_ABORT_AT[] = 0
end

@testset "churn under GC pressure" begin
    for i in 1:80
        html = render_html("# H$i\n\npara **$i** and `code`")
        @test occursin("<h1>H$i</h1>", html)
        @test occursin("<strong>$i</strong>", html)
        i % 11 == 0 && GC.gc(false)
    end
    PARSE_ABORT_AT[] = 0
    rc = parse_sax(repeat("- item\n", 40))
    @test rc == 0
    @test count(==(M.MD_BLOCK_LI), BLOCKS_ENTER) == 40
end

end
