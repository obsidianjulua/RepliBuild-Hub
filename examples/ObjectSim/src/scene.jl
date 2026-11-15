# Scene files: TOML → ObjectSpec list. Pure Julia; nothing is created here.
#
#   [world]
#   gravity = [0, -9.81, 0]     # m/s²
#   hz      = 120               # fixed physics steps per simulated second
#
#   [[object]]
#   name     = "crate"
#   shape    = "box"            # box | sphere | capsule | cylinder | cone | hull | mesh
#   size     = [1, 1, 1]        # box: full extents
#   radius   = 0.5              # sphere, capsule, cylinder, cone
#   height   = 2.0              # capsule (tip to tip), cylinder, cone
#   asset    = "assets/rock.obj"  # hull, mesh; relative to the scene file
#   scale    = 1.0              # hull, mesh: number or [x, y, z]
#   mass     = 1.0              # kg; 0 = static. mesh is always static
#   position = [0, 5, 0]        # where the shape's own origin goes
#   rotation = [0, 45, 0]       # degrees about X, then Y, then Z
#   velocity = [0, 0, 0]        # m/s, initial
#   spin     = [0, 0, 0]        # rad/s, initial
#   friction = 0.5
#   restitution = 0.0           # bounciness
#   rolling_friction = 0.0
#   damping  = [0.0, 0.0]       # linear, angular
#   color    = "#d94f3d"        # or [r, g, b] 0-255
#   repeat   = [1, 1, 1]        # copies along x, y, z …
#   spacing  = [1, 1, 1]        # … this far apart (default: the object's size)

const SHAPES = (:box, :sphere, :capsule, :cylinder, :cone, :hull, :mesh)

const PALETTE = (
    (0xd9, 0x4f, 0x3d), (0x3d, 0x8b, 0xd9), (0xe8, 0xb3, 0x3a), (0x4f, 0xb0, 0x6a),
    (0x9a, 0x6f, 0xd6), (0xe0, 0x7b, 0x39), (0x38, 0xb2, 0xac), (0xc9, 0x5f, 0x9b),
)

Base.@kwdef struct WorldSpec
    gravity::Vec3 = (0f0, -9.81f0, 0f0)
    hz::Int = 120
end

Base.@kwdef struct ObjectSpec
    name::String
    shape::Symbol
    size::Vec3 = (1f0, 1f0, 1f0)       # box full extents
    radius::Float32 = 0.5f0
    height::Float32 = 1f0
    asset::String = ""                 # absolute path once parsed
    scale::Vec3 = (1f0, 1f0, 1f0)
    mass::Float32 = 1f0
    position::Vec3 = (0f0, 0f0, 0f0)
    rotation::Vec3 = (0f0, 0f0, 0f0)   # degrees
    velocity::Vec3 = (0f0, 0f0, 0f0)
    spin::Vec3 = (0f0, 0f0, 0f0)
    friction::Float32 = 0.5f0
    restitution::Float32 = 0f0
    rolling_friction::Float32 = 0f0
    damping::NTuple{2,Float32} = (0f0, 0f0)
    color::NTuple{3,UInt8} = PALETTE[1]
end

# Optional [camera] table, used by the viewer. `nothing` fields are fitted to
# the scene's bounds.
Base.@kwdef struct CameraSpec
    target::Union{Nothing,Vec3} = nothing
    distance::Union{Nothing,Float32} = nothing
    yaw::Float32 = 35f0           # degrees about Y, 0 = looking along -Z
    pitch::Float32 = 25f0         # degrees above the horizon
    orbit::Bool = true            # turn slowly on its own
end

struct SceneSpec
    name::String
    world::WorldSpec
    camera::CameraSpec
    objects::Vector{ObjectSpec}
end

Base.show(io::IO, s::SceneSpec) =
    print(io, "SceneSpec(\"", s.name, "\", ", length(s.objects), " objects, ", s.world.hz, " Hz)")

"""
    load_scene(path) -> SceneSpec

Parse and validate a scene file. Errors name the object and the key at fault.
"""
function load_scene(path::AbstractString)
    isfile(path) || error("ObjectSim: scene file not found: $path")
    parse_scene(TOML.parsefile(path); dir = dirname(abspath(path)),
                name = splitext(basename(path))[1])
end

"""
    parse_scene(dict; dir = pwd(), name = "scene") -> SceneSpec

The same as [`load_scene`](@ref) for an already-parsed TOML dictionary. Asset
paths resolve against `dir`.
"""
function parse_scene(d::AbstractDict; dir::AbstractString = pwd(), name::AbstractString = "scene")
    _known(d, ("world", "camera", "object"), "top level")
    w = get(d, "world", Dict{String,Any}())
    _known(w, ("gravity", "hz"), "[world]")
    world = WorldSpec(; gravity = _vec3(get(w, "gravity", [0, -9.81, 0]), "[world] gravity"),
                        hz = Int(get(w, "hz", 120)))
    world.hz > 0 || error("ObjectSim: [world] hz must be positive")
    c = get(d, "camera", Dict{String,Any}())
    _known(c, ("target", "distance", "yaw", "pitch", "orbit"), "[camera]")
    camera = CameraSpec(;
        target = haskey(c, "target") ? _vec3(c["target"], "[camera] target") : nothing,
        distance = haskey(c, "distance") ? Float32(c["distance"]) : nothing,
        yaw = Float32(get(c, "yaw", 35)), pitch = Float32(get(c, "pitch", 25)),
        orbit = Bool(get(c, "orbit", true)))
    objects = ObjectSpec[]
    for (i, o) in enumerate(get(d, "object", Any[]))
        append!(objects, _objects(o, i, dir))
    end
    return SceneSpec(String(name), world, camera, objects)
