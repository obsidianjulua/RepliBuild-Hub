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

function _gguf_skip_elems(io, et::UInt32, n::Integer)
    if et == 8
        for _ in 1:n; _gguf_str(io); end
    elseif et == 9
        error("GGUF: nested arrays unsupported")
    else
        skip(io, _GGUF_SZ[et] * n)
    end
    return nothing
end

function _gguf_skip_value(io, t::UInt32)
    if t == 8
        _gguf_str(io)
    elseif t == 9                      # array: elem type, count, elems
        et = read(io, UInt32); n = read(io, UInt64)
        _gguf_skip_elems(io, et, n)
    else
        skip(io, _GGUF_SZ[t])
    end
    return nothing
end

# GGUF integer element types, for the per-layer arrays below.
const _GGUF_INT = Dict{UInt32,DataType}(0 => UInt8, 1 => Int8, 2 => UInt16, 3 => Int16,
                                        4 => UInt32, 5 => Int32, 10 => UInt64, 11 => Int64)

function _gguf_read_value(io, t::UInt32)
    t == 8 && return _gguf_str(io)
    if t == 9
        # A short integer array is a per-layer value: a hybrid model's
        # `head_count_kv` is one ([0,2,…] for qwen3.6, 0 on a linear-attention
        # layer). Anything else (the vocabulary, token types) is skipped.
        et = read(io, UInt32); n = read(io, UInt64)
        if haskey(_GGUF_INT, et) && n <= 4096
            return Int[read(io, _GGUF_INT[et]) for _ in 1:n]
        end
        # A per-layer flag array: Gemma 4's `sliding_window_pattern`.
        et == 7 && n <= 4096 && return Bool[read(io, Bool) for _ in 1:n]
        _gguf_skip_elems(io, et, n)
        return nothing
    end
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

Scalar + string metadata from a GGUF file's header, and short integer arrays
(per-layer values, `Vector{Int}`). Long arrays are skipped: the tokenizer
vocabulary is the big one, and skipping it is the difference between reading
kilobytes and reading hundreds of megabytes. Its LENGTH is kept, as
`"tokenizer.ggml.tokens.length"`: n_vocab sizes the compute buffer (see
`compute_reserve`), and few GGUFs carry `<arch>.vocab_size`.
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
            if k == "tokenizer.ggml.tokens" && t == 9
                et = read(io, UInt32); n = read(io, UInt64)
                md["tokenizer.ggml.tokens.length"] = Int(n)
                _gguf_skip_elems(io, et, n)
                continue
            end
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

