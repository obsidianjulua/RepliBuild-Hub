# plan.jl — decide n_gpu_layers from the model's real shape and a VRAM budget.
#
# WHY THIS IS NOT JUST `n_gpu_layers = 99`
# ----------------------------------------
# llama.cpp does not fit-to-available. Ask it for more layers than the card can
# hold and it attempts the allocation and dies — and on the Vulkan path that is
# a GGML_ASSERT abort, which takes the whole Julia process with it, REPL and
# all. There is no exception to catch. So the decision has to be made before the
# load, from numbers, not by trying it and recovering.
#
# The numbers are not optional either, because weights are the smaller half of
# the story at long context. qwen3:4b is 2.32 GiB of weights and 144 KiB/token
# of KV cache — at the default n_ctx of 32768 that is 4.5 GiB of cache on top,
# i.e. the cache is TWICE the model. A size-of-file check would have called it a
# comfortable fit and then aborted the process.
#
# WHERE THE SHAPE COMES FROM
# --------------------------
# GGUF's own header. llama.h has a `no_alloc` model param documented as "only
# load metadata and simulate memory allocations", which looks purpose-built for
# this — but `llama_model_load_from_file` with it set trips
# `GGML_ASSERT(!ml.no_alloc)` (llama-model.cpp:1570) and aborts. It is for an
# internal path, not this one. Reading the header directly costs a few KB and
# cannot abort the process.

# ── GGUF header ──────────────────────────────────────────────────────────────

const _GGUF_SZ = Dict{UInt32,Int}(0=>1, 1=>1, 2=>2, 3=>2, 4=>4, 5=>4, 6=>4,
                                  7=>1, 10=>8, 11=>8, 12=>8)

_gguf_str(io) = String(read(io, read(io, UInt64)))

function _gguf_skip_value(io, t::UInt32)
    if t == 8
        _gguf_str(io)
    elseif t == 9                      # array: elem type, count, elems
        et = read(io, UInt32); n = read(io, UInt64)
        if et == 8
            for _ in 1:n; _gguf_str(io); end
        elseif et == 9
            error("GGUF: nested arrays unsupported")
        else
            skip(io, _GGUF_SZ[et] * n)
        end
    else
        skip(io, _GGUF_SZ[t])
    end
    return nothing
end

function _gguf_read_value(io, t::UInt32)
    t == 8 && return _gguf_str(io)
    t == 9 && (_gguf_skip_value(io, t); return nothing)
    T = t == 0  ? UInt8   : t == 1  ? Int8    :
        t == 2  ? UInt16  : t == 3  ? Int16   :
        t == 4  ? UInt32  : t == 5  ? Int32   :
        t == 6  ? Float32 : t == 7  ? Bool    :
        t == 10 ? UInt64  : t == 11 ? Int64   :
        t == 12 ? Float64 : error("GGUF: unknown value type $t")
    return read(io, T)
end

"""
    gguf_header(path) -> Dict{String,Any}

Scalar + string metadata from a GGUF file's header. Arrays are skipped: the only
array in a typical header is the tokenizer vocabulary, which is both enormous and
irrelevant here, and skipping it is the difference between reading kilobytes and
reading hundreds of megabytes.
"""
function gguf_header(path::AbstractString)
    open(path, "r") do io
        magic = read(io, 4)
        magic == b"GGUF" || error("not a GGUF file (magic $(String(copy(magic)))): $path")
        version = read(io, UInt32)
        version in (2, 3) || error("GGUF version $version unsupported (need 2 or 3): $path")
        skip(io, 8)                                 # tensor_count
        nkv = read(io, UInt64)

        md = Dict{String,Any}()
        for _ in 1:nkv
            k = _gguf_str(io)
            t = read(io, UInt32)
            v = _gguf_read_value(io, t)
            v === nothing || (md[k] = v)
        end
        return md
    end
end

"""
    model_shape(path) -> NamedTuple

The four numbers that decide placement, plus MoE facts.

`key_length`/`value_length` are read explicitly rather than derived as
`embedding_length ÷ head_count`. For qwen3:4b that derivation gives 80 where the
truth is 128 — a 1.6× underestimate of every KV byte, which at 32k context is
1.7 GiB of cache the planner would not have known about.
"""
function model_shape(path::AbstractString)
    md   = gguf_header(path)
    arch = get(md, "general.architecture", "")
    g(suffix, default=nothing) = begin
        v = get(md, "$arch.$suffix", nothing)
        v === nothing ? default : Int(v)
    end

    n_layer = g("block_count")
    if n_layer === nothing
        # ollama's blob store mixes projectors in with language models — a
        # `clip` blob is the vision half of a multimodal pair and has no
        # block_count under its own arch. Naming that is worth more than
        # "no clip.block_count", which reads like a corrupt file.
        arch in ("clip", "mmproj") && error("""
            $(basename(path)) is a `$arch` blob — the vision/projector half of a
            multimodal model, not a language model. It has no transformer block
            count to plan against. Point LlamaChat at the text model instead.""")
        error("GGUF: no `$arch.block_count` in $path — cannot determine layer count")
    end
    n_head    = g("attention.head_count", 0)
    n_head_kv = g("attention.head_count_kv", n_head)
    n_embd    = g("embedding_length", 0)
    # Fall back to the derivation only when the explicit keys are absent.
    k_len = g("attention.key_length",   n_head > 0 ? n_embd ÷ n_head : 0)
    v_len = g("attention.value_length", n_head > 0 ? n_embd ÷ n_head : 0)

    n_expert = g("expert_count", 0)

    return (arch = String(arch), n_layer = n_layer, n_head = n_head,
            n_head_kv = n_head_kv, n_embd = n_embd, k_len = k_len, v_len = v_len,
            n_expert = n_expert, is_moe = n_expert > 0,
            file_bytes = filesize(path))
