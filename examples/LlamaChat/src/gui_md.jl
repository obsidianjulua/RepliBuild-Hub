# Markdown in the window. Included by gui.jl, inside `module GUI`.
#
# The terminal path renders markdown with the stdlib's ANSI printer; imgui has
# no rich text, so here the same `Markdown.parse` tree is turned into a small
# render tree once, and laid out every frame:
#
#   * inline runs (bold, italic, `code`, links) are drawn word by word, breaking
#     lines by hand — one TextUnformatted per word, measured once per font size;
#   * headings, code blocks (a child window, mono font, a copy button), lists,
#     tables (imgui tables), quotes and rules are blocks.
#
# Parsing follows the stream the way the terminal does: `LlamaChat._segment`
# cuts the reply into markdown blocks, and a block is parsed once and cached by
# its raw text, so a streaming reply re-parses only its open tail. Each cached
# segment remembers the height it drew at, and a segment scrolled out of view is
# skipped with a Dummy of that height — the cost of a frame is what is visible,
# not the length of the conversation.

const MD = LC.Markdown

include("gui_highlight.jl")

const S_BOLD, S_ITALIC, S_CODE, S_LINK, S_BREAK = 0x01, 0x02, 0x04, 0x08, 0x10

const C_CODE   = Ref(vec4(0.95, 0.74, 0.48))
const C_CODEBG = Ref(vec4(0.11, 0.12, 0.15))
const CODE_CHILD_FLAGS = flags(G.ImGuiChildFlags_Borders, G.ImGuiChildFlags_AutoResizeY,
                               G.ImGuiChildFlags_AlwaysUseWindowPadding)
const TABLE_FLAGS = flags(G.ImGuiTableFlags_Borders, G.ImGuiTableFlags_RowBg,
                          G.ImGuiTableFlags_SizingStretchProp)

"""
Text as this build can draw it. ImWchar is 16-bit here (imconfig.h leaves
IMGUI_USE_WCHAR32 off), so a code point above U+FFFF — most emoji — can never
reach a glyph and draws as U+FFFD. Drop those, and the invisible selectors and
joiners that dress emoji, rather than scatter replacement marks through a reply.
The raw text (what **copy** puts on the clipboard) keeps them.
"""
display_text(s::AbstractString) =
    any(_undrawable, s) ? filter(!_undrawable, String(s)) : String(s)
_undrawable(c::Char) = !isvalid(c) || c > '￿' || c in ('︎', '️', '‍', '⃣')

# A run of one style, cut at word boundaries: each piece is a word plus the
# spaces after it, so a line can break between any two pieces.
mutable struct Span
    pieces::Vector{String}
    style::UInt8
    widths::Vector{Float32}             # measured at `wsize`
    wsize::Float32
end
Span(text::AbstractString, style::UInt8) =
    Span([String(m.match) for m in eachmatch(r"\S+\s*|\s+", text)], style, Float32[], 0f0)

abstract type Blk end
struct Para      <: Blk; spans::Vector{Span}; end
struct Heading   <: Blk; level::Int; spans::Vector{Span}; end
struct CodeBlock <: Blk; lang::String; code::String; lines::Runs; end
CodeBlock(lang::AbstractString, code::AbstractString) =
    CodeBlock(String(lang), String(code), highlight_code(lang, code))   # coloured once, at parse time
struct ListBlk   <: Blk; start::Int; items::Vector{Vector{Blk}}; end   # start < 0: bullets
struct Quote     <: Blk; body::Vector{Blk}; end
struct Rule      <: Blk end
struct TableBlk  <: Blk; header::Vector{String}; rows::Vector{Vector{Vector{Span}}}; end
struct Plain     <: Blk; text::String; end

"""One markdown block of a reply as `_segment` cut it, parsed, with its last drawn size."""
mutable struct Seg
    raw::String
    blocks::Vector{Blk}
    h::Float32                          # height drawn at width `w`; 0 = never drawn
    w::Float32
end

# ── Markdown AST → render tree ───────────────────────────────────────────────

function spans!(out::Vector{Span}, x, st::UInt8)
    if x isa AbstractString
        s = display_text(replace(x, '\n' => ' '))
        isempty(s) || push!(out, Span(s, st))
    elseif x isa AbstractVector
        for c in x; spans!(out, c, st); end
    elseif x isa MD.Bold
        spans!(out, x.text, st | S_BOLD)
    elseif x isa MD.Italic
        spans!(out, x.text, st | S_ITALIC)
    elseif x isa MD.Code
        s = display_text(replace(x.code, '\n' => ' '))
        isempty(s) || push!(out, Span(s, st | S_CODE))
    elseif x isa MD.Link
        spans!(out, x.text, st | S_LINK)
    elseif x isa MD.Image
        spans!(out, x.alt, st | S_ITALIC)
    elseif x isa MD.LineBreak
        push!(out, Span(String[], S_BREAK, Float32[], 0f0))
    elseif x isa MD.LaTeX
        spans!(out, MD.Code("", x.formula), st)
    else
        spans!(out, try sprint(MD.plaininline, x) catch; string(x) end, st)
    end
    return out
