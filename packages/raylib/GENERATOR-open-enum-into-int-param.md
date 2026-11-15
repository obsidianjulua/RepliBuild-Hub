# Generator gap: an open enum's constants cannot be passed to the `int` parameter they are for

> **STATUS:** OPEN
> **PACKAGE:** raylib (wrapper generated 2026-11-14 by RepliBuild 4.5.0)
> **STAGE:** wrap
> **BLOCKS:** nothing. Callers write `Int(R.KEY_SPACE)`. The package wraps and
> a game runs through it (`demo.jl`, and the vendored copy in `Ray-Qwen`).
> **HUB PIN:** none.
> **FOUND:** 2026-11-14, vendoring the wrapper for a model to write games with.

## What happens

```julia
include("packages/raylib/julia/Raylib.jl"); const R = Raylib
R.IsKeyDown(R.KEY_SPACE)
# MethodError: no method matching IsKeyDown(::Raylib.KeyboardKey)
#   Closest candidates are: IsKeyDown(!Matched::Integer)
R.IsKeyDown(Int(R.KEY_SPACE))        # works
```

The wrapper has both halves and they do not meet:

- raylib.h declares the constants as `enum KeyboardKey` and the function as
  `bool IsKeyDown(int key)`. C converts the one to the other silently, so
  every raylib program is written `IsKeyDown(KEY_SPACE)`.
- The wrapper emits `primitive type KeyboardKey <: RepliBuild.OpenEnums.OpenEnum{Cint}`
  with `const KEY_SPACE = KeyboardKey(32)` (Raylib.jl:1828, 1989), and
  `IsKeyDown(key::Integer)` with `key_c = Cint(key)` in its body (Raylib.jl:49999).
- `KeyboardKey` is not an `Integer`, so dispatch refuses the call before the
  body's `Cint(key)` runs. That conversion itself is defined: `Cint(R.KEY_SPACE) == 32`.

The same holds for every function taking a key, a mouse button or a gamepad
button as `int`: `IsKeyPressed`, `IsKeyReleased`, `IsKeyUp`, `SetExitKey`,
`IsMouseButtonDown`, `IsMouseButtonPressed`, `IsGamepadButtonDown`, … (110
`KEY_` constants, plus `MOUSE_BUTTON_*` and `GAMEPAD_BUTTON_*`).

It is not every enum. `R.SetConfigFlags(R.FLAG_WINDOW_HIDDEN)` works:
`ConfigFlags` is a flags type whose supertype is `Signed`, so it is an
`Integer` and matches. Only the `OpenEnum` enums are shut out.

## Why it matters here

The wrapper's promise is that C's own spelling works. This is the first thing
a raylib user types, and the first thing a language model types too: the
constant is present and named exactly as in every raylib example, and the call
fails. The error names the cause (a `KeyboardKey` where an `Integer` was
wanted), so it is recoverable, but only by someone who knows to convert.

## What is not known

Whether this is a decision or an omission. An open enum that is deliberately
not an `Integer` keeps `KEY_SPACE + 1` from compiling, which may be wanted.
The parameter is plain `int` in C, so the generator cannot know from the
signature alone that it takes a `KeyboardKey`.

## Smallest change that would close it

An integer parameter's wrapper method could accept an open enum as well as an
`Integer`: the body already converts with `Cint(key)`, and that conversion is
already defined for `OpenEnum`. That widens what is accepted without making
the enum itself an integer. Not tried: this report is from the Hub, where the
engine is not changed.
