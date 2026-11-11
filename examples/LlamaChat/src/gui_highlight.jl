# Syntax colours for code blocks. Included by gui_md.jl, inside `module GUI`.
#
# A block is highlighted once, when its markdown segment is parsed (so a
# streaming reply re-highlights only its open tail), into lines of coloured
# runs that the code block draws with one TextUnformatted per run.
#
#   * Julia goes through JuliaSyntaxHighlighting, which runs Julia's own parser
#     and annotates the text with faces (julia_funcdef, julia_number, …).
#   * Everything else goes through a small tokenizer: comments, strings,
#     numbers, keywords, types, preprocessor lines, shell variables, and a name
#     followed by `(` as a function. Not a parser, but it gives the
#     int-vs-function distinction an editor shows, in the languages models
#     write most.
#   * Unknown or plain languages ("", "text", "output", …) stay uncoloured.

import JuliaSyntaxHighlighting

# A Dark+-style palette, as ImU32 (0xAABBGGRR). 0 means "the text colour".
_col(rgb::UInt32) = 0xff000000 | ((rgb & 0xff) << 16) | (rgb & 0x00ff00) | ((rgb >> 16) & 0xff)
const HL_KEYWORD  = _col(0xC586C0)
const HL_CONST    = _col(0x569CD6)
const HL_FUNC     = _col(0xDCDCAA)
const HL_TYPE     = _col(0x4EC9B0)
const HL_NUMBER   = _col(0xB5CEA8)
const HL_STRING   = _col(0xCE9178)
const HL_COMMENT  = _col(0x6A9955)
const HL_MACRO    = _col(0x9CDCFE)
const HL_SYMBOL   = _col(0x4FC1FF)
const HL_PARENS   = (_col(0xFFD700), _col(0xDA70D6), _col(0x179FFF))

"""Lines of (text, colour) runs; colour 0 is the default text colour."""
const Runs = Vector{Vector{Tuple{String,UInt32}}}

# ── Julia: Julia's own highlighter ───────────────────────────────────────────

function _julia_face(f::Symbol)::UInt32
    s = String(f)
    if startswith(s, "julia_rainbow_")
        d = tryparse(Int, s[end:end])
        return HL_PARENS[mod1(something(d, 1), 3)]
    end
    s == "julia_comment"                                         && return HL_COMMENT
    s in ("julia_string", "julia_string_delim", "julia_cmd", "julia_cmd_delim") && return HL_STRING
    s == "julia_number"                                          && return HL_NUMBER
    s in ("julia_bool", "julia_singleton_identifier")            && return HL_CONST
    s == "julia_keyword"                                         && return HL_KEYWORD
    s in ("julia_funcall", "julia_funcdef")                      && return HL_FUNC
    s in ("julia_type", "julia_typedec")                         && return HL_TYPE
    s == "julia_macro"                                           && return HL_MACRO
    s == "julia_symbol"                                          && return HL_SYMBOL
    return UInt32(0)                                             # operators and the rest
end

function _julia_colors(code::String)
    colors = zeros(UInt32, ncodeunits(code))
    for a in Base.annotations(JuliaSyntaxHighlighting.highlight(code))
        a.label === :face || continue
        c = _julia_face(a.value)
        c == 0 && continue
        r = a.region
        colors[max(first(r), 1):min(last(r), length(colors))] .= c
    end
    # Julia's highlighter tags definitions but not every call; an untagged
    # name right before `(` is a call, as an editor would colour it.
    for m in eachmatch(r"(?<![\p{L}\p{N}_!.])([\p{L}_][\p{L}\p{N}_!]*)(?=\()", code)
        r = m.offset:(m.offset + ncodeunits(m.match) - 1)
        all(iszero, view(colors, r)) && (colors[r] .= HL_FUNC)
    end
    return colors
end

# ── everything else: a small tokenizer ──────────────────────────────────────

