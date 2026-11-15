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
  `router` a llama-server in router mode: it holds no model itself and starts
           one child server per model a request asks for
  `parent` the router's pid, for such a child; 0 otherwise
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
    router::Bool
    parent::Int
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
        router = false
        if kind === :llama
            path = something(_argval(argv, "-m", "--model"), "")
            router = isempty(path) && any(a -> startswith(a, "--models-preset") || startswith(a, "--models-dir"), argv)
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
        model = router ? "router" : get(names, path, something(alias, isempty(path) ? comm : basename(path)))
        # /proc/<pid>/stat is "pid (comm) state ppid …"; comm may hold spaces, so split after the ")".
        ppid = try
            s = read(joinpath(dir, "stat"), String)
            parse(Int, split(s[findlast(')', s)+1:end])[2])
        catch
            0
        end
        push!(out, Server(parse(Int, d), kind, model, path, port, ctx, st.mtime, _proc_vram(dir), ppid == me, router, ppid))
    end
    # `parent` is only meaningful when it is a router in this list.
    routers = Set(s.pid for s in out if s.router)
    out = [s.parent in routers ? s : Server(s.pid, s.kind, s.model, s.path, s.port, s.ctx, s.started, s.vram, s.own, s.router, 0) for s in out]
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


# ── every model behind one address ───────────────────────────────────────────
#
# One llama-server per model means a client is tied to whichever model that
# server was started on: opencode would list "qwen3-coder" and be answered by
# whatever was actually loaded, and choosing another model there loaded nothing.
# llama-server's router mode is the fix. Started without a model and given a
# preset file, it lists every model at /v1/models, loads the one a request
# names, and with --models-max 1 unloads the one before it. So the client's
# model list is the store, and switching in the client is switching on the card.

"""
The name a store model is served under: its name without `:latest`, and with
`:` as `-`. The router treats what follows a colon as a quantisation tag and
upper-cases it (`qwen3:4b` is listed as `qwen3:4B`), so a colon cannot be kept.
"""
served_id(name::AbstractString) = replace(replace(String(name), r":latest$" => ""), ':' => '-')

"""
VRAM a model server can be planned into: what is free on the card now, less
twice the in-process margin. A server is its own process with its own Vulkan
instance, and an over-commit there is an abort, not a refusal.

What other servers hold is not added back, even one about to be replaced: the
per-process figure in /proc counts about 2 GiB more than the card gives back
when the process ends (20.5 held against 18.3 freed, qwen3-coder), so a sum
would plan a model that does not fit. `serve_all` stops the old server first
and plans against what is then really free.
"""
function server_budget()
    _ensure_backend(false)
    return max(something(_live_vram_free(), 0) - 2 * _VRAM_MARGIN, 0.0)
end

"""
    served_models(; budget = server_budget()) -> Vector{NamedTuple}

Every model in the store a llama-server can serve wholly on the GPU, each with
the settings the planner gives it when it has the card to itself:
`(id, name, path, n_ctx, n_batch, flash_attn)`. Laya and embedding models are
left out, and so is anything that would not fit: a server does not fall back
to the CPU, it aborts.
"""
function served_models(; budget::Real = server_budget())
    out = NamedTuple[]
    for (name, _) in list_models()
        path = try resolve_model(name) catch; continue end
        (_is_laya(path) || occursin("embed", lowercase(name))) && continue
        pl = try
            with_budget(budget) do
                fa = auto_flash_attn(path)
                nb = auto_batch(path; flash_attn = fa)
                c  = auto_ctx(path; n_batch = nb, flash_attn = fa)
                (n_ctx = c, n_batch = nb, flash_attn = fa,
                 fits = plan_offload(path; n_ctx = c, n_batch = nb, flash_attn = fa).why === :fits)
            end
        catch
            continue                                  # not a model the planner can shape
        end
        pl.fits || continue
        id = served_id(name)
        any(m -> m.id == id, out) && continue
        push!(out, (id = id, name = String(name), path = path, n_ctx = pl.n_ctx, n_batch = pl.n_batch, flash_attn = pl.flash_attn))
    end
    return out
end

preset_file() = joinpath(dirname(server_log()), "llama-server.ini")

"""Write the router's preset file: one section a model, its path and planned settings."""
function write_preset(models, file::AbstractString = preset_file())
    mkpath(dirname(file))
    open(file, "w") do io
        println(io, "; Written by LlamaChat.serve_all from the model store. Edits are overwritten.")
        println(io, "version = 1\n\n[*]\nn-gpu-layers = 99\njinja = true\nparallel = 1")
        for m in models
            println(io, "\n[", m.id, "]\nmodel = ", m.path, "\nc = ", m.n_ctx, "\nb = ", m.n_batch,
                    "\nub = ", m.n_batch, "\nflash-attn = ", m.flash_attn)
        end
    end
    return file
end

opencode_config() = joinpath(get(ENV, "XDG_CONFIG_HOME", joinpath(homedir(), ".config")), "opencode", "opencode.json")

