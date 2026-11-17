# The raylib side: a window that draws a World while it runs.
#
# raylib never owns the simulation. Each frame the viewer hands bullet3 the
# frame time (or a fixed number of steps, for --frames), reads every body's
# interpolated pose from its motion state, and draws the body's TriMesh with
# it. The meshes are the same TriMesh the collision shapes were built from,
# uploaded once. Drawing goes through the shared renderer (render.jl): bodies
# are batched into instanced draw calls, shadowed, and the frame is bloomed.
#
# Matrix layout: raylib's Matrix struct is declared m0, m4, m8, m12, m1, …,
# i.e. its fields in declaration order are the matrix ROW by row (m12, m13,
# m14 is the translation). bullet3's btMatrix3x3 stores rows too, so a body
# transform maps field for field with no transpose. Do not memcpy bullet3's
# getOpenGLMatrix output into a raylib Matrix: that one is column-major.

const _BG = (0x1b, 0x1d, 0x23)

_rl_color(c, a = 0xff) = R.Color(UInt8(c[1]), UInt8(c[2]), UInt8(c[3]), UInt8(a))
_rl_v3(v) = R.Vector3(Float32(v[1]), Float32(v[2]), Float32(v[3]))

function _matrix(rows, o)
    r1, r2, r3 = rows
    return R.Matrix(r1[1], r1[2], r1[3], o[1],
                    r2[1], r2[2], r2[3], o[2],
                    r3[1], r3[2], r3[3], o[3],
                    0f0, 0f0, 0f0, 1f0)
end

# Upload a TriMesh. The vertex and normal arrays are malloc'd copies because
# UnloadMesh frees them with libc free.
function _upload(m::TriMesh)
    pos, nrm = render_arrays(m)
    n = length(pos)
    vp = Ptr{Cfloat}(Libc.malloc(4n)); unsafe_copyto!(vp, pointer(pos), n)
    np = Ptr{Cfloat}(Libc.malloc(4n)); unsafe_copyto!(np, pointer(nrm), n)
    ref = Ref(_with(R.Mesh(); vertexCount = Cint(n ÷ 3), triangleCount = Cint(n ÷ 9),
                    vertices = vp, normals = np))
    R.UploadMesh(ref, false)
    return ref[]
end

# Bodies built from the same geometry share one GPU mesh.
_mesh_key(s::ObjectSpec) = (s.shape, s.size, s.radius, s.height, s.asset, s.scale)

mutable struct _Orbit
    target::Vec3
    distance::Float32
    yaw::Float32
    pitch::Float32
    auto::Bool
end

function _orbit(w::World)
    c = w.scene.camera
    lo = (Inf32, Inf32, Inf32); hi = (-Inf32, -Inf32, -Inf32)
    for b in w.bodies
        rows, o = transform(b)
        mlo, mhi = aabb(b.mesh)
        # Skip huge static slabs (floors) when fitting: they would zoom far out.
        isstatic(b) && maximum(vsub(mhi, mlo)) > 30 && continue
        for corner in (mlo, mhi)
            p = vadd(o, _rotate(rows, corner))
            lo = min.(lo, p); hi = max.(hi, p)
        end
    end
    if !all(isfinite, lo)
        lo, hi = (-5f0, 0f0, -5f0), (5f0, 5f0, 5f0)
    end
    target = something(c.target, vscale(vadd(lo, hi), 0.5f0))
    dist = something(c.distance, 1.1f0 * vnorm(vsub(hi, lo)) + 4f0)
    return _Orbit(target, dist, c.yaw, c.pitch, c.orbit)
end

function _camera(o::_Orbit)
    y, p = deg2rad(o.yaw), deg2rad(o.pitch)
    eye = vadd(o.target, vscale(v3(sin(y) * cos(p), sin(p), cos(y) * cos(p)), o.distance))
    return R.Camera3D(_rl_v3(eye), _rl_v3(o.target), _rl_v3((0, 1, 0)), 45f0, Cint(0))
end

# ── interactive state ───────────────────────────────────────────────────────

const _ASSETS = normpath(joinpath(@__DIR__, "..", "assets"))
const _SCENES = normpath(joinpath(@__DIR__, "..", "scenes"))

# Keys (raylib.h KeyboardKey / MouseButton).
const _K = (space = 32, one = 49, b = 66, c = 67, e = 69, f = 70, g = 71, h = 72, j = 74, l = 76, n = 78,
            o = 79, r = 82, t = 84, x = 88, z = 90, escape = 256, delete = 261)
const _M = (left = 0, right = 1, middle = 2)

const _SPAWN_KINDS = ("Box", "Ball", "Capsule", "Drum", "Cone", "Rock", "Lamp")
const _GRAVITY_PRESETS = (("Earth", -9.81f0), ("Moon", -1.62f0), ("Mars", -3.71f0), ("Jupiter", -24.79f0), ("Zero", 0f0))
const _SKIES = ((0x1b, 0x1d, 0x23), (0x07, 0x08, 0x0c), (0x2a, 0x3a, 0x55), (0x6d, 0x86, 0xa8), (0x3a, 0x2a, 0x30))
const _SWATCHES = (PALETTE..., (0xe8, 0xe8, 0xe8), (0x3a, 0x3f, 0x4b))
const _MENU_TABS = ("World", "View", "Object", "Spawn", "Scenes", "Help")
const _LIQUIDS = (("Fresh", 1000f0, 1f0), ("Sea", 1025f0, 1f0), ("Oil", 900f0, 3f0),
                  ("Honey", 1420f0, 40f0), ("Mercury", 13534f0, 1.5f0))

mutable struct _View
    paused::Bool
    timescale::Float64
    sleep_tint::Bool
    show_joints::Bool
    show_contacts::Bool
    show_stats::Bool
    menu::Bool
    tab::Int
    orbiting::Bool                  # left-drag on empty space
    press_at::Tuple{Float32,Float32}
    hover::Union{Nothing,Body}
    selected::Union{Nothing,Body}
    message::String
    message_until::Float64
    palette_i::Int
    spawn_kind::Int                 # index into _SPAWN_KINDS
    spawn_size::Float32
    spawn_mass::Float32
    spawn_glow::Float32
    spawn_light::Float32
    sun_yaw::Float32                # main light direction, degrees
    sun_height::Float32
    next::Union{Nothing,String}     # a scene to switch to when the window closes
    quit::Bool
    restart::Bool
    motors::Float32                 # × the scene's motor speeds
    model_dir::Int                  # Spawn tab: which model folder is open
    follow::Bool                    # the camera keeps the selected body in the middle
    engine::String                  # the physics backend the world runs on
