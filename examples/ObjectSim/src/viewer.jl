# The raylib side: a window that draws a World while it runs.
#
# raylib never owns the simulation. Each frame the viewer steps the World a
# fixed number of physics steps, reads every body's transform out of bullet3,
# and draws the body's TriMesh with it. The meshes are the same TriMesh the
# collision shapes were built from, uploaded once.
#
# Matrix layout: raylib's Matrix struct is declared m0, m4, m8, m12, m1, …,
# i.e. its fields in declaration order are the matrix ROW by row (m12, m13,
# m14 is the translation). bullet3's btMatrix3x3 stores rows too, so a body
# transform maps field for field with no transpose. Do not memcpy bullet3's
# getOpenGLMatrix output into a raylib Matrix: that one is column-major.

const _VS = """
#version 330
in vec3 vertexPosition;
in vec3 vertexNormal;
uniform mat4 mvp;
uniform mat4 matModel;
uniform mat4 matNormal;
out vec3 fragPosition;
out vec3 fragNormal;
void main() {
    fragPosition = vec3(matModel * vec4(vertexPosition, 1.0));
    fragNormal = normalize(vec3(matNormal * vec4(vertexNormal, 0.0)));
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
"""

const _FS = """
#version 330
in vec3 fragPosition;
in vec3 fragNormal;
uniform vec4 colDiffuse;
uniform vec3 lightDir;
uniform vec3 viewPos;
uniform vec3 fogColor;
uniform float fogFar;
out vec4 finalColor;
void main() {
    // Two-sided: asset files often mix windings, so back faces are drawn
    // (culling is off) and lit from their own side.
    vec3 n = normalize(gl_FrontFacing ? fragNormal : -fragNormal);
    vec3 l = normalize(-lightDir);
    vec3 v = normalize(viewPos - fragPosition);
    float diff = max(dot(n, l), 0.0);
    float hemi = 0.5 + 0.5 * n.y;
    float spec = pow(max(dot(n, normalize(l + v)), 0.0), 40.0) * 0.18;
    vec3 c = colDiffuse.rgb * (0.22 + 0.23 * hemi + 0.62 * diff) + vec3(spec);
    float fog = smoothstep(fogFar * 0.45, fogFar, length(viewPos - fragPosition));
    finalColor = vec4(mix(c, fogColor, fog), 1.0);
}
"""

const _BG = (0x1b, 0x1d, 0x23)

_rl_color(c, a = 0xff) = R.Color(UInt8(c[1]), UInt8(c[2]), UInt8(c[3]), UInt8(a))
_rl_v3(v) = R.Vector3(Float32(v[1]), Float32(v[2]), Float32(v[3]))

# Rebuild an immutable wrapper struct with some fields replaced.
_with(x::T; kw...) where {T} = T((get(kw, f, getfield(x, f)) for f in fieldnames(T))...)

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

