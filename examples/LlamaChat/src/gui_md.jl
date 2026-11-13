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

const S_BOLD, S_ITALIC, S_CODE, S_LINK, S_BREAK, S_MATH = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20

const C_CODE   = Ref(vec4(0.95, 0.74, 0.48))
const C_CODEBG = Ref(vec4(0.11, 0.12, 0.15))
# Markdown colours, set by the theme (`Theme.md`): headings by level, bold,
# italic, maths, quotes, and the accent that draws bars, bullets and rules.
const C_H      = (Ref(vec4(0.38, 0.69, 0.94)), Ref(vec4(0.34, 0.71, 0.76)), Ref(vec4(0.78, 0.47, 0.87)))
const C_BOLD   = Ref(vec4(0.90, 0.75, 0.48))
const C_ITALIC = Ref(vec4(0.61, 0.86, 1.00))
const C_MATH   = Ref(vec4(0.82, 0.60, 0.40))
const C_QUOTE  = Ref(vec4(0.60, 0.65, 0.70))
const C_ACCENT = Ref(vec4(0.26, 0.59, 0.98))
u32(c::Ref{G.ImVec4}, a::Real = 1) = G.ImGui_GetColorU32(Ref(vec4(c[].x, c[].y, c[].z, c[].w * a)))
const CODE_CHILD_FLAGS = flags(G.ImGuiChildFlags_Borders, G.ImGuiChildFlags_AutoResizeY,
                               G.ImGuiChildFlags_AlwaysUseWindowPadding)
const TABLE_FLAGS = flags(G.ImGuiTableFlags_Borders, G.ImGuiTableFlags_RowBg,
                          G.ImGuiTableFlags_SizingStretchProp)

"""
Text as this build can draw it. With 16-bit ImWchar a code point above U+FFFF
— most emoji — can never reach a glyph and draws as U+FFFD, so those are
dropped. The Hub's imgui is built with IMGUI_USE_WCHAR32 (`WCHAR_BYTES == 4`)
and FreeType, so other scripts beyond the BMP stay, and emoji stay when a
scalable colour emoji font is installed (`EMOJI`, see `load_fonts`). Either way
the invisible selectors and joiners that dress emoji go: imgui does no text
shaping, so they would only draw as gaps. The raw text (what **copy** puts on
the clipboard) keeps everything.
"""
# The font text is drawn in (set by `App`), and which characters it has. A
# character no merged font covers would draw as U+FFFD; better left out.
const GLYPH_FONT = Ref{Ptr{Cvoid}}(C_NULL)
const _HAS_GLYPH = Dict{Char,Bool}()
_has_glyph(c::Char) = GLYPH_FONT[] == C_NULL ||
    get!(() -> G.ImFont_IsGlyphInFont(GLYPH_FONT[], UInt32(c)), _HAS_GLYPH, c)

display_text(s::AbstractString) =
    any(_undrawable, s) ? filter(!_undrawable, String(s)) : String(s)
_undrawable(c::Char) = !isvalid(c) || (c > '￿' && (WCHAR_BYTES < 4 || (_is_emoji(c) && !EMOJI[]))) ||
                       c in ('︎', '️', '‍', '⃣') ||
                       (!isascii(c) && !_has_glyph(c))
# The emoji blocks: pictographs, transport, faces, supplemental symbols.
_is_emoji(c::Char) = '\U1F000' <= c <= '\U1FAFF'

# ── inline maths ─────────────────────────────────────────────────────────────