end

# ── Budgets ──────────────────────────────────────────────────────────────────

const _GiB = 1024.0^3

# Deliberately BELOW the card's 7.94 GiB. The Vulkan heap reports ~7.14 GiB of
# budget, the compositor holds some of it, and overshooting is an abort rather
# than a swap. 5 GiB leaves that margin without being so tight it refuses models
# that clearly fit.
_vram_budget() = parse(Float64, get(ENV, "LLAMACHAT_VRAM_GB", "5")) * _GiB
_ram_budget()  = parse(Float64, get(ENV, "LLAMACHAT_RAM_GB",  "35")) * _GiB

# Compute buffers scale with n_batch, not n_ctx: measured 301.75 MiB on Vulkan0
# plus 11.02 MiB host for qwen3:4b at n_batch=512. Rounded up to 0.5 GiB because
# being wrong in this direction costs headroom and being wrong in the other
# costs the process.
const _COMPUTE_RESERVE = 0.5 * _GiB

"""
    kv_bytes(shape, n_ctx; bits = 16) -> Int

Bytes of KV cache for `n_ctx` tokens. K and V are stored per KV-head per layer,
so this is `2 × n_layer × n_head_kv × (k_len + v_len)/2 × n_ctx × bytes`, which
reduces to the form below. llama.cpp's default cache type is F16.
"""
kv_bytes(s, n_ctx::Integer; bits::Integer = 16) =
    Int(s.n_layer) * Int(s.n_head_kv) * (Int(s.k_len) + Int(s.v_len)) *
    Int(n_ctx) * (bits ÷ 8)

"""
    plan_offload(path; n_ctx, requested = nothing) -> NamedTuple

Decide `n_gpu_layers`. Returns `(ngl, why, vram_needed, kv, weights, shape,
max_ctx_on_gpu)`.

`requested === nothing` means AUTO: place as many layers on the GPU as the VRAM
budget holds, all-or-nothing at the top end (a full offload is worth far more
than one layer short of it, because a single CPU layer per token serializes the
whole pipeline).

A `requested` value is honoured but CHECKED — see `check_request`.
"""
function plan_offload(path::AbstractString; n_ctx::Integer, requested = nothing)
    s        = model_shape(path)
    weights  = s.file_bytes
    kv       = kv_bytes(s, n_ctx)
    full     = weights + kv + _COMPUTE_RESERVE
    budget   = _vram_budget()

    # Largest n_ctx that would let the whole model sit on the GPU. Reported so a
    # refusal can say "or lower n_ctx to this" instead of only saying no.
    per_tok  = kv_bytes(s, 1)
    max_ctx  = per_tok > 0 ? max(0, Int((budget - weights - _COMPUTE_RESERVE) ÷ per_tok)) : 0

    if requested !== nothing
        return (ngl = Int(requested), why = :requested, vram_needed = full,
                kv = kv, weights = weights, shape = s, max_ctx_on_gpu = max_ctx)
    end

    if full <= budget
        return (ngl = 99, why = :fits, vram_needed = full, kv = kv,
                weights = weights, shape = s, max_ctx_on_gpu = max_ctx)
    end

    # Does not fit whole. Partial offload is possible — llama.cpp takes any
    # n_gpu_layers — but each CPU-resident layer is a full round trip per token,
    # so a mostly-GPU split is not "mostly GPU speed". Offer it only when it is
    # a clear majority of the model, otherwise CPU is the honest answer.
    #
    # The per-layer figure is an AVERAGE and therefore optimistic: token
    # embeddings and the output head are not repeating layers, so dividing total
    # weights by n_layer under-counts what the GPU actually takes on. The
    # full-fit branch above does not care — it measures the whole file — but
    # this one would creep over the budget, and over the budget is an abort.
    # Hence the 0.9: spend nine tenths of the headroom, keep one in reserve.
    per_layer = (weights + kv) / s.n_layer
    usable    = 0.9 * (budget - _COMPUTE_RESERVE)
    k = per_layer > 0 ? Int(floor(usable / per_layer)) : 0
    k = clamp(k, 0, s.n_layer)

    if k >= (3 * s.n_layer) ÷ 4
        return (ngl = k, why = :partial, vram_needed = full, kv = kv,
                weights = weights, shape = s, max_ctx_on_gpu = max_ctx)
    end

    return (ngl = 0, why = :too_big, vram_needed = full, kv = kv,
            weights = weights, shape = s, max_ctx_on_gpu = max_ctx)
