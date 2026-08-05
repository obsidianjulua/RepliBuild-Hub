/* miniz_export.h — supplied by hand for the RepliBuild build.
 *
 * Upstream miniz #includes this from miniz.h but never ships it: CMake's
 * generate_export_header() writes it into the build directory at configure
 * time, and RepliBuild does not run CMake. Without it every TU fails with
 * "'miniz_export.h' file not found".
 *
 * miniz's own amalgamation script substitutes exactly this definition
 * (CMakeLists.txt: "#ifndef MINIZ_EXPORT\n#define MINIZ_EXPORT\n#endif"), so an
 * empty macro is the upstream-sanctioned rendering, not an invention. It is
 * also the correct one here: the CMake shared-library path pairs the export
 * attribute with C_VISIBILITY_PRESET hidden, and this build passes no
 * -fvisibility=hidden, so everything already has default visibility and an
 * annotation would be redundant.
 *
 * Reached via [compile] include_dirs = ["include"] in replibuild.toml.
 */

#ifndef MINIZ_EXPORT_H
#define MINIZ_EXPORT_H

#ifndef MINIZ_EXPORT
#define MINIZ_EXPORT
#endif

#ifndef MINIZ_NO_EXPORT
#define MINIZ_NO_EXPORT
#endif

#endif /* MINIZ_EXPORT_H */
