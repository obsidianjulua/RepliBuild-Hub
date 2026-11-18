# The window: a control panel (imgui) on the left, the system on the right
# (raylib). Attractors and the pendulum integrate live, a few hundred to a few
# thousand CVode calls a frame; any change to a parameter, method or tolerance
# restarts the run. An attractor's whole trail is re-integrated at once, so its
# shape follows a slider as it is dragged. Robertson runs its race (BDF against
# Adams, every step recorded) on each change and draws it as charts.

const PANEL_W = 390
const _BG = (0x0d, 0x0e, 0x13)

# raylib loads only ASCII from a TTF unless told which code points to take:
# Latin-1 (ö, ·) plus the few symbols the chart labels use.
const _FONT_CODEPOINTS = Cint[32:126; 160:255; 0x03bb; 0x2070; 0x2074:0x2079; 0x2192]

rgba(r, g, b, a = 255) = R.Color(UInt8(r), UInt8(g), UInt8(b), UInt8(a))
v3(t) = R.Vector3(Float32(t[1]), Float32(t[2]), Float32(t[3]))

# ── camera ──────────────────────────────────────────────────────────────────

mutable struct Orbit
    yaw::Float32
    pitch::Float32
    dist::Float32
    target::Vec3f
end
default_orbit(sys::System) = sys.kind == :pendulum ? Orbit(0f0, 8f0, 6.2f0, (0f0, -0.7f0, 0f0)) :
                                                     Orbit(35f0, 18f0, 9.5f0, (0f0, 0f0, 0f0))
function camera(o::Orbit)
    y, p = deg2rad(o.yaw), deg2rad(o.pitch)
    eye = o.target .+ o.dist .* Float32.((sin(y) * cos(p), sin(p), cos(y) * cos(p)))
    return R.Camera3D(v3(eye), v3(o.target), R.Vector3(0f0, 1f0, 0f0), 45f0, Cint(0))
end

# ── a live run (attractors and the pendulum) ────────────────────────────────

mutable struct Live
    sys::System
    p::Vector{Float64}
    method::Symbol
    rtol::Float64
    atol::Float64
    a::Any                      # Cvode; its type depends on the system's rhs!
    b::Any                      # the second run, or nothing
    shadow::Bool
    δ::Float64
    t::Float64
    t_goal::Float64
    flag::Int
    pts::Vector{Vec3f}
    pts_b::Vector{Vec3f}
    sep::Vector{Float32}        # log10 of the distance between the two runs
    ua::Vector{Float64}
    ub::Vector{Float64}
    I0::Float64
    drift_now::Float64
    drift_max::Float64
    ms::Float64                 # integration time per frame (smoothed)
    trail::Int
    lyap::Union{Nothing,Float64}
    changed::Bool               # trail changed since the last upload
end

function Live(sys::System)
    return Live(sys, defaults(sys), sys.method, sys.rtol, sys.atol, nothing, nothing,
                sys.kind == :pendulum, sys.kind == :pendulum ? 1e-6 : 1e-8, 0.0, 0.0, 0,
                Vec3f[], Vec3f[], Float32[], copy(sys.u0), copy(sys.u0), 0.0, 0.0, 0.0, 0.0,
                sys.trail, nothing, true)
end

function free_runs!(L::Live)
    L.a === nothing || free!(L.a)
    L.b === nothing || free!(L.b)
    L.a = L.b = nothing
end

_scale(L::Live) = 2.2 / (L.p[3] + L.p[4])          # pendulum: the whole thing fits in ~2.2 units

function _point(L::Live, u)
    if L.sys.kind == :pendulum
        _, (x2, y2) = pendulum_bobs(u, L.p)
        s = _scale(L)
        return (Float32(x2 * s), Float32(y2 * s), 0f0)
    end
    return Vec3f(Float32.(L.sys.view(u)))
end

