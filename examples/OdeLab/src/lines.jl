# Trails as GPU line strips.
#
# raylib's DrawLine3D is one call per segment, and through the wrapper that
# measured ~16 ms a frame for a 20,000-point trail: too slow for an attractor.
# Here a trail is one vertex buffer, updated when it changes and drawn with ONE
# glDrawArrays(GL_LINE_STRIP). rlgl does the buffer and attribute work; only
# the draw call itself goes to libGL, because rlgl's rlDrawVertexArray always
# draws triangles. The colour fades from `old` to `new` along the strip, worked
# out in the vertex shader from gl_VertexID, so there is no colour buffer.

const _LINE_VS = """
#version 330
in vec3 vertexPosition;
uniform mat4 mvp;
uniform int first;
uniform int count;
uniform vec4 colOld;
uniform vec4 colNew;
out vec4 vCol;
void main() {
    float a = count > 1 ? float(gl_VertexID - first) / float(count - 1) : 1.0;
    vCol = mix(colOld, colNew, a * a);
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
"""

const _LINE_FS = """
#version 330
in vec4 vCol;
out vec4 finalColor;
void main() { finalColor = vCol; }
"""

const _GL = "libGL.so.1"
const _GL_LINE_STRIP = Cuint(0x0003)
const _RL_FLOAT = 0x1406
const _UNIFORM_VEC4 = 3
const _UNIFORM_INT = 4

const Vec3f = NTuple{3,Float32}
const Rgba = NTuple{4,Float32}

struct LineShader
    sh::R.Shader
    mvp::Cint
    first::Cint
    count::Cint
    old::Cint
    new::Cint
end

function LineShader()
    sh = R.LoadShaderFromMemory(_LINE_VS, _LINE_FS)
    sh.id == R.rlGetShaderIdDefault() && error("OdeLab: the trail shader did not compile (raylib's log says why)")
    loc(n) = R.GetShaderLocation(sh, n)
    return LineShader(sh, loc("mvp"), loc("first"), loc("count"), loc("colOld"), loc("colNew"))
end
unload!(ls::LineShader) = R.UnloadShader(ls.sh)

mutable struct Strip
    vao::Cuint
    vbo::Cuint
    cap::Int
    n::Int
end

function Strip(cap::Integer = 4096)
    vao = R.rlLoadVertexArray()
    R.rlEnableVertexArray(vao)
    vbo = R.rlLoadVertexBuffer(C_NULL, Cint(cap * sizeof(Vec3f)), true)
    R.rlSetVertexAttribute(0, 3, _RL_FLOAT, false, 0, 0)   # location 0 = vertexPosition in raylib's shaders
    R.rlEnableVertexAttribute(0)
    R.rlDisableVertexArray()
    return Strip(vao, vbo, Int(cap), 0)
end

function unload!(s::Strip)
    s.vao == 0 && return
    R.rlUnloadVertexBuffer(s.vbo); R.rlUnloadVertexArray(s.vao)
    s.vao = s.vbo = 0
    return
end

"""Replace the strip's points (the buffer grows as needed)."""
function upload!(s::Strip, pts::Vector{Vec3f})
    n = length(pts)
    if n > s.cap
        unload!(s)
        t = Strip(nextpow(2, n))
        s.vao, s.vbo, s.cap = t.vao, t.vbo, t.cap
    end
    n > 0 && GC.@preserve pts R.rlUpdateVertexBuffer(s.vbo, pointer(pts), Cint(n * sizeof(Vec3f)), 0)
    s.n = n
    return s
end

# raylib's Matrix fields are declared m0 m4 m8 m12 m1 …, i.e. row by row of the
# column-major GL matrix, so reading them in order gives rows.
_jmat(m::R.Matrix) = (f = ntuple(i -> getfield(m, i), 16);
                      [f[1] f[2] f[3] f[4]; f[5] f[6] f[7] f[8]; f[9] f[10] f[11] f[12]; f[13] f[14] f[15] f[16]])
_rmat(M) = R.Matrix(ntuple(i -> Float32(M[(i - 1) ÷ 4 + 1, (i - 1) % 4 + 1]), 16)...)

"""The current projection × modelview. Call between BeginMode3D and EndMode3D."""
current_mvp() = _rmat(_jmat(R.rlGetMatrixProjection()) * _jmat(R.rlGetMatrixModelview()))

"""
    draw!(ls, s, mvp, old, new; additive = false)

Draw the strip, its colour fading from `old` (first point) to `new` (last).
Flushes raylib's batch first so depth and order stay right.
"""
function draw!(ls::LineShader, s::Strip, mvp::R.Matrix, old::Rgba, new::Rgba; additive::Bool = false)
    s.n < 2 && return
    R.rlDrawRenderBatchActive()
    additive && R.rlSetBlendMode(1)                  # BLEND_ADDITIVE: dense regions glow
    R.rlEnableShader(ls.sh.id)
    R.rlSetUniformMatrix(ls.mvp, mvp)
    R.rlSetUniform(ls.first, Ref(Cint(0)), _UNIFORM_INT, 1)
    R.rlSetUniform(ls.count, Ref(Cint(s.n)), _UNIFORM_INT, 1)
    R.rlSetUniform(ls.old, Ref(old), _UNIFORM_VEC4, 1)
    R.rlSetUniform(ls.new, Ref(new), _UNIFORM_VEC4, 1)
    R.rlEnableVertexArray(s.vao)
    ccall((:glDrawArrays, _GL), Cvoid, (Cuint, Cint, Cint), _GL_LINE_STRIP, 0, s.n)
    R.rlDisableVertexArray()
    R.rlDisableShader()
    additive && R.rlSetBlendMode(0)                  # back to BLEND_ALPHA
    return
end
