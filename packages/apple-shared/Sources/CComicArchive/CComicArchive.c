#include "CComicArchive.h"
#include <XLibArchiveCore.h>
#include <XLibUnRAR.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

struct xca_reader { struct archive *archive; xur_reader *unrar; const char *error; int directory; };
xca_reader *xca_open(const char *path) {
    xca_reader *r = calloc(1, sizeof(*r));
    if (!r) return NULL;
    r->archive = archive_read_new();
    if (!r->archive) { free(r); return NULL; }
    archive_read_support_filter_none(r->archive);
    archive_read_support_format_zip_seekable(r->archive);
    archive_read_support_format_rar(r->archive);
    archive_read_support_format_rar5(r->archive);
    archive_read_set_format_option(r->archive, "zip", "hdrcharset", "CP437");
    archive_read_set_format_option(r->archive, "rar", "hdrcharset", "UTF-8");
    archive_read_set_format_option(r->archive, "zip", "mac-ext", NULL);
    unsigned char signature[7];
    FILE *probe = fopen(path, "rb");
    int rar4 = probe && fread(signature, 1, sizeof(signature), probe) == sizeof(signature) &&
        memcmp(signature, "Rar!\x1a\x07\x00", sizeof(signature)) == 0;
    if (probe) fclose(probe);
    if (rar4) {
        archive_read_set_format_option(r->archive, "rar", "xlib-metadata-only", "1");
        r->unrar = xur_open(path);
        if (!r->unrar) r->error = "Cannot create UnRAR decoder";
    }
    if (archive_read_open_filename(r->archive, path, 65536) != ARCHIVE_OK)
        r->error = "Cannot open comic archive";
    return r;
}
int xca_next(xca_reader *r, const char **path, int64_t *size, int *directory, int *link) {
    if (r->error) return -1;
    struct archive_entry *e = NULL;
    int result = archive_read_next_header(r->archive, &e);
    if (result == ARCHIVE_EOF) {
        if (r->unrar && xur_next(r->unrar, 0, 0, 1) != 1) {
            r->error = xur_error(r->unrar); return -1;
        }
        return 1;
    }
    if (result != ARCHIVE_OK) return -1;
    if (archive_entry_is_encrypted(e) || archive_read_has_encrypted_entries(r->archive) > 0) {
        r->error = "Encrypted comic archives are unsupported"; return -1;
    }
    *path = archive_entry_pathname_utf8(e);
    if (!*path || !archive_entry_size_is_set(e)) {
        r->error = "Invalid comic entry name or size"; return -1;
    }
    *size = archive_entry_size(e);
    *directory = archive_entry_filetype(e) == AE_IFDIR;
    r->directory = *directory;
    *link = archive_entry_symlink(e) != NULL || archive_entry_hardlink(e) != NULL ||
        (archive_entry_filetype(e) != AE_IFREG && !*directory);
    if (r->unrar && xur_next(r->unrar, *size, *directory, 0) != 0) {
        r->error = xur_error(r->unrar); return -1;
    }
    return 0;
}
int64_t xca_read(xca_reader *r, void *buffer, size_t count) {
    if (r->error) return -1;
    if (r->unrar) { r->error = "UnRAR requires the cancellable chunk sink"; return -1; }
    if (r->directory) return 0;
    return archive_read_data(r->archive, buffer, count);
}
int xca_uses_sink(xca_reader *r) { return r->unrar != NULL; }
int xca_process(xca_reader *r, xca_sink sink, void *context) {
    if (r->error || !r->unrar) return -1;
    int result = xur_process(r->unrar, sink, context);
    if (result) r->error = xur_error(r->unrar);
    return result;
}
const char *xca_error(xca_reader *r) {
    if (r->error) return r->error;
    const char *detail = archive_error_string(r->archive);
    return detail ? detail : (r->error ? r->error : "Comic archive validation failed");
}
void xca_close(xca_reader *r) {
    if (r) { xur_close(r->unrar); archive_read_free(r->archive); free(r); }
}
