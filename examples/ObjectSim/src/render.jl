# The renderer both windows share: instanced meshes, shadow mapping, bloom.
#
# Instancing. Every object is drawn with DrawMeshInstanced, and objects that
# share a mesh, colour and glow go out in one draw call (a wall of 40 crates
# is one call). The vertex shader takes each instance's transform as a mat4
# attribute; raylib passes `mvp` as view·projection only.
#
# Shadows. Each frame the scene is drawn once more from the light, with an
# orthographic camera centred on what the viewer looks at, into a depth-only
# framebuffer (4096²). The main shader projects every fragment into that map
# and compares depths over a 5×5 neighbourhood (PCF), so edges are soft.
#
# Bloom. The finished 3D frame (multisampled) is blitted into a texture, which
# resolves the MSAA; its bright parts are extracted at half resolution, blurred
# with a separable Gaussian, and added back over the frame. The HUD is drawn
# after, so text stays sharp. Objects with `glow` are drawn bright and unlit,
# which is what makes them bloom.
#
# Point lights. Up to MAX_LIGHTS objects with a `light` range shine their
# colour on everything within it, fading as (1 − d/range)² to nothing at the
# edge, with diffuse and specular. They cast no shadows (only the main light
# does): a shadow map per point light would be six depth renders each.

const _LIT_VS = """
#version 330
in vec3 vertexPosition;
in vec3 vertexNormal;
in mat4 instanceTransform;
uniform mat4 mvp;                       // view · projection (instanced: no model)
out vec3 fragPosition;
out vec3 fragNormal;
void main() {
    vec4 wp = instanceTransform * vec4(vertexPosition, 1.0);
    fragPosition = wp.xyz;
    fragNormal = normalize(mat3(instanceTransform) * vertexNormal);
    gl_Position = mvp * wp;
}
"""

const MAX_LIGHTS = 16

const _LIT_FS = """
#version 330
#define MAX_LIGHTS $MAX_LIGHTS
in vec3 fragPosition;
in vec3 fragNormal;
uniform vec4 colDiffuse;
uniform float sunStrength;              // scales the main light
uniform float ambient;                  // scales the ambient / sky term
uniform int numLights;
uniform vec3 lightPositions[MAX_LIGHTS];
uniform vec3 lightColors[MAX_LIGHTS];   // colour × intensity
uniform float lightRanges[MAX_LIGHTS];
uniform int lightMode;                  // 0: directional (lightDir), 1: point (lightPos)
uniform vec3 lightDir;
uniform vec3 lightPos;
uniform vec3 viewPos;
uniform vec3 fogColor;
uniform float fogFar;
uniform float glow;                     // 0 lit … 1 fully self-lit (and bloomed)
uniform int shadowsOn;
uniform sampler2D shadowMap;
uniform mat4 lightVP;
uniform float shadowTexel;
uniform float shadowBias;
out vec4 finalColor;

float shadowLit(vec3 n, vec3 l) {
    vec4 lp = lightVP * vec4(fragPosition, 1.0);
    vec3 p = lp.xyz / lp.w * 0.5 + 0.5;
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z > 1.0) return 1.0;
    float bias = shadowBias * (1.0 + 3.0 * (1.0 - max(dot(n, l), 0.0)));
    float lit = 0.0;
    for (int x = -2; x <= 2; x++)
        for (int y = -2; y <= 2; y++) {
            float d = texture(shadowMap, p.xy + vec2(x, y) * shadowTexel).r;
            lit += (p.z - bias > d) ? 0.0 : 1.0;
        }
    return lit / 25.0;
}

void main() {
    // Two-sided: asset files often mix windings, so back faces are drawn and
    // lit from their own side.
    vec3 n = normalize(gl_FrontFacing ? fragNormal : -fragNormal);
    vec3 l = lightMode == 1 ? normalize(lightPos - fragPosition) : normalize(-lightDir);
    vec3 v = normalize(viewPos - fragPosition);
    float diff = max(dot(n, l), 0.0);
    float hemi = 0.5 + 0.5 * n.y;
    float lit = (shadowsOn == 1 && diff > 0.0) ? shadowLit(n, l) : 1.0;
    float spec = pow(max(dot(n, normalize(l + v)), 0.0), 40.0) * 0.22;
    vec3 base = colDiffuse.rgb;
    vec3 c = base * (ambient * (0.20 + 0.20 * hemi) + sunStrength * 0.65 * diff * lit)
           + vec3(spec) * lit * sunStrength;
    for (int i = 0; i < numLights; i++) {
        vec3 L = lightPositions[i] - fragPosition;
        float d = length(L);
        if (d >= lightRanges[i] || d < 1e-4) continue;
        vec3 ld = L / d;
        float a = 1.0 - d / lightRanges[i];
        a *= a;
        float nd = max(dot(n, ld), 0.0);
        float ps = pow(max(dot(n, normalize(ld + v)), 0.0), 32.0) * 0.35;
        c += (base * nd + vec3(ps) * nd) * lightColors[i] * a;
    }
    c = mix(c, min(base * 1.35 + 0.15, vec3(1.0)), glow);
    float fog = glow > 0.5 ? 0.0 : smoothstep(fogFar * 0.45, fogFar, length(viewPos - fragPosition));
    finalColor = vec4(mix(c, fogColor, fog), colDiffuse.a);
}
"""

