# The raylib window for orbit scenes: the same renderer as the physics viewer
# (lit spheres, orbit camera), plus trails, labels, a clock and time controls.
# Positions come from the Float64 OrbitSim and are only turned into Float32
# (and scaled, 1 AU = `scale` drawing units) at the moment they are drawn.

const _OK = (space = 32, b = 66, r = 82, h = 72, l = 76, t = 84, tab = 258, lbracket = 91, rbracket = 93,
             comma = 44, period = 46)

# Background stars: fixed directions, drawn around the camera at a distance
# no zoom reaches, self-lit so the bright ones bloom. Three brightness groups
# (three instanced draw calls). Directions spread over the sphere with a
# golden-angle spiral, jittered by a hash so there is no visible pattern.
const _STAR_R = 20_000f0
_hash01(x) = (v = sin(x * 12.9898) * 43758.5453; v - floor(v))
function _star_field(n::Int = 3000)
    groups = (dim = Tuple{Vec3,Float32}[], white = Tuple{Vec3,Float32}[], blue = Tuple{Vec3,Float32}[])
    for i in 0:n - 1
        z = 1 - 2 * (i + 0.5) / n
        θ = i * 2.39996323 + 0.7 * _hash01(i)
        z = clamp(z + 0.002 * (_hash01(i + 0.5) - 0.5), -1, 1)
        r = sqrt(1 - z^2)
        d = Float32.((r * cos(θ), z, r * sin(θ)))
        k = _hash01(i * 1.7 + 3.1)
        size = Float32(0.6 + 1.4 * _hash01(i * 2.3 + 1.3)^3)
        push!(k < 0.80 ? groups.dim : k < 0.96 ? groups.white : groups.blue, (d, size))
    end
    return groups
end

mutable struct _Trails
    pts::Dict{String,Vector{Vec3}}   # by body name (bodies are renumbered when two merge)
    every::Float64                   # sim time between samples
    last::Float64
    max::Int
end

function _trail_sample!(tr::_Trails, s::OrbitSim, sc)
    t = orbit_time(s)
    t - tr.last < tr.every && return
    tr.last = t
    X = orbit_positions(s)
    alive = Set(b.name for b in s.bodies)
    filter!(kv -> kv.first in alive, tr.pts)                 # swallowed bodies' trails go
    for (i, b) in enumerate(s.bodies)
        pts = get!(tr.pts, b.name, Vec3[])
        push!(pts, _draw_pos(X, i, sc))
        length(pts) > tr.max && popfirst!(pts)
    end
end

# The light source: the most massive body, if it outweighs the next by 10×
# (a sun); otherwise there is none and light comes from above.
function _sun(s::OrbitSim)
    length(s.m) < 2 && return 0
    order = sortperm(s.m; rev = true)
    return s.m[order[1]] >= 10 * s.m[order[2]] ? order[1] : 0
end

# Physics frame has z up (ecliptic north); raylib's camera has y up.
_draw_pos(X, i, sc) = Float32.((X[1, i] * sc, X[3, i] * sc, -X[2, i] * sc))

# Drawn size: the body's own (exaggerated) size, but never under a few pixels
# at the current camera distance, so zooming in separates close pairs.
function _display_radius(b::OrbitBody, sys::OrbitSystem, cam_distance)
    r = b.display_radius !== nothing ? b.display_radius : b.radius * sys.exaggerate
    return Float32(max(r * sys.scale, 0.004 * cam_distance))
end

mutable struct _OrbitView
    menu::Bool
    tab::Int
    size_k::Float32                 # drawn body size multiplier
    show_stats::Bool
    next::Union{Nothing,String}
    quit::Bool
    restart::Bool
    merges_seen::Int
    message::String
    message_until::Float64
end
_OrbitView(menu::Bool) = _OrbitView(menu, 1, 1f0, false, nothing, false, false, 0, "", 0.0)