"""Start the run again from the system's initial state with the current settings."""
function restart!(L::Live)
    free_runs!(L)
    sys = L.sys
    sys.kind == :chemistry && return L
    L.a = Cvode(sys.rhs!, sys.u0, L.p; method = L.method, rtol = L.rtol, atol = L.atol,
                quiet = true, maxsteps = 20_000)
    if L.shadow
        u0b = copy(sys.u0); u0b[1] += L.δ
        L.b = Cvode(sys.rhs!, u0b, L.p; method = L.method, rtol = L.rtol, atol = L.atol,
                    quiet = true, maxsteps = 20_000)
    end
    L.t = L.t_goal = 0.0
    L.flag = 0
    empty!(L.pts); empty!(L.pts_b); empty!(L.sep)
    copyto!(L.ua, sys.u0)
    push!(L.pts, _point(L, L.ua))
    L.shadow && push!(L.pts_b, _point(L, L.ua))
    L.I0 = sys.invariant === nothing ? 0.0 : sys.invariant(L.ua, L.p)
    L.drift_now = L.drift_max = 0.0
    L.lyap = nothing
    # An attractor's trail is filled at once: its shape is the point, and it
    # then follows a slider while it is being dragged.
    if sys.kind == :attractor
        t0 = time_ns()
        for _ in 1:L.trail
            _output!(L) || break
        end
        L.t_goal = L.t
        L.ms = (time_ns() - t0) / 1e6
    end
    L.changed = true
    return L
end

# One drawn point further: both runs to t + dt.
function _output!(L::Live)
    tn = L.t + L.sys.dt
    f = advance!(L.a, tn)
    if f < 0
        L.flag = f
        return false
    end
    state!(L.ua, L.a)
    push!(L.pts, _point(L, L.ua))
    if L.b !== nothing
        fb = advance!(L.b, tn)
        if fb < 0
            L.flag = fb
            return false
        end
        state!(L.ub, L.b)
        push!(L.pts_b, _point(L, L.ub))
        d = 0.0
        for i in eachindex(L.ua)
            d += (L.ua[i] - L.ub[i])^2
        end
        push!(L.sep, Float32(log10(max(sqrt(d), 1e-300))))
    end
    if L.sys.invariant !== nothing
        L.drift_now = (L.sys.invariant(L.ua, L.p) - L.I0) / abs(L.I0)
        L.drift_max = max(L.drift_max, abs(L.drift_now))
    end
    L.t = tn
    return true
end

function _trim!(v::Vector, n::Int)
    length(v) > n && deleteat!(v, 1:length(v) - n)
    return v
end

"""Advance by `speed × dt` time units (at most 5000 drawn points a frame)."""
function step_live!(L::Live, dt::Real, speed::Real)
    (L.a === nothing || L.flag < 0) && return
    L.t_goal += speed * dt
    t0 = time_ns()
    n = 0
    while L.t + L.sys.dt <= L.t_goal && n < 5000
        _output!(L) || break
        n += 1
    end
    n == 5000 && (L.t_goal = L.t)          # fell behind: drop the backlog rather than chase it
    if n > 0
        _trim!(L.pts, L.trail); _trim!(L.pts_b, L.trail); _trim!(L.sep, 600)
        L.changed = true
    end
    L.ms = 0.9 * L.ms + 0.1 * (time_ns() - t0) / 1e6
    return
end

# ── the app ─────────────────────────────────────────────────────────────────

mutable struct App
    gui::Gui
    ls::LineShader
    strip_a::Strip
    strip_b::Strip
    font::R.Font
    own_font::Bool
    idx::Int
    live::Live
    race::Any                   # race() result, or nothing
    race_budget::Float64
    orbit::Orbit
    speed::Float64
    paused::Bool
    spin::Bool
    glow::Bool
end

function switch!(app::App, i::Int)
    free_runs!(app.live)
    sys = SYSTEMS[i]
    app.idx = i
    app.live = Live(sys)
    app.orbit = default_orbit(sys)
    app.speed = sys.speed
    app.paused = false
    restart!(app.live)
    sys.kind == :chemistry && rerace!(app)
    return app
end

function rerace!(app::App)
    L = app.live
    app.race = race(; p = L.p, rtol = L.rtol, atol = L.atol, maxsteps = round(Int, app.race_budget))
    return app
end

