# typed.jl — typed decisions: the second kind of model LlamaChat runs.
#
# A chat model reads a conversation and writes text. A typed decision model
# (Laya) reads a STATE and a set of QUESTIONS, each with its own answer options,
# and returns a probability for every option: no text is generated. Three
# question types — choice, score, noul — so a caller branches on a value, not
# on a string it has to parse.
#
# Three pieces here:
#
#   * the format: `Choice`/`Score`/`Noul`, a `TypedFile` read from JSON, and
#     `Decisions` back. Everything is checked before the model sees it, because
#     the engine does not: a question typed "nope" comes back as a confident
#     empty choice instead of an error (laya 0.9.6, measured);
#   * the engine: `TypedSession` owns a `laya daemon` process and talks JSON
#     lines to it. The GGUF is a ggmlc graph, not a llama.cpp model, and the
#     runner is a C++ executable with no library behind it, so a process is the
#     way in until ggmlc is a Hub package of its own;
#   * the store: `add_model` puts any local GGUF into LlamaChat's store under a
#     name, and `bring_laya` does it for the Laya files, so they sit in
#     `list_models()` and the window's picker next to the chat models.

# ── an ordered JSON object ───────────────────────────────────────────────────

"""
A JSON object that keeps its keys in file order. JSON.jl 0.21 parses objects
into `Dict`, which shuffles them, and order is input here: the options of a
question reach the model in the order written, and with weak labels the winner
changes with it. `JSON.parse(text; dicttype = ODict)`.
"""
struct ODict <: AbstractDict{String,Any}
    ks::Vector{String}
    vs::Vector{Any}
end
ODict() = ODict(String[], Any[])
ODict(ps::Pair...) = (d = ODict(); for (k, v) in ps; d[k] = v; end; d)
Base.length(d::ODict) = length(d.ks)
Base.iterate(d::ODict, i::Int = 1) = i > length(d.ks) ? nothing : (d.ks[i] => d.vs[i], i + 1)
Base.get(d::ODict, k::AbstractString, default) =
    (i = findfirst(==(k), d.ks); i === nothing ? default : d.vs[i])
function Base.setindex!(d::ODict, v, k::AbstractString)
    i = findfirst(==(k), d.ks)
    i === nothing ? (push!(d.ks, String(k)); push!(d.vs, v)) : (d.vs[i] = v)
    return d
end

_parse_json(text::AbstractString) = JSON.parse(text; dicttype = ODict)

# ── the format ───────────────────────────────────────────────────────────────

"""A typed question: `Choice`, `Score` or `Noul`."""
abstract type Question end

"""Pick one label. `criteria` is `label => description` (or `nothing`), in order."""
struct Choice <: Question
    id::String
    instructions::String
    criteria::Vector{Pair{String,Union{Nothing,String}}}
end

"""Place the state on an ordered scale. `criteria` is the levels, lowest first."""
struct Score <: Question
    id::String
    instructions::String
    criteria::Vector{String}
end

"""Yes or no: the answer is P(true). `no`/`yes` replace the default wording."""
struct Noul <: Question
    id::String
    instructions::String
    no::Union{Nothing,String}
    yes::Union{Nothing,String}
end
Noul(id, instructions) = Noul(id, instructions, nothing, nothing)

question_type(::Choice) = :choice
question_type(::Score)  = :score
question_type(::Noul)   = :noul

"""How many options a question puts in front of the model."""
n_options(q::Choice) = length(q.criteria)
n_options(q::Score)  = length(q.criteria)
n_options(::Noul)    = 2

"""
A request that is not in the format. `param` is the path of the part at fault
(`questions.intent.criteria`), as the engine's own HTTP errors name it.
"""
struct TypedFormatError <: Exception
    param::String
    msg::String
end
Base.showerror(io::IO, e::TypedFormatError) = print(io, e.param, ": ", e.msg)

_bad(param, msg) = throw(TypedFormatError(param, msg))

const MAX_OPTIONS = 16          # laya.max_opts in every published file

