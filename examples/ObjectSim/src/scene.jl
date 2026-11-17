# Scene files: TOML → ObjectSpec list. Pure Julia; nothing is created here.
#
#   [world]
#   gravity = [0, -9.81, 0]     # m/s²
#   hz      = 120               # fixed physics steps per simulated second
#   iterations = 10             # solver passes per step; more = stiffer joints and stacks
#   mutual_gravity = 0          # G: every object attracts every other (0 = off)
#   backend  = "jolt"           # physics engine: "bullet3" or "jolt" (src/backends/);
#                               # default: ObjectSim.DEFAULT_BACKEND[] (\$OBJECTSIM_BACKEND)
#
#   [water]                     # optional: a sea that things float in
#   level    = 0.0              # height of the surface (m)
#   density  = 1000             # kg/m³; an object denser than this sinks
#   drag     = 1.0              # how thick it is to move through
#   color    = "#2a6f97"
#   clarity  = 0.55             # 0 = clear, 1 = opaque surface
#
#   [lighting]                  # optional
#   sun      = 1.0              # main light strength (it casts the shadows); low for night
#   ambient  = 1.0              # sky light strength
#   sky      = "#1b1d23"        # background colour
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
#   sleep    = true             # false: never put to sleep (see README: a slow
#                               # pendulum otherwise freezes mid-swing)
#   gravity  = [0, 2, 0]        # this object's own gravity (m/s²), whatever the world's
#   layer    = "debris"         # collision layer name …
#   ignore   = ["debris"]       # … and layers it passes through
#   trigger  = false            # true: nothing bounces off it; contacts are still reported
#   glow     = 0.0              # 0-1: self-lit; at 1 it shines and blooms (lava, lamps, stars)
#   light    = 0.0              # > 0: a point light of its colour, reaching this far (m)
#   light_intensity = 1.5       # how bright that light is at the lamp
#   gravity_mass = 1000         # with [world] mutual_gravity: the mass that attracts
#                               # (default: mass; lets a static body pull)
#   swirl    = [0, 0.5, 0]      # with repeat: each copy moves at swirl × (its offset
#                               # from the group's centre), a spinning cloud
#   color    = "#d94f3d"        # or [r, g, b] 0-255
#   repeat   = [1, 1, 1]        # a grid of copies along x, y, z …
#   spacing  = [1, 1, 1]        # … this far apart on each axis (default: the object's size)
#   repeat   = 10               # or copies in a line, each one …
#   step     = [0.5, -0.4, 0]   # … this far on from the last (any direction)
#
#   [[joint]]                   # see src/joints.jl for what each type does
#   type     = "hinge"          # point | hinge | slider | fixed | spring
#   a        = "door"           # body names; copies from `repeat` are name[1], name[2] …
#   b        = "frame"          # omit to attach `a` to the world
#   pivot    = [0, 1, 0]        # the shared point, world coordinates at the start
#   axis     = [0, 1, 0]        # hinge: turning axis; slider: sliding axis
#   limit    = [-90, 90]        # hinge: degrees; slider: metres along the axis
#   motor    = [90, 20]         # hinge: [deg/s, max impulse]; slider: [m/s, max force]
#   break_impulse = 40          # snaps when the joint has to push harder than this
#   collide  = false            # whether the two joined bodies still collide
#   stiffness = 100             # spring: N/m on each axis …
#   damping  = 2                # … and how quickly it stops bouncing
#
#   [[joint]]                   # or a whole chain at once:
#   type     = "point"
#   chain    = "link"           # joins link[1]–link[2]–… at the midpoints
#   ends     = "first"          # also pin the first / last / both ends to the world

const SHAPES = (:box, :sphere, :capsule, :cylinder, :cone, :hull, :mesh)

const PALETTE = (
    (0xd9, 0x4f, 0x3d), (0x3d, 0x8b, 0xd9), (0xe8, 0xb3, 0x3a), (0x4f, 0xb0, 0x6a),
    (0x9a, 0x6f, 0xd6), (0xe0, 0x7b, 0x39), (0x38, 0xb2, 0xac), (0xc9, 0x5f, 0x9b),
)

Base.@kwdef struct WaterSpec
    level::Float32 = 0f0
    density::Float32 = 1000f0          # kg/m³
    drag::Float32 = 1f0
    color::NTuple{3,UInt8} = (0x2a, 0x6f, 0x97)
    clarity::Float32 = 0.55f0
