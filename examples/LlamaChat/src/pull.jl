# Model download from ollama's public registry, without ollama.
#
# The registry speaks the OCI / Docker distribution protocol:
#
#   GET /v2/<ns>/<model>/manifests/<tag>   → JSON: a config blob and the layers
#                                            (GGUF weights, template, params,
#                                            license), each named by sha256
#   GET /v2/<ns>/<model>/blobs/<digest>    → 307 to Cloudflare R2, which
#                                            honours HTTP Range
#
# and the on-disk layout is the one `resolve_model` already reads:
# manifests/registry.ollama.ai/<ns>/<model>/<tag> and blobs/sha256-<hex>.
#
# Speed comes from parallel byte ranges, not from the HTTP client: one
# connection to R2 is far below a home link, several saturate it (measured:
# 4.4–7.6 MiB/s on one, 11.2 on four, on a ~95 Mbit/s line). So a large blob is
# cut into `chunk`-sized ranges, a pool of tasks takes ranges from a queue, and
# each streams its range straight into the right offset of a preallocated
# `-partial` file — no buffering a chunk in memory, no reassembly pass.
#
# A pull survives being stopped. Each finished range is appended to a
# `.chunks` log beside the partial file; a later pull of the same blob skips
# those ranges. The whole blob is checked against its sha256 before it is
# renamed into place, which also catches a server that ignored a Range header
# (it would have written the wrong bytes at the right offset).
#
# Julia's `Downloads` (libcurl, multiplexed on Julia's event loop) does the HTTP.

import Downloads
import RepliBuild           # its SHA, when sha256sum is missing

const _MANIFEST_ACCEPT = "application/vnd.docker.distribution.manifest.v2+json"

"""
    PullProgress

Live counters for a `pull`, updated from its worker tasks and safe to read from
any thread (the GUI reads them every frame). `cancel!(p)` stops the pull; what
it finished stays on disk for the next pull of the same model to resume.
"""
mutable struct PullProgress
    name::String
    total::Threads.Atomic{Int}      # bytes this pull has to have on disk (known after the manifest)
    done::Threads.Atomic{Int}       # of which present: fetched, resumed, or already in a store
    skipped::Threads.Atomic{Int}    # of `done`, what was already there (not part of the speed)
    phase::Threads.Atomic{Int}      # see _PHASES
    cancelled::Threads.Atomic{Bool} # the user stopped it
    aborted::Threads.Atomic{Bool}   # stop everything: cancelled, or a range failed for good
    live::Set{Base.Event}           # one per request in flight; see _request
    lk::ReentrantLock
    t0::Float64
end
PullProgress(name::AbstractString = "") =
    PullProgress(String(name), Threads.Atomic{Int}(0), Threads.Atomic{Int}(0), Threads.Atomic{Int}(0),
                 Threads.Atomic{Int}(0), Threads.Atomic{Bool}(false), Threads.Atomic{Bool}(false),
                 Set{Base.Event}(), ReentrantLock(), time())

const _PHASES = (:manifest, :downloading, :verifying, :done, :failed)
phase(p::PullProgress) = _PHASES[p.phase[] + 1]
_phase!(p::PullProgress, s::Symbol) = (p.phase[] = findfirst(==(s), _PHASES) - 1; p)

"""Stop every request in flight and keep new ones from starting."""
function _abort!(p::PullProgress)
    p.aborted[] = true
    lock(() -> foreach(notify, p.live), p.lk)
    return p
end
cancel!(p::PullProgress) = (p.cancelled[] = true; _abort!(p))
cancelled(p::PullProgress) = p.cancelled[]

"""
`Downloads.request` with an `interrupt` event of its own.

An event can serve exactly one request. When a request finishes normally,
`Downloads` notifies its `interrupt` itself, to stop the task that was waiting
on it (Downloads.jl 1.7, `request`, the `finally` block). Shared between
requests, the first one to finish aborts all the others — here that was the
manifest, which killed every range before it started, with `code 0` and no
message. So each request gets a fresh event, registered in `p.live` for
`_abort!` to reach.
"""
function _request(url, p::PullProgress; kw...)
    ev = Base.Event()
    lock(p.lk) do
        p.aborted[] && notify(ev)          # aborted before we started: start stopped
        push!(p.live, ev)
    end
    try
        return Downloads.request(url; interrupt = ev, throw = true, kw...)
    finally
        lock(() -> delete!(p.live, ev), p.lk)
    end