const _DEPTH_VS = """
#version 330
in vec3 vertexPosition;
in mat4 instanceTransform;
uniform mat4 mvp;
void main() { gl_Position = mvp * instanceTransform * vec4(vertexPosition, 1.0); }
"""

const _DEPTH_FS = """
#version 330
out vec4 finalColor;
void main() { finalColor = vec4(1.0); }
"""

# 2D passes use raylib's default vertex shader (fragTexCoord, texture0).
const _BRIGHT_FS = """
#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform float threshold;
out vec4 finalColor;
void main() {
    vec3 c = texture(texture0, fragTexCoord).rgb;
    float m = max(c.r, max(c.g, c.b));
    float k = clamp((m - threshold) / max(1.0 - threshold, 1e-3), 0.0, 1.0);
    finalColor = vec4(c * k * k, 1.0);
}
"""

const _BLUR_FS = """
#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform vec2 dir;                       // one texel, along x or y
out vec4 finalColor;
void main() {
    float w[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
    vec3 c = texture(texture0, fragTexCoord).rgb * w[0];
    for (int i = 1; i < 5; i++) {
        c += texture(texture0, fragTexCoord + dir * float(i) * 1.5).rgb * w[i];
        c += texture(texture0, fragTexCoord - dir * float(i) * 1.5).rgb * w[i];
    }
    finalColor = vec4(c, 1.0);
}
"""

const _GL_READ_FRAMEBUFFER = 0x8CA8      # rlgl.h RL_READ_FRAMEBUFFER (a #define, not in the wrapper)
const _GL_DRAW_FRAMEBUFFER = 0x8CA9
const _GL_COLOR_BUFFER_BIT = 0x4000
const _SHADOW_SLOT = 10                  # texture unit for the shadow map

mutable struct _Renderer
    shader::R.Shader
    mat::R.Material
    depth_mat::R.Material
    color_off::Int
    loc::Dict{String,Cint}
    shadow::R.RenderTexture
    shadow_size::Int
    shadows::Bool
    bloom::Bool
    bloom_strength::Float32
    bloom_threshold::Float32
    bright::R.Shader
    blur::R.Shader
    scene_rt::Union{Nothing,R.RenderTexture}
    rt_a::Union{Nothing,R.RenderTexture}
    rt_b::Union{Nothing,R.RenderTexture}
    size::Tuple{Int,Int}
end

# A shader whose model matrix is the `instanceTransform` vertex attribute.
function _instanced_shader(vs, fs)
    sh = R.LoadShaderFromMemory(vs, fs)
    unsafe_store!(sh.locs, R.GetShaderLocationAttrib(sh, "instanceTransform"), 9 + 1)   # SHADER_LOC_MATRIX_MODEL
    return sh
end