end

Base.@kwdef struct WorldSpec
    gravity::Vec3 = (0f0, -9.81f0, 0f0)
    hz::Int = 120
    iterations::Int = 10               # bullet3's default
    mutual_gravity::Float64 = 0.0      # G between objects; 0 = off
    water::Union{Nothing,WaterSpec} = nothing
    backend::String = ""               # "" = DEFAULT_BACKEND[]
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
    sleep::Bool = true
    gravity::Union{Nothing,Vec3} = nothing
    layer::String = ""
    ignore::Vector{String} = String[]
    trigger::Bool = false
    glow::Float32 = 0f0
    light::Float32 = 0f0
    light_intensity::Float32 = 1.5f0
    gravity_mass::Union{Nothing,Float32} = nothing
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
    follow::String = ""           # keep this object in the middle (and select it)
    # [lighting], kept here with the other viewing settings
    sun::Float32 = 1f0            # strength of the main (shadow-casting) light
    ambient::Float32 = 1f0        # strength of the sky / ambient light
    sky::NTuple{3,UInt8} = (0x1b, 0x1d, 0x23)
end

Base.@kwdef struct JointSpec
    name::String
    kind::Symbol
    a::String
    b::String = ""                     # "" = the world
    pivot::Vec3
    axis::Vec3 = (0f0, 0f0, 1f0)
    limit::Union{Nothing,NTuple{2,Float32}} = nothing
    motor::Union{Nothing,NTuple{2,Float32}} = nothing
    break_impulse::Float32 = Inf32
    collide::Bool = false
    stiffness::Float32 = 100f0
    damping::Float32 = 2f0
end

struct SceneSpec
    name::String
    world::WorldSpec
    camera::CameraSpec
    objects::Vector{ObjectSpec}
    joints::Vector{JointSpec}
end
SceneSpec(name, world, camera, objects) = SceneSpec(name, world, camera, objects, JointSpec[])

Base.show(io::IO, s::SceneSpec) =
    print(io, "SceneSpec(\"", s.name, "\", ", length(s.objects), " objects, ",
          length(s.joints), " joints, ", s.world.hz, " Hz)")

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
    _known(d, ("world", "camera", "lighting", "water", "object", "joint"), "top level")
    w = get(d, "world", Dict{String,Any}())
    _known(w, ("gravity", "hz", "iterations", "mutual_gravity", "backend"), "[world]")
    world = WorldSpec(; gravity = _vec3(get(w, "gravity", [0, -9.81, 0]), "[world] gravity"),
                        hz = Int(get(w, "hz", 120)), iterations = Int(get(w, "iterations", 10)),
                        mutual_gravity = Float64(get(w, "mutual_gravity", 0.0)),
                        water = haskey(d, "water") ? _water(d["water"]) : nothing,
                        backend = String(get(w, "backend", "")))
    isempty(world.backend) || world.backend in BACKENDS || error("ObjectSim: [world] backend must be one of $(join(BACKENDS, ", "))")
    world.mutual_gravity >= 0 || error("ObjectSim: [world] mutual_gravity must be ≥ 0")
    world.hz > 0 || error("ObjectSim: [world] hz must be positive")
    1 <= world.iterations <= 1000 || error("ObjectSim: [world] iterations must be 1-1000")
    c = get(d, "camera", Dict{String,Any}())
    _known(c, ("target", "distance", "yaw", "pitch", "orbit", "follow"), "[camera]")
    lt = get(d, "lighting", Dict{String,Any}())
    _known(lt, ("sun", "ambient", "sky"), "[lighting]")
    camera = CameraSpec(;
        target = haskey(c, "target") ? _vec3(c["target"], "[camera] target") : nothing,
        distance = haskey(c, "distance") ? Float32(c["distance"]) : nothing,
        yaw = Float32(get(c, "yaw", 35)), pitch = Float32(get(c, "pitch", 25)),
        orbit = Bool(get(c, "orbit", true)), follow = String(get(c, "follow", "")),
        sun = Float32(get(lt, "sun", 1.0)), ambient = Float32(get(lt, "ambient", 1.0)),
        sky = haskey(lt, "sky") ? _color(lt["sky"], 0, "[lighting] sky") : (0x1b, 0x1d, 0x23))
    objects = ObjectSpec[]
    for (i, o) in enumerate(get(d, "object", Any[]))
        append!(objects, _objects(o, i, dir))
    end
    dup = [n for n in unique(o.name for o in objects) if count(o -> o.name == n, objects) > 1]
    isempty(dup) || error("ObjectSim: two objects share a name: $(join(dup, ", "))")
    joints = JointSpec[]
    for (i, j) in enumerate(get(d, "joint", Any[]))
        append!(joints, _joints(j, i, objects))
    end
    return SceneSpec(String(name), world, camera, objects, joints)