Cached per file (path, size, mtime). The header walk skips a quarter-million
vocabulary strings, 48 ms for qwen3.8:27b, and deciding flash attention, batch
and window asks for the shape some thirty times: 1.05 s of a load, before the
cache, spent re-reading the same header.
"""
function model_shape(path::AbstractString)
    st  = stat(path)
    key = (String(path), Int(st.size), Float64(st.mtime))
    return lock(_SHAPE_LOCK) do
        get!(() -> _model_shape(path), _SHAPES, key)
    end
end

const _SHAPES     = Dict{Tuple{String,Int,Float64},Any}()
const _SHAPE_LOCK = ReentrantLock()

function _model_shape(path::AbstractString)
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
    n_embd    = g("embedding_length", 0)

    # KV heads per layer. A hybrid model (qwen35, qwen35moe, qwen3next) keeps a
    # KV cache only on its full-attention layers; the rest are linear attention
    # (Gated DeltaNet) with a fixed recurrent state instead. qwen3.6 states it as
    # an array, `head_count_kv = [0,0,0,2, …]`; qwen3.8 gives a scalar 4 and
    # `full_attention_interval = 4`, and llama.cpp makes layer `il` recurrent
    # unless `(il + 1) % 4 == 0`. Counting every layer at the scalar (or at
    # `head_count`, the fallback when the array was skipped) made qwen3.6's cache
    # 640 KiB/token where llama.cpp allocates 20: 20 GiB at 32k against 0.63.
    hkv = get(md, "$arch.attention.head_count_kv", nothing)
    interval = g("full_attention_interval", 0)
    kv_heads = if hkv isa AbstractVector
        length(hkv) == n_layer || error("GGUF: $arch.attention.head_count_kv has $(length(hkv)) entries for $n_layer layers")
        Int.(hkv)
    else
        h = hkv === nothing ? n_head : Int(hkv)
        [interval > 0 && (il + 1) % interval != 0 ? 0 : h for il in 0:n_layer-1]
    end
    n_head_kv = maximum(kv_heads; init = 0)
    # Fall back to the derivation only when the explicit keys are absent.
    k_len = g("attention.key_length",   n_head > 0 ? n_embd ÷ n_head : 0)
    v_len = g("attention.value_length", n_head > 0 ? n_embd ÷ n_head : 0)

    # Sliding-window layers (Gemma 4: 25 of 30). llama.cpp caches only
    # min(n_ctx, pad256(n_swa + n_ubatch)) cells for them, with their own head
    # sizes, so they cost a fixed amount rather than a per-token one. Counted
    # at full context, gemma4:26b's cache came out 430 KiB/token against a true
    # 20 KiB plus ~0.6 GiB, and the planner opened it at 10240 where 32768 fits.
    # The pattern is per layer (true = sliding); a scalar N means every Nth
    # layer is full, as llama.cpp's set_swa_pattern reads it.
    n_swa = g("attention.sliding_window", 0)
    pat = get(md, "$arch.attention.sliding_window_pattern", nothing)
    swa = if n_swa <= 0 || pat === nothing
        falses(n_layer)
    elseif pat isa AbstractVector
        length(pat) == n_layer || error("GGUF: $arch.attention.sliding_window_pattern has $(length(pat)) entries for $n_layer layers")
        BitVector(Bool.(pat))
    else
        N = Int(pat)
        BitVector([N > 0 && (il + 1) % N != 0 for il in 0:n_layer-1])
    end
    k_len_swa = g("attention.key_length_swa", k_len)
    v_len_swa = g("attention.value_length_swa", v_len)

    n_expert = g("expert_count", 0)
    n_vocab  = Int(get(md, "tokenizer.ggml.tokens.length", g("vocab_size", 0)))

    # A recurrent layer's state, per sequence, in f32: llama.cpp's n_embd_r (the
    # conv window) plus n_embd_s (the SSM state). Zero for a plain transformer.
    n_rec = count(==(0), kv_heads)
    d_conv, d_inner = g("ssm.conv_kernel", 0), g("ssm.inner_size", 0)
    d_state, n_group = g("ssm.state_size", 0), g("ssm.group_count", 0)
    rs_per_layer = d_inner > 0 ?
        (max(d_conv - 1, 0) * (d_inner + 2 * n_group * d_state) + d_state * d_inner) * 4 : 0

    return (arch = String(arch), n_layer = n_layer, n_head = n_head,
            n_head_kv = n_head_kv, kv_heads = kv_heads,
            n_kv_layers = n_layer - n_rec, n_embd = n_embd, k_len = k_len, v_len = v_len,
            n_swa = n_swa, swa = swa, k_len_swa = k_len_swa, v_len_swa = v_len_swa,
            n_expert = n_expert, is_moe = n_expert > 0, n_vocab = n_vocab,
            rs_bytes = n_rec * rs_per_layer,
            file_bytes = filesize(path))
end

# ── Budgets ──────────────────────────────────────────────────────────────────

const _GiB = 1024.0^3

# The card is an Arc Pro B60 (BMG-G21, Battlemage) on xe, since 2026-11-08: a
# 23.91 GiB device-local heap, of which Mesa's VK_EXT_memory_budget reports
# ~21.08 GiB free with the desktop up (88%; the A750 before it showed the same
# ratio, 7.14 of 7.94). Overshooting is still an abort rather than a swap.
#
# So the budget is that live figure, less a margin, read from ggml's own device
# query (the Vulkan backend answers it from the same extension). A constant could
# only be right for an idle desktop: a game or a second loaded model holding VRAM
# would make it an over-commit. `$LLAMACHAT_VRAM_GB` still overrides, and before
# the backend is up (or with no GPU device) the B60's figure stands in.
const _VRAM_MARGIN     = 0.5 * _GiB
const _B60_BUDGET_GIB  = 20.5

"""
    _live_vram_free() -> Union{Int, Nothing}

