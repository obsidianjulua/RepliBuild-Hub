# Typed mode. Included by gui.jl, inside `module GUI`.
#
# The window is in typed mode while the loaded model is a typed decision model
# (`LlamaChat.TypedSession`): picking one in the model list is the switch. The
# chat side then shows, in place of the transcript and the message box:
#
#   a path box      a JSON file to load (request, batch, questions or state:
#                   `LlamaChat.TypedFile`), or a folder to list
#   State           what the model looks at: JSON or plain text, editable
#   Questions       the questions object, editable; checked before it is sent
#   Decide          runs it on a worker; each answer is drawn as bars
#
# Nothing here generates text, so there is no transcript to keep: the boxes are
# the request and the bars are the answer.

const TYPED_BUF = 64 * 1024

buf_text(b::Vector{UInt8}) = GC.@preserve b unsafe_string(pointer(b))

"""Put `s` in a NUL-terminated box buffer, cut at a character boundary if it is too long."""
function set_buf!(b::Vector{UInt8}, s::AbstractString)
    s = String(s)
    sizeof(s) >= length(b) && (s = s[1:prevind(s, length(b) - 4)])
    fill!(b, 0x00)
    copyto!(b, 1, codeunits(s), 1, sizeof(s))
    return b
end

typed(app) = app.session isa LC.AnyTyped

# What the boxes hold before anything is loaded: one question of each type.
const TYPED_SAMPLE_STATE = """
{
  "message": "This is the third time the webhook failed this week. If you cannot fix it today I am moving to a competitor."
}"""
const TYPED_SAMPLE_QUESTIONS = """
{
  "intent": {
    "type": "choice",
    "instructions": "What does the customer want in `message`?",
    "criteria": {
      "refund": "money returned or a duplicate charge reversed",
      "technical_help": "a bug, outage, or integration problem",
      "cancellation": "wants to cancel, downgrade, or leave",
      "other": "none of the other options fits"
    }
  },
  "frustration": {
    "type": "score",
    "instructions": "How frustrated does the customer sound in `message`?",
    "criteria": ["calm and neutral", "concerned but civil", "clearly annoyed", "very angry"]
  },
  "churn_risk": {
    "type": "noul",
    "instructions": "Does `message` say the customer may leave or cancel?"
  }
}"""

# What Ask puts to a typed model about a terminal, unless you loaded questions of your own.
const TYPED_TERMINAL_QUESTIONS = """
{
  "failed": {
    "type": "noul",
    "instructions": "Does `terminal` show a command that failed or printed an error?",
    "criteria": {"false": "everything shown ran normally", "true": "a command failed or an error was printed"}
  },
  "kind": {
    "type": "choice",
    "instructions": "What kind of problem does `terminal` show?",
    "criteria": {
      "nothing_wrong": "no error is shown",
      "missing": "a file, folder, command or package was not found",
      "permission": "access was denied",
      "build": "a compile, link or syntax error",
      "runtime": "the program ran and then threw, crashed or timed out",
      "network": "a connection, DNS or download failure"
    }
  },
  "severity": {
    "type": "score",
    "instructions": "How serious is what `terminal` shows?",
    "criteria": ["nothing to do", "a typo or one-line fix", "needs investigation", "data loss or a broken system"]
  }
}"""

"""Fill empty boxes with the sample, so a freshly loaded typed model can Decide at once."""
function typed_defaults!(app)
    if isempty(strip(buf_text(app.typed_q))) && isempty(strip(buf_text(app.typed_state)))
        set_buf!(app.typed_state, strip(TYPED_SAMPLE_STATE))
        set_buf!(app.typed_q, strip(TYPED_SAMPLE_QUESTIONS))
        app.typed_builtin = true
        app.typed_note = "A sample: one question of each type. Edit it, or load a JSON file."
    end
    return app
end

_pretty(x) = x isa AbstractString ? String(x) : LC.JSON.json(x, 2)