end

const _OBJECT_KEYS = ("name", "shape", "size", "radius", "height", "asset", "scale", "mass",
                      "position", "rotation", "velocity", "spin", "friction", "restitution",
                      "rolling_friction", "damping", "sleep", "color", "repeat", "spacing", "step",
                      "gravity", "layer", "ignore", "trigger", "gravity_mass", "swirl", "glow",
                      "light", "light_intensity")

function _water(x)
    x isa AbstractDict || error("ObjectSim: [water] must be a table")
    _known(x, ("level", "density", "drag", "color", "clarity"), "[water]")
    wt = WaterSpec(; level = Float32(get(x, "level", 0)), density = Float32(get(x, "density", 1000)),
                   drag = Float32(get(x, "drag", 1)), clarity = Float32(get(x, "clarity", 0.55)),
                   color = haskey(x, "color") ? _color(x["color"], 0, "[water] color") : (0x2a, 0x6f, 0x97))
    wt.density > 0 || error("ObjectSim: [water] density must be positive")
    wt.drag >= 0 || error("ObjectSim: [water] drag must be ≥ 0")
    0 <= wt.clarity <= 1 || error("ObjectSim: [water] clarity must be 0-1")
    return wt
end

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
        sleep = (v = get(o, "sleep", true); v isa Bool ? v : error("ObjectSim: $what sleep must be true or false")),
        gravity = haskey(o, "gravity") ? _vec3(o["gravity"], "$what gravity") : nothing,
        layer = String(get(o, "layer", "")),
        ignore = (v = get(o, "ignore", String[]); v isa AbstractVector ? String.(v) : error("ObjectSim: $what ignore must be a list of layer names")),
        trigger = (v = get(o, "trigger", false); v isa Bool ? v : error("ObjectSim: $what trigger must be true or false")),
        gravity_mass = haskey(o, "gravity_mass") ? num("gravity_mass", 0) : nothing,
        glow = clamp(num("glow", 0), 0f0, 1f0),
        light = max(num("light", 0), 0f0),
        light_intensity = max(num("light_intensity", 1.5), 0f0),
        color = _color(get(o, "color", nothing), i, what))

    rep = get(o, "repeat", nothing)
    if rep === nothing
        (haskey(o, "spacing") || haskey(o, "step") || haskey(o, "swirl")) &&
            error("ObjectSim: $what has spacing/step/swirl but no repeat")
        return [base]
    end
    out = _repeat(o, base, name, what, rep)
    if haskey(o, "swirl")                # a spinning cloud: v = base + ω × (p − centre)
        ω = _vec3(o["swirl"], "$what swirl")
        c = vscale(reduce(vadd, (s.position for s in out)), 1f0 / length(out))
        out = [_with(s; velocity = vadd(s.velocity, vcross(ω, vsub(s.position, c)))) for s in out]
    end
    return out
end

function _repeat(o, base, name, what, rep)
    out = ObjectSpec[]
    if rep isa Integer                 # a line: copy i sits at position + (i - 1) · step
        rep >= 1 || error("ObjectSim: $what repeat must be ≥ 1")
        haskey(o, "spacing") && error("ObjectSim: $what: `repeat = n` goes with step, not spacing")
        haskey(o, "step") || error("ObjectSim: $what: `repeat = n` needs step = [dx, dy, dz]")
        step = _vec3(o["step"], "$what step")
        for k in 0:rep - 1
            push!(out, _with(base; name = "$(name)[$(k + 1)]", position = vadd(base.position, vscale(step, Float32(k)))))
        end
        return out
    end
    (rep isa AbstractVector && length(rep) == 3 && all(r -> r isa Integer && r >= 1, rep)) ||
        error("ObjectSim: $what repeat must be n (with step) or [nx, ny, nz] (with spacing)")
    haskey(o, "step") && error("ObjectSim: $what: `repeat = [nx, ny, nz]` goes with spacing, not step")
    spacing = _vec3(get(o, "spacing", collect(_extent(base))), "$what spacing")
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

