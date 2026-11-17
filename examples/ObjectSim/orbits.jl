#!/usr/bin/env julia
# Run an orbit scene from the command line.
#
#   julia --project=examples/ObjectSim examples/ObjectSim/orbits.jl SCENE [options]
#
#   (no options)          open a window
#   --headless            no window: integrate and print energy drift
#   --days D              headless: how long (default: one year, or 20 time units)
#   --frames N            window: run N frames at a fixed rate, then close
#   --screenshot FILE     window: save the last frame (needs --frames)
#   --presim D            integrate D days (time units) before the first frame
#   --size WxH            window size (default 1280x760)
#   --record FILE         window: encode every frame to FILE (mp4, via ffmpeg) at a fixed
#                         1/60 s per frame; stop with --frames N or ESC

using ObjectSim

function main(args)
    isempty(args) && (println(stderr, "usage: orbits.jl SCENE [--headless] [--days D] [--frames N] ",
                              "[--screenshot FILE] [--presim D] [--size WxH]"); exit(2))
    scene = args[1]
    opts = Dict{String,String}(); flags = Set{String}()
    i = 2
    while i <= length(args)
        a = args[i]
        if a == "--headless"
            push!(flags, a); i += 1
        elseif a in ("--days", "--frames", "--screenshot", "--presim", "--size", "--record") && i < length(args)
            opts[a] = args[i + 1]; i += 2
        else
            println(stderr, "orbits.jl: unknown or incomplete option '$a'"); exit(2)
        end
    end
    sys = load_orbits(scene)
    if "--headless" in flags
        days = parse(Float64, get(opts, "--days", sys.units == :solar ? "365.25" : "20"))
        run_orbits(sys; days, every = days / 10)
    else
        w, h = parse.(Int, split(get(opts, "--size", "1280x760"), 'x'))
        run_orbits_window(sys; width = w, height = h,
                          frames = parse(Int, get(opts, "--frames", "0")),
                          screenshot = get(opts, "--screenshot", ""),
                          presim = parse(Float64, get(opts, "--presim", "0")),
                          record = get(opts, "--record", ""))
    end
end

main(ARGS)
