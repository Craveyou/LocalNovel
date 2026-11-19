#ifndef XLIB_ANDROID_LF_H
#define XLIB_ANDROID_LF_H
/* XLib's read-only source files are capped at 1 GiB, so signed 32-bit off_t
 * suffices for API 23 on every reviewed ABI. Deliberately do not import the
 * upstream large-file remapping of libc calls to newer Android API symbols.
 * This header is requested internally by libarchive's archive.h on Android. */
#endif