"""
    OdeLab.run(system = :lorenz; width = 1440, height = 880, frames = 0,
               screenshot = "", visible = true) -> NamedTuple

Open the lab. `system` is where it starts (`:lorenz`, `:rossler`, `:pendulum`,
`:robertson`). `frames > 0` runs that many frames at a fixed 1/60 s each and
closes; `screenshot` then saves the last one. `visible = false` keeps the window
hidden (needs `frames`).

Mouse: drag to turn the camera, wheel to zoom. SPACE pauses, R restarts.
"""
function run(system_key::Symbol = :lorenz; width::Integer = 1440, height::Integer = 880,
             frames::Integer = 0, screenshot::AbstractString = "", visible::Bool = true)
    haskey(ENV, "DISPLAY") || error("OdeLab.run needs an X display (raylib's GLFW here is X11; Xwayland's :1)")
    visible || frames > 0 || throw(ArgumentError("a hidden window needs frames > 0"))
    i0 = findfirst(s -> s.key == system_key, SYSTEMS)
    i0 === nothing && throw(ArgumentError("no system :$system_key"))
    R.SetTraceLogLevel(Cint(4))                                   # warnings and up
    R.SetConfigFlags(Cuint(0x20 | 0x04 | (visible ? 0x40 : 0x80))) # MSAA, resizable, vsync | hidden
    R.InitWindow(Cint(width), Cint(height), "OdeLab")
    R.IsWindowReady() || error("OdeLab: raylib could not open a window")
    R.SetWindowMinSize(Cint(PANEL_W + 320), Cint(480))
    R.SetExitKey(Cint(0))
    app = nothing
    shot_ok = false
    n = 0
    result = nothing
    try
        gui = Gui()
        fpath = find_font()
        cps = _FONT_CODEPOINTS
        font = fpath === nothing ? R.GetFontDefault() :
               GC.@preserve cps R.LoadFontEx(fpath, Cint(36), pointer(cps), Cint(length(cps)))
        fpath === nothing || R.SetTextureFilter(font.texture, Cint(1))
        sys = SYSTEMS[i0]
        app = App(gui, LineShader(), Strip(), Strip(), font, fpath !== nothing, i0, Live(sys), nothing,
                  20_000.0, default_orbit(sys), sys.speed, false, true, true)
        switch!(app, i0)
        while !R.WindowShouldClose()
            n += 1
            dt = frames > 0 ? 1 / 60 : Float64(R.GetFrameTime())
            begin_frame!(gui)
            _panel!(app)
            _input!(app, dt)
            L = app.live
            L.sys.kind == :chemistry || app.paused || step_live!(L, dt, app.speed)

            R.BeginDrawing()
            R.ClearBackground(rgba(_BG...))
            L.sys.kind == :chemistry ? _draw_race(app) : _draw_3d(app)
            _hud(app)
            end_frame!(gui)
            if frames > 0 && n >= frames
                if !isempty(screenshot)
                    img = R.LoadImageFromScreen()
                    shot_ok = R.ExportImage(img, screenshot)
                    R.UnloadImage(img)
                end
                dd = unsafe_load(G.ImGui_GetDrawData())
                st = L.a === nothing ? nothing : stats(L.a)
                result = (frames = n, system = L.sys.key, t = L.t, flag = L.flag, stats = st,
                          points = length(L.pts), imgui_vertices = Int(dd.TotalVtxCount),
                          race = app.race === nothing ? nothing :
                                 (bdf = app.race.bdf.flag, adams = app.race.adams.flag))
                R.EndDrawing()
                break
            end
            R.EndDrawing()
        end
    finally
        if app !== nothing
            free_runs!(app.live)
            unload!(app.strip_a); unload!(app.strip_b); unload!(app.ls)
            app.own_font && R.UnloadFont(app.font)
            shutdown!(app.gui)
        end
        R.CloseWindow()
    end
    isempty(screenshot) || shot_ok || @warn "OdeLab: the screenshot was not written" screenshot
    return result === nothing ? (frames = n,) : result
end

function _input!(app::App, dt)
    g = app.gui
    if !wants_mouse(g)
        o = app.orbit
        if R.IsMouseButtonDown(Cint(0)) || R.IsMouseButtonDown(Cint(1))
            d = R.GetMouseDelta()
            o.yaw -= 0.3f0 * d.x
            o.pitch = clamp(o.pitch + 0.3f0 * d.y, -85f0, 85f0)
        end
        o.dist = clamp(o.dist * (1f0 - 0.1f0 * R.GetMouseWheelMove()), 0.5f0, 200f0)
    end
    if !wants_keyboard(g)
        R.IsKeyPressed(Cint(32)) && (app.paused = !app.paused)           # SPACE
        R.IsKeyPressed(Cint(82)) && restart!(app.live)                     # R
    end
    app.spin && app.live.sys.kind == :attractor && !app.paused && (app.orbit.yaw += Float32(4 * dt))
    return
