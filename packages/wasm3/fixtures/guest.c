// Guest module for the wasm3 Hub tests. Compiled to WebAssembly at test time:
//
//   clang --target=wasm32 -O2 -nostdlib -Wl,--no-entry -o guest.wasm guest.c
//
// No libc: the one OS call is WASI's fd_write, declared by hand. Every export
// exercises one thing the host side has to get right.

#define EXPORT(name) __attribute__((export_name(name)))
#define IMPORT(mod, name) __attribute__((import_module(mod), import_name(name)))

// Supplied by Julia (m3_LinkRawFunction, signature "i(i)").
IMPORT("env", "jl_scale") int jl_scale(int x);

// WASI: write iovecs to a file descriptor (wasi_snapshot_preview1).
typedef struct { const void *buf; unsigned len; } iovec;
IMPORT("wasi_snapshot_preview1", "fd_write")
int wasi_fd_write(int fd, const iovec *iovs, int iovs_len, unsigned *nwritten);

// ── Scalars of every wasm type ──
EXPORT("add")   int add(int a, int b) { return a + b; }
EXPORT("mul64") long long mul64(long long a, long long b) { return a * b; }
EXPORT("hyp")   double hyp(double a, double b) { return __builtin_sqrt(a * a + b * b); }
EXPORT("halff") float halff(float x) { return x / 2.0f; }
EXPORT("scale") double scale(int n, double x) { return n * x; }

// ── Recursion, and a trap ──
EXPORT("fib") int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
EXPORT("idiv") int idiv(int a, int b) { return a / b; }          // b == 0 traps
// Real recursion: deep(1000) returns 1000, deep(10000000) exhausts wasm3's
// stack. `deep(n - 1) + 1` would not do: LLVM's tail-recursion elimination
// turns that accumulator form into a loop. Adding a volatile GLOBAL instead
// forces a load after each call returns, so the call is never in tail
// position. (A volatile LOCAL would live on the guest's linear-memory shadow
// stack and corrupt memory long before wasm3's own stack ran out.)
static volatile int one = 1;
EXPORT("deep") int deep(int n) { return n == 0 ? 0 : deep(n - 1) + one; }

// ── Calling back into the host ──
EXPORT("call_host") int call_host(int x) { return jl_scale(x) + 1; }

// ── Linear memory shared with the host ──
static unsigned char buf[256];
EXPORT("buffer") unsigned char *buffer(void) { return buf; }
EXPORT("checksum") unsigned checksum(int n) {
    unsigned s = 0;
    for (int i = 0; i < n; i++) s = s * 31 + buf[i];
    return s;
}
EXPORT("upcase") void upcase(int n) {
    for (int i = 0; i < n; i++)
        if (buf[i] >= 'a' && buf[i] <= 'z') buf[i] -= 32;
}

// ── WASI ──
EXPORT("hello") int hello(void) {
    static const char msg[] = "hello from wasm\n";
    iovec iov = { msg, sizeof msg - 1 };
    unsigned written = 0;
    return wasi_fd_write(1, &iov, 1, &written) == 0 ? (int)written : -1;
}
