# A small immediate-mode UI for the menus, drawn with raylib's 2D shapes.
#
# Immediate mode, as in Dear ImGui: every frame the menu code calls
#     m = _slider!(ui, :mass, "Mass (kg)", m, 0.05, 1000; log = true)
# and gets the (possibly changed) value back. There are no widget objects; a
# widget's identity is the `id` it is called with, which is how a slider keeps
# hold of the mouse while it is dragged. Layout is a single column that flows
# down a panel, with optional rows.
#
# Mouse capture: `_ui_wants_mouse(ui)` is true while the pointer is over the
# panel drawn last frame or a widget is being dragged; the viewers use it to
# keep clicks on the menu from also grabbing things in the scene.

const _UI_BG     = R.Color(0x12, 0x14, 0x1a, 0xf0)
const _UI_EDGE   = R.Color(0x2c, 0x30, 0x3a, 0xff)
const _UI_FIELD  = R.Color(0x22, 0x25, 0x2e, 0xff)
const _UI_HOVER  = R.Color(0x2e, 0x33, 0x40, 0xff)
const _UI_ACCENT = R.Color(0x3d, 0x8b, 0xd9, 0xff)
const _UI_TEXT   = R.Color(0xe8, 0xe8, 0xec, 0xff)
const _UI_DIM    = R.Color(0x9a, 0x9e, 0xa8, 0xff)
const _UI_WARM   = R.Color(0xff, 0xd0, 0x40, 0xff)

mutable struct _UI
    mx::Float32
    my::Float32
    down::Bool
    pressed::Bool
    wheel::Float32
    active::Any                         # id of the widget holding the mouse
    panel::NTuple{4,Float32}            # this frame's panel (x, y, w, h)
    last_panel::NTuple{4,Float32}       # last frame's, for mouse capture
    x::Float32                          # layout: left edge, cursor, width
    y::Float32
    w::Float32
    row::Vector{Float32}                # column x positions while in a row
    row_i::Int
    row_h::Float32
    scroll::Dict{Any,Float32}           # per-page scroll offset
    content_h::Float32
    page::Any
    fs::Int                             # font size
end

_ui() = _UI(0, 0, false, false, 0, nothing, (0, 0, 0, 0), (0, 0, 0, 0), 0, 0, 0, Float32[], 0, 0,
            Dict{Any,Float32}(), 0, nothing, 18)

"""Read the mouse for this frame. Call once per frame before any widget."""
function _ui_input!(ui::_UI)
    p = R.GetMousePosition()
    ui.mx, ui.my = p.x, p.y
    ui.down = R.IsMouseButtonDown(0)
    ui.pressed = R.IsMouseButtonPressed(0)
    ui.wheel = R.GetMouseWheelMove()
    ui.down || (ui.active = nothing)
    ui.last_panel = ui.panel
    ui.panel = (0f0, 0f0, 0f0, 0f0)
end

_inside(ui::_UI, x, y, w, h) = x <= ui.mx < x + w && y <= ui.my < y + h
"""Whether the menu has the mouse: over last frame's panel, or dragging a widget."""
_ui_wants_mouse(ui::_UI) = ui.active !== nothing || (ui.last_panel[3] > 0 && _inside(ui, ui.last_panel...))

# Always a String: a SubString (from split) passes a pointer into its parent,
# and C reads on to the parent's NUL, drawing every later line on top.
_text(t, x, y, size, c) = R.DrawText(String(t), Cint(round(x)), Cint(round(y)), Cint(size), c)
_measure(t, size) = Float32(R.MeasureText(String(t), Cint(size)))

"""
Open a panel. `page` keys its scroll position; content taller than the panel
scrolls with the wheel and is clipped.
"""
function _panel_begin!(ui::_UI, x, y, w, h; page = :main)
    ui.panel = Float32.((x, y, w, h))
    R.DrawRectangleRounded(R.Rectangle(Float32(x), Float32(y), Float32(w), Float32(h)), 0.03f0, 6, _UI_BG)
    R.DrawRectangleRoundedLines(R.Rectangle(Float32(x), Float32(y), Float32(w), Float32(h)), 0.03f0, 6, _UI_EDGE)
    ui.page = page
    s = get(ui.scroll, page, 0f0)
    if _inside(ui, x, y, w, h) && ui.wheel != 0
        s = clamp(s - 28f0 * ui.wheel, 0f0, max(0f0, ui.content_h - h + 24))
        ui.scroll[page] = s
    end
    ui.x = Float32(x) + 16; ui.w = Float32(w) - 32
    ui.y = Float32(y) + 14 - s
    ui.content_h = 0
    R.BeginScissorMode(Cint(x), Cint(y), Cint(w), Cint(h))
end

