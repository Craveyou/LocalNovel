/* XLib's read-only POSIX profile. No Darwin crypto, iconv, ACL or xattr.
 * Selected through upstream PLATFORM_CONFIG_H, never by editing config.h.
 * Android API 23+: use only libc, zlib and the vendored BLAKE2 implementation.
 * Keep this profile independent of the SDK that generated Apple's config.h.
 */
#ifndef XLIB_READ_ONLY_POSIX_CONFIG_H
#define XLIB_READ_ONLY_POSIX_CONFIG_H

#if defined(__ANDROID__) && __ANDROID_API__ < 23
#error XLib archive requires Android API 23 or newer
#endif

#define __LIBARCHIVE_CONFIG_H_INCLUDED 1
#define LIBARCHIVE_VERSION_NUMBER "3008009"
#define LIBARCHIVE_VERSION_STRING "3.8.9"
#define PACKAGE_VERSION "3.8.9"
#define VERSION "3.8.9"
#define PACKAGE_NAME "libarchive"
#define PACKAGE_STRING "libarchive 3.8.9"
#define SIZEOF_INT __SIZEOF_INT__
#define SIZEOF_LONG __SIZEOF_LONG__
#define SIZEOF_WCHAR_T __SIZEOF_WCHAR_T__
#define STDC_HEADERS 1

#define HAVE_CTYPE_H 1
#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_LOCALE_H 1
#define HAVE_PTHREAD_H 1
#define HAVE_STDARG_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_IOCTL_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_SELECT_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_TIME_H 1
#define HAVE_UNISTD_H 1
#define HAVE_WCHAR_H 1
#define HAVE_WCTYPE_H 1
#define HAVE_ZLIB_H 1
#define HAVE_LIBZ 1

#define HAVE_DECL_INT32_MAX 1
#define HAVE_DECL_INT32_MIN 1
#define HAVE_DECL_INT64_MAX 1
#define HAVE_DECL_INT64_MIN 1
#define HAVE_DECL_INTMAX_MAX 1
#define HAVE_DECL_INTMAX_MIN 1
#define HAVE_DECL_SIZE_MAX 1
#define HAVE_DECL_SSIZE_MAX 1
#define HAVE_DECL_UINT32_MAX 1
#define HAVE_DECL_UINT64_MAX 1
#define HAVE_DECL_UINTMAX_MAX 1
#define HAVE_DECL_STRERROR_R 1
#define HAVE_EILSEQ 1
#define HAVE_INTMAX_T 1
#define HAVE_UINTMAX_T 1
#define HAVE_LONG_LONG_INT 1
#define HAVE_UNSIGNED_LONG_LONG 1
#define HAVE_UNSIGNED_LONG_LONG_INT 1
#define HAVE_WCHAR_T 1

#define HAVE_CTIME_R 1
#define HAVE_FCNTL 1
#define HAVE_FSEEKO 1
#define HAVE_FSTAT 1
#define HAVE_GETEUID 1
#define HAVE_GETPID 1
#define HAVE_GETTIMEOFDAY 1
#define HAVE_GMTIME_R 1
#define HAVE_LOCALTIME_R 1
#define HAVE_LSTAT 1
#define HAVE_MBRTOWC 1
#define HAVE_MEMMOVE 1
#define HAVE_MEMSET 1
#define HAVE_MKSTEMP 1
#define HAVE_READLINK 1
#define HAVE_STRCHR 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR 1
#define HAVE_STRERROR_R 1
#define HAVE_STRFTIME 1
#define HAVE_STRNLEN 1
#define HAVE_STRRCHR 1
#define HAVE_SYSCONF 1
#define HAVE_TIMEGM 1
#define HAVE_TZSET 1
#define HAVE_WCRTOMB 1
#define HAVE_WCSCMP 1
#define HAVE_WCSCPY 1
#define HAVE_WCSLEN 1
#define HAVE_WCTOMB 1
#define HAVE_WMEMCMP 1
#define HAVE_WMEMCPY 1
#define HAVE_WMEMMOVE 1
#define HAVE_STRUCT_STAT_ST_BLKSIZE 1

#if defined(__ANDROID__) || defined(__APPLE__)
#define HAVE_ARC4RANDOM_BUF 1
#endif
#if defined(__APPLE__)
#define HAVE_STRUCT_STAT_ST_MTIMESPEC_TV_NSEC 1
#else
#define HAVE_STRUCT_STAT_ST_MTIM_TV_NSEC 1
#endif

/* Deliberately absent: HAVE_ICONV[_H], HAVE_NL_LANGINFO (API 26), all
 * ARCHIVE_CRYPTO_* and external compression providers. XLib's patched readers
 * decode names using the fixed CP437/strict UTF-8/UTF-16 routines, not locale.
 * Unsupported encrypted archives are rejected, not routed to crypto stubs.
 * Do not set _FILE_OFFSET_BITS=64 on 32-bit min23: that can select newer libc
 * entry points. XLib's <=1 GiB input fits a signed 32-bit off_t.
 */
#endif
