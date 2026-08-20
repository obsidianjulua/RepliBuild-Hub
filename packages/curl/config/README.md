# `curl_config.h` — a checked-in build artifact, on purpose

libcurl is the one Hub package whose upstream cannot be compiled from a bare
checkout. `lib/curl_setup.h` does:

```c
#ifdef HAVE_CONFIG_H
#include "curl_config.h"
#else /* only _WIN32 / macintosh / RISCOS / OS400 have a shipped fallback */
```

On Linux there is no checked-in fallback, and the header is produced by 122
CMake feature probes (`check_include_file`, `check_symbol_exists`,
`check_type_size`). RepliBuild compiles all-sources-minus-excludes under one
flag set and never runs a configure step, so the header has to already exist.

**Reconstructing those 123 defines by hand would be the wrong fix.** Getting a
`SIZEOF_*`, a `HAVE_STRUCT_*` or a `USE_*` wrong does not fail the build — it
produces a library that is self-consistently *not curl* (no TLS, or a 32-bit
`curl_off_t`), which wraps clean and passes tests. So the header is captured
from cmake's own output instead, exactly as curl itself does for platforms
without a config tool (`lib/config-win32.h`, `config-mac.h`, …).

## Regenerating it (required on any version bump)

```bash
cmake -S <curl-checkout> -B /tmp/curlcfg \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_CURL_EXE=OFF -DBUILD_SHARED_LIBS=ON \
  -DCURL_BUILD_TESTING=OFF \
  -DCURL_USE_OPENSSL=ON -DCURL_ZLIB=ON \
  -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON \
  -DCURL_USE_LIBSSH2=OFF -DCURL_USE_LIBSSH=OFF -DCURL_USE_LIBPSL=OFF \
  -DUSE_LIBIDN2=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF \
  -DUSE_NGHTTP2=OFF -DUSE_NGTCP2=OFF -DUSE_QUICHE=OFF \
  -DENABLE_ARES=OFF -DCURL_USE_GSSAPI=OFF -DCURL_USE_LIBUV=OFF
cp /tmp/curlcfg/lib/curl_config.h packages/curl/config/
```

Nine seconds. The `-D` set is what makes this build **lean**: OpenSSL + zlib and
nothing else. A default configure enables brotli, zstd, nghttp2, idn2, psl,
libssh2, c-ares, krb5 and ngtcp2 — 15 link libraries, any one of which breaks
`use("curl")` when it bumps. This config links 4.

Protocols are *not* disabled: they are internal code with no external deps, so
the wrapper still covers http/https/ftp/imap/pop3/smtp/rtsp/ws and the rest.
Dropped by the lean config: ldap/ldaps (needs -lldap -llber), scp/sftp (libssh2)
and HTTP/2 (nghttp2).

## The pin this file implies

`curl_config.h` is a snapshot of **this machine's** feature detection at the
pinned commit. It travels with the package, so the build is reproducible — but
it is a single-target pin, which matches the Hub (CLAUDE.md: "the hub is
currently a single-target hub"). Regenerate on a version bump, and diff the
result: a changed `SIZEOF_*` or a vanished `USE_*` is real news.

Captured from curl-8_21_0 (`68720b4837284335b2d63cb358f8f6ce65f5bc55`) on
2026-08-16, cmake 4.4.2, glibc/x86_64-linux-gnu.
