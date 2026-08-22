# LlamaChat.jl

A multi-turn chat app built on the RepliBuild-generated **llama.cpp b10286**
wrapper — the reference example for **driving a wrapped C library whose entire
entry surface crosses by value**, and the counterpart to `BoxWorld` (which
covers the C++ object-model side).

## The interface

Three names.

```julia
using LlamaChat

list_models()              # what is on the box
load("qwen3-coder")        # load it and start talking
ask("why did that fail?")  # answer in a second window; this REPL stays yours
```

```
julia> load("qwen3-coder")
loading qwen3-coder … ok  (35.1s, n_ctx=32768, 6 threads, template=built-in)

qwen3-coder  ·  32768 ctx  ·  /help for commands

>>> write a haiku about pointers
…
[9 prompt tok @ 43.2/s · 31 gen tok @ 20.1/s]

>>> /exit
(unloaded)

julia>
```

In the loop: `/reset`, `/system <text>`, `/stats`, `/help`, `/exit`. Ctrl-C
stops a reply without leaving the loop; Ctrl-D leaves like `/exit`.

`/exit` frees the context **and** the weights before returning, so the Julia
session you come back to holds nothing and the next `load` starts clean —
including after a turn that died halfway, since the teardown is in a `finally`.
The cost is a full reload to resume; the benefit is never wondering whether
18 GB is still resident.

`load()` with no argument opens `default_model()` — `$LLAMACPP_CHAT_MODEL`, else
`qwen3-coder`. Its keywords are `ChatSession`'s:

```julia
load("qwen2.5-coder:1.5b-base"; temp = 0)            # greedy
load("qwen3-coder"; system = "You are terse.", n_ctx = 8192)
```