end

function _View(paused::Bool)
    # The default light (-0.6, -1, -0.42) as yaw/height.
    L = vunit((0.6f0, 1f0, 0.42f0))
    _View(paused, 1.0, false, true, false, false, false, 1, false, (0f0, 0f0), nothing, nothing, "", 0.0, 0,
          1, 1f0, 1f0, 0f0, 0f0, Float32(rad2deg(atan(L[1], L[3]))), Float32(rad2deg(asin(L[2]))), nothing, false,
          false, 1f0, 1, false, "")
end

_say!(v::_View, msg) = (v.message = msg; v.message_until = time() + 2.5; @info "ObjectSim: $msg")

"""The main light's direction (it points from the sun into the scene)."""
function _sun_dir(v::_View)
    y, h = deg2rad(v.sun_yaw), deg2rad(v.sun_height)
    return Float32.((-cos(h) * sin(y), -sin(h), -cos(h) * cos(y)))
end

function _mouse_ray(cam)
    r = R.GetScreenToWorldRay(R.GetMousePosition(), cam)
    return (r.position.x, r.position.y, r.position.z), (r.direction.x, r.direction.y, r.direction.z)
end

# Where the mouse points: the first thing it hits, else the ground plane y = 0.
function _aim(w::World, from, dir)
    hit = raycast(w, from, vadd(from, vscale(dir, 500f0)))
    hit !== nothing && return hit.point
    dir[2] < -1f-3 && return vadd(from, vscale(dir, -from[2] / dir[2]))
    return vadd(from, vscale(dir, 10f0))
end

function _next_color!(v::_View)
    v.palette_i += 1
    return PALETTE[mod1(v.palette_i, length(PALETTE))]
end

"""
What the spawn settings drop: kind `k` (1-7, as `_SPAWN_KINDS`), scaled by
`size`, 2.5 m above `at`. `mass` nothing = the kind's own; a lamp always glows.
"""
function _spawn_spec(k::Int, at, color; size = 1f0, mass = nothing, glow = 0f0, light = 0f0)
    s = Float32(size)
    p = vadd(at, (0f0, 1.5f0 + 1.2f0 * s, 0f0))
    o = if k == 1
        ObjectSpec(; name = "box", shape = :box, size = (0.8f0s, 0.8f0s, 0.8f0s), position = p, color)
    elseif k == 2
        ObjectSpec(; name = "ball", shape = :sphere, radius = 0.4f0s, position = p, color, rolling_friction = 0.02f0)
    elseif k == 3
        ObjectSpec(; name = "capsule", shape = :capsule, radius = 0.25f0s, height = 1.2f0s, position = p, color)
    elseif k == 4
        ObjectSpec(; name = "drum", shape = :cylinder, radius = 0.4f0s, height = 0.8f0s, position = p, color)
    elseif k == 5
        ObjectSpec(; name = "cone", shape = :cone, radius = 0.5f0s, height = 1.0f0s, position = p, color)
    elseif k == 7
        ObjectSpec(; name = "lamp", shape = :sphere, radius = 0.25f0s, mass = 0.5f0, position = p,
                   color = (0xff, 0xc0, 0x70), glow = 1f0, light = 6f0 * max(1f0, s), rolling_friction = 0.02f0)
    else
        ObjectSpec(; name = "rock", shape = :hull, asset = joinpath(_ASSETS, "rock.obj"), scale = (s, s, s),
                   mass = 3f0 * s^3, position = p, color, friction = 0.8f0, rolling_friction = 0.05f0)
    end
    mass === nothing || (o = _with(o; mass = Float32(mass)))
    k == 7 || (o = _with(o; glow = Float32(glow), light = Float32(light)))
    return o
end

# A file dropped on the window: a moving convex hull, scaled so its largest
# side is about 1.5 m when the file's own size is far from that.
function _dropped_spec(path, at, color; size = 1f0, mass = nothing)
    m = load_mesh(path)
    lo, hi = aabb(m)
    ext = maximum(vsub(hi, lo))
    k = Float32(((0.2f0 < ext < 4f0) ? 1f0 : 1.5f0 / ext) * size)
    h = (hi[2] - lo[2]) * k
    # Mass from the hull's volume at 500 kg/m³ (about wood: it floats).
    kg = mass === nothing ? Float32(clamp(500 * volume(m) * k^3, 0.05, 1e5)) : Float32(mass)
    return ObjectSpec(; name = splitext(basename(path))[1], shape = :hull, asset = path,
                      scale = (k, k, k), mass = kg, color,
                      position = vadd(at, (0f0, 1f0 + h, 0f0)))
end

"""The model files the Spawn tab offers: [(folder name, [paths…])], from
assets/ (its own files as "basic") and each folder under assets/models."""
function _model_library()
    is_model(f) = lowercase(splitext(f)[2]) in (".obj", ".stl")
    out = Tuple{String,Vector{String}}[]
    base = isdir(_ASSETS) ? sort([joinpath(_ASSETS, f) for f in readdir(_ASSETS) if is_model(f)]) : String[]
    isempty(base) || push!(out, ("basic", base))
    md = joinpath(_ASSETS, "models")
    if isdir(md)
        for d in sort(readdir(md))
            dir = joinpath(md, d)
            isdir(dir) || continue
            fs = String[]
            for (root, _, files) in walkdir(dir), f in files
                is_model(f) && push!(fs, joinpath(root, f))
            end
            isempty(fs) || push!(out, (d, sort(fs)))
        end
    end
    return out
end

_gl_string(e) = try
    p = ccall((:glGetString, "libGL.so.1"), Ptr{UInt8}, (UInt32,), e)
    p == C_NULL ? "" : unsafe_string(p)
catch
    ""
end

"""The scene files the Scenes tab offers: (physics, orbits), as paths."""
function _scene_files()
    list(d) = isdir(d) ? sort([joinpath(d, f) for f in readdir(d) if endswith(f, ".toml")]) : String[]
    return list(_SCENES), list(joinpath(_SCENES, "orbits"))
