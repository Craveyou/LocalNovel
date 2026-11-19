/* Developer-only smoke test, not an application extraction API. */
#include <XLibArchiveCore.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

static void le16(unsigned char *p, unsigned v) {
    p[0] = (unsigned char)v; p[1] = (unsigned char)(v >> 8);
}
static void le32(unsigned char *p, uint32_t v) {
    le16(p, v); le16(p + 2, v >> 16);
}
static struct archive *reader(int rar_option) {
    struct archive *a = archive_read_new();
    archive_read_support_filter_none(a);
    archive_read_support_format_zip_seekable(a);
    archive_read_support_format_rar(a);
    archive_read_support_format_rar5(a);
    /* Match the Apple wrapper, including its compatibility options. */
    archive_read_set_format_option(a, "zip", "hdrcharset", "CP437");
    if (rar_option)
        archive_read_set_format_option(a, "rar", "hdrcharset", "UTF-8");
    archive_read_set_format_option(a, "zip", "mac-ext", NULL);
    return a;
}
static int memory_zip(int method, int corrupt) {
    /* Real one-entry ZIP with a CP437 name, not a mock archive reader. */
    unsigned char zip[128] = {0};
    const unsigned char name[] = {0x82, '.', 'p', 'n', 'g'};
    const unsigned char expected[] = {0xc3, 0xa9, '.', 'p', 'n', 'g', 0};
    const unsigned char stored[] = {'a', 'b', 'c'};
    const unsigned char deflated[] = {1, 3, 0, 0xfc, 0xff, 'a', 'b', 'c'};
    const unsigned char *payload = method ? deflated : stored;
    unsigned packed = method ? sizeof(deflated) : sizeof(stored);
    uint32_t crc = (uint32_t)crc32(0, stored, sizeof(stored));
    unsigned central = 30 + sizeof(name) + packed;
    unsigned end = central + 46 + sizeof(name);
    le32(zip, 0x04034b50); le16(zip + 4, 20); le16(zip + 8, method);
    le32(zip + 14, crc); le32(zip + 18, packed); le32(zip + 22, 3);
    le16(zip + 26, sizeof(name));
    memcpy(zip + 30, name, sizeof(name));
    memcpy(zip + 30 + sizeof(name), payload, packed);
    if (corrupt) zip[central - 1] ^= 1;
    unsigned char *c = zip + central;
    le32(c, 0x02014b50); le16(c + 4, 20); le16(c + 6, 20);
    le16(c + 10, method); le32(c + 16, crc); le32(c + 20, packed);
    le32(c + 24, 3); le16(c + 28, sizeof(name));
    memcpy(c + 46, name, sizeof(name));
    c = zip + end;
    le32(c, 0x06054b50); le16(c + 8, 1); le16(c + 10, 1);
    le32(c + 12, end - central); le32(c + 16, central);
    struct archive *a = reader(1);
    struct archive_entry *entry = NULL;
    unsigned char result[32] = {0};
    int failed = archive_read_open_memory(a, zip, end + 22) != ARCHIVE_OK;
    if (!failed) failed = archive_read_next_header(a, &entry) != ARCHIVE_OK;
    if (!failed) {
        const char *path = archive_entry_pathname_utf8(entry);
        failed = !path || strcmp(path, (const char *)expected);
    }
    la_ssize_t count = failed ? -1 : archive_read_data(a, result, sizeof(result));
    if (corrupt && !failed) failed = count >= 0;
    else if (!failed) failed = count != 3 || memcmp(result, stored, 3) ||
        archive_read_data(a, result, sizeof(result)) != 0 ||
        archive_read_next_header(a, &entry) != ARCHIVE_EOF;
    if (failed) fprintf(stderr, "memory ZIP method=%d corrupt=%d: %s\n",
        method, corrupt, archive_error_string(a));
    archive_read_free(a);
    return failed;
}
/* Rename only the first header of the genuine upstream binary-data fixture.
 * Its compressed bodies and file CRCs stay byte-identical. This is a format-
 * valid metadata mutation, not a fabricated RAR decoder/magic-only fixture. */
