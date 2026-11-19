# Android consumption handoff (not an Android acceptance claim)

## Update: approved UnRAR 7.23 RAR4-solid adapter

The product owner approved official UnRAR; CMake now also exposes
`XLibUnRAR` / `xlib::unrar` (C++11, PIC, RARDLL/SILENT, no RAR_SMP).
Its public `XLibUnRAR.h` has a C ABI. Link it with the NDK C++ runtime;
the original `xlib::archive` C target remains independently consumable.
For production integration prefer the new `XLibComicArchive` / `xlib::comic`
CMake target. It exports the exact `CComicArchive.h` facade used by Apple and
links both engines transitively. JNI calls `xca_open/next`, then either
`xca_process` (chunk sink) or `xca_read`, and finally `xca_close`; this keeps
the paired metadata/decoder policy in one implementation, not two copies.
It is platform-neutral C, not a dependency on Foundation or Apple UI.
Path NFC/safety/duplicate checks, image validation and full-stream declared/
actual byte budgets still belong in the client consuming the facade.

The remaining sections describe that original C target's prior host evidence,
not acceptance of the new adapter on Android.

The facade already pairs the strict RAR4 parser option
`archive_read_set_format_option(archive, "rar", "xlib-metadata-only", "1")`
with `xur_open` / `xur_next` / `xur_process` / `xur_close` in physical entry
order. `xur_next` checks expected size/directory or EOF; `xur_process` requires
a synchronous <=64 KiB sink returning nonzero on cancellation. Do not read
RAR4 bodies through libarchive in this metadata-only mode. Keep NFC/path and
duplicate checks in JNI, reject unsafe headers before processing, drain every
entry for CRC and compare the new `comic-basic-rar4-solid.cbr` against CBZ.
Callbacks cannot reenter the decoder. All adapter DLL operations serialize
around upstream global error state; it must be the only UnRAR entry point.
See `RAR4-SOLID.md` for exact limits, checksum, patches and licensing.

Distribute the complete `unrar/license.txt` and required restriction notice
in Android's own notices/resources as well; Apple's bundled resource does not
satisfy Android distribution. `xlib::unrar` propagates 16 KiB linker alignment
flags but still requires final ELF/APK and min23/ABI/runtime verification.
No Android app/JNI/Gradle changes or device acceptance are made by this update.

## Original libarchive C target

`CMakeLists.txt` defines `XLibArchiveCore` / alias `xlib::archive`: a PIC static
library with an explicit list of the same 35 read-only C sources used by Apple.
No configure, downloads, system libarchive, iconv, CommonCrypto or C++ runtime
is required. The only external library is the NDK's system zlib (`z`).
`config/read-only-posix.h` is selected using upstream `PLATFORM_CONFIG_H`;
the Darwin-generated `libarchive/config.h` and SwiftPM manifests are untouched.
The build rejects Android API levels below 23. Width macros follow the target
compiler rather than assuming Apple arm64's `long` size.

Example standalone build, with caller-resolved absolute SDK tool paths:

```sh
cmake -S packages/native-archive -B /private/tmp/xlib-archive-arm64 \
  -DCMAKE_TOOLCHAIN_FILE=/absolute/ndk/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-23 \
  -DCMAKE_BUILD_TYPE=Release
cmake --build /private/tmp/xlib-archive-arm64 --parallel
```

In the Android-owned JNI CMake project, use `add_subdirectory` with this package
and `target_link_libraries(your_jni PRIVATE xlib::archive)`. Public includes
expose `XLibArchiveCore.h`, `archive.h` and `archive_entry.h`. Only register
`archive_read_support_filter_none`, `archive_read_support_format_zip_seekable`,
`archive_read_support_format_rar` and `archive_read_support_format_rar5`.
Do not enable a general/all-formats or streaming-ZIP fallback. ZIP mac-ext must
be disabled so hidden resource entries are not silently removed. Consume paths
through `archive_entry_pathname_utf8`; no locale fallback or filesystem extract.
ZIP's fixed CP437/UTF-8 conversion, RAR4's validated UTF-8/decoded UTF-16BE and
RAR5's strict UTF-8 do not require iconv. Do not add Android API 28 `iconv` just
to match the Apple link line. RAR4 tracks the validated raw-name encoding
directly; neither locale discovery nor `setlocale` is used. Its compatibility
`hdrcharset=UTF-8` option is accepted without creating a conversion object;
other charset options are rejected rather than enabling codepage guessing.

The native parser enforces ZIP method/encoding/metadata constraints, RAR
encryption/multivolume rejection and the 64 MiB dictionary limit. The Swift
wrapper's 1 GiB input / 20,000 entries / 128 MiB entry / 4 GiB expanded bounds,
NFC path validation and canonical duplicate detection are NOT automatically
provided by linking the C core: JNI must enforce the same policy. Drain all
entry bodies, including hidden entries and solid predecessors, for CRC and
expanded-byte accounting. Check cancellation before every header and bounded
read chunk; reject links/special entries. The manifest owns 10,000-page and
image-format validation. Image-less ZIP must remain available for EPUB dispatch.

For Android, the static target propagates `max-page-size=16384` and
`common-page-size=16384` linker options to the final JNI shared library. A `.a`
itself has no ELF LOAD segments and proves nothing about load alignment.
The final `.so` must pass `llvm-readelf -lW` LOAD alignment checks; the APK/AAB
must separately pass 16 KiB ZIP alignment/packaging checks and runtime tests.
See https://developer.android.com/guide/practices/page-sizes.

