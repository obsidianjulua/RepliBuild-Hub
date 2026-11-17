# The app: open a scene by name, and follow the menu from scene to scene.

"""
    find_scene(name) -> path

A scene by file path, or by name: `"night"` finds `scenes/night.toml`,
`"solar_system"` finds `scenes/orbits/solar_system.toml`.
"""
function find_scene(name::AbstractString)
    isfile(name) && return abspath(name)
    base = endswith(name, ".toml") ? name : name * ".toml"
    for d in (_SCENES, joinpath(_SCENES, "orbits"))
        p = joinpath(d, base)
        isfile(p) && return p
    end
    phys, orbs = _scene_files()
    names = join(sort([splitext(basename(f))[1] for f in vcat(phys, orbs)]), ", ")
    error("ObjectSim: no scene '$name'. Scenes: $names")
end

"""Whether a scene file is an orbit scene (it has [[body]] tables) or a physics one."""
is_orbit_scene(path::AbstractString) = haskey(TOML.parsefile(path), "body")

"""
    app(scene = "playground"; kwargs...)
    app(args::Vector{String})

Open ObjectSim on a scene (a name or a path) in the right window, physics or
orbits, and keep going as scenes are picked from the menu, until the window
is closed or Quit is chosen. `args` is the command line: the first argument
is the scene; `--record` records the first window to recordings/<scene>.mp4
(`--record=FILE`: to FILE). This is what the `objectsim` command runs.
"""
function app(scene::AbstractString = "playground"; kwargs...)
    path = find_scene(scene)
    while path !== nothing
        @info "ObjectSim: opening $(splitext(basename(path))[1])"
        path = is_orbit_scene(path) ? run_orbits_window(path; app = true, kwargs...) :
                                      run_window(path; kwargs...)
    end
    return nothing
end
function app(args::Vector{String})
    scene = "playground"; record = nothing
    for a in args
        if a == "--record"                  # recordings/<scene>.mp4
            record = ""
        elseif startswith(a, "--record=")
            record = abspath(a[length("--record=") + 1:end])
        else
            scene = a
        end
    end
    record == "" && (record = joinpath(dirname(_SCENES), "recordings", splitext(basename(scene))[1] * ".mp4"))
    return record === nothing ? app(scene) : app(scene; record)
end