"""
    typed_load!(app, path) -> Bool

Read a JSON file into the boxes. What it fills depends on what the file is
(`LlamaChat.TypedFile`): a request fills both, a batch fills the state box with
`{"states": […]}`, a questions file or a state file fills its own box and
leaves the other. A file that is not in the format says why, in the panel.
"""
function typed_load!(app, path::AbstractString)
    p = expanduser(String(strip(path)))
    app.typed_err = ""
    f = try
        isfile(p) || error("no such file: $p")
        LC.load_typed(p)
    catch e
        e isa InterruptException && rethrow()
        app.typed_err = sprint(showerror, e)
        return false
    end
    if f.kind === :batch
        set_buf!(app.typed_state, _pretty(LC.ODict("states" => f.states)))
    elseif !isempty(f.states)
        set_buf!(app.typed_state, _pretty(f.states[1]))
    end
    if !isempty(f.questions)
        set_buf!(app.typed_q, _pretty(LC.questions_json(f.questions)))
        app.typed_builtin = false
    end
    empty!(app.typed_out)
    nq, ns = length(f.questions), length(f.states)
    app.typed_note = string("Loaded ", basename(p), ": ",
        f.kind === :request ? "a request, $nq question$(nq == 1 ? "" : "s")" :
        f.kind === :batch ? "a batch of $ns states, $nq question$(nq == 1 ? "" : "s")" :
        f.kind === :questions ? "$nq question$(nq == 1 ? "" : "s"); the state is unchanged" :
                                "a state; the questions are unchanged")
    set_buf!(app.typed_path, p)
    return true
end

"""
The states the State box holds: the list under `states` when the box is exactly
`{"states": […]}`, else the box as one state — parsed JSON, or the text itself
when it is not JSON.
"""
function typed_states(text::AbstractString)
    v = try LC._parse_json(text) catch; return Any[String(strip(text))] end
    v isa LC.ODict && length(v) == 1 && get(v, "states", nothing) isa AbstractVector && !isempty(v["states"]) &&
        return collect(Any, v["states"])
    return Any[v]
end

"""
    typed_decide!(app) -> Bool

Check the boxes and run them on a worker. `false`, with the reason in the
panel, when the questions are not in the format or the state is empty.
"""
function typed_decide!(app)
    (typed(app) && app.state === :idle && !app.closing) || return false
    app.typed_err = ""
    st = buf_text(app.typed_state)
    if isempty(strip(st))
        app.typed_err = "state: is empty; give the model something to look at"
        return false
    end
    s = app.session
    qs = try
        obj = try LC._parse_json(buf_text(app.typed_q)) catch e
            e isa InterruptException && rethrow()
            throw(LC.TypedFormatError("questions", "is not valid JSON"))
        end
        LC.parse_questions(obj; max_options = s.info.max_opts)
    catch e
        e isa LC.TypedFormatError || rethrow()
        app.typed_err = sprint(showerror, e)
        return false
    end
    states = typed_states(st)
    app.typed_states = states
    app.state = :deciding
    app.t_start = time()
    app.task = Threads.@spawn [LC.decide(s, x, qs) for x in states]
    return true
end

"""Ask, in typed mode: the terminal becomes the state, and it is decided at once."""
function typed_ask!(app, t)
    (app.state === :idle && !app.closing) || return false
    set_buf!(app.typed_state, _pretty(LC.ODict("where" => term_where(t), "terminal" => term_text(t; lines = 40))))
    if app.typed_builtin || isempty(strip(buf_text(app.typed_q)))
        set_buf!(app.typed_q, strip(TYPED_TERMINAL_QUESTIONS))
        app.typed_builtin = true
    end
    app.typed_note = "The state is $(term_where(t)), its last 40 lines."
    return typed_decide!(app)
end

"""JSON files under `dir`, two levels deep, dot-folders left out, at most 80."""
function json_files(dir::AbstractString)
    out = String[]
    isdir(dir) || return out
    try
        for f in sort!(readdir(dir))
            p = joinpath(dir, f)
            if endswith(f, ".json") && isfile(p)
                push!(out, p)
            elseif isdir(p) && !startswith(f, ".")
                for g in sort!(readdir(p))
                    endswith(g, ".json") && isfile(joinpath(p, g)) && push!(out, joinpath(p, g))
                end
            end
            length(out) >= 80 && break
        end
    catch
    end
    return out