static unsigned get16(const unsigned char *p) {
    return p[0] | (unsigned)p[1] << 8;
}
static unsigned char *rar4_rename(const unsigned char *source, size_t length,
    const unsigned char *name, size_t name_size, int unicode, size_t *result_size) {
    if (length < 100 || memcmp(source, "Rar!\x1a\x07\0", 7)) return NULL;
    size_t header = 7 + get16(source + 12);
    if (header + 32 > length || source[header + 2] != 0x74) return NULL;
    unsigned flags = get16(source + header + 3);
    size_t old_size = get16(source + header + 26);
    size_t header_size = get16(source + header + 5);
    if ((flags & 0x100) || old_size != 15 ||
        memcmp(source + header + 32, "random_data.bin", 15) ||
        header_size < 32 + old_size || header + header_size > length ||
        header_size - old_size + name_size > 65535) return NULL;
    *result_size = length - old_size + name_size;
    unsigned char *result = malloc(*result_size);
    if (!result) return NULL;
    memcpy(result, source, header + 32);
    memcpy(result + header + 32, name, name_size);
    memcpy(result + header + 32 + name_size, source + header + 32 + old_size,
        length - header - 32 - old_size);
    header_size = header_size - old_size + name_size;
    le16(result + header + 5, (unsigned)header_size);
    le16(result + header + 26, (unsigned)name_size);
    le16(result + header + 3, unicode ? flags | 0x200 : flags & ~0x200);
    le16(result + header, (unsigned)crc32(0, result + header + 2,
        (uInt)header_size - 2));
    return result;
}
static int rar4_name_case(const unsigned char *source, size_t length,
    const unsigned char *name, size_t name_size, int unicode,
    const char *expected, int rar_option) {
    size_t result_size;
    unsigned char *result = rar4_rename(source, length, name, name_size, unicode,
        &result_size);
    if (!result) return 1;
    struct archive *a = reader(rar_option);
    struct archive_entry *entry = NULL;
    int status = archive_read_open_memory(a, result, result_size);
    if (status == ARCHIVE_OK) status = archive_read_next_header(a, &entry);
    int failed = 0;
    if (!expected) failed = status >= ARCHIVE_WARN;
    else {
        const char *path = status == ARCHIVE_OK ? archive_entry_pathname_utf8(entry) : NULL;
        failed = !path || strcmp(path, expected);
        unsigned char buffer[65536];
        uint64_t size = 0;
        la_ssize_t n = 0;
        while (!failed && (n = archive_read_data(a, buffer, sizeof(buffer))) > 0)
            size += (uint64_t)n;
        if (n < 0 || size != 1048576) failed = 1;
    }
    if (failed) fprintf(stderr, "RAR4 name unicode=%d option=%d expected=%s: %s\n",
        unicode, rar_option, expected ? expected : "rejection", archive_error_string(a));
    archive_read_free(a); free(result);
    return failed;
}
static size_t rar4_unicode(unsigned char *name, const uint16_t *units, size_t count) {
    /* RAR's encoded suffix: fallback + NUL, high byte, 2-bit modes (explicit
     * UTF-16LE units). The reader must independently track decoded UTF-16BE. */
    name[0] = 'x'; name[1] = 0; name[2] = 0;
    size_t offset = 3;
    for (size_t i = 0; i < count;) {
        size_t flags_at = offset++;
        name[flags_at] = 0;
        for (unsigned slot = 0; slot < 4 && i < count; ++slot, ++i) {
            name[flags_at] |= 2U << (6 - 2 * slot);
            le16(name + offset, units[i]); offset += 2;
        }
    }
    return offset;
}
static int rar4_names(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) return 1;
    if (fseek(file, 0, SEEK_END)) { fclose(file); return 1; }
    long length = ftell(file);
    if (length < 100 || length > 4 * 1024 * 1024 || fseek(file, 0, SEEK_SET)) {
        fclose(file); return 1;
    }
    unsigned char *source = malloc((size_t)length);
    if (!source) { fclose(file); return 1; }
    size_t read_size = fread(source, 1, (size_t)length, file);
    fclose(file);
    if (read_size != (size_t)length) { free(source); return 1; }
    int failed = 0;
    const unsigned char ascii[] = "ascii-name.bin", utf8[] = "caf\xc3\xa9.png";
    const unsigned char invalid[] = {0xc0, 0xaf}, slash[] = "a\\b.png";
    const unsigned char nul[] = {'a', 0, 'b'};
    const uint16_t units[] = {0xe9, '.', 'p', 'n', 'g'};
    const uint16_t astral[] = {0xd83e, 0xdd8a, '.', 'p', 'n', 'g'};
    const uint16_t backslash[] = {'a', '\\', 'b'};
    const uint16_t surrogate[] = {0xd800, 'b'};
    for (int option = 0; option < 2; ++option) {
        for (int unicode = 0; unicode < 2; ++unicode) {
            failed |= rar4_name_case(source, read_size, ascii, sizeof(ascii) - 1,
                unicode, (const char *)ascii, option);
            failed |= rar4_name_case(source, read_size, utf8, sizeof(utf8) - 1,
                unicode, (const char *)utf8, option);
        }
        unsigned char encoded[64];
        size_t count = rar4_unicode(encoded, units, sizeof(units) / sizeof(*units));
        failed |= rar4_name_case(source, read_size, encoded, count, 1, "\xc3\xa9.png", option);
        count = rar4_unicode(encoded, astral, sizeof(astral) / sizeof(*astral));
        failed |= rar4_name_case(source, read_size, encoded, count, 1,
            "\xf0\x9f\xa6\x8a.png", option);
        count = rar4_unicode(encoded, backslash, sizeof(backslash) / sizeof(*backslash));
        failed |= rar4_name_case(source, read_size, encoded, count, 1, NULL, option);
        count = rar4_unicode(encoded, surrogate, sizeof(surrogate) / sizeof(*surrogate));
        failed |= rar4_name_case(source, read_size, encoded, count, 1, NULL, option);
        failed |= rar4_name_case(source, read_size, invalid, sizeof(invalid), 0, NULL, option);
        failed |= rar4_name_case(source, read_size, slash, sizeof(slash) - 1, 0, NULL, option);
        failed |= rar4_name_case(source, read_size, nul, sizeof(nul), 0, NULL, option);
    }
    free(source);
    if (!failed) puts("RAR4 raw UTF-8 / encoded Unicode names passed (default + UTF-8 option)");
    return failed;
}
static int scan(const char *path) {
    struct archive *a = reader(1);
    int status = archive_read_open_filename(a, path, 65536);
    unsigned entries = 0;
    uint64_t expanded = 0;
    struct archive_entry *entry;
    unsigned char buffer[65536];
    while (status == ARCHIVE_OK &&
        (status = archive_read_next_header(a, &entry)) == ARCHIVE_OK) {
        if (++entries > 20000 || !archive_entry_pathname_utf8(entry) ||
            archive_entry_is_encrypted(entry) || archive_entry_symlink(entry) ||
            archive_entry_hardlink(entry)) { status = ARCHIVE_FATAL; break; }
        if (archive_entry_filetype(entry) == AE_IFDIR) continue;
        if (archive_entry_filetype(entry) != AE_IFREG ||
            archive_entry_size(entry) < 0 ||
            archive_entry_size(entry) > 128 * 1024 * 1024) {
            status = ARCHIVE_FATAL; break;
        }
        uint64_t size = 0;
        la_ssize_t n;
        while ((n = archive_read_data(a, buffer, sizeof(buffer))) > 0) {
            size += (uint64_t)n; expanded += (uint64_t)n;
            if (size > 128 * 1024 * 1024 || expanded > UINT64_C(4294967296)) {
                status = ARCHIVE_FATAL; break;
            }
        }
        if (n < 0 || size != (uint64_t)archive_entry_size(entry))
            status = ARCHIVE_FATAL;
    }
    int failed = status != ARCHIVE_EOF;
    if (failed) fprintf(stderr, "%s: %s\n", path, archive_error_string(a));
    else printf("%s: %u entries, %llu expanded bytes\n", path, entries,
        (unsigned long long)expanded);
    archive_read_free(a);
    return failed;
}
int main(int argc, char **argv) {
    int failed = memory_zip(0, 0) | memory_zip(8, 0) |
        memory_zip(0, 1) | memory_zip(8, 1);
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--rar4-names") && i + 1 < argc)
            failed |= rar4_names(argv[++i]);
        else failed |= scan(argv[i]);
    }
    if (!failed) puts("Portable archive smoke checks passed");
    return failed ? 1 : 0;
}
