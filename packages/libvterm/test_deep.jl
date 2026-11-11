#!/usr/bin/env julia
# libvterm Hub package — deep integration test
#
# Assumes the wrapper is already built (builds it if missing). Drives a real
# terminal screen through every ABI point the header makes interesting:
#   - VTermScreenCellAttrs: 13 bitfields in one 32-bit word — 1-bit (bold),
#     2-bit (underline: curly = 3), 4-bit (font) fields through the generated
#     get_*/set_* accessors
#   - VTermColor: a union tagged by its first byte (palette index vs RGB, plus
#     the default-fg/bg flags)
#   - VTermScreenCell: uint32_t[6], char width, the bitfield word and two
#     unions, read back through vterm_screen_get_cell
#   - callbacks C calls back into Julia via @cfunction, with VTermRect and
#     VTermPos passed BY VALUE (damage, movecursor), a bool (sb_pushline4) and
#     a cell array pointer
#   - scrollback with the soft-wrap continuation flag (sb_pushline4)
#   - keyboard encoding out through vterm_output_read (Ctrl, cursor keys in
#     normal and application mode)
#   - UTF-8 and double-width cells, resize, the alternate screen
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/libvterm/test_deep.jl

using Test

const PKG_DIR = @__DIR__
const WRAPPER = joinpath(PKG_DIR, "julia", "Libvterm.jl")

if !isfile(WRAPPER)
    @info "Wrapper missing — building first"
    using RepliBuild
    RepliBuild.build(joinpath(PKG_DIR, "replibuild.toml"))
    RepliBuild.wrap(joinpath(PKG_DIR, "replibuild.toml"))
end

include(WRAPPER)
import .Libvterm
const V = Libvterm

# ── helpers ──────────────────────────────────────────────────────────────────

feed(vt, s::AbstractString) = V.vterm_input_write(vt, s, sizeof(s))

function cell(scr, row, col)
    ref = Ref(V.VTermScreenCell())
    V.vterm_screen_get_cell(scr, V.VTermPos(row, col), ref) == 1 || error("get_cell($row, $col) failed")
    return ref[]
end
char(c) = (u = c.chars[1]; u == 0 ? ' ' : Char(u))

function rowtext(scr, row, cols)
    buf = zeros(UInt8, 4cols + 8)
    n = V.vterm_screen_get_text(scr, buf, length(buf), V.VTermRect(row, row + 1, 0, cols))
    return String(buf[1:n])
end

function output!(vt)
    buf = zeros(UInt8, 64)
    n = V.vterm_output_read(vt, buf, length(buf))
    return String(buf[1:n])
end

# VTermColor's tag byte (vterm.h): bit 0 set = palette index, clear = RGB;
# bit 1 / bit 2 = "this is the default fg / bg". Then idx, or r g b.
colortag(c) = c.data[1]
is_indexed(c) = colortag(c) & 0x01 != 0
is_default_fg(c) = colortag(c) & 0x02 != 0

# ── C → Julia callbacks (top-level, non-closure, for @cfunction) ─────────────

const DAMAGE = V.VTermRect[]
damage_cb(rect::V.VTermRect, ::Ptr{Cvoid})::Cint = (push!(DAMAGE, rect); Cint(1))

const CURSOR = Ref((-1, -1, -1))
movecursor_cb(pos::V.VTermPos, ::V.VTermPos, visible::Cint, ::Ptr{Cvoid})::Cint =
    (CURSOR[] = (Int(pos.row), Int(pos.col), Int(visible)); Cint(1))

const BELLS = Ref(0)
bell_cb(::Ptr{Cvoid})::Cint = (BELLS[] += 1; Cint(1))

const PUSHED = Tuple{String,Bool}[]
function pushline4_cb(cols::Cint, cells::Ptr{V.VTermScreenCell}, cont::Bool, ::Ptr{Cvoid})::Cint
    io = IOBuffer()
    for i in 1:cols
        print(io, char(unsafe_load(cells, i)))
    end
    push!(PUSHED, (rstrip(String(take!(io))), cont))
    return Cint(1)
