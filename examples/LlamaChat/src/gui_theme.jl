# Colour themes. Included by gui.jl, inside `module GUI`, after the colour Refs
# and gui_md.jl (so the code palette exists).
#
# A theme is a handful of RGB values. Applying one writes imgui's style colours
# (starting from its own Dark or Light set), the transcript's role colours, the
# status light, the code-block palette and the terminal's default colours. Code
# runs store a token CLASS, not a colour (gui_highlight.jl), so switching
# recolours code already on screen. The choice, and an optional accent of your
# own, persist in `~/.config/llamachat/theme`.

struct Theme
    name::String
    light::Bool                    # start from imgui's Light set instead of Dark
    bg::UInt32                     # 0xRRGGBB, as everywhere in this file
    text::UInt32
    dim::UInt32
    accent::UInt32                 # buttons, frames, headers, check marks
    user::UInt32
    bot::UInt32
    err::UInt32
    code::UInt32                   # inline `code`
    codebg::UInt32
    ready::UInt32; busy::UInt32; gen::UInt32; off::UInt32   # the status light
    hl::NTuple{12,UInt32}          # keyword const func type number string comment macro symbol paren×3
    term_fg::UInt32
    term_bg::UInt32
    md::NTuple{6,UInt32}           # markdown: heading 1, 2, 3, bold, italic, maths
end

const THEMES = Theme[
    Theme("Dark", false, 0x0F0F0F, 0xFFFFFF, 0x808080, 0x4296FA,
          0x8CBFFF, 0x8CE099, 0xFF7373, 0xF2BD7A, 0x1C1F26,
          0x66D973, 0xF2BF4D, 0x73B3FF, 0x8C8C8C,
          (0xC586C0, 0x569CD6, 0xDCDCAA, 0x4EC9B0, 0xB5CEA8, 0xCE9178, 0x6A9955,
           0x9CDCFE, 0x4FC1FF, 0xFFD700, 0xDA70D6, 0x179FFF),
          0xDDDDDD, 0x0F1317,
          (0x61AFEF, 0x56B6C2, 0xC678DD, 0xE5C07B, 0x9CDCFE, 0xD19A66)),
    Theme("Light", true, 0xF5F5F5, 0x1E1E1E, 0x7A7A7A, 0x2F6FD6,
          0x1F5FBF, 0x2E8B47, 0xC0392B, 0xA0522D, 0xE9ECEF,
          0x2E9E4A, 0xC88A12, 0x2F6FD6, 0x8C8C8C,
          (0xAF00DB, 0x0000FF, 0x795E26, 0x267F99, 0x098658, 0xA31515, 0x008000,
           0x001080, 0x0070C1, 0x0431FA, 0x319331, 0x7B3814),
          0x1E1E1E, 0xFFFFFF,
          (0x0B5CAD, 0x0E7C86, 0x8E44AD, 0x9A6700, 0x00698F, 0xA0522D)),
    Theme("Midnight", false, 0x0D1117, 0xC9D1D9, 0x8B949E, 0x8957E5,
          0x58A6FF, 0x3FB950, 0xF85149, 0xFFA657, 0x161B22,
          0x3FB950, 0xD29922, 0x58A6FF, 0x6E7681,
          (0xFF7B72, 0x79C0FF, 0xD2A8FF, 0xFFA657, 0x79C0FF, 0xA5D6FF, 0x8B949E,
           0x7EE787, 0x79C0FF, 0xFFD700, 0xDA70D6, 0x179FFF),
          0xC9D1D9, 0x0D1117,
          (0x79C0FF, 0xD2A8FF, 0x7EE787, 0xFFA657, 0xA5D6FF, 0xFF7B72)),
    Theme("Nord", false, 0x2E3440, 0xECEFF4, 0x7B88A1, 0x88C0D0,
          0x81A1C1, 0xA3BE8C, 0xBF616A, 0xEBCB8B, 0x3B4252,
          0xA3BE8C, 0xEBCB8B, 0x88C0D0, 0x4C566A,
          (0xB48EAD, 0x81A1C1, 0x88C0D0, 0x8FBCBB, 0xD08770, 0xA3BE8C, 0x616E88,
           0x5E81AC, 0xEBCB8B, 0xEBCB8B, 0xB48EAD, 0x88C0D0),
          0xD8DEE9, 0x2E3440,
          (0x88C0D0, 0x81A1C1, 0xB48EAD, 0xEBCB8B, 0x8FBCBB, 0xD08770)),
    Theme("Gruvbox", false, 0x282828, 0xEBDBB2, 0x928374, 0x458588,
          0x83A598, 0xB8BB26, 0xFB4934, 0xFABD2F, 0x32302F,
          0xB8BB26, 0xFABD2F, 0x83A598, 0x665C54,
          (0xFB4934, 0xD3869B, 0xB8BB26, 0xFABD2F, 0xD3869B, 0x8EC07C, 0x928374,
           0x83A598, 0xFE8019, 0xFABD2F, 0xD3869B, 0x83A598),
          0xEBDBB2, 0x282828,
          (0xFABD2F, 0x8EC07C, 0xD3869B, 0xFE8019, 0x83A598, 0xB8BB26)),
    Theme("Solarized", false, 0x002B36, 0x93A1A1, 0x586E75, 0x268BD2,
          0x268BD2, 0x859900, 0xDC322F, 0xB58900, 0x073642,
          0x859900, 0xB58900, 0x268BD2, 0x586E75,
          (0x859900, 0x2AA198, 0x268BD2, 0xB58900, 0xD33682, 0x2AA198, 0x586E75,
           0xCB4B16, 0x6C71C4, 0xB58900, 0xD33682, 0x268BD2),
          0x93A1A1, 0x002B36,
          (0x268BD2, 0x2AA198, 0x6C71C4, 0xCB4B16, 0x859900, 0xD33682)),
]

