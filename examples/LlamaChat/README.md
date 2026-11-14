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
LlamaChat.cancel!(s)                      # stop a reply from another thread
LlamaChat.resolve_model(name)             # name → blob path
LlamaChat.default_model() / ollama_root()
```

That is the scripting path, and `chat.jl`'s one-shot branch is the worked
example of it. Gone outright, not merely unexported: `md`, `chatrepl`, `start!`,
`run_demo`, the module-global session behind bare `chat("...")`, and the
`markdown` kwarg.

## `LlamaChat.gui` — a chat window

The same session in a window instead of a terminal: a scrolling transcript, a
prompt box below it, and a status line with the model, context use and the
last reply's tok/s. Window, widgets and model are all RepliBuild wrappers driven
from Julia — Dear ImGui and GLFW beside the llama.cpp one. There is no C++ host
program.

```bash
DISPLAY=:1 julia -t 4 --project=examples/LlamaChat -e 'using LlamaChat; LlamaChat.gui()'
```

On this machine `~/.local/bin/llamagui [model]` wraps that line (it lives
outside the repo).

```julia
julia> using LlamaChat          # julia started with -t 2 or more
julia> LlamaChat.gui()                                   # nothing loaded: pick a model in the window
julia> LlamaChat.gui("qwen3:4b"; think = false, font_size = 20)
```

- The **model picker** (top left) lists the generative models in the ollama
  store with their sizes, re-read each time it opens. Picking one unloads the
  current model and then loads the new one, in that order and on the worker,
  so the planner sizes the new load from the VRAM just given back. A new
  model starts a new conversation: the turns above stay on screen but are not
  sent to it. **Unload** frees the model and keeps the window.
- The **status light** says what the window is doing: green *ready*, amber
  *loading* / *unloading* and blue *replying* (both pulse), grey *no model
  loaded*, red *load failed*. After it come the seconds spent on the current
  step, context use, and the last reply's tok/s. The window title follows it
  (`LlamaChat · qwen3:4b · ready`), and a finished load says where the model
  runs: "qwen3:4b is ready · all 36 layers on GPU · 32768 ctx · loaded in
  2.8 s". A partial offload reads "43/48 layers on GPU", and no GPU reads "CPU
  only" (`LlamaChat.placement(session)`, from the planner's decision at load).
- The empty prompt box says what Enter will do right now.
- **Enter** sends, **Ctrl+Enter** is a newline. You can type while the model
  loads or a reply streams: Enter then queues the message, the status line
  says so, and it goes the moment the model is free (Stop frees it at once).
- With no model given, the window opens with nothing loaded; pick one from
  the list. `$LLAMACHAT_GUI_MODEL`, if set, is loaded instead.
- Enter in the prompt sends even with Super or Alt reported as held. imgui
  treats that as Super+Enter and does nothing, and a compositor keybinding
  (Hyprland's, over Xwayland) can leave Super reported as held after its
  release went to the compositor: the box kept taking characters but Enter
  did nothing.
- **Stop** ends the reply at the next token and keeps what it said (the
  `Response` reads `stop = :interrupt`, as Ctrl-C does at the REPL). **New
  chat** forgets the conversation and keeps the model.
- Reasoning is folded and dimmed above each answer ("Reasoning (212 words)"),
  open it to read it. It is there even with `think = false`: that setting
  shortens reasoning and strips it from `Response.text`, but the stream still
  carries it.
- Replies render as markdown as they stream: bold, italic, `code` and links
  inside wrapped paragraphs, headings, lists, tables, quotes, rules, and code
  blocks in a mono face with their own **copy** button. Code is coloured like
  an editor (functions, types, keywords, numbers, strings, comments): Julia
  through `JuliaSyntaxHighlighting`, which runs Julia's own parser; C/C++,
  Python, bash, Rust, JS/TS, Go, Java-likes, Lua, SQL and data formats
  (TOML/YAML/JSON/INI) through a small tokenizer; unlabelled or `text` blocks
  stay plain. A block is coloured once, when it is parsed, not per frame. It is the parser the
  terminal uses (`Markdown.parse`), so it has the same blind spots: italic
  nested in bold that closes on `***` would stay literal, so `***x***` is
  rewritten to `**_x_**` first. A `$` before a digit is money, not LaTeX
  (`$10k–$100k` used to turn into maths); a `$…$` that looks like maths stays
  maths. `markdown = false` shows replies raw.
- **Markdown is coloured**, per theme: headings by level (levels 1 and 2 with
  an underline that fades out), bold and italic in their own colours, inline
  code on a pill, links underlined, numbered and bulleted list markers in
  colour, table headers tinted, quotes with an accent bar, rules that fade at
  both ends. Inline LaTeX becomes Unicode in the maths colour: `$\rightarrow$`
  is →, `$E = mc^2$` is E = mc², `$v_0 \approx 9.81 \times t$` is
  v₀ ≈ 9.81 × t, Greek letters and the usual relations and operators
  (`tex2uni`); what it does not know stays as written.
- **Text** is rasterised by FreeType (hinted, crisper than stb_truetype) with
  32-bit characters: the Hub's imgui is built with `IMGUI_ENABLE_FREETYPE` and
  `IMGUI_USE_WCHAR32`. Noto Sans Symbols2 and Math are merged into every face,
  and Noto Sans CJK when installed (one ~20 MB copy shared by all four faces).
  A character no merged font has is left out rather than drawn as U+FFFD.
  Emoji draw in colour only with a *scalable* colour emoji font (COLR, e.g.
  Twemoji); Noto Color Emoji is a single 109 px bitmap strike, which FreeType
  will not scale to text size, so with only that installed emoji are left out.
  **copy** keeps everything.
- **Theme** (the combo in the status bar): Dark, Light, Midnight, Nord,
  Gruvbox, Solarized, each with a swatch, plus an **Accent** colour of your own
  under them. A theme sets imgui's colours, the role colours, the status
  light, the markdown and code palettes and the terminal's default colours, and switching
  recolours what is already on screen (code runs store a token class, not a
  colour). The choice is saved in `~/.config/llamachat/theme`;
  `gui(; theme = "Nord")` or `$LLAMACHAT_THEME` picks one for a session.
- The transcript follows the stream only while you are at the bottom. Scroll
  up and it stays put; sending jumps back down.
- **copy** under a reply puts its raw markdown on the clipboard (imgui text is
  drawn, not selectable).
- Closing the window frees the model, like `/exit`. Closing it during a load
  waits for the load to land first, since a load cannot be interrupted.

### A small environment: places, terminals, Ask, notes, stats

The window is also somewhere to work: several terminals in the folders you use,
a model that can be shown any of them, notes it always has, and the machine's
numbers along the bottom. No RAG and no tools: the model gets text, and answers.

**Places.** The folders terminals start in. By default RepliBuild (the checkout
this package builds against), the Hub, and the folder that holds the Hub, in
that order; `~/.config/llamachat/places` replaces them:

```
# name = folder, in menu order; the first is where the first terminal opens
Work  = ~/code/work
Notes = ~/Documents/notes
```

The first terminal opens in the first place when the window was started from
`$HOME` (a keybinding, a launcher); started from anywhere else, it opens there.

**Terminals.** As many as you like, as tabs over the terminal panel. `+` lists
every place twice, as a Julia REPL (`julia --project=@.`, so the folder's own
project) and as your `$SHELL`. `Go` sends the showing terminal to a place by
typing its own `cd` (`cd("…")` in Julia, `cd -- '…'` in a shell). `Close` ends
one; the others, and any not showing, keep running and keep being read. The
line under the tabs is where the program is *now* (from `/proc`), not where it
started.

**Ask.** The button over a terminal, or Ctrl+Shift+E inside it, sends that
terminal's last 120 lines to the model at once, with what it is and where
(`a zsh shell in /path`). The question is whatever the message box holds; with
the box empty it asks what went wrong and how to fix it. While the model is
loading or mid-reply the question is queued, as Enter queues a message.
`Attach` is the slower form: tick it, then write the message yourself.

**Notes.** The `Notes` button opens a box above the transcript. What you write
there is saved to `~/.config/llamachat/notes.md` when you leave the box, and
goes to every model as its system prompt when it loads (after `system`, if you
passed one). A model already loaded gets edited notes on `New chat`: the system
prompt is the first thing in the KV cache, so that is the one moment it can
change for free. The box says how many tokens the notes cost and when a loaded
model does not have the latest.

**Think.** Unticked, models load with `think = false`: short, direct answers,
which is what a quick question about a terminal wants (qwen3:4b: 22 s of
reasoning for a one-line answer with it on). For a model whose template has
Qwen's hybrid switch (qwen3.8:27b and nimble here) that is a real off switch:
the reply opens with an empty think block, as the model's own template writes
it, and the answer is the first thing generated. For the others it is a
directive that shortens the reasoning. Same timing as notes: at load, or on
`New chat`.

**Stats.** The bottom row, sampled once a second, read from `/sys` and `/proc`
in Julia:

| | what | from |
|---|---|---|
| GPU | busy %, a 90 s graph, temperature, watts, fan | xe: `gtidle/idle_residency_ms`, hwmon `energy1`, `temp` (pkg), `fan1`; amdgpu: `gpu_busy_percent`, `power1_average` |
| VRAM | used / total for the whole card, memory temperature | ggml's device query, the figure the planner budgets with; hwmon `temp` (vram) |
| model | tokens a second while it works (prefill and generation), a graph; the last reply's speed when idle | the session's token position |
| CPU | busy %, temperature | `/proc/stat`; k10temp / coretemp |
| RAM | used / total | `/proc/meminfo` |

**Servers.** LlamaChat runs models in its own process and frees them when you
say. A server is the other arrangement: `llama-server` (llama.cpp's
OpenAI-compatible HTTP endpoint, what opencode and other tools talk to) or
`laya serve` loads a model and keeps it on the card until its *process* ends.
Nothing unloads it. The `Servers` button counts the ones running and opens a
list read from `/proc`, every two seconds: what each serves, its address,
context, the VRAM it holds (from its DRM file descriptors), how long it has
been up, and `Stop`, which ends it and frees the card. A typed session's own
`laya daemon` shows there too, marked as this window's.

`Start` in the same menu serves a model from the store: `llama-server` on
127.0.0.1, from port 8090 (8080 is `laya serve`'s), one slot, `--jinja` (the
model's own template, which is what gives a client tool calls), with the
context, batch and flash attention the planner picks for the VRAM free at that
moment. It runs detached, so it outlives the window; its output is in
`~/.cache/llamachat/llama-server.log`. A server does not fit itself to the
card, so a model that would not go wholly on the GPU is refused, with what is
holding the memory. And when a model you load in the window lands on the CPU
because a server has the card, the transcript says which one.

```julia
LlamaChat.list_servers()                 # what is running
s = LlamaChat.serve("qwen3-coder")       # http://127.0.0.1:8090/v1, planner-sized
LlamaChat.stop_server(s.pid)
```

`llama-server` is not part of the Hub's llama.cpp package (which wraps the
library, not its tools); it has to be on PATH, or named in `$LLAMACHAT_SERVER`.
`llama-serve.sh` does the same start from a shell. Measured through opencode,
qwen3-coder (2026-11-14): 87 tok/s on a bare request, about 31 tok/s inside a
session, which starts some 8.5k tokens deep with opencode's own prompt.

A sensor the driver does not publish leaves its part of the row out.
`gui(...; stats = false)` leaves the whole row out. `LlamaChat.GUI.stats_text(app)`
is the row as words.

### Typed mode: decision models (Laya)

A second kind of model. A chat model reads a conversation and writes text; a
typed decision model reads a **state** and a set of **questions**, each with
its own answer options, and returns a probability for every option. Nothing is
generated, so an answer takes tens of milliseconds and a program branches on a
value instead of parsing a sentence. The models are Laya's (ModernBERT-large
plus a decision head, ~430 MiB each).

**The format.** A request is JSON, and a question is one of three types:

```json
{
  "state": {"message": "The webhook failed again. If it is not fixed today I am leaving."},
  "questions": {
    "intent":      {"type": "choice", "instructions": "What does the customer want in `message`?",
                    "criteria": {"refund": "money back", "technical_help": null, "cancellation": null}},
    "frustration": {"type": "score",  "instructions": "How frustrated does `message` sound?",
                    "criteria": ["calm", "concerned", "annoyed", "very angry"]},
    "churn_risk":  {"type": "noul",   "instructions": "Does `message` say the customer may leave?"}
  }
}
```

| type | `criteria` | the answer's `value` |
|---|---|---|
| `choice` | an object, `label: description` or `null`; 2–16 labels, in the order written | the winning label |
| `score`  | a list of levels, lowest first; 2–16 | the expected level, Σ level × p |
| `noul`   | optional, `{"false": …, "true": …}` | P(true) |

In Julia these are `Choice`, `Score` and `Noul`, and an answer is an `Answer`
(`value`, `confidence`, and `probabilities` as `option => p` in the question's
own order) inside a `Decisions`. Objects are parsed into an ordered map, not a
`Dict`: option order reaches the model, and a `Dict` shuffles it.

Everything is checked before it is sent, and a request that is wrong is a
`TypedFormatError` naming the field (`questions.intent.criteria: a choice takes
2 to 16 labels; this has 1`). The engine does not do this: a question typed
`"nope"` comes back as a confident empty choice.

A JSON file can be any of four things, and `load_typed` tells them apart:
a request (`state` + `questions`), a batch (`states` + `questions`, one
decision per state), questions alone, or a state alone (any other JSON, or
plain text).

**The store.** `LlamaChat.bring_laya()` adds the Laya GGUFs under
`~/ggmlc/models` (`$LLAMACHAT_LAYA_MODELS`) to LlamaChat's store as
`laya:<family>`, the family read from each file. They then sit in
`list_models()` and the window's model list next to the chat models, tagged
"typed decisions". `LlamaChat.add_model(path, name)` does the same for any
local GGUF. The blob is a hard link when it can be, so nothing is copied.

**Headless.**

```julia
LlamaChat.bring_laya()                                             # once
s = LlamaChat.TypedSession("laya:typed-decisions")
d = LlamaChat.decide(s, Dict("message" => "…"), read("questions.json", String))
d["intent"].value, d["intent"].probabilities, d["churn_risk"].value
LlamaChat.decide(s, LlamaChat.load_typed("request.json"))          # a file: one Decisions per state
LlamaChat.close!(s)
LlamaChat.decide("laya:typed-decisions", "request.json")           # load, run, free
```

`open_model(name)` returns a `ChatSession` or a `TypedSession`, whichever the
file is; `ChatSession` on a typed model is an error that says which to use.

**In the window.** Picking a typed model is the switch: the chat side becomes
a path box with `Load JSON` and `Files` (the `.json` files under the path, or
under your places when it is empty), a State box, a Questions box, `Decide`,
and the answers as a bar per option with the winner marked. A batch fills the
State box with `{"states": […]}` and each state gets its own row. `Ask` on a
terminal makes that terminal the state and decides at once, with three
questions about terminals (did something fail, what kind, how serious) unless
you loaded questions of your own. Picking a chat model switches back.

**How it runs.** A Laya GGUF is a ggmlc graph, which llama.cpp does not load,
and the runner is a C++ executable with no library behind it. So a
`TypedSession` owns a `laya daemon` process (`laya` on PATH, or
`$LLAMACHAT_LAYA`; device `$LLAMACHAT_LAYA_DEVICE`, default `vulkan:0`) and
sends it one JSON line per decision. It is the one model here that is not a
RepliBuild wrapper; that needs ggmlc built as a Hub package of its own.

Measured on the B60, typed-decisions file (2026-11-13): load 0.4 s; three
questions over a short state 53 ms; three questions over a 311-token request
155 ms.

**Nimble: the other kind of typed model.** Laya is an encoder with a decision
head. Nimble (Bespoke-Nimble-9B fused onto Qwen3.5-9B, 8.9 GiB at Q8_0) is a
language model trained to answer a typed question with one token, the letter
of the option it picks. Its GGUF says so (`qwen35.decision.type = "nimble"`)
and carries the prompt contract as a second chat template
(`tokenizer.chat_template.systemone`). `model_kind` calls such a file typed,
and `open_model` loads it as a `LogitSession`:

- it runs **in this process**, on the RepliBuild-wrapped llama.cpp, like chat;
- the prompt is decoded, the logits of the letters `A`, `B`, … are read off the
  last position, and their softmax (temperature 1) is the answer. Nothing is
  generated;
- same request format, same `Decisions` back, same panel in the window;
- every question's prompt carries the context and the whole schema and differs
  only in its last line, so the shared part is decoded once and each further
  question costs about 75 ms. Going back to the shared point is a checkpoint of
  the recurrent state plus dropping the attention cells after it (Qwen3.5 is a
  hybrid: most layers keep a running state that cannot be rewound by position);
- up to 26 options a question, 8192 tokens of prompt (what it was trained and
  served at).

Because it is a chat model underneath, the window shows a **Typed** box while
it is loaded: unticked, the same weights chat (a new conversation each time,
since a decision overwrites the chat's cache).

Measured on the B60, nimble, model loaded (2026-11-13):

| | Laya typed-decisions | nimble, typed | nimble, chat (`think = false`) |
|---|---|---|---|
| load | 0.4 s | 3.1 s + 1.2 s warm-up | same session |
| one short question | ~30 ms | 343 ms | ~0.5 s for a one-sentence answer |
| three questions, support ticket (437-token prompts) | 53 ms | 761 ms | – |
| three questions, agent step (311 / 414 tokens) | 155 ms | 565 ms | – |
| batch of 8 lines, one question each | ~20 ms each | 323 ms each | – |
| generation | none | none | 39.7 tok/s; prefill 1105 tok/s at 8k |

Nimble is 5–15× slower than Laya and far more decisive on the same examples:
the ticket's intent is `technical_help` at 0.95 (Laya 0.55), the journal lines
come back at 0.99–1.0 or 0.0–0.02 (Laya 0.23–0.75), and a failed `ls` in a
terminal is `failed: yes 1.0, kind: missing 1.0`. Its time is the prompt:
about 1.2 ms a token to read it, then one short tail per question.

**Prompt batching.** Both of those, and every chat turn, go through the same
finding about this backend: a llama_decode of up to 8 tokens takes ggml's
matrix-vector path, 9 or more its dequantise-and-multiply path, which has a
floor a small batch never gets under and is only efficient at a multiple of
128 tokens. So prompts are cut to fit (`_prompt_runs`, with the table): a run
of up to 31 tokens goes in chunks of 8, and a few tokens past a multiple of
128 are split off. A 20-token chat turn on qwen3.8:27b is read in 327 ms
instead of 682; 129 tokens in 574 ms instead of 1270.

### Startup: the sysimage

`sysimage/build.jl` builds `LlamaChat.so`, a PackageCompiler sysimage holding
LlamaChat, its three GUI wrappers, the GUI itself and the code a first frame
compiles:

```bash
DISPLAY=:1 julia -t 4 examples/LlamaChat/sysimage/build.jl
```

The GUI is the part a plain `create_sysimage([:LlamaChat])` misses: `using
LlamaChat` never loads it (the first `gui()` includes it), so that image only
removed the `using` time and left the slow part, including 1.7 MB of imgui
wrapper and compiling the first frames. `sysimage/workload.jl` therefore runs
as PackageCompiler's `script`, *inside* the image-writing process: it defines
`LlamaChat.GUI` and draws frames in a hidden window (markdown, coloured code,
the terminal, the Pull row), so all of that is in the image. It must not load
a model; an initialised-backend flag would be baked in with no backend behind
it.

An image is a snapshot: Julia runs the LlamaChat inside it and ignores `src/`.
`llamagui` uses `LlamaChat.so` only when it is at least as new as `src/` and
`Project.toml`, and otherwise starts without it and says so. Rebuild after
changing LlamaChat.

### Downloading models

**Pull...** opens a row: type a name from [ollama.com/library](https://ollama.com/library)
(`qwen3:0.6b`, `gemma3`, `someone/model:tag`) and press Enter or **Download**.
A progress bar shows size, speed and time left; **Cancel** stops it, and
pulling the same name again resumes where it stopped. When it lands, the
model is in the picker. You keep chatting while it downloads.

No ollama involved: this is `LlamaChat.pull`, which works from the REPL too.

```julia
LlamaChat.pull("qwen3:0.6b")      # prints a progress line; returns the weights' path
```

- **Where it goes.** LlamaChat keeps its own store,
  `~/.local/share/llamachat/models` (`$LLAMACHAT_MODELS` to move it), yours and
  writable without root, in ollama's layout. `pull` writes there and nowhere
  else. ollama's stores (`$OLLAMA_MODELS`, `/var/lib/ollama`,
  `~/.ollama/models`) are read as well, but never written. A part that an
  ollama store already has is copied across rather than downloaded, so the own
  store never depends on ollama's.
- **Moving off ollama.** `LlamaChat.import_ollama()` copies every model from
  ollama's stores into the own store (59 GB, five models, in 49 s here), and is
  safe to rerun. It trusts each file's sha256 name over the manifest's
  recorded size, because ollama had a stale size for qwen3-coder's config (539
  recorded, 542 on disk, digest intact). It never touches the originals;
  `/var/lib/ollama` belongs to the `ollama` user, so removing it is a `sudo`
  step for you.
- **How it is fast.** One connection to the registry's storage (Cloudflare R2)
  runs well below a home line; several saturate it (measured: 4.4–7.6 MiB/s
  on one, 11.2 MiB/s on four, on a ~95 Mbit/s line). So a large part is cut
  into 32 MiB byte ranges and six tasks (`Threads.@spawn`) fetch them through
  Julia's `Downloads`, each streaming straight to its offset in a
  preallocated file. qwen3:0.6b (498 MiB) took 62 s at the REPL.
- **Safety.** Finished ranges are logged beside the partial file, which is what
  resume reads. Every part is checked against its sha256 before it is renamed
  into place, and the manifest is written last, so a model either exists
  whole or not at all.
- **Two things learned on the way:** `Downloads` notifies a request's
  `interrupt` event itself when the request ends, so each request gets its own
  event (a shared one let the manifest request cancel every range). And
  `Downloads` waits on Julia's event loop, which only turns when the main task
  yields, so the render loop yields once a frame. That is safe because Julia
  runs the main task on an interactive thread, where a yield can never pick
  up a reply's `@spawn`ed task.

### The terminal

**Terminal** opens a real terminal beside the chat, running
`julia --banner=no` (this Julia's own executable, with your usual startup.jl)
in the directory `gui()` was started from. It starts without a shell, so
shell aliases do not apply; pass `terminal` for other flags. Drag the bar between them to share the width. **Hide terminal**
hides it and leaves the process running; **Restart** starts it again after it
exits.

- Tick **Attach** and your next message carries the terminal's last 120 lines.
  The model reads your REPL directly: the error, the stacktrace, what you
  typed. That replaces `ask`'s second window and kitty remote control. It is
  one message at a time: the box unticks after sending, and the transcript
  folds the attached lines under your message.
- Colours, bold, underline, the alternate screen (`less`, `htop`), resize
  (the child gets SIGWINCH), bracketed paste with Ctrl+Shift+V, and
  scrollback through the mouse wheel or Shift+PgUp/PgDn. Typing jumps back to
  the live screen.
- Not yet: F1–F12, text selection with the mouse, and emoji (the same 16-bit
  `ImWchar` limit as the chat).
- ``terminal = `bash` `` runs something else; `terminal_dir` sets where.

How it works: a pty from libc (`posix_openpt`), the child started as
`setsid --ctty --wait <cmd>` so the pty is its controlling terminal (job
control and Ctrl-C work, and this process never `fork`s). The bytes go
through **libvterm**, a VT220/xterm state machine wrapped by RepliBuild from
`packages/libvterm`, and imgui draws its grid. Everything runs on the render
thread: the pty is non-blocking and read once a frame, because a worker
blocked in `read()` would hold off every garbage collection in the process
until the child printed something.

Keywords: `terminal` (a `Cmd`, default `julia`), `terminal_dir`, `width`, `height`, `font` (a .ttf; default is fontconfig's sans,
override with `$LLAMACHAT_FONT`; bold, italic and mono come from fontconfig's
`sans:bold`, `sans:italic` and `monospace`), `font_size` (18), `max_tokens` per
reply (4096), `markdown` (true), `visible`, `vsync`. Everything else goes to `ChatSession` (`system`,
`n_ctx`, `think`, `temp`, …). `gui` is not exported; it is `LlamaChat.gui`.

### Requirements

- **Threads.** Start Julia with `-t 2` or more. The window, its GL context and
  every GLFW and imgui call stay on the calling thread. The model loads, and each
  reply generates, in a `Threads.@spawn` task that streams into a buffer the
  render loop reads once per frame. The window is created before the model
  loads, so the VRAM planner's free-memory reading already includes the GL
  context.
- **X11.** The GLFW build is X11-only, so `gui()` asks for the X11 platform
  itself and needs `$DISPLAY`. Under Hyprland (or any Wayland compositor) that
  is Xwayland: `DISPLAY=:1` on this machine. Without `$DISPLAY` it fails with a
  message listing the X servers it can find. In a `systemd-run --user` unit,
  pass `-E DISPLAY=:1 -E PATH="$PATH"` and `-t N` explicitly.
- **The wrappers**, in `lib/gui/` (below).

### `lib/gui/` and re-vendoring

`gui.jl` is not part of the package load. The first `LlamaChat.gui()` includes
it (≈5 s for the three wrappers), so a terminal session never maps libimgui,
libglfw, libvterm or libGL. It loads seven files from `lib/gui/`:

```
lib/gui/
├── Imgui.jl     libimgui.so  libimgui_thunks.so  # packages/imgui/julia
├── Glfw.jl      libglfw.so                       # packages/glfw/julia
└── Libvterm.jl  liblibvterm.so                   # packages/libvterm/julia
```

They live in a subdirectory because `lib/` already holds llama.cpp's
`compilation_metadata.json` and `thunk_manifest.json`. After rebuilding either
package, copy them again with one command, then restart Julia (an open session
keeps the copy it loaded):

```bash
examples/LlamaChat/vendor_gui.sh
```

The script refuses if a file is missing, prints each wrapper's
`BUILD_GENERATOR`, and fails if `libimgui.so` would bind any `libglfw.so` but
the one beside it. That check matters more than it looks. GLFW keeps
process-global state, so two copies in one process are two GLFWs, and
`glfwInit` on one does not initialise the other. Both wrappers resolve their
library next to their own `.jl`, and `libimgui.so`'s RUNPATH starts with
`$ORIGIN`, so the vendored pair binds one copy. The test suite checks
`/proc/self/maps` for exactly one. `HUB=/other/checkout vendor_gui.sh` copies
from another Hub checkout.

The Hub's imgui is built with `IMGUI_ENABLE_FREETYPE` and `IMGUI_USE_WCHAR32`
(`packages/imgui/replibuild.toml`), so `libimgui.so` also needs the system
`libfreetype.so.6`. Neither define is something the GUI has to be told about:
`HAS_FREETYPE` is whether the wrapper has `ImGuiFreeType_*`, and `WCHAR_BYTES`
is read from the struct layout DWARF gave it (ImFont's two adjacent ImWchar
fields), so a 16-bit build still works, minus text beyond U+FFFF.

### Measured

qwen3:4b on the Arc B60, in a hidden 900×640 window. A 160-token reply streams
at 77–92 tok/s across runs (the terminal path does the same) while frames hold
at 17.1 ms median and 20 ms worst. Frames do not wait on tokens.

The one way found to stall the UI is a long prompt meeting a garbage
collection. Julia's GC stops every thread at a safepoint, and a thread inside
`llama_decode` reaches none until the call returns. Prefill runs in `n_batch`
chunks, so a GC that lands during a long paste holds the window for the rest
of a chunk. Measured on a 3,379-token paste:

| `n_batch`     | prefill | worst frame, no GC | worst frame, GC forced mid-prefill |
|---------------|---------|--------------------|------------------------------------|
| 512 (default) | 3.42 s  | 26.7 ms            | 257.7 ms                           |
| 128           | 5.10 s  | 17.6 ms            | 43.8 ms                            |

Left alone, no GC landed: the render loop allocates little per frame (it takes
a new snapshot of the reply only when bytes arrived), so collections are rare.
The default stays at 512, because 128 costs half again on every long prefill. If
long pastes do stutter for you, trade that time back with
`LlamaChat.gui(; n_batch = 128)`.

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

## Running on the GPU

The vendored wrapper carries ggml's **Vulkan** backend, so `lib/libllamacpp.so`
can offload to the Arc Pro B60 (Battlemage, 24 GB, on the `xe` kernel driver)
through Mesa's ANV driver. Nothing about that
crosses the RepliBuild boundary — the kernels are ggml's, already compiled into
the `.so` as SPIR-V, and the thunks stay host-side. One parameter turns it on:

```julia
s = ChatSession("qwen3:4b"; n_ctx = 8192)    # nothing to pass — auto picks the GPU
```

**`n_gpu_layers` defaults to `:auto`**, which reads the model's GGUF header and
places it inside a VRAM budget. Nothing to remember per model, and a model that
does not fit runs on CPU instead of killing your REPL.

That last part is the reason this exists. llama.cpp does **not** fit-to-available
— ask for more layers than the card holds and it attempts the allocation and
calls `abort()` from inside ggml-vulkan. There is no Julia exception to catch:
the REPL, the loaded model and your session go with it. So the decision is made
from numbers before the load.

An explicit `n_gpu_layers = N` is honoured but bounds-checked, and an
over-budget value is **refused as a normal Julia error** rather than warned
about — a warning followed one second later by process death is not a warning.

| Variable | Default | Meaning |
|---|---|---|
| `LLAMACHAT_NGL` | `auto` | `auto`, or an integer to force |
| `LLAMACHAT_VRAM_GB` | live | VRAM the planner may spend |
| `LLAMACHAT_RAM_GB` | `35` | CPU-side ceiling |

The default is what Vulkan reports free on the card **now**, less 0.5 GiB: about
20.5 GiB on an idle desktop. Where 24 GB goes: 96 MiB is Battlemage's
compression metadata (`FLAT_CCS`, 1/256 of VRAM), leaving 23.91 GiB; the desktop
holds ~0.6 GiB (Steam's web helper, this app's renderer); and Mesa's
`VK_EXT_memory_budget` reports 90% of what is left, ~21.0 GiB, keeping the rest
as headroom. Reading it live means a game or a second loaded model shrinks the
budget instead of turning the plan into an over-commit, which is an abort, not a
swap. Before the backend is up the B60's 20.5 stands in.

**`n_ctx` defaults to `:auto`** as well: 32768, or the largest window (rounded
down to 1024) that keeps the whole model on the GPU, whichever is smaller. That
is what puts `load("qwen3-coder")` on the card with no flags — it opens at
29696 instead of going partial at 32k. (On the A750 it did the same for
qwen3:4b, at about 26k.) A model that would only fit below 8192
keeps 32768 and the partial/CPU plan. Pass `n_ctx` to choose it yourself; an
explicit value is never resized.

### Context is the expensive half

The thing that makes a size-of-file check useless: **qwen3:4b is 2.33 GiB of
weights and 144 KiB/token of KV cache.** At the default `n_ctx = 32768` that is
**4.5 GiB of cache — nearly twice the model.**

```
at the old 5 GiB budget:
ctx=2048…8192   →  ngl=99   whole model on GPU
ctx=16384       →  ngl=35   partial (35 of 36 layers)
ctx=32768       →  ngl=0    CPU — "n_ctx ≤ 15832 would fit it on the GPU"
```

So `n_ctx` is the dial that decides GPU vs CPU for a model this size, not the
quantization. The KV figure comes from `block_count`, `head_count_kv` and
`attention.key_length`/`value_length` in the GGUF header — read explicitly,
because deriving head_dim as `embedding_length ÷ head_count` gives 80 where
qwen3's truth is 128, a 1.6× under-count of every KV byte. A hybrid model (qwen3.6,
qwen3.8: Gated DeltaNet with full attention every fourth layer) keeps KV only on
its full-attention layers, which the header says per layer (`head_count_kv` is
an array, 0 on a linear layer) or through `full_attention_interval`; counting
every layer put qwen3.6's cache at 32× its size. Its linear layers carry a fixed
recurrent state instead (63 MiB for qwen3.6), which the plan adds once.

Falling back to CPU always prints a line. A silent fallback is
indistinguishable from a broken GPU build — the Vulkan backend still
initializes, the card still gets opened, two DRI fds still appear, and the
weights go to RAM anyway.

What fits on the B60 (20.5 GiB budget), from the GGUF headers:

| Model | Weights | KV/token | Placement |
|---|---|---|---|
| qwen3-coder 30B-A3B (MoE, 128 experts) | 17.28 GiB | 96 KiB | whole, at n_ctx 29696 (49/49 layers) |
| qwen3.8:27b (dense, hybrid attention) | 15.66 GiB | 64 KiB | whole, at 32768 |
| qwen3:4b | 2.33 GiB | 144 KiB | whole, at 32768 |
| qwen3.6:35b 35B-A3B (MoE, 256 experts) | 22.29 GiB | 20 KiB | partial, 31/40: the weights alone pass the budget |

qwen3.6 would need expert offload (experts in RAM, attention on the card), which
is not built. For qwen3-coder the plan said 20.5 GiB and llama.cpp allocated
20.16 (17.11 weights, 2.72 KV, 0.29 compute).

Measured through `chat()`, a 1,787-token prompt then up to 256 tokens, `temp = 0`
(Ryzen 9 5900XT, Mesa 26.2.6, 2026-11-08):

| | Prefill | Generation |
|---|---|---|
| qwen3-coder, B60 | **815 tok/s** | **50.2 tok/s** |
| qwen3-coder, CPU (`n_gpu_layers = 0`) | 114 tok/s | 9.6 tok/s |
| qwen3:4b, B60 (`n_ctx = 8192`) | 1500 tok/s | 69.1 tok/s |
| qwen3:4b, A750 (2026-09) | — | 55.3 tok/s |

**5.2× on generation, 7× on prefill, for the 30B MoE.** The B60 numbers need the
Hub package's `GGML_VULKAN_*_GLSLC_SUPPORT` defines (2026-11-08): without them
ggml reports `matrix cores: none | int dot: 0` and the same runs were 202/33.1
and 474/57.4 tok/s. ggml enables Intel's cooperative-matrix path only on Xe2,
so the A750 never used it. Note that qwen3 is a *reasoning* model — it opens with a `<think>`
block, so a low `max_tokens` returns an empty-looking answer because generation
never escaped the thinking. Budget a few hundred tokens before concluding
anything is broken.

### The sweet spot: flash attention, batch, KV cache

Generation speed is set by what each token reads: the weights, and the KV cache
of everything in context. So a chat slows as it grows, and on this card the
attention kernels make it slow faster than bandwidth explains. qwen3:4b,
`LlamaChat.bench`, f16 KV:

| flash attention | n_batch | gen, fresh | prefill 8k | gen at 8k | prefill 24k | gen at 24k |
|---|---|---|---|---|---|---|
| on  | 2048 |  93.1 |  551 | 43.5 | 247 | **10.6** |
| off | 2048 |  86.0 |  975 | 50.1 | **35.5** | 27.6 |
| off |  512 |  87.5 |    – |    – | 532 | 23.5 |

Without flash attention llama.cpp materialises the attention scores,
n_ubatch × n_ctx × n_head × f32 of compute buffer: one copy while that is up
to 768 MiB, two from 1 GiB (4194 MiB at 512/32k for qwen3:4b, to the MiB). At
2048 that is 16 GiB, more than the card: the run did not abort, it crawled.
The planner counts it (`attn_scores_bytes`), so `n_batch` and the window
shrink to fit instead, and with flash attention off `n_batch` may go down to
256 to stay in the one-copy case: that is what gives qwen3.8:27b its whole
window (0.83 GiB of buffer at 256/32768, against two copies of 1.5 GiB at 512).

`flash_attn = :auto` (the default) turns it off when that keeps the context
window it would have had with it on — context first, then speed, the same rule
as `n_batch`. The four models here, 8k paste then 256 tokens:

| model | chosen | window | gen | prefill 8k | gen at 8k | the other setting |
|---|---|---|---|---|---|---|
| qwen3:4b    | off | 32768 | 86.8 | 1051 | 50.2 | on: 93.1 / 551 / 43.5 |
| gemma4:26b  | off | 32768 | 60.9 | 1062 | 50.8 | on: 57.7 / 267 / 29.7 |
| qwen3-coder | on  | 30720 | 83.4 |  299 | 28.5 | off: 22528 window (n_batch 256), 77.5 / 504 / 42.9 |
| qwen3.8:27b | off | 32768 | 17.4 |  290 | 16.1 | on: 17.9 / 254 / 13.5 |

For qwen3-coder on long code, `flash_attn = :off` trades a quarter of the
window for 1.5–1.7× speed; it is a choice, so it is not the default.

qwen3.8:27b is a dense 27B: every token reads its 15 GiB of weights, and the
Vulkan timings (`GGML_VK_PERF_LOGGER=1`) put the q4_K matrix-vector products
at about 370 GB/s, the card's memory bandwidth. So ~18 tok/s on a fresh context
is the ceiling for this quantisation, and none of ggml-vulkan's switches
(`GGML_VK_FORCE_MMVQ`, `…_DISABLE_FUSION`, `…_ALLOW_GRAPHICS_QUEUE`,
`…_MAX_NODES_PER_SUBMIT`, thread count) moves it. What flash attention decides
is how fast that falls as the chat grows (n_batch 256, 2026-11-12):

| flash attention | gen, fresh | prefill 8k | gen at 8k | prefill 24k | gen at 24k |
|---|---|---|---|---|---|
| on  | 17.9 | 254 | 13.5 | 141 | **4.0** |
| off | 16.9 | 290 | 15.7 | 259 | **12.8** |

- **`kv_type`** (`:f16`, `:q8_0`, `:q4_0`; `$LLAMACHAT_KV`). q8_0 halves the
  cache, which buys window (qwen3-coder: 32k with n_batch 1024), but on this
  card it is *slower*: 24.5 against 42.5 tok/s at 8k for qwen3:4b, since the
  flash-attention path dequantises as it goes. Memory, not speed.
- **Sliding-window layers** (Gemma 4: 25 of 30) cache only their window plus
  a ubatch. LlamaChat opens contexts with `swa_full = false`; llama.cpp's
  default keeps a full-length cache for them too (3.2 GiB of gemma4's 16k
  window), needed only to roll a cache back, which LlamaChat never does. The
  planner counts them the same way, which is what moved gemma4:26b from a
  10240 window to 32768.

- **Load time.** A model going wholly to the card is read, not memory-mapped
  (`load_mode = NONE`): the upload out of a mapping page-faults its way through
  the file, 4.6 s against 2.1 s for qwen3.8:27b from the page cache. A model
  with layers on the CPU keeps the mapping. The planner also parses each GGUF
  header once per file now instead of some thirty times a load (1 s for a
  248k-token vocabulary). `ChatSession("qwen3.8:27b")`, warm: 7.1 s → 2.1 s;
  qwen3-coder 2.2 s, qwen3:4b 0.55 s (2026-11-12).

### Headless: `reply`, `bench`, `sweep`

```julia
r = LlamaChat.reply("qwen3:4b", "Name three moons of Jupiter."; think = false)
LlamaChat.bench("gemma4:26b"; depth = 8192)          # one line: load, VRAM, gen, prefill, gen at depth
LlamaChat.sweep("qwen3:4b"; n_batch = (512, 2048), kv_type = (:f16, :q8_0), flash_attn = :off)
```

No window, no markdown redraw, plain text out: for scripts, for comparing
settings, and for an agent that reads output rather than looks at it. `bench`
loads, measures at `temp = 0` with thinking off (a fresh-context run, then a
`depth`-token paste of this package's own source), frees, and returns every
number as a NamedTuple.

### Terse mode

`think = false` shortens the reasoning and folds the block out of the reply:

```julia
s = ChatSession("qwen3:4b"; think = false)   # or /nothink in the REPL
```

Measured on qwen3:4b, `temp = 0`, two prompts: **662 → 201 generated tokens,
11.8 s → 3.9 s**, and "Say hello." answers `Hello!` instead of 280 tokens of
deliberation.

That is the directive, for models whose template has no switch. Where the
template has Qwen's hybrid switch (`enable_thinking`; qwen3.8:27b and nimble of
the models here) `think = false` uses it instead: the reply is prefilled with
the closed, empty think block the template itself writes, and nothing is added
to the system prompt. "Say hello in three words.", temp 0, nimble: 300+ tokens
of reasoning with the directive, `Hello there, friend!` in 5 tokens with the
switch; qwen3.8:27b: 3 tokens. Which a model gets is read from its template,
not its name.

For the rest the directive **shortens** reasoning; it cannot disable it:

- Qwen3's documented `/no_think` switch does nothing here. It is implemented in
  the model's Jinja template, which strips the token — `llama_chat_apply_template`
  is a matcher over known templates, not a Jinja engine, so the literal text
  reaches the model and it reasons *about* it.
- `enable_thinking = false` has nothing to set: that key does not appear in this
  model's template at all. Its generation prompt is unconditionally
  `<|im_start|>assistant\n<think>\n`. qwen3:4b is the *Thinking* variant — the
  hybrid switch was a Qwen3-2504 feature, and later releases split Instruct and
  Thinking into separate models.
- Prefilling an empty `<think></think>` only removes the *tags* (606 tok vs 662).
  The model keeps reasoning in prose, which then lands in the visible answer —
  strictly worse, and it destroys the marker needed to fold the block.

So the flag is a system-prompt directive plus display folding. It is
session-level because it changes the system prompt, and changing that
mid-conversation re-renders every earlier turn — `/think` and `/nothink` clear
the conversation for the same reason `/system` does.

`history` and the KV cache always keep the raw reasoning; only what the caller
sees is trimmed. Storing the folded text would break `_format`'s byte-exact
prefix check and silently rebuild the whole cache every turn.

One API-ordering trap if you query the device directly:
`ggml_backend_vk_get_device_memory` asserts on
`device < vk_instance.device_indices.size()`, and that vector is populated when
the instance initializes. Calling it before `ggml_backend_vk_get_device_count()`
aborts the process — a `GGML_ASSERT` failure, not a Julia exception, so it takes
the REPL with it.

`GGML_DISABLE_VULKAN=1` unregisters the backend entirely, which is the switch to
reach for when comparing against CPU or when the driver misbehaves —
`ggml-backend-reg.cpp` reads it at registration time, so one build serves both
paths and there is no separate CPU library.

## Layout

```
LlamaChat/
├── Project.toml         # depends on RepliBuild (the wrapper dispatches through its JIT)
├── lib/                 # RepliBuild build + wrap output — the ABI layer, never edited
│   ├── Llamacpp.jl
│   ├── libllamacpp.so
│   ├── compilation_metadata.json
│   ├── thunk_manifest.json
│   └── gui/             # Imgui.jl, Glfw.jl, Libvterm.jl and their .so — vendor_gui.sh copies them
├── src/
│   ├── LlamaChat.jl     # the ergonomic layer — sessions, templating, KV bookkeeping
│   ├── window.jl        # ask(): sidecar window, ptys, scrollback capture
│   ├── gui.jl           # gui(): imgui window, loaded on first call
│   ├── pull.jl          # pull(): ollama-registry downloads, parallel ranges, resume
│   ├── gui_md.jl        # gui(): markdown parsed once per block, laid out per frame
│   ├── gui_highlight.jl # gui(): syntax colours for code blocks
│   └── gui_term.jl      # gui(): the embedded terminal — pty, libvterm, imgui grid
├── chat.jl              # thin launcher for shell use
├── vendor_gui.sh        # copy the imgui + GLFW wrappers into lib/gui/
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