"""
    parse_questions(obj; max_options = 16) -> Vector{Question}

The questions object of a request, `id => {type, instructions, criteria}`,
checked and typed, in the order written. Throws `TypedFormatError`.
"""
function parse_questions(obj; max_options::Integer = MAX_OPTIONS)
    obj isa ODict || _bad("questions", "must be an object of id => question")
    isempty(obj) && _bad("questions", "has no questions")
    out = Question[]
    for (id, q) in obj
        at = "questions.$id"
        q isa ODict || _bad(at, "must be an object with `type` and `instructions`")
        ty = get(q, "type", nothing)
        ty in ("choice", "score", "noul") ||
            _bad("$at.type", "must be \"choice\", \"score\" or \"noul\"" * (ty === nothing ? " (it is missing)" : "; got $(repr(ty))"))
        ins = get(q, "instructions", nothing)
        ins isa AbstractString && !isempty(strip(ins)) ||
            _bad("$at.instructions", "must be a sentence: it is part of what the model reads")
        c = get(q, "criteria", nothing)
        for k in keys(q)
            k in ("type", "instructions", "criteria") || _bad("$at.$k", "is not a field of a question")
        end
        if ty == "choice"
            c isa ODict || _bad("$at.criteria", "a choice needs an object of label => description (or null)")
            2 <= length(c) <= max_options ||
                _bad("$at.criteria", "a choice takes 2 to $max_options labels; this has $(length(c))")
            crit = Pair{String,Union{Nothing,String}}[]
            for (label, d) in c
                d === nothing || d isa AbstractString ||
                    _bad("$at.criteria.$label", "a description is a string or null")
                push!(crit, label => (d === nothing ? nothing : String(d)))
            end
            push!(out, Choice(id, String(ins), crit))
        elseif ty == "score"
            c isa AbstractVector && all(x -> x isa AbstractString, c) ||
                _bad("$at.criteria", "a score needs a list of level descriptions, lowest first")
            2 <= length(c) <= max_options ||
                _bad("$at.criteria", "a score takes 2 to $max_options levels; this has $(length(c))")
            push!(out, Score(id, String(ins), String.(c)))
        else
            no = yes = nothing
            if c !== nothing
                c isa ODict || _bad("$at.criteria", "a noul's criteria is an object with `false` and `true`")
                for (k, v) in c
                    k in ("false", "true") || _bad("$at.criteria.$k", "a noul's criteria has only `false` and `true`")
                    v isa AbstractString || _bad("$at.criteria.$k", "must be a string")
                end
                no, yes = get(c, "false", nothing), get(c, "true", nothing)
            end
            push!(out, Noul(id, String(ins), no, yes))
        end
    end
    return out
end

_question_json(q::Choice) = ODict("type" => "choice", "instructions" => q.instructions,
                                  "criteria" => ODict(q.criteria...))
_question_json(q::Score)  = ODict("type" => "score", "instructions" => q.instructions, "criteria" => q.criteria)
function _question_json(q::Noul)
    d = ODict("type" => "noul", "instructions" => q.instructions)
    if q.no !== nothing || q.yes !== nothing
        c = ODict()
        q.no  === nothing || (c["false"] = q.no)
        q.yes === nothing || (c["true"]  = q.yes)
        d["criteria"] = c
    end
    return d
end

"""The questions as the JSON object a request carries."""
questions_json(qs::Vector{<:Question}) = ODict((q.id => _question_json(q) for q in qs)...)

"""
What a JSON file holds, for the typed format:

  `:request`    `{"state": …, "questions": {…}}` — one decision, ready to run
  `:batch`      `{"states": […], "questions": {…}}` — one decision per state
  `:questions`  an object whose every value is a question — questions alone
  `:state`      anything else: the whole file is one state (text that is not
                JSON is a plain-text state)

`states` is empty for `:questions`, and `questions` for `:state`.
"""
struct TypedFile
    kind::Symbol
    states::Vector{Any}
    questions::Vector{Question}
end