end

_gib(x) = round(x / _GiB, digits = 2)

"""
    check_request(plan, path, n_ctx)

Refuse an explicit `n_gpu_layers` that the budget cannot hold.

This is an ERROR rather than a warning on purpose. The failure it prevents is a
`GGML_ASSERT` inside ggml-vulkan, which calls `abort()` — the REPL, the loaded
model, and any unsaved session state go with it. A warning that is followed one
second later by process death is not a warning.
"""
function check_request(p, path::AbstractString, n_ctx::Integer)
    p.why === :requested || return
    p.ngl == 0 && return                       # CPU is always allowed
    budget = _vram_budget()
    p.vram_needed <= budget && return

    s = p.shape
    error("""
    n_gpu_layers = $(p.ngl) does not fit the VRAM budget.

      model          $(basename(path))
      weights        $(_gib(p.weights)) GiB
      KV @ n_ctx=$(n_ctx)  $(_gib(p.kv)) GiB   ($(s.n_layer) layers × $(s.n_head_kv) kv-heads × $(s.k_len + s.v_len) dims, F16)
      compute        $(_gib(_COMPUTE_RESERVE)) GiB
      ─ required     $(_gib(p.vram_needed)) GiB
      ─ budget       $(_gib(budget)) GiB   (\$LLAMACHAT_VRAM_GB)

    Refusing rather than warning: llama.cpp does not fit-to-available, and an
    over-commit on the Vulkan backend is a GGML_ASSERT abort that kills this
    process outright.

    Options:
      • n_ctx = $(p.max_ctx_on_gpu) or less would fit the whole model on the GPU
      • n_gpu_layers = 0 runs on CPU ($(_gib(p.weights)) GiB of $(_gib(_ram_budget())) GiB RAM budget)
      • raise the budget if you know the card has room:
          LLAMACHAT_VRAM_GB=7 …$(s.is_moe ? "\n      • this is an MoE ($(s.n_expert) experts) — expert-offload to CPU would\n        fit the attention layers on the GPU and keep the experts in RAM" : "")""")
end

"""
    plan_note(p, n_ctx) -> String | nothing

The one line worth printing when the user did NOT ask for verbose: why this run
is not on the GPU, and what would put it there.

`nothing` when the model went to the GPU whole — that is the expected case and
needs no commentary. But a silent fall back to CPU is precisely the failure that
motivated this file: the Vulkan backend initializes, the card gets opened, two
DRI fds appear, and the weights go to system RAM anyway. From the outside that
is indistinguishable from a broken GPU build.
"""
function plan_note(p, n_ctx::Integer)
    p.why === :fits && return nothing
    p.why === :requested && return nothing         # they chose; check_request vetted it

    # The expert-offload advisory belongs on BOTH incomplete outcomes, not just
    # the CPU one. A partial split is the case where it helps most: the experts
    # are the bulk and are touched sparsely, so moving them to RAM is what would
    # let the remaining attention layers onto the card.
    moe = p.shape.is_moe ?
        "; MoE ($(p.shape.n_expert) experts) — expert-offload to CPU would help" : ""

    if p.why === :too_big
        hint = p.max_ctx_on_gpu > 0 ?
            "n_ctx ≤ $(p.max_ctx_on_gpu) would fit it on the GPU" :
            "too large for the GPU at any context"
        return string("gpu-plan: CPU — needs ", _gib(p.vram_needed), " GiB vs ",
                      _gib(_vram_budget()), " GiB budget at n_ctx=", n_ctx,
                      "; ", hint, moe)
    end
    return string("gpu-plan: ", p.ngl, "/", p.shape.n_layer,
                  " layers on GPU — ", _gib(p.vram_needed), " GiB needed vs ",
                  _gib(_vram_budget()), " GiB budget", moe)
end

"""
    describe_plan(p, path, n_ctx) -> String

One line, printed at load. Says what was decided and why, because a silent
placement decision is one the user cannot notice is wrong.
"""
function describe_plan(p, path::AbstractString, n_ctx::Integer)
    s = p.shape
    tag = p.why === :fits      ? "fits" :
          p.why === :partial   ? "partial" :
          p.why === :too_big   ? "too big for VRAM" : "requested"
    moe = s.is_moe ? ", MoE/$(s.n_expert)e" : ""
    string("gpu-plan: n_gpu_layers=", p.ngl, " ($tag) — ",
           _gib(p.weights), " GiB weights + ", _gib(p.kv), " GiB KV@", n_ctx,
           " + ", _gib(_COMPUTE_RESERVE), " GiB compute = ", _gib(p.vram_needed),
           " GiB vs ", _gib(_vram_budget()), " GiB budget [", s.arch, "/",
           s.n_layer, "L", moe, "]")
end
