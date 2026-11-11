# Generator bug: `icmp constexprs are no longer supported` at `.ll → .so`

> **STATUS:** CLOSED — class document
> **PACKAGE:** zstd 1.5.7
> **STAGE:** create_library
> **BLOCKS:** nothing
> **HUB PIN:** none — `-DZSTD_TRACE=0` dropped 2026-08-29
> **FIXED BY:** RepliBuild.jl — *Assemble C-bucket IR with the same clang that
> emitted it*. `create_library`, `create_executable` and `compile_single_to_ir`
> now share `_clang_for_c_bucket`, which routes `clang` through
> `Clang_unified_jll`. The report's diagnosis was correct in full; its suggested
> fix was taken. Note `resolve_tool(name, :c)` — floated as the tighter
> invariant — would **not** have worked: Arch's `llvm18` package ships LLVM
> tools with no clang binary, so it finds the directory, misses the binary, and
> falls back to system clang anyway. `Clang_unified_jll` was the right hook.
>
> **VERIFIED:** rebuilt this package with `-DZSTD_TRACE=0` removed. 26
> `icmp eq (ptr @ZSTD_trace…)` constexprs reach the per-file IR, `zstd_linked.ll`
> and `zstd_abi.ll` (the assembled file); build succeeds at 4.2 MB with 4
> `ZSTD_trace` symbols in the `.so`.
>
> **GROK ACTION:** done 2026-08-29, local clone (no fetch):
> 1. Deleted `"-DZSTD_TRACE=0"` from `[compile] flags`; rebuilt+wrapped.
> 2. Flags comment now says the pin was a dodge, not a library choice.
> 3. `test_deep.jl` asserts the four weak `ZSTD_trace_*` names in the `.so`
>    and that the icmp-constexpr form is still in `zstd_abi.ll`. 656/656.
> 4. HUB.md row dropped from *Resolved — awaiting cleanup*.
>
> **THEN:** keep as class document (this block).

Triggered while wrapping **zstd 1.5.7**. The package TOML is not the cause;
`-DZSTD_TRACE=0` is a legitimate library pin that *also* happens to dodge this.
This file is the report, not a workaround note.

## Symptom

`RepliBuild.build` compiles all 31 libzstd TUs to IR, links and opts them
in-process, then dies at `create_library`:

```
Library creation failed: ./build/zstd_abi.ll:33559:22: error: icmp constexprs are no longer supported
 33559 |   %160 = or i1 %159, icmp eq (ptr @ZSTD_trace_compress_end, ptr null), !dbg !21282
1 error generated.
```

Stack: `Compiler.create_library` (`Compiler.jl:1112`) ← `compile_project` ← `build`.

The per-file IR already contains the form. It is not invented by the linker:

```
build/zstd_compress.c-*.ll:    or i1 %6, icmp eq (ptr @ZSTD_trace_compress_end, ptr null)
build/zstd_decompress.c-*.ll:  or i1 %8, icmp eq (ptr @ZSTD_trace_decompress_end, ptr null)
```

`zstd_linked.ll` / `zstd_opt.ll` / `zstd_abi.ll` just preserve it.

## C source that produces it

`lib/compress/zstd_compress.c` (and the decompress twin):

```c
if (cctx->traceCtx && ZSTD_trace_compress_end != NULL) {
    ZSTD_trace_compress_end(cctx->traceCtx, &trace);
}
```

`ZSTD_trace_compress_end` is a **weak** function (`ZSTD_WEAK_ATTR` in
`lib/common/zstd_trace.h`), default-enabled on ELF x86-64 when
`ZSTD_TRACE` is unset (`ZSTD_TRACE` defaults to `ZSTD_HAVE_WEAK_SYMBOLS`).
A comparison of a weak function's address against `NULL` is a compile-time
constant as far as LLVM 18 is concerned, so Clang_unified_jll emits an
`icmp` constant expression.

This is ordinary C. Any library that writes `if (weak_fn != NULL)` will
hit the same IR shape.

## Why assembly fails

Three different clangs, one pipeline:

| Stage | Tool | LLVM | icmp constexpr |
|---|---|---|---|
| per-file `.c → .ll` | `Clang_unified_jll.clang()` (`compile_single_to_ir`) | **18.x**, matched to Julia | **emits** it |
| link / opt / promote | Julia's resident libLLVM (`_link_ir_libllvm` / `_optimize_ir_libllvm`) | **18.x**, same | **preserves** it |
| `.ll → .so` | `BuildBridge.execute("clang", …)` (`create_library`) | **system Clang 22.1.8** (`/usr/bin/clang`) | **rejects** it |

LLVM 19 removed icmp constexprs. The C compile path is careful to keep
JLL clang and Julia's libLLVM version-matched (the comment at
`link_optimize_ir` states this invariant). **The assemble step is not
on that path.** `create_library` always does:

```julia
compiler = config.wrap.language == :c ? "clang" : "clang++"
(output, exitcode) = BuildBridge.execute(compiler, cmd_args)
```

`BuildBridge.execute` resolves via `LLVMEnvironment.get_tool`, which is
the **system** toolchain (this box: LLVM 22.1.8). It does **not** call
`Clang_unified_jll` and does **not** call `resolve_tool(name, :c)`.

The C-bucket helper `resolve_tool("clang", :c)` exists and already knows
to look at `c_toolchain_bin_dir()`. `create_library` does not use it.
CLAUDE.md already records the missing piece: *"Codegen of the final
`.ll → .so` still shells to clang (not yet internalized)."*

## What this is not

- Not a bad zstd flag. The IR is legal LLVM 18; the assembler is LLVM 22.
- Not an LTO / promotion artefact. The constexpr is in the *unlinked*
  per-file `.ll` that JLL clang wrote.
- Not unique to tracing conceptually — tracing is just the first Hub
  source that compares a weak function pointer to NULL.

## Config that dodges it (this package)

```toml
# in [compile] flags
"-DZSTD_TRACE=0"
```

That compiles the `#if ZSTD_TRACE` blocks out, so JLL clang never emits
the icmp. Tracing is optional profiler hooks, not the compression API, so
the pin is also the right *library* choice. It is **not** a fix for the
pipeline: the next C library with a weak-symbol NULL check will fail the
same way.

`[link] fallback = true` was not tried. It would re-link with the
external llvm-link/opt (system LLVM 22), which might rewrite the constexpr
away — or might fail earlier. Either way it would not put the assemble
step on JLL clang.

## Suggested fix (not applied — generator is out of scope here)

`create_library` for `language === :c` should assemble with the **same**
clang that emitted the IR: `Clang.Clang_unified_jll.clang()`, the same
`try` used in `compile_single_to_ir`. C++ can keep the system clang++
(it already uses the external pipeline end to end).

A tighter invariant: every tool that reads C-bucket IR (link, opt,
assemble, llvm-dwarfdump) is either Julia's libLLVM or Clang_unified_jll.
`resolve_tool(name, :c)` is the existing hook; `create_library` just
doesn't call it.

Negative check: wrap this tree **without** `-DZSTD_TRACE=0` after the
assemble-step clang is JLL-matched, and the icmp constexpr should
assemble cleanly. The package test does not currently assert that —
with the pin, those symbols are absent by design.

## Environment (this box)

- Julia 1.12.7, `Base.libllvm_version` 18.x (Clang_unified_jll)
- System `clang` / `llvm-config` 22.1.8 (`/usr/bin`)
- RepliBuild 3.3.3, `check_environment()` green for Tier 2/3
- First seen 2026-08-27, `packages/zstd` v1.5.7