theme_named(name) = something(findfirst(t -> lowercase(t.name) == lowercase(String(name)), THEMES), 1)

_rgb(c::UInt32, a = 1) = vec4(((c >> 16) & 0xff) / 255, ((c >> 8) & 0xff) / 255, (c & 0xff) / 255, a)
_u32rgb(c::UInt32, a::Integer = 0xff) = (UInt32(a) << 24) | ((c & 0xff) << 16) | (c & 0x00ff00) | ((c >> 16) & 0xff)  # → ImU32
_mix(a::UInt32, b::UInt32, t) = reduce(|, (UInt32(round((1 - t) * ((a >> s) & 0xff) + t * ((b >> s) & 0xff))) << s for s in (16, 8, 0)))
_hex(c::UInt32) = "#" * string(c; base = 16, pad = 6)
_parsehex(s) = (m = match(r"^#?([0-9a-fA-F]{6})$", strip(s)); m === nothing ? nothing : parse(UInt32, m[1]; base = 16))

function _setcol!(idx, v::G.ImVec4)
    p = Ptr{G.ImVec4}(Ptr{UInt8}(style_ptr()) + G.member_offset("ImGuiStyle", "Colors")) + sizeof(G.ImVec4) * Int(idx)
    unsafe_store!(p, v)
end

"""The accent in force: the theme's, or the one picked in the Theme menu."""
accent(app) = app.accent_custom ? app.accent_rgb : THEMES[app.theme].accent