end

function _split_name(name::AbstractString)
    spec, tag = occursin(':', name) ? split(name, ':'; limit = 2) : (name, "latest")
    ns, model = occursin('/', spec) ? split(spec, '/'; limit = 2) : ("library", spec)
    return String(ns), String(model), String(tag)
end

_blob_file(root, digest) = joinpath(root, "blobs", replace(digest, ':' => '-'))

"""A blob already present, with the right size, in any store LlamaChat reads."""
function _have_blob(digest::AbstractString, size::Integer)
    for r in model_roots()
        p = _blob_file(r, digest)
        isfile(p) && filesize(p) == size && return p
    end
    return nothing
end

"""Copy one blob into place: to a `-partial` file, size-checked, then renamed."""
function _copy_blob(src, dest, size::Integer)
    mkpath(dirname(dest))
    tmp = dest * "-partial"
    cp(src, tmp; force = true)
    got = filesize(tmp)
    got == size || (rm(tmp; force = true); error("copy of $src came out $got bytes, expected $size"))
    mv(tmp, dest; force = true)
    return dest
end

"""
    LlamaChat.import_ollama(; from = ollama_stores(), to = models_dir()) -> Vector{String}

Copy every model in ollama's stores into LlamaChat's own, so nothing here needs
ollama or root again. Blobs already present are skipped, so it is safe to rerun
(after an `ollama pull`, say). Each manifest is written after its blobs, so an
interrupted import leaves no half-model. The originals are not touched:
`/var/lib/ollama` belongs to the `ollama` user, and removing it is yours to do
(`sudo rm -rf /var/lib/ollama`, after `sudo systemctl disable --now ollama`).

Returns the names imported, e.g. `["qwen3:4b", "qwen3-coder:latest"]`.
"""
function import_ollama(; from = ollama_stores(), to::AbstractString = models_dir(), io::IO = stderr)
    names = String[]
    for store in from
        mroot = joinpath(store, "manifests", REGISTRY)
        (isdir(mroot) && abspath(store) != abspath(to)) || continue
        for (dir, _, files) in walkdir(mroot), f in files
            endswith(f, ".tmp") && continue
            src = joinpath(dir, f)
            rel = relpath(src, mroot)
            parts = splitpath(rel)
            name = (parts[1] == "library" ? join(parts[2:end-1], "/") : join(parts[1:end-1], "/")) * ":" * parts[end]
            m = try JSON.parsefile(src) catch; continue end
            blobs = Any[]
            haskey(m, "config") && push!(blobs, m["config"])
            append!(blobs, m["layers"])
            if !all(b -> isfile(_blob_file(store, b["digest"])), blobs)
                println(io, "skipping $name: its store is missing a blob")
                continue
            end
            # A blob is named by its sha256, and that name is the truth: ollama
            # has been seen recording a stale size for a config blob (qwen3-coder:
            # 539 in the manifest, 542 on disk, digest intact). Where size and
            # file disagree, hash the file; keep it only if it matches its name.
            ok = true
            for b in blobs
                f = _blob_file(store, b["digest"])
                filesize(f) == b["size"] && continue
                if _sha256(f) == b["digest"]
                    b["size"] = filesize(f)       # copy what is really there
                else
                    println(io, "skipping $name: $(basename(f)) does not match its own sha256")
                    ok = false
                end
            end
            ok || continue
            total = sum(b -> Int(b["size"]), blobs)
            print(io, rpad(name, 32), lpad(_human(total), 10), " … "); flush(io)
            t0 = time()
            copied = 0
            for b in blobs
                dest, size = _blob_file(to, b["digest"]), Int(b["size"])
                isfile(dest) && filesize(dest) == size && continue
                _copy_blob(_blob_file(store, b["digest"]), dest, size)
                copied += size
            end
            mdest = joinpath(to, "manifests", REGISTRY, rel)
            mkpath(dirname(mdest))
            cp(src, mdest * ".tmp"; force = true)
            mv(mdest * ".tmp", mdest; force = true)
            println(io, copied == 0 ? "already here" :
                        "copied $(_human(copied)) in $(round(time() - t0; digits = 1)) s")
            push!(names, name)
        end
    end
    return names