end

# libvterm keeps the pointer: the struct must outlive the screen.
const CALLBACKS = Ref{V.VTermScreenCallbacks}()

function with_term(f, rows, cols; callbacks = false)
    vt = V.vterm_new(rows, cols)
    vt == C_NULL && error("vterm_new failed")
    try
        V.vterm_set_utf8(vt, 1)
        scr = V.vterm_obtain_screen(vt)
        if callbacks
            CALLBACKS[] = V.VTermScreenCallbacks(
                @cfunction(damage_cb, Cint, (V.VTermRect, Ptr{Cvoid})),
                C_NULL,                                                         # moverect
                @cfunction(movecursor_cb, Cint, (V.VTermPos, V.VTermPos, Cint, Ptr{Cvoid})),
                C_NULL,                                                         # settermprop
                @cfunction(bell_cb, Cint, (Ptr{Cvoid},)),
                C_NULL, C_NULL, C_NULL, C_NULL,                                 # resize, sb_pushline/popline/clear
                @cfunction(pushline4_cb, Cint, (Cint, Ptr{V.VTermScreenCell}, Bool, Ptr{Cvoid})))
            V.vterm_screen_set_callbacks(scr, CALLBACKS, C_NULL)
            V.vterm_screen_callbacks_has_pushline4(scr)
        end
        V.vterm_screen_reset(scr, 1)
        return f(vt, scr)
    finally
        V.vterm_free(vt)
    end
end

@testset "libvterm deep" begin

@testset "macros and layout" begin
    @test V.VTERM_VERSION_MAJOR() == 0
    @test V.VTERM_VERSION_MINOR() == 3
    @test V.VTERM_MAX_CHARS_PER_CELL() == 6
    @test sizeof(V.VTermPos) == 8
    @test sizeof(V.VTermRect) == 16
    @test sizeof(V.VTermScreenCell) == 40            # 6×u32 + char + pad + attrs + 2 colours
    @test sizeof(V.VTermScreenCellAttrs) == 4         # 13 bitfields, one word
    @test sizeof(V.VTermColor) == 4                   # tag + 3 bytes
    @test sizeof(V.VTermScreenCallbacks) == 10 * sizeof(Ptr{Cvoid})
end

@testset "text and the bitfield word" begin
    with_term(5, 40) do vt, scr
        feed(vt, "hi \e[1;4:3;3;7;9mX\e[0m \e[11mF\e[10m n")
        @test rowtext(scr, 0, 40) == "hi X F n"
        x = cell(scr, 0, 3)
        @test char(x) == 'X'
        a = x.attrs
        @test V.get_bold(a) == 1
        @test V.get_underline(a) == 3                 # VTERM_UNDERLINE_CURLY: the 2-bit field
        @test V.get_italic(a) == 1
        @test V.get_reverse(a) == 1
        @test V.get_strike(a) == 1
        @test V.get_blink(a) == 0
        @test V.get_font(cell(scr, 0, 5).attrs) == 1   # SGR 11: the 4-bit field
        plain = cell(scr, 0, 0).attrs
        @test all(f -> f(plain) == 0, (V.get_bold, V.get_underline, V.get_italic, V.get_font))
        # The setter writes only its own bits.
        a2 = V.set_underline(a, 1)
        @test V.get_underline(a2) == 1 && V.get_bold(a2) == 1 && V.get_italic(a2) == 1
    end
end

@testset "the colour union" begin
    with_term(5, 40) do vt, scr
        feed(vt, "d\e[31mr\e[38;2;10;20;30mg\e[0m")
        d, r, g = cell(scr, 0, 0), cell(scr, 0, 1), cell(scr, 0, 2)
        @test is_default_fg(d.fg)
        @test is_indexed(r.fg) && r.fg.data[2] == 1     # palette index 1: red
        @test !is_indexed(g.fg) && g.fg.data[2:4] == (10, 20, 30)
        # vterm_screen_convert_color_to_rgb takes the union by pointer, in place.
        c = Ref(r.fg)
        V.vterm_screen_convert_color_to_rgb(scr, c)
        @test !is_indexed(c[])
    end
