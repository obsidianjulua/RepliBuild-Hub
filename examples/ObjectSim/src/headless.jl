# Running a scene with no window: step it and report what the bodies did.

"""
    run_headless(scene; seconds = 5, every = 1, io = stdout, verbose = false)
        -> Vector{NamedTuple}

Simulate `seconds` of the scene and return the final [`snapshot`](@ref).
Every `every` simulated seconds a line goes to `io`: time, how many bodies
are still awake, and the fastest one. With `verbose`, the final position of
every moving body is printed too.
"""
function run_headless(scene; seconds::Real = 5, every::Real = 1, io::IO = stdout,
                      verbose::Bool = false)
    spec = scene isa SceneSpec ? scene : load_scene(scene)
    with_world(spec) do w
        moving = filter(!isstatic, w.bodies)
        println(io, "$(spec.name): $(length(moving)) moving, $(length(w.bodies) - length(moving)) static, ",
                "$(spec.world.hz) Hz, $(seconds) s")
        chunk = max(1, round(Int, every / w.dt))
        total = round(Int, seconds / w.dt)
        t0 = time_ns()
        while w.steps < total
            step!(w, min(chunk, total - w.steps))
            awake = count(b -> !sleeping(b), moving)
            fastest, who = isempty(moving) ? (0f0, "-") :
                findmax(b -> vnorm(velocity(b)), moving) |> r -> (r[1], moving[r[2]].name)
            println(io, "  t = ", lpad(string(round(sim_time(w); digits = 2)), 6), " s   ",
                    lpad(awake, 4), " awake   fastest ", round(fastest; digits = 3), " m/s (", who, ")")
        end
        wall = (time_ns() - t0) / 1e9
        println(io, "  $(w.steps) steps in $(round(wall; digits = 3)) s wall ",
                "($(round(sim_time(w) / max(wall, 1e-9); digits = 1))× real time)")
        snap = snapshot(w)
        if verbose
            for s in snap
                p = round.(s.position; digits = 3)
                println(io, "    ", rpad(s.name, 18), " at ", p, s.sleeping ? "  (asleep)" : "")
            end
        end
        return snap
    end
end
