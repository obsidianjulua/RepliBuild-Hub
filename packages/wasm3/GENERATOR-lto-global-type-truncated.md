# Generator bug: the LTO module truncates a global whose type has spaces inside an array

> **STATUS:** FIXED in RepliBuild.jl#104 (open PR). The recipe now sets
> `[link] enable_lto = false` (Hub pin), so wasm3 no longer builds the module.
> **PACKAGE:** wasm3 0.9.0 (`0cd3832`)
> **STAGE:** build (LTO bitcode for the Tier 1 / llvmcall path)
> **BLOCKS:** the LTO module for any C package with an exported global of type
> "array of literal struct" or "array of arrays". Nothing user-visible breaks:
> assembly fails, `<lib>_lto.bc` is not written, and every call stays a plain
> `ccall`, which is always correct. Only the zero-overhead path is lost, with a
> warning at every build.
> **HUB PIN:** `test.jl` asserts both truncated declarations are in
> `julia/wasm3_lto.ll` and that `julia/wasm3_lto.bc` does not exist. Flip to
> `isfile(...lto.bc)` when this is fixed.
> **ENGINE AT:** RepliBuild.jl `ad99b99` (main, after #103)

## Symptom

Every `RepliBuild.build` of `packages/wasm3`:

```
packages/wasm3/julia/wasm3_lto.ll:125:1: error: expected 'x' after element count
┌ Warning: libLLVM IR parse failed: lto_ir:125:1: error: expected 'x' after element count
┌ Warning: Failed to assemble bitcode for LTO: /usr/bin/llvm-as: …/wasm3_lto.ll:125:1: error: expected 'x' after element count
```

The module holds two cut-off declarations:

```
124: @preopen = external global [5
170: @c_operationsFC = external constant [18
```

from these definitions in `build/wasm3_linked.ll`:

```
@preopen = local_unnamed_addr global [5 x { i32, [4 x i8], ptr, ptr }] [ … ]
@c_operationsFC = constant [18 x { i8, i8, [6 x i8], [4 x ptr], ptr }] [ … ]
```

## Why this is not a TOML mistake

The globals are ordinary upstream C, and the definitions in the linked IR are
valid (the `.so` built from the same module links and runs; test_deep passes
35/35). The truncation happens only when the LTO copy rewrites definitions as
declarations. Nothing in `[link]` or `[compile]` selects how that is done.

## C source that produces it

```c
// source/m3_api_wasi.c:79 — a non-static array of a typedef'd struct
Preopen preopen[PREOPEN_CNT] = { … };
// source/m3_compile.c:3330
const M3OpInfo c_operationsFC [] = { … };
```

Clang emits an initialized struct with padding as a LITERAL struct type
(`{ i32, [4 x i8], ptr, ptr }`), not `%struct.Preopen`, so the element type of
the array contains spaces.

## Pipeline stage

`src/Builder/Compiler.jl:1234`, `sanitize_ir_for_julia`, "Global variable
externalization" (read-only):

```julia
gm = match(r"^(@[\w][\w.]*\s*=\s*)(.*?)\b(global|constant)\b\s+((?:<\{.*?\}>|\{.*?\}|\[\d+\s+x\s+\S+\]|\S+))\s+\S", line)
...
line = "$(gm[1])external $(gm[3]) $(type_str)"
```

The type alternatives are `<{…}>`, `{…}`, `[N x <token with no space>]`, or
any token with no space. `[5 x { i32, [4 x i8], ptr, ptr }]` matches none of
the bracketed forms (its element type has spaces), so the last alternative,
`\S+`, takes `[5`, and the following `\s+\S` is satisfied by ` x`. The same
happens to any array whose element type contains a space: nested arrays
(`[2 x [3 x i32]]` → `[2`), arrays of literal structs, arrays of packed
structs.

Called from `Compiler.jl:1082`; assembled at `:1257` (`assemble_bitcode`),
where both warnings are raised (`:1348` libLLVM, `:1281` llvm-as).

## Minimal reproduction

```c
// lto_globals.c, built as a C package with [link] enable_lto = true
typedef struct { int fd; const char *path; const char *real; } P;
P table[2] = { {0, "a", "b"}, {1, "c", "d"} };   // padded → literal struct type
int grid[2][3] = { {1, 2, 3}, {4, 5, 6} };       // [2 x [3 x i32]]
int get(int i, int j) { return grid[i][j] + table[i].fd; }
```

Expected `_lto.ll` lines: `@table = external global [2`,
`@grid = external global [2`, and the same parse error. Not built in this
session; derived from the regex and the two wasm3 cases.

## Proposed fix (from this package's data)

Scoped to what this package shows. The general fix, and whether it holds for
every wrapped Hub package, arm64, Linux and Windows, is the engine side's call.

1. **Read the type by bracket balance, not by regex.** After the
   `global|constant` keyword, scan forward counting `[`/`]`, `{`/`}` and
   `<{`/`}>` depth; the type ends at the first whitespace at depth 0. That
   covers every nesting the regex alternatives were approximating (named
   structs, literal structs, packed structs, vectors `<4 x i32>`, nested
   arrays, `ptr`) and needs no list of shapes.
2. **Fail loudly on a line the rewrite cannot read.** Today a bad match
   silently produces invalid IR, and the only signal is an assembler error
   pointing into a generated file. If the type cannot be delimited, keep the
   original definition line, or name the global in the warning.

Tests this would want (Compiler unit tests on `sanitize_ir_for_julia`, no
library needed):
- `@a = global [5 x { i32, [4 x i8], ptr, ptr }] [ … ], align 16` →
  `@a = external global [5 x { i32, [4 x i8], ptr, ptr }]`
- `@b = constant [2 x [3 x i32]] [ … ]` → `@b = external constant [2 x [3 x i32]]`
- `@c = global <{ i32, i8 }> <{ … }>`, `@d = global %struct.S { … }`,
  `@e = global ptr null`, `@f = global <4 x float> …` keep working.
- Hub: `packages/wasm3/test.jl`'s pin flips (`wasm3_lto.bc` exists, no
  truncated lines).

**Checked here:** wasm3 on Linux x86-64, Julia 1.13, LLVM 23. Scanned every
`_lto.ll` present in the Hub for a truncated `external global|constant`
declaration: only two exist (quickjs, wasm3), and only wasm3's has them.
**Not checked:**
- the other C packages' LTO modules (most `julia/` folders hold no `_lto.ll`
  after a build, so they were not scanned);
- whether any other per-line rewrite in `sanitize_ir_for_julia` makes the same
  "no spaces in a type" assumption;
- the C++ path (C++ packages here build with `enable_lto = false`);
- arm64 and Windows.
