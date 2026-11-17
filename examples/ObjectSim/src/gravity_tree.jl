# Mutual gravity's two ways of summing: the direct O(N²) sum, every pair, and a
# Barnes–Hut octree, O(N log N), which pulls a body towards a far group of
# bodies as one point at the group's centre of mass. `mutual_gravity`
# (interactions.jl) gathers the sources each step and calls `_gravity_accel!`,
# which picks one by the number of sources.
#
# Both work in Float64 on structure-of-arrays sources x, y, z, gm (gravitating
# mass) and write a = G·Σ m_j·d/r³ into ax, ay, az; pairs at r = 0 are skipped,
# with no softening. The tree is rebuilt every step into buffers it keeps, so
# once warm a step allocates nothing (bar the tasks `Threads.@threads` starts).
#
# Crossover, measured on a 32-thread machine with Julia on 32 threads (the
# `objectsim` launcher's default): N spheres in a uniform ball, Jolt, zero g,
# mutual gravity on; µs for one gravity hook call (gathering, the sum, the
# impulses) and for a whole fixed step with it, best of 15-50:
#        N    hook: direct    tree    step: direct    tree
#      256            61        74             169     177
#      512           118       137             308     314
#     1024           220       273             437     486
#     1536           337       374             696     658
#     2048           571       524             995     794
#     3072          1062       837            1583    1297
#     4096          1717      1046            2753    2145
#     8192          6242      2408            7539    3571
# so the tree takes over from 2000 sources. On one thread the sum alone
# (direct / tree, µs) is 197 / 208 at 512, 788 / 686 at 1024, 3091 / 1745 at
# 2048 and 49332 / 11686 at 8192: there it pays from about 800.
#
# Accuracy against the direct sum at θ = 0.5, |a_tree − a|/|a| per body,
# median / worst: uniform ball 0.09 % / 1.2 % (N = 1000), 0.26 % / 4.5 %
# (N = 8192); five clumps 0.02 % / 0.6 % (1000), 0.06 % / 0.7 % (8192). The
# worst are bodies near a ball's middle, where the pulls nearly cancel. θ = 0.3:
# ball 0.05 % / 2.1 % at 8192; θ = 0.7: 0.6 % / 19 %.
#
# GRAVITY_THETA[]: the opening angle. Each leaf (a group of up to _BH_LEAF
# nearby bodies) walks the tree once: a node of side s is taken whole, as its
# centre of mass, when that is further than s/θ + δ from every point of the
# group's bounding box (δ: how far the centre of mass sits from the node's
# geometric centre), else opened; a leaf too near is summed body by body.
# Smaller is more accurate and slower; θ < 1.15 never takes a node that holds
# the body itself.
# GRAVITY_TREE_FROM[]: the source count from which the tree is used (1: always;
# typemax(Int): never).
const GRAVITY_THETA = Ref(0.5)
const GRAVITY_TREE_FROM = Ref(2000)

const _BH_LEAF = 32              # at most this many bodies in a leaf (8, 16, 64 measured slower)
const _BH_MAXDEPTH = 48          # deeper than this, a leaf takes whatever is left (coincident bodies)

# ── direct sum ───────────────────────────────────────────────────────────────

# Every pair, all of i's partners in one SIMD loop (both halves of each pair:
# twice the arithmetic of the half-matrix loop but no scattered writes, which
# is faster up to thousands of bodies). Threads take rows when Julia has them.
function _gravity_direct!(ax, ay, az, x, y, z, gm, G::Float64)
    n = length(x)
    if Threads.nthreads() > 1 && n >= 512
        Threads.@threads for i in 1:n
            _direct_row!(ax, ay, az, x, y, z, gm, G, i)
        end
    else
        for i in 1:n
            _direct_row!(ax, ay, az, x, y, z, gm, G, i)
        end
    end
    return nothing
end