"""
    run_window(scene; width = 1280, height = 720, frames = 0, screenshot = "", presim = 0,
         paused = false)

Open a window and run the scene in it. `scene` is a path or a SceneSpec.

- `frames > 0`: run exactly that many frames, then close. Physics then advances
  `hz ÷ 60` steps per frame regardless of wall time, so the result is the same
  on every run; otherwise it follows real time.
- `screenshot`: save the last frame as a PNG at this path.
- `presim`: simulate this many seconds before the first frame.

Keys: SPACE pause, R restart, O toggle auto-orbit, left-drag orbit, wheel zoom,
ESC quit.
"""
function run_window(scene; width::Integer = 1280, height::Integer = 720, frames::Integer = 0,
              screenshot::AbstractString = "", presim::Real = 0, paused::Bool = false)
    spec = scene isa SceneSpec ? scene : load_scene(scene)
    haskey(ENV, "DISPLAY") || haskey(ENV, "WAYLAND_DISPLAY") ||
        error("ObjectSim.run_window needs a display (DISPLAY is not set); use run_headless instead")
    R.SetTraceLogLevel(Cint(4))                                    # LOG_WARNING
    R.SetConfigFlags(Cuint(0x20 | 0x04 | 0x40))                     # MSAA 4x | resizable | vsync
    R.InitWindow(Cint(width), Cint(height), "ObjectSim — $(spec.name)")
    R.IsWindowReady() || error("ObjectSim: raylib could not open a window")
    frames > 0 || R.SetTargetFPS(Cint(60))

    shader = R.LoadShaderFromMemory(_VS, _FS)
    mat = _with(R.LoadMaterialDefault(); shader = shader)
    color_off = fieldoffset(R.MaterialMap, findfirst(==(:color), fieldnames(R.MaterialMap)))
    loc(name) = R.GetShaderLocation(shader, name)
    setv(name, v::Vector{Float32}, kind) = R.SetShaderValue(shader, loc(name), v, Cint(kind))
    setv("lightDir", Float32[-0.45, -1.0, -0.3], 2)                # SHADER_UNIFORM_VEC3
    setv("fogColor", Float32[_BG...] ./ 255, 2)
    view_loc = loc("viewPos")

    meshes = Dict{Any,R.Mesh}()
    w = World(spec)
    shot_ok = false
    try
        presim > 0 && simulate!(w, presim)
        orbit = _orbit(w)
        setv("fogFar", Float32[orbit.distance * 4], 0)            # SHADER_UNIFORM_FLOAT
        per_frame = max(1, round(Int, spec.world.hz / 60))
        acc = 0.0
        frame = 0
        while !R.WindowShouldClose()
            frame += 1
            dt_wall = Float64(R.GetFrameTime())

            # ── input ────────────────────────────────────────────────────
            R.IsKeyPressed(Cint(32)) && (paused = !paused)          # SPACE
            R.IsKeyPressed(Cint(79)) && (orbit.auto = !orbit.auto)  # O
            if R.IsKeyPressed(Cint(82))                             # R
                destroy!(w); w = World(spec); acc = 0.0
            end
            if R.IsMouseButtonDown(Cint(0))
                d = R.GetMouseDelta()
                orbit.yaw -= 0.3f0 * d.x
                orbit.pitch = clamp(orbit.pitch + 0.3f0 * d.y, -5f0, 85f0)
                orbit.auto = false
            end
            orbit.distance = max(1f0, orbit.distance * (1f0 - 0.1f0 * R.GetMouseWheelMove()))
            orbit.auto && (orbit.yaw += (frames > 0 ? 1 / 60 : dt_wall) * 6)

            # ── physics ──────────────────────────────────────────────────
            if !paused
                if frames > 0
                    step!(w, per_frame)
                else
                    acc = min(acc + dt_wall, 0.25)
                    n = floor(Int, acc / w.dt)
                    n > 0 && step!(w, n)
                    acc -= n * w.dt
                end
            end

            # ── draw ─────────────────────────────────────────────────────
            cam = _camera(orbit)
            setv("viewPos", Float32[cam.position.x, cam.position.y, cam.position.z], 2)
            R.BeginDrawing()
            R.ClearBackground(_rl_color(_BG))
            R.BeginMode3D(cam)
            R.rlDisableBackfaceCulling()
            awake = 0
            for b in w.bodies
                mesh = get!(() -> _upload(b.mesh), meshes, _mesh_key(b.spec))
                unsafe_store!(Ptr{R.Color}(mat.maps + color_off), _rl_color(b.spec.color))
                rows, o = transform(b)
                R.DrawMesh(mesh, mat, _matrix(rows, o))
                isstatic(b) || sleeping(b) || (awake += 1)
            end
            R.rlEnableBackfaceCulling()
            R.EndMode3D()
            _hud(w, awake, paused)
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
        end
    finally
        destroy!(w)
        foreach(R.UnloadMesh, values(meshes))
        R.UnloadMaterial(mat)          # frees the maps and unloads the shader
        R.CloseWindow()
    end
    isempty(screenshot) || shot_ok || @warn "ObjectSim: screenshot was not written" screenshot
    return nothing
end

function _hud(w::World, awake, paused)
    fg = R.Color(0xe8, 0xe8, 0xe8, 0xff); dim = R.Color(0x9a, 0x9e, 0xa8, 0xff)
    moving = count(!isstatic, w.bodies)
    R.DrawText("$(w.scene.name)   t = $(round(sim_time(w); digits = 2)) s", Cint(14), Cint(12), Cint(20), fg)
    R.DrawText("$moving moving bodies, $awake awake, $(length(w.bodies) - moving) static   " *
               "$(w.scene.world.hz) Hz", Cint(14), Cint(38), Cint(16), dim)
    R.DrawText(paused ? "PAUSED - SPACE to run" : "SPACE pause  R restart  O orbit  drag/wheel camera",
               Cint(14), R.GetScreenHeight() - Cint(28), Cint(16), dim)
    R.DrawFPS(R.GetScreenWidth() - Cint(90), Cint(12))
end
