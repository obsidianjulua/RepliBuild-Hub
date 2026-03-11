# RepliBuild Hub

Community-maintained registry of `replibuild.toml` configs for popular C/C++ libraries. Search, fetch, and build wrappers directly from Julia — no manual setup required.

**Repository:** [github.com/obsidianjulua/RepliBuild-Hub](https://github.com/obsidianjulua/RepliBuild-Hub)

## Usage

```julia
using RepliBuild

# Search available packages
RepliBuild.search("lua")

# Install and use — one call does everything
Lua = RepliBuild.use("lua")
Lua.luaL_newstate()
```

`use()` checks your local registry first. On a miss, it fetches the TOML from the hub, registers it locally, then runs the full pipeline: dependency resolution → compile → link → DWARF introspect → wrap → load.

Subsequent calls are cached — rebuild only happens when the TOML or source content changes.

## Hub Repository Structure

```
RepliBuild-Hub/
  index.toml                    # package listing (used by search())
  packages/
    lua/
      replibuild.toml
    sqlite/
      replibuild.toml
    cjson/
      replibuild.toml
```

### index.toml

Flat listing of every package with metadata for search and display:

```toml
[lua]
description = "Lua 5.4 scripting language"
version = "5.4.7"
language = "c"
tags = ["scripting", "embedded"]

[sqlite]
description = "SQLite embedded database engine"
version = "3.46"
language = "c"
tags = ["database", "embedded"]

[cjson]
description = "Ultralightweight JSON parser in C"
version = "1.7.18"
language = "c"
tags = ["json", "parser"]
```

### Package TOMLs

Each `packages/<name>/replibuild.toml` is a standard RepliBuild config. The key difference from local configs: source code is declared as a git dependency rather than local paths.

```toml
[project]
name = "lua"
uuid = "..."
root = "."

[dependencies]
lua = { type = "git", url = "https://github.com/lua/lua.git", tag = "v5.4.7" }

[compile]
flags = ["-std=c99", "-fPIC", "-DLUA_USE_LINUX"]
source_files = []    # populated from dependency after fetch
include_dirs = []

[link]
enable_lto = true
optimization_level = "2"

[binary]
type = "shared"

[wrap]
style = "clang"
language = "c"

[types]
strictness = "warn"

[cache]
enabled = true
```

When `use()` fetches this TOML, RepliBuild's `DependencyResolver` clones the git repo, injects the source files and include paths, then the standard pipeline takes over.

## Environment Variable

Override the hub URL for private registries or mirrors:

```bash
export REPLIBUILD_HUB_URL="https://raw.githubusercontent.com/your-org/your-hub/main"
```

## Contributing a Package

1. Fork [RepliBuild-Hub](https://github.com/obsidianjulua/RepliBuild-Hub)
2. Create `packages/<name>/replibuild.toml` with a git dependency pointing to upstream source
3. Add an entry to `index.toml` with description, version, language, and tags
4. Test locally: `RepliBuild.register("packages/<name>/replibuild.toml"); RepliBuild.use("<name>")`
5. Open a PR

### Guidelines

- Package names are lowercase, no underscores (e.g., `cjson` not `c_json`)
- Point dependencies at stable tags, not branches
- Include only the minimal flags needed — RepliBuild handles debug metadata and LTO automatically
- Test that `use("<name>")` succeeds on a clean machine before submitting