_is_question(v) = v isa ODict && get(v, "type", nothing) in ("choice", "score", "noul")

"""
    parse_typed(text) -> TypedFile

Read the typed format from JSON text (see `TypedFile` for the four shapes).
A file that says it carries questions has them checked: `TypedFormatError`.
"""
function parse_typed(text::AbstractString)
    v = try
        _parse_json(text)
    catch
        return TypedFile(:state, Any[String(strip(text))], Question[])
    end
    if v isa ODict && haskey(v, "questions")
        qs = parse_questions(v["questions"])
        if haskey(v, "states")
            v["states"] isa AbstractVector && !isempty(v["states"]) ||
                _bad("states", "must be a non-empty list of states")
            return TypedFile(:batch, collect(Any, v["states"]), qs)
        end
        haskey(v, "state") || return TypedFile(:questions, Any[], qs)
        return TypedFile(:request, Any[v["state"]], qs)
    end
    v isa ODict && !isempty(v) && all(_is_question, values(v)) &&
        return TypedFile(:questions, Any[], parse_questions(v))
    return TypedFile(:state, Any[v], Question[])
end

"""`parse_typed` on a file."""
load_typed(path::AbstractString) = parse_typed(read(path, String))

# ── answers ──────────────────────────────────────────────────────────────────

"""
One question's answer.

  `value`          the winning label (choice), the expected level (score), or
                   P(true) (noul)
  `probabilities`  `option => probability`, in the question's order; for a
                   score the options are the levels' own wording
  `confidence`     choice and score: 1 − entropy / ln(options), 0 is flat and 1
                   is certain. noul: max(P, 1 − P), never under 0.5. Keep a
                   cutoff per type
"""
struct Answer
    id::String
    type::Symbol
    value::Union{String,Float64}
    confidence::Float64
    probabilities::Vector{Pair{String,Float64}}
end

"""Every answer to one state, with what it cost. `raw` is the engine's JSON."""
struct Decisions
    model::String
    family::String
    answers::Vector{Answer}
    input_tokens::Int
    latency_ms::Float64
    raw::ODict
end

Base.getindex(d::Decisions, id::AbstractString) =
    (i = findfirst(a -> a.id == id, d.answers); i === nothing ? throw(KeyError(id)) : d.answers[i])
Base.length(d::Decisions) = length(d.answers)
Base.iterate(d::Decisions, i::Int = 1) = iterate(d.answers, i)

function _answer(q::Question, a)
    a isa ODict || error("the engine returned no answer for question `$(q.id)`")
    conf = Float64(get(a, "confidence", NaN))
    if q isa Choice
        p = get(a, "probabilities", ODict())
        return Answer(q.id, :choice, String(get(a, "choice", "")), conf,
                      [l => Float64(get(p, l, NaN)) for (l, _) in q.criteria])
    elseif q isa Score
        p = get(a, "probabilities", ODict())
        return Answer(q.id, :score, Float64(get(a, "score", NaN)), conf,
                      [c => Float64(get(p, string(i - 1), NaN)) for (i, c) in enumerate(q.criteria)])
    else
        y = Float64(get(a, "noul", NaN))
        return Answer(q.id, :noul, y, conf, ["false" => 1 - y, "true" => y])
    end
end

"""The answer's headline: `refund 0.82`, `2.14 of 3`, `yes 0.91`."""
function headline(a::Answer)
    r(x) = string(round(x; digits = 2))
    if a.type === :choice
        i = findfirst(p -> first(p) == a.value, a.probabilities)
        return string(a.value, i === nothing ? "" : "  " * r(last(a.probabilities[i])))
    elseif a.type === :score
        return string(r(a.value), " of ", length(a.probabilities) - 1)
    end
    return string(a.value >= 0.5 ? "yes  " : "no  ", r(a.value))
end