### Templates llama.cpp does not know: Gemma 4

`llama_chat_apply_template` matches a model's Jinja template against formats it
knows; it is not a Jinja engine. For anything else it returns -1, and LlamaChat
falls back to ChatML. Gemma 4's `<|turn>user … <turn|>` is one it does not know
(b10286), and ChatML is text Gemma 4 never trained on: gemma4:26b answered with
a stray `<|channel>thought` tag and then garbage. `_format_gemma4` writes the
format out (text chat, no tools), and `think` maps to the template's own
`enable_thinking`: on, `<|think|>` opens a system turn and the reasoning
arrives in a thought channel, which folds like `<think>`. Off, the generation
prompt closes an empty channel, so Gemma 4 gets no terse directive. One
difference from the Jinja: earlier replies keep their reasoning
(`preserve_thinking`), because stripping it would change cached bytes and
re-decode the conversation every turn. Measured on the B60: 55–57 tok/s, a
second turn feeding 18–22 prompt tokens.

## Building the wrapper

`lib/` is RepliBuild output, not vendored source. With RepliBuild installed:

```julia
using RepliBuild
RepliBuild.build("packages/llamacpp/replibuild.toml")   # → libllamacpp.so + compilation_metadata.json
RepliBuild.wrap("packages/llamacpp/replibuild.toml")    # → Llamacpp.jl
```