"""
    opencode_sync(models, port; file = opencode_config()) -> String

Make opencode's `llamacpp` provider list exactly `models`, at this port, each
with its real context size. Everything else in the file is kept as it is. A
one-line account of what happened: written, or why not (opencode not
installed, or a config this cannot parse and so will not overwrite).
"""
function opencode_sync(models, port::Integer; file::AbstractString = opencode_config())
    isdir(dirname(file)) || return "opencode: no $(dirname(file)), nothing written"
    cfg = ODict()
    if isfile(file)
        cfg = try _parse_json(read(file, String)) catch; nothing end
        cfg isa ODict || return "opencode: $file is not plain JSON, left alone"
    end
    haskey(cfg, "\$schema") || (cfg["\$schema"] = "https://opencode.ai/config.json")
    prov = get(cfg, "providers", nothing)
    prov isa ODict || (prov = ODict(); cfg["providers"] = prov)
    prov["llamacpp"] = ODict(
        "name" => "llama.cpp (local)",
        "package" => "@opencode/ai/providers/openai-compatible",
        "settings" => ODict("baseURL" => "http://127.0.0.1:$port/v1"),
        "models" => ODict((m.id => ODict("name" => "$(m.id) (local)",
                                         "limit" => ODict("context" => m.n_ctx, "output" => min(8192, m.n_ctx ÷ 4)))
                           for m in models)...))
    write(file, JSON.json(cfg, 2))
    return "opencode: llamacpp/" * join((m.id for m in models), ", llamacpp/")
end

"""
    serve_all(; port = 8090, sync = true, probe = sync, wait = 30) -> (server, models, note)

Serve the whole store from one address. Starts llama-server as a router on a
preset written from `served_models()`: every model is listed, the one a
request names is loaded, and only one is loaded at a time. A router already on
that port is stopped first, so this is also how the list is refreshed after a
pull.

With `sync`, opencode's config is updated to match (`opencode_sync`), and with
`probe` only the models that can take tool calls are listed there
(`tool_capable`): a coding agent sends tool definitions with every request,
and a model whose template llama-server cannot build a tool parser for answers
each one with an error. A model is probed once, the first time it is served
(it has to be loaded for that, a few seconds each), and the answer is kept.
"""
function serve_all(; port::Integer = 8090, sync::Bool = true, probe::Bool = sync, wait::Real = 30)
    bin = llama_server_bin()
    # Whatever llama-server has this port, and the models a router there has loaded.
    running = list_servers(; names = Dict{String,String}())
    here = [s.pid for s in running if s.kind === :llama && s.port == port]
    old = [here; [s.pid for s in running if s.parent in here]]
    foreach(stop_server, here)                  # a router takes its children with it
    # Gone, not just closed: the plan below is made against the memory they give back.
    t0 = time()
    while time() - t0 < 20 && (port_open(port) || any(s -> s.pid in old, list_servers(; names = Dict{String,String}())))
        sleep(0.25)
    end
    port_open(port) && error("port $port is in use by something that is not a llama-server")
    models = served_models()
    isempty(models) && error("no model in the store fits the card as a server right now " *
                             "($(_gib(server_budget())) GiB to plan with); unload the model in this window first")
    preset = write_preset(models)
    log = server_log()
    cmd = `setsid -f $bin --models-preset $preset --models-max 1 --host 127.0.0.1 --port $port`
    run(pipeline(cmd; stdout = log, stderr = log, stdin = devnull); wait = true)
    t0 = time()
    while time() - t0 < wait
        if port_open(port)
            i = findfirst(s -> s.router && s.port == port, list_servers(; names = Dict{String,String}()))
            if i !== nothing
                server = list_servers(; names = Dict{String,String}())[i]
                listed, left_out = models, String[]
                if probe
                    ok = tool_capable(models, port)
                    # A decision-trained model (Nimble) passes the probe and is no use
                    # to an agent: asked to chat with a 8.6k-token agent prompt it
                    # reasoned for over 280 s without answering. It is served, for
                    # anything that wants it by name, and not offered to opencode.
                    agent(m) = ok[m.id] && decision_template(m.path) === nothing
                    listed = [m for m in models if agent(m)]
                    left_out = [m.id for m in models if !agent(m)]
                end
                note = sync ? opencode_sync(listed, port) : ""
                isempty(left_out) || (note *= "  (served, not listed there: " * join(left_out, ", ") * ")")
                return (server = server, models = models, note = note)
            end
        end
        sleep(0.25)
    end
    tail = try join(last(readlines(log), 8), "\n") catch; "" end
    error("the llama-server router did not come up on port $port" * (isempty(tail) ? "" : ":\n$tail"))
end

