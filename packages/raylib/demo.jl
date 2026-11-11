#!/usr/bin/env julia
# raylib Hub package — a tiny playable 2D game, straight through the wrapper.
#
# Catch the falling blocks with the paddle (← / →). Miss three and it's over;
# SPACE restarts, ESC quits. Everything here is a raw raylib call — no Julia
# game layer — so it doubles as a smoke test of the input/draw/timing loop.
#
# Usage:  julia --project=/path/to/RepliBuild.jl packages/raylib/demo.jl

const WRAPPER = joinpath(@__DIR__, "julia", "Raylib.jl")
isfile(WRAPPER) || error("Build the wrapper first: julia --project=… packages/raylib/test_deep.jl")
haskey(ENV, "DISPLAY") || (ENV["DISPLAY"] = ":1")   # X11-only build
include(WRAPPER)
const R = Raylib

rgba(r, g, b, a=255) = R.Color(UInt8(r), UInt8(g), UInt8(b), UInt8(a))
const BG, FG, PADDLE, BLOCK = rgba(24, 24, 32), rgba(235, 235, 235), rgba(0, 158, 47), rgba(230, 41, 55)
const KEY_SPACE, KEY_RIGHT, KEY_LEFT = Cint(32), Cint(262), Cint(263)   # raylib.h KeyboardKey

const W, H = 640, 400
mutable struct Block; x::Float32; y::Float32; v::Float32; end

function main()
    R.InitWindow(Cint(W), Cint(H), "RepliBuild × raylib — catch")
    R.SetTargetFPS(Cint(60))

    px = Float32(W / 2); pw = 90f0
    blocks = Block[]; spawn = 0f0
    score = 0; misses = 0

    while !R.WindowShouldClose()
        dt = R.GetFrameTime()

        if misses < 3
            R.IsKeyDown(KEY_LEFT)  && (px -= 420f0 * dt)
            R.IsKeyDown(KEY_RIGHT) && (px += 420f0 * dt)
            px = clamp(px, pw / 2, W - pw / 2)

            spawn -= dt
            if spawn <= 0
                push!(blocks, Block(R.GetRandomValue(Cint(10), Cint(W - 30)), -20f0,
                                    140f0 + 6f0 * score))
                spawn = max(0.25f0, 0.9f0 - 0.02f0 * score)
            end

            paddle = R.Rectangle(px - pw / 2, H - 30f0, pw, 12f0)
            for b in blocks
                b.y += b.v * dt
            end
            caught = filter(b -> R.CheckCollisionRecs(R.Rectangle(b.x, b.y, 20f0, 20f0), paddle), blocks)
            missed = filter(b -> b.y > H, blocks)
            score += length(caught); misses += length(missed)
            filter!(b -> !(b in caught) && !(b in missed), blocks)
        elseif R.IsKeyPressed(KEY_SPACE)
            empty!(blocks); score = 0; misses = 0
        end

        R.BeginDrawing()
        R.ClearBackground(BG)
        for b in blocks
            R.DrawRectangle(Cint(round(b.x)), Cint(round(b.y)), Cint(20), Cint(20), BLOCK)
        end
        R.DrawRectangle(Cint(round(px - pw / 2)), Cint(H - 30), Cint(pw), Cint(12), PADDLE)
        R.DrawText("score $score   misses $misses/3", Cint(12), Cint(10), Cint(20), FG)
        if misses >= 3
            msg = "GAME OVER - SPACE to restart"
            R.DrawText(msg, Cint((W - R.MeasureText(msg, Cint(30))) ÷ 2), Cint(H ÷ 2 - 15), Cint(30), FG)
        end
        R.DrawFPS(Cint(W - 90), Cint(10))
        R.EndDrawing()
    end
    R.CloseWindow()
end

main()
