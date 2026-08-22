#!/usr/bin/env julia
#
# Shell launcher for LlamaChat.
#
#   julia --project=examples/LlamaChat examples/LlamaChat/chat.jl              # chat
#   julia --project=examples/LlamaChat examples/LlamaChat/chat.jl "a prompt"   # one-shot
#
# Model selection follows $LLAMACPP_CHAT_MODEL, else the package default.
#
# The one-shot branch reaches through `LlamaChat.` on purpose: the package
# exports `list_models` and `load` and nothing else, and a single turn on a
# throwaway session is a scripting job, not part of the interface.

using LlamaChat
const LC = LlamaChat

if isempty(ARGS)
    load()
else
    s = LC.ChatSession()
    try
        r = LC.chat(s, join(ARGS, " "))
        printstyled(LC._stats_line(r), "\n"; color = :light_black)
    finally
        LC.close!(s)
    end
end