function Base.show(io::IO, ::MIME"text/plain", d::Decisions)
    printstyled(io, d.model, "  ·  ", d.family, "  ·  ", d.input_tokens, " tokens  ·  ",
                round(d.latency_ms; digits = 1), " ms\n"; color = :light_black)
    for a in d.answers
        printstyled(io, "[", a.id, "] "; bold = true)
        print(io, a.type, "  ", headline(a))
        printstyled(io, "   conf ", round(a.confidence; digits = 2), "\n"; color = :light_black)
        a.type === :noul && continue
        for (l, p) in a.probabilities
            n = isnan(p) ? 0 : round(Int, 24 * p)
            print(io, "    ", "#"^n, "."^(24 - n), "  ", rpad(round(p; digits = 4), 6), "  ", l, "\n")
        end
    end
end

# ── the model file ───────────────────────────────────────────────────────────

"""
    model_kind(path) -> :chat | :typed

What a GGUF is, from its header. Two things make a typed decision model: a
ggmlc graph carrying `laya.*` keys (Laya: its own runner, `TypedSession`), or a
language model that carries a decision template (Nimble: answered from its
logits, `LogitSession`). Everything else is a chat model.
"""
function model_kind(path::AbstractString)
    md = try gguf_header(path) catch; return :chat end
    _is_laya(md) && return :typed
    return get(md, "tokenizer.chat_template.systemone", nothing) isa AbstractString ? :typed : :chat
end

_is_laya(md::AbstractDict) = get(md, "general.architecture", "") == "ggmlc" && haskey(md, "laya.family")
_is_laya(path::AbstractString) = (md = try gguf_header(path) catch; return false end; _is_laya(md))

"""
    typed_info(path) -> NamedTuple

A typed model's own limits, from its GGUF: `family`, `max_len` (tokens per
question, state included), `head_max_len` (the question line and options),
`max_opts`, `max_batch` (questions per forward pass).
"""
function typed_info(path::AbstractString)
    md = gguf_header(path)
    g(k, d) = Int(get(md, "laya.$k", d))
    return (family = String(get(md, "laya.family", "")), name = String(get(md, "laya.model_name", "laya")),
            max_len = g("max_len", 512), head_max_len = g("head_max_len", 192),
            max_opts = g("max_opts", MAX_OPTIONS), max_batch = g("max_batch", 8))
end

# ── the engine ───────────────────────────────────────────────────────────────

"""
    laya_bin() -> String

The `laya` runner: `\$LLAMACHAT_LAYA`, else `laya` on PATH, else
`~/ggmlc/bin/laya`. An error that says so when there is none.
"""
function laya_bin()
    p = get(ENV, "LLAMACHAT_LAYA", "")
    isempty(p) || return p
    w = Sys.which("laya")
    w === nothing || return w
    d = joinpath(homedir(), "ggmlc", "bin", "laya")
    isfile(d) && return d
    error("no `laya` runner: typed decision models need the ggmlc `laya` binary on PATH, " *
          "or its path in \$LLAMACHAT_LAYA")
end

"""`\$LLAMACHAT_LAYA_DEVICE`, else `vulkan:0`, or `cpu` under `GGML_DISABLE_VULKAN`."""
laya_device() = get(ENV, "LLAMACHAT_LAYA_DEVICE", haskey(ENV, "GGML_DISABLE_VULKAN") ? "cpu" : "vulkan:0")

"""
A typed decision model, loaded: a `laya daemon` process this session owns, one
JSON line in and one out per decision. `decide` it; `close!` ends the process.
"""
mutable struct TypedSession
    name::String
    path::String
    proc::Base.Process
    info::NamedTuple
    device::String
    errlog::String                  # the daemon's stderr, for when it dies
    lk::ReentrantLock               # one request on the pipe at a time
    isopen::Bool
    n_decided::Int
end

_errtail(f) = try join(last(readlines(f), 6), "\n") catch; "" end

