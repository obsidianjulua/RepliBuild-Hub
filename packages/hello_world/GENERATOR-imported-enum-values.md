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

## Proposed fix (from this package's data)

Scoped to what this package shows. The general fix, and whether it holds for
every wrapped Hub package, arm64, Linux and Windows, is the engine side's call.

What the data says first: the owner's `type_manifest.json` entry for
`__enum__Mood` records `julia_name`, `kind`, `layout`, `scopes`, `decl_files`
and a `layout_signature` holding the **raw** enumerator names
(`[("Calm", 1),("Happy", 2),("Loud", 3)]`), but not the names the owner
actually **emitted**. Those can differ, because the owner prefixes an
enumerator with its enum's name when it would rebind another top-level name.
So an importer cannot alias the values safely from today's manifest.

1. **Owner records its emitted value names.** Both generators already have
   them: `_render_enum_chunks` (`src/Wrapper/Utils.jl:1125`) returns
   `enum_member_names`, which `GeneratorCpp.jl:4254-4263` and
   `GeneratorC.jl:4313-4322` use for the export list. Pass them through the
   emitted facts into `_type_manifest` (`Generator.jl:1492`,
   `TypeImports.jl:329`) as, for example, `"values" => ["Calm", "Happy", "Loud"]`
   on each `kind = "enum"` row.
2. **Importer aliases them.** In `_type_imports_chunk` (`TypeImports.jl:709`),
   for each imported enum also emit
   `const <v> = Base.parentmodule(@__MODULE__).<Owner>.<v>` for every `v` in
   the owner's `values`, sorted, beside the type alias it already writes.
3. **A collision in the importer is skipped, not prefixed.** If the importer
   itself defines `v` (a function, a global, its own enum's member), emit no
   alias and report `Mood: value Happy stays Hello.Happy (World defines Happy)`.
   Prefixing on the importer's side would give one value two spellings across
   the graph; the owner's name is the canonical one.
4. **Export the aliases** next to the imported enum's type name in the
   importer's export list, so `using HelloWorld.World` brings `Mood` and its
   values together, as `using HelloWorld.Hello` does.
5. **The write-time guard** (`_assert_no_imported_redefinition`) has to accept
   these `const … = Owner.v` lines as aliases, not redefinitions.

Tests this would want:

- `test/test_cross_library_types.jl` (runtests): XHist imports XCore's
  `Color`, so its text gains `const RED = Base.parentmodule(@__MODULE__).XCore.RED`
  and `GREEN`, both exported. A variant where XHist defines a function `RED`
  gets no `RED` alias and gets the report line.
- `test/test_cross_library_types_live.jl` (devtests): `M.Xb.GREEN === M.Xa.GREEN`,
  beside the existing `identity_color` probe.
- Hub: flip `packages/hello_world/test_deep.jl:60` to `W.Happy === H.Happy`.

**Checked here:** only this package (two C++ libraries, one `enum class`) on
Linux x86-64, Julia 1.13, engine `ae611f0`. **Not checked:**
- the C generator path in a live graph (hello_world is C++; `GeneratorC.jl`
  shares the renderer but was only read);
- single-library Hub wraps. The import chunk is empty when nothing is
  imported, so they should stay byte-identical, but I did not re-wrap any;
- manifests written before this change (an owner row with no `values`
  should mean "no aliases", the current behaviour);
- arm64 and Windows;
- the thunk side. Enum values cross as plain integers today, so it should be
  unaffected, but that is untested.

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
