#ifndef XLIB_UNRAR_H
#define XLIB_UNRAR_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct xur_reader xur_reader;
/* Synchronous, <=64 KiB chunks. Return nonzero to cancel. Never reenter UnRAR. */
typedef int (*xur_sink)(void *context, const void *bytes, size_t count);
xur_reader *xur_open(const char *utf8_path);
int xur_next(xur_reader *, int64_t expected_size, int expected_directory, int eof);
int xur_process(xur_reader *, xur_sink, void *context);
const char *xur_error(xur_reader *);
void xur_close(xur_reader *);
#ifdef __cplusplus
}
#endif
#endif