end

# ── the panel ───────────────────────────────────────────────────────────────

_fmt(x::Real; d = 4) = x == 0 ? "0" : string(round(x; sigdigits = d))
_fmtt(t) = abs(t) >= 1e4 || (abs(t) < 1e-3 && t != 0) ? string(round(t; sigdigits = 4)) : string(round(t; digits = 3))
_flagtext(f) = f >= 0 ? "ok" : flagname(f)

function _panel!(app::App)
    L = app.live
    sys = L.sys
    G.ImGui_SetNextWindowPos(Ref(G.ImVec2(0f0, 0f0)), Int(G.ImGuiCond_Always), Ref(G.ImVec2(0f0, 0f0)))
    G.ImGui_SetNextWindowSize(Ref(G.ImVec2(Float32(PANEL_W), Float32(R.GetScreenHeight()))), Int(G.ImGuiCond_Always))
    flags = Int(G.ImGuiWindowFlags_NoTitleBar) | Int(G.ImGuiWindowFlags_NoResize) |
            Int(G.ImGuiWindowFlags_NoMove) | Int(G.ImGuiWindowFlags_NoCollapse) |
            Int(G.ImGuiWindowFlags_NoSavedSettings)
    G.ImGui_Begin("OdeLab", C_NULL, flags)
    text("OdeLab")
    dim("CVODE (SUNDIALS 7.9) · raylib · Dear ImGui")

    heading("System")
    pick = 0
    for (i, s) in enumerate(SYSTEMS)
        iseven(i) && sameline()
        radio(s.title, i == app.idx) && i != app.idx && (pick = i)
    end
    dim(sys.blurb; wrap = true)
    if pick > 0
        switch!(app, pick)
        G.ImGui_End()
        return
    end

    changed = false
    heading("Parameters")
    for (k, q) in enumerate(sys.params)
        r = Ref(L.p[k])
        if slider!(q.name, r, q.lo, q.hi; log = q.log)
            L.p[k] = r[]; changed = true
        end
    end
    button("Defaults##p") && (L.p .= defaults(sys); changed = true)

    heading("Integrator")
    if sys.kind != :chemistry
        radio("Adams (non-stiff)", L.method == :adams) && L.method != :adams && (L.method = :adams; changed = true)
        sameline()
        radio("BDF (stiff)", L.method == :bdf) && L.method != :bdf && (L.method = :bdf; changed = true)
    end
    r = Ref(L.rtol); slider!("rtol", r, 1e-13, 1e-2; log = true, fmt = "%.1e") && (L.rtol = r[]; changed = true)
    r = Ref(L.atol); slider!("atol", r, 1e-15, 1e-3; log = true, fmt = "%.1e") && (L.atol = r[]; changed = true)

    if sys.kind == :chemistry
        r = Ref(app.race_budget)
        slider!("Adams steps", r, 1000, 200_000; log = true, fmt = "%.0f") && (app.race_budget = r[]; changed = true)
        changed && rerace!(app)
        _race_panel(app)
        G.ImGui_End()
        return
    end

    heading("Time")
    r = Ref(app.speed); slider!("speed (t/s)", r, 0.01, 100; log = true) && (app.speed = r[])
    r = Ref(Float64(L.trail))
    if slider!("trail (points)", r, 100, 60_000; log = true, fmt = "%.0f")
        L.trail = round(Int, r[]); sys.kind == :attractor && (changed = true)
    end
    button(app.paused ? "Run" : "Pause") && (app.paused = !app.paused)
    sameline(); button("Restart") && (changed = true)
    sameline(); dim("SPACE  R")
    sh = Ref(L.shadow)
    checkbox!("second run, moved by δ", sh) && (L.shadow = sh[]; changed = true)
    if L.shadow
        r = Ref(L.δ); slider!("δ", r, 1e-14, 1e-1; log = true, fmt = "%.1e") && (L.δ = r[]; changed = true)
    end
    sp = Ref(app.spin); sys.kind == :attractor && checkbox!("turn the camera", sp) && (app.spin = sp[])
    gl = Ref(app.glow); checkbox!("glow (additive trails)", gl) && (app.glow = gl[])
    changed && restart!(L)

    heading("Now")
    st = L.a === nothing ? nothing : stats(L.a)
    rows = Any[("t", _fmtt(L.t)), ("status", _flagtext(L.flag))]
    if st !== nothing
        append!(rows, [("steps", string(st.steps)), ("rhs evaluations", string(st.rhs)),
                       ("Jacobians", string(st.jac)), ("order now", string(st.order)),
                       ("last step h", _fmt(st.h)), ("rejected steps", string(st.errfails)),
                       ("integration", "$(round(L.ms; digits = 2)) ms/frame")])
    end
    if sys.invariant !== nothing
        push!(rows, ("$(sys.invariant_name) drift", _fmt(L.drift_now; d = 3)))
        push!(rows, ("largest so far", _fmt(L.drift_max; d = 3)))
    end
    table("##now", rows)
    if L.shadow && !isempty(L.sep)
        dim("log10 distance between the two runs")
        plot("##sep", L.sep, -15, 2, PANEL_W - 24, 90; overlay = "now $(round(L.sep[end]; digits = 2))")
        dim("A straight climb is exponential growth; its slope × ln 10 is the Lyapunov exponent.";
            wrap = true)
    end
    if sys.kind == :attractor
        if button("Measure λ (Benettin)")
            L.lyap = lyapunov(sys.key; p = L.p, T = sys.key == :rossler ? 3000.0 : 1000.0)
        end
        L.lyap === nothing || (sameline(); text("λ ≈ $(round(L.lyap; digits = 4))"))
    end
    G.ImGui_End()
    return