"""
    http_post(port, path, body; timeout = 30) -> (status, text)

POST JSON to a server on 127.0.0.1 and read the whole reply: a plain blocking
socket, closed by the server (`Connection: close`). `status` is 0 when nothing
answered. Not Downloads: a request with a body, made from a worker thread,
fails there with "client read function EOF fail, only 0/20 of needed bytes
read" (Julia 1.13.4), and these calls are made from worker threads so the
window keeps drawing. The calls are marked GC-safe: a thread waiting in
`recv` for a model to load must not hold up a collection.
"""
function http_post(port::Integer, path::AbstractString, body::AbstractString; timeout::Real = 30)
    fd = ccall(:socket, Cint, (Cint, Cint, Cint), 2, 1, 0)
    fd < 0 && return (0, "")
    try
        tv = Int[floor(Int, timeout), 0]                                  # struct timeval
        for opt in (20, 21)                                               # SO_RCVTIMEO, SO_SNDTIMEO
            ccall(:setsockopt, Cint, (Cint, Cint, Cint, Ptr{Int}, Cuint), fd, 1, opt, tv, 16)
        end
        addr = zeros(UInt8, 16)
        addr[1] = 0x02
        addr[3], addr[4] = UInt8((port >> 8) & 0xff), UInt8(port & 0xff)
        addr[5], addr[6], addr[7], addr[8] = 0x7f, 0x00, 0x00, 0x01
        (@ccall gc_safe = true connect(fd::Cint, addr::Ptr{UInt8}, 16::Cuint)::Cint) == 0 || return (0, "")
        req = Vector{UInt8}("POST $path HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nContent-Type: application/json\r\n" *
                            "Content-Length: $(sizeof(body))\r\nConnection: close\r\n\r\n$body")
        sent = 0
        while sent < length(req)
            n = @ccall gc_safe = true send(fd::Cint, pointer(req, sent + 1)::Ptr{UInt8}, (length(req) - sent)::Csize_t, 0x4000::Cint)::Cssize_t   # MSG_NOSIGNAL
            n <= 0 && return (0, "")
            sent += n
        end
        out = UInt8[]
        buf = Vector{UInt8}(undef, 65536)
        while true
            n = @ccall gc_safe = true recv(fd::Cint, buf::Ptr{UInt8}, length(buf)::Csize_t, 0::Cint)::Cssize_t
            n <= 0 && break
            append!(out, view(buf, 1:n))
        end
        text = String(out)
        m = match(r"^HTTP/\d\.\d (\d{3})", text)
        m === nothing && return (0, "")
        i = findfirst("\r\n\r\n", text)
        return (parse(Int, m[1]), i === nothing ? "" : text[last(i)+1:end])
    finally
        ccall(:close, Cint, (Cint,), fd)
    end
end

"""Ask a router to unload a model (it stays listed, and loads again when asked for)."""
unload_served(port::Integer, id::AbstractString) =
    first(http_post(port, "/models/unload", JSON.json(ODict("model" => String(id))); timeout = 15)) == 200

# ── can a served model take tool calls? ──────────────────────────────────────

probe_cache() = joinpath(dirname(server_log()), "tool-probe.json")

const _PROBE_BODY = """{"messages":[{"role":"user","content":"hi"}],"max_tokens":1,"tools":[{"type":"function","function":{"name":"probe","description":"probe","parameters":{"type":"object","properties":{"path":{"type":"string","pattern":"[a-z]+"},"n":{"type":"integer"}},"required":["path"]}}}]}"""

"""
    probe_tools(port, id) -> Bool

One request to a served model with a tool whose schema carries a regex
`pattern`, as a coding agent's tools do. `false` when the server cannot build
a tool-call parser for the model's chat template: qwen3:4b's (Qwen3 Thinking
2507) fails with "JSON schema conversion failed: Pattern must start with '^'
and end with '\$'" on llama.cpp b10286, while the same model takes a tool
without a pattern. The router loads the model to answer, so this takes as long
as a load.
"""
function probe_tools(port::Integer, id::AbstractString)
    body = replace(_PROBE_BODY, "{\"messages\"" => "{\"model\":" * JSON.json(String(id)) * ",\"messages\""; count = 1)
    status, text = http_post(port, "/v1/chat/completions", body; timeout = 240)
    status == 0 && error("no answer from the server on port $port while probing $id")
    return status == 200 && occursin("\"choices\"", text)
end

"""
    tool_capable(models, port; cache = probe_cache()) -> Dict{String,Bool}

Which served models can take tool calls, by id. Answers are kept per weights
file (its blob name), so each model is probed once; the last one probed is
unloaded again, leaving the card as it was.
"""
function tool_capable(models, port::Integer; cache::AbstractString = probe_cache())
    known = try _parse_json(read(cache, String)) catch; ODict() end
    known isa ODict || (known = ODict())
    out = Dict{String,Bool}()
    probed = ""
    for m in models
        key = basename(m.path)
        if !(get(known, key, nothing) isa Bool)
            known[key] = probe_tools(port, m.id)
            probed = m.id
        end
        out[m.id] = known[key]
    end
    if !isempty(probed)
        mkpath(dirname(cache))
        write(cache, JSON.json(known, 2))
        try unload_served(port, probed) catch end
    end
    return out
end
