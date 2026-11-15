// Records no translation unit of Bullet's library mentions, made visible to the
// build. Nothing here constructs or calls anything.
//
// RepliBuild.jl #105 defines a class's header-only constructors itself, but it
// finds them through the class's DWARF definition, and a class that no library
// .cpp uses has none: btDefaultMotionState is a convenience class for
// applications, referenced nowhere in LinearMath/BulletCollision/BulletDynamics.
// One global of a pointer to it is enough: under -fstandalone-debug (the
// recipe's flags) the CU then carries the full class definition, and the
// build forces its constructor like the others (btDefaultMotionState_btDefaultMotionState).
//
// HUB PIN: retire this file when the build can be told to make a record
// visible on its own (GENERATOR-unreferenced-record-invisible.md).

#include "LinearMath/btDefaultMotionState.h"

btDefaultMotionState *replibuild_visible_btDefaultMotionState = nullptr;