Free VRAM on the GPU, as ggml's Vulkan backend reports it
(`ggml_backend_dev_memory`: the heap's budget less this process's usage).
`nothing` before `llama_backend_init` or when no GPU device is registered
(`GGML_DISABLE_VULKAN=1`).
"""
function _live_vram_free()
    _backend_up[] || return nothing
    best = nothing
    for i in 0:Int(L.ggml_backend_dev_count()) - 1
        d = L.ggml_backend_dev_get(i)
        L.ggml_backend_dev_type(d) == L.GGML_BACKEND_DEVICE_TYPE_GPU || continue
        free, total = Ref{Csize_t}(0), Ref{Csize_t}(0)
        L.ggml_backend_dev_memory(d, free, total)
        free[] > 0 && (best = max(something(best, 0), Int(free[])))
    end
    return best
end

function _vram_budget()
    haskey(ENV, "LLAMACHAT_VRAM_GB") && return parse(Float64, ENV["LLAMACHAT_VRAM_GB"]) * _GiB
    live = _live_vram_free()
    return live === nothing ? _B60_BUDGET_GIB * _GiB : max(live - _VRAM_MARGIN, 0.0)
end
_ram_budget()  = parse(Float64, get(ENV, "LLAMACHAT_RAM_GB",  "35")) * _GiB

# Compute buffers scale with n_batch (= n_ubatch here) and n_vocab, not n_ctx.
# llama.cpp reserves the graph for a full ubatch of outputs, so the logits node,
# n_batch × n_vocab × f32, is most of it. Vulkan0 compute buffer, B60, b10286,
# flash-attn auto (2026-11-11):
#
#   model         n_vocab   n_batch=512   n_batch=2048
#   qwen3:4b      151936     301.75 MiB    1615.05 MiB
#   qwen3-coder   151936     300.75 MiB    1643.05 MiB
#   gemma4:26b    262144     535.66 MiB    2512.08 MiB
#   qwen3.8:27b   248320     505.00 MiB    2604.19 MiB
#
# Beyond the logits the largest overshoot is qwen3.8's 0.324 MiB/token at 2048,
# so the reserve is logits + 0.375 MiB/token, floored at the old flat 0.5 GiB.
# The flat 0.5 GiB alone was already short for gemma4 at 512 (535.66 MiB) and
# ~1.1–2.1 GiB short at 2048. Round up: being wrong in this direction costs
# headroom, and being wrong in the other costs the process.
const _COMPUTE_RESERVE   = 0.5 * _GiB
const _COMPUTE_PER_TOKEN = 0.375 * 1024^2

# n_batch (= n_ubatch). Bigger is faster prefill, 2048 against 512 on the B60,
# b10286 (generation unchanged):
#
#   qwen3:4b       1072 → 1493 tok/s   (2,680-token prompt)
#   qwen3-coder     648 → 1143         (2,680)
#   gemma4:26b      504 →  818         (2,977)
#   qwen3.8:27b     327 →  441         (2,774)
#
# and costs VRAM (`compute_reserve`), which on a full card comes out of the
# context window: at a 20.6 GiB budget, 2048 cuts qwen3-coder's auto window
# 30720 → 15360 and leaves gemma4:26b no GPU fit at all. So `auto_batch` steps
# down from the top and takes the first size that costs no window.
#
# Below 512 only pays with flash attention OFF, where the attention scores
# scale with n_batch × n_ctx and 256 can hold them in one copy where 512 needs
# two (`attn_scores_bytes`). qwen3.8:27b, flash attention off, 8k paste:
#
#   n_batch   window   prefill   gen at 8k
#     512     26624     326       15.7       (the window 512 leaves room for)
#     256     32768     290       15.7
#     128     32768     245       15.7
#
# With flash attention on the buffer does not depend on n_ctx, and 512 is
# already under the reserve's floor for most vocabularies: nothing to gain.
const _BATCH_STEPS = (2048, 1024, 512, 256)
const _BATCH_BASE  = 512              # the reference window; also forced-ngl's batch
"""The smallest batch `auto_batch` will pick: 256 with flash attention off, else 512."""
_batch_floor(flash_attn::Symbol) = flash_attn === :off ? 256 : _BATCH_BASE
const _N_BATCH     = _BATCH_BASE      # what plan_offload/auto_ctx assume unless told

"""
    compute_reserve(shape, n_batch) -> Float64

