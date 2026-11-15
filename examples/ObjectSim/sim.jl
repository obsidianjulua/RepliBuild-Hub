#!/usr/bin/env julia
# Run an ObjectSim scene from the command line.
#
#   julia --project=examples/ObjectSim examples/ObjectSim/sim.jl SCENE [options]
#
#   (no options)          open a window and run in real time
#   --headless            no window: simulate and print progress
#   --seconds S           headless: how long to simulate (default 5)
#   --verbose             headless: print every body's final position
#   --frames N            window: run N frames (deterministic stepping), then close
#   --screenshot FILE     window: save the last frame as PNG (needs --frames)
#   --presim S            window: simulate S seconds before the first frame
#   --size WxH            window size (default 1280x720)

using ObjectSim

function main(args)
    isempty(args) && (println(stderr, "usage: sim.jl SCENE [--headless] [--seconds S] [--frames N] ",
                              "[--screenshot FILE] [--presim S] [--size WxH] [--verbose]"); exit(2))
    scene = args[1]
    opts = Dict{String,String}(); flags = Set{String}()
    i = 2
    while i <= length(args)
        a = args[i]
        if a in ("--headless", "--verbose")
            push!(flags, a); i += 1
        elseif a in ("--seconds", "--frames", "--screenshot", "--presim", "--size") && i < length(args)
            opts[a] = args[i + 1]; i += 2
        else
            println(stderr, "sim.jl: unknown or incomplete option '$a'"); exit(2)
        end
    end
    if "--headless" in flags
        run_headless(scene; seconds = parse(Float64, get(opts, "--seconds", "5")),
                     verbose = "--verbose" in flags)
    else
        w, h = parse.(Int, split(get(opts, "--size", "1280x720"), 'x'))
        run_window(scene; width = w, height = h,
             frames = parse(Int, get(opts, "--frames", "0")),
             screenshot = get(opts, "--screenshot", ""),
             presim = parse(Float64, get(opts, "--presim", "0")))
    end
end

main(ARGS)
