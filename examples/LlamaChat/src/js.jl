"""
    LlamaChat.JSEngine

A JavaScript engine in the process, and the one thing LlamaChat uses it for:
running a model's own Jinja chat template.

Two pieces, neither of them LlamaChat's:

  * QuickJS (Bellard's ES2023 interpreter), through the Hub's RepliBuild wrapper
    in `lib/js/` (`Quickjs.jl` + `libquickjs.so`; `vendor_js.sh` copies them);
  * `@huggingface/jinja` 0.5.13 (MIT), one dependency-free file in
    `js/jinja-0.5.13.cjs`, the library transformers.js renders chat templates
    with.

Why: a chat template is a Jinja program stored in the GGUF, and llama.cpp's C
API does not run it. `llama_chat_apply_template` is a matcher over the formats
it knows, so a template it does not know falls back to ChatML, and nothing a
template says about tools, thinking switches or system defaults reaches the
prompt. llama-server runs the template with its own C++ engine (minja), which
lives in the part of llama.cpp the Hub does not wrap. This is the same result
by another road: across the five models here, five conversations each (plain,
multi-turn, thinking off, tools offered, a tool call and its result), the text
is byte-identical to llama-server's (2026-11-15).

Not loaded with the package: `LlamaChat._js_module()` includes this file the
first time a template is rendered. The engine has no `std` or `os` module, so
a template can compute and nothing else: no files, no processes, no network.

ONE ENGINE, ONE CALLER AT A TIME. A QuickJS runtime is single-threaded, and it
measures stack depth from where it was created. Chat runs on whatever thread
and task asked, so every call takes `LOCK` and re-bases the stack mark
(`JS_UpdateStackTop`) before it evaluates anything.
"""
module JSEngine

const LIBDIR = joinpath(dirname(@__DIR__), "lib", "js")
const JINJA_FILE = joinpath(dirname(@__DIR__), "js", "jinja-0.5.13.cjs")

# `import`, never `using`: a generated wrapper exports names that shadow Base.
include(joinpath(LIBDIR, "Quickjs.jl")); import .Quickjs as Q

mutable struct Engine
    rt::Ptr{Q.JSRuntime}
    ctx::Ptr{Q.JSContext}
end

"""A fresh engine, capped in memory and stack, with no file, process or network access."""
function Engine(; memory_mb::Integer = 256, stack_kb::Integer = 512)
    rt = Q.JS_NewRuntime()
    rt == C_NULL && error("JS_NewRuntime failed")
    Q.JS_SetMemoryLimit(rt, memory_mb * 1024^2)
    Q.JS_SetMaxStackSize(rt, stack_kb * 1024)
    ctx = Q.JS_NewContext(rt)
    ctx == C_NULL && (Q.JS_FreeRuntime(rt); error("JS_NewContext failed"))
    return Engine(rt, ctx)
end

function close!(js::Engine)
    js.ctx == C_NULL && return nothing
    Q.JS_FreeContext(js.ctx)
    Q.JS_FreeRuntime(js.rt)
    js.ctx = C_NULL
    js.rt = C_NULL
    return nothing
end

function _string(js::Engine, v)
    p = Q.JS_ToCStringLen2_ptr(js.ctx, C_NULL, v, 0)
    p == C_NULL && return nothing
    s = unsafe_string(p)
    Q.JS_FreeCString(js.ctx, Ptr{UInt8}(p))
    return s
end

# The pending exception as one line: a template error is the user's to read,
# and the library's stack frames are not.
function _exception(js::Engine)
    exc = Q.JS_GetException(js.ctx)
    msg = something(_string(js, exc), "unknown JavaScript error")
    Q.JS_FreeValue(js.ctx, exc)
    return msg
end