# A framebuffer with only a depth texture, for the shadow map.
function _depth_target(size::Int)
    id = R.rlLoadFramebuffer()
    R.rlEnableFramebuffer(id)
    tex = R.rlLoadTextureDepth(size, size, false)
    R.rlFramebufferAttach(id, tex, 100, 100, 0)          # RL_ATTACHMENT_DEPTH, RL_ATTACHMENT_TEXTURE2D
    R.rlFramebufferComplete(id) || error("ObjectSim: the shadow-map framebuffer is incomplete")
    R.rlDisableFramebuffer()
    # BeginTextureMode takes the viewport from `texture`'s size.
    return R.RenderTexture(id, R.Texture(Cuint(0), Cint(size), Cint(size), Cint(1), Cint(0)),
                           R.Texture(tex, Cint(size), Cint(size), Cint(1), Cint(19)))
end

function _renderer(; shadows::Bool = true, bloom::Bool = true, shadow_size::Int = 4096, fs = _LIT_FS,
                   bloom_strength = 0.9, bloom_threshold = 0.72)
    sh = _instanced_shader(_LIT_VS, fs)
    mat = _with(R.LoadMaterialDefault(); shader = sh)
    dmat = _with(R.LoadMaterialDefault(); shader = _instanced_shader(_DEPTH_VS, _DEPTH_FS))
    loc = Dict{String,Cint}()
    for n in ("lightMode", "lightDir", "lightPos", "viewPos", "fogColor", "fogFar", "glow", "shadowsOn",
              "shadowMap", "lightVP", "shadowTexel", "shadowBias", "sunStrength", "ambient",
              "numLights", "lightPositions", "lightColors", "lightRanges")
        loc[n] = R.GetShaderLocation(sh, n)
    end
    r = _Renderer(sh, mat, dmat,
        fieldoffset(R.MaterialMap, findfirst(==(:color), fieldnames(R.MaterialMap))),
        loc, _depth_target(shadow_size), shadow_size, shadows, bloom,
        Float32(bloom_strength), Float32(bloom_threshold),
        R.LoadShaderFromMemory(C_NULL, _BRIGHT_FS), R.LoadShaderFromMemory(C_NULL, _BLUR_FS),
        nothing, nothing, nothing, (0, 0))
    _setf(r, "shadowTexel", 1f0 / shadow_size)
    _seti(r, "lightMode", 0)
    _setf(r, "sunStrength", 1); _setf(r, "ambient", 1); _seti(r, "numLights", 0)
    return r
end

_setf(r::_Renderer, name, x::Real) = R.SetShaderValue(r.shader, r.loc[name], Float32[x], 0)        # FLOAT
_setv(r::_Renderer, name, v) = R.SetShaderValue(r.shader, r.loc[name], Float32[v...], length(v) - 1) # VEC2/3/4
_seti(r::_Renderer, name, x::Integer) = R.SetShaderValue(r.shader, r.loc[name], Int32[x], 4)       # INT

"""A point light for one frame: where, what colour (0-1, already × intensity), how far."""
struct _Light
    pos::Vec3
    color::Vec3
    range::Float32
end

"""
Upload this frame's point lights. With more than MAX_LIGHTS, the ones nearest
`near` (where the camera looks) are used.
"""
function _set_lights!(r::_Renderer, lights::Vector{_Light}; near = (0f0, 0f0, 0f0))
    if length(lights) > MAX_LIGHTS
        lights = sort(lights; by = l -> vnorm(vsub(l.pos, near)))[1:MAX_LIGHTS]
    end
    n = length(lights)
    _seti(r, "numLights", n)
    n == 0 && return
    pos = Float32[x for l in lights for x in l.pos]
    col = Float32[x for l in lights for x in l.color]
    rng = Float32[l.range for l in lights]
    R.SetShaderValueV(r.shader, r.loc["lightPositions"], pos, 2, n)    # VEC3 × n
    R.SetShaderValueV(r.shader, r.loc["lightColors"], col, 2, n)
    R.SetShaderValueV(r.shader, r.loc["lightRanges"], rng, 0, n)       # FLOAT × n
end