struct LangSpec
    keywords::Set{String}
    consts::Set{String}
    types::Set{String}
    line::Vector{String}                    # line-comment openers
    block::Union{Nothing,Tuple{String,String}}
    preproc::Bool                           # `#` lines are preprocessor (C, C++)
    vars::Bool                              # $NAME, ${…} (shells)
    backtick::Bool                          # `…` is a string
    capital_types::Bool                     # Capitalised names are types
    keys::Bool                              # data formats: `key =`, `"key":`, `[section]`
end
LangSpec(kw, cs, ty, line, block, pre, vars, bt, cap) = LangSpec(kw, cs, ty, line, block, pre, vars, bt, cap, false)

_set(s) = Set{String}(String.(split(s)))

const _CLIKE_TYPES = "void int char short long float double bool unsigned signed size_t ssize_t ptrdiff_t " *
    "int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t intptr_t uintptr_t wchar_t auto"

const _LANGS = Dict{String,LangSpec}()
let C = LangSpec(_set("if else for while do switch case default break continue return goto sizeof typedef " *
                      "struct union enum class namespace using template typename public private protected " *
                      "virtual override final const constexpr consteval static extern inline volatile mutable " *
                      "new delete this operator friend explicit noexcept register try catch throw " *
                      "static_cast dynamic_cast reinterpret_cast const_cast decltype co_await co_return " *
                      "co_yield concept requires"),
                 _set("true false nullptr NULL"), _set(_CLIKE_TYPES * " std string vector map"),
                 ["//"], ("/*", "*/"), true, false, false, true)
    for l in ("c", "h", "cpp", "c++", "cc", "cxx", "hpp", "hh", "objc", "cuda", "cu", "glsl", "hlsl", "metal")
        _LANGS[l] = C
    end
    J = LangSpec(_set("abstract assert break case catch class continue default do else enum extends final " *
                      "finally for if implements import instanceof interface native new package private " *
                      "protected public return static super switch synchronized this throw throws try " *
                      "volatile while var record sealed permits yield fun val when object companion data " *
                      "override open internal lateinit using namespace foreach in is as get set async await"),
                 _set("true false null"), _set("int long short byte char float double boolean void String var"),
                 ["//"], ("/*", "*/"), false, false, false, true)
    for l in ("java", "kotlin", "kt", "cs", "csharp", "c#", "scala", "swift", "dart")
        _LANGS[l] = J
    end
    JS = LangSpec(_set("break case catch class const continue debugger default delete do else export extends " *
                       "finally for function if import in instanceof let new return super switch this throw " *
                       "try typeof var void while with yield async await of from as interface type enum " *
                       "implements declare namespace readonly keyof static get set"),
                  _set("true false null undefined NaN Infinity"),
                  _set("string number boolean any unknown never object symbol bigint"),
                  ["//"], ("/*", "*/"), false, false, true, true)
    for l in ("js", "javascript", "jsx", "ts", "typescript", "tsx", "mjs", "cjs")
        _LANGS[l] = JS
    end
    _LANGS["rust"] = _LANGS["rs"] = LangSpec(
        _set("as async await break const continue crate dyn else enum extern fn for if impl in let loop " *
             "match mod move mut pub ref return self Self static struct super trait type unsafe use where while"),
        _set("true false None Some Ok Err"),
        _set("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box"),
        ["//"], ("/*", "*/"), false, false, false, true)
    _LANGS["go"] = _LANGS["golang"] = LangSpec(
        _set("break case chan const continue default defer else fallthrough for func go goto if import " *
             "interface map package range return select struct switch type var"),
        _set("nil true false iota"),
        _set("int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 uintptr float32 float64 " *
             "complex64 complex128 byte rune string bool error any"),
        ["//"], ("/*", "*/"), false, false, true, false)
    P = LangSpec(_set("and as assert async await break class continue def del elif else except finally for " *
                      "from global if import in is lambda nonlocal not or pass raise return try while with " *
                      "yield match case self cls"),
                 _set("True False None"), _set("int float str list dict set tuple bool bytes object complex"),
                 ["#"], nothing, false, false, false, true)
    for l in ("python", "py", "python3", "ipython")
        _LANGS[l] = P
    end
    SH = LangSpec(_set("if then else elif fi for while until do done case esac function in return export " *
                       "local readonly declare select time coproc"),
                  _set("true false"),
                  _set("echo cd source alias unset shift exit sudo printf read eval exec test set trap " *
                       "pwd ls cat grep sed awk find mkdir rm cp mv chmod chown curl git make cmake julia pacman"),
                  ["#"], nothing, false, true, true, false)
    for l in ("bash", "sh", "shell", "zsh", "fish", "console", "terminal", "shell-session", "ksh", "dockerfile")
        _LANGS[l] = SH
    end
    _LANGS["lua"] = LangSpec(
        _set("and break do else elseif end for function goto if in local not or repeat return then until while"),
        _set("nil true false"), Set{String}(), ["--"], ("--[[", "]]"), false, false, false, false)
    _LANGS["sql"] = LangSpec(
        _set("select from where insert into values update set delete create table drop alter join inner " *
             "left right outer on group by order having limit offset as and or not in is like between " *
             "union distinct primary key foreign references index view begin commit rollback " *
             "SELECT FROM WHERE INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP ALTER JOIN INNER " *
             "LEFT RIGHT OUTER ON GROUP BY ORDER HAVING LIMIT OFFSET AS AND OR NOT IN IS LIKE BETWEEN " *
             "UNION DISTINCT PRIMARY KEY FOREIGN REFERENCES INDEX VIEW BEGIN COMMIT ROLLBACK"),
        _set("NULL null TRUE FALSE true false"),
        _set("int integer bigint text varchar char real float double boolean date timestamp blob " *
             "INT INTEGER BIGINT TEXT VARCHAR CHAR REAL FLOAT DOUBLE BOOLEAN DATE TIMESTAMP BLOB"),
        ["--"], ("/*", "*/"), false, false, false, false)
    D = LangSpec(Set{String}(), _set("true false null yes no on off True False"), Set{String}(),
                 ["#"], nothing, false, false, false, false, true)
    for l in ("toml", "ini", "cfg", "conf", "yaml", "yml", "json", "jsonc", "properties", "env", "dotenv",
              "make", "makefile", "cmake", "nix", "r", "ruby", "rb", "perl", "pl", "elixir", "ex")
        _LANGS[l] = D
    end
