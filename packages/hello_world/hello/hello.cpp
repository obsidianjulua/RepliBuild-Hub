#include "hello.h"

#include <stdexcept>

namespace hw {

Greeter::Greeter(Mood mood) : mood_(mood) {}
Greeter::~Greeter() = default;
const char *Greeter::message() const { return "Hello, World!"; }
Mood Greeter::mood() const { return mood_; }

Vec2 vec2(float x, float y) { return Vec2{x, y}; }
Vec2 vec2_add(Vec2 a, Vec2 b) { return Vec2{a.x + b.x, a.y + b.y}; }
Vec2 vec2_scale(Vec2 v, float k) { return Vec2{v.x * k, v.y * k}; }
float vec2_dot(Vec2 a, Vec2 b) { return a.x * b.x + a.y * b.y; }
int mood_level(Mood m) { return static_cast<int>(m) * 10; }

Greeter *make_greeter(Mood mood) { return new Greeter(mood); }
void destroy_greeter(Greeter *g) { delete g; }
const char *greet(const Greeter *g) { return g->message(); }

} // namespace hw

// The original string, reachable as a function. A `main` in a shared library
// would be wrapped like any other export, so the fixture defines none.
const char *hello_message() { return "Hello, World!"; }

// 3 args, all INTEGER class.
int add_scaled(int a, int b, int scale) { return (a + b) * scale; }

// 3 args, all SSE class — the other half of the SysV register file.
double blend(double a, double b, double t) { return a * (1.0 - t) + b * t; }

// Mixed INTEGER/SSE with a widening return: the thunk must move each argument
// in its own register file.
int64_t mix_widths(int32_t a, double b) {
    return static_cast<int64_t>(a) + static_cast<int64_t>(b * 1000.0);
}

// The reason the thunk path exists: a C++ exception has to cross the thunk
// boundary and surface in Julia instead of terminating the process.
int checked_div(int numerator, int denominator) {
    if (denominator == 0) {
        throw std::invalid_argument("checked_div: division by zero");
    }
    return numerator / denominator;
}