function _free!(r::_Renderer)
    for t in (r.scene_rt, r.rt_a, r.rt_b)
        t === nothing || R.UnloadRenderTexture(t)
    end
    R.rlUnloadFramebuffer(r.shadow.id)
    R.UnloadShader(r.bright); R.UnloadShader(r.blur)
    R.UnloadMaterial(r.depth_mat)
    R.UnloadMaterial(r.mat)
end

# ── batches ──────────────────────────────────────────────────────────────────

"""Objects to draw this frame, grouped so that each group is one draw call."""
struct _Batch
    mesh::R.Mesh
    color::NTuple{4,UInt8}
    glow::Float32
    transforms::Vector{R.Matrix}
end

function _batch!(batches::Dict, mesh::R.Mesh, key, color, alpha, glow, m::R.Matrix)
    k = (key, color, alpha, glow)
    b = get!(() -> _Batch(mesh, (UInt8(color[1]), UInt8(color[2]), UInt8(color[3]), UInt8(alpha)),
                          Float32(glow), R.Matrix[]), batches, k)
    push!(b.transforms, m)
end

function _draw_batches(r::_Renderer, batches; depth::Bool = false)
    # Opaque first, see-through last.
    for b in sort!(collect(values(batches)); by = b -> b.color[4] < 0xff)
        isempty(b.transforms) && continue
        if depth
            b.color[4] < 0xff && continue                 # triggers cast no shadow
            GC.@preserve b R.DrawMeshInstanced(b.mesh, r.depth_mat, pointer(b.transforms), length(b.transforms))
        else
            unsafe_store!(Ptr{R.Color}(r.mat.maps + r.color_off), R.Color(b.color...))
            _setf(r, "glow", b.glow)
            GC.@preserve b R.DrawMeshInstanced(b.mesh, r.mat, pointer(b.transforms), length(b.transforms))
        end
    end
end

# ── shadows ──────────────────────────────────────────────────────────────────

"""
Draw the batches into the shadow map from a directional light, covering a
square `size` wide centred on `center`. Sets the main shader up to use it.
"""
function _shadow_pass!(r::_Renderer, batches, center, size, light_dir)
    if !r.shadows
        _seti(r, "shadowsOn", 0)
        return
    end
    L = vunit(Float32.(Tuple(light_dir)))
    dist = 2f0 * size + 20f0
    up = abs(L[2]) > 0.95f0 ? (0f0, 0f0, 1f0) : (0f0, 1f0, 0f0)
    cam = R.Camera3D(_rl_v3(vsub(center, vscale(L, dist))), _rl_v3(center), _rl_v3(up),
                     Float32(size), Cint(1))                                # CAMERA_ORTHOGRAPHIC
    near, far = 1.0, 2.0 * dist
    R.BeginTextureMode(r.shadow)
    R.ClearBackground(R.Color(0xff, 0xff, 0xff, 0xff))
    R.rlSetClipPlanes(near, far)
    R.BeginMode3D(cam)
    vp = R.MatrixMultiply(R.rlGetMatrixModelview(), R.rlGetMatrixProjection())
    _draw_batches(r, batches; depth = true)
    R.EndMode3D()
    R.EndTextureMode()
    R.rlSetClipPlanes(0.01, 1000.0)                                         # raylib's defaults
    R.SetShaderValueMatrix(r.shader, r.loc["lightVP"], vp)
    _setf(r, "shadowBias", 0.015 / (far - near))                            # ~1.5 cm in depth units
    _seti(r, "shadowsOn", 1)
end

function _bind_shadow!(r::_Renderer)
    r.shadows || return
    R.rlEnableShader(r.shader.id)
    R.rlActiveTextureSlot(_SHADOW_SLOT)
    R.rlEnableTexture(r.shadow.depth.id)
    R.rlSetUniform(r.loc["shadowMap"], Int32[_SHADOW_SLOT], 4, 1)          # SHADER_UNIFORM_INT
    R.rlActiveTextureSlot(0)
end

# ── bloom ────────────────────────────────────────────────────────────────────

