#pragma once
#include <sys/time.h>
#include <errno.h>
// Upstream's filesystem symlink timestamp path is never used by the streaming
// bridge (all links are rejected). Bionic exposes lutimes only from API 26.
// Explicit failure preserves the minimum API without following any symlink.
#if defined(__ANDROID__) && __ANDROID_API__ < 26
static inline int xlib_unavailable_lutimes(const char*,const struct timeval*) {
    errno=ENOTSUP;return -1;
}
#define lutimes xlib_unavailable_lutimes
#endif