end

function _race_panel(app::App)
    rc = app.race
    rc === nothing && return
    heading("The race, from 0 to 4·10¹⁰")
    for (name, m) in (("BDF", rc.bdf), ("Adams", rc.adams))
        text(name)
        table("##race" * name, [
            ("result", m.flag == 0 ? "finished" : m.flag == S.CV_TOO_MUCH_WORK() ? "out of steps" : flagname(m.flag)),
            ("reached t", _fmt(m.reached)), ("steps", string(m.stats.steps)),
            ("rhs evaluations", string(m.stats.rhs)), ("Jacobians", string(m.stats.jac)),
            ("largest step", _fmt(maximum(m.h; init = 0.0))), ("wall time", "$(round(m.ms; digits = 1)) ms")])
    end
    dim("Both use Newton iteration with the same dense solver; only the method differs. " *
        "Adams's step is held near the stability limit of the fastest reaction for as long " *
        "as it runs. BDF's grows by ten orders of magnitude.", wrap = true)
end

# ── drawing ─────────────────────────────────────────────────────────────────

# BeginMode3D frames the whole window, and the panel covers its left side. So
# the 3D view gets its own GL viewport right of the panel, and a projection with
# that viewport's aspect (same 45° vertical field of view raylib uses).
function _begin_3d(app::App)
    R.BeginMode3D(camera(app.orbit))
    sw, sh = R.GetScreenWidth(), R.GetScreenHeight()
    k = R.GetRenderWidth() / max(sw, 1)
    vw = max(sw - PANEL_W, 1)
    R.rlViewport(round(Int, PANEL_W * k), 0, round(Int, vw * k), round(Int, sh * k))
    near, far = R.rlGetCullDistanceNear(), R.rlGetCullDistanceFar()
    top = near * tan(deg2rad(45) / 2)
    right = top * vw / max(sh, 1)
    R.rlMatrixMode(0x1701)                       # RL_PROJECTION
    R.rlLoadIdentity()
    R.rlFrustum(-right, right, -top, top, near, far)
    R.rlMatrixMode(0x1700)                       # RL_MODELVIEW
end
function _end_3d()
    R.EndMode3D()
    R.rlViewport(0, 0, R.GetRenderWidth(), R.GetRenderHeight())
end

