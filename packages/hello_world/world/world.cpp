#include "world.h"

#include <cmath>

namespace hw {

Shouter::Shouter(int volume) : Greeter(Mood::Loud), volume_(volume) {}
const char *Shouter::message() const { return "HELLO, WORLD!"; }
int Shouter::volume() const { return volume_; }

Entity spawn(int32_t id, Vec2 pos, Vec2 vel, Mood mood) {
    return Entity{pos, vel, id, mood};
}

Entity step(Entity e, float dt) {
    e.pos = vec2_add(e.pos, vec2_scale(e.vel, dt));   // hello's functions
    return e;
}

Vec2 entity_pos(Entity e) { return e.pos; }

float travel(Vec2 from, Vec2 to) {
    Vec2 d{to.x - from.x, to.y - from.y};
    return std::sqrt(vec2_dot(d, d));
}

Mood louder(Mood m) {
    switch (m) {
    case Mood::Calm:  return Mood::Happy;
    case Mood::Happy: return Mood::Loud;
    default:          return Mood::Loud;
    }
}

Greeter *spawn_shouter(int volume) { return new Shouter(volume); }

Crowd gather(Greeter *leader, int32_t size) { return Crowd{leader, size}; }

const char *crowd_says(Crowd c) { return greet(c.leader); }

} // namespace hw
