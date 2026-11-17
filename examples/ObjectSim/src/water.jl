# Water: buoyancy and drag for every moving body, as a force hook.
#
# Each body is split into small cells once: a grid over its own (body-local)
# mesh, keeping the cell centres that are inside the mesh, each carrying an
# equal share of the mesh's volume. Before every fixed step, a cell below the
# surface is pushed up by the weight of the water it displaces (Archimedes:
# ρ·V·g, against gravity) at its own position, so a body that floats tilted
# gets the turning push that rights it (or capsizes it, if it is top-heavy).
# A cell is treated as a little cube, so one that straddles the surface counts
# the part that is under. The same cells feel drag, ½·ρ·C·A·|v|·v on their
# own velocity (which includes the body's spin), so things slow down, stop
# spinning and settle in water instead of bobbing forever.
#
# Whether a body floats is its density against the water's: mass / volume.
# A 1 m crate of 1000 kg is exactly neutral in fresh water.

"""
    volume(m::TriMesh) -> m³

The volume the mesh encloses (signed tetrahedra; an open mesh gives an
approximation).
"""
function volume(m::TriMesh)
    v = 0.0
    for (i, j, k) in m.faces
        a = Float64.(m.vertices[i]); b = Float64.(m.vertices[j]); c = Float64.(m.vertices[k])
        v += vdot(a, vcross(b, c)) / 6
    end
    return abs(v)
end

# Inside test by crossings: a ray from the point along an axis, counting the
# triangles it passes through (odd = inside). Points on the same grid line
# share one ray, so each line costs one pass over the triangles. Three rays
# (along x, y, z) vote, which forgives a small hole or a seam.
function _hits(m::TriMesh, u::Int, w::Int, axis::Int, pu, pw)
    out = Float32[]
    @inbounds for (i, j, k) in m.faces
        a, b, c = m.vertices[i], m.vertices[j], m.vertices[k]
        au, aw = a[u] - pu, a[w] - pw
        bu, bw = b[u] - pu, b[w] - pw
        cu, cw = c[u] - pu, c[w] - pw
        d1 = au * bw - aw * bu; d2 = bu * cw - bw * cu; d3 = cu * aw - cw * au
        ((d1 > 0) == (d2 > 0) == (d3 > 0) && d1 != 0 && d2 != 0 && d3 != 0) || continue
        push!(out, (d2 * a[axis] + d3 * b[axis] + d1 * c[axis]) / (d1 + d2 + d3))
    end
    return out
end

# votes[i, j, k] += 1 for each grid point the ray along `axis` finds inside
function _vote!(votes, m, grid, axis, nudge)
    u, w = axis == 1 ? (2, 3) : axis == 2 ? (3, 1) : (1, 2)
    for iu in eachindex(grid[u]), iw in eachindex(grid[w])
        # nudged off the grid line a hair, so a ray never runs exactly along
        # a triangle edge (the diagonal of a box face) and misses both sides
        hits = _hits(m, u, w, axis, grid[u][iu] + 0.731f0 * nudge, grid[w][iw] + 0.379f0 * nudge)
        isempty(hits) && continue
        for ia in eachindex(grid[axis])
            isodd(count(>(grid[axis][ia]), hits)) || continue
            idx = ntuple(d -> d == axis ? ia : d == u ? iu : iw, 3)
            votes[idx...] += 1
        end
    end
end

"""
    buoyancy_cells(m::TriMesh; across = 4, max_cells = 400) -> (points, cell_volume, volume)

The body-local cell centres water pushes on, their volume each, and the
mesh's volume. Cells are cubes, `across` of them over the mesh's thinnest
side (so a long hull still gets several across its beam, which is what lets
it right itself), made bigger if that would exceed `max_cells`. A mesh too
thin for any centre to fall inside gets a single cell at its middle.
"""
function buoyancy_cells(m::TriMesh; across::Integer = 4, max_cells::Integer = 400)
    V = volume(m)
    lo, hi = aabb(m)
    ext = map(e -> max(e, 1f-3), vsub(hi, lo))
    V < 1e-9 && (V = Float64(ext[1] * ext[2] * ext[3]))   # flat or open: use the box
    h = minimum(ext) / across
    counts = map(e -> max(1, ceil(Int, e / h)), ext)
    while prod(counts) > max_cells
        h *= 1.15f0
        counts = map(e -> max(1, ceil(Int, e / h)), ext)
    end
    grid = ntuple(d -> [lo[d] + ext[d] * (i - 0.5f0) / counts[d] for i in 1:counts[d]], 3)
    votes = zeros(Int8, counts...)
    foreach(ax -> _vote!(votes, m, grid, ax, 1f-4 * h), 1:3)
    pts = Vec3[(grid[1][I[1]], grid[2][I[2]], grid[3][I[3]]) for I in CartesianIndices(votes) if votes[I] >= 2]
    isempty(pts) && push!(pts, vscale(vadd(lo, hi), 0.5f0))
    return pts, V / length(pts), V
