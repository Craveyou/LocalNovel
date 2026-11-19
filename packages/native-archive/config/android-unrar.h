#ifndef XLIB_ANDROID_UNRAR_H
#define XLIB_ANDROID_UNRAR_H
#include <sys/time.h>
#include <errno.h>
/* Read-only RAR_TEST never writes symlink timestamps. Keep the unused helper
 * a hard failure rather than linking API-26 lutimes into a min23 decoder or
 * falling back to an operation that follows a symlink. */
#if defined(__ANDROID__) && __ANDROID_API__ < 26
static inline int xlib_unrar_unavailable_lutimes(const char *path, const struct timeval *times) {
    (void)path; (void)times;
    errno = ENOTSUP;
    return -1;
}
#define lutimes xlib_unrar_unavailable_lutimes
#endif
#endif
