# servers.jl — model servers on this machine: see them, stop them, start one.
#
# LlamaChat runs models in its own process and frees them when it is told to.
# A server is the other arrangement: `llama-server` (llama.cpp's OpenAI-
# compatible HTTP endpoint, what opencode and other tools talk to) or
# `laya serve` loads a model and keeps it on the card until the PROCESS ends.
# Nothing unloads it, and nothing in here knew it was there: the planner would
# find the card full and put the next load on the CPU with no word of why.
#
# So: `list_servers` reads /proc for them (what each serves, on which port,
# how much VRAM it holds), `stop_server` ends one, and `serve` starts a
# llama-server on a model from the store, sized by the same planner that sizes
# an in-process load.

"""
A model server found running.

  `kind`   `:llama` (llama-server) or `:laya` (`laya serve` / `laya daemon`)
  `model`  the store's name for what it serves, its `--alias`, or the file name
  `port`   0 when it has none (a `laya daemon` talks on pipes)
  `vram`   bytes of GPU memory the process holds, -1 when the driver does not say
  `own`    started by this process (a typed session's daemon): closing the
           session is how that one stops
"""
struct Server
    pid::Int
    kind::Symbol
    model::String
    path::String
    port::Int
    ctx::Int
    started::Float64
    vram::Int
    own::Bool
end

const _SERVER_COMMS = Dict("llama-server" => :llama, "laya" => :laya)

# argv's value for a flag, in any of its spellings: `-m x`, `--model x`, `--model=x`.
function _argval(argv::Vector{String}, names...)
    for (i, a) in enumerate(argv), n in names
        a == n && i < length(argv) && return argv[i + 1]
        startswith(a, n * "=") && return a[length(n) + 2:end]
    end
    return nothing
end

"""
GPU memory a process holds, from its DRM file descriptors (`/proc/<pid>/fdinfo`):
the resident bytes of every memory region, each DRM client counted once however
many descriptors share it. -1 when nothing there says (no GPU, another driver's
keys, or a process that is not ours to read).
"""
function _proc_vram(dir::AbstractString)
    fd = joinpath(dir, "fdinfo")
    isdir(fd) || return -1
    clients = Dict{String,Int}()
    for f in try readdir(fd; join = true) catch; String[] end
        text = try read(f, String) catch; continue end
        m = match(r"^drm-client-id:\s*(\S+)"m, text)
        m === nothing && continue
        haskey(clients, m[1]) && continue
        total = 0
        for r in eachmatch(r"^drm-resident-(?!system)\S+:\s*(\d+)\s*(KiB|MiB|GiB)?\s*$"m, text)
            total += parse(Int, r[1]) * (r[2] == "KiB" ? 1024 : r[2] == "MiB" ? 1024^2 : r[2] == "GiB" ? 1024^3 : 1)
        end
        clients[m[1]] = total
    end
    return isempty(clients) ? -1 : sum(values(clients))
end

# blob path → the store's name for it, for every model in every store.
function _blob_names()
    out = Dict{String,String}()
    for (name, _) in try list_models() catch; Tuple{String,Int}[] end
        p = try resolve_model(name) catch; continue end
        out[p] = name
        try out[realpath(p)] = name catch end
    end
    return out
end

"""
    list_servers(; proc = "/proc") -> Vector{Server}

The model servers running as this user: every process whose program is
`llama-server` or `laya` (serving or as a daemon), oldest first. Read from
/proc alone, so it costs a directory listing and never talks to the servers.
"""
function list_servers(; proc::AbstractString = "/proc", names::Dict{String,String} = _blob_names())
    out = Server[]
    me, uid = getpid(), Libc.getuid()
    for d in try readdir(proc) catch; String[] end
        all(isdigit, d) || continue
        dir = joinpath(proc, d)
        comm = try strip(read(joinpath(dir, "comm"), String)) catch; continue end
        kind = get(_SERVER_COMMS, comm, nothing)
        kind === nothing && continue
        st = try stat(dir) catch; continue end
        st.uid == uid || continue
        argv = try String.(split(String(read(joinpath(dir, "cmdline"))), '\0'; keepempty = false)) catch; continue end
        isempty(argv) && continue
        path = ""
        if kind === :llama
            path = something(_argval(argv, "-m", "--model"), "")
        else
            i = findfirst(a -> a in ("serve", "daemon"), argv)
            i === nothing && continue                       # `laya decide`, `laya info`: not a server
            j = findnext(a -> endswith(a, ".gguf") || occursin("/blobs/sha256-", a), argv, i + 1)
            path = j === nothing ? "" : argv[j]
        end
        port = something(tryparse(Int, something(_argval(argv, "--port"), "")),
                         kind === :llama ? 8080 : any(==("serve"), argv) ? 8080 : 0)
        ctx = something(tryparse(Int, something(_argval(argv, "-c", "--ctx-size"), "")), 0)
        alias = _argval(argv, "-a", "--alias")
        model = get(names, path, something(alias, isempty(path) ? comm : basename(path)))
        # /proc/<pid>/stat is "pid (comm) state ppid …"; comm may hold spaces, so split after the ")".
        ppid = try
            s = read(joinpath(dir, "stat"), String)
            parse(Int, split(s[findlast(')', s)+1:end])[2])
        catch
            0
        end
        push!(out, Server(parse(Int, d), kind, model, path, port, ctx, st.mtime, _proc_vram(dir), ppid == me))
    end
    sort!(out; by = s -> (s.started, s.pid))
    return out
end

