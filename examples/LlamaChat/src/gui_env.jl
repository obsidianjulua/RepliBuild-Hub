# The window as a small working environment. Included by gui.jl, inside
# `module GUI`. Three things that are not chat:
#
#   * places — the folders a terminal starts in, and jumps to;
#   * notes  — text you keep, that every model reads when it loads;
#   * stats  — the GPU, the machine and the model, sampled once a second from
#     /sys and /proc. No tool is run and no library is asked, except for VRAM,
#     which is ggml's own figure (the one the planner budgets with).

config_dir() = joinpath(get(ENV, "XDG_CONFIG_HOME", joinpath(homedir(), ".config")), "llamachat")

# ── places ───────────────────────────────────────────────────────────────────

"""A folder with a short name: where a terminal starts, and where Go takes one."""
struct Place
    name::String
    dir::String
end

places_file() = joinpath(config_dir(), "places")

"""
The places when `places_file()` does not exist, in order: RepliBuild (the
checkout this LlamaChat builds against), the Hub this file is in, and the
folder that holds the Hub.
"""
function default_places()
    hub = normpath(joinpath(@__DIR__, "..", "..", ".."))
    projects = dirname(rstrip(hub, '/'))
    rb = try pkgdir(LC.RepliBuild) catch; nothing end
    rb === nothing && (rb = joinpath(projects, "RepliBuild.jl"))
    return [Place("RepliBuild", rstrip(rb, '/')), Place("Hub", rstrip(hub, '/')), Place("Projects", projects)]
end

"""
    load_places() -> Vector{Place}

`~/.config/llamachat/places`, one `name = /path` a line (`~` expands, `#`
comments), in the order the menus show them; the first is where the first
terminal opens. Without the file, or with nothing usable in it,
`default_places()`. A folder that does not exist is left out.
"""
function load_places(file::AbstractString = places_file())
    out = Place[]
    if isfile(file)
        for l in eachline(file)
            l = strip(first(split(l, '#'; limit = 2)))
            m = match(r"^([^=]+)=(.+)$", l)
            m === nothing && continue
            push!(out, Place(String(strip(m[1])), rstrip(expanduser(String(strip(m[2]))), '/')))
        end
    end
    isempty(out) && (out = default_places())
    filter!(p -> isdir(p.dir), out)
    return out
end

"""What a terminal runs: this Julia on the folder's own project, or your shell."""
julia_cmd() = Cmd([joinpath(Sys.BINDIR, Base.julia_exename()), "--banner=no", "--project=@."])
shell_cmd() = Cmd([get(ENV, "SHELL", "/bin/sh")])

"""`:julia`, `:shell` or `:other`, from the program's name: it decides how Go says `cd`."""
function term_kind(cmd::Cmd)
    exe = basename(first(cmd.exec))
    startswith(exe, "julia") && return :julia
    exe in ("sh", "bash", "zsh", "fish", "dash", "ksh") && return :shell
    return :other
end

"""The line that takes a terminal of this kind to `dir`, as typed."""
function cd_line(kind::Symbol, dir::AbstractString)
    kind === :julia && return "cd($(repr(String(dir))))\r"
    return " cd -- '" * replace(String(dir), "'" => "'\\''") * "'\r"
end

# ── notes ────────────────────────────────────────────────────────────────────

notes_file() = joinpath(config_dir(), "notes.md")
const NOTES_MAX = 64 * 1024

read_notes(file::AbstractString = notes_file()) = isfile(file) ? read(file, String) : ""

function write_notes(text::AbstractString, file::AbstractString = notes_file())
    mkpath(dirname(file))
    write(file, text)
    return file
end

const NOTES_HEADER = "These are the user's standing notes. Use them as background for every reply; " *
                     "do not repeat them back."

"""
    system_with_notes(system, notes) -> String

The system prompt a model is loaded with: the caller's own, then the notes
under a line saying what they are. Notes that are blank add nothing.
"""
function system_with_notes(system::AbstractString, notes::AbstractString)
    n = strip(notes)
    isempty(n) && return String(system)
    body = NOTES_HEADER * "\n\n" * n
    return isempty(strip(system)) ? body : rstrip(String(system)) * "\n\n" * body