function _panel_end!(ui::_UI)
    R.EndScissorMode()
    x, y, w, h = ui.panel
    ui.content_h = ui.y + get(ui.scroll, ui.page, 0f0) - y
    if ui.content_h > h                                   # a scroll bar
        frac = h / ui.content_h
        off = get(ui.scroll, ui.page, 0f0) / ui.content_h
        R.DrawRectangle(Cint(round(x + w - 6)), Cint(round(y + off * h)), Cint(3), Cint(round(frac * h)), _UI_EDGE)
    end
end

# The box the next widget gets: the full width, or the next cell of a row.
function _cell!(ui::_UI, h)
    if !isempty(ui.row)
        i = ui.row_i += 1
        n = length(ui.row)
        cw = (ui.w - 6 * (n - 1)) / n
        x = ui.x + (i - 1) * (cw + 6)
        ui.row_h = max(ui.row_h, h)
        if i == n                                         # row complete
            empty!(ui.row); y = ui.y; ui.y += ui.row_h + 6
            return x, y, cw, h
        end
        return x, ui.y, cw, h
    end
    y = ui.y; ui.y += h + 6
    return ui.x, y, ui.w, h
end

"""Lay the next `n` widgets out side by side."""
_row!(ui::_UI, n::Integer) = (ui.row = zeros(Float32, n); ui.row_i = 0; ui.row_h = 0; ui)

_space!(ui::_UI, h = 8) = (ui.y += h; ui)

"""Close a row that has fewer widgets than it was made for."""
function _endrow!(ui::_UI)
    isempty(ui.row) && return ui
    ui.row_i > 0 && (ui.y += ui.row_h + 6)
    empty!(ui.row)
    return ui
end

function _heading!(ui::_UI, t)
    _space!(ui, 4)
    x, y, w, h = _cell!(ui, ui.fs + 4)
    _text(t, x, y, ui.fs + 2, _UI_TEXT)
    R.DrawRectangle(Cint(round(x)), Cint(round(y + ui.fs + 4)), Cint(round(w)), Cint(1), _UI_EDGE)
    _space!(ui, 4)
end

function _label!(ui::_UI, t; color = _UI_DIM, size = ui.fs - 2)
    for line in _wrap(t, ui.w, size)
        x, y, w, h = _cell!(ui, size)
        _text(line, x, y, size, color)
    end
end

# Lines of `t` broken at word boundaries to fit `width` pixels; a wrapped
# continuation keeps the line's own indent plus two spaces.
function _wrap(t, width, size)
    out = String[]
    for line in split(t, '\n')
        if _measure(line, size) <= width
            push!(out, String(line)); continue
        end
        indent = match(r"^ *", line).match
        cur = ""
        for word in split(line, r"(?<= )(?=\S)")        # keep each word's trailing spaces
            cand = cur * word
            if !isempty(cur) && _measure(rstrip(cand), size) > width
                push!(out, rstrip(cur)); cur = indent * "  " * word
            else
                cur = cand
            end
        end
        isempty(cur) || push!(out, rstrip(cur))
    end
    return out
end

"""A button; true on the frame it is clicked. `on` draws it as selected."""
function _button!(ui::_UI, t; on::Bool = false)
    x, y, w, h = _cell!(ui, ui.fs + 12)
    hover = ui.active === nothing && _inside(ui, x, y, w, h)
    R.DrawRectangleRounded(R.Rectangle(x, y, w, h), 0.25f0, 4, on ? _UI_ACCENT : hover ? _UI_HOVER : _UI_FIELD)
    t = String(t); tw = _measure(t, ui.fs - 2)
    if tw > w - 10                                          # too long: shorten to fit
        while length(t) > 1 && _measure(t * "..", ui.fs - 2) > w - 10
            t = first(t, length(t) - 1)
        end
        t *= ".."; tw = _measure(t, ui.fs - 2)
    end
    _text(t, x + (w - tw) / 2, y + (h - ui.fs + 2) / 2, ui.fs - 2, on ? R.Color(0xff, 0xff, 0xff, 0xff) : _UI_TEXT)
    return hover && ui.pressed
end

"""A row of buttons of which one is current; returns the (possibly new) index."""
function _choice!(ui::_UI, labels, cur::Integer)
    _row!(ui, length(labels))
    for (i, l) in enumerate(labels)
        _button!(ui, l; on = i == cur) && (cur = i)
    end
    return cur
end