end

const _OBJECT_KEYS = ("name", "shape", "size", "radius", "height", "asset", "scale", "mass",
                      "position", "rotation", "velocity", "spin", "friction", "restitution",
                      "rolling_friction", "damping", "color", "repeat", "spacing")

function _known(d, keys, where)
    for k in Base.keys(d)
        k in keys || error("ObjectSim: unknown key '$k' in $where (known: $(join(keys, ", ")))")
    end
end

function _vec3(x, what)
    x isa Real && return (Float32(x), Float32(x), Float32(x))
    (x isa AbstractVector && length(x) == 3 && all(e -> e isa Real, x)) ||
        error("ObjectSim: $what must be 3 numbers, got $(repr(x))")
    return (Float32(x[1]), Float32(x[2]), Float32(x[3]))
end

function _color(x, i, what)
    x === nothing && return PALETTE[mod1(i, length(PALETTE))]
    if x isa AbstractString
        m = match(r"^#?([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$", x)
        m === nothing && error("ObjectSim: $what color must be \"#rrggbb\", got $(repr(x))")
        return Tuple(parse(UInt8, c; base = 16) for c in m.captures)
    end
    c = _vec3(x, "$what color")
    all(v -> 0 <= v <= 255, c) || error("ObjectSim: $what color components must be 0-255")
    return UInt8.(round.(Int, c))
end

# One [[object]] table → one spec, or several when it has `repeat`.
function _objects(o, i, dir)
    o isa AbstractDict || error("ObjectSim: [[object]] #$i is not a table")
    name = String(get(o, "name", "object$i"))
    what = "object '$name'"
    _known(o, _OBJECT_KEYS, what)
    haskey(o, "shape") || error("ObjectSim: $what has no shape (one of $(join(SHAPES, ", ")))")
    shape = Symbol(o["shape"])
    shape in SHAPES || error("ObjectSim: $what has unknown shape '$shape' (one of $(join(SHAPES, ", ")))")

    num(k, default) = (v = get(o, k, default); v isa Real ? Float32(v) :
                       error("ObjectSim: $what $k must be a number, got $(repr(v))"))
    radius = num("radius", 0.5); height = num("height", 1.0); mass = num("mass", 1.0)
    size = _vec3(get(o, "size", [1, 1, 1]), "$what size")

    asset = ""
    if shape in (:hull, :mesh)
        haskey(o, "asset") || error("ObjectSim: $what (shape = \"$shape\") needs an asset file")
        asset = normpath(joinpath(dir, String(o["asset"])))
        isfile(asset) || error("ObjectSim: $what asset not found: $asset")
    end
    shape == :mesh && mass != 0 && haskey(o, "mass") &&
        error("ObjectSim: $what: a triangle mesh is static only (mass = 0); use shape = \"hull\" for a moving object")
    shape == :mesh && (mass = 0f0)
    mass >= 0 || error("ObjectSim: $what mass must be ≥ 0")
    radius > 0 || error("ObjectSim: $what radius must be > 0")
    height > 0 || error("ObjectSim: $what height must be > 0")
    all(>(0), size) || error("ObjectSim: $what size must be positive")
    shape == :capsule && height < 2radius &&
        error("ObjectSim: $what: capsule height (tip to tip) must be ≥ 2·radius")

    damping = get(o, "damping", [0, 0])
    (damping isa AbstractVector && length(damping) == 2) ||
        error("ObjectSim: $what damping must be [linear, angular]")

    base = ObjectSpec(; name, shape, size, radius, height, asset, mass,
        scale = _vec3(get(o, "scale", 1.0), "$what scale"),
        position = _vec3(get(o, "position", [0, 0, 0]), "$what position"),
        rotation = _vec3(get(o, "rotation", [0, 0, 0]), "$what rotation"),
        velocity = _vec3(get(o, "velocity", [0, 0, 0]), "$what velocity"),
        spin = _vec3(get(o, "spin", [0, 0, 0]), "$what spin"),
        friction = num("friction", 0.5), restitution = num("restitution", 0.0),
        rolling_friction = num("rolling_friction", 0.0),
        damping = (Float32(damping[1]), Float32(damping[2])),
        color = _color(get(o, "color", nothing), i, what))

    rep = get(o, "repeat", nothing)
    rep === nothing && return [base]
    (rep isa AbstractVector && length(rep) == 3 && all(r -> r isa Integer && r >= 1, rep)) ||
        error("ObjectSim: $what repeat must be 3 positive integers")
    spacing = _vec3(get(o, "spacing", collect(_extent(base))), "$what spacing")
    out = ObjectSpec[]
    for ix in 0:rep[1] - 1, iy in 0:rep[2] - 1, iz in 0:rep[3] - 1
        p = vadd(base.position, vmul(spacing, Float32.((ix, iy, iz))))
        push!(out, _with(base; name = "$(name)[$(length(out) + 1)]", position = p))
    end
    return out
end

# Rough full extents, for the default repeat spacing.
function _extent(s::ObjectSpec)
    s.shape == :box && return s.size
    s.shape == :sphere && return v3(2s.radius, 2s.radius, 2s.radius)
    s.shape in (:capsule, :cylinder, :cone) && return v3(2s.radius, s.height, 2s.radius)
    lo, hi = aabb(transform_mesh(load_mesh(s.asset); scale = s.scale))
    return vsub(hi, lo)
end
