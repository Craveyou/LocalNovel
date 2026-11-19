# XLib read-only archive core

Pinned upstream: libarchive **3.8.9**, tag `v3.8.9`.
Source: https://github.com/libarchive/libarchive/releases/download/v3.8.9/libarchive-3.8.9.tar.xz
Release: https://github.com/libarchive/libarchive/releases/tag/v3.8.9
Downloaded 2026-10-24. SHA-256 of the release tarball:
`888c934f9d95648ecb9163dc8e23ab80a476ecb81a8f1154704a227b5b676dde`.
This value matches the official checksum published at
https://libarchive.org/downloads/libarchive-3.8.9.tar.xz.sums.txt.

Only ZIP/RAR/RAR5 readers and their required utility sources are compiled.
The approved official UnRAR **7.23 final** is additionally pinned for RAR4
body decoding, including solid streams; libarchive remains its strict metadata
parser. See RAR4-SOLID.md for source checksum, licensing and adapter policy.
No archive writers, filesystem extraction, external filters, command invocation,
or system libarchive linkage. Apple system zlib and iconv are linked.
See COPYING and each retained source header for redistribution notices.
Configuration was generated with upstream configure on Apple arm64, disabling
ACL/xattr, command-line tools, bz2, libb2, lz4, zstd, lzma, CNG, OpenSSL, XML2,
and expat. Apple deployment targets are macOS 14 and iOS 17.

## XLib policy changes

- ZIP store/deflate only; no encrypted entries, split volumes, SFX/padding,
  unknown methods, duplicate local offsets or inconsistent central/local names.
- ZIP names decode without the process locale: UTF-8 flag, a validated 0x7075
  Unicode path field, otherwise a fixed CP437 table. Unicode field version, raw
  filename CRC, UTF-8 scalar validity and conflicting fields are checked.
- RAR4 names must be valid Unicode/UTF-8 (legacy unspecified high-byte encodings
  are not guessed). Malformed Unicode encoding, embedded NUL and backslash
  normalization are rejected. The validated raw encoding is tracked directly
  as UTF-8 or decoded UTF-16BE, without locale/charset-object discovery.
  RAR5 names require strict UTF-8.
- Native RAR4 PPMd allocation is capped at 64 MiB before allocation.
  Native RAR5 already rejects dictionaries above 64 MiB before allocation.
  RAR5's zero-valued-but-present CRC is now checked as well.
- UnRAR raw integer loads/stores use `memcpy` instead of typed unaligned
  pointer accesses, including the endian-swapping paths. This fixes alignment/
  aliasing undefined behavior found by the native UBSan regression.
- ZIP central-directory allocation is capped at 20,000 entries, 64 MiB total
  metadata and 8,192 raw filename bytes per entry. The filename/metadata caps
  are additional implementation support limits and must not be hidden.
- The Swift bridge enforces 1 GiB input, 20,000 entries, 128 MiB declared/actual
  entry data and 4 GiB declared/actual expanded data per full scan. Page count
  (10,000), image signatures and dimensions are ComicManifest / reader concerns.
  Every header and 64 KiB output chunk checks cooperative task cancellation;
  an individual native decompression call is not preemptible.
- Every ordinary entry is fully drained for CRC validation, including hidden
  files, metadata and predecessors of a requested solid-stream entry.
- Swift emits NFC paths, rejects unsafe components, controls, colon and links,
  detects canonical duplicates, and reuses the original physical entry order
  for reads. Nothing is extracted to an entry-named filesystem path.

## Build and verification

`make test-comic-native-security` builds the actual paired C facade and both
engines with ASan + UBSan (fail on the first finding), then runs 1,024 fixed-seed
truncation/bit-flip cases derived from four original CBZ/RAR4/RAR5/solid packages.
Valid originals, output cancellation and recovery are required to pass too.
An explicit unaligned-offset LE/BE integer test protects the UnRAR patch.
The harness caps its own work and fails on a five-second per-input timeout.
It is a bounded mutation regression, not a coverage-guided fuzz campaign or
proof against all malicious archives. macOS ASan leak detection is disabled;
address/alignment/undefined-behavior diagnostics remain enabled.
The Apple CI job runs this target. No test CLI is included in the application.

CMake consumers may link `xlib::comic` for the same platform-neutral
`CComicArchive.h` facade used by Apple; it transitively links `xlib::archive`
and `xlib::unrar`. The source happens to live in the AppleShared C target but
has no Swift/Foundation/UI dependency. Android NDK acceptance is separate.

Run `bash scripts/build-comic-native.sh` at the repository root to compile
macOS 14 arm64, iOS 17 arm64 simulator and iOS 17 arm64 device static libraries
in a fresh temporary folder. No CMake, Homebrew, downloads, signing or system
libarchive are involved. SwiftPM consumes this same source target directly.
Normal shared checks run through `make test-apple-shared` (and `make check`).

For a standalone fixed-source PIC static CMake target, see `CMakeLists.txt` and
`ANDROID.md`. Android uses a separate no-iconv/no-CommonCrypto POSIX profile,
not this Darwin config. The target propagates 16 KiB final-shared-library link
options and requires min23. `make test-comic-native-android` verifies API 23
compile/link for arm64-v8a, armeabi-v7a and x86_64 plus 16 KiB PT_LOAD alignment
of a shared developer probe, and rejects API 22. Final JNI/APK packaging and
device loading remain separate acceptance requirements (see `ANDROID.md`).
The portable-profile host smoke covers CBZ, RAR4 non-solid and RAR5, including
RAR4 Unicode/raw-encoding regression checks documented in `ANDROID.md`.
Host evidence alone is not Android ABI or full common-core G0 acceptance.

The upstream BLAKE2 sources are used under their CC0 alternative.
The retained fixture sources and their checksum inventory are in fixtures/.

## Explicit gaps

The default libarchive RAR4 reader still rejects solid bodies. Apple's paired
metadata-only + UnRAR path now supports the tested solid RAR4 image corpus;
RAR5 remains on libarchive. This is not full RAR or joint first-batch acceptance.
The upstream RAR payloads are text/binary files. A separate original 24-PNG
RAR4 compressed-solid CBR now exercises image-bearing reverse/reopen reads.
This is not a full JPEG/PNG/method matrix. Android app JNI/packaging/device
loading, real-device memory/performance, coverage-guided decoder fuzzing and
full format-method coverage are not claimed by Apple tests or the public NDK
link probe. The bounded ASan/UBSan mutation regression above is not full fuzzing.

The 64 MiB limit is a **dictionary** limit, not total decoder/process memory.
RAR5 can also allocate a dictionary-sized filtered buffer; returned page Data,
image decoding and caches consume additional memory. Measure those separately.