end

"""
    run_window(scene; width = 1280, height = 720, frames = 0, screenshot = "", presim = 0,
               paused = false, fps = 0, shadows = true, bloom = true, menu = false, tab = 1)
        -> next scene path or nothing

Open a window and run the scene in it, interactively. `scene` is a path or a
SceneSpec. Returns the scene picked in the menu's Scenes tab (the window
closes first), or `nothing` when the window was closed or Quit was chosen;
[`app`](@ref) uses that to move between scenes.

- `frames > 0`: run exactly that many frames, then close. Physics then advances
  `hz ÷ 60` steps per frame regardless of wall time, so the result is the same
  on every run; otherwise it follows real time.
- `screenshot`: save the last frame as a PNG at this path.
- `presim`: simulate this many seconds before the first frame.
- `fps`: frame-rate cap; 0 = the monitor's refresh rate.
- `shadows`, `bloom`: start with them on or off.
- `menu`, `tab`: start with the menu open on that tab (1 World … 6 Help).
- `select`: start with the body of this name selected.
- `record`: write an MP4 to this path through ffmpeg. The scene renders at 2×
  and is downsampled; the physics advances 1/`fps` s per frame (60 when `fps`
  is 0), so the video runs at real speed however slow the rendering. The mouse
  and keys still work, the menu is off, and ESC (or closing the window) ends
  the recording.

ESC opens the menu: World (gravity, time, solver, mutual gravity), View
(lighting, shadows, bloom, sky, overlays), Object (the selected body's mass,
material, gravity, look), Spawn, Scenes and Help (every control). Click an
object to select it; drag it to carry it.
"""
function run_window(scene; width::Integer = 1280, height::Integer = 720, frames::Integer = 0,
                    screenshot::AbstractString = "", presim::Real = 0, paused::Bool = false,
                    fps::Integer = 0, shadows::Bool = true, bloom::Bool = true,
                    menu::Bool = false, tab::Integer = 1, select::AbstractString = "",
                    backend = nothing, record::AbstractString = "")
    spec = scene isa SceneSpec ? scene : load_scene(scene)
    haskey(ENV, "DISPLAY") || haskey(ENV, "WAYLAND_DISPLAY") ||
        error("ObjectSim.run_window needs a display (DISPLAY is not set); use run_headless instead")
    recording = !isempty(record)
    recording && Sys.which("ffmpeg") === nothing && error("ObjectSim: record needs ffmpeg on PATH")
    rfps = fps > 0 ? fps : 60                                      # the recording's frame rate
    rec = nothing                                                  # ffmpeg's stdin, opened on the first frame
    ss = recording ? 2 : 1                                         # a recording renders at 2x and is downsampled
    W, H = Cint(width * ss), Cint(height * ss)
    nrec = 0
    R.SetTraceLogLevel(Cint(4))                                    # LOG_WARNING
    R.SetConfigFlags(Cuint(0x20 | 0x04 | 0x40))                     # MSAA 4x | resizable | vsync
    R.InitWindow(Cint(width), Cint(height), "ObjectSim — $(spec.name)$(recording ? "  ● recording" : "")")
    R.IsWindowReady() || error("ObjectSim: raylib could not open a window")
    recording || R.SetExitKey(Cint(0))                             # ESC opens the menu instead (recording: ends it)
    rt = recording ? R.LoadRenderTexture(W, H) : nothing
    if frames == 0 && !recording
        hz = fps > 0 ? fps : R.GetMonitorRefreshRate(R.GetCurrentMonitor())
        R.SetTargetFPS(Cint(hz > 0 ? hz : 60))
    end
    gpu = _gl_string(0x1F01)                                        # GL_RENDERER

    rr = _renderer(; shadows, bloom)
    v = _View(paused)
    v.menu = menu; v.tab = tab
    sky = spec.camera.sky
    _setv(rr, "fogColor", Float32.(sky) ./ 255)
    _setf(rr, "sunStrength", spec.camera.sun)
    _setf(rr, "ambient", spec.camera.ambient)
    sun_strength, ambient = spec.camera.sun, spec.camera.ambient
    ui = _ui()

    meshes = Dict{Any,R.Mesh}()
    w = World(spec; backend)
    v.engine = ObjectSim.backend(w)
    shot_ok = false
    try
        presim > 0 && simulate!(w, presim)
        isempty(select) || (v.selected = body(w, select))
        if !isempty(spec.camera.follow)
            v.selected = body(w, spec.camera.follow); v.follow = true
        end
        orbit = _orbit(w)
        _setf(rr, "fogFar", orbit.distance * 4)
        frame = 0
        t_measure = 0.0; n_measure = 0        # frame rate after the first second (compilation)
        t_open = time()
        while !R.WindowShouldClose() && !v.quit
            frame += 1
            if time() - t_open > 1.0
                t_measure == 0.0 && (t_measure = time())
                n_measure += 1
            end
            per_frame = max(1, round(Int, 1 / (60 * w.dt)))
            dt_wall = recording ? 1 / rfps : Float64(R.GetFrameTime())
            cam = _camera(orbit)
            from, dir = _mouse_ray(cam)
            key(k) = R.IsKeyPressed(Cint(k))
            _ui_input!(ui)
            on_menu = v.menu && _ui_wants_mouse(ui)

            # ── mouse: select and carry, orbit, pan, zoom ────────────────
            if !on_menu
                if R.IsMouseButtonPressed(Cint(_M.left))
                    v.press_at = (ui.mx, ui.my)
                    p = grab!(w, from, dir)
                    if p === nothing
                        v.orbiting = true
                    else
                        v.selected = p.body; orbit.auto = false
                    end
                end
                wheel = ui.wheel
                if w.pick !== nothing
                    drag!(w, from, dir; distance = w.pick.distance * (1f0 + 0.1f0 * wheel))
                else
                    orbit.distance = max(1f0, orbit.distance * (1f0 - 0.1f0 * wheel))
                end
                if R.IsMouseButtonDown(Cint(_M.middle))
                    d = R.GetMouseDelta()
                    y = deg2rad(orbit.yaw)
                    right = (cos(y), 0.0, -sin(y)); fwd = (-sin(y), 0.0, -cos(y))
                    k = 0.0015f0 * orbit.distance
                    orbit.target = vadd(orbit.target, Float32.(vadd(vscale(right, -d.x * k), vscale(fwd, d.y * k))))
                    orbit.auto = false
                end
            end
            if R.IsMouseButtonReleased(Cint(_M.left))
                # A click (no drag) on empty space clears the selection.
                if v.orbiting && hypot(ui.mx - v.press_at[1], ui.my - v.press_at[2]) < 4
                    v.selected = nothing
                end
                release!(w); v.orbiting = false
            end
            if v.orbiting || (!on_menu && R.IsMouseButtonDown(Cint(_M.right)))
                d = R.GetMouseDelta()
                orbit.yaw -= 0.3f0 * d.x
                orbit.pitch = clamp(orbit.pitch + 0.3f0 * d.y, -5f0, 85f0)
                orbit.auto = false
            end
            v.hover = w.pick !== nothing ? w.pick.body : on_menu ? nothing :
                (h = raycast(w, from, vadd(from, vscale(dir, 500f0))); h === nothing ? nothing : h.body)
            v.selected !== nothing && !isalive(v.selected) && (v.selected = nothing)   # removed

            # ── keys (shortcuts; everything is also in the menu) ─────────
            recording || (key(_K.escape) && (v.menu = !v.menu))
            recording || (key(_K.h) && (v.menu = true; v.tab = 6))
            key(_K.space) && (v.paused = !v.paused)
            key(_K.o) && (orbit.auto = !orbit.auto)
            key(_K.z) && (v.sleep_tint = !v.sleep_tint)
            key(_K.j) && (v.show_joints = !v.show_joints)
            key(_K.c) && (v.show_contacts = !v.show_contacts)
            key(_K.b) && (rr.bloom = !rr.bloom; _say!(v, rr.bloom ? "bloom on" : "bloom off"))
            key(_K.l) && (rr.shadows = !rr.shadows; _say!(v, rr.shadows ? "shadows on" : "shadows off"))
            key(_K.t) && (v.timescale = v.timescale == 1 ? 0.25 : 1.0; _say!(v, "speed ×$(v.timescale)"))
            if key(_K.g)
                g = vnorm(w.gravity) > 0 ? (0f0, 0f0, 0f0) : spec.world.gravity
                set_gravity!(w, g); _say!(v, vnorm(g) > 0 ? "gravity on" : "gravity off")
            end
            if key(_K.r) || v.restart
                release!(w); destroy!(w); w = World(spec; backend = v.engine); v.hover = nothing; v.selected = nothing
                v.restart = false
                _say!(v, "restarted")
            end
            if key(_K.f)
                eye = (cam.position.x, cam.position.y, cam.position.z)
                b = spawn!(w, ObjectSpec(; name = "shot", shape = :sphere, radius = 0.22f0, mass = 3f0,
                                         position = vadd(eye, vscale(dir, 1.5f0)),
                                         color = (0xf2, 0xf2, 0xf2), restitution = 0.2f0))
                set_velocity!(b, vscale(dir, 28f0))
            end
            for k in 1:7
                if key(_K.one + k - 1)
                    v.spawn_kind = k
                    b = spawn!(w, _spawn_spec(k, _aim(w, from, dir), _next_color!(v); size = v.spawn_size,
                                              mass = v.spawn_mass == 1 ? nothing : v.spawn_mass,
                                              glow = v.spawn_glow, light = v.spawn_light))
                    _say!(v, "added $(b.name)")
                end
            end
            key(_K.e) && (n = explode!(w, _aim(w, from, dir)); _say!(v, "blast hit $n bodies"))
            if (key(_K.x) || key(_K.delete)) && v.hover !== nothing && !isstatic(v.hover)
                name = v.hover.name; v.hover === v.selected && (v.selected = nothing)
                remove!(w, v.hover); v.hover = nothing
                _say!(v, "removed $name")
            end
            if R.IsFileDropped()
                files = R.LoadDroppedFiles()
                for i in 1:files.count
                    path = unsafe_string(unsafe_load(files.paths, i))
                    ext = lowercase(splitext(path)[2])
                    if ext in (".obj", ".stl")
                        try
                            b = spawn!(w, _dropped_spec(path, _aim(w, from, dir), _next_color!(v);
                                                        size = v.spawn_size,
                                                        mass = v.spawn_mass == 1 ? nothing : v.spawn_mass))
                            v.selected = b
                            _say!(v, "added $(basename(path)) as $(b.name)")
                        catch e
                            _say!(v, "could not load $(basename(path)): $(sprint(showerror, e))")
                        end
                    else
                        _say!(v, "$(basename(path)): only .obj and .stl can be dropped in")
                    end
                end
                R.UnloadDroppedFiles(files)
            end
            orbit.auto && (orbit.yaw += (frames > 0 ? 1 / 60 : dt_wall) * 6)
            if v.follow && v.selected !== nothing
                k = Float32(1 - exp(-6 * (frames > 0 ? 1 / 60 : dt_wall)))   # eases in over ~0.2 s
                orbit.target = vadd(orbit.target, vscale(vsub(position(v.selected), orbit.target), k))
            end

            # ── physics ──────────────────────────────────────────────────
            if !v.paused
                if frames > 0 && !recording
                    step!(w, per_frame)
                else
                    advance!(w, dt_wall * v.timescale)
                end
            elseif key(_K.n)
                step!(w, per_frame)
            end

            # ── draw ─────────────────────────────────────────────────────
            cam = _camera(orbit)
            light = _sun_dir(v)
            _setv(rr, "lightDir", light)
            batches = Dict{Any,_Batch}()
            lights = _Light[]
            for b in w.bodies
                key_ = _mesh_key(b.spec)
                mesh = get!(() -> _upload(b.mesh), meshes, key_)
                c = b.spec.color
                asleep = !isstatic(b) && sleeping(b)
                v.sleep_tint && asleep && (c = (0x50, 0x5a, 0x78))
                if (b === v.hover || b === v.selected) && !isstatic(b)
                    c = UInt8.(min.(255, round.(Int, c .* 1.25 .+ (b === v.selected ? 45 : 25))))
                end
                rows, o = render_transform(b)
                _batch!(batches, mesh, key_, c, istrigger(b) ? 0x55 : 0xff, b.spec.glow, _matrix(rows, o))
                b.spec.light > 0 && push!(lights, _Light(o, Float32.(b.spec.color) ./ 255f0 .* b.spec.light_intensity,
                                                         b.spec.light))
            end
            _set_lights!(rr, lights; near = orbit.target)
            _shadow_pass!(rr, batches, orbit.target, clamp(orbit.distance * 1.4f0, 8f0, 140f0), light)
            _setv(rr, "viewPos", (cam.position.x, cam.position.y, cam.position.z))
            recording ? R.BeginTextureMode(rt) : R.BeginDrawing()
            R.ClearBackground(_rl_color(sky))
            R.BeginMode3D(cam)
            recording && (R.rlDrawRenderBatchActive(); R.rlSetLineWidth(Float32(ss)))
            R.rlDisableBackfaceCulling()
            _bind_shadow!(rr)
            _draw_batches(rr, batches)
            wt = water(w)
            if wt !== nothing                               # after the solids: see-through
                R.DrawPlane(_rl_v3((orbit.target[1], wt.level, orbit.target[3])), R.Vector2(600f0, 600f0),
                            _rl_color(wt.color, round(UInt8, 255 * clamp(wt.clarity, 0, 1))))
            end
            R.rlEnableBackfaceCulling()
            v.show_joints && _draw_joints(w)
            ncontacts = 0
            if v.show_contacts
                for ct in contacts(w)
                    ncontacts += 1
                    r = 0.03f0 + 0.05f0 * min(1f0, abs(ct.impulse) / max(0.05f0, mass(ct.a) * 0.1f0))
                    R.DrawSphere(_rl_v3(ct.point), r, istrigger(ct.a) || istrigger(ct.b) ?
                                 R.Color(0x40, 0xd0, 0xff, 0xff) : R.Color(0xff, 0x40, 0x40, 0xff))
                end
            end
            if w.pick !== nothing
                R.DrawLine3D(_rl_v3(_held_point(w)), _rl_v3(w.pick.point), R.Color(0xff, 0xd0, 0x40, 0xff))
                R.DrawSphere(_rl_v3(w.pick.point), 0.06f0, R.Color(0xff, 0xd0, 0x40, 0xff))
            end
            R.EndMode3D()
            recording && (R.rlDrawRenderBatchActive(); R.rlSetLineWidth(1f0))
            _bloom_pass!(rr; target = rt)

            # ── recording: send the frame to ffmpeg, show it in the window ─
            if recording
                R.EndTextureMode()
                img = R.LoadImageFromTexture(rt.texture)   # RGBA8, bottom row first
                try
                    iw, ih = Int(img.width), Int(img.height)
                    if rec === nothing
                        mkpath(dirname(abspath(record)))
                        rec = open(`ffmpeg -y -loglevel error -f rawvideo -pix_fmt rgba -s $(iw)x$(ih)
                                    -r $rfps -i - -vf vflip,scale=$(width ÷ 2 * 2):$(height ÷ 2 * 2):flags=lanczos
                                    -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart
                                    $record`, "w")
                    end
                    write(rec, unsafe_wrap(Array, Ptr{UInt8}(img.data), iw * ih * 4)); nrec += 1
                finally
                    R.UnloadImage(img)
                end
                R.BeginDrawing()
                R.ClearBackground(R.Color(0x00, 0x00, 0x00, 0xff))
                vw, vh = R.GetScreenWidth(), R.GetScreenHeight()
                k = min(vw / W, vh / H)
                R.DrawTexturePro(rt.texture, R.Rectangle(0, 0, W, -H),
                                 R.Rectangle((vw - k * W) / 2, (vh - k * H) / 2, k * W, k * H),
                                 R.Vector2(0, 0), 0, R.Color(0xff, 0xff, 0xff, 0xff))
                # on the window only, not in the video
                _text("● REC  $(round(nrec / rfps; digits = 1)) s    ESC  stop", 14, 12, 18,
                      R.Color(0xff, 0x50, 0x50, 0xe0))
                _toast(v.message, v.message_until, vw, vh)
            end

            # ── 2D: menu, or just the hint ───────────────────────────────
            sw, sh = R.GetScreenWidth(), R.GetScreenHeight()
            !recording && v.show_stats && _stats_overlay(w, v, ncontacts, gpu)
            if recording
            elseif v.menu
                ctx = (; w, spec, rr, orbit, gpu, ncontacts)
                sky, sun_strength, ambient = _physics_menu!(ui, v, ctx, sky, sun_strength, ambient, sw, sh)
            else
                _hint(sw, sh, v.paused ? "PAUSED" : v.selected !== nothing ? "selected: $(v.selected.name)" : "")
            end
            recording || _toast(v.message, v.message_until, sw, sh)

            if frames > 0 && frame >= frames
                if !isempty(screenshot)
                    # 2D draws (text) sit in rlgl's batch until EndDrawing
                    # flushes it; flush first or the capture misses them.
                    R.rlDrawRenderBatchActive()
                    img = R.LoadImageFromScreen()
                    shot_ok = R.ExportImage(img, screenshot)
                    R.UnloadImage(img)
                end
                R.EndDrawing()
                break
            end
            R.EndDrawing()
            v.next === nothing || break
        end
        n_measure > 30 && @info "ObjectSim: $(round(n_measure / (time() - t_measure); digits = 1)) frames/s " *
                                 "on average after the first second ($n_measure frames, $gpu)"
    finally
        if rec !== nothing
            close(rec); wait(rec)                    # ffmpeg finishes the file on EOF
            success(rec) ? @info("ObjectSim: recorded $nrec frames ($(round(nrec / rfps; digits = 1)) s) to $record") :
                           @warn("ObjectSim: ffmpeg failed; the recording may be incomplete", record)
        end
        rt === nothing || R.UnloadRenderTexture(rt)
        destroy!(w)
        foreach(R.UnloadMesh, values(meshes))
        _free!(rr)
        R.CloseWindow()
    end
    isempty(screenshot) || shot_ok || @warn "ObjectSim: screenshot was not written" screenshot
    return v.next