"""
    stop_server(pid) -> Bool

Ask a model server to exit (SIGTERM): it frees its model and its VRAM on the
way out. Only a process `list_servers` reports is touched, so a stale or
mistyped pid cannot signal anything else. `true` if the signal was sent.
"""
function stop_server(pid::Integer; proc::AbstractString = "/proc")
    any(s -> s.pid == pid, list_servers(; proc = proc, names = Dict{String,String}())) || return false
    return ccall(:kill, Cint, (Cint, Cint), pid, 15) == 0
end

"""The `llama-server` program: `\$LLAMACHAT_SERVER`, else the one on PATH."""
function llama_server_bin()
    p = get(ENV, "LLAMACHAT_SERVER", "")
    isempty(p) || return p
    w = Sys.which("llama-server")
    w === nothing && error("no `llama-server` on PATH (or set \$LLAMACHAT_SERVER to it)")
    return w
end

server_log() = joinpath(get(ENV, "XDG_CACHE_HOME", joinpath(homedir(), ".cache")), "llamachat", "llama-server.log")

"""Something is listening on 127.0.0.1:`port`. Plain libc: one loopback connect, closed at once."""
function port_open(port::Integer)
    fd = ccall(:socket, Cint, (Cint, Cint, Cint), 2, 1, 0)             # AF_INET, SOCK_STREAM
    fd < 0 && return false
    addr = zeros(UInt8, 16)
    addr[1] = 0x02                                                     # sin_family = AF_INET
    addr[3], addr[4] = UInt8((port >> 8) & 0xff), UInt8(port & 0xff)   # sin_port, network order
    addr[5], addr[6], addr[7], addr[8] = 0x7f, 0x00, 0x00, 0x01        # 127.0.0.1
    rc = ccall(:connect, Cint, (Cint, Ptr{UInt8}, Cuint), fd, addr, 16)
    ccall(:close, Cint, (Cint,), fd)
    return rc == 0
end

"""The first port from `from` that no listed server has and nothing is listening on."""
function free_port(from::Integer = 8090; servers = list_servers(; names = Dict{String,String}()))
    for p in from:from + 50
        any(s -> s.port == p, servers) || port_open(p) || return Int(p)
    end
    error("no free port from $from")
end

"""
    serve_plan(model; n_ctx = :auto) -> NamedTuple

How a llama-server would be opened on `model` right now: `(n_ctx, n_batch,
flash_attn, fits, need)`, from the planner an in-process load uses and the
VRAM that is free this moment.
"""
function serve_plan(model::AbstractString; n_ctx = :auto)
    path = resolve_model(model)
    _ensure_backend(false)
    fa = auto_flash_attn(path; n_ctx = n_ctx)
    nb = auto_batch(path; n_ctx = n_ctx, flash_attn = fa)
    c  = n_ctx === :auto ? auto_ctx(path; n_batch = nb, flash_attn = fa) : Int(n_ctx)
    p  = plan_offload(path; n_ctx = c, n_batch = nb, flash_attn = fa)
    return (path = path, n_ctx = c, n_batch = nb, flash_attn = fa, fits = p.why === :fits, need = p.vram_needed)
end

"""
    serve(model; port = free_port(), n_ctx = :auto, wait = 60) -> Server

Start `llama-server` on a chat model from the store: on 127.0.0.1, one slot,
`--jinja` (the model's own template, which is what gives a client tool calls),
with the context, batch and flash attention the planner picks for the VRAM
free now. It runs in its own session, so it outlives this process; its output
goes to `server_log()`. Returns once it is listed (and, within `wait` seconds,
answering), or throws with the log's last lines.

A server does not fit itself to the card: an over-commit aborts it. So this
refuses a model the planner cannot put wholly on the GPU, and says what is
holding the memory.
"""
function serve(model::AbstractString; port::Integer = free_port(), n_ctx = :auto, wait::Real = 60)
    bin = llama_server_bin()
    path = resolve_model(model)
    _is_laya(path) && error("$model is a Laya model: `laya serve` serves those, not llama-server")
    pl = serve_plan(model; n_ctx = n_ctx)
    if !pl.fits
        held = [s for s in list_servers() if s.vram > 0]
        error("$model needs $(_gib(pl.need)) GiB on the card and $(_gib(something(_live_vram_free(), 0))) GiB is free" *
              (isempty(held) ? "; unload the model in this window first" :
               ": " * join(("$(s.model) (pid $(s.pid)) holds $(_gib(s.vram)) GiB" for s in held), ", ")))
    end
    log = server_log()
    mkpath(dirname(log))
    cmd = `setsid -f $bin -m $path --alias $model --host 127.0.0.1 --port $port
           -ngl 99 -c $(pl.n_ctx) -b $(pl.n_batch) -ub $(pl.n_batch) -fa $(String(pl.flash_attn)) -np 1 --jinja`
    run(pipeline(cmd; stdout = log, stderr = log, stdin = devnull); wait = true)   # setsid -f returns at once
    t0 = time()
    found = nothing
    while time() - t0 < wait
        found = findfirst(s -> s.kind === :llama && s.port == port, list_servers(; names = Dict(path => String(model))))
        if found !== nothing
            port_open(port) && return list_servers(; names = Dict(path => String(model)))[found]
        elseif time() - t0 > 2
            break                                    # it started and is already gone
        end
        sleep(0.25)
    end
    found === nothing || return list_servers(; names = Dict(path => String(model)))[found]
    tail = try join(last(readlines(log), 8), "\n") catch; "" end
    error("llama-server did not stay up for $model" * (isempty(tail) ? "" : ":\n$tail"))
end