function _draw_3d(app::App)
    L = app.live
    if L.changed
        upload!(app.strip_a, L.pts)
        upload!(app.strip_b, L.pts_b)
        L.changed = false
    end
    _begin_3d(app)
    mvp = current_mvp()
    if L.sys.kind == :attractor
        R.rlPushMatrix(); R.rlTranslatef(0f0, -2.9f0, 0f0)
        R.DrawGrid(Cint(24), 0.5f0)
        R.rlPopMatrix()
        a_old, a_new = app.glow ? ((0.10f0, 0.30f0, 0.90f0, 0.10f0), (0.55f0, 0.85f0, 1.0f0, 0.85f0)) :
                                  ((0.20f0, 0.35f0, 0.80f0, 0.15f0), (0.55f0, 0.85f0, 1.0f0, 1.0f0))
        L.b === nothing || draw!(app.ls, app.strip_b, mvp, (0.9f0, 0.3f0, 0.1f0, 0.08f0), (1f0, 0.6f0, 0.2f0, 0.85f0);
                                 additive = app.glow)
        draw!(app.ls, app.strip_a, mvp, a_old, a_new; additive = app.glow)
        isempty(L.pts) || R.DrawSphereEx(v3(L.pts[end]), 0.06f0, Cint(8), Cint(8), rgba(255, 255, 255))
        isempty(L.pts_b) || R.DrawSphereEx(v3(L.pts_b[end]), 0.05f0, Cint(8), Cint(8), rgba(255, 160, 60))
    else
        _draw_pendulum(app, mvp)
    end
    _end_3d()
end

function _draw_pendulum(app::App, mvp)
    L = app.live
    s = _scale(L)
    L.b === nothing || draw!(app.ls, app.strip_b, mvp, (1f0, 0.5f0, 0.15f0, 0f0), (1f0, 0.6f0, 0.2f0, 0.7f0);
                             additive = app.glow)
    draw!(app.ls, app.strip_a, mvp, (0.2f0, 0.5f0, 1f0, 0f0), (0.6f0, 0.85f0, 1f0, 0.9f0); additive = app.glow)
    R.DrawCylinderEx(R.Vector3(-0.6f0, 0f0, 0f0), R.Vector3(0.6f0, 0f0, 0f0), 0.03f0, 0.03f0, Cint(8), rgba(90, 94, 110))
    rb(m) = Float32(0.07 * cbrt(m))
    # The second pendulum sits a little behind the first: while they still
    # agree (δ is 1e-6 rad) they would otherwise z-fight.
    function pend(u, rod, bob, alpha, z)
        (x1, y1), (x2, y2) = pendulum_bobs(u, L.p)
        p1 = (Float32(x1 * s), Float32(y1 * s), z); p2 = (Float32(x2 * s), Float32(y2 * s), z)
        R.DrawCylinderEx(R.Vector3(0f0, 0f0, z), v3(p1), 0.018f0, 0.018f0, Cint(8), rgba(rod..., alpha))
        R.DrawCylinderEx(v3(p1), v3(p2), 0.018f0, 0.018f0, Cint(8), rgba(rod..., alpha))
        R.DrawSphereEx(v3(p1), rb(L.p[1]), Cint(12), Cint(12), rgba(bob..., alpha))
        R.DrawSphereEx(v3(p2), rb(L.p[2]), Cint(12), Cint(12), rgba(bob..., alpha))
    end
    L.b === nothing || pend(L.ub, (200, 120, 70), (255, 150, 60), 150, -0.12f0)
    pend(L.ua, (200, 205, 215), (120, 190, 255), 255, 0f0)
end

function _text(app::App, s, x, y, size, col)
    R.DrawTextEx(app.font, s, R.Vector2(Float32(x), Float32(y)), Float32(size), 0.5f0, col)
end

function _hud(app::App)
    L = app.live
    sw = R.GetScreenWidth()
    L.sys.kind == :chemistry && return
    s = "$(L.sys.title)    t = $(_fmtt(L.t))$(app.paused ? "    paused" : "")$(L.flag < 0 ? "    " * flagname(L.flag) : "")"
    _text(app, s, PANEL_W + 18, 14, 20, rgba(220, 222, 230))
    _text(app, "$(R.GetFPS()) fps · drag to turn · wheel to zoom", PANEL_W + 18, 38, 16, rgba(130, 134, 146))
end

# ── Robertson's charts ──────────────────────────────────────────────────────

struct Axes
    x::Float32
    y::Float32
    w::Float32
    h::Float32
    xlo::Float64
    xhi::Float64
    ylo::Float64
    yhi::Float64
end
_px(a::Axes, v) = a.x + Float32((v - a.xlo) / (a.xhi - a.xlo)) * a.w
_py(a::Axes, v) = a.y + a.h - Float32((clamp(v, a.ylo, a.yhi) - a.ylo) / (a.yhi - a.ylo)) * a.h