"""
    evaljs(engine, source) -> Union{String,Nothing}

Evaluate `source` as a script and return its value as text (`nothing` for
`undefined`). A JavaScript exception is a Julia error carrying its message.
Every value this creates is released before it returns.
"""
function evaljs(js::Engine, src::AbstractString; name::AbstractString = "<eval>")
    js.ctx == C_NULL && error("the JavaScript engine is closed")
    Q.JS_UpdateStackTop(js.rt)                    # this task's stack, not the creator's
    s = String(src)
    v = Q.JS_Eval(js.ctx, s, sizeof(s), name, Q.JS_EVAL_TYPE_GLOBAL())
    if Q.JS_IsException(v) == 1
        Q.JS_FreeValue(js.ctx, v)
        error("JavaScript: " * _exception(js))
    end
    out = Q.JS_IsUndefined(v) == 1 ? nothing : _string(js, v)
    Q.JS_FreeValue(js.ctx, v)
    return out
end

"""Set a global variable to a string: how data goes in, as text, never spliced into source."""
function setglobal!(js::Engine, name::AbstractString, value::AbstractString)
    g = Q.JS_GetGlobalObject(js.ctx)
    Q.JS_SetPropertyStr(js.ctx, g, name, Q.JS_NewString(js.ctx, String(value)))   # takes the string's reference
    Q.JS_FreeValue(js.ctx, g)
    return nothing
end

# ── Jinja ────────────────────────────────────────────────────────────────────

# The one addition to the library: the `select` and `reject` filters with a
# test (0.5.13 has only `selectattr` / `rejectattr`). qwen3-coder's template
# lists a tool parameter's extra schema keys with
# `param_fields.keys() | reject("in", handled_keys)`; without this, every
# request that offers that model a tool is "Unknown ArrayValue filter: reject".
const _FILTER_ANCHOR = "          case \"selectattr\":\n          case \"rejectattr\": {"
const _FILTER_PATCH = raw"""          case "select":
          case "reject": {
            const sel = filterName === "select";
            const [testName, value] = filter.args.map((x) => this.evaluate(x, environment));
            let fn;
            if (!testName) fn = (x) => x.__bool__().value;
            else if (testName.value === "in") fn = (x, v) => v.value.some((y) => y.value === x.value);
            else {
              const test = environment.tests.get(testName.value);
              if (!test) throw new Error(`Unknown test: ${testName.value}`);
              fn = test;
            }
            return new ArrayValue(operand.value.filter((item) => { const r = fn(item, value); return sel ? r : !r; }));
          }
"""

"""Load the Jinja library into an engine. It is CommonJS, so it is given a `module` to export into."""
function load_jinja!(js::Engine, path::AbstractString = JINJA_FILE)
    src = read(path, String)
    occursin(_FILTER_ANCHOR, src) ||
        error("$path is not the @huggingface/jinja build LlamaChat's filter patch was written for (0.5.13)")
    src = replace(src, _FILTER_ANCHOR => _FILTER_PATCH * _FILTER_ANCHOR; count = 1)
    evaljs(js, "var module = {exports: {}}; var exports = module.exports;\n" * src *
               "\n;globalThis.Jinja = module.exports; globalThis.__tmpl = new Map(); 'ok'"; name = "jinja.cjs")
    # A template is parsed once and kept by its text; a render is a context in, as JSON.
    evaljs(js, raw"""
        globalThis.__render = function (template, contextJSON) {
            let t = __tmpl.get(template);
            if (t === undefined) { t = new Jinja.Template(template); __tmpl.set(template, t); }
            return t.render(JSON.parse(contextJSON));
        }; 'ok'""")
    return js
end

const ENGINE = Ref{Union{Nothing,Engine}}(nothing)
const LOCK = ReentrantLock()

"""
    render(template, context_json) -> String

Render a Jinja template with a context given as JSON text. The engine is
created on the first call (about 50 ms) and kept; a template costs a few
milliseconds the first time and well under one after.
"""
function render(template::AbstractString, context_json::AbstractString)
    lock(LOCK) do
        js = ENGINE[]
        if js === nothing
            js = load_jinja!(Engine())
            ENGINE[] = js
        end
        setglobal!(js, "__T", template)
        setglobal!(js, "__C", context_json)
        out = evaljs(js, "__render(__T, __C)")
        return something(out, "")
    end
end

"""Free the engine. The next `render` makes a new one."""
function shutdown()
    lock(LOCK) do
        ENGINE[] === nothing || close!(ENGINE[])
        ENGINE[] = nothing
    end
    return nothing
end

end # module JSEngine