end

# ── the menu ─────────────────────────────────────────────────────────────────

# The menu's panel: down the right-hand side.
_menu_rect(sw, sh) = (max(12, sw - 392), 12, min(380, sw - 24), sh - 24)

function _physics_menu!(ui::_UI, v::_View, ctx, sky, sun_strength, ambient, sw, sh)
    w, spec, rr, orbit = ctx.w, ctx.spec, ctx.rr, ctx.orbit
    x, y, pw, ph = _menu_rect(sw, sh)
    _panel_begin!(ui, x, y, pw, ph; page = v.tab)
    v.tab = _tabs!(ui, _MENU_TABS[1:3], v.tab <= 3 ? v.tab : 0) |> t -> t == 0 ? v.tab : t
    v.tab = _tabs!(ui, _MENU_TABS[4:6], v.tab >= 4 ? v.tab - 3 : 0) |> t -> t == 0 ? v.tab : t + 3
    tab = _MENU_TABS[v.tab]

    if tab == "World"
        _heading!(ui, "Physics engine")
        cur = something(findfirst(==(v.engine), BACKENDS), 1)
        new = _choice!(ui, collect(BACKENDS), cur)
        if new != cur                                   # the same scene again, on the other engine
            v.engine = BACKENDS[new]; DEFAULT_BACKEND[] = v.engine
            v.restart = true; _say!(v, "restarting on $(v.engine)")
        end
        _heading!(ui, "Gravity")
        g = w.gravity
        _row!(ui, length(_GRAVITY_PRESETS))
        for (name, gy) in _GRAVITY_PRESETS
            if _button!(ui, name; on = g == (0f0, gy, 0f0))
                set_gravity!(w, (0f0, gy, 0f0)); _say!(v, "gravity: $name")
            end
        end
        gx = _slider!(ui, :gx, "sideways (x)", g[1], -15, 15)
        gy = _slider!(ui, :gy, "down / up (y)", g[2], -30, 10)
        gz = _slider!(ui, :gz, "sideways (z)", g[3], -15, 15)
        (gx, gy, gz) != g && set_gravity!(w, Float32.((gx, gy, gz)))
        _heading!(ui, "Time")
        v.timescale = _slider!(ui, :speed, "speed (× real time)", v.timescale, 0.05, 2.0)
        _row!(ui, 3)
        _button!(ui, v.paused ? "Run" : "Pause"; on = v.paused) && (v.paused = !v.paused)
        _button!(ui, "Step") && step!(w, max(1, round(Int, 1 / (60 * w.dt))))
        _button!(ui, "×1") && (v.timescale = 1.0)
        _label!(ui, "physics steps per second")
        hzs = (60, 120, 240, 480)
        cur = something(findfirst(==(round(Int, 1 / w.dt)), hzs), 2)
        new = _choice!(ui, string.(hzs), cur)
        new != cur && (w.dt = 1f0 / hzs[new])
        _heading!(ui, "Solver")
        it = solver_iterations(w)
        it2 = round(Int, _slider!(ui, :iters, "passes per step (stiffer joints, stacks)", it, 1, 100))
        it2 != it && set_solver_iterations!(w, it2)
        _heading!(ui, "Mutual gravity")
        on = _toggle!(ui, "every object attracts every other", w.mutual_G > 0)
        if on != (w.mutual_G > 0)
            set_mutual_gravity!(w, on ? max(spec.world.mutual_gravity, 0.05) : 0.0)
        end
        if w.mutual_G > 0
            G = _slider!(ui, :G, "G (strength)", w.mutual_G, 0.001, 10; log = true)
            G != w.mutual_G && set_mutual_gravity!(w, G)
        end
        nm = motor_count(w)
        if nm > 0
            _heading!(ui, "Motors ($nm)")
            f = _slider!(ui, :motors, "speed (× the scene's; minus = reverse)", v.motors, -3, 3)
            _row!(ui, 3)
            _button!(ui, "Reverse"; on = v.motors < 0) && (f = -abs(v.motors == 0 ? 1f0 : v.motors))
            _button!(ui, "Stop"; on = v.motors == 0) && (f = 0f0)
            _button!(ui, "Forward"; on = v.motors > 0) && (f = abs(v.motors == 0 ? 1f0 : v.motors))
            if f != v.motors
                v.motors = Float32(f); set_motors!(w, v.motors)
            end
        end
        _heading!(ui, "Water")
        wt = water(w)
        on = _toggle!(ui, "fill the world with water", wt !== nothing)
        if on != (wt !== nothing)
            set_water!(w, on ? something(spec.world.water, WaterSpec(; level = 1f0)) : nothing)
            _say!(v, on ? "water on" : "water drained"); wt = water(w)
        end
        if wt !== nothing
            nw = wt
            _row!(ui, length(_LIQUIDS))
            for (name, ρ, c) in _LIQUIDS
                _button!(ui, name; on = wt.density == ρ) && (nw = WaterSpec(; level = wt.level, density = ρ, drag = c,
                                                                            color = wt.color, clarity = wt.clarity))
            end
            lv = _slider!(ui, :wl, "surface height (m)", wt.level, -5, 15)
            ρ = _slider!(ui, :wd, "density (kg/m³; denser things sink)", wt.density, 100, 15000; log = true)
            c = _slider!(ui, :wc, "thickness (drag)", wt.drag, 0, 50; log = false)
            (lv, ρ, c) != (wt.level, wt.density, wt.drag) &&
                (nw = WaterSpec(; level = Float32(lv), density = Float32(ρ), drag = Float32(c),
                                color = nw.color, clarity = nw.clarity))
            nw !== wt && set_water!(w, nw)
        end
        _heading!(ui, "Everything")
        _row!(ui, 2)
        _button!(ui, "Wake all") && foreach(b -> isstatic(b) || wake!(b), w.bodies)
        if _button!(ui, "Clear spawned")
            for b in filter(b -> occursin('#', b.name), w.bodies)
                b === v.selected && (v.selected = nothing); remove!(w, b)
            end
        end

    elseif tab == "View"
        _heading!(ui, "Light")
        sun_strength = _slider!(ui, :sun, "sun strength", sun_strength, 0, 2)
        ambient = _slider!(ui, :amb, "sky light", ambient, 0, 2)
        v.sun_yaw = _slider!(ui, :yaw, "sun direction (°)", v.sun_yaw, -180, 180)
        v.sun_height = _slider!(ui, :height, "sun height (°)", v.sun_height, 5, 90)
        _setf(rr, "sunStrength", sun_strength); _setf(rr, "ambient", ambient)
        _label!(ui, "sky")
        c = _swatches!(ui, _SKIES, sky)
        if c !== nothing
            sky = c; _setv(rr, "fogColor", Float32.(sky) ./ 255)
        end
        _heading!(ui, "Effects")
        rr.shadows = _toggle!(ui, "shadows", rr.shadows)
        rr.bloom = _toggle!(ui, "bloom", rr.bloom)
        if rr.bloom
            rr.bloom_strength = _slider!(ui, :bs, "bloom strength", rr.bloom_strength, 0, 1)
            rr.bloom_threshold = _slider!(ui, :bt, "bloom from brightness", rr.bloom_threshold, 0.3, 0.98)
        end
        _heading!(ui, "Show")
        v.show_joints = _toggle!(ui, "joints", v.show_joints)
        v.show_contacts = _toggle!(ui, "contact points", v.show_contacts)
        v.sleep_tint = _toggle!(ui, "sleeping bodies (tinted)", v.sleep_tint)
        v.show_stats = _toggle!(ui, "stats on screen", v.show_stats)
        orbit.auto = _toggle!(ui, "camera turns by itself", orbit.auto)
        v.follow = _toggle!(ui, "camera follows the selected object", v.follow)

    elseif tab == "Object"
        b = v.selected
        if b === nothing
            _label!(ui, "Click an object in the scene to select it.\nDrag it to carry it; its settings\nappear here.")
        else
            _heading!(ui, b.name)
            p = position(b)
            _label!(ui, "$(b.spec.shape)$(isstatic(b) ? ", static" : "")$(sleeping(b) ? ", asleep" : "")\n" *
                        "at ($(round(p[1]; digits = 2)), $(round(p[2]; digits = 2)), $(round(p[3]; digits = 2)))  " *
                        "speed $(round(vnorm(velocity(b)); digits = 2)) m/s")
            if !isstatic(b)
                vol = body_volume(b); ρ = density(b); wt = water(w)
                _label!(ui, "volume $(_fmt(vol)) m³   density $(_fmt(ρ)) kg/m³" *
                            (wt === nothing ? "" : ρ > wt.density ? "\nsinks (water is $(_fmt(wt.density)))" :
                                                   "\nfloats, $(round(Int, 100ρ / wt.density))% under"))
                m = _slider!(ui, :mass, "mass (kg)", b.spec.mass, 0.01, 1e6; log = true)
                m != b.spec.mass && set_mass!(b, m)
            end
            f = _slider!(ui, :fr, "friction", b.spec.friction, 0, 1.5)
            f != b.spec.friction && set_friction!(b, f)
            e = _slider!(ui, :bo, "bounce", b.spec.restitution, 0, 1)
            e != b.spec.restitution && set_restitution!(b, e)
            rf = _slider!(ui, :rf, "rolling friction", b.spec.rolling_friction, 0, 0.3)
            rf != b.spec.rolling_friction && set_rolling_friction!(b, rf)
            if !isstatic(b)
                ld = _slider!(ui, :ld, "air drag", b.spec.damping[1], 0, 1)
                ad = _slider!(ui, :ad, "spin drag", b.spec.damping[2], 0, 1)
                (ld, ad) != b.spec.damping && set_damping!(b, ld, ad)
                own = _toggle!(ui, "its own gravity", b.spec.gravity !== nothing)
                if own != (b.spec.gravity !== nothing)
                    set_body_gravity!(w, b, own ? w.gravity : nothing)
                    b.spec = _with(b.spec; gravity = own ? w.gravity : nothing)
                end
                if b.spec.gravity !== nothing
                    gy = _slider!(ui, :bgy, "its gravity (y)", b.spec.gravity[2], -30, 10)
                    if gy != b.spec.gravity[2]
                        g = (b.spec.gravity[1], Float32(gy), b.spec.gravity[3])
                        set_body_gravity!(w, b, g); b.spec = _with(b.spec; gravity = g)
                    end
                end
            end
            _heading!(ui, "Look")
            c = _swatches!(ui, _SWATCHES, b.spec.color)
            c === nothing || set_look!(b; color = c)
            gl = _slider!(ui, :glow, "glow", b.spec.glow, 0, 1)
            gl != b.spec.glow && set_look!(b; glow = Float32(gl))
            lr = _slider!(ui, :light, "light reach (m, 0 = none)", b.spec.light, 0, 15)
            lr != b.spec.light && set_look!(b; light = Float32(lr))
            if b.spec.light > 0
                li = _slider!(ui, :li, "light brightness", b.spec.light_intensity, 0, 4)
                li != b.spec.light_intensity && set_look!(b; light_intensity = Float32(li))
            end
            if !isstatic(b)
                _heading!(ui, "Do")
                _row!(ui, 3)
                _button!(ui, "Stop") && set_velocity!(b, (0, 0, 0); spin = (0, 0, 0))
                _button!(ui, "Launch") && apply_impulse!(b, (0, 8 * mass(b), 0))
                if _button!(ui, "Delete")
                    _say!(v, "removed $(b.name)"); remove!(w, b); v.selected = nothing
                end
                if _button!(ui, "Duplicate")
                    c2 = spawn!(w, _with(b.spec; position = vadd(position(b), (0f0, 1.5f0, 0f0)),
                                         rotation = (0f0, 0f0, 0f0), velocity = (0f0, 0f0, 0f0)))
                    v.selected = c2
                end
            end
        end

    elseif tab == "Spawn"
        _heading!(ui, "What 1-7 and the button drop")
        _row!(ui, 4)
        for k in 1:4
            _button!(ui, _SPAWN_KINDS[k]; on = v.spawn_kind == k) && (v.spawn_kind = k)
        end
        _row!(ui, 3)
        for k in 5:7
            _button!(ui, _SPAWN_KINDS[k]; on = v.spawn_kind == k) && (v.spawn_kind = k)
        end
        v.spawn_size = _slider!(ui, :ss, "size (×)", v.spawn_size, 0.25, 4)
        v.spawn_mass = _slider!(ui, :sm, "mass (kg, 1 = the shape's own)", v.spawn_mass, 0.05, 500; log = true)
        if v.spawn_kind != 7
            v.spawn_glow = _slider!(ui, :sg, "glow", v.spawn_glow, 0, 1)
            v.spawn_light = _slider!(ui, :sl, "light reach (m)", v.spawn_light, 0, 15)
        end
        if _button!(ui, "Drop one in the middle")
            b = spawn!(w, _spawn_spec(v.spawn_kind, orbit.target, _next_color!(v); size = v.spawn_size,
                                      mass = v.spawn_mass == 1 ? nothing : v.spawn_mass,
                                      glow = v.spawn_glow, light = v.spawn_light))
            v.selected = b
        end
        _label!(ui, "Keys 1-7 drop where the mouse points.\nF throws a ball from the camera.")
        lib = _model_library()
        if !isempty(lib)
            _heading!(ui, "Models (click to drop one)")
            v.model_dir = clamp(v.model_dir, 1, length(lib))
            names = first.(lib)
            for r in 1:2:length(names)                     # folder choice, 2 per row
                _row!(ui, 2)
                for i in r:min(r + 1, length(names))
                    _button!(ui, names[i]; on = i == v.model_dir) && (v.model_dir = i)
                end
                _endrow!(ui)
            end
            files = lib[v.model_dir][2]
            stems = [splitext(basename(f))[1] for f in files]
            for (i, f) in enumerate(files)
                isodd(i) && _row!(ui, 2)
                label = replace(stems[i], '_' => ' ')
                count(==(stems[i]), stems) > 1 && (label *= " " * splitext(f)[2])   # ramp .obj / ramp .stl
                if _button!(ui, label)
                    try
                        b = spawn!(w, _dropped_spec(f, orbit.target, _next_color!(v); size = v.spawn_size,
                                                    mass = v.spawn_mass == 1 ? nothing : v.spawn_mass))
                        v.selected = b
                        _say!(v, "added $(b.name), $(_fmt(mass(b))) kg")
                    catch e
                        _say!(v, "could not load $(basename(f)): $(sprint(showerror, e))")
                    end
                end
            end
            _endrow!(ui)
            _label!(ui, "Models are scaled so the longest side is\n1.5 m × size, and weigh 500 kg/m³ unless\nmass is set. Or drop any .obj / .stl file\nonto the window. Files live in assets/models.")
        end

    elseif tab == "Scenes"
        phys, orbs = _scene_files()
        _heading!(ui, "Physics")
        _row!(ui, 2)
        for (i, f) in enumerate(phys)
            i > 1 && isodd(i) && _row!(ui, 2)
            name = splitext(basename(f))[1]
            _button!(ui, name; on = name == spec.name) && (v.next = f)
        end
        _endrow!(ui)
        _heading!(ui, "Orbits")
        _row!(ui, 2)
        for (i, f) in enumerate(orbs)
            i > 1 && isodd(i) && _row!(ui, 2)
            _button!(ui, splitext(basename(f))[1]) && (v.next = f)
        end
        _endrow!(ui)
        _heading!(ui, "This scene")
        _row!(ui, 2)
        _button!(ui, "Restart") && (v.restart = true)
        _button!(ui, "Quit") && (v.quit = true)

    else  # Help
        _heading!(ui, "Mouse")
        _label!(ui, "drag an object: carry it (and select it)\n" *
                    "    wheel while carrying: closer / further\n" *
                    "drag empty space: turn the camera\n" *
                    "right-drag: turn      middle-drag: pan\n" *
                    "wheel: zoom      click empty space: deselect")
        _heading!(ui, "Keys")
        _label!(ui, "ESC  menu          H  this page\n" *
                    "F  throw a ball\n" *
                    "1-7  drop box, ball, capsule, drum,\n" *
                    "        cone, rock, lamp at the mouse\n" *
                    "E  blast          X  delete (under the mouse)\n" *
                    "G  gravity on/off      T  slow motion\n" *
                    "SPACE  pause     N  step     R  restart\n" *
                    "O  camera turns     Z  sleeping\n" *
                    "J  joints     C  contacts\n" *
                    "L  shadows     B  bloom")
        _heading!(ui, "Now")
        moving = count(!isstatic, w.bodies)
        _label!(ui, "$(w.scene.name)   t = $(round(sim_time(w); digits = 2)) s   $(round(Int, 1 / w.dt)) Hz\n" *
                    "$moving moving, $(count(b -> !isstatic(b) && !sleeping(b), w.bodies)) awake, " *
                    "$(length(w.bodies) - moving) static, $(count(!broken, w.joints)) joints\n" *
                    "$(R.GetFPS()) fps   $(ctx.gpu)")
    end
    _panel_end!(ui)
    return sky, sun_strength, ambient