end

# ── stats ────────────────────────────────────────────────────────────────────

const HIST = 90                         # samples kept for the sparklines, one a second

_readstr(path) = try strip(read(path, String)) catch; nothing end
_readnum(path) = (s = _readstr(path); s === nothing ? nothing : tryparse(Float64, s))

"""Where the GPU's numbers are in sysfs. Every entry may be `nothing`."""
struct GpuPaths
    name::String
    idle_ms::Union{Nothing,String}      # xe: time the render engine spent idle
    busy_pct::Union{Nothing,String}     # amdgpu: gpu_busy_percent
    energy_uj::Union{Nothing,String}    # cumulative energy, µJ
    power_uw::Union{Nothing,String}     # or instantaneous power, µW
    temp::Union{Nothing,String}         # millidegrees
    temp_vram::Union{Nothing,String}
    fan::Union{Nothing,String}          # rpm
end

_isfile(p) = isfile(p) ? p : nothing

"""
    find_gpu(root = "/sys/class/drm") -> GpuPaths | nothing

The first card with a driver, and what its driver publishes: Intel xe's idle
residency and hwmon (energy, package and VRAM temperature, fan), amdgpu's
busy percent and power. Anything missing is `nothing` and its meter is left out.
"""
function find_gpu(root::AbstractString = "/sys/class/drm")
    isdir(root) || return nothing
    for c in sort!(filter(n -> occursin(r"^card\d+$", n), readdir(root)))
        dev = joinpath(root, c, "device")
        isdir(joinpath(dev, "driver")) || islink(joinpath(dev, "driver")) || continue
        hw = nothing
        hd = joinpath(dev, "hwmon")
        isdir(hd) && !isempty(readdir(hd)) && (hw = joinpath(hd, first(sort!(readdir(hd)))))
        temp = temp_vram = energy = power = fan = nothing
        if hw !== nothing
            labels = Dict{String,String}()
            for f in readdir(hw)
                m = match(r"^(temp\d+)_label$", f)
                m === nothing && continue
                l = _readstr(joinpath(hw, f))
                l === nothing || (labels[l] = joinpath(hw, m[1] * "_input"))
            end
            temp      = something(_isfile(get(labels, "pkg", "")), _isfile(get(labels, "edge", "")),
                                  _isfile(joinpath(hw, "temp1_input")), _isfile(joinpath(hw, "temp2_input")), Some(nothing))
            temp_vram = something(_isfile(get(labels, "vram", "")), _isfile(get(labels, "mem", "")), Some(nothing))
            energy    = _isfile(joinpath(hw, "energy1_input"))
            power     = something(_isfile(joinpath(hw, "power1_average")), _isfile(joinpath(hw, "power1_input")), Some(nothing))
            fan       = _isfile(joinpath(hw, "fan1_input"))
        end
        name = something(_readstr(joinpath(hw === nothing ? dev : hw, "name")), c)
        return GpuPaths(String(name), _isfile(joinpath(dev, "tile0", "gt0", "gtidle", "idle_residency_ms")),
                        _isfile(joinpath(dev, "gpu_busy_percent")), energy, power, temp, temp_vram, fan)
    end
    return nothing
end

"""The CPU's temperature file: k10temp (AMD), coretemp (Intel) or zenpower."""
function find_cpu_temp(root::AbstractString = "/sys/class/hwmon")
    isdir(root) || return nothing
    for h in sort!(readdir(root))
        _readstr(joinpath(root, h, "name")) in ("k10temp", "coretemp", "zenpower") || continue
        f = joinpath(root, h, "temp1_input")
        isfile(f) && return f
    end
    return nothing
end