Replies render as **markdown** — fenced code blocks get syntax highlighting,
lists and emphasis get formatted — via Julia's `Markdown` stdlib. There is no
switch for it: on a terminal it always happens, into a pipe it never does,
because the redraw is cursor arithmetic and a pipe has no cursor. See
[Markdown vs. streaming](#markdown-vs-streaming).

Or from a shell:

```console
$ julia --project=examples/LlamaChat examples/LlamaChat/chat.jl        # chat
$ julia --project=examples/LlamaChat examples/LlamaChat/chat.jl "hi"   # one-shot
```

## `ask` — the answer goes to another window

`load` wants the terminal. `ask` is for when the REPL is the thing you are
working in and you are not leaving it: the reply renders in a **second terminal
window**, driven by this same Julia process, and you keep the prompt.

```julia
julia> RepliBuild.wrap("packages/pugixml/replibuild.toml")
ERROR: MethodError: no method matching thunk_abi(::MEMORY, ::Val{:byval})
Stacktrace: [1] emit_thunk ...

julia> ask("why did that fail?")     # returns in ~0.5s; answer lands next door
julia> # ...and you carry straight on working here
```

Three things make it work, and each was a choice:

**It returns immediately.** Generation runs on a spawned thread
(`$JULIA_NUM_THREADS=auto` gives 12 here), and so does the *model load* — the
first `ask` returns in about half a second with the window already up saying
`loading qwen3-coder …`, rather than freezing the REPL for the 36 s it takes to
map 18 GB. A second `ask` during that simply queues behind it on the session
lock. Getting this wrong is subtle: loading in `ask` itself was correct, worked
fine, and blocked the prompt for 36 s on the one call whose entire purpose is
not to.

**The model sees your terminal, not just your question.** Context comes from
`kitty @ get-text` — the real scrollback, so the failing call, the error and the
stacktrace are all in it without you retyping any of them. Only what is *new*
since the last `ask` is sent; re-sending a 400-line capture every turn would
spend the whole context window re-reading itself in about three turns.

**Closing the window is the hangup.** It frees the context and the weights, and
the next `ask` starts clean — the same contract `/exit` has in `load`. The window
also dies with the Julia process, including when Julia is killed outright: the
child watches its parent's pid, because a Julia that gets SIGKILLed has no
handler left to run and an orphaned window sits on screen forever otherwise.

```julia
ask("why?"; model = "qwen3-coder")     # opens the window and loads
ask("show the fix")                    # same conversation, same window
ask("..."; context = false)            # no scrollback, just the prompt
ask("..."; max_tokens = 300, lines = 100)
```

`ChatSession` keywords (`system`, `n_ctx`, `temp`, …) apply on the call that
opens the window, since that is the one that builds the session.

### Setup

The scrollback needs kitty remote control, which is one line in `kitty.conf`:

```
allow_remote_control socket-only
listen_on unix:/tmp/kitty-{kitty_pid}
```

`socket-only` leaves the escape-code channel closed, so only processes that can
see `$KITTY_LISTEN_ON` can drive kitty. **Windows already open when you add this
must be restarted** — kitty reads it at window start. Without it `ask` still
works; it warns once and sends the prompt on its own.

### Everything else

`list_models` and `load` are the whole export list. The machinery underneath is
unchanged and still supported — it is simply not in your namespace:

```julia
LlamaChat.ChatSession(model; kwargs...)   # a session you own the lifetime of
LlamaChat.chat(s, prompt; kwargs...)      # one turn → Response
LlamaChat.reset!(s) / close!(s)
LlamaChat.resolve_model(name)             # name → blob path
LlamaChat.default_model() / ollama_root()
```

That is the scripting path, and `chat.jl`'s one-shot branch is the worked
example of it. Gone outright, not merely unexported: `md`, `chatrepl`, `start!`,
`run_demo`, the module-global session behind bare `chat("...")`, and the
`markdown` kwarg.

## Models

Models are named the way ollama names them — `"qwen3-coder"`, `"gemma4:e2b"`,
`"igorls/gemma-4-E4B-it-heretic-GGUF:latest"` — and resolved through the local
manifest store (`$OLLAMA_MODELS`, default `/var/lib/ollama`). A path to a
`.gguf` works too.

```
julia> list_models()
   qwen3.6:35b                 22 GiB
   gemma4:31b                  19 GiB
 → qwen3-coder:latest          17 GiB
   qwen3.8:27b                 16 GiB
   ornith-1.5:9b              5.2 GiB
   qwen2.5-coder:1.5b-base    940 MiB
   nomic-embed-text:latest    262 MiB
```

`→` marks what bare `load()` will open. The return value is still a
`Vector{Tuple{String,Int}}` of (name, bytes) for anything that wants to index or
filter it — only the printing is different.

The default model is **qwen3-coder** (30B-A3B): a MoE, so only ~3B parameters are
active per token, which makes an 18 GB model *faster* on CPU than a dense 8 GB
one. Measured on a Ryzen 5 5600 (6 threads, CPU-only): ~43 tok/s prompt,
~20 tok/s generation, 35 s one-time load. Override with `$LLAMACPP_CHAT_MODEL`;
`LlamaChat.default_model()` reports what bare `load()` will open, and
`list_models()` marks it.

Both environment variables are read when they are used, not when the package is
loaded, so setting one mid-session takes effect on the next `load`. (They were
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
├── src/
│   ├── LlamaChat.jl     # the ergonomic layer — sessions, templating, KV bookkeeping
│   └── window.jl        # ask(): sidecar window, ptys, scrollback capture
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

There is deliberately no switch for any of this. The one condition that actually
governs it — is `io` a tty — is not a preference, it is whether `\e[nA` has a
cursor to move; a `markdown = false` kwarg and a `/md` toggle were just a way to
ask for worse output on a terminal that could do better. Both are gone.

Note that a model writing literal `•` characters instead of `-` list markers is
emitting paragraph text, not a list, and renders as one — that is the model's
choice, not the renderer's.

### Headings are drawn without their underline rule

Julia's terminal backend underlines a header with a run of characters chosen by
level — `Markdown._header_underlines = collect("≡=–-⋅ ")`. h1 gets `≡`, which
reads as decoration. h2 gets plain ASCII `=`, and a bold line sitting above
`==========` is character-for-character what setext markdown *source* looks
like:

```
Origins and Design Philosophy          ← rendered h2, working correctly
==============================
```

So a correctly rendered `## Heading` looks like a renderer that failed to strip
the syntax, and models reach for `##` constantly — this is the common case, not
an edge one. It got reported here as "qwen breaks it somehow."

h1 keeps its rule; h2 and below render as bold text with none, which is what
they already looked like minus the false syntax. The rewrite happens on the
parsed tree using public node types (`Header` → `Paragraph(Bold(...))`) rather
than by poking `_header_underlines`, which is a mutable global shared with
`?help` and every other markdown render in the session.

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