end

# cells, cell volume, volume, and how far the geometry reaches from the
# centre of mass (to skip bodies wholly above the surface cheaply)
function _cells_reach(m::TriMesh)
    pts, cv, V = buoyancy_cells(m)
    return pts, cv, V, Float64(maximum(vnorm(p) for p in m.vertices; init = 0f0))
end

# Cells per body, worked out once per piece of geometry and reused by every
# body built from it (a hundred crates share one set).
const _CELLS = Dict{Any,Tuple{Vector{Vec3},Float64,Float64,Float64}}()
_cells(b::Body) = get!(() -> _cells_reach(b.mesh), _CELLS,
                       (b.spec.shape, b.spec.size, b.spec.radius, b.spec.height, b.spec.asset, b.spec.scale))

"""Volume of a body's shape, m³ (the mesh it is drawn with)."""
body_volume(b::Body) = _cells(b)[3]

"""Density of a body, kg/m³: mass over volume. Water is 1000."""
density(b::Body) = mass(b) / body_volume(b)

"""
    water_force(spec::WaterSpec) -> f

The force hook behind a scene's `[water]`: buoyancy and drag on every moving
body (see the top of src/water.jl).
"""
function water_force(spec::WaterSpec)
    return (w::World, dt) -> _water!(w, w.phys, spec, dt)
end

function _water!(w::World, P::Physics, spec::WaterSpec, dt)
    ρ = Float64(spec.density); level = Float64(spec.level); C = Float64(spec.drag)
    for b in w.bodies
        isstatic(b) && continue
        (R, o) = _be_transform(P, b)
        pts, cv, _, reach = _cells(b)
        o[2] - reach > level && continue            # wholly above the water
        h = cbrt(cv); area = h * h
        g = b.spec.gravity === nothing ? w.gravity : b.spec.gravity
        v = _be_velocity(P, b); ω = _be_spin(P, b)
        m_cell = mass(b) / length(pts)
        J = (0.0, 0.0, 0.0); T = (0.0, 0.0, 0.0)
        for lp in pts
            r = _rotate(R, lp)                      # from the centre of mass
            depth = level - (o[2] + r[2])
            f = clamp(depth / h + 0.5, 0.0, 1.0)
            f == 0 && continue
            # Archimedes: −ρ·V·g, for the part of the cell that is under
            j = (-ρ * cv * f * g[1] * dt, -ρ * cv * f * g[2] * dt, -ρ * cv * f * g[3] * dt)
            # drag on the cell's own velocity, never more than stops it
            vp = vadd(Float64.(v), vcross(Float64.(ω), Float64.(r)))
            sp = vnorm(vp)
            if sp > 1e-6 && C > 0
                k = min(0.5 * ρ * C * area * f * sp * dt, m_cell)
                j = vsub(j, vscale(vp, k))
            end
            J = vadd(J, j); T = vadd(T, vcross(Float64.(r), j))
        end
        J == (0.0, 0.0, 0.0) && continue
        _be_impulse!(P, b, Float32.(J), nothing)
        _be_angular_impulse!(P, b, Float32.(T))
    end
    return nothing
end

"""
    set_water!(w, spec::Union{WaterSpec,Nothing})

Fill the world with water (or drain it, with `nothing`). Bodies are woken so
they start floating or falling at once.
"""
function set_water!(w::World, spec)
    _check(w)
    w.water === nothing || filter!(f -> f !== w.water[2], w.forces)
    if spec === nothing
        w.water = nothing
    else
        f = water_force(spec)
        push!(w.forces, f)
        w.water = (spec, f)
    end
    foreach(b -> isstatic(b) || wake!(b), w.bodies)
    return w
end

"""The world's water spec, or `nothing`."""
water(w::World) = w.water === nothing ? nothing : w.water[1]