mutable struct Stats
    gpu::Union{Nothing,GpuPaths}
    cpu_temp_file::Union{Nothing,String}
    t::Float64                          # when the last sample was taken
    # the last sample; NaN = not available
    gpu_busy::Float32                   # 0–1
    gpu_w::Float32
    gpu_temp::Float32
    vram_temp::Float32
    fan::Float32
    vram_used::Float64                  # bytes, every process on the card
    vram_total::Float64
    cpu::Float32                        # 0–1, all cores
    cpu_temp::Float32
    ram_used::Float64
    ram_total::Float64
    tps::Float32                        # tokens through the model in the last second
    # counters the rates are differences of
    idle_prev::Float64
    energy_prev::Float64
    cpu_prev::NTuple{2,Float64}         # (idle, total) jiffies
    toks_prev::Int
    hist_gpu::Vector{Float32}
    hist_tps::Vector{Float32}
end

Stats() = Stats(find_gpu(), find_cpu_temp(), 0.0, NaN32, NaN32, NaN32, NaN32, NaN32, NaN, NaN,
                NaN32, NaN32, NaN, NaN, 0f0, NaN, NaN, (NaN, NaN), -1, Float32[], Float32[])

_f32(x) = x === nothing ? NaN32 : Float32(x)

"""`(idle, total)` jiffies from /proc/stat's first line."""
function cpu_jiffies(text::AbstractString)
    v = tryparse.(Float64, split(first(split(text, '\n')))[2:end])
    (length(v) < 5 || any(isnothing, v)) && return (NaN, NaN)
    return (v[4] + v[5], sum(v[1:min(end, 8)]))          # idle + iowait; guest time is inside user
end

"""`(used, total)` bytes from /proc/meminfo: total less what is available."""
function mem_bytes(text::AbstractString)
    g(k) = (m = match(Regex("^$k:\\s+(\\d+) kB", "m"), text); m === nothing ? NaN : parse(Float64, m[1]) * 1024)
    tot, av = g("MemTotal"), g("MemAvailable")
    return (tot - av, tot)
end

"""Free and total VRAM as ggml's backend reports it; `nothing` before a model has brought it up."""
function vram()
    LC._backend_up[] || return nothing
    L = LC.L
    for i in 0:Int(L.ggml_backend_dev_count()) - 1
        d = L.ggml_backend_dev_get(i)
        L.ggml_backend_dev_type(d) == L.GGML_BACKEND_DEVICE_TYPE_GPU || continue
        free, total = Ref{Csize_t}(0), Ref{Csize_t}(0)
        L.ggml_backend_dev_memory(d, free, total)
        total[] > 0 && return (Float64(free[]), Float64(total[]))
    end
    return nothing
end

_push!(h::Vector{Float32}, x) = (push!(h, isnan(x) ? 0f0 : Float32(x)); length(h) > HIST && popfirst!(h); h)

"""
    sample!(stats, now; tokens = -1) -> stats

Take one sample. Rates (GPU busy, watts, CPU, tok/s) are differences against
the previous sample, so the first one leaves them unset. `tokens` is the
session's token position while a reply is generating, -1 otherwise.
"""
function sample!(s::Stats, now::Float64 = time(); tokens::Integer = -1)
    dt = now - s.t
    first_ = s.t == 0
    s.t = now
    g = s.gpu
    if g !== nothing
        if g.idle_ms !== nothing
            idle = something(_readnum(g.idle_ms), NaN)
            s.gpu_busy = first_ || isnan(s.idle_prev) ? NaN32 :
                         Float32(clamp(1 - (idle - s.idle_prev) / (1000dt), 0, 1))
            s.idle_prev = idle
        elseif g.busy_pct !== nothing
            s.gpu_busy = _f32(_readnum(g.busy_pct)) / 100
        end
        if g.energy_uj !== nothing
            e = something(_readnum(g.energy_uj), NaN)
            s.gpu_w = first_ || isnan(s.energy_prev) || e < s.energy_prev ? NaN32 :
                      Float32((e - s.energy_prev) / 1e6 / dt)
            s.energy_prev = e
        elseif g.power_uw !== nothing
            s.gpu_w = _f32(_readnum(g.power_uw)) / 1f6
        end
        g.temp === nothing      || (s.gpu_temp  = _f32(_readnum(g.temp)) / 1000)
        g.temp_vram === nothing || (s.vram_temp = _f32(_readnum(g.temp_vram)) / 1000)
        g.fan === nothing       || (s.fan       = _f32(_readnum(g.fan)))
    end
    v = vram()
    v === nothing || ((s.vram_used, s.vram_total) = (v[2] - v[1], v[2]))
    st = _readstr("/proc/stat")
    if st !== nothing
        idle, tot = cpu_jiffies(st)
        pi, pt = s.cpu_prev
        s.cpu = isnan(pt) || tot <= pt ? NaN32 : Float32(clamp(1 - (idle - pi) / (tot - pt), 0, 1))
        s.cpu_prev = (idle, tot)
    end
    s.cpu_temp_file === nothing || (s.cpu_temp = _f32(_readnum(s.cpu_temp_file)) / 1000)
    mi = _readstr("/proc/meminfo")
    mi === nothing || ((s.ram_used, s.ram_total) = mem_bytes(mi))
    s.tps = tokens >= 0 && s.toks_prev >= 0 && tokens >= s.toks_prev && !first_ ?
            Float32((tokens - s.toks_prev) / dt) : 0f0
    s.toks_prev = Int(tokens)
    _push!(s.hist_gpu, s.gpu_busy)
    _push!(s.hist_tps, s.tps)
    return s
