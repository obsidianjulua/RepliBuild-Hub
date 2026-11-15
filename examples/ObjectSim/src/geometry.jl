# Geometry shared by the simulation and the viewer.
#
# One TriMesh is the single source of an object's shape: the physics side
# builds its collision shape from it (hull points, triangle-mesh buffers) and
# the viewer uploads the same triangles to the GPU. Nothing here touches a
# library, so all of it runs headless.

const Vec3 = NTuple{3,Float32}

"""
    TriMesh(vertices, faces[, normals])

An indexed triangle mesh. `faces` hold 1-based vertex indices. `normals`, when
given, is one normal per vertex (smooth shading for the procedural primitives);
when `nothing`, the viewer shades each face flat.
"""
struct TriMesh
    vertices::Vector{Vec3}
    faces::Vector{NTuple{3,Int32}}
    normals::Union{Nothing,Vector{Vec3}}
end
TriMesh(v, f) = TriMesh(v, f, nothing)

Base.show(io::IO, m::TriMesh) =
    print(io, "TriMesh(", length(m.vertices), " vertices, ", length(m.faces), " triangles)")

# ── small vector helpers (tuples: no allocation, no dependency) ──────────────
@inline v3(x, y, z) = (Float32(x), Float32(y), Float32(z))
@inline vadd(a, b) = (a[1] + b[1], a[2] + b[2], a[3] + b[3])
@inline vsub(a, b) = (a[1] - b[1], a[2] - b[2], a[3] - b[3])
@inline vscale(a, s) = (a[1] * s, a[2] * s, a[3] * s)
@inline vmul(a, b) = (a[1] * b[1], a[2] * b[2], a[3] * b[3])
@inline vdot(a, b) = a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
@inline vcross(a, b) = (a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1])
@inline vnorm(a) = sqrt(vdot(a, a))
@inline function vunit(a)
    n = vnorm(a)
    n > 0 ? vscale(a, 1 / n) : (0.0f0, 1.0f0, 0.0f0)
end

"""
    aabb(m) -> (lo, hi)

Axis-aligned bounds of the mesh's vertices.
"""
function aabb(m::TriMesh)
    isempty(m.vertices) && return ((0f0, 0f0, 0f0), (0f0, 0f0, 0f0))
    lo = hi = m.vertices[1]
    for v in m.vertices
        lo = min.(lo, v)
        hi = max.(hi, v)
    end
    return lo, hi
end

"""
    centroid(m)

Centre of mass of the solid the mesh encloses, assuming uniform density: the
volume-weighted mean of the signed tetrahedra (origin, a, b, c). A mesh that is
open or flat encloses no volume; then the area-weighted mean of the triangles
is used, and failing that the AABB centre.
"""
function centroid(m::TriMesh)
    vol = 0.0
    c = (0.0, 0.0, 0.0)
    area = 0.0
    ca = (0.0, 0.0, 0.0)
    for (i, j, k) in m.faces
        a = Float64.(m.vertices[i]); b = Float64.(m.vertices[j]); d = Float64.(m.vertices[k])
        v = vdot(a, vcross(b, d)) / 6
        vol += v
        c = vadd(c, vscale(vadd(vadd(a, b), d), v / 4))
        t = vnorm(vcross(vsub(b, a), vsub(d, a))) / 2
        area += t
        ca = vadd(ca, vscale(vadd(vadd(a, b), d), t / 3))
    end
    abs(vol) > 1e-9 && return Float32.(vscale(c, 1 / vol))
    area > 1e-12 && return Float32.(vscale(ca, 1 / area))
    lo, hi = aabb(m)
    return vscale(vadd(lo, hi), 0.5f0)
end

"""
    transform_mesh(m; scale = (1,1,1), offset = (0,0,0))

Each vertex becomes `v .* scale .+ offset`. Normals follow the scale (inverse
transpose, then renormalised); a negative scale component flips the winding so
the faces still point outward.
"""
function transform_mesh(m::TriMesh; scale = (1f0, 1f0, 1f0), offset = (0f0, 0f0, 0f0))
    s = Float32.(scale); o = Float32.(offset)
    verts = [vadd(vmul(v, s), o) for v in m.vertices]
    flip = (s[1] * s[2] * s[3]) < 0
    faces = flip ? [(a, c, b) for (a, b, c) in m.faces] : copy(m.faces)
    normals = m.normals === nothing ? nothing :
              [vunit((n[1] / s[1], n[2] / s[2], n[3] / s[3])) for n in m.normals]
    return TriMesh(verts, faces, normals)
end

# ── Procedural primitives, matching bullet3's shapes ─────────────────────────
# All are centred on the origin with Y up, the same frame bullet3's
# btBoxShape / btMultiSphereShape / btCapsuleShape / btCylinderShape /
# btConeShape use, so the body transform places mesh and shape identically.

"""Box with half extents `h`. Flat faces, 24 vertices."""
function box_mesh(h::Vec3)
    verts = Vec3[]; faces = NTuple{3,Int32}[]; normals = Vec3[]
    for axis in 1:3, sgn in (-1f0, 1f0)
        n = ntuple(i -> i == axis ? sgn : 0f0, 3)
        u = ntuple(i -> i == mod1(axis + 1, 3) ? 1f0 : 0f0, 3)
        w = vcross(n, u)
        base = Int32(length(verts))
        for (a, b) in ((-1, -1), (1, -1), (1, 1), (-1, 1))
            p = vadd(vadd(n, vscale(u, a)), vscale(w, b))
            push!(verts, vmul(p, h)); push!(normals, n)
        end
        push!(faces, (base + 1, base + 2, base + 3), (base + 1, base + 3, base + 4))
    end
    return TriMesh(verts, faces, normals)