@inline function _direct_row!(ax, ay, az, x, y, z, gm, G::Float64, i::Int)
    @inbounds begin
        n = length(x)
        xi, yi, zi = x[i], y[i], z[i]
        sx = sy = sz = 0.0
        @simd for j in 1:n
            dx = x[j] - xi; dy = y[j] - yi; dz = z[j] - zi
            r2 = dx * dx + dy * dy + dz * dz
            s = ifelse(r2 > 0, gm[j] / (r2 * sqrt(r2)), 0.0)
            sx += s * dx; sy += s * dy; sz += s * dz
        end
        ax[i] = G * sx; ay[i] = G * sy; az[i] = G * sz
    end
    return nothing
end

# ── Barnes–Hut octree ────────────────────────────────────────────────────────

# Nodes are stored depth first, so a node's first child is the next node and
# `skip` is the node after its whole subtree: the walk needs no stack. Each
# node covers a range lo:hi of the sources in tree order (sx, sy, sz, sm), so
# a near leaf goes onto an interaction list straight from contiguous memory.
mutable struct GravityTree
    perm::Vector{Int32}          # tree order → source index
    tmp::Vector{Int32}
    oct::Vector{UInt8}           # each source's octant in the node being split
    sx::Vector{Float64}; sy::Vector{Float64}; sz::Vector{Float64}; sm::Vector{Float64}
    cmx::Vector{Float64}; cmy::Vector{Float64}; cmz::Vector{Float64}; m::Vector{Float64}
    crit2::Vector{Float64}       # taken whole beyond √crit2 from its centre of mass
    lo::Vector{Int32}; hi::Vector{Int32}; skip::Vector{Int32}
    leaf::Vector{Bool}
    leaves::Vector{Int32}        # the leaf nodes, in tree order
    count::Matrix{Int32}         # octant counts, one column per depth
    lists::Vector{NTuple{4, Vector{Float64}}}    # interaction lists (x, y, z, m), one per chunk
end

GravityTree() = GravityTree(Int32[], Int32[], UInt8[], Float64[], Float64[], Float64[], Float64[],
    Float64[], Float64[], Float64[], Float64[], Float64[], Int32[], Int32[], Int32[], Bool[],
    Int32[], zeros(Int32, 9, _BH_MAXDEPTH + 1), NTuple{4, Vector{Float64}}[])

_nnodes(t::GravityTree) = length(t.lo)

function _bh_build!(t::GravityTree, x, y, z, gm, θ::Float64)
    n = length(x)
    resize!(t.perm, n); resize!(t.tmp, n); resize!(t.oct, n)
    for v in (t.sx, t.sy, t.sz, t.sm)
        resize!(v, n)
    end
    for v in (t.cmx, t.cmy, t.cmz, t.m, t.crit2)
        empty!(v)
    end
    empty!(t.lo); empty!(t.hi); empty!(t.skip); empty!(t.leaf); empty!(t.leaves)
    n == 0 && return t
    xmin = ymin = zmin = Inf; xmax = ymax = zmax = -Inf
    @inbounds for i in 1:n
        t.perm[i] = i
        xmin = min(xmin, x[i]); xmax = max(xmax, x[i])
        ymin = min(ymin, y[i]); ymax = max(ymax, y[i])
        zmin = min(zmin, z[i]); zmax = max(zmax, z[i])
    end
    h = 0.5 * max(xmax - xmin, ymax - ymin, zmax - zmin)
    h = h > 0 ? h * (1 + 1e-9) : 1.0
    _bh_node!(t, x, y, z, gm, Int32(1), Int32(n), 0.5 * (xmin + xmax), 0.5 * (ymin + ymax),
        0.5 * (zmin + zmax), h, 1, θ)
    @inbounds for k in 1:n                               # sources in tree order
        i = t.perm[k]
        t.sx[k] = x[i]; t.sy[k] = y[i]; t.sz[k] = z[i]; t.sm[k] = gm[i]
    end
    return t
end