end

_gib(x) = string(round(x / 2^30; digits = 1))
_deg(x) = isnan(x) ? "" : string(round(Int, x), "°C")

"""
    stats_text(app) -> Vector{Pair{String,String}}

The stats row as words, label => value, in drawing order: what the meters
say, for tests and for anything that cannot look at the window.
"""
function stats_text(app)
    s = app.stats
    out = Pair{String,String}[]
    if s.gpu !== nothing
        parts = String[]
        isnan(s.gpu_busy) || push!(parts, string(round(Int, 100 * s.gpu_busy), "%"))
        isnan(s.gpu_temp) || push!(parts, _deg(s.gpu_temp))
        isnan(s.gpu_w)    || push!(parts, string(round(Int, s.gpu_w), " W"))
        isnan(s.fan)      || push!(parts, string(round(Int, s.fan), " rpm"))
        push!(out, "GPU" => join(parts, "  "))
    end
    isnan(s.vram_total) ||
        push!(out, "VRAM" => "$(_gib(s.vram_used)) / $(_gib(s.vram_total)) GiB" *
                             (isnan(s.vram_temp) ? "" : "  " * _deg(s.vram_temp)))
    push!(out, "model" => model_stat(app))
    isnan(s.cpu) || push!(out, "CPU" => string(round(Int, 100 * s.cpu), "%") *
                                        (isnan(s.cpu_temp) ? "" : "  " * _deg(s.cpu_temp)))
    isnan(s.ram_total) || push!(out, "RAM" => "$(_gib(s.ram_used)) / $(_gib(s.ram_total)) GiB")
    return out
end

"""The model's part of the row: live tok/s while it works, the last reply's when idle."""
function model_stat(app)
    s = app.stats
    app.state === :generating && return string(round(s.tps; digits = 1), " tok/s")
    app.state === :loading && return "loading"
    app.state === :deciding && return "deciding"
    if app.session isa LC.AnyTyped
        o = app.typed_out
        isempty(o) && return "typed  ·  idle"
        return "last $(round(sum(x -> x.latency_ms, o); digits = 1)) ms  ·  $(sum(length, o)) answers"
    end
    r = app.last
    (app.session === nothing || r === nothing) && return app.session === nothing ? "none" : "idle"
    gen = r.t_gen > 0 ? round(r.n_gen / r.t_gen; digits = 1) : 0.0
    return "last $gen tok/s  ·  $(r.n_gen) tok"
end

