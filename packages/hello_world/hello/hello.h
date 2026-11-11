#ifndef HELLO_H
#define HELLO_H
// hello — the OWNER library of the hello_world graph. Every type that world/
// also uses is defined here, so in graph mode hello's wrapper emits it and
// world's wrapper imports it (one Julia type per C++ type, RepliBuild #80).

#include <cstdint>

namespace hw {

// POD crossed by value in both libraries: two floats, one SSE eightbyte.
struct Vec2 {
    float x;
    float y;
};

// Scoped enum with a fixed underlying type, shared by both libraries.
enum class Mood : int32_t { Calm = 1, Happy = 2, Loud = 3 };

// Polymorphic base with a key function (`message` is defined in hello.cpp), so
// its vtable and full DWARF live in hello alone. world derives from it, and
// hello's free function `greet` must reach world's override.
class Greeter {
public:
    explicit Greeter(Mood mood);
    virtual ~Greeter();
    virtual const char *message() const;
    Mood mood() const;
protected:
    Mood mood_;
};

Vec2 vec2(float x, float y);
Vec2 vec2_add(Vec2 a, Vec2 b);
Vec2 vec2_scale(Vec2 v, float k);
float vec2_dot(Vec2 a, Vec2 b);
int mood_level(Mood m);

Greeter *make_greeter(Mood mood);
void destroy_greeter(Greeter *g);
const char *greet(const Greeter *g);   // virtual call: reaches overrides

} // namespace hw

// ── The original hello_world Tier-2 exerciser (global namespace) ──
// Plain C++, mangled, deliberately NOT noexcept: each one needs an
// exception-safe thunk, so all of them route through Tier 2 rather than ccall.
const char *hello_message();
int add_scaled(int a, int b, int scale);
double blend(double a, double b, double t);
int64_t mix_widths(int32_t a, double b);
int checked_div(int numerator, int denominator);   // throws on zero

#endif
