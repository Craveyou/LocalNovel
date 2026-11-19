/* XLib policy additions to the pinned libarchive core (not upstream). */
#ifndef XLIB_ARCHIVE_POLICY_H
#define XLIB_ARCHIVE_POLICY_H
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "archive_entry.h"
static int xlib_utf8_name(const void *bytes, size_t n) {
    const unsigned char *p = bytes;
    size_t i = 0;
    if (!n) return 0;
    while (i < n) {
        uint32_t c = p[i++], min = 0;
        unsigned continuation = 0;
        if (!c || c == 92) return 0;
        if (c < 0x80) continue;
        if (c >= 0xc2 && c <= 0xdf) { c &= 31; continuation = 1; min = 0x80; }
        else if (c >= 0xe0 && c <= 0xef) { c &= 15; continuation = 2; min = 0x800; }
        else if (c >= 0xf0 && c <= 0xf4) { c &= 7; continuation = 3; min = 0x10000; }
        else return 0;
        while (continuation--) {
            if (i == n || (p[i] & 0xc0) != 0x80) return 0;
            c = (c << 6) | (p[i++] & 63);
        }
        if (c < min || c > 0x10ffff || (c >= 0xd800 && c <= 0xdfff)) return 0;
    }
    return 1;
}
/* Names must never pass through the process-global locale. */
static int xlib_copy_name(struct archive_entry *entry, const void *bytes,
                         size_t n, const char *charset) {
    if (!strcmp(charset, "UTF-16BE") && (n & 1)) --n;
    if (!n || n > 65535) return 0;
    static const uint16_t cp437[128] = {
        0x00c7,0x00fc,0x00e9,0x00e2,0x00e4,0x00e0,0x00e5,0x00e7,
        0x00ea,0x00eb,0x00e8,0x00ef,0x00ee,0x00ec,0x00c4,0x00c5,
        0x00c9,0x00e6,0x00c6,0x00f4,0x00f6,0x00f2,0x00fb,0x00f9,
        0x00ff,0x00d6,0x00dc,0x00a2,0x00a3,0x00a5,0x20a7,0x0192,
        0x00e1,0x00ed,0x00f3,0x00fa,0x00f1,0x00d1,0x00aa,0x00ba,
        0x00bf,0x2310,0x00ac,0x00bd,0x00bc,0x00a1,0x00ab,0x00bb,
        0x2591,0x2592,0x2593,0x2502,0x2524,0x2561,0x2562,0x2556,
        0x2555,0x2563,0x2551,0x2557,0x255d,0x255c,0x255b,0x2510,
        0x2514,0x2534,0x252c,0x251c,0x2500,0x253c,0x255e,0x255f,
        0x255a,0x2554,0x2569,0x2566,0x2560,0x2550,0x256c,0x2567,
        0x2568,0x2564,0x2565,0x2559,0x2558,0x2552,0x2553,0x256b,
        0x256a,0x2518,0x250c,0x2588,0x2584,0x258c,0x2590,0x2580,
        0x03b1,0x00df,0x0393,0x03c0,0x03a3,0x03c3,0x00b5,0x03c4,
        0x03a6,0x0398,0x03a9,0x03b4,0x221e,0x03c6,0x03b5,0x2229,
        0x2261,0x00b1,0x2265,0x2264,0x2320,0x2321,0x00f7,0x2248,
        0x00b0,0x2219,0x00b7,0x221a,0x207f,0x00b2,0x25a0,0x00a0
    };
    const unsigned char *input = bytes;
    char *result = malloc(n * 4 + 1);
    if (!result) return 0;
    size_t length = 0;
    int valid = 1;
    if (!strcmp(charset, "UTF-8")) {
        memcpy(result, bytes, n);
        length = n;
    } else for (size_t i = 0; i < n && valid; ++i) {
        uint32_t c;
        if (!strcmp(charset, "CP437")) {
            c = input[i] < 128 ? input[i] : cp437[input[i] - 128];
        } else if (!strcmp(charset, "UTF-16BE") && i + 1 < n) {
            c = ((uint32_t)input[i] << 8) | input[i + 1];
            ++i;
            if (c >= 0xd800 && c <= 0xdbff) {
                if (i + 2 >= n) { valid = 0; break; }
                uint32_t low = ((uint32_t)input[i + 1] << 8) | input[i + 2];
                if (low < 0xdc00 || low > 0xdfff) { valid = 0; break; }
                c = 0x10000 + ((c - 0xd800) << 10) + (low - 0xdc00);
                i += 2;
            } else if (c >= 0xdc00 && c <= 0xdfff) { valid = 0; break; }
        } else { valid = 0; break; }
        if (c < 128) result[length++] = (char)c;
        else if (c < 0x800) {
            result[length++] = (char)(0xc0 | (c >> 6));
            result[length++] = (char)(0x80 | (c & 63));
        } else if (c < 0x10000) {
            result[length++] = (char)(0xe0 | (c >> 12));
            result[length++] = (char)(0x80 | ((c >> 6) & 63));
            result[length++] = (char)(0x80 | (c & 63));
        } else {
            result[length++] = (char)(0xf0 | (c >> 18));
            result[length++] = (char)(0x80 | ((c >> 12) & 63));
            result[length++] = (char)(0x80 | ((c >> 6) & 63));
            result[length++] = (char)(0x80 | (c & 63));
        }
    }
    valid = valid && xlib_utf8_name(result, length);
    if (valid) {
        result[length] = 0;
        archive_entry_update_pathname_utf8(entry, result);
    }
    free(result);
    return valid;
}
#endif