function meter!(app, key::Symbol, label::String, frac, overlay::String, w::Real)
    G.ImGui_AlignTextToFramePadding()
    colored(() -> text!(label), app.dim)
    G.ImGui_SameLine(0f0, app.fonts.size * 0.35f0)
    f = isnan(frac) ? 0f0 : Float32(clamp(frac, 0, 1))
    G.ImGui_ProgressBar(f, Ref(vec2(w, 0)), overlay)
    rect!(app, key)
end

"""A line graph of `vals` against `top`, one frame-height tall."""
function spark!(app, key::Symbol, vals::Vector{Float32}, top::Real, w::Real)
    p = G.ImGui_GetCursorScreenPos()
    h = G.ImGui_GetFrameHeight()
    dl = G.ImGui_GetWindowDrawList()
    G.ImDrawList_AddRectFilled(dl, Ref(vec2(p.x, p.y)), Ref(vec2(p.x + w, p.y + h)),
                               G.ImGui_GetColorU32(Cint(G.ImGuiCol_FrameBg), 1f0), 0f0, Cint(0))
    n = length(vals)
    if n >= 2 && top > 0
        col = G.ImGui_GetColorU32(Cint(G.ImGuiCol_PlotHistogram), 1f0)
        x(i) = p.x + w * (HIST - n + i - 1) / (HIST - 1)
        y(i) = p.y + h - 1 - (h - 2) * clamp(vals[i] / Float32(top), 0f0, 1f0)
        for i in 2:n
            G.ImDrawList_AddLine(dl, Ref(vec2(x(i - 1), y(i - 1))), Ref(vec2(x(i), y(i))), col, 1.5f0)
        end
    end
    G.ImGui_Dummy(Ref(vec2(w, h)))
    rect!(app, key)
end

"""
The stats row along the bottom of the window: GPU, VRAM, the model, CPU, RAM.
Meters for what has a ceiling, a graph of the last 90 seconds for the two that
move (GPU use and tokens a second).
"""
function stats_bar!(app)
    s = app.stats
    fs = app.fonts.size
    gap() = G.ImGui_SameLine(0f0, fs * 0.9f0)
    near() = G.ImGui_SameLine(0f0, fs * 0.35f0)
    words = Dict(stats_text(app))
    started = false
    next() = (started ? gap() : (started = true); nothing)
    if haskey(words, "GPU")
        next()
        busy = isnan(s.gpu_busy) ? "" : string(round(Int, 100 * s.gpu_busy), "%")
        meter!(app, :stat_gpu, "GPU", s.gpu_busy, busy, fs * 4.5f0)
        near(); spark!(app, :stat_gpu_graph, s.hist_gpu, 1, fs * 5)
        rest = strip(replace(words["GPU"], busy => ""; count = 1))
        isempty(rest) || (near(); G.ImGui_AlignTextToFramePadding(); text!(String(rest)))
    end
    if haskey(words, "VRAM")
        next()
        meter!(app, :stat_vram, "VRAM", s.vram_used / s.vram_total,
               "$(_gib(s.vram_used)) / $(_gib(s.vram_total))", fs * 7.5f0)
        isnan(s.vram_temp) || (near(); G.ImGui_AlignTextToFramePadding(); text!(_deg(s.vram_temp)))
    end
    next()
    G.ImGui_AlignTextToFramePadding()
    colored(() -> text!(isempty(app.model) ? "model" : app.model), app.dim)
    near(); spark!(app, :stat_tps_graph, s.hist_tps, max(1f0, maximum(s.hist_tps; init = 0f0)), fs * 5)
    near(); G.ImGui_AlignTextToFramePadding(); text!(words["model"])
    if haskey(words, "CPU")
        next()
        meter!(app, :stat_cpu, "CPU", s.cpu, string(round(Int, 100 * s.cpu), "%"), fs * 4.5f0)
        isnan(s.cpu_temp) || (near(); G.ImGui_AlignTextToFramePadding(); text!(_deg(s.cpu_temp)))
    end
    if haskey(words, "RAM")
        next()
        meter!(app, :stat_ram, "RAM", s.ram_used / s.ram_total,
               "$(_gib(s.ram_used)) / $(_gib(s.ram_total))", fs * 7.5f0)
    end
    return nothing
end