"""A checkbox; returns the (possibly flipped) value."""
function _toggle!(ui::_UI, t, v::Bool)
    x, y, w, h = _cell!(ui, ui.fs + 6)
    hover = ui.active === nothing && _inside(ui, x, y, w, h)
    b = Float32(ui.fs)
    R.DrawRectangleRounded(R.Rectangle(x, y + 3, b, b), 0.3f0, 4, v ? _UI_ACCENT : hover ? _UI_HOVER : _UI_FIELD)
    v && _text("x", x + b / 2 - 4, y + 3, ui.fs - 2, R.Color(0xff, 0xff, 0xff, 0xff))
    _text(t, x + b + 10, y + 4, ui.fs - 2, _UI_TEXT)
    return (hover && ui.pressed) ? !v : v
end

_fmt(v) = abs(v) >= 100 ? string(round(Int, v)) : string(round(v; sigdigits = 3))

"""
A slider from `lo` to `hi`; returns the new value. `log` spaces it
logarithmically (for things like mass that span orders of magnitude).
"""
function _slider!(ui::_UI, id, t, v::Real, lo::Real, hi::Real; log::Bool = false, fmt = _fmt)
    x, y, w, h = _cell!(ui, ui.fs + 20)
    _text(t, x, y, ui.fs - 2, _UI_DIM)
    vs = fmt(v)
    _text(vs, x + w - _measure(vs, ui.fs - 2), y, ui.fs - 2, _UI_TEXT)
    ty = y + ui.fs + 4; th = 8f0
    to01(v) = log ? (Base.log(v) - Base.log(lo)) / (Base.log(hi) - Base.log(lo)) : (v - lo) / (hi - lo)
    from01(f) = log ? exp(Base.log(lo) + f * (Base.log(hi) - Base.log(lo))) : lo + f * (hi - lo)
    if ui.active === nothing && ui.pressed && _inside(ui, x, ty - 6, w, th + 12)
        ui.active = (ui.page, id)
    end
    if ui.active == (ui.page, id) && ui.down
        v = from01(clamp((ui.mx - x) / w, 0, 1))
    end
    f = clamp(to01(v), 0, 1)
    R.DrawRectangleRounded(R.Rectangle(x, ty, w, th), 1f0, 4, _UI_FIELD)
    R.DrawRectangleRounded(R.Rectangle(x, ty, max(th, f * w), th), 1f0, 4, _UI_ACCENT)
    R.DrawCircle(Cint(round(x + f * w)), Cint(round(ty + th / 2)), 7f0, _UI_TEXT)
    return v
end

"""Colour swatches; returns the clicked colour or `nothing`."""
function _swatches!(ui::_UI, colors, cur)
    _row!(ui, length(colors))
    picked = nothing
    for c in colors
        x, y, w, h = _cell!(ui, ui.fs + 8)
        hover = ui.active === nothing && _inside(ui, x, y, w, h)
        R.DrawRectangleRounded(R.Rectangle(x, y, w, h), 0.3f0, 4, R.Color(c[1], c[2], c[3], 0xff))
        (c == cur || hover) && R.DrawRectangleRoundedLines(R.Rectangle(x - 2, y - 2, w + 4, h + 4), 0.3f0, 4, _UI_TEXT)
        hover && ui.pressed && (picked = c)
    end
    return picked
end

"""Tabs across the top of a panel; returns the (possibly new) tab index."""
function _tabs!(ui::_UI, names, cur::Integer)
    _row!(ui, length(names))
    for (i, n) in enumerate(names)
        x, y, w, h = _cell!(ui, ui.fs + 14)
        hover = ui.active === nothing && _inside(ui, x, y, w, h)
        R.DrawRectangleRounded(R.Rectangle(x, y, w, h), 0.25f0, 4, i == cur ? _UI_ACCENT : hover ? _UI_HOVER : _UI_FIELD)
        tw = _measure(n, ui.fs - 2)
        _text(n, x + (w - tw) / 2, y + (h - ui.fs + 2) / 2, ui.fs - 2, _UI_TEXT)
        hover && ui.pressed && (cur = i)
    end
    _space!(ui, 6)
    return cur
end

"""A short message near the bottom of the screen that fades after `secs`."""
function _toast(msg, t_until, sw, sh)
    left = t_until - time()
    left <= 0 && return
    a = UInt8(round(255 * clamp(left / 0.6, 0, 1)))
    tw = _measure(msg, 18)
    x = (sw - tw) / 2
    R.DrawRectangleRounded(R.Rectangle(x - 14, sh - 64f0, tw + 28, 34), 0.4f0, 6, R.Color(0x12, 0x14, 0x1a, UInt8(round(0.9 * a))))
    _text(msg, x, sh - 56, 18, R.Color(0xe8, 0xe8, 0xec, a))
end

"""The one thing left on screen when the menu is closed."""
function _hint(sw, sh, extra = "")
    t = "ESC  menu" * (isempty(extra) ? "" : "    " * extra)
    _text(t, 14, sh - 26, 16, R.Color(0x9a, 0x9e, 0xa8, 0xb0))
end