function _axes(app::App, a::Axes, title, yticks, ylabel)
    R.DrawRectangle(round(Int, a.x), round(Int, a.y), round(Int, a.w), round(Int, a.h), rgba(18, 20, 27))
    grid = rgba(40, 44, 56); lab = rgba(140, 145, 158)
    for k in ceil(Int, a.xlo):floor(Int, a.xhi)
        x = _px(a, k)
        R.DrawLineV(R.Vector2(x, a.y), R.Vector2(x, a.y + a.h), grid)
        iseven(k) && _text(app, "1e$k", x - 12, a.y + a.h + 6, 15, lab)
    end
    for (v, l) in yticks
        y = _py(a, v)
        R.DrawLineV(R.Vector2(a.x, y), R.Vector2(a.x + a.w, y), grid)
        _text(app, l, a.x - 46, y - 8, 15, lab)
    end
    _text(app, title, a.x, a.y - 30, 20, rgba(220, 222, 230))
    _text(app, ylabel, a.x + a.w - 260, a.y - 26, 15, lab)
end

function _curve(a::Axes, xs, ys, col)
    pts = R.Vector2[]
    sizehint!(pts, length(xs))
    for i in eachindex(xs, ys)
        x, y = xs[i], ys[i]
        (isfinite(x) && isfinite(y) && a.xlo <= x <= a.xhi) || continue
        push!(pts, R.Vector2(_px(a, x), _py(a, y)))
    end
    length(pts) >= 2 && R.DrawLineStrip(pts, Cint(length(pts)), col)
end

function _draw_race(app::App)
    rc = app.race
    rc === nothing && return
    sw, sh = R.GetScreenWidth(), R.GetScreenHeight()
    x0 = PANEL_W + 70; w = sw - x0 - 30
    w < 100 && return
    h = (sh - 170) / 2
    lt(m) = log10.(m.t)
    xlo = floor(min(minimum(lt(rc.bdf); init = 0.0), minimum(lt(rc.adams); init = 0.0)))
    xlo = max(xlo, -10.0)
    xhi = ceil(log10(4e10))

    a1 = Axes(x0, 60, w, h, xlo, xhi, 0, 1.05)
    _axes(app, a1, "Concentrations", [(0.0, "0"), (0.5, "0.5"), (1.0, "1")],
          "y1 blue · 10⁴·y2 orange · y3 green")
    R.BeginScissorMode(round(Int, a1.x), round(Int, a1.y), round(Int, a1.w), round(Int, a1.h))
    for (m, alpha) in ((rc.adams, 110), (rc.bdf, 255))
        x = lt(m)
        _curve(a1, x, view(m.y, 1, :), rgba(90, 160, 255, alpha))
        _curve(a1, x, 1e4 .* view(m.y, 2, :), rgba(255, 160, 60, alpha))
        _curve(a1, x, view(m.y, 3, :), rgba(110, 210, 120, alpha))
    end
    R.EndScissorMode()

    lh(m) = log10.(m.h)
    hs = vcat(lh(rc.bdf), lh(rc.adams))
    ylo, yhi = floor(minimum(hs; init = -6.0)), ceil(maximum(hs; init = 0.0))
    a2 = Axes(x0, 60 + h + 80, w, h, xlo, xhi, ylo, yhi)
    _axes(app, a2, "Step size h", [(Float64(k), "1e$k") for k in Int(ylo):2:Int(yhi)],
          "BDF blue · Adams red")
    R.BeginScissorMode(round(Int, a2.x), round(Int, a2.y), round(Int, a2.w), round(Int, a2.h))
    _curve(a2, lt(rc.adams), lh(rc.adams), rgba(255, 90, 80))
    _curve(a2, lt(rc.bdf), lh(rc.bdf), rgba(90, 160, 255))
    R.EndScissorMode()

    if rc.adams.flag != 0 && rc.adams.reached > 0
        for a in (a1, a2)
            x = _px(a, log10(rc.adams.reached))
            R.DrawLineV(R.Vector2(x, a.y), R.Vector2(x, a.y + a.h), rgba(255, 90, 80, 160))
        end
        _text(app, "Adams spent its $(round(Int, app.race_budget)) steps by t = $(_fmt(rc.adams.reached; d = 3))",
              _px(a2, log10(rc.adams.reached)) + 8, a2.y + 8, 16, rgba(255, 120, 110))
    end
end
