#!/usr/bin/env julia
#
# Shell launcher for LlamaChat.
#
#   julia --project=examples/LlamaChat examples/LlamaChat/chat.jl              # REPL
#   julia --project=examples/LlamaChat examples/LlamaChat/chat.jl "a prompt"   # one-shot
#
# Model selection follows $LLAMACPP_CHAT_MODEL, else the package default.

using LlamaChat

if isempty(ARGS)
    chatrepl()
else
    r = chat(join(ARGS, " "))
    printstyled(LlamaChat._stats_line(r), "\n"; color = :light_black)
end