"""
    TypedSession(model; device = laya_device(), log = stderr)

Load a typed decision model (`laya:typed-decisions`, or a path). Chat keywords
are accepted and ignored, so one call site can open either kind of model.
"""
function TypedSession(model::AbstractString; device::AbstractString = laya_device(),
                      log::IO = stderr, kwargs...)
    path = resolve_model(model)
    _is_laya(path) ||
        error("$model is not a Laya model (LlamaChat.open_model picks the right session for a file)")
    info = typed_info(path)
    print(log, "loading $model … "); flush(log)
    t0 = time()
    errlog = tempname()
    proc = open(pipeline(`$(laya_bin()) daemon $path --device $device`; stderr = errlog), "r+")
    line = readline(proc)
    ready = try _parse_json(line) catch; nothing end
    if !(ready isa ODict && get(ready, "status", "") == "ready")
        try kill(proc) catch end
        tail = _errtail(errlog)
        rm(errlog; force = true)
        error("the laya daemon did not start for $model on $device" *
              (isempty(line) ? "" : ": $line") * (isempty(tail) ? "" : "\n$tail"))
    end
    println(log, "ok  ($(round(time() - t0; digits = 1))s, typed decisions, $(info.family), $device)")
    flush(log)
    return TypedSession(String(model), path, proc, info, String(device), errlog, ReentrantLock(), true, 0)
end

function close!(s::TypedSession)
    s.isopen || return s
    s.isopen = false
    try close(s.proc.in) catch end        # end of input: the daemon exits
    try
        timedwait(() -> !process_running(s.proc), 3.0) === :ok || kill(s.proc)
    catch
    end
    rm(s.errlog; force = true)
    return s
end

function Base.show(io::IO, s::TypedSession)
    print(io, "TypedSession(\"", s.name, "\", ", s.isopen ? "$(s.info.family), $(s.n_decided) decided" : "closed", ")")
end

"""`typed decisions on vulkan:0`: where the model runs, in `placement`'s words."""
placement(s::TypedSession) = "typed decisions on $(s.device)"

"""
    decide(session, state, questions) -> Decisions

Answer `questions` (a `Vector{Question}`, or the JSON object, or its text)
about `state` (an object, a list or plain text). One encoder pass per eight
questions, no generated tokens. The request is checked first: a malformed
question is a `TypedFormatError` naming the field, not a wrong answer.
"""
function decide(s::TypedSession, state, questions::Vector{<:Question})
    s.isopen || error("session is closed")
    for q in questions
        n_options(q) <= s.info.max_opts ||
            _bad("questions.$(q.id).criteria", "has $(n_options(q)) options; $(s.name) takes at most $(s.info.max_opts)")
    end
    req = JSON.json(ODict("state" => state, "questions" => questions_json(questions)))
    line = lock(s.lk) do
        println(s.proc, req)
        flush(s.proc)
        readline(s.proc)
    end
    isempty(line) && error("the laya daemon stopped answering" *
                           (tail = _errtail(s.errlog); isempty(tail) ? "" : "\n$tail"))
    r = _parse_json(line)
    r isa ODict || error("unexpected answer from the laya daemon: $line")
    haskey(r, "error") && error("laya: $(r["error"] isa ODict ? get(r["error"], "message", r["error"]) : r["error"])")
    ans = get(r, "answers", ODict())
    u = get(r, "usage", ODict())
    s.n_decided += 1
    return Decisions(String(get(r, "model", s.info.name)), String(get(r, "family", s.info.family)),
                     [_answer(q, get(ans, q.id, nothing)) for q in questions],
                     Int(get(u, "input_tokens", 0)), Float64(get(u, "latency_ms", NaN)), r)
end
decide(s::TypedSession, state, questions::ODict) = decide(s, state, parse_questions(questions; max_options = s.info.max_opts))
decide(s::TypedSession, state, questions::AbstractString) = decide(s, state, _parse_json(questions))

"""
    decide(session, file::TypedFile) -> Vector{Decisions}

One `Decisions` per state in the file (one for a request, many for a batch).
"""
function decide(s::TypedSession, f::TypedFile)
    isempty(f.questions) && _bad("questions", "this file has a state but no questions")
    isempty(f.states) && _bad("state", "this file has questions but no state")
    return [decide(s, st, f.questions) for st in f.states]
