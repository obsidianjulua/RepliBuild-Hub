# Mesh files → TriMesh. Plain Julia, no GPU, so headless runs can load assets.
#
# Only geometry is read: positions and faces. Texture coordinates, normals,
# materials and groups in the file are skipped. Collision only needs the
# positions, and the viewer shades flat from the faces.

"""
    load_mesh(path) -> TriMesh

Read a Wavefront `.obj` or an `.stl` (ASCII or binary).
"""
function load_mesh(path::AbstractString)
    isfile(path) || error("ObjectSim: mesh file not found: $path")
    ext = lowercase(splitext(path)[2])
    ext == ".obj" && return load_obj(path)
    ext == ".stl" && return load_stl(path)
    error("ObjectSim: unsupported mesh format '$ext' ($path); use .obj or .stl")
end

"""
    load_obj(path) -> TriMesh

`v x y z` and `f a b c …` lines. Face entries may be `i`, `i/t`, `i//n` or
`i/t/n`; negative indices count back from the latest vertex. Polygons are
triangulated as a fan, which is right for the convex faces exporters write.
"""
function load_obj(path::AbstractString)
    verts = Vec3[]; faces = NTuple{3,Int32}[]
    for (lineno, raw) in enumerate(eachline(path))
        line = strip(raw)
        (isempty(line) || startswith(line, '#')) && continue
        parts = split(line)
        tag = parts[1]
        if tag == "v"
            length(parts) >= 4 || error("$path:$lineno: vertex needs 3 coordinates")
            push!(verts, (parse(Float32, parts[2]), parse(Float32, parts[3]), parse(Float32, parts[4])))
        elseif tag == "f"
            idx = Int32[]
            for p in @view parts[2:end]
                i = parse(Int, first(split(p, '/')))
                i = i < 0 ? length(verts) + 1 + i : i
                1 <= i <= length(verts) || error("$path:$lineno: face index $p out of range")
                push!(idx, Int32(i))
            end
            length(idx) >= 3 || error("$path:$lineno: face needs 3 or more vertices")
            for k in 2:length(idx) - 1
                push!(faces, (idx[1], idx[k], idx[k + 1]))
            end
        end
    end
    isempty(faces) && error("ObjectSim: $path has no faces")
    return TriMesh(verts, faces)
end

"""
    load_stl(path) -> TriMesh

Binary STL is recognised by its size (84 + 50·n bytes); anything else is read
as ASCII. STL repeats every corner per triangle, so identical positions are
welded back into shared vertices: hull building and the centroid both work on
the shared set.
"""
function load_stl(path::AbstractString)
    sz = filesize(path)
    tris = Vec3[]
    open(path) do io
        if sz >= 84
            seek(io, 80)
            n = ltoh(read(io, UInt32))
            if 84 + 50 * Int(n) == sz
                for _ in 1:n
                    skip(io, 12)                                    # facet normal
                    for _ in 1:3
                        push!(tris, (ltoh(read(io, Float32)), ltoh(read(io, Float32)), ltoh(read(io, Float32))))
                    end
                    skip(io, 2)                                     # attribute bytes
                end
                return
            end
        end
        seekstart(io)
        for line in eachline(io)
            parts = split(strip(line))
            if !isempty(parts) && parts[1] == "vertex"
                push!(tris, (parse(Float32, parts[2]), parse(Float32, parts[3]), parse(Float32, parts[4])))
            end
        end
    end
    (isempty(tris) || length(tris) % 3 != 0) && error("ObjectSim: $path is not a readable STL")
    index = Dict{Vec3,Int32}()
    verts = Vec3[]; faces = NTuple{3,Int32}[]
    weld(p) = get!(index, p) do
        push!(verts, p); Int32(length(verts))
    end
    for t in 1:3:length(tris)
        push!(faces, (weld(tris[t]), weld(tris[t + 1]), weld(tris[t + 2])))
    end
    return TriMesh(verts, faces)
end

"""
    save_obj(path, m)

Write a mesh as `.obj` (positions and faces only).
"""
function save_obj(path::AbstractString, m::TriMesh; comment::AbstractString = "")
    open(path, "w") do io
        isempty(comment) || foreach(l -> println(io, "# ", l), split(comment, '\n'))
        for v in m.vertices
            println(io, "v ", join((round(x; digits = 5) for x in v), ' '))
        end
        for f in m.faces
            println(io, "f ", join(f, ' '))
        end
    end
    return path
end
