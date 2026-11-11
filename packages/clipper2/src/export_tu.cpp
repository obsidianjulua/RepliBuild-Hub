// Compile Clipper2's official C ABI. The functions live as definitions
// inside clipper.export.h; upstream's library target never includes that
// header (only the Windows DLL project does). source_files merges with
// the resolver-discovered TUs, same class as pcre2's harvested chartables.
//
// clipper.h first: export.h 2.0.1 calls MinkowskiSum/MinkowskiDiff without
// including clipper.minkowski.h. clipper.h pulls that in. Without it the TU
// fails to compile (undeclared identifier) — not a RepliBuild issue.
#include "clipper2/clipper.h"
#include "clipper2/clipper.export.h"