end

"""
    LlamaChat.decide(model, path) -> Vector{Decisions}

Load `model`, run the request or batch file at `path`, free the model.

```julia
LlamaChat.decide("laya:typed-decisions", "harness-step.request.json")[1]["next"].value
```
"""
function decide(model::AbstractString, path::AbstractString)
    f = load_typed(path)
    s = open_model(model; log = devnull)
    s isa ChatSession && (close!(s); error("$model is a chat model, not a typed decision model"))
    try
        return decide(s, f)
    finally
        close!(s)
    end
end

"""
    open_model(name; kwargs...) -> ChatSession | TypedSession | LogitSession

Load whichever kind of model `name` is: a Laya file as a `TypedSession`, a
language model with a decision template as a `LogitSession`, anything else as
a `ChatSession`. `kwargs` are `ChatSession`'s; Laya takes `log` and `device`
and ignores the rest.
"""
function open_model(name::AbstractString; kwargs...)
    path = resolve_model(name)
    _is_laya(path) && return TypedSession(name; kwargs...)
    decision_template(path) === nothing || return LogitSession(name; kwargs...)
    return ChatSession(name; kwargs...)
end

# ── the store ────────────────────────────────────────────────────────────────

"""
    add_model(path, name; root = models_dir()) -> String

Put a local GGUF into LlamaChat's store as `name` (`laya:english`,
`mymodel:q4`): a blob named by its sha256 and a manifest pointing at it, in
ollama's layout, so `list_models`, `resolve_model` and the window's picker see
it like any pulled model.

The blob is a hard link to `path` when both are on one filesystem (no second
copy on disk; either name keeps the data alive), else a copy. Returns the
store's name for it, tag included.
"""
function add_model(path::AbstractString, name::AbstractString; root::AbstractString = models_dir())
    isfile(path) || error("no such file: $path")
    open(io -> read(io, 4) == b"GGUF", path) || error("$path is not a GGUF file")
    ns, model, tag = _split_name(name)
    digest, size = _sha256(path), filesize(path)
    blob = _blob_file(root, digest)
    if !(isfile(blob) && filesize(blob) == size)
        mkpath(dirname(blob))
        rm(blob; force = true)
        try
            hardlink(abspath(path), blob)
        catch
            _copy_blob(path, blob, size)
        end
    end
    manifest = JSON.json(ODict(
        "schemaVersion" => 2,
        "mediaType" => "application/vnd.docker.distribution.manifest.v2+json",
        "layers" => [ODict("mediaType" => "application/vnd.ollama.image.model",
                           "digest" => digest, "size" => size)]))
    mpath = joinpath(root, "manifests", REGISTRY, ns, model, tag)
    mkpath(dirname(mpath))
    write(mpath * ".tmp", manifest)
    mv(mpath * ".tmp", mpath; force = true)
    return (ns == "library" ? "" : ns * "/") * model * ":" * tag
end

"""Where the Laya GGUFs are: `\$LLAMACHAT_LAYA_MODELS`, else `~/ggmlc/models`."""
laya_models_dir() = get(ENV, "LLAMACHAT_LAYA_MODELS", joinpath(homedir(), "ggmlc", "models"))

"""
    bring_laya(; from = laya_models_dir(), root = models_dir()) -> Vector{String}

Add every Laya GGUF under `from` to the store as `laya:<family>`
(`laya:english`, `laya:typed-decisions`, …), the family read from each file's
header. Returns the names added. Run again after downloading another family.
"""
function bring_laya(; from::AbstractString = laya_models_dir(), root::AbstractString = models_dir())
    isdir(from) || error("no Laya models folder at $from (set \$LLAMACHAT_LAYA_MODELS)")
    out = String[]
    for f in sort!(filter(f -> endswith(f, ".gguf"), readdir(from; join = true)))
        model_kind(f) === :typed || continue
        push!(out, add_model(f, "laya:" * typed_info(f).family; root = root))
    end
    isempty(out) && error("no Laya GGUF under $from")
    return out
end