const _TEX = Dict(
    "rightarrow" => "→", "to" => "→", "leftarrow" => "←", "gets" => "←", "leftrightarrow" => "↔",
    "Rightarrow" => "⇒", "implies" => "⇒", "Leftarrow" => "⇐", "Leftrightarrow" => "⇔", "iff" => "⇔",
    "mapsto" => "↦", "uparrow" => "↑", "downarrow" => "↓", "longrightarrow" => "⟶",
    "times" => "×", "cdot" => "·", "div" => "÷", "pm" => "±", "mp" => "∓", "ast" => "∗",
    "approx" => "≈", "neq" => "≠", "ne" => "≠", "leq" => "≤", "le" => "≤", "geq" => "≥", "ge" => "≥",
    "ll" => "≪", "gg" => "≫", "sim" => "∼", "simeq" => "≃", "equiv" => "≡", "propto" => "∝",
    "infty" => "∞", "partial" => "∂", "nabla" => "∇", "sum" => "∑", "prod" => "∏", "int" => "∫",
    "oint" => "∮", "sqrt" => "√", "in" => "∈", "notin" => "∉", "subset" => "⊂", "subseteq" => "⊆",
    "cup" => "∪", "cap" => "∩", "forall" => "∀", "exists" => "∃", "emptyset" => "∅", "neg" => "¬",
    "land" => "∧", "lor" => "∨", "circ" => "∘", "degree" => "°", "angle" => "∠", "perp" => "⊥",
    "parallel" => "∥", "hbar" => "ħ", "ell" => "ℓ", "Re" => "ℜ", "Im" => "ℑ", "aleph" => "ℵ",
    "ldots" => "…", "dots" => "…", "cdots" => "⋯", "quad" => "  ", "qquad" => "    ",
    "langle" => "⟨", "rangle" => "⟩", "lfloor" => "⌊", "rfloor" => "⌋", "lceil" => "⌈", "rceil" => "⌉",
    "alpha" => "α", "beta" => "β", "gamma" => "γ", "delta" => "δ", "epsilon" => "ε", "varepsilon" => "ε",
    "zeta" => "ζ", "eta" => "η", "theta" => "θ", "vartheta" => "ϑ", "iota" => "ι", "kappa" => "κ",
    "lambda" => "λ", "mu" => "μ", "nu" => "ν", "xi" => "ξ", "pi" => "π", "rho" => "ρ", "sigma" => "σ",
    "tau" => "τ", "upsilon" => "υ", "phi" => "φ", "varphi" => "φ", "chi" => "χ", "psi" => "ψ",
    "omega" => "ω", "Gamma" => "Γ", "Delta" => "Δ", "Theta" => "Θ", "Lambda" => "Λ", "Xi" => "Ξ",
    "Pi" => "Π", "Sigma" => "Σ", "Phi" => "Φ", "Psi" => "Ψ", "Omega" => "Ω",
    "left" => "", "right" => "", "displaystyle" => "", "," => " ", ";" => " ", "!" => "",
)
const _SUP = Dict(zip("0123456789+-=()ni", "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿⁱ"))
const _SUB = Dict(zip("0123456789+-=()", "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎"))

_script(s, tbl, mark) = all(c -> haskey(tbl, c), s) ? map(c -> tbl[c], s) : string(mark, "(", s, ")")

@doc raw"""
    tex2uni(formula) -> String

Inline LaTeX as plain Unicode: `\rightarrow` → `→`, `x^2` → `x²`, `v_0` → `v₀`,
`\frac{a}{b}` → `(a)/(b)`, Greek letters, relations and operators. Models write
`$\rightarrow$` for an arrow in prose; drawn as source it read `\rightarrow`.
What it does not know stays as written, minus braces, in the maths colour.
"""
function tex2uni(f::AbstractString)
    s = String(f)
    s = replace(s, r"\\(?:text|mathrm|mathbf|mathit|mathsf|operatorname|textbf|textit)\s*\{([^{}]*)\}" => s"\1")
    s = replace(s, r"\\[dt]?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}" => s"(\1)/(\2)")
    s = replace(s, r"\\sqrt\s*\{([^{}]*)\}" => s"√(\1)")
    s = replace(s, r"\\([A-Za-z]+|[,;!])" => m -> get(_TEX, m[2:end], m))
    s = replace(s, r"\^\{([^{}]*)\}" => m -> _script(m[3:end-1], _SUP, '^'))
    s = replace(s, r"\^([0-9A-Za-z+\-])" => m -> _script(m[2:end], _SUP, '^'))
    s = replace(s, r"_\{([^{}]*)\}" => m -> _script(m[3:end-1], _SUB, '_'))
    s = replace(s, r"_([0-9])" => m -> _script(m[2:end], _SUB, '_'))
    s = replace(s, r"[{}]" => "")
    return strip(replace(s, r"\s+" => " "))
end

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
        spans!(out, tex2uni(x.formula), st | S_MATH)
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
    x isa MD.LaTeX          && return Para(spans!(Span[], tex2uni(x.formula), S_MATH))
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
        return blocks(MD.parse(LC._md_prep(raw)).content)
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
    st & (S_ITALIC | S_MATH) != 0 && return f.italic
    return f.regular
end

