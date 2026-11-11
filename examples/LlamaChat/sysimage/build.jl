# Build LlamaChat.so: LlamaChat, its wrappers and the GUI in one sysimage.
#
#   DISPLAY=:1 julia -t 4 examples/LlamaChat/sysimage/build.jl
#
# PackageCompiler comes from your default environment (@v1.13), stacked under
# the project. The workload opens a hidden window, so it needs $DISPLAY.
#
# The image is a snapshot: Julia runs the LlamaChat inside it and ignores
# src/. Rebuild after changing LlamaChat; `llamagui` skips an image older than
# the sources rather than run stale code.

using PackageCompiler

proj = dirname(@__DIR__)
out  = joinpath(proj, "LlamaChat.so")
t0 = time()
create_sysimage([:LlamaChat]; sysimage_path = out, project = proj,
                script = joinpath(@__DIR__, "workload.jl"))
println("=== sysimage written: $out  ($(round(Int, filesize(out) / 1_000_000)) MB, ",
        "$(round((time() - t0) / 60; digits = 1)) min)")