# One node over perm[lo:hi], a cube of half side h round (cx, cy, cz): split
# into its occupied octants, recursively. Returns the node's mass and its
# mass-weighted position sums.
function _bh_node!(t::GravityTree, x, y, z, gm, lo::Int32, hi::Int32,
                   cx::Float64, cy::Float64, cz::Float64, h::Float64, depth::Int, θ::Float64)
    k = length(t.lo) + 1
    push!(t.lo, lo); push!(t.hi, hi); push!(t.skip, 0); push!(t.leaf, false)
    push!(t.cmx, 0.0); push!(t.cmy, 0.0); push!(t.cmz, 0.0); push!(t.m, 0.0); push!(t.crit2, 0.0)
    M = Mx = My = Mz = 0.0
    if hi - lo + 1 <= _BH_LEAF || depth > _BH_MAXDEPTH
        t.leaf[k] = true
        push!(t.leaves, k)
        @inbounds for q in lo:hi
            i = t.perm[q]; mi = gm[i]
            M += mi; Mx += mi * x[i]; My += mi * y[i]; Mz += mi * z[i]
        end
    else
        c = view(t.count, :, depth)
        fill!(c, 0)
        @inbounds for q in lo:hi
            i = t.perm[q]
            o = UInt8((x[i] > cx) | ((y[i] > cy) << 1) | ((z[i] > cz) << 2))
            t.oct[q] = o
            c[o + 2] += 1
        end
        c[1] = lo                                         # c[o+1]: where octant o starts
        @inbounds for o in 2:9
            c[o] += c[o - 1]
        end
        @inbounds for q in lo:hi                         # scatter by octant, keep the starts
            o = t.oct[q] + 1
            t.tmp[c[o]] = t.perm[q]; c[o] += 1
        end
        @inbounds for q in lo:hi
            t.perm[q] = t.tmp[q]
        end
        # c[o] now ends octant o (exclusive); octant o runs (o == 1 ? lo : c[o-1]) : c[o]-1
        h2 = 0.5 * h
        start = lo
        for o in 1:8
            stop = @inbounds c[o] - Int32(1)
            if stop >= start
                b = o - 1
                m, mx, my, mz = _bh_node!(t, x, y, z, gm, start, stop,
                    cx + ifelse(b & 1 != 0, h2, -h2), cy + ifelse(b & 2 != 0, h2, -h2),
                    cz + ifelse(b & 4 != 0, h2, -h2), h2, depth + 1, θ)::NTuple{4, Float64}
                M += m; Mx += mx; My += my; Mz += mz
            end
            start = stop + Int32(1)
        end
    end
    @inbounds begin
        t.skip[k] = length(t.lo) + 1
        t.m[k] = M
        gx, gy, gz = Mx / M, My / M, Mz / M
        t.cmx[k] = gx; t.cmy[k] = gy; t.cmz[k] = gz
        δ = sqrt((gx - cx)^2 + (gy - cy)^2 + (gz - cz)^2)
        r = 2h / θ + δ
        t.crit2[k] = r * r
    end
    return M, Mx, My, Mz
end

# Each leaf is a group of nearby bodies that walks the tree once: a node is
# taken whole when it is far enough from the nearest point of the group's
# bounding box (so from every body in it), its centre of mass going on the
# group's interaction list; a leaf too near puts its bodies on the list. Then
# every body in the group sums the list in one SIMD loop (r = 0 skipped: the
# body itself).
function _bh_grow!(L::NTuple{4, Vector{Float64}}, need::Integer)
    for v in L
        resize!(v, max(256, 2need))
    end
end