then copy the **five** artifacts into `lib/`: `Llamacpp.jl`, `libllamacpp.so`,
`libllamacpp_thunks.so`, `compilation_metadata.json`, `thunk_manifest.json`.

Two things about that sequence are not optional since the Vulkan backend went
in, and both cost a wasted rebuild if skipped:

1. **The shaders must be harvested first.** ggml-vulkan ships 136 GLSL `.comp`
   files and a generator built as a CMake ExternalProject, which RepliBuild's
   resolver cannot run. `packages/llamacpp/harvest_vulkan_shaders.sh` stands in
   for it, emitting 136 `.cpp` of embedded SPIR-V plus a header into
   `packages/llamacpp/vulkan/` (206 MB, gitignored, regenerable). It reads the
   dependency clone, which `build()` creates — so on a cold package run
   `build()` once, then the script, then build for real.
2. **`build()` then `wrap()` twice.** `aot_thunks = true` compiles Tier-2 thunks
   from the *previous* wrap's manifest, so the first pass after any change to
   the exported surface fails in `_assert_aot_thunks_present`. That refusal is
   expected, not a bug; run the pair again and it binds.

A cold rebuild is a 200 MB clone and 332 TUs — `ggml-vulkan.cpp` alone is 19k
lines pulling in `vulkan.hpp` and takes ~107 s, and DWARF extraction ~199 s — so
it is deliberately not a routine step.

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

The GUI tests open a hidden window, type into it through `ImGuiIO`, stream a
short reply on a worker while rendering, click Stop, and check the pixels
against the window's own background. They skip cleanly without `lib/gui/`,
without `$DISPLAY`, or with fewer than two threads, so run the suite as:

```bash
DISPLAY=:1 julia -t 4 --project=examples/LlamaChat examples/LlamaChat/test/runtests.jl
```
