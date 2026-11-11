#ifndef WORLD_H
#define WORLD_H
// world — the IMPORTER library of the hello_world graph. Links hello and uses
// hello's types in every shape a second library can: by value in and out,
// embedded (twice) in its own record, behind a pointer, as a base class, and
// as a scoped enum. In graph mode none of hw::Vec2 / hw::Mood / hw::Greeter
// may be redefined by world's wrapper.

#include "hello.h"

namespace hw {

// Embeds hello's Vec2 twice and its Mood once: 24 bytes, MEMORY class on
// SysV, so it crosses through a hidden return pointer.
struct Entity {
    Vec2 pos;
    Vec2 vel;
    int32_t id;
    Mood mood;
};

// Points at hello's class from a record world owns.
struct Crowd {
    Greeter *leader;
    int32_t size;
};

// Derives from hello's Greeter: flattens its fields, overrides its virtual.
class Shouter : public Greeter {
public:
    explicit Shouter(int volume);
    const char *message() const override;
    int volume() const;
private:
    int volume_;
};

// `spawn_`/`step`, not a make_/create_ prefix: those name factories.
Entity spawn(int32_t id, Vec2 pos, Vec2 vel, Mood mood);
Entity step(Entity e, float dt);          // advances pos by vel*dt
Vec2 entity_pos(Entity e);                 // hello's type back out of world
float travel(Vec2 from, Vec2 to);          // hello's type into world
Mood louder(Mood m);                       // scoped enum both ways
Greeter *spawn_shouter(int volume);        // a hello type made by world
Crowd gather(Greeter *leader, int32_t size);
const char *crowd_says(Crowd c);           // calls hello's greet → virtual

} // namespace hw

#endif