end
spans(x) = spans!(Span[], x, 0x00)

plain(sp::Vector{Span}) = strip(join(join(s.pieces) for s in sp))
_level(::MD.Header{l}) where {l} = l

function blk(x)::Blk
    x isa MD.Paragraph      && return Para(spans(x.content))
    x isa MD.Header         && return Heading(_level(x), spans(x.text))
    x isa MD.Code           && return CodeBlock(x.language, display_text(rstrip(x.code)))
    x isa MD.List           && return ListBlk(x.ordered, [blocks(i) for i in x.items])
    x isa MD.BlockQuote     && return Quote(blocks(x.content))
    x isa MD.HorizontalRule && return Rule()
    x isa MD.LaTeX          && return CodeBlock("math", display_text(x.formula))
    x isa MD.Admonition     && return Quote(vcat(Blk[Para(spans(MD.Bold(Any[x.title])))], blocks(x.content)))
    if x isa MD.Table && !isempty(x.rows)
        return TableBlk([String(plain(spans(c))) for c in x.rows[1]],
                        [[spans(c) for c in r] for r in x.rows[2:end]])
    end
    return Plain(display_text(rstrip(try sprint(MD.plain, x) catch; string(x) end)))
end
blocks(xs) = Blk[blk(x) for x in xs]

"""Parse one segment. A parser failure costs the formatting, never the text."""
function parse_md(raw::AbstractString)
    try
        return blocks(MD.parse(raw).content)
    catch e
        e isa InterruptException && rethrow()
        return Blk[Plain(display_text(rstrip(raw)))]
    end
end

"""Re-cut `answer` into segments, reusing every segment whose text is unchanged."""
function segments(answer::AbstractString, old::Vector{Seg})
    isempty(answer) && return Seg[]
    pool = Dict{String,Vector{Seg}}()
    for s in old; push!(get!(pool, s.raw, Seg[]), s); end
    out = Seg[]
    for raw in LC._segment(answer)
        reuse = get(pool, raw, nothing)
        push!(out, reuse === nothing || isempty(reuse) ? Seg(raw, parse_md(raw), 0f0, 0f0) : popfirst!(reuse))
    end
    return out
end

# ── drawing ──────────────────────────────────────────────────────────────────

function font_for(app, st::UInt8)
    f = app.fonts
    st & S_CODE   != 0 && return f.mono
    st & S_BOLD   != 0 && return f.bold
    st & S_ITALIC != 0 && return f.italic
    return f.regular
end

function measure!(sp::Span)
    fs = G.ImGui_GetFontSize()
    (sp.wsize == fs && length(sp.widths) == length(sp.pieces)) && return sp
    resize!(sp.widths, length(sp.pieces))
    for (k, p) in enumerate(sp.pieces)
        sp.widths[k] = GC.@preserve p G.ImGui_CalcTextSize(pointer(p), pointer(p) + sizeof(p), false, -1f0).x
    end
    sp.wsize = fs
    return sp
end

"""
Lay out inline runs, breaking lines by hand. Each piece is drawn, then
`SameLine(0, 0)`; a piece that would cross the right edge goes to a new line
first. A new line starts at the current indent or group, so this works inside
list items and table cells.
"""
function flow!(app, sps::Vector{Span}, base::UInt8 = 0x00; scale::Float32 = 1f0)
    isempty(sps) && return nothing
    size = app.fonts.size * scale
    right = G.ImGui_GetCursorPosX() + G.ImGui_GetContentRegionAvail().x
    linestart = true
    for sp in sps
        st = sp.style | base
        if st & S_BREAK != 0
            linestart || G.ImGui_NewLine()
            linestart = true
            continue
        end
        G.ImGui_PushFont(font_for(app, st), size)
        col = st & S_CODE != 0 ? C_CODE : st & S_LINK != 0 ? C_USER : nothing
        col === nothing || G.ImGui_PushStyleColor(Cint(G.ImGuiCol_Text), col)
        measure!(sp)
        for (k, p) in enumerate(sp.pieces)
            if !linestart && G.ImGui_GetCursorPosX() + sp.widths[k] > right
                G.ImGui_NewLine()                     # ends the line SameLine left open
                linestart = true
            end
            linestart && isspace(p[1]) && continue    # no blanks at the start of a line
            text!(p)
            G.ImGui_SameLine(0f0, 0f0)
            linestart = false
        end
        col === nothing || G.ImGui_PopStyleColor(Cint(1))
        G.ImGui_PopFont()
    end
    linestart || G.ImGui_NewLine()
    return nothing