end

function _sha256(path)
    if Sys.which("sha256sum") !== nothing          # coreutils: SHA-NI, GB/s
        return "sha256:" * first(split(read(`sha256sum $path`, String)))
    end
    return "sha256:" * bytes2hex(open(RepliBuild.SHA.sha256, path))
end

# One range of one blob, streamed into place. Returns the bytes it added.
function _fetch_range(url, part, a, b, p::PullProgress)
    got = Ref(0)
    on_progress(_, now, _...) = (d = now - got[]; d > 0 && (Threads.atomic_add!(p.done, d); got[] = now))
    try
        open(part, "r+") do io
            seek(io, a)
            r = _request(url, p; output = io, headers = ["Range" => "bytes=$a-$b"], progress = on_progress)
            r.status == 206 || error("expected 206 Partial Content for bytes $a-$b, got $(r.status)")
            position(io) - a == b - a + 1 || error("short range: bytes $a-$b, got $(position(io) - a)")
        end
    catch
        Threads.atomic_sub!(p.done, got[])          # this range starts over
        rethrow()
    end
end

function _fetch_blob(url, size::Integer, dest, p::PullProgress; connections, chunk)
    mkpath(dirname(dest))
    part, log = dest * "-partial", dest * "-partial.chunks"
    n = cld(size, chunk)
    len(i) = min(chunk, size - i * chunk)
    done = Set{Int}()
    if isfile(part) && filesize(part) == size && isfile(log)
        for l in eachline(log)
            i = tryparse(Int, l)
            i !== nothing && 0 <= i < n && push!(done, i)
        end
    else
        open(io -> truncate(io, size), part, "w")   # preallocate; ranges land at their offsets
        rm(log; force = true)
    end
    resumed = sum(len, done; init = 0)
    Threads.atomic_add!(p.done, resumed); Threads.atomic_add!(p.skipped, resumed)
    todo = setdiff(0:n-1, done)
    queue = Channel{Int}(length(todo))
    foreach(i -> put!(queue, i), todo)
    close(queue)
    loglock = ReentrantLock()
    function worker()
        for i in queue
            p.aborted[] && break
            a, b = i * chunk, i * chunk + len(i) - 1
            for attempt in 1:5
                try
                    _fetch_range(url, part, a, b, p)
                    lock(() -> open(f -> println(f, i), log, "a"), loglock)
                    break
                catch e
                    (p.aborted[] || attempt == 5) && rethrow()
                    sleep(0.5 * 2^attempt)          # a dropped connection: back off, retry
                end
            end
        end
    end
    tasks = [Threads.@spawn worker() for _ in 1:min(connections, length(todo))]
    failure = nothing
    for t in tasks
        try
            wait(t)
        catch e
            failure === nothing && (failure = e; _abort!(p))   # stop the others too
        end
    end
    failure === nothing || throw(failure)
    _phase!(p, :verifying)
    got = _sha256(part)
    if got != url_digest(url)
        rm(part; force = true); rm(log; force = true)
        error("checksum mismatch for $(basename(dest)): got $got")
    end
    mv(part, dest; force = true)
    rm(log; force = true)
    _phase!(p, :downloading)
    return dest
end
url_digest(url) = last(split(url, '/'))