_fmt_time(t, units) = units == :solar ?
    (abs(t) < 730 ? "$(round(t; digits = 1)) days" : "$(round(t / 365.25; digits = 2)) years") :
    "t = $(round(t; digits = 3))"

"""
    run_orbits_window(scene; width = 1280, height = 760, frames = 0, screenshot = "",
                      presim = 0)

Open a window on an orbit scene (path or OrbitSystem). `frames > 0` runs that
many frames at a fixed time per frame and closes (for screenshots); `presim`
integrates that much time first.

Mouse: left/right-drag orbit, wheel zoom. ESC opens the menu (View, Bodies,
Scenes, Help). Keys: SPACE pause · [ ] slower / faster · TAB follow the next
body · L labels · T trails · B bloom · R restart · H help.

With `app = true` it returns the scene picked in the Scenes tab (or nothing);
otherwise the OrbitSim, as before. `record` writes an MP4 through ffmpeg and
shows no menu.
"""
function run_orbits_window(scene; width::Integer = 1280, height::Integer = 760, frames::Integer = 0,
                           screenshot::AbstractString = "", presim::Real = 0,
                           record::AbstractString = "", fps::Integer = 60,
                           app::Bool = false, menu::Bool = false)
    sys = scene isa OrbitSystem ? scene : load_orbits(scene)
    haskey(ENV, "DISPLAY") || haskey(ENV, "WAYLAND_DISPLAY") ||
        error("ObjectSim.run_orbits_window needs a display; use run_orbits instead")
    recording = !isempty(record)
    recording && Sys.which("ffmpeg") === nothing && error("ObjectSim: --record needs ffmpeg on PATH")
    rec = nothing                                    # ffmpeg's stdin, opened on the first frame
    ss = recording ? 2 : 1                           # a recording renders at 2x and is downsampled
    W, H = Cint(width * ss), Cint(height * ss)       # the recorded frame, whatever the window does
    u(x) = Cint(round(x * ss))                       # HUD sizes in recorded pixels
    R.SetTraceLogLevel(Cint(4))
    R.SetConfigFlags(Cuint(0x20 | 0x04 | 0x40))
    R.InitWindow(Cint(width), Cint(height), "ObjectSim orbits — $(sys.name)")
    R.IsWindowReady() || error("ObjectSim: raylib could not open a window")
    frames == 0 && !recording && R.SetTargetFPS(Cint(max(60, R.GetMonitorRefreshRate(R.GetCurrentMonitor()))))
    gpu = _gl_string(0x1F01)
    recording || R.SetExitKey(Cint(0))              # ESC opens the menu
    ui = _ui()
    ov = _OrbitView(menu && !recording)

    rr = _renderer(; shadows = false, bloom = true, bloom_threshold = 0.6, shadow_size = 16)
    _setv(rr, "fogColor", (0.04f0, 0.045f0, 0.06f0))
    R.rlSetClipPlanes(0.05, 40_000.0)                # far enough for the star field and a wide zoom
    sphere = _upload(sphere_mesh(1.0; seg = 40, rings = 20))
    star_mesh = _upload(sphere_mesh(1.0; seg = 6, rings = 4))
    stars = _star_field()
    rt = recording ? R.LoadRenderTexture(W, H) : nothing
    nrec = 0

    s = OrbitSim(sys)
    presim > 0 && advance_orbits!(s, presim)
    sc = sys.scale
    X0 = orbit_positions(s)
    extent = Float32(maximum(sqrt.(sum(abs2, X0; dims = 1))) * sc)
    extent = max(extent, 1f0)
    orbit = _Orbit((0f0, 0f0, 0f0), sys.view_distance === nothing ? 2.6f0 * extent :
                   Float32(sys.view_distance * sc), 30f0, 30f0, false)
    _setf(rr, "fogFar", extent * 12)
    speed = sys.days_per_second
    paused = false; labels = true; trails_on = true
    follow = 0                                       # 0 = centre of mass, else body index
    tr = _Trails(Dict{String,Vector{Vec3}}(), speed / 60, -Inf, 900)
    shot_ok = false
    frame = 0; t_open = time(); n_measure = 0; t_measure = 0.0
    try
        while !R.WindowShouldClose() && !ov.quit
            frame += 1
            if time() - t_open > 1.0
                t_measure == 0.0 && (t_measure = time()); n_measure += 1
            end
            dt_wall = recording ? 1 / fps : frames > 0 ? 1 / 60 : Float64(R.GetFrameTime())
            key(k) = R.IsKeyPressed(Cint(k))
            recording || _ui_input!(ui)
            on_menu = ov.menu && _ui_wants_mouse(ui)

            # ── input ────────────────────────────────────────────────────
            recording || (key(256) && (ov.menu = !ov.menu))          # ESC
            key(_OK.h) && !recording && (ov.menu = true; ov.tab = 4)
            key(_OK.space) && (paused = !paused)
            key(_OK.l) && (labels = !labels)
            key(_OK.b) && (rr.bloom = !rr.bloom)
            key(_OK.t) && (trails_on = !trails_on; empty!(tr.pts))
            if key(_OK.rbracket) || key(_OK.period)
                speed *= 2; tr.every = speed / 60
            end
            if key(_OK.lbracket) || key(_OK.comma)
                speed /= 2; tr.every = speed / 60
            end
            key(_OK.tab) && (follow = mod(follow + 1, length(s.bodies) + 1))
            if key(_OK.r) || ov.restart
                s = OrbitSim(sys); empty!(tr.pts); tr.last = -Inf; speed = sys.days_per_second
                ov.restart = false; ov.merges_seen = 0
            end
            if !on_menu
                if R.IsMouseButtonDown(Cint(0)) || R.IsMouseButtonDown(Cint(1))
                    d = R.GetMouseDelta()
                    orbit.yaw -= 0.3f0 * d.x
                    orbit.pitch = clamp(orbit.pitch + 0.3f0 * d.y, -85f0, 85f0)
                end
                orbit.distance = max(1f-3, orbit.distance * (1f0 - 0.1f0 * R.GetMouseWheelMove()))
            end

            # ── integrate ────────────────────────────────────────────────
            if !paused
                advance_orbits!(s, speed * dt_wall)
                trails_on && _trail_sample!(tr, s, sc)
            end
            X = orbit_positions(s)
            follow > length(s.bodies) && (follow = 0)
            orbit.target = follow == 0 ? (0f0, 0f0, 0f0) : _draw_pos(X, follow, sc)

            # ── draw ─────────────────────────────────────────────────────
            cam = _camera(orbit)
            eye = (cam.position.x, cam.position.y, cam.position.z)
            _setv(rr, "viewPos", eye)
            sun = _sun(s)
            # A sun is a point light at its position; without one, light from above.
            if sun == 0
                _seti(rr, "lightMode", 0); _setv(rr, "lightDir", (-0.3f0, -1f0, -0.2f0))
            else
                _seti(rr, "lightMode", 1); _setv(rr, "lightPos", _draw_pos(X, sun, sc))
            end
            batches = Dict{Any,_Batch}()
            for (i, b) in enumerate(s.bodies)
                rd = _display_radius(b, sys, orbit.distance) * ov.size_k
                rows = ((rd, 0f0, 0f0), (0f0, rd, 0f0), (0f0, 0f0, rd))
                _batch!(batches, sphere, :sphere, i == sun ? (0xff, 0xf0, 0xb0) : b.color, 0xff,
                        i == sun ? 1f0 : 0f0, _matrix(rows, _draw_pos(X, i, sc)))
            end
            star_size = _STAR_R * 0.0011f0
            for (g, col) in ((:dim, (0x6a, 0x6e, 0x80)), (:white, (0xf0, 0xf0, 0xf4)), (:blue, (0xb8, 0xd0, 0xff)))
                for (d, k) in getfield(stars, g)
                    sz = star_size * k
                    _batch!(batches, star_mesh, :star, col, 0xff, 1f0,
                            _matrix(((sz, 0f0, 0f0), (0f0, sz, 0f0), (0f0, 0f0, sz)), vadd(eye, vscale(d, _STAR_R))))
                end
            end
            recording ? R.BeginTextureMode(rt) : R.BeginDrawing()
            R.ClearBackground(R.Color(0x0a, 0x0b, 0x10, 0xff))
            R.BeginMode3D(cam)
            recording && (R.rlDrawRenderBatchActive(); R.rlSetLineWidth(Float32(ss)))
            if trails_on
                for b in s.bodies
                    pts = get(tr.pts, b.name, nothing)
                    pts === nothing && continue
                    c = b.color
                    n = length(pts)
                    for k in 2:n
                        a = UInt8(round(40 + 160 * k / n))
                        R.DrawLine3D(_rl_v3(pts[k - 1]), _rl_v3(pts[k]), R.Color(c[1], c[2], c[3], a))
                    end
                end
            end
            _seti(rr, "shadowsOn", 0)
            _draw_batches(rr, batches)
            R.EndMode3D()
            recording && R.rlSetLineWidth(1f0)
            _bloom_pass!(rr; target = recording ? rt : nothing)

            # ── labels and HUD ───────────────────────────────────────────
            fg = R.Color(0xe8, 0xe8, 0xe8, 0xff); dim = R.Color(0x9a, 0x9e, 0xa8, 0xff)
            warm = R.Color(0xff, 0xd0, 0x40, 0xff)
            if labels
                for (i, b) in enumerate(s.bodies)
                    pw = _rl_v3(_draw_pos(X, i, sc))
                    q = recording ? R.GetWorldToScreenEx(pw, cam, W, H) : R.GetWorldToScreen(pw, cam)
                    R.DrawText(b.name, Cint(round(q.x)) + u(8), Cint(round(q.y)) - u(8), u(14), dim)
                end
            end
            sw, sh = recording ? (W, H) : (R.GetScreenWidth(), R.GetScreenHeight())
            unit = sys.units == :solar ? "days" : "time units"
            if recording || ov.show_stats            # a recording keeps its title and clock
                R.DrawText("$(sys.name)   $(_fmt_time(orbit_time(s), sys.units))$(paused ? "   PAUSED" : "")",
                           u(14), u(12), u(20), fg)
                R.DrawText("$(length(s.bodies)) bodies   speed $(round(speed; sigdigits = 3)) $unit/s   " *
                           "energy drift $(round(energy_drift(s); sigdigits = 2))   following " *
                           (follow == 0 ? "centre of mass" : s.bodies[follow].name),
                           u(14), u(38), u(16), dim)
                for (k, m) in enumerate(s.mergers[max(1, end - 3):end])
                    R.DrawText("merged: $(m.a) + $(m.b) at $(_fmt_time(m.t, sys.units))", u(14),
                               u(60 + 18 * (k - 1)), u(16), warm)
                end
            end
            if !recording
                if length(s.mergers) > ov.merges_seen          # a new collision: say so briefly
                    m = s.mergers[end]; ov.merges_seen = length(s.mergers)
                    ov.message = "$(m.a) fell into $(m.b) at $(_fmt_time(m.t, sys.units))"; ov.message_until = time() + 2.5
                end
                if ov.menu
                    st = (; speed, paused, labels, trails_on, follow, trail_max = tr.max)
                    st = _orbit_menu!(ui, ov, s, sys, rr, st, gpu, sw, sh)
                    speed, paused, labels, follow = st.speed, st.paused, st.labels, st.follow
                    st.trails_on != trails_on && empty!(tr.pts)
                    trails_on = st.trails_on; tr.max = st.trail_max; tr.every = speed / 60
                else
                    _hint(sw, sh, "$(_fmt_time(orbit_time(s), sys.units))$(paused ? "   PAUSED" : "")")
                end
                _toast(ov.message, ov.message_until, sw, sh)
            end
            if recording
                R.EndTextureMode()
                img = R.LoadImageFromTexture(rt.texture)   # RGBA8, bottom row first
                try
                    w, h = Int(img.width), Int(img.height)
                    if rec === nothing
                        rec = open(`ffmpeg -y -loglevel error -f rawvideo -pix_fmt rgba -s $(w)x$(h)
                                    -r $fps -i - -vf vflip,scale=$(width ÷ 2 * 2):$(height ÷ 2 * 2):flags=lanczos
                                    -c:v libx264 -preset slow -crf 23 -pix_fmt yuv420p -movflags +faststart
                                    $record`, "w")
                    end
                    write(rec, unsafe_wrap(Array, Ptr{UInt8}(img.data), w * h * 4)); nrec += 1
                finally
                    R.UnloadImage(img)
                end
                # show what is being recorded, letterboxed into the window
                R.BeginDrawing()
                R.ClearBackground(R.Color(0x00, 0x00, 0x00, 0xff))
                vw, vh = R.GetScreenWidth(), R.GetScreenHeight()
                k = min(vw / W, vh / H)
                R.DrawTexturePro(rt.texture, R.Rectangle(0, 0, W, -H),
                                 R.Rectangle((vw - k * W) / 2, (vh - k * H) / 2, k * W, k * H),
                                 R.Vector2(0, 0), 0, R.Color(0xff, 0xff, 0xff, 0xff))
            end
            if frames > 0 && frame >= frames
                if !isempty(screenshot)
                    R.rlDrawRenderBatchActive()
                    img = R.LoadImageFromScreen()
                    shot_ok = R.ExportImage(img, screenshot)
                    R.UnloadImage(img)
                end
                R.EndDrawing()
                break
            end
            R.EndDrawing()
            ov.next === nothing || break
        end
        n_measure > 30 && @info "ObjectSim: $(round(n_measure / (time() - t_measure); digits = 1)) frames/s " *
                                 "on average after the first second ($gpu)"
    finally
        if rec !== nothing
            close(rec); wait(rec)                    # ffmpeg finishes the file on EOF
            success(rec) ? @info("ObjectSim: recorded $nrec frames ($(round(nrec / fps; digits = 1)) s) to $record") :
                           @warn("ObjectSim: ffmpeg failed; the recording may be incomplete", record)
        end
        rt === nothing || R.UnloadRenderTexture(rt)
        R.UnloadMesh(sphere); R.UnloadMesh(star_mesh)
        _free!(rr)
        R.CloseWindow()
    end
    isempty(screenshot) || shot_ok || @warn "ObjectSim: screenshot was not written" screenshot
    return app ? ov.next : s