end

const HEADING_SCALE = (1.5f0, 1.3f0, 1.15f0)

draw!(app, b::Para)  = flow!(app, b.spans)
draw!(app, ::Rule)   = G.ImGui_Separator()
draw!(app, b::Plain) = text!(b.text)

function draw!(app, b::Heading)
    flow!(app, b.spans, S_BOLD; scale = get(HEADING_SCALE, b.level, 1f0))
    b.level <= 2 && G.ImGui_Separator()
end

function draw!(app, b::CodeBlock)
    G.ImGui_PushStyleColor(Cint(G.ImGuiCol_ChildBg), C_CODEBG)
    # A child window: its own background, and no wrapping — a long line scrolls
    # sideways instead. AutoResizeY sizes it to the code; it has no vertical
    # scroll of its own, so the mouse wheel still scrolls the transcript.
    G.ImGui_BeginChild("##code", ZERO, CODE_CHILD_FLAGS, Cint(G.ImGuiWindowFlags_HorizontalScrollbar))
    colored(() -> text!(isempty(b.lang) ? "code" : b.lang), app.dim)
    G.ImGui_SameLine(0f0, -1f0)
    G.ImGui_SmallButton("copy") && G.ImGui_SetClipboardText(b.code)
    G.ImGui_PushFont(app.fonts.mono, app.fonts.size)
    for line in b.lines
        if isempty(line)
            G.ImGui_NewLine()
            continue
        end
        for (k, (s, c)) in enumerate(line)
            k > 1 && G.ImGui_SameLine(0f0, 0f0)
            if c == 0
                text!(s)
            else
                G.ImGui_PushStyleColor(Cint(G.ImGuiCol_Text), c)     # the ImU32 overload
                text!(s)
                G.ImGui_PopStyleColor(Cint(1))
            end
        end
    end
    G.ImGui_PopFont()
    G.ImGui_EndChild()
    G.ImGui_PopStyleColor(Cint(1))
end

function draw!(app, b::ListBlk)
    for (k, item) in enumerate(b.items)
        G.ImGui_PushID(Cint(k))
        text!(b.start >= 0 ? string(b.start + k - 1, ".") : "•")
        G.ImGui_SameLine(0f0, -1f0)
        G.ImGui_BeginGroup()            # wrapped lines return to here, not the margin
        draw_blocks!(app, item; tight = true)
        G.ImGui_EndGroup()
        G.ImGui_PopID()
    end
end

function draw!(app, b::Quote)
    G.ImGui_Indent(app.fonts.size)
    colored(() -> draw_blocks!(app, b.body; tight = true), app.dim)
    G.ImGui_Unindent(app.fonts.size)
end

function draw!(app, b::TableBlk)
    n = length(b.header)
    n == 0 && return
    G.ImGui_BeginTable("##table", Cint(n), TABLE_FLAGS, ZERO, 0f0) || return
    for h in b.header
        G.ImGui_TableSetupColumn(h, Cint(0), 0f0, Cuint(0))
    end
    G.ImGui_TableHeadersRow()
    for row in b.rows
        G.ImGui_TableNextRow(Cint(0), 0f0)
        for k in 1:n
            G.ImGui_TableNextColumn()
            k <= length(row) && flow!(app, row[k])
        end
    end
    G.ImGui_EndTable()
end

# Every block gets an ID scope from its position, so two identical code blocks
# (same "copy" button label) never collide.
function draw_blocks!(app, bs::Vector{Blk}; tight::Bool = false)
    for (k, b) in enumerate(bs)
        G.ImGui_PushID(Cint(k))
        draw!(app, b)
        G.ImGui_PopID()
        tight || G.ImGui_Dummy(Ref(vec2(0, app.fonts.size * 0.35f0)))
    end
end

"""Draw a reply's segments, skipping the ones scrolled out of view."""
function draw_markdown!(app, t)
    G.ImGui_PushID(Cint(t.id))
    w = G.ImGui_GetContentRegionAvail().x
    for (i, sg) in enumerate(t.segs)
        y0 = G.ImGui_GetCursorPosY()
        if sg.h > 0 && sg.w == w && !G.ImGui_IsRectVisible(Ref(vec2(w, sg.h)))
            # Advance exactly as drawing it would: Dummy adds ItemSpacing itself.
            G.ImGui_Dummy(Ref(vec2(0, max(0f0, sg.h - app.spacing_y))))
        else
            G.ImGui_PushID(Cint(i))
            draw_blocks!(app, sg.blocks)
            G.ImGui_PopID()
            sg.h = G.ImGui_GetCursorPosY() - y0
            sg.w = w
        end
    end
    G.ImGui_PopID()
end