function _ensure_targets!(r::_Renderer, w = Int(R.GetRenderWidth()), h = Int(R.GetRenderHeight()))
    (w, h) == r.size && r.scene_rt !== nothing && return
    for t in (r.scene_rt, r.rt_a, r.rt_b)
        t === nothing || R.UnloadRenderTexture(t)
    end
    r.scene_rt = R.LoadRenderTexture(w, h)
    r.rt_a = R.LoadRenderTexture(max(1, w ÷ 2), max(1, h ÷ 2))
    r.rt_b = R.LoadRenderTexture(max(1, w ÷ 2), max(1, h ÷ 2))
    for t in (r.scene_rt, r.rt_a, r.rt_b)
        R.SetTextureFilter(t.texture, 1)                                    # BILINEAR
    end
    r.size = (w, h)
end

_full(t::R.Texture) = R.Rectangle(0f0, 0f0, Float32(t.width), -Float32(t.height))   # render textures are upside down
_draw_into(src::R.Texture, w, h) = R.DrawTexturePro(src, _full(src), R.Rectangle(0f0, 0f0, Float32(w), Float32(h)),
                                                    R.Vector2(0f0, 0f0), 0f0, R.Color(0xff, 0xff, 0xff, 0xff))

"""
Add bloom to what is on screen so far: copy the frame out (resolving MSAA),
pull out the bright parts at half size, blur them, add them back.

With `target` (a RenderTexture the frame is being drawn into, e.g. for a
recording), read the frame from it instead, and add the bloom back into it;
raylib cannot nest texture modes, so this ends the target's texture mode and
begins it again.
"""
function _bloom_pass!(r::_Renderer; target = nothing)
    r.bloom || return
    R.rlDrawRenderBatchActive()
    if target === nothing
        _ensure_targets!(r)
        w, h = r.size
        R.rlBindFramebuffer(_GL_READ_FRAMEBUFFER, 0)
        R.rlBindFramebuffer(_GL_DRAW_FRAMEBUFFER, r.scene_rt.id)
        R.rlBlitFramebuffer(0, 0, w, h, 0, 0, w, h, _GL_COLOR_BUFFER_BIT)
        R.rlDisableFramebuffer()
        src = r.scene_rt.texture
        out_w, out_h = Float32(R.GetScreenWidth()), Float32(R.GetScreenHeight())
    else
        R.EndTextureMode()
        _ensure_targets!(r, Int(target.texture.width), Int(target.texture.height))
        src = target.texture
        out_w, out_h = Float32(target.texture.width), Float32(target.texture.height)
    end
    hw, hh = r.rt_a.texture.width, r.rt_a.texture.height

    R.SetShaderValue(r.bright, R.GetShaderLocation(r.bright, "threshold"), Float32[r.bloom_threshold], 0)
    R.BeginTextureMode(r.rt_a)
    R.ClearBackground(R.Color(0, 0, 0, 0xff))
    R.BeginShaderMode(r.bright); _draw_into(src, hw, hh); R.EndShaderMode()
    R.EndTextureMode()
    dir = R.GetShaderLocation(r.blur, "dir")
    for _ in 1:3                                                            # ping-pong: wider each round
        R.SetShaderValue(r.blur, dir, Float32[1 / hw, 0], 1)
        R.BeginTextureMode(r.rt_b); R.BeginShaderMode(r.blur); _draw_into(r.rt_a.texture, hw, hh); R.EndShaderMode(); R.EndTextureMode()
        R.SetShaderValue(r.blur, dir, Float32[0, 1 / hh], 1)
        R.BeginTextureMode(r.rt_a); R.BeginShaderMode(r.blur); _draw_into(r.rt_b.texture, hw, hh); R.EndShaderMode(); R.EndTextureMode()
    end
    target === nothing || R.BeginTextureMode(target)
    R.BeginBlendMode(1)                                                     # BLEND_ADDITIVE
    R.DrawTexturePro(r.rt_a.texture, _full(r.rt_a.texture), R.Rectangle(0f0, 0f0, out_w, out_h),
                     R.Vector2(0f0, 0f0), 0f0, R.Color(0xff, 0xff, 0xff, UInt8(round(255 * clamp(r.bloom_strength, 0, 1)))))
    R.EndBlendMode()
end