function _bh_group!(t::GravityTree, L::NTuple{4, Vector{Float64}}, g::Int32, ax, ay, az, G::Float64)
    lx, ly, lz, lm = L
    px, py, pz, pm = t.sx, t.sy, t.sz, t.sm
    @inbounds begin
        glo, ghi = t.lo[g], t.hi[g]
        x0 = y0 = z0 = Inf; x1 = y1 = z1 = -Inf
        for q in glo:ghi
            x0 = min(x0, px[q]); x1 = max(x1, px[q])
            y0 = min(y0, py[q]); y1 = max(y1, py[q])
            z0 = min(z0, pz[q]); z1 = max(z1, pz[q])
        end
        nl = 0
        nn = Int32(_nnodes(t))
        k = Int32(1)
        while k <= nn
            cx, cy, cz = t.cmx[k], t.cmy[k], t.cmz[k]
            dx = max(x0 - cx, cx - x1, 0.0)
            dy = max(y0 - cy, cy - y1, 0.0)
            dz = max(z0 - cz, cz - z1, 0.0)
            if dx * dx + dy * dy + dz * dz > t.crit2[k]
                nl + 1 > length(lx) && _bh_grow!(L, nl + 1)
                nl += 1
                lx[nl] = cx; ly[nl] = cy; lz[nl] = cz; lm[nl] = t.m[k]
                k = t.skip[k]
            elseif t.leaf[k]
                lo, hi = t.lo[k], t.hi[k]
                nl + (hi - lo + 1) > length(lx) && _bh_grow!(L, nl + hi - lo + 1)
                for q in lo:hi
                    nl += 1
                    lx[nl] = px[q]; ly[nl] = py[q]; lz[nl] = pz[q]; lm[nl] = pm[q]
                end
                k = t.skip[k]
            else
                k += Int32(1)
            end
        end
        for q in glo:ghi
            xi, yi, zi = px[q], py[q], pz[q]
            sx = sy = sz = 0.0
            @simd for j in 1:nl
                ex = lx[j] - xi; ey = ly[j] - yi; ez = lz[j] - zi
                e2 = ex * ex + ey * ey + ez * ez
                s = ifelse(e2 > 0, lm[j] / (e2 * sqrt(e2)), 0.0)
                sx += s * ex; sy += s * ey; sz += s * ez
            end
            i = t.perm[q]
            ax[i] = G * sx; ay[i] = G * sy; az[i] = G * sz
        end
    end
    return nothing
end

function _gravity_tree!(t::GravityTree, ax, ay, az, x, y, z, gm, G::Float64, θ::Float64 = GRAVITY_THETA[])
    n = length(x)
    _bh_build!(t, x, y, z, gm, θ)
    nleaf = length(t.leaves)
    threaded = Threads.nthreads() > 1 && n >= 512
    # Leaves in chunks, one interaction list per chunk (kept between steps).
    nchunk = threaded ? min(nleaf, 4 * Threads.nthreads()) : min(nleaf, 1)
    while length(t.lists) < nchunk
        push!(t.lists, (Float64[], Float64[], Float64[], Float64[]))
    end
    if threaded
        Threads.@threads for c in 1:nchunk
            _bh_chunk!(t, c, nchunk, ax, ay, az, G)
        end
    else
        for c in 1:nchunk
            _bh_chunk!(t, c, nchunk, ax, ay, az, G)
        end
    end
    return nothing
end

function _bh_chunk!(t::GravityTree, c::Int, nchunk::Int, ax, ay, az, G::Float64)
    nleaf = length(t.leaves)
    L = t.lists[c]
    for j in (1 + (c - 1) * nleaf ÷ nchunk):(c * nleaf ÷ nchunk)
        _bh_group!(t, L, @inbounds(t.leaves[j]), ax, ay, az, G)
    end
    return nothing
end

# ── choosing ─────────────────────────────────────────────────────────────────

function _gravity_accel!(t::GravityTree, ax, ay, az, x, y, z, gm, G::Float64)
    n = length(x)
    resize!(ax, n); resize!(ay, n); resize!(az, n)
    if n >= GRAVITY_TREE_FROM[]
        _gravity_tree!(t, ax, ay, az, x, y, z, gm, G, Float64(GRAVITY_THETA[]))
    else
        _gravity_direct!(ax, ay, az, x, y, z, gm, G)
    end
    return nothing
end
