# template.jl — a model's own chat template, run.
#
# The GGUF carries the chat template as a Jinja program. llama.cpp's C API
# does not run it (`llama_chat_apply_template` matches known formats), so what
# a template says beyond the turn markers never reached the prompt here: tool
# definitions, a thinking switch, a default system line. `apply_template` runs
# the program itself, in the JavaScript engine of js.jl, and gives the same
# text llama-server does.

const _JS = Ref{Union{Nothing,Module}}(nothing)
const _JS_LOCK = ReentrantLock()

_js_files() = (joinpath(dirname(@__DIR__), "lib", "js", "Quickjs.jl"),
               joinpath(dirname(@__DIR__), "lib", "js", "libquickjs.so"),
               joinpath(dirname(@__DIR__), "js", "jinja-0.5.13.cjs"))

"""The JavaScript engine and the Jinja library are both in place (`vendor_js.sh` copies the engine)."""
jinja_available() = all(isfile, _js_files())

"""`LlamaChat.JSEngine`, included on first use: a chat that never renders a template never maps QuickJS."""
function _js_module()
    lock(_JS_LOCK) do
        _JS[] === nothing || return _JS[]
        gone = [f for f in _js_files() if !isfile(f)]
        isempty(gone) || error("running a chat template needs the QuickJS wrapper and the Jinja library " *
                               "(missing: $(join(gone, ", "))). $(joinpath(dirname(@__DIR__), "vendor_js.sh")) " *
                               "copies the wrapper from the Hub's packages/quickjs.")
        _JS[] = Base.include(@__MODULE__, joinpath(@__DIR__, "js.jl"))
    end
end

"""
    render_template(template, context) -> String

Render a Jinja template. `context` is the template's variables: a dictionary
(an `ODict` keeps key order, which a template that prints one can show), or
JSON text. A template error is a Julia error with the engine's message.
"""
function render_template(template::AbstractString, context)
    m = _js_module()
    json = context isa AbstractString ? String(context) : JSON.json(context)
    # `m` was defined after this method was compiled: call it in the newest world.
    return Base.invokelatest(() -> m.render(String(template), json))::String
end

# One message as the template gets it. A tool call's arguments travel as JSON
# text in the OpenAI format and templates iterate them as a mapping, so they
# are parsed here (llama-server does the same before it renders).
_template_message(m::Pair) = ODict("role" => String(first(m)), "content" => String(last(m)))
function _template_message(m::AbstractDict)
    out = ODict()
    for (k, v) in m
        out[String(k)] = v
    end
    calls = get(out, "tool_calls", nothing)
    if calls isa AbstractVector
        out["tool_calls"] = map(calls) do c
            c isa AbstractDict || return c
            c2 = ODict((String(k) => v for (k, v) in c)...)
            f = get(c2, "function", nothing)
            if f isa AbstractDict
                f2 = ODict((String(k) => v for (k, v) in f)...)
                a = get(f2, "arguments", nothing)
                a isa AbstractString && (f2["arguments"] = try _parse_json(a) catch; a end)
                c2["function"] = f2
            end
            c2
        end
    end
    return out
end

"""
    apply_template(template, messages; tools, add_generation_prompt = true, think = true,
                   bos_token = "", eos_token = "", extra...) -> String

The prompt a chat template makes of a conversation: what llama-server's
`/apply-template` returns for the same input.

  `messages`  `role => content` pairs, or dictionaries in the OpenAI shape
              (`role`, `content`, and for tools `tool_calls` / `tool_call_id`)
  `tools`     tool definitions in the OpenAI shape, or `nothing`
  `think`     the template's `enable_thinking`. A template without the switch
              ignores it
  `extra`     any other variable the template reads

The leading BOS is removed from the result when the template writes one: the
tokenizer adds it, and it must not be there twice.
"""
function apply_template(template::AbstractString, messages; tools = nothing, add_generation_prompt::Bool = true,
                        think::Bool = true, bos_token::AbstractString = "", eos_token::AbstractString = "", extra...)
    ctx = ODict("messages" => [_template_message(m) for m in messages],
                "add_generation_prompt" => add_generation_prompt,
                "bos_token" => String(bos_token), "eos_token" => String(eos_token),
                "enable_thinking" => think)
    tools === nothing || (ctx["tools"] = tools)
    for (k, v) in extra
        ctx[String(k)] = v
    end
    out = render_template(template, ctx)
    !isempty(bos_token) && startswith(out, bos_token) && (out = out[sizeof(bos_token)+1:end])
    return out
end

"""The text of a special token (BOS, EOS), or "" when the model has none."""
function _token_text(vocab, id::Integer)
    id < 0 && return ""
    return something(L.llama_vocab_get_text(vocab, Int32(id)), "")
end

"""
    apply_template(session, messages = <its conversation>; kwargs...) -> String

`apply_template` with the session's own template, BOS and EOS, and its
`think` setting unless given.
"""
function apply_template(s::ChatSession, messages = _messages(s); think::Bool = s.think, kwargs...)
    s.template === nothing && error("$(s.name) carries no chat template")
    return apply_template(s.template, messages; think = think,
                          bos_token = _token_text(s.vocab, L.llama_vocab_bos(s.vocab)),
                          eos_token = _token_text(s.vocab, L.llama_vocab_eos(s.vocab)), kwargs...)
end

"""llama.cpp's own matcher recognises this template (it returns a length, not -1)."""
function _builtin_knows(tmpl::AbstractString)
    role, cont = _cstr("user"), _cstr("x")
    return GC.@preserve role cont begin
        msgs = [L.llama_chat_message(pointer(role), pointer(cont))]
        buf = Vector{UInt8}(undef, 512)
        GC.@preserve msgs buf L.llama_chat_apply_template(tmpl, msgs, 1, true, buf, Int32(length(buf))) >= 0
    end
end

"""`\$LLAMACHAT_TEMPLATE` (`auto`, `builtin`, `jinja`), read at call time."""
function _env_template()
    v = Symbol(lowercase(strip(get(ENV, "LLAMACHAT_TEMPLATE", "auto"))))
    v in (:auto, :builtin, :jinja) && return v
    @warn "LLAMACHAT_TEMPLATE=$(repr(ENV["LLAMACHAT_TEMPLATE"])) is not auto, builtin or jinja — using auto"
    return :auto
end

"""
    _use_jinja(mode, template) -> Bool

Whether a session runs its template with the Jinja engine.

  `:jinja`    yes; an error if the engine is not installed or the model has
              no template
  `:builtin`  no: llama.cpp's matcher (and LlamaChat's own Gemma 4 formatter)
  `:auto`     only where the matcher does not know the template, which used
              to mean ChatML with a warning, whatever the model expected

`:auto` does not prefer Jinja everywhere, on purpose. A template is free to
render an earlier reply differently from how it was generated (Qwen's drop the
reasoning of every turn but the last), and then the prompt no longer extends
what is in the KV cache: the whole conversation is decoded again each turn.
The matcher's rendering keeps replies as they were generated, so a turn costs
only its own tokens. Measured in the README ("Chat templates").
"""
function _use_jinja(mode::Symbol, tmpl)
    mode in (:auto, :builtin, :jinja) || throw(ArgumentError("template must be :auto, :builtin or :jinja; got :$mode"))
    mode === :builtin && return false
    if mode === :jinja
        tmpl === nothing && error("template = :jinja, but this model carries no chat template")
        jinja_available() || _js_module()           # raises the error that says what is missing
        return true
    end
    return tmpl !== nothing && !_is_gemma4(tmpl) && jinja_available() && !_builtin_knows(tmpl)
end