end

# A surface of revolution about Y: `profile` is a list of (radius, y, nr, ny)
# rings from bottom to top, (nr, ny) the normal in the profile plane. Rings
# with radius 0 are poles.
function _revolve(profile, seg::Int)
    verts = Vec3[]; normals = Vec3[]; faces = NTuple{3,Int32}[]
    for (r, y, nr, ny) in profile, k in 0:seg
        θ = 2π * k / seg
        c, s = Float32(cos(θ)), Float32(sin(θ))
        push!(verts, (r * c, y, r * s))
        push!(normals, vunit((nr * c, ny, nr * s)))
    end
    row = seg + 1
    for i in 0:length(profile) - 2, k in 0:seg - 1
        a = Int32(i * row + k + 1); b = a + Int32(1)
        c = a + Int32(row); d = c + Int32(1)
        # Counter-clockwise seen from outside, i.e. from +r.
        profile[i + 1][1] > 0 && push!(faces, (a, c, b))
        profile[i + 2][1] > 0 && push!(faces, (b, c, d))
    end
    return TriMesh(verts, faces, normals)
end

"""Sphere of radius `r`, smooth normals."""
function sphere_mesh(r::Real; seg::Int = 32, rings::Int = 16)
    prof = [(Float32(r * sin(φ)), Float32(-r * cos(φ)), Float32(sin(φ)), Float32(-cos(φ)))
            for φ in range(0, π; length = rings + 1)]
    return _revolve(prof, seg)
end

"""Capsule: radius `r`, `hh` = half the distance between the two sphere centres."""
function capsule_mesh(r::Real, hh::Real; seg::Int = 32, rings::Int = 8)
    lower = [(Float32(r * sin(φ)), Float32(-hh - r * cos(φ)), Float32(sin(φ)), Float32(-cos(φ)))
             for φ in range(0, π / 2; length = rings + 1)]
    upper = [(Float32(r * cos(φ)), Float32(hh + r * sin(φ)), Float32(cos(φ)), Float32(sin(φ)))
             for φ in range(0, π / 2; length = rings + 1)]
    return _revolve(vcat(lower, upper), seg)
end

"""Cylinder: radius `r`, half height `hh`. Separate cap rings keep the edges sharp."""
function cylinder_mesh(r::Real, hh::Real; seg::Int = 32)
    r = Float32(r); hh = Float32(hh)
    prof = [(0f0, -hh, 0f0, -1f0), (r, -hh, 0f0, -1f0),
            (r, -hh, 1f0, 0f0), (r, hh, 1f0, 0f0),
            (r, hh, 0f0, 1f0), (0f0, hh, 0f0, 1f0)]
    return _merge_bands(prof, seg)
end

"""Cone: base radius `r`, height `h`, centred so the apex is at +h/2 (bullet3's frame)."""
function cone_mesh(r::Real, h::Real; seg::Int = 32)
    r = Float32(r); hh = Float32(h) / 2
    slope = vunit((Float32(h), r, 0f0))           # outward normal of the side
    prof = [(0f0, -hh, 0f0, -1f0), (r, -hh, 0f0, -1f0),
            (r, -hh, slope[1], slope[2]), (0f0, hh, slope[1], slope[2])]
    return _merge_bands(prof, seg)
end

# Profiles whose consecutive pairs are separate bands (hard edges between them):
# rings 1-2, 3-4, 5-6 … each revolve on their own and are concatenated.
function _merge_bands(prof, seg)
    verts = Vec3[]; normals = Vec3[]; faces = NTuple{3,Int32}[]
    for i in 1:2:length(prof) - 1
        m = _revolve(prof[i:i + 1], seg)
        off = Int32(length(verts))
        append!(verts, m.vertices); append!(normals, m.normals)
        append!(faces, [(a + off, b + off, c + off) for (a, b, c) in m.faces])
    end
    return TriMesh(verts, faces, normals)
end

"""
    render_arrays(m) -> (positions, normals)

Flat `Float32` arrays for the GPU, three vertices per triangle (no index
buffer, so there is no 65 535-vertex limit). Uses the mesh's own normals when
it has them, the face normal otherwise.
"""
function render_arrays(m::TriMesh)
    n = 9 * length(m.faces)
    pos = Vector{Float32}(undef, n); nrm = Vector{Float32}(undef, n)
    o = 0
    for (i, j, k) in m.faces
        a, b, c = m.vertices[i], m.vertices[j], m.vertices[k]
        fn = vunit(vcross(vsub(b, a), vsub(c, a)))
        for (idx, p) in ((i, a), (j, b), (k, c))
            nv = m.normals === nothing ? fn : m.normals[idx]
            pos[o+1], pos[o+2], pos[o+3] = p
            nrm[o+1], nrm[o+2], nrm[o+3] = nv
            o += 3
        end
    end
    return pos, nrm
end