"""
    apply_theme!(app, k = app.theme)

Make `THEMES[k]` (and the custom accent, if one is set) the window's colours.
"""
function apply_theme!(app, k::Integer = app.theme)
    th = THEMES[k]
    app.theme = k
    th.light ? G.ImGui_StyleColorsLight(C_NULL) : G.ImGui_StyleColorsDark(C_NULL)
    a = accent(app)
    C = G
    _setcol!(C.ImGuiCol_WindowBg, _rgb(th.bg))
    _setcol!(C.ImGuiCol_PopupBg, _rgb(_mix(th.bg, th.text, 0.06), 0.98))
    _setcol!(C.ImGuiCol_Text, _rgb(th.text))
    _setcol!(C.ImGuiCol_TextDisabled, _rgb(th.dim))
    _setcol!(C.ImGuiCol_Border, _rgb(th.dim, 0.35))
    _setcol!(C.ImGuiCol_Separator, _rgb(th.dim, 0.45))
    for (idx, al) in ((C.ImGuiCol_FrameBg, 0.22), (C.ImGuiCol_FrameBgHovered, 0.40),
                      (C.ImGuiCol_FrameBgActive, 0.60), (C.ImGuiCol_Button, 0.40),
                      (C.ImGuiCol_ButtonHovered, 0.85), (C.ImGuiCol_Header, 0.22),
                      # Hover tints rows such as "Reasoning": at 80% a light accent
                      # (Nord's) washed the dim label out; 38% keeps it readable.
                      (C.ImGuiCol_HeaderHovered, 0.38), (C.ImGuiCol_HeaderActive, 0.50),
                      (C.ImGuiCol_TextSelectedBg, 0.35), (C.ImGuiCol_SeparatorHovered, 0.78),
                      (C.ImGuiCol_SeparatorActive, 1.0), (C.ImGuiCol_ResizeGrip, 0.20),
                      (C.ImGuiCol_ResizeGripHovered, 0.67), (C.ImGuiCol_ResizeGripActive, 0.95))
        _setcol!(idx, _rgb(a, al))
    end
    _setcol!(C.ImGuiCol_ButtonActive, _rgb(_mix(a, th.bg, 0.25)))
    _setcol!(C.ImGuiCol_CheckMark, _rgb(a))
    _setcol!(C.ImGuiCol_SliderGrab, _rgb(a))
    _setcol!(C.ImGuiCol_SliderGrabActive, _rgb(_mix(a, th.text, 0.3)))
    _setcol!(C.ImGuiCol_TableHeaderBg, _rgb(_mix(th.bg, a, 0.18)))
    _setcol!(C.ImGuiCol_TableBorderStrong, _rgb(th.dim, 0.55))
    _setcol!(C.ImGuiCol_TableBorderLight, _rgb(th.dim, 0.30))
    _setcol!(C.ImGuiCol_TableRowBgAlt, _rgb(th.text, 0.04))
    _setcol!(C.ImGuiCol_ScrollbarBg, _rgb(th.bg, 0.0))
    _setcol!(C.ImGuiCol_ScrollbarGrab, _rgb(th.dim, 0.45))
    _setcol!(C.ImGuiCol_ScrollbarGrabHovered, _rgb(th.dim, 0.65))
    _setcol!(C.ImGuiCol_ScrollbarGrabActive, _rgb(th.dim, 0.85))

    app.clear = _rgb(th.bg)
    app.dim[] = _rgb(th.dim)
    C_USER[] = _rgb(th.user);  C_BOT[] = _rgb(th.bot);   C_ERR[] = _rgb(th.err)
    C_CODE[] = _rgb(th.code);  C_CODEBG[] = _rgb(th.codebg)
    h1, h2, h3, bold, ital, math = th.md
    C_H[1][] = _rgb(h1); C_H[2][] = _rgb(h2); C_H[3][] = _rgb(h3)
    C_BOLD[] = _rgb(bold); C_ITALIC[] = _rgb(ital); C_MATH[] = _rgb(math)
    C_ACCENT[] = _rgb(a)
    C_QUOTE[] = _rgb(_mix(th.dim, ital, 0.45))
    C_READY[] = _rgb(th.ready); C_BUSY[] = _rgb(th.busy); C_GEN[] = _rgb(th.gen); C_OFF[] = _rgb(th.off)
    for (i, c) in enumerate(th.hl)
        HL_RGBA[i] = _u32rgb(c)
    end
    app.term_fg, app.term_bg = _u32rgb(th.term_fg), _u32rgb(th.term_bg)
    for t in app.terms
        t.fg, t.bg = app.term_fg, app.term_bg
        t.dirty .= true               # rows cache their colours; rebuild them
    end
    return app