const _JOINT_KEYS = ("name", "type", "a", "b", "pivot", "axis", "limit", "motor", "break_impulse",
                     "collide", "stiffness", "damping", "chain", "ends")
const JOINT_TYPES = (:point, :hinge, :slider, :fixed, :spring)

# One [[joint]] table → one JointSpec, or one per link for `chain`.
function _joints(j, i, objects)
    j isa AbstractDict || error("ObjectSim: [[joint]] #$i is not a table")
    name = String(get(j, "name", "joint$i"))
    what = "joint '$name'"
    _known(j, _JOINT_KEYS, what)
    kind = Symbol(get(j, "type", ""))
    kind in JOINT_TYPES || error("ObjectSim: $what type must be one of $(join(JOINT_TYPES, ", "))")
    pos = Dict(o.name => o.position for o in objects)
    pair(k) = haskey(j, k) ? (v = j[k]; (v isa AbstractVector && length(v) == 2 && all(x -> x isa Real, v)) ?
        (Float32(v[1]), Float32(v[2])) : error("ObjectSim: $what $k must be two numbers")) : nothing
    num(k, d) = (v = get(j, k, d); v isa Real ? Float32(v) : error("ObjectSim: $what $k must be a number"))
    common = (; kind,
        axis = vunit(_vec3(get(j, "axis", [0, 0, 1]), "$what axis")),
        limit = pair("limit"), motor = pair("motor"),
        break_impulse = num("break_impulse", Inf), collide = Bool(get(j, "collide", false)),
        stiffness = num("stiffness", 100), damping = num("damping", 2))
    kind in (:point, :fixed, :spring) && common.motor !== nothing &&
        error("ObjectSim: $what: only hinges and sliders have motors")
    kind in (:hinge, :slider) && !haskey(j, "axis") && error("ObjectSim: $what needs an axis")
    known(n) = haskey(pos, n) || error("ObjectSim: $what refers to '$n', which is not an object in the scene")

    if haskey(j, "chain")
        for k in ("a", "b", "pivot")
            haskey(j, k) && error("ObjectSim: $what: give either chain or a/b/pivot, not both")
        end
        base = String(j["chain"])
        links = String[]
        while haskey(pos, "$base[$(length(links) + 1)]")
            push!(links, "$base[$(length(links) + 1)]")
        end
        length(links) >= 1 || error("ObjectSim: $what: no objects named $base[1], $base[2] … (use repeat)")
        ends = Symbol(get(j, "ends", "none"))
        ends in (:none, :first, :last, :both) || error("ObjectSim: $what ends must be none, first, last or both")
        out = JointSpec[]
        step = length(links) >= 2 ? vsub(pos[links[2]], pos[links[1]]) : (0f0, 1f0, 0f0)
        if ends in (:first, :both)
            push!(out, JointSpec(; name = "$name[start]", a = links[1],
                                 pivot = vsub(pos[links[1]], vscale(step, 0.5f0)), common...))
        end
        for k in 1:length(links) - 1
            mid = vscale(vadd(pos[links[k]], pos[links[k + 1]]), 0.5f0)
            push!(out, JointSpec(; name = "$name[$k]", a = links[k], b = links[k + 1], pivot = mid, common...))
        end
        if ends in (:last, :both)
            n = length(links)
            last_step = n >= 2 ? vsub(pos[links[n]], pos[links[n - 1]]) : step
            push!(out, JointSpec(; name = "$name[end]", a = links[n],
                                 pivot = vadd(pos[links[n]], vscale(last_step, 0.5f0)), common...))
        end
        return out
    end

    haskey(j, "a") || error("ObjectSim: $what needs a (a body name) or chain")
    haskey(j, "pivot") || error("ObjectSim: $what needs a pivot (world coordinates)")
    a = String(j["a"]); b = String(get(j, "b", ""))
    known(a); isempty(b) || known(b)
    kind == :fixed && isempty(b) && error("ObjectSim: $what: a fixed joint joins two bodies (to fix one in place, give it mass = 0)")
    return [JointSpec(; name, a, b, pivot = _vec3(j["pivot"], "$what pivot"), common...)]
end
