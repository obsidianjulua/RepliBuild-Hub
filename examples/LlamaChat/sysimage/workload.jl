# The sysimage workload: run INSIDE the process that writes LlamaChat.so
# (PackageCompiler's `script`), so what it defines and compiles is in the image.
#
# Why `script` and not `precompile_execution_file`: the GUI is not loaded by
# `using LlamaChat`; the first `gui()` includes src/gui.jl into a fresh module,
# `LlamaChat.GUI`. An execution file runs in a separate process and is only
# traced, and its statements are replayed before any `script` runs — when no
# `LlamaChat.GUI` exists yet — so every one naming the GUI would be dropped.
# Run here instead, `_gui_module()` defines the module in the image (gui() then
# skips the ~5 s include) and the frames below compile the drawing code into it.
#
# Do NOT load a model here. `LlamaChat._backend_up` would be baked in as true
# with no backend behind it, and every later load would skip the init it needs.

using LlamaChat

# Everything below is inside `let`: a global here (a `const GM`, say) would be
# baked into the image's Main and taken in every session started with it.
let GM = LlamaChat._gui_module()

# Writing a sysimage defers every module's __init__ to image load (that is where
# handles and addresses exist), so the wrappers just included have not run
# theirs: imgui's thunk table is empty and the first frame would call through
# a null pointer ("AOT thunk pointer is null"). Run them for the workload; they
# are idempotent, and the image runs them again at every start.
for m in (GM.Imgui, GM.Glfw, GM.Libvterm)
    isdefined(m, :__init__) && Base.invokelatest(getfield(m, :__init__))
end

Base.invokelatest() do
    LlamaChat.list_models()
    LlamaChat.pull_status(LlamaChat.PullProgress("warmup"))
    # Its own notes and places: an image build should not read yours.
    tmp = mktempdir()
    app = GM.App(; visible = false, vsync = false, notes_file = joinpath(tmp, "notes.md"),
                 places = [GM.Place("warmup", tmp)], terminal_dir = tmp)
    try
        md = """
        # A heading

        Some **bold**, *italic*, `inline code` and a [link](https://example.com).

        - one
        - two
          1. nested

        > a quote

        | a | b |
        |---|---|
        | 1 | **2** |

        ```julia
        f(x) = x^2 + 0x10   # square
        println(f(3), :sym, "s")
        ```

        ```cpp
        #include <cstdio>
        int main() { return printf("%d", 42); }
        ```

        ```toml
        [table]
        key = "value"
        ```

        ---
        """
        push!(app.turns, GM.Turn(:user, 1, "hello"))
        t = GM.Turn(:assistant, 2, "<think>\nthinking it over\n</think>\n\n" * md, "warmup")
        t.stats = "[warmup]"
        push!(app.turns, t)
        push!(app.turns, GM.Turn(:ready, 3, "warmup is ready"))
        push!(app.turns, GM.Turn(:note, 4, "a note"))
        push!(app.turns, GM.Turn(:error, 5, "an error"))
        for _ in 1:6
            GM.step!(app)
        end
        # The terminal: pty, libvterm, the grid, colours.
        app.term_cmd = `sh -c 'printf "\033[1;31mred\033[0m and plain\n"; sleep 0.5'`
        GM.toggle_terminal!(app)
        for _ in 1:40
            GM.step!(app)
        end
        GM.term_text(app.term)
        # A second tab, Ask with no model (a note), the notes box, the stats row.
        GM.open_terminal!(app, `sh -c 'sleep 0.3'`, tmp)
        app.notes_open = true
        for _ in 1:4
            GM.step!(app)
        end
        GM.term_where(app.term); GM.cd_line(:julia, tmp); GM.cd_line(:shell, tmp)
        GM.ask_terminal!(app)
        GM.sample!(app.stats); GM.stats_text(app); GM.system_text(app)
        GM.step!(app)
        GM.close_terminal!(app)
        app.notes_open = false
        GM.load_places(joinpath(tmp, "places")); GM.default_places()
        # Typed mode's own code, without a model: the format and the boxes.
        tf = LlamaChat.parse_typed("""{"state": {"m": "hi"}, "questions": $(GM.TYPED_SAMPLE_QUESTIONS)}""")
        LlamaChat.questions_json(tf.questions); LlamaChat.parse_typed(GM.TYPED_TERMINAL_QUESTIONS)
        try LlamaChat.parse_questions(LlamaChat._parse_json("{\"q\": 1}")) catch end
        GM.typed_defaults!(app); GM.typed_states(GM.buf_text(app.typed_state)); GM.json_files(tmp)
        GM.typed_load!(app, joinpath(tmp, "missing.json")); GM.typed_decide!(app)
        # The Servers view: reading /proc, with whatever is or is not running.
        LlamaChat.list_servers(); GM.refresh_servers!(app); GM.poll_servers!(app)
        GM._uptime(time() - 100.0); LlamaChat.port_open(1); LlamaChat.stop_server(0)
        LlamaChat.served_id("a:b"); LlamaChat.write_preset(NamedTuple[], joinpath(tmp, "p.ini"))
        LlamaChat.opencode_sync(NamedTuple[], 1; file = joinpath(tmp, "none", "opencode.json"))
        GM.toggle_terminal!(app)
        # The Pull row, the status line, a pixel readback.
        app.pull_open = true
        for _ in 1:3
            GM.step!(app)
        end
        GM.capture!(app)
        GM.status_text(app); GM.prompt_hint(app); GM.indicator(app)
        # Themes: apply each once (the menu's draw ran above), then back.
        k0 = app.theme
        for k in eachindex(GM.THEMES)
            GM.apply_theme!(app, k); GM.step!(app)
        end
        GM.apply_theme!(app, k0)
        LlamaChat._md_prep("costs \$10, \$x^2\$ and ***this***")
    finally
        GM.close!(app)
    end
end
end