"""The colour a run is drawn in: code, maths and links keep theirs; inside a
heading the heading's; otherwise bold and italic have their own."""
function color_for(st::UInt8, heading)
    st & S_CODE   != 0 && return C_CODE
    st & S_MATH   != 0 && return C_MATH
    st & S_LINK   != 0 && return C_USER
    heading === nothing || return heading
    st & S_BOLD   != 0 && return C_BOLD
    st & S_ITALIC != 0 && return C_ITALIC
    return nothing
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
function flow!(app, sps::Vector{Span}, base::UInt8 = 0x00; scale::Float32 = 1f0, color = nothing)
    isempty(sps) && return nothing
    size = app.fonts.size * scale
    dl = G.ImGui_GetWindowDrawList()
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
        col = color_for(st, color)
        col === nothing || G.ImGui_PushStyleColor(Cint(G.ImGuiCol_Text), col)
        lh = G.ImGui_GetTextLineHeight()
        measure!(sp)
        for (k, p) in enumerate(sp.pieces)
            if !linestart && G.ImGui_GetCursorPosX() + sp.widths[k] > right
                G.ImGui_NewLine()                     # ends the line SameLine left open
                linestart = true
            end
            linestart && isspace(p[1]) && continue    # no blanks at the start of a line
            if st & S_CODE != 0                       # inline code sits on a pill
                q = G.ImGui_GetCursorScreenPos()
                G.ImDrawList_AddRectFilled(dl, Ref(vec2(q.x - 2, q.y)), Ref(vec2(q.x + sp.widths[k] + 2, q.y + lh)),
                                           u32(C_CODEBG), 3f0, Cint(0))
            end
            text!(p)
            if st & S_LINK != 0                       # links are underlined
                lo = G.ImGui_GetItemRectMin(); hi = G.ImGui_GetItemRectMax()
                G.ImDrawList_AddLine(dl, Ref(vec2(lo.x, hi.y - 1)), Ref(vec2(hi.x, hi.y - 1)), u32(C_USER, 0.6), 1f0)
            end
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
draw!(app, b::Plain) = text!(b.text)

"""A horizontal line in `c` fading to nothing: towards the right, or both ways."""
function fade_line!(c, y, thick; both::Bool = false)
    dl = G.ImGui_GetWindowDrawList()
    x0 = G.ImGui_GetCursorScreenPos().x
    w = G.ImGui_GetContentRegionAvail().x
    on, off = u32(c, 0.9), u32(c, 0.0)
    if both
        m = x0 + w / 2
        G.ImDrawList_AddRectFilledMultiColor(dl, Ref(vec2(x0, y)), Ref(vec2(m, y + thick)), off, on, on, off)
        G.ImDrawList_AddRectFilledMultiColor(dl, Ref(vec2(m, y)), Ref(vec2(x0 + w, y + thick)), on, off, off, on)
    else
        G.ImDrawList_AddRectFilledMultiColor(dl, Ref(vec2(x0, y)), Ref(vec2(x0 + w, y + thick)), on, off, off, on)
    end
end

function draw!(app, ::Rule)
    y = G.ImGui_GetCursorScreenPos().y + app.spacing_y
    fade_line!(C_ACCENT, y, 1.5f0; both = true)
    G.ImGui_Dummy(Ref(vec2(0, 2 * app.spacing_y)))
end

# Headings in their level's colour; levels 1 and 2 get an underline in it that
# fades out to the right, where a plain separator used to be.
function draw!(app, b::Heading)
    c = C_H[clamp(b.level, 1, 3)]
    flow!(app, b.spans, S_BOLD; scale = get(HEADING_SCALE, b.level, 1f0), color = c)
    if b.level <= 2
        thick = b.level == 1 ? 2f0 : 1f0
        fade_line!(c, G.ImGui_GetCursorScreenPos().y - app.spacing_y / 2, thick)
        G.ImGui_Dummy(Ref(vec2(0, thick)))
    end
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
                G.ImGui_PushStyleColor(Cint(G.ImGuiCol_Text), HL_RGBA[c])   # the ImU32 overload
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
        colored(() -> text!(b.start >= 0 ? string(b.start + k - 1, ".") : "•"), C_H[2])
        G.ImGui_SameLine(0f0, -1f0)
        G.ImGui_BeginGroup()            # wrapped lines return to here, not the margin
        draw_blocks!(app, item; tight = true)
        G.ImGui_EndGroup()
        G.ImGui_PopID()
    end
end

# A quote: indented, tinted, with a bar in the accent down its left edge.
function draw!(app, b::Quote)
    top = G.ImGui_GetCursorScreenPos()
    G.ImGui_Indent(app.fonts.size)
    G.ImGui_BeginGroup()
    colored(() -> draw_blocks!(app, b.body; tight = true), C_QUOTE)
    G.ImGui_EndGroup()
    G.ImGui_Unindent(app.fonts.size)
    bot = G.ImGui_GetItemRectMax().y
    x = top.x + app.fonts.size * 0.3f0
    G.ImDrawList_AddRectFilled(G.ImGui_GetWindowDrawList(), Ref(vec2(x, top.y)), Ref(vec2(x + 3, bot)),
                               u32(C_ACCENT, 0.85), 1.5f0, Cint(0))
end

function draw!(app, b::TableBlk)
    n = length(b.header)
    n == 0 && return
    G.ImGui_BeginTable("##table", Cint(n), TABLE_FLAGS, ZERO, 0f0) || return
    for h in b.header
        G.ImGui_TableSetupColumn(h, Cint(0), 0f0, Cuint(0))
    end
    colored(G.ImGui_TableHeadersRow, C_H[2])       # header text in the theme's heading colour
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
