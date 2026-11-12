# Generator gap: an imported enum brings its type but not its values

> **STATUS:** OPEN
> **PACKAGE:** hello_world (local graph fixture: `hello` → `world`)
> **STAGE:** wrap (graph mode, cross-library type imports, RepliBuild.jl #80)
> **BLOCKS:** nothing — ergonomics. Values cross correctly; only their names
> are missing on the importer's side.
> **HUB PIN:** `test_deep.jl:57-60` pins the current behaviour
> (`!isdefined(W, :Happy) && H.Happy isa W.Mood`). Flip it to
> `W.Happy === H.Happy` when this is fixed.
> **ENGINE AT:** RepliBuild.jl `ae611f0` (main, after #85)

## Symptom

`hello` owns a scoped enum; `world` links `hello` and uses it. After
`wrap`, World imports the enum **type** from Hello, but none of its
**enumerators**:

```julia
julia> G = include("julia/HelloWorld.jl");
julia> G.World.Mood === G.Hello.Mood
true
julia> G.World.Happy
ERROR: UndefVarError: `Happy` not defined in `Main.HelloWorld.World`
julia> G.World.hw_louder(G.Hello.Calm) === G.Hello.Happy     # values work
true
```

So a caller working in World has to know which library owns each enum and
spell its values through the owner (`Hello.Happy`), while every record type
World uses (`Vec2`, `Greeter`) is reachable as `World.X`. `using
HelloWorld.World` brings `Mood` into scope (it is in World's export list) and
none of its values.

Generated text, World (`julia/world/lib/World.jl`):

```julia
const Greeter = Base.parentmodule(@__MODULE__).Hello.Greeter
const Mood = Base.parentmodule(@__MODULE__).Hello.Mood        # line 168
const Vec2 = Base.parentmodule(@__MODULE__).Hello.Vec2
...
export ..., Mood, Crowd, Entity, Greeter, Shouter, Vec2, ...  # no Calm/Happy/Loud
```

Owner, Hello (`julia/hello/lib/Hello.jl:164-173`), for comparison:

```julia
primitive type Mood <: RepliBuild.OpenEnums.OpenEnum{Int32} 32 end
RepliBuild.OpenEnums.enumerators(::Type{Mood}) = (:Calm => 1, :Happy => 2, :Loud => 3)
const Calm = Mood(1)
const Happy = Mood(2)
const Loud = Mood(3)
export ..., Mood, Calm, Happy, Loud, ...
```

`julia/world/lib/type_imports.json` records the import as
`__enum__Mood → (Hello, Mood)`.

## Why this is not a TOML mistake

Nothing in the TOML selects what an import carries; graph mode does not apply
per-library `[wrap]` keys at all. The enum is declared once, in a header both
libraries include, so importing it is the correct ownership decision. Only the
spelling of its values on the importer's side is missing.

## Source that produces it

`packages/hello_world/hello/hello.h:18`:

```cpp
namespace hw {
enum class Mood : int32_t { Calm = 1, Happy = 2, Loud = 3 };
}
```

used by value in `world/world.h` (`Entity::mood`, `spawn(…, Mood)`,
`louder(Mood) -> Mood`). Any graph where a later library takes an earlier
library's enum hits this; C enums (`enum Mode { MODE_A … }`) the same way.

## Pipeline stage

Wrap, the import pre-pass and its emitter (read-only references at `ae611f0`):

- `src/Wrapper/TypeImports.jl:709` `_type_imports_chunk` emits one
  `const <name> = Base.parentmodule(@__MODULE__).<Owner>.<name>` per imported
  key, and for `__enum__Mood` that is the type alone.
- `src/Wrapper/Cpp/GeneratorCpp.jl:554` (`_imported(k)`), and the enum
  emission loop at `:855`, skip an imported enum entirely: the per-enumerator
  `const Calm = Mood(1)` lines are emitted only by the owner.
  `src/Wrapper/C/GeneratorC.jl:1307` has the same predicate for C enums.

The owner's enumerator names are available on both sides: in the owner's
metadata (`owner_entry` in `type_imports.json` carries the enum entry) and at
run time through `RepliBuild.OpenEnums.enumerators(Owner.Mood)`.

## Minimal reproduction

`packages/hello_world/` is already minimal: two C++ libraries, one shared
`enum class`. From the Hub root:

```bash
julia --project=/path/to/RepliBuild.jl packages/hello_world/test_deep.jl
```

passes 38/38 today with the pin above; the gap is the pinned line.

## Open questions for the engine side

- Should an imported enum also alias its enumerators (`const Happy =
  Base.parentmodule(@__MODULE__).Hello.Happy`) and export them, so the
  importer's module reads like the owner's?
- If yes: an enumerator name that collides with something the importer
  defines itself (a function, a global, another enum's value) needs the same
  rule the owner's emitter already applies (`GeneratorCpp.jl:800-804`: an
  enumerator that would rebind a record, a function, a global or another
  enum's member is prefixed with its enum's name).
- Scoped (`enum class`) vs unscoped C/C++ enums may want different answers:
  the owner exports unscoped-style names for both today.
