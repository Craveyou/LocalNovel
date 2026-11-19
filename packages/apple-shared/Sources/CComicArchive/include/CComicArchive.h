#ifndef XLIB_COMIC_ARCHIVE_H
#define XLIB_COMIC_ARCHIVE_H
#include <stdint.h>
#include <stddef.h>
typedef struct xca_reader xca_reader;
xca_reader *xca_open(const char *path);
/* 0 = entry, 1 = EOF, -1 = error. Pointer remains owned by the reader. */
int xca_next(xca_reader *, const char **path, int64_t *size, int *directory, int *link);
int64_t xca_read(xca_reader *, void *buffer, size_t count);
typedef int (*xca_sink)(void *context, const void *bytes, size_t count);
int xca_uses_sink(xca_reader *);
int xca_process(xca_reader *, xca_sink, void *context);
const char *xca_error(xca_reader *);
void xca_close(xca_reader *);
#endif