Bytes of VRAM to hold back for llama.cpp's compute buffer at this `n_batch`.
"""
compute_reserve(s, n_batch::Integer) =
    max(_COMPUTE_RESERVE, Int(n_batch) * (4.0 * s.n_vocab + _COMPUTE_PER_TOKEN))

"""
    attn_scores_bytes(shape, n_batch, n_ctx, flash_attn) -> Float64

Compute-buffer bytes attention adds WITHOUT flash attention: the scores,
n_ubatch × n_kv × n_head in f32, which llama.cpp reserves for a full window.
Zero with flash attention, which never materialises them.

How many copies depends on the tensor's size. Up to 768 MiB the softmax reuses
the scores' own buffer and the graph holds ONE copy (plus the mask, about 12
bytes per cell); from 1 GiB it holds TWO. Vulkan0 compute buffer, B60, b10286,
flash attention off (2026-11-12; the 4194/4228 rows 2026-11-11):

    model        heads  n_batch  n_ctx   llama.cpp     one copy (4·nb·ctx·heads)
    qwen3:4b       32     512     8192    562.01 MiB     512   → ×1 (+50)
    qwen3:4b       32     256    16384    545.00         512   → ×1 (+33)
    qwen3:4b       32     512    16384   2114.01        1024   → ×2 (+66)
    qwen3:4b       32     512    32768   4194.01        2048   → ×2 (+98)
    qwen3:4b       32    1024    16384   4228.02        2048   → ×2 (+132)
    qwen3-coder    32     512     8192    556.01         512   → ×1
    qwen3-coder    32     512    16384   2140.50        1024   → ×2
    gemma4:26b     16     512    16384    608.01         512   → ×1 (+96)
    qwen3.8:27b    24     256    16384    432.01         384   → ×1 (+48)
    qwen3.8:27b    24     512    16384    864.01         768   → ×1 (+96)
    qwen3.8:27b    24     256    32768    832.01         768   → ×1 (+64)