"""
    LlamaChat.pull(name; root, connections = 6, chunk = 32 MiB, progress) -> path

Download `name` (`"qwen3:0.6b"`, `"gemma3"`, `"user/model:tag"`) from ollama's
public registry into `root` — `\$OLLAMA_MODELS` when set, else
`~/.ollama/models` — in ollama's own layout, so `load`, `gui` and ollama itself
all see it. Returns the path of the weights.

Large blobs come down as `connections` parallel byte ranges written straight
into place; an interrupted pull resumes where it stopped; every blob is checked
against its sha256. Blobs already present in any store are not fetched again.

`progress` (a `PullProgress`) is how another thread watches it or stops it
(`cancel!`). At the REPL a progress line is printed to stderr.
"""
function pull(name::AbstractString; root::AbstractString = pull_root(),
              connections::Integer = 6, chunk::Integer = 32 * 2^20,
              progress::PullProgress = PullProgress(name), io::IO = stderr)
    p = progress
    ns, model, tag = _split_name(name)
    base = "https://$REGISTRY/v2/$ns/$model"
    printer = _istty(io) ? _progress_printer(io, p) : nothing
    try
        _phase!(p, :manifest)
        raw = try
            buf = IOBuffer()
            _request("$base/manifests/$tag", p; output = buf, headers = ["Accept" => _MANIFEST_ACCEPT])
            take!(buf)
        catch e
            e isa Downloads.RequestError && e.response.status == 404 &&
                error("no model \"$name\" in the ollama registry (see ollama.com/library)")
            rethrow()
        end
        m = JSON.parse(String(copy(raw)))
        blobs = Any[]
        haskey(m, "config") && push!(blobs, m["config"])
        append!(blobs, m["layers"])
        p.total[] = sum(b -> Int(b["size"]), blobs)
        _phase!(p, :downloading)
        # Largest first: the weights are the long pole, the rest is kilobytes.
        for b in sort(blobs; by = b -> -Int(b["size"]))
            digest, size = String(b["digest"]), Int(b["size"])
            dest = _blob_file(root, digest)
            if isfile(dest) && filesize(dest) == size
                Threads.atomic_add!(p.done, size); Threads.atomic_add!(p.skipped, size)
                continue
            end
            # In another store (ollama's): copy it rather than point at it, so
            # this store never depends on one you may delete. Local disk, not
            # the network.
            other = _have_blob(digest, size)
            if other !== nothing
                _copy_blob(other, dest, size)
                Threads.atomic_add!(p.done, size); Threads.atomic_add!(p.skipped, size)
                continue
            end
            _fetch_blob("$base/blobs/$digest", size, _blob_file(root, digest), p;
                        connections = connections, chunk = size > chunk ? chunk : size)
        end
        # The manifest last, atomically: until it exists the model does not.
        mpath = joinpath(root, "manifests", REGISTRY, ns, model, tag)
        mkpath(dirname(mpath))
        write(mpath * ".tmp", raw)
        mv(mpath * ".tmp", mpath; force = true)
        _phase!(p, :done)
    catch e
        _phase!(p, :failed)
        cancelled(p) && error("pull of $name stopped; pull it again to resume")
        rethrow()
    finally
        printer === nothing || wait(printer)
    end
    return resolve_model(name)
end

function _progress_printer(io, p::PullProgress)
    return @async begin
        while true
            ph = phase(p)
            print(io, "\r\e[K", pull_status(p))
            ph in (:done, :failed) && break
            sleep(0.25)
        end
        println(io)
    end
end

"""One line: name, phase, bytes, speed, time left."""
function pull_status(p::PullProgress)
    ph, done, total = phase(p), p.done[], p.total[]
    ph === :manifest && return "$(p.name): fetching manifest…"
    dt = max(time() - p.t0, 1e-3)
    pct = total > 0 ? round(Int, 100 * done / total) : 0
    rate = (done - p.skipped[]) / dt
    eta = rate > 0 && total > done ? round(Int, (total - done) / rate) : 0
    s = "$(p.name): $(_human(done)) / $(_human(total))  $(pct)%  $(_human(round(Int, rate)))/s"
    ph === :downloading && eta > 0 && (s *= "  $(eta ÷ 60):$(lpad(eta % 60, 2, '0')) left")
    ph === :verifying && (s *= "  verifying sha256…")
    ph === :done && (s = "$(p.name): $(_human(total)) in $(round(dt; digits = 1)) s")
    ph === :failed && (s *= "  (stopped)")
    return s
end
