/* Developer-only shared-library link probe, never shipped with the app. */
#include "CComicArchive.h"
int xlib_comic_link_probe(const char *path) {
    xca_reader *reader = xca_open(path);
    if (!reader) return -1;
    const char *name = 0;
    int64_t bytes = 0;
    int directory = 0, link = 0;
    int status = xca_next(reader, &name, &bytes, &directory, &link);
    xca_close(reader);
    return status;
}
