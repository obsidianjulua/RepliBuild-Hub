# Headless use: a one-shot reply and a benchmark, both plain text, no window and
# no markdown redraw. For scripts, for comparing settings, and for an agent
# that has to read the output rather than look at it.

"""
    LlamaChat.reply(model, prompt; max_tokens = 4096, kwargs...) -> Response

Load `model`, answer `prompt` once, free the model. Nothing is printed; the
reply is `r.text`, the numbers are on the `Response`. Keywords are
`ChatSession`'s (`think`, `temp`, `n_ctx`, `kv_type`, …).

```julia
r = LlamaChat.reply("qwen3:4b", "Name three moons of Jupiter."; think = false)
print(r.text)
```
"""
function reply(model::AbstractString, prompt::AbstractString; max_tokens::Integer = 4096, kwargs...)
    s = ChatSession(model; log = devnull, kwargs...)
    try
        return chat(s, prompt; max_tokens = max_tokens, stream = false, io = devnull)
    finally
        close!(s)
    end
end

# A long prompt that reads like what people paste: this package's own source.
function _filler(s::ChatSession, n_tok::Integer)
    io = IOBuffer()
    files = sort!(filter(f -> endswith(f, ".jl"), readdir(@__DIR__; join = true)))
    while true
        for f in files
            write(io, read(f, String))
            text = String(take!(copy(io)))
            length(_tokenize(s, text, false)) >= n_tok && return _trim_to(s, text, n_tok)
        end
    end
end

function _trim_to(s::ChatSession, text::AbstractString, n_tok::Integer)
    toks = _tokenize(s, text, false)
    lo, hi = 1, ncodeunits(text)
    while lo < hi                       # the longest prefix with ≤ n_tok tokens
        mid = prevind(text, (lo + hi + 1) ÷ 2)
        mid <= lo && break
        length(_tokenize(s, text[1:mid], false)) <= n_tok ? (lo = mid) : (hi = prevind(text, mid))
    end
    return text[1:lo]
end

const _BENCH_ASK = "Count from 1 to 400, separated by commas. Output only the numbers."

"""
    LlamaChat.bench(model; depth = 8192, gen = 256, kwargs...) -> NamedTuple

Load `model` with `kwargs` (`n_batch`, `n_ctx`, `kv_type`, …, as
`ChatSession`) and measure, headless, at `temp = 0` with thinking off:

  * `load_s`, and VRAM used (`vram_gib`, from the Vulkan budget before/after)
  * `gen0`: generation tok/s on a fresh context
  * `pp`:   prefill tok/s on a `depth`-token paste (this package's source)
  * `genD`: generation tok/s right after it, with `depth` tokens in context

A depth that does not fit the window is skipped (`pp`/`genD` are `NaN`).
Prints one line to `io`; returns every number. One model at a time: it loads,
measures and frees before returning.
"""
function bench(model::AbstractString; depth::Integer = 8192, gen::Integer = 256,
               io::IO = stdout, kwargs...)
    _ensure_backend(false)
    free0 = something(_live_vram_free(), 0)
    t0 = time()
    s = ChatSession(model; log = devnull, think = false, temp = 0.0, kwargs...)
    load_s = time() - t0
    try
        vram = (free0 - something(_live_vram_free(), free0)) / _GiB
        r0 = chat(s, _BENCH_ASK; max_tokens = gen, stream = false, io = devnull)
        gen0 = r0.n_gen / r0.t_gen
        pp = genD = NaN
        nD = 0
        if depth > 0 && depth + gen + 256 < s.n_ctx
            reset!(s)
            text = _filler(s, depth) * "\n\n" * _BENCH_ASK
            r1 = chat(s, text; max_tokens = gen, stream = false, io = devnull)
            pp = r1.n_prompt / r1.t_prompt
            genD = r1.n_gen / r1.t_gen
            nD = r1.n_prompt
        end
        # After the deep run: without flash attention the attention scores are
        # materialised, so a long context can grow the compute buffer past
        # what the load reserved. This is the number that says whether it did.
        vram_peak = (free0 - something(_live_vram_free(), free0)) / _GiB
        res = (model = String(model), n_ctx = s.n_ctx, n_batch = s.n_batch,
               kv_type = s.kv_type, flash_attn = s.flash_attn,
               placement = placement(s), load_s = load_s,
               vram_gib = vram, vram_after = vram_peak, gen0 = gen0, n_gen0 = r0.n_gen, pp = pp,
               depth = nD, genD = genD)
        println(io, _bench_line(res))
        return res
    finally
        close!(s)
    end
end

_r1(x) = isnan(x) ? "   –  " : lpad(string(round(x; digits = 1)), 6)

function _bench_line(r)
    rpad(r.model, 14) * " ctx " * lpad(r.n_ctx, 6) * "  batch " * lpad(r.n_batch, 4) *
    "  kv " * rpad(String(r.kv_type), 4) * "  fa " * rpad(String(r.flash_attn), 4) * "  vram " * lpad(round(r.vram_gib; digits = 1), 4) *
    "→" * rpad(round(r.vram_after; digits = 1), 4) * " GiB  load " * lpad(round(r.load_s; digits = 1), 4) * " s  gen " * _r1(r.gen0) *
    "  pp " * _r1(r.pp) * " @" * lpad(r.depth, 5) * "  gen@depth " * _r1(r.genD) *
    "  (" * r.placement * ")"
end

"""
    LlamaChat.sweep(model; n_batch = (512, 2048), kv_type = (:f16, :q8_0), kwargs...) -> Vector

`bench` once per combination, each in a fresh load. Every other keyword goes
to `bench` (and through it to `ChatSession`). Returns the rows.
"""
function sweep(model::AbstractString; n_batch = (512, 2048), kv_type = (:f16, :q8_0),
               io::IO = stdout, kwargs...)
    rows = NamedTuple[]
    for kt in kv_type, nb in n_batch
        try
            push!(rows, bench(model; n_batch = nb, kv_type = kt, io = io, kwargs...))
        catch e
            e isa InterruptException && rethrow()
            println(io, rpad(model, 14), " batch ", nb, " kv ", kt, ": ", sprint(showerror, e))
        end
    end
    return rows
end