Nothing was measured between 768 MiB and 1 GiB, so that range counts as two.
The one-copy case is why a small batch matters with flash attention off:
qwen3.8:27b at 256 keeps its whole 32768 window for 0.83 GiB of buffer, where
512 would take two copies of 1.5 GiB. At 2048/32768 qwen3:4b's would be 16 GiB,
more than the card: that run did not abort, it crawled (prefill 35 tok/s at
24k), so the planner has to know.
"""
function attn_scores_bytes(s, n_batch::Integer, n_ctx::Integer, flash_attn::Symbol)
    flash_attn === :off || return 0.0
    cells = Float64(n_batch) * Float64(n_ctx)
    one = 4.0 * s.n_head * cells
    return one <= _SCORES_ONE_COPY ? one + _SCORES_MASK * cells : 2one
end

# The largest scores tensor seen held as a single copy, and the per-cell bytes
# the graph holds beside it (the largest measured: 12.0, qwen3.8 at 512/16384).
const _SCORES_ONE_COPY = 768.0 * 1024^2
const _SCORES_MASK     = 12.0

"""
Bytes per cached K or V element, by cache type (`ChatSession`'s `kv_type`).
q8_0 and q4_0 store 32 values in 34 and 18 bytes.
"""
const _KV_ELT_BYTES = Dict(:f16 => 2.0, :q8_0 => 34 / 32, :q4_0 => 18 / 32)

"""Cells llama.cpp gives a sliding-window layer: the window plus a ubatch, padded."""
_swa_cells(s, n_ctx::Integer, n_batch::Integer) =
    min(Int(n_ctx), cld(Int(s.n_swa) + Int(n_batch), 256) * 256)

"""
    kv_bytes(shape, n_ctx; kv_type = :f16, n_batch = _N_BATCH) -> Int

Bytes of KV cache for `n_ctx` tokens. K and V are stored per KV-head per layer,
so this is `Σ_layers n_head_kv × (k_len + v_len) × cells × bytes`: for a plain
transformer `n_layer × n_head_kv × …`, and for a hybrid only its full-attention
layers count (`shape.kv_heads` is 0 on the others). A sliding-window layer
(Gemma 4) holds `_swa_cells` cells at its own head sizes, whatever `n_ctx` is.
A hybrid's recurrent state does not grow with `n_ctx`; it is `shape.rs_bytes`,
which `plan_offload` adds once. `bits` (16, 8) is the older way to say f16/q8.
"""
function kv_bytes(s, n_ctx::Integer; bits::Integer = 16, kv_type = nothing,
                  n_batch::Integer = _N_BATCH)
    e = kv_type === nothing ? bits / 8 : _KV_ELT_BYTES[kv_type]
    swa = hasproperty(s, :swa) ? s.swa : falses(length(s.kv_heads))
    cells = any(swa) ? _swa_cells(s, n_ctx, n_batch) : 0
    total = 0.0
    for (il, h) in enumerate(s.kv_heads)
        total += swa[il] ? h * (Int(s.k_len_swa) + Int(s.v_len_swa)) * cells :
                           h * (Int(s.k_len) + Int(s.v_len)) * Int(n_ctx)
    end
    return round(Int, total * e)
end

"""
    plan_offload(path; n_ctx, n_batch = _N_BATCH, requested = nothing) -> NamedTuple

Decide `n_gpu_layers`. Returns `(ngl, why, vram_needed, kv, weights, compute,
shape, max_ctx_on_gpu)`; `compute` is `compute_reserve(shape, n_batch)`.

`requested === nothing` means AUTO: place as many layers on the GPU as the VRAM
budget holds, all-or-nothing at the top end (a full offload is worth far more
than one layer short of it, because a single CPU layer per token serializes the
whole pipeline).

A `requested` value is honoured but CHECKED — see `check_request`.
"""
function plan_offload(path::AbstractString; n_ctx::Integer, n_batch::Integer = _N_BATCH,
                      kv_type::Symbol = :f16, flash_attn::Symbol = :auto, requested = nothing)
    s        = model_shape(path)
    weights  = s.file_bytes
    kv       = kv_bytes(s, n_ctx; kv_type = kv_type, n_batch = n_batch)
    rs       = s.rs_bytes                  # a hybrid's recurrent state, fixed per sequence
    compute  = compute_reserve(s, n_batch) + attn_scores_bytes(s, n_batch, n_ctx, flash_attn)
    full     = weights + kv + rs + compute
    budget   = _vram_budget()

    # Largest n_ctx that would let the whole model sit on the GPU. Reported so a
    # refusal can say "or lower n_ctx to this" instead of only saying no.
    # Sliding-window layers are a fixed cost (their cells stop growing at the
    # window), so only the full-attention layers divide the headroom.
    # Past the window the cache grows by the full layers alone.
    big      = 1 << 20
    kv_big   = kv_bytes(s, big; kv_type = kv_type, n_batch = n_batch)
    per_tok  = kv_bytes(s, big + 1; kv_type = kv_type, n_batch = n_batch) - kv_big
    swa_fix  = kv_big - per_tok * big
    base     = compute_reserve(s, n_batch)
    # Flash attention off adds the scores, a cost per token of window that
    # doubles past `_SCORES_ONE_COPY` (`attn_scores_bytes`): the answer is the
    # better of the largest one-copy window and the largest two-copy one.
    avail    = budget - weights - rs - base - swa_fix
    max_ctx  = if per_tok <= 0
        0
    elseif flash_attn === :off
        one   = 4.0 * s.n_head * n_batch                       # bytes per token, one copy
        c_one = min(floor(Int, avail / (per_tok + one + _SCORES_MASK * n_batch)),
                    floor(Int, _SCORES_ONE_COPY / one))
        max(0, c_one, floor(Int, avail / (per_tok + 2one)))
    else
        max(0, floor(Int, avail / per_tok))
    end

    if requested !== nothing
        return (ngl = Int(requested), why = :requested, vram_needed = full,
                kv = kv, weights = weights, compute = compute, shape = s, max_ctx_on_gpu = max_ctx)
    end

    if full <= budget
        return (ngl = 99, why = :fits, vram_needed = full, kv = kv,
                weights = weights, compute = compute, shape = s, max_ctx_on_gpu = max_ctx)
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
    per_layer = (weights + kv + rs) / s.n_layer
    usable    = 0.9 * (budget - compute)
    k = per_layer > 0 ? Int(floor(usable / per_layer)) : 0
    k = clamp(k, 0, s.n_layer)

    if k >= (3 * s.n_layer) ÷ 4
        return (ngl = k, why = :partial, vram_needed = full, kv = kv,
                weights = weights, compute = compute, shape = s, max_ctx_on_gpu = max_ctx)
    end

    return (ngl = 0, why = :too_big, vram_needed = full, kv = kv,
            weights = weights, compute = compute, shape = s, max_ctx_on_gpu = max_ctx)
end

# The context `ChatSession` opens when the caller does not pass `n_ctx`.
const _CTX_CEILING = 32768
const _CTX_FLOOR   = 8192

"""
    auto_ctx(path; n_batch = _N_BATCH) -> Int

The context window to open when the caller did not choose one: 32768, unless
that pushes the model off the GPU and a smaller window keeps all of it on. Then
it is the largest such window, rounded down to a multiple of 1024.

This is what puts qwen3-coder on the B60 with no flags. Its 17.28 GiB of weights
and 96 KiB/token of KV need 20.78 GiB at 32768 against a ~20.5 GiB budget, so
the plan would go partial, while 29696 keeps the whole model on. GPU generation
is 5.2× CPU for it (50.2 against 9.6 tok/s), which is worth a tenth of the
window. (On the A750 it was qwen3:4b, opening at about 26k.)

Below 8192 a window is too short for a chat that carries scrollback, so a model
that only fits that small keeps 32768 and gets the plan's partial or CPU answer,
as before. An explicit `n_ctx` never comes through here.
"""
function auto_ctx(path::AbstractString; n_batch::Integer = _N_BATCH, kv_type::Symbol = :f16,
                  flash_attn::Symbol = :auto)
    p = plan_offload(path; n_ctx = _CTX_CEILING, n_batch = n_batch, kv_type = kv_type, flash_attn = flash_attn)
    p.why === :fits && return _CTX_CEILING
    fit = (p.max_ctx_on_gpu ÷ 1024) * 1024
    return fit >= _CTX_FLOOR ? fit : _CTX_CEILING
end

"""
    auto_batch(path; n_ctx = :auto) -> Int

The `n_batch` to open with when the caller did not choose one: the largest of
`_BATCH_STEPS` that keeps the model wholly on the GPU at the widest context
window any of them gets. Context first, then speed.

With flash attention on the steps stop at 512 and the widest window is 512's.
With it off they go down to 256, and the widest window may be 256's
(`attn_scores_bytes`). With `n_ctx = :auto` the windows compared are
`auto_ctx`'s; with an explicit `n_ctx` it is that window, which must still fit.
A model that fits the GPU at no step gets 512 — a batch cannot help it onto
the card.
"""
function auto_batch(path::AbstractString; n_ctx = :auto, kv_type::Symbol = :f16,
                    flash_attn::Symbol = :auto)
    kw = (kv_type = kv_type, flash_attn = flash_attn)
    steps = filter(>=(_batch_floor(flash_attn)), _BATCH_STEPS)
    # The window each step gets with the whole model on the card, 0 if none.
    function window(nb)
        c = n_ctx === :auto ? auto_ctx(path; n_batch = nb, kw...) : Int(n_ctx)
        plan_offload(path; n_ctx = c, n_batch = nb, kw...).why === :fits ? c : 0
    end
    ws = map(window, steps)
    best = maximum(ws)
    best == 0 && return _BATCH_BASE
    return steps[findfirst(==(best), ws)]
end

"""
    auto_flash_attn(path; n_ctx = :auto, n_batch = :auto, kv_type = :f16) -> Symbol

`:off` when turning flash attention off keeps the context window the model
would get with it on, else `:on`. Context first, then speed, as `auto_batch`.

On the B60 (Vulkan, b10286) flash attention is the slow path past a few
thousand tokens of context. Measured, 8k-token paste, then 256 generated, f16 KV:

    model          fa    ctx    gen   prefill@8k   gen@8k
    qwen3:4b       on   32768   93.1     551        43.5
                   off  32768   86.8    1051        50.2     (at 24k: 23.5 vs 10.6 gen)
    gemma4:26b     on   32768   57.7     267        29.7
                   off  32768   60.9    1062        50.8
    qwen3-coder    on   30720   84.2     347        29.1
                   off  12288   76.1     656        43.1     ← off costs 60% of the window
    qwen3.8:27b    on   32768   18.0     278        14.2
                   off  26624   17.6     339        16.3     ← and this one 19% for 15%

Off materialises the attention scores (`attn_scores_bytes`), VRAM that grows
with n_batch × n_ctx; that is what cost the window on the two big ones at 512.
At 256 qwen3.8:27b holds them in one copy and keeps all 32768, and that is
where the real difference shows, deep in a chat (2026-11-12):

    qwen3.8:27b    fa   n_batch  gen   prefill@8k  gen@8k  prefill@24k  gen@24k
                   on    2048    17.9     254       13.5      141         4.0
                   off    256    16.9     290       15.7      259        12.8 A quantised KV
cache needs flash attention for V, so `kv_type` other than `:f16` is `:on`.
"""
function auto_flash_attn(path::AbstractString; n_ctx = :auto, n_batch = :auto, kv_type::Symbol = :f16)
    kv_type === :f16 || return :on
    function window(fa)
        nb = n_batch === :auto ? auto_batch(path; n_ctx = n_ctx, kv_type = kv_type, flash_attn = fa) : Int(n_batch)
        c  = n_ctx === :auto ? auto_ctx(path; n_batch = nb, kv_type = kv_type, flash_attn = fa) : Int(n_ctx)
        plan_offload(path; n_ctx = c, n_batch = nb, kv_type = kv_type, flash_attn = fa).why === :fits ? c : 0
    end
    off = window(:off)
    return off > 0 && off >= window(:on) ? :off : :on
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
      KV @ n_ctx=$(n_ctx)  $(_gib(p.kv)) GiB   ($(s.n_kv_layers) layers × $(s.n_head_kv) kv-heads × $(s.k_len + s.v_len) dims, F16)$(s.rs_bytes > 0 ? "\n      recurrent      $(_gib(s.rs_bytes)) GiB   ($(s.n_layer - s.n_kv_layers) linear-attention layers, f32)" : "")
      compute        $(_gib(p.compute)) GiB   (n_batch × n_vocab logits + activations)
      ─ required     $(_gib(p.vram_needed)) GiB
      ─ budget       $(_gib(budget)) GiB   (\$LLAMACHAT_VRAM_GB)

    Refusing rather than warning: llama.cpp does not fit-to-available, and an
    over-commit on the Vulkan backend is a GGML_ASSERT abort that kills this
    process outright.

    Options:
      • n_ctx = $(p.max_ctx_on_gpu) or less would fit the whole model on the GPU
      • n_gpu_layers = 0 runs on CPU ($(_gib(p.weights)) GiB of $(_gib(_ram_budget())) GiB RAM budget)
      • raise the budget if you know the card has room (the default is what
        Vulkan reports free now, less $(_gib(_VRAM_MARGIN)) GiB):
          LLAMACHAT_VRAM_GB=<GiB> …$(s.is_moe ? "\n      • this is an MoE ($(s.n_expert) experts) — expert-offload to CPU would\n        fit the attention layers on the GPU and keep the experts in RAM" : "")""")
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
    rs = s.rs_bytes > 0 ? string(" + ", _gib(s.rs_bytes), " GiB recurrent") : ""
    string("gpu-plan: n_gpu_layers=", p.ngl, " ($tag) — ",
           _gib(p.weights), " GiB weights + ", _gib(p.kv), " GiB KV@", n_ctx, rs,
           " + ", _gib(p.compute), " GiB compute = ", _gib(p.vram_needed),
           " GiB vs ", _gib(_vram_budget()), " GiB budget [", s.arch, "/",
           s.n_layer, "L", moe, "]")
end
