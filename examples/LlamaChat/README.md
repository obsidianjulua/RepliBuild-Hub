# LlamaChat.jl

A multi-turn chat app built on the RepliBuild-generated **llama.cpp b10286**
wrapper — the reference example for **driving a wrapped C library whose entire
entry surface crosses by value**, and the counterpart to `BoxWorld` (which
covers the C++ object-model side).

```julia
using LlamaChat

chat("write a haiku about pointers")
chat("now make it about DWARF")           # remembers the turn before
start!("qwen2.5-coder:1.5b-base")         # switch models
chatrepl()                                # interactive
```

Replies render as **markdown** in the terminal — fenced code blocks get syntax
highlighting, lists and emphasis get formatted — via Julia's `Markdown` stdlib.
It is on by default whenever output is a tty, off for pipes and files.

```julia
chat("show me a julia function")             # streams, then renders formatted
chat("..."; markdown = false)                # raw text only
md(r)                                        # render any Response after the fact
```

Or from a shell:

```console
$ julia --project=examples/LlamaChat examples/LlamaChat/chat.jl        # REPL
$ julia --project=examples/LlamaChat examples/LlamaChat/chat.jl "hi"   # one-shot
```

Or just:

```julia
julia> LlamaChat.run_demo()
```

Models are named the way ollama names them — `"qwen3-coder"`, `"gemma4:e2b"`,
`"igorls/gemma-4-E4B-it-heretic-GGUF:latest"` — and resolved through the local
manifest store (`$OLLAMA_MODELS`, default `/var/lib/ollama`). A path to a
`.gguf` works too. `list_models()` shows what is on the box.

The default is **qwen3-coder** (30B-A3B): a MoE, so only ~3B parameters are
active per token, which makes an 18 GB model *faster* on CPU than a dense 8 GB
one. Measured on a Ryzen 5 5600 (6 threads, CPU-only): ~43 tok/s prompt,
~20 tok/s generation, 35 s one-time load. Override with `$LLAMACPP_CHAT_MODEL`;
`default_model()` reports what bare `chat("...")` will open.

Both environment variables are read when they are used, not when the package is
loaded, so setting one mid-session takes effect on the next `start!`. (They were
`const`s initialised from `ENV` at module scope, which Julia evaluates during
*precompilation* and freezes into the `.ji` — so `$LLAMACPP_CHAT_MODEL` silently
did nothing for anyone whose first `using LlamaChat` came before they set it.)

## Layout

```
LlamaChat/
├── Project.toml         # depends on RepliBuild (the wrapper dispatches through its JIT)
├── lib/                 # RepliBuild build + wrap output — the ABI layer, never edited
│   ├── Llamacpp.jl
│   ├── libllamacpp.so
│   ├── compilation_metadata.json
│   └── thunk_manifest.json
├── src/LlamaChat.jl     # the ergonomic layer — sessions, templating, KV bookkeeping
├── chat.jl              # thin launcher for shell use
└── test/runtests.jl
```

The package precompiles normally (~9 s for the 3.9 MB wrapper); the JIT engine
initializes at load time from the wrapper's `__init__`.

## What it exercises

`packages/llamacpp/test_deep.jl` pins the ABI against a native C oracle. This
package is the other half: it drives the same surface the way an application
does, where a broken crossing is *legible* — garbage text instead of a
plausible float vector.

- **MEMORY-class structs returned and passed by value** — `llama_model_params`
  (72 B), `llama_context_params` (160 B), `llama_batch`,
  `llama_sampler_chain_params`. Every one is both a return value and an
  argument.
- **An array of C structs built on the Julia side** — `llama_chat_message[]`,
  with the role/content byte buffers kept alive across the call.
- **Out-params into plain Julia arrays** — `llama_tokenize`,
  `llama_token_to_piece`, both with the negative-return "your buffer was too
  small, here is the size" protocol.
- **Cstring returns** — `llama_model_chat_template`.
- **Tier-2 MLIR-JIT dispatch** — `llama_model_load_from_file`,
  `llama_init_from_model`.

## Three traps this package documents

Each of these is invisible on the happy path, so each has a test.

**1. `import` the wrapper, never `using` it.** A wrapper generated from C++
DWARF takes a name from every symbol that reached the debug info, libstdc++
included — this one defines 6,527. Import the module and go through `L.`.

This was a correctness trap before it was a hygiene one, and the fix is worth
knowing about: llamacpp defines `error` (from `codecvt_base::result.error`) and
used to *export* it, so `using .Llamacpp` turned a bare `error("...")` in the
caller into an ambiguous binding and every failure path in that file raised
`UndefVarError: error not defined` instead of its message — invisible until
something went wrong, because the happy path never touches it. Debugging that
here is what prompted RepliBuild to withhold Base/Core-colliding names from
`export` (they stay defined and reachable as `L.error`; the wrapper carries a
banner naming them — `all`, `error`, `stat`, `symlink`). `using` is no longer
unsafe, just unwise at this scale.