end

@testset "UTF-8 and double-width cells" begin
    with_term(5, 40) do vt, scr
        feed(vt, "é中a")
        @test char(cell(scr, 0, 0)) == 'é' && cell(scr, 0, 0).width == 1
        @test char(cell(scr, 0, 1)) == '中' && cell(scr, 0, 1).width == 2
        @test char(cell(scr, 0, 3)) == 'a'               # after the wide cell's two columns
        @test rowtext(scr, 0, 40) == "é中a"
    end
end

@testset "cursor position" begin
    with_term(5, 40) do vt, scr
        st = V.vterm_obtain_state(vt)
        feed(vt, "\e[3;5Hxy")
        p = Ref(V.VTermPos())
        V.vterm_state_get_cursorpos(st, p)
        @test (p[].row, p[].col) == (2, 6)
    end
end

@testset "callbacks, structs by value" begin
    empty!(DAMAGE); BELLS[] = 0; CURSOR[] = (-1, -1, -1)
    with_term(5, 20; callbacks = true) do vt, scr
        feed(vt, "abc")
        V.vterm_screen_flush_damage(scr)
        # Every written cell is inside some damage rect C passed by value.
        covered(r, c) = any(d -> d.start_row <= r < d.end_row && d.start_col <= c < d.end_col, DAMAGE)
        @test !isempty(DAMAGE)
        @test all(c -> covered(0, c), 0:2)
        @test all(d -> 0 <= d.start_row < d.end_row <= 5 && 0 <= d.start_col < d.end_col <= 20, DAMAGE)
        feed(vt, "\e[4;7H")
        @test CURSOR[] == (3, 6, 1)                  # two VTermPos by value, then an int
        feed(vt, "\a\a")
        @test BELLS[] == 2
    end
end

@testset "scrollback, with the soft-wrap flag" begin
    empty!(PUSHED)
    with_term(4, 10; callbacks = true) do vt, scr
        feed(vt, "one\r\n")
        feed(vt, "x"^14 * "\r\n")                    # wraps: 10 + 4
        feed(vt, "\r\n\r\n\r\n")                     # push them all off the top
        @test PUSHED[1] == ("one", false)
        @test PUSHED[2] == ("x"^10, false)
        @test PUSHED[3] == ("x"^4, true)             # continues the line above
    end
end

@testset "keyboard out through the output buffer" begin
    with_term(5, 20) do vt, scr
        V.vterm_keyboard_unichar(vt, UInt32('a'), V.VTERM_MOD_CTRL)
        @test output!(vt) == "\x01"
        V.vterm_keyboard_unichar(vt, UInt32('é'), V.VTermModifier(0))
        @test output!(vt) == "é"
        V.vterm_keyboard_key(vt, V.VTERM_KEY_UP, V.VTermModifier(0))
        @test output!(vt) == "\e[A"
        feed(vt, "\e[?1h")                           # DECCKM: application cursor keys
        V.vterm_keyboard_key(vt, V.VTERM_KEY_UP, V.VTermModifier(0))
        @test output!(vt) == "\eOA"
        V.vterm_keyboard_key(vt, V.VTERM_KEY_ENTER, V.VTermModifier(0))
        @test output!(vt) == "\r"
    end
end

@testset "resize and the alternate screen" begin
    with_term(5, 20) do vt, scr
        feed(vt, "primary")
        V.vterm_set_size(vt, 8, 30)
        r, c = Ref{Cint}(0), Ref{Cint}(0)
        V.vterm_get_size(vt, r, c)
        @test (r[], c[]) == (8, 30)
        @test rowtext(scr, 0, 30) == "primary"
        V.vterm_screen_enable_altscreen(scr, 1)
        feed(vt, "\e[?1049h\e[HALT")
        @test rowtext(scr, 0, 30) == "ALT"
        feed(vt, "\e[?1049l")
        @test rowtext(scr, 0, 30) == "primary"
    end
end

end

println("✓ libvterm deep test passed")
