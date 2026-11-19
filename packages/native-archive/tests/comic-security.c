/* Developer-only bounded mutation regression of the actual paired decoder.
 * No extraction, network, commercial compressor or production data involved.
 * This is not a coverage-guided fuzz campaign or a complete security audit. */
#include "CComicArchive.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct budget { uint64_t entry, total; int cancel; };
static int collect(void *context, const void *bytes, size_t size) {
    struct budget *b = context;
    (void)bytes;
    if (b->cancel || size > 65536 || size > 33554432 - b->total) return -1;
    b->entry += size; b->total += size;
    return 0;
}
static int scan(const char *path, int cancel) {
    /* A malformed input that hangs fails the suite, rather than wedging CI. */
    alarm(5);
    xca_reader *reader = xca_open(path);
    if (!reader) { alarm(0); return -1; }
    struct budget b = {0, 0, cancel};
    unsigned count = 0;
    int status = -1;
    for (;;) {
        const char *name = NULL;
        int64_t declared = -1;
        int directory = 0, link = 0;
        int next = xca_next(reader, &name, &declared, &directory, &link);
        if (next == 1) { status = (int)count; break; }
        if (next || !name || link || declared < 0 || declared > 134217728 ||
            ++count > 20000) break;
        b.entry = 0;
        if (xca_uses_sink(reader)) {
            if (xca_process(reader, collect, &b)) break;
        } else {
            unsigned char buffer[65536];
            int failed = 0;
            for (;;) {
                int64_t n = xca_read(reader, buffer, sizeof(buffer));
                if (n < 0) { failed = 1; break; }
                if (!n) break;
                if ((uint64_t)n > sizeof(buffer) || collect(&b, buffer, (size_t)n)) {
                    failed = 1; break;
                }
            }
            if (failed) break;
        }
        if (b.entry != (uint64_t)declared) break;
    }
    xca_close(reader);
    alarm(0);
    return status;
}
static void write_case(const char *path, const unsigned char *bytes, size_t size) {
    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); exit(2); }
    int failed = fwrite(bytes, 1, size, f) != size;
    if (fclose(f)) failed = 1;
    if (failed) { perror("write mutation"); exit(2); }
}
static uint32_t random_word(uint32_t *state) {
    uint32_t x = *state;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    return *state = x;
}
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    const char *names[] = {"comic-basic.cbz", "comic-basic-rar4.cbr",
        "comic-basic-rar5.cbr", "comic-basic-rar4-solid.cbr"};
    /* The compressor emits an explicit pages/ directory in the solid sample. */
    const int expected_entries[] = {25, 25, 25, 26};
    char source[4096], output[4096];
    if (snprintf(output, sizeof(output), "%s/mutation.bin", argv[2]) >= sizeof(output)) return 2;
    uint32_t seed = 0x584c4942;
    unsigned cases = 0, rejected = 0;
    for (unsigned fixture = 0; fixture < 4; ++fixture) {
        if (snprintf(source, sizeof(source), "%s/%s", argv[1], names[fixture]) >= sizeof(source)) return 2;
        FILE *f = fopen(source, "rb");
        if (!f || fseek(f, 0, SEEK_END)) return 2;
        long length = ftell(f);
        if (length <= 128 || length > 4194304 || fseek(f, 0, SEEK_SET)) return 2;
        unsigned char *original = malloc((size_t)length), *mutation = malloc((size_t)length);
        if (!original || !mutation || fread(original, 1, (size_t)length, f) != (size_t)length) return 2;
        fclose(f);
        int baseline = scan(source, 0), cancelled = scan(source, 1);
        if (baseline != expected_entries[fixture] || cancelled >= 0) {
            fprintf(stderr, "Baseline/cancellation failed: %s entries=%d cancel=%d\n", source, baseline, cancelled); return 1;
        }
        for (unsigned i = 0; i < 256; ++i) {
            memcpy(mutation, original, (size_t)length);
            size_t size = (size_t)length;
            if (i < 64) size = i;
            else if (i < 128) size = random_word(&seed) % (size_t)length;
            else {
                /* Keep magic intact to reach format parsing and body decoding. */
                size_t offset = 8 + random_word(&seed) % ((size_t)length - 8);
                mutation[offset] ^= (unsigned char)(1u << (random_word(&seed) % 8));
            }
            write_case(output, mutation, size);
            fprintf(stderr, "case=%u fixture=%s mutation=%u bytes=%zu seed=%08x\n",
                cases, names[fixture], i, size, seed);
            if (scan(output, 0) < 0) ++rejected;
            ++cases;
        }
        /* Failure/cancellation must not poison upstream's process-global state. */
        if (scan(source, 0) != expected_entries[fixture]) return 1;
        free(mutation); free(original);
    }
    printf("Native ASan/UBSan mutation regression: %u cases, %u rejected; four originals and cancellation/recovery passed\n",
        cases, rejected);
    return 0;
}