end

function _stats_overlay(w::World, v::_View, ncontacts, gpu)
    dim = R.Color(0x9a, 0x9e, 0xa8, 0xff)
    moving = count(!isstatic, w.bodies)
    _text("$(w.scene.name) on $(backend(w))   t = $(round(sim_time(w); digits = 2)) s   $(R.GetFPS()) fps", 14, 12, 18, _UI_TEXT)
    _text("$moving moving, $(count(b -> !isstatic(b) && !sleeping(b), w.bodies)) awake, " *
          "$(length(w.bodies) - moving) static, $(count(!broken, w.joints)) joints" *
          (v.show_contacts ? ", $ncontacts contacts" : ""), 14, 36, 16, dim)
end

# The point on the held body that the mouse is pulling (pivot A in world).
function _held_point(w::World)
    p = w.pick
    return _render_to_world(p.body, p.local_point)
end

function _draw_joints(w::World)
    rod = R.Color(0xd8, 0xdc, 0xe6, 0xff); dot = R.Color(0xff, 0xff, 0xff, 0xff)
    for j in w.joints
        broken(j) && continue
        pa, pb = joint_points(j)
        ca = render_transform(j.a)[2]
        R.DrawLine3D(_rl_v3(ca), _rl_v3(pa), rod)
        if j.b === nothing
            R.DrawSphere(_rl_v3(pb), 0.07f0, R.Color(0x9a, 0x9e, 0xa8, 0xff))   # world anchor
        else
            R.DrawLine3D(_rl_v3(render_transform(j.b)[2]), _rl_v3(pb), rod)
        end
        if j.kind == :spring
            R.DrawLine3D(_rl_v3(pa), _rl_v3(pb), R.Color(0x7c, 0xd9, 0x8b, 0xff))
        end
        R.DrawSphere(_rl_v3(pa), 0.045f0, dot)
    end
end
