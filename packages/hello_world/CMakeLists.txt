# hello_world — a two-library graph for RepliBuild's graph mode and
# cross-library type identity (RepliBuild.jl #80).
#
#   hello   C++ shared library: owns hw::Vec2, hw::Mood (enum class),
#           hw::Greeter (polymorphic), plus the original Tier-2 exerciser
#           functions (one of which throws).
#   world   C++ shared library linking hello: embeds, returns, derives from and
#           points at hello's types. replibuild.toml selects world; hello comes
#           with it as a linked dependency.
cmake_minimum_required(VERSION 3.20)
project(hello_world CXX)

add_library(hello SHARED hello/hello.cpp hello/hello.h)
target_include_directories(hello PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/hello)
target_compile_features(hello PRIVATE cxx_std_17)

add_library(world SHARED world/world.cpp world/world.h)
target_include_directories(world PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/world)
target_compile_features(world PRIVATE cxx_std_17)
target_link_libraries(world PUBLIC hello)