end

_isident(b::UInt8) = b == UInt8('_') || UInt8('a') <= b <= UInt8('z') || UInt8('A') <= b <= UInt8('Z') || UInt8('0') <= b <= UInt8('9')
_isdigit(b::UInt8) = UInt8('0') <= b <= UInt8('9')
_at(code, i, s) = i + ncodeunits(s) - 1 <= ncodeunits(code) && view(codeunits(code), i:i+ncodeunits(s)-1) == codeunits(s)
function _eol(code, i)
    j = findnext(==(UInt8('\n')), codeunits(code), i)
    return j === nothing ? ncodeunits(code) : j - 1
end

function _generic_colors(code::String, L::LangSpec)
    u = codeunits(code)
    n = length(u)
    colors = zeros(UInt32, n)
    paint!(a, b, c) = (colors[a:min(b, n)] .= c)
    i, linestart = 1, true
    while i <= n
        b = u[i]
        if b == UInt8('\n')
            linestart = true; i += 1; continue
        end
        if L.block !== nothing && _at(code, i, L.block[1])
            r = findnext(L.block[2], code, i + ncodeunits(L.block[1]))
            e = r === nothing ? n : last(r)
            paint!(i, e, HL_COMMENT); i = e + 1; linestart = false; continue
        end
        if any(o -> _at(code, i, o), L.line)
            e = _eol(code, i); paint!(i, e, HL_COMMENT); i = e + 1; continue
        end
        if L.preproc && linestart && b == UInt8('#')
            e = _eol(code, i); paint!(i, e, HL_MACRO); i = e + 1; continue
        end
        if b == UInt8(' ') || b == UInt8('\t')
            i += 1; continue
        end
        first = linestart
        linestart = false
        if L.keys && first && b == UInt8('[')                    # [section], [[array]]
            e = min(something(findnext(==(UInt8(']')), u, i), n), _eol(code, i))
            while e < n && u[e+1] == UInt8(']'); e += 1; end
            paint!(i, e, HL_KEYWORD); i = e + 1; continue
        end
        if b == UInt8('"') || b == UInt8('\'') || (L.backtick && b == UInt8('`'))
            j = i + 1
            while j <= n && u[j] != b && u[j] != UInt8('\n')
                j += u[j] == UInt8('\\') ? 2 : 1
            end
            e = min(j, n)
            k = e + 1
            while k <= n && (u[k] == UInt8(' ') || u[k] == UInt8('\t')); k += 1; end
            paint!(i, e, L.keys && k <= n && u[k] == UInt8(':') ? HL_MACRO : HL_STRING)   # "key":
            i = e + 1; continue
        end
        if L.vars && b == UInt8('$') && i < n && (u[i+1] == UInt8('{') || _isident(u[i+1]))
            j = i + 1
            if u[j] == UInt8('{')
                while j <= n && u[j] != UInt8('}'); j += 1; end
            else
                while j <= n && _isident(u[j]); j += 1; end
                j -= 1
            end
            e = min(j, n); paint!(i, e, HL_SYMBOL); i = e + 1; continue
        end
        if _isdigit(b) && (i == 1 || !_isident(u[i-1]))
            m = match(r"\G(0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(\.\d[\d_]*)?([eE][+-]?\d+)?)[a-zA-Z]*", code, i)
            e = m === nothing ? i : i + ncodeunits(m.match) - 1
            paint!(i, e, HL_NUMBER); i = e + 1; continue
        end
        if _isident(b)
            j = i
            while j <= n && _isident(u[j]); j += 1; end
            w = String(u[i:j-1])
            k = j
            while k <= n && (u[k] == UInt8(' ') || u[k] == UInt8('\t')); k += 1; end
            c = L.keys && first && k <= n && (u[k] == UInt8('=') || u[k] == UInt8(':')) ? HL_MACRO :
                w in L.keywords ? HL_KEYWORD :
                w in L.consts ? HL_CONST :
                w in L.types ? HL_TYPE :
                (k <= n && u[k] == UInt8('(')) ? HL_FUNC :
                (L.capital_types && isuppercase(Char(b)) && any(islowercase, w)) ? HL_TYPE : UInt32(0)
            c == 0 || paint!(i, j - 1, c)
            i = j; continue
        end
        i += 1
    end
    return colors