end

_state_label(x) = (s = replace(x isa AbstractString ? String(x) : LC.JSON.json(x), r"\s+" => " ");
                   length(s) > 90 ? first(s, 90) * "…" : s)

function answer!(app, a::LC.Answer, w::Float32)
    colored(() -> text!(a.id), C_USER)
    G.ImGui_SameLine(0f0, app.fonts.size * 0.6f0)
    colored(() -> text!(string(a.type)), app.dim)
    G.ImGui_SameLine(0f0, app.fonts.size * 0.6f0)
    text!(LC.headline(a))
    G.ImGui_SameLine(0f0, app.fonts.size * 0.6f0)
    colored(() -> text!("conf " * string(round(a.confidence; digits = 2))), app.dim)
    bar(p, label, win) = begin
        G.ImGui_ProgressBar(isnan(p) ? 0f0 : Float32(clamp(p, 0, 1)), Ref(vec2(w, 0)), string(round(p; digits = 3)))
        G.ImGui_SameLine(0f0, app.fonts.size * 0.5f0)
        win ? colored(() -> text!(label), C_READY) : text!(label)
    end
    if a.type === :noul
        bar(a.value, a.value >= 0.5 ? "yes" : "no", a.value >= 0.5)
    else
        top = argmax(map(p -> isnan(last(p)) ? -1.0 : last(p), a.probabilities))
        for (i, (label, p)) in enumerate(a.probabilities)
            bar(p, a.type === :score ? "$(i - 1)  $label" : label, i == top)
        end
    end
    G.ImGui_Spacing()
end

function typed_results!(app)
    G.ImGui_BeginChild("##typedout", ZERO, Cint(G.ImGuiChildFlags_Borders), Cint(0))
    w = Float32(clamp(0.38f0 * G.ImGui_GetContentRegionAvail().x, 120f0, 420f0))
    out = app.typed_out
    if isempty(out)
        colored(app.dim) do
            text!(app.state === :deciding ? "Deciding..." :
                  "Decide runs every question over the state in one pass and draws a bar per option.\n" *
                  "choice: one label wins.  score: a level on your scale.  noul: yes or no, as P(true).")
        end
    else
        d = out[1]
        tok = sum(x -> x.input_tokens, out); ms = sum(x -> x.latency_ms, out)
        colored(app.dim) do
            text!(string(d.model, "  ·  ", d.family, "  ·  ", length(out) == 1 ? "" : "$(length(out)) states  ·  ",
                         tok, " tokens  ·  ", round(ms; digits = 1), " ms"))
        end
        G.ImGui_Separator()
        for (k, d) in enumerate(out)
            if length(out) > 1
                st = k <= length(app.typed_states) ? _state_label(app.typed_states[k]) : ""
                summary = join((a.id * ": " * LC.headline(a) for a in d.answers), "    ")
                open_ = G.ImGui_TreeNodeEx("$k   $summary###st$k", THINK_FLAGS)
                colored(() -> text!("    " * st), app.dim)
                open_ || continue
            end
            G.ImGui_PushID(Cint(k))
            for a in d.answers
                answer!(app, a, w)
            end
            G.ImGui_PopID()
        end
    end
    G.ImGui_EndChild()
    rect!(app, :typed_out)
end

const TYPED_PATH_FLAGS = flags(G.ImGuiInputTextFlags_EnterReturnsTrue)
const TYPED_BOX_FLAGS  = flags(G.ImGuiInputTextFlags_AllowTabInput)

