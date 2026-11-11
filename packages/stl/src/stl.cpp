// Host-STL canary. The wrappable surface is the [types] templates
// instantiation TU; this file exists so the .so has a non-template export
// tests can call without going through JIT.
#include <string>

#if defined(_LIBCPP_VERSION)
#define RB_STL_HOST "libc++"
#elif defined(__GLIBCXX__)
#define RB_STL_HOST "libstdc++"
#else
#define RB_STL_HOST "unknown"
#endif

extern "C" const char *replibuild_stl_host(void) { return RB_STL_HOST; }

extern "C" int replibuild_stl_cxx(void) { return static_cast<int>(__cplusplus); }