end

# ── lines of runs ────────────────────────────────────────────────────────────

function _runs(code::String, colors::Vector{UInt32})
    lines = Runs()
    cur = Tuple{String,UInt32}[]
    buf = IOBuffer()
    curc = UInt32(0)
    flush_run() = (position(buf) > 0 && push!(cur, (String(take!(buf)), curc)); nothing)
    for (i, ch) in pairs(code)
        if ch == '\n'
            flush_run(); push!(lines, cur); cur = Tuple{String,UInt32}[]
            continue
        end
        c = colors[i]
        c != curc && flush_run()
        curc = c
        ch == '\t' ? print(buf, "    ") : print(buf, ch)
    end
    flush_run(); push!(lines, cur)
    return lines
end

const _JULIA_LANGS = ("julia", "jl", "julia-repl", "jldoctest")

"""
    highlight_code(lang, code) -> Runs

`code` as lines of (text, colour) runs for the code block to draw. `lang` is
the fence's info string; its first word picks the highlighter.
"""
function highlight_code(lang::AbstractString, code::AbstractString)
    s = String(code)
    l = lowercase(first(split(String(lang) * " ", ' ')))
    colors = if l in _JULIA_LANGS
        try
            _julia_colors(s)
        catch e
            e isa InterruptException && rethrow()
            zeros(UInt32, ncodeunits(s))          # a highlighter failure costs the colour only
        end
    elseif haskey(_LANGS, l)
        _generic_colors(s, _LANGS[l])
    else
        zeros(UInt32, ncodeunits(s))
    end
    return _runs(s, colors)
end