## Historical portable-host evidence

At the initial handoff the local SDK contained no NDK or CMake. No Android-target compilation,
min23 symbol audit, ABI matrix, JNI run or 16 KiB ELF/APK/device acceptance has
been performed by the core owner. All 35 C sources were compiled on the macOS
host with the portable profile instead of the Darwin config and linked using
only `-lz`. `nm -u` found no iconv/CommonCrypto/nl_langinfo/locale_charset imports.
The developer `tests/portable-smoke.c` passed CP437 store/deflate ZIP and corrupt
CRC rejection, the genuine RAR4 binary-data fixture (2 entries; 1,081,194 expanded
bytes), and four genuine RAR5 stored/compressed/solid fixtures (1, 1, 4, 7 entries;
29, 1,200, 16,384, 25,776 expanded bytes respectively).
It also passed 22 RAR4 name checks, with and without the explicit UTF-8 option:
ASCII/raw UTF-8, FHD_UNICODE without an encoded suffix, encoded Unicode with
non-BMP surrogate pairs, plus rejection of malformed UTF-8/UTF-16, NUL and
backslash. Those checks mutate only the first filename, lengths/flags and
header CRC in the genuine upstream binary-data fixture; compressed bodies and
their CRCs stay unchanged. No fake-magic RAR or locale change is involved.

Follow-up evidence (2026-10-24):

- Portable objects/static library/smoke executable:
  `/private/tmp/xlib-native-rar4-followup.UbGbMa`.
- Portable run log: `/private/tmp/xlib-rar4-followup-portable.log`.
- Apple shared: 10 archive XCTest cases and 14 shared Swift Testing cases passed;
  `/private/tmp/xlib-rar4-followup-tests.log`.
- macOS14 arm64, iOS17 arm64 device and arm64 simulator compilation passed;
  `/private/tmp/xlib-rar4-followup-build.log`, libraries in
  `/private/tmp/xlib-comic-native.ha7iI7`.

The shared run used `swift test --disable-sandbox --scratch-path
/private/tmp/xlib-comic-tests --package-path packages/apple-shared` with temporary
module caches. The three-target run used `bash scripts/build-comic-native.sh`.
No SwiftPM manifest or Apple configuration was changed by this follow-up.
That host run was not Bionic validation. The Android owner must build
each shipping ABI with the selected pinned NDK, audit undefined symbols/API
requirements, compare entry names/hashes against Apple's fixtures, and test
both 4 KiB and 16 KiB runtime environments before promoting G0.

The earlier portable RAR4 error (`Pathname cannot be converted from current
locale to current locale`) is resolved by direct raw-encoding tracking. The
Apple regression checks the original ASCII filenames, Unicode/NFC read-back
and identical decoded payloads, while retaining rejection of unsafe paths.

The optional CMake `XLIB_ARCHIVE_BUILD_TESTS=ON` target builds the same developer
smoke test (`xlib_archive_smoke`); its optional file arguments drain real
archives. `--rar4-names /absolute/test_read_format_rar_binary_data.rar` additionally
runs the metadata-mutation checks above. It is not the JNI policy wrapper and
does not implement NFC/cancel.

The genuine upstream RAR tests cover RAR4 non-solid and RAR5 stored/compressed/
solid text/binary payloads, not a complete image-CBR corpus. The original C-only
target does not decode RAR4 solid; use the approved paired UnRAR adapter above.
Apple now has a 24-PNG solid regression corpus, but Android JNI consumption and
ABI/device verification remain required. Android app/JNI/Gradle files are not changed.

## Current NDK/API/ELF evidence (2026-10-24)

`make test-comic-native-android` now builds the public paired facade, not a
private Android copy, with the installed NDK **27.2.12479018** and CMake
**3.22.1**, targeting **API 23** for **arm64-v8a, armeabi-v7a and x86_64**.
All three compile and link a shared developer probe against both decoders.
`llvm-readelf -lW` confirms every probe PT_LOAD alignment is at least 16 KiB;
an API 22 configure is required to fail. The command neither installs SDK
components nor downloads tools. Log: `/private/tmp/xlib-0141-ndk-final.log`;
outputs: `/private/var/folders/l0/5ht9f2gs6znf1b8pb_p7_ds00000gn/T/xlib-comic-android.XOlyO8`.

The CMake guard reads the actual NDK platform level, not the legacy toolchain's
constant `CMAKE_SYSTEM_VERSION=1`. Public compatibility headers keep the bounded
read-only archive profile on API 23: no unavailable large-file libc remapping,
and pre-26 `lutimes` returns ENOTSUP rather than following a link or importing a
newer API. The in-memory RAR_TEST path does not change filesystem timestamps.

The macOS CMake test build also passes both host tests (ZIP smoke and the
1,024-case paired mutation regression); the separate Apple security target
passes ASan/UBSan, including unaligned LE/BE integer access. These are distinct
proofs, not Android runtime executions.

This closes the public-source three-ABI min23 compile/link and **probe ELF**
alignment gap. It does **not** certify the app's final JNI library or APK/AAB,
ZIP packaging alignment, 4/16 KiB device loading, Android policy/migration/UI,
or Android/iOS progress handoff. Those remain Android/joint acceptance work.
The core owner did not modify `apps/android` during this follow-up.