end

# ── persistence ──────────────────────────────────────────────────────────────

theme_file() = joinpath(get(ENV, "XDG_CONFIG_HOME", joinpath(homedir(), ".config")), "llamachat", "theme")

"""`(name, accent)` from the theme file; `accent` is `nothing` when not customised."""
function load_theme_choice()
    f = theme_file()
    name, acc = "Dark", nothing
    isfile(f) || return (name, acc)
    for l in eachline(f)
        k, _, v = partition(l, '=')
        k == "theme"  && (name = strip(v))
        k == "accent" && (acc = _parsehex(v))
    end
    return (name, acc)
end
partition(s, c) = (i = findfirst(c, s); i === nothing ? (strip(s), "", "") : (strip(s[1:i-1]), c, s[i+1:end]))

function save_theme_choice(app)
    f = theme_file()
    try
        mkpath(dirname(f))
        write(f, "theme=$(THEMES[app.theme].name)\n" * (app.accent_custom ? "accent=$(_hex(app.accent_rgb))\n" : ""))
    catch e
        e isa InterruptException && rethrow()
        @warn "could not save the theme to $f" exception = e maxlog = 1
    end
end

# ── the Theme menu ───────────────────────────────────────────────────────────

const COLOR_FLAGS = flags(G.ImGuiColorEditFlags_NoInputs)

"""A combo in the status bar: the presets, then an accent of your own."""
function theme_menu!(app)
    G.ImGui_SetNextItemWidth(app.fonts.size * 7)
    if G.ImGui_BeginCombo("##theme", THEMES[app.theme].name, Cint(G.ImGuiComboFlags_HeightLarge))
        app.theme_open = true
        for (k, th) in enumerate(THEMES)
            G.ImGui_PushID(Cint(k))
            # A swatch of the theme: its background, accent and code colours.
            p = G.ImGui_GetCursorScreenPos()
            h = G.ImGui_GetTextLineHeight()
            dl = G.ImGui_GetWindowDrawList()
            for (i, c) in enumerate((th.bg, th.accent, th.hl[3], th.hl[6]))
                x = p.x + (i - 1) * h * 0.8f0
                G.ImDrawList_AddRectFilled(dl, Ref(vec2(x, p.y + 2)), Ref(vec2(x + h * 0.7f0, p.y + h - 2)),
                                           _u32rgb(c), 2f0, Cint(0))
            end
            G.ImGui_Dummy(Ref(vec2(h * 3.3f0, h)))
            G.ImGui_SameLine(0f0, -1f0)
            if G.ImGui_Selectable(th.name, k == app.theme, Cint(0), ZERO)
                app.accent_custom = false
                apply_theme!(app, k)
                save_theme_choice(app)
            end
            G.ImGui_PopID()
        end
        G.ImGui_Separator()
        a = app.accent_edit
        if !app.accent_custom
            c = accent(app)
            a .= Cfloat.((((c >> 16) & 0xff), ((c >> 8) & 0xff), (c & 0xff)) ./ 255)
        end
        if GC.@preserve a G.ImGui_ColorEdit3("Accent", pointer(a), COLOR_FLAGS)
            app.accent_custom = true
            app.accent_rgb = reduce(|, UInt32(round(clamp(a[i], 0, 1) * 255)) << s for (i, s) in ((1, 16), (2, 8), (3, 0)))
            apply_theme!(app)
            app.accent_dirty = true
        end
        if app.accent_custom
            G.ImGui_SameLine(0f0, -1f0)
            if G.ImGui_SmallButton("theme's own")
                app.accent_custom = false
                apply_theme!(app)
                save_theme_choice(app)
            end
        end
        G.ImGui_EndCombo()
    elseif app.theme_open
        app.theme_open = false
        app.refocus = true            # the menu took the keyboard; hand it back to the prompt
        if app.accent_dirty
            save_theme_choice(app)    # once the picker closes, not every drag step
            app.accent_dirty = false
        end
    end
    rect!(app, :theme)
end