end

# ── the orbit window's menu ──────────────────────────────────────────────────

const _ORBIT_TABS = ("View", "Bodies", "Scenes", "Help")

function _orbit_menu!(ui::_UI, ov::_OrbitView, s::OrbitSim, sys::OrbitSystem, rr, st, gpu, sw, sh)
    speed, paused, labels, trails_on, follow, trail_max = st
    x, y, pw, ph = _menu_rect(sw, sh)
    _panel_begin!(ui, x, y, pw, ph; page = (:orbit, ov.tab))
    ov.tab = _tabs!(ui, _ORBIT_TABS, ov.tab)
    tab = _ORBIT_TABS[ov.tab]
    unit = sys.units == :solar ? "days" : "time units"
    if tab == "View"
        _heading!(ui, "Time")
        lo, hi = sys.units == :solar ? (0.05, 5000.0) : (0.01, 20.0)
        speed = _slider!(ui, :speed, "speed ($unit per second)", speed, lo, hi; log = true)
        _row!(ui, 3)
        _button!(ui, paused ? "Run" : "Pause"; on = paused) && (paused = !paused)
        _button!(ui, "Slower") && (speed /= 2)
        _button!(ui, "Faster") && (speed *= 2)
        _heading!(ui, "Look")
        ov.size_k = _slider!(ui, :size, "body size (×)", ov.size_k, 0.1, 20; log = true)
        labels = _toggle!(ui, "names", labels)
        trails_on = _toggle!(ui, "trails", trails_on)
        trails_on && (trail_max = round(Int, _slider!(ui, :trail, "trail length (points)", trail_max, 100, 5000; log = true)))
        rr.bloom = _toggle!(ui, "bloom (the sun and stars glow)", rr.bloom)
        rr.bloom && (rr.bloom_strength = _slider!(ui, :bs, "bloom strength", rr.bloom_strength, 0, 1))
        ov.show_stats = _toggle!(ui, "clock and stats on screen", ov.show_stats)
    elseif tab == "Bodies"
        _heading!(ui, "Follow")
        _button!(ui, "Centre of mass"; on = follow == 0) && (follow = 0)
        for (i, b) in enumerate(s.bodies)
            isodd(i) && _row!(ui, 2)
            _button!(ui, b.name; on = follow == i) && (follow = i)
        end
        _endrow!(ui)
        if follow > 0
            X = orbit_positions(s); V = orbit_velocities(s)
            b = s.bodies[follow]
            sun = _sun(s)
            ref = sun == 0 || sun == follow ? "centre of mass" : s.bodies[sun].name
            rp = sun == 0 || sun == follow ? X[:, follow] : X[:, follow] .- X[:, sun]
            rv = sun == 0 || sun == follow ? V[:, follow] : V[:, follow] .- V[:, sun]
            dunit = sys.units == :solar ? " AU" : ""
            _heading!(ui, b.name)
            _label!(ui, "mass $(round(s.m[follow]; sigdigits = 4))$(sys.units == :solar ? " M☉" : "")
" *
                        "distance from $ref $(round(sqrt(sum(abs2, rp)); sigdigits = 4))$dunit
" *
                        "speed $(round(sqrt(sum(abs2, rv)); sigdigits = 4))$dunit per $(sys.units == :solar ? "day" : "time unit")")
        end
        if !isempty(s.mergers)
            _heading!(ui, "Collisions")
            for m in s.mergers[max(1, end - 7):end]
                _label!(ui, "$(m.a) into $(m.b) at $(_fmt_time(m.t, sys.units))")
            end
        end
    elseif tab == "Scenes"
        phys, orbs = _scene_files()
        _heading!(ui, "Orbits")
        for (i, f) in enumerate(orbs)
            isodd(i) && _row!(ui, 2)
            n = splitext(basename(f))[1]
            _button!(ui, n; on = n == sys.name) && (ov.next = f)
        end
        _endrow!(ui)
        _heading!(ui, "Physics")
        for (i, f) in enumerate(phys)
            isodd(i) && _row!(ui, 2)
            _button!(ui, splitext(basename(f))[1]) && (ov.next = f)
        end
        _endrow!(ui)
        _heading!(ui, "This scene")
        _row!(ui, 2)
        _button!(ui, "Restart") && (ov.restart = true)
        _button!(ui, "Quit") && (ov.quit = true)
    else
        _heading!(ui, "Mouse")
        _label!(ui, "drag   turn the camera      wheel   zoom")
        _heading!(ui, "Keys")
        _label!(ui, "ESC menu      H this page
SPACE pause      [ ]  slower / faster
" *
                    "TAB follow the next body
L names   T trails   B bloom   R restart")
        _heading!(ui, "Now")
        _label!(ui, "$(sys.name)   $(_fmt_time(orbit_time(s), sys.units))
" *
                    "$(length(s.bodies)) bodies   energy drift $(round(energy_drift(s); sigdigits = 2))
" *
                    "integrator: DPRKN12 (Float64), tolerance 1e-13
$(R.GetFPS()) fps   $gpu")
    end
    _panel_end!(ui)
    return (; speed, paused, labels, trails_on, follow, trail_max)
end
