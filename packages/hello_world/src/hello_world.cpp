// hello_world — the Hub's minimal Tier-2 exerciser.
//
// Every function here is plain C++: mangled, and deliberately NOT noexcept.
// `is_ccall_safe` (Wrapper/DispatchLogic.jl) returns false at its first check
// for exactly that shape — a C++ function that may throw needs an
// exception-safe thunk — so all of these route through the MLIR AOT thunks
// rather than through ccall. Marking any of them `noexcept`, or wrapping them
// in `extern "C"`, drops them to Tier 3 and defeats the point of the fixture.
//
// Kept deliberately POD: the routing here is driven by the exception rule, not
// by aggregate ABI complexity, so the arguments stay trivial to call from Julia.

#include <cstdint>
#include <stdexcept>

// The original string, now reachable as a function instead of from main().
// A `main` symbol in a shared library is its own hazard — it gets wrapped like
// any other export — so the fixture no longer defines one.
const char *hello_message() { return "Hello, World!"; }

// 3 args, all integer class.
int add_scaled(int a, int b, int scale) { return (a + b) * scale; }

// 3 args, all SSE class — the other half of the SysV register file.
double blend(double a, double b, double t) { return a * (1.0 - t) + b * t; }

// 2 args, mixed integer/SSE, widening return. Pins that the thunk moves each
// argument in the right register file rather than getting away with a
// same-class shuffle.
int64_t mix_widths(int32_t a, double b) {
    return static_cast<int64_t>(a) + static_cast<int64_t>(b * 1000.0);
}

// 2 args, and the reason the thunk path exists: this one actually throws.
// A C++ exception has to cross the thunk boundary intact and surface in Julia
// rather than terminating the process.
int checked_div(int numerator, int denominator) {
    if (denominator == 0) {
        throw std::invalid_argument("checked_div: division by zero");
    }
    return numerator / denominator;
}
