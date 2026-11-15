// MicroPython configuration for the Hub's embed package.
//
// This file is BOTH the input to harvest_embed.sh (upstream's embed.mk scans
// the sources under it to generate embed/genhdr/: the qstr tables, root
// pointers, module list) AND on the include path when RepliBuild compiles
// embed/. The two must be the same file: a genhdr generated under one config
// and compiled under another is a library whose interned-string table does not
// match its code. harvest_embed.sh records this file's sha256 in
// embed/HARVEST.md and test.jl checks it, so edit here, then re-run the
// harvest.
//
// Starts from upstream's examples/embedding/mpconfigport.h (minimal level),
// raised to what a Julia host can use. Every addition below was needed or
// chosen for a stated reason; see the probe notes in replibuild.toml.

// Include common MicroPython embed configuration.
#include <port/mpconfigport_common.h>

// BASIC: core builtins and modules from py/ alone (math, gc, sys, collections,
// struct, array, micropython, ...). EXTRA needs shared/readline, an interrupt
// char HAL and more that the embed port does not ship; it does not link.
#define MICROPY_CONFIG_ROM_LEVEL                (MICROPY_CONFIG_ROM_LEVEL_BASIC_FEATURES)

#define MICROPY_ENABLE_COMPILER                 (1)
#define MICROPY_ENABLE_GC                       (1)
#define MICROPY_PY_GC                           (1)

// Real numbers: doubles for float, arbitrary-precision ints (2**100 works).
#define MICROPY_FLOAT_IMPL                      (MICROPY_FLOAT_IMPL_DOUBLE)
#define MICROPY_LONGINT_IMPL                    (MICROPY_LONGINT_IMPL_MPZ)

// mp_embed_exec_mpy: run precompiled .mpy bytecode.
#define MICROPY_PERSISTENT_CODE_LOAD            (1)

// sys is on at BASIC level, and the banner / sys.platform string needs a name.
// Every hardware port defines one; the embed port does not.
#define MICROPY_PY_SYS_PLATFORM                 "julia"

// No filesystem: code arrives as strings. With these on, the port must supply
// mp_import_stat, mp_lexer_new_from_file and open(), which the embed port does
// not (the link fails on exactly those three). Built-in modules still import.
#define MICROPY_ENABLE_EXTERNAL_IMPORT          (0)
#define MICROPY_PY_IO                           (0)

// Runaway recursion raises RuntimeError instead of overflowing the C stack
// (which, inside a Julia process, would take Julia down with it). REQUIRES the
// host to call mp_stack_set_limit right after mp_embed_init, before any Python
// runs: the default limit is 0, every call then fails the check, and printing
// that error re-trips it outside any handler, into the embed port's
// nlr_jump_fail, which is `for (;;) {}` — a silent hang.
#define MICROPY_STACK_CHECK                     (1)