"""The chat side in typed mode: load row, State, Questions, Decide, answers."""
function typed_panel!(app)
    s = app.session
    fs = app.fonts.size
    avail = G.ImGui_GetContentRegionAvail()
    colored(app.dim) do
        text!("Typed decisions  ·  $(s.info.family)  ·  $(s.info.max_len) tokens a question, state included  ·  " *
              "up to $(s.info.max_opts) options  ·  $(s.device)")
    end
    # ── load row ──
    b = app.typed_path
    G.ImGui_SetNextItemWidth(max(fs * 10, avail.x - fs * 13))
    go = GC.@preserve b G.ImGui_InputText("##typedpath", pointer(b), length(b), TYPED_PATH_FLAGS, C_NULL, C_NULL)
    rect!(app, :typed_path)
    if b[1] == 0x00 && !G.ImGui_IsItemActive()
        lo = G.ImGui_GetItemRectMin()
        h = "a .json file (request, batch, questions or state), or a folder"
        GC.@preserve h G.ImDrawList_AddText(G.ImGui_GetWindowDrawList(),
            Ref(vec2(lo.x + app.pad.x, lo.y + app.pad.y)),
            G.ImGui_GetColorU32(Cint(G.ImGuiCol_TextDisabled), 1f0), pointer(h), pointer(h) + sizeof(h))
    end
    G.ImGui_SameLine(0f0, -1f0)
    go |= G.ImGui_Button("Load JSON", ZERO)
    rect!(app, :typed_load)
    G.ImGui_SameLine(0f0, -1f0)
    G.ImGui_Button("Files", ZERO) && G.ImGui_OpenPopup("##typedfiles", Cint(0))
    rect!(app, :typed_files)
    path = expanduser(String(strip(buf_text(b))))
    if G.ImGui_BeginPopup("##typedfiles", Cint(0))
        dirs = isempty(path) ? [p.dir for p in app.places] : [isdir(path) ? path : dirname(path)]
        n = 0
        for d in dirs, f in json_files(d)
            n += 1
            G.ImGui_Selectable("$(relpath(f, d))###tf$n", false, Cint(0), ZERO) && typed_load!(app, f)
            length(dirs) > 1 && (G.ImGui_SameLine(0f0, fs * 1.5f0); colored(() -> text!(d), app.dim))
        end
        n == 0 && colored(() -> text!("No .json files under " * join(dirs, ", ")), app.dim)
        G.ImGui_EndPopup()
    end
    if go && !isempty(path)
        isdir(path) ? G.ImGui_OpenPopup("##typedfiles", Cint(0)) : typed_load!(app, path)
    end
    # ── the request ──
    body = max(avail.y - 4 * G.ImGui_GetFrameHeightWithSpacing() - 2 * G.ImGui_GetTextLineHeightWithSpacing(), 240f0)
    colored(() -> text!("State"), C_USER)
    G.ImGui_SameLine(0f0, fs * 0.6f0)
    colored(() -> text!("JSON or plain text; {\"states\": [...]} decides each one"), app.dim)
    st = app.typed_state
    GC.@preserve st G.ImGui_InputTextMultiline("##typedstate", pointer(st), length(st),
                                               Ref(vec2(-1, 0.22f0 * body)), TYPED_BOX_FLAGS, C_NULL, C_NULL)
    rect!(app, :typed_state)
    colored(() -> text!("Questions"), C_USER)
    G.ImGui_SameLine(0f0, fs * 0.6f0)
    colored(() -> text!("id: {type: choice | score | noul, instructions, criteria}"), app.dim)
    q = app.typed_q
    GC.@preserve q G.ImGui_InputTextMultiline("##typedq", pointer(q), length(q),
                                              Ref(vec2(-1, 0.33f0 * body)), TYPED_BOX_FLAGS, C_NULL, C_NULL)
    rect!(app, :typed_q)
    G.ImGui_IsItemDeactivatedAfterEdit() && (app.typed_builtin = false)
    G.ImGui_BeginDisabled(app.state !== :idle || app.closing)
    G.ImGui_Button("Decide", ZERO) && typed_decide!(app)
    rect!(app, :typed_decide)
    G.ImGui_EndDisabled()
    if !isempty(app.typed_err)
        G.ImGui_SameLine(0f0, fs)
        colored(() -> text!(app.typed_err), C_ERR)
    elseif !isempty(app.typed_note)
        G.ImGui_SameLine(0f0, fs)
        colored(() -> text!(app.typed_note), app.dim)
    end
    typed_results!(app)
end