**2. Name collisions pick the tier for you.** `llama_vocab_is_eog` is emitted
twice: a Tier-3 ccall `(vocab, ::Int32)` and a Tier-2 JIT thunk `(this,
::Integer)` for the C++ member function of the same name. `Tuple{Any,Int32}` is
strictly more specific, so an `Int32` token reaches the ccall — but a plain
`Int`, Julia's default literal type, silently routes through the JIT and drags
in a `libJLCS.so` dependency the ccall path does not need. Every token in this
package goes through `_is_eog`, which pins the conversion.

**3. A token is not a character.** `llama_token_to_piece` returns bytes, and
multi-byte code points routinely split across two tokens. Streaming them
straight to the terminal corrupts it. `_take_utf8!` holds a partial tail back
until it completes.

## Markdown vs. streaming

These two want opposite things. Markdown has no meaning until a block is
closed — a fence, a list, a table only has a shape once it ends — so it cannot
be rendered token by token. Streaming is the whole feel of a chat REPL, so
neither gets dropped: text streams live, and **each block is reprinted formatted
the moment it closes**.

A block closes on a blank line, or on a closing code fence. Both are cheap to
spot one line at a time, which is all a token stream gives you. The redraw is
`\e[nA` + `\e[0J` over just that block's rows.

Per *block* rather than per reply, because `\e[0J` can only erase what is still
on screen. The first version redrew the whole reply once at the end, which meant
any reply taller than the window stayed raw forever — its top had already
scrolled into scrollback. That is most answers of substance: a 47-row reply
needed a 49-row terminal. Blocks are individually short, so doing it per block
removes the height limit instead of working around it, and formats sooner
besides — a code fence is highlighted as soon as it ends, not after the last
token.

Four things make this less obvious than it looks, and each has a test:

- **Soft wrap and wide characters.** `n` is not `count('\n')` — a long line
  wraps to several terminal rows, and CJK/emoji take two columns each.
  `_wrapped_lines` accounts for both.
- **Flush before the partial line prints.** A block frequently closes in the
  middle of a token. If the whole chunk were printed first, the cursor would be
  neither at column 0 nor `n` rows down, and `\e[0J` would eat the text after
  the block. `_emit!` prints line by line for exactly this reason.
- **Blank lines inside a block.** A blank line inside a fence does not close it,
  and blank lines are *interior* to an indented code block — closing on one
  would split it and the second half would stop being code.
- **Token boundaries are arbitrary.** Segmentation must not depend on where the
  model split its output; `_segment` drives the same text one byte at a time to
  prove it.

A block is left raw when output is not a tty, or when that single block is
taller than the window. A reply truncated at `max_tokens` is malformed markdown
by construction (unterminated fence, half a table), so the renderer is wrapped
in a fallback to raw text: a formatting problem must never cost a finished
generation.

Note that a model writing literal `•` characters instead of `-` list markers is
emitting paragraph text, not a list, and renders as one — that is the model's
choice, not the renderer's.

## Incremental KV reuse

The session keeps `s.decoded` — the exact transcript bytes backing the KV
cache. Each turn re-renders the whole conversation through the chat template,
then feeds the model only the byte-suffix it has not seen. The generated text is
appended to `s.decoded` immediately after the assistant header, so cache and
transcript stay in step; the closing `<|im_end|>` is sampled but deliberately
not decoded, arriving instead as part of the next turn's delta.

If a template re-renders earlier turns (some do), the prefix check fails and the
cache is rebuilt from scratch rather than extended onto a transcript the model
never saw. `test/runtests.jl` asserts both the prefix invariant and that turn 2
costs far fewer prompt tokens than a full re-decode would — that assertion is
what catches a regression in the reuse path.

## Building the wrapper

`lib/` is RepliBuild output, not vendored source. With RepliBuild installed:

```julia
using RepliBuild
RepliBuild.build("packages/llamacpp/replibuild.toml")   # → libllamacpp.so + compilation_metadata.json
RepliBuild.wrap("packages/llamacpp/replibuild.toml")    # → Llamacpp.jl
```

then copy the four artifacts into `lib/`. A cold rebuild is a 200 MB clone,
195 TUs and a 252 MB DWARF dump — roughly 19 minutes — so it is deliberately not
a routine step.

## Setup

`RepliBuild` is a local path dependency:

```julia
julia> using Pkg
julia> Pkg.develop(path="/path/to/RepliBuild.jl")
julia> Pkg.test()
```

Tests pick the smallest generative model in the local ollama store (embedding
models are skipped) and warn-and-skip the live half entirely if none is present.
Override with `$LLAMACHAT_TEST_MODEL`.
