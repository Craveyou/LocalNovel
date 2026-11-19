#!/usr/bin/env bash
# Public native core only. Never edits/builds the Android app, installs SDKs,
# accepts licenses, downloads dependencies, or claims APK/device acceptance.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
cmake="$sdk/cmake/3.22.1/bin/cmake"
ninja="$sdk/cmake/3.22.1/bin/ninja"
ndk="$sdk/ndk/27.2.12479018"
host=darwin-x86_64
if [[ "$(uname -s)" == Linux ]]; then host=linux-x86_64; fi
readelf="$ndk/toolchains/llvm/prebuilt/$host/bin/llvm-readelf"
for required in "$cmake" "$ninja" "$readelf" "$ndk/build/cmake/android.toolchain.cmake"; do
    if [[ ! -f "$required" ]]; then echo "Missing pinned developer tool: $required" >&2; exit 2; fi
done
build="$(mktemp -d "${TMPDIR:-/tmp}/xlib-comic-android.XXXXXX")"
for abi in arm64-v8a armeabi-v7a x86_64; do
    "$cmake" -S "$root/packages/native-archive" -B "$build/$abi" -G Ninja \
        -DCMAKE_MAKE_PROGRAM="$ninja" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$abi" -DANDROID_PLATFORM=android-23 -DANDROID_STL=c++_static \
        -DXLIB_ARCHIVE_BUILD_TESTS=ON
    "$cmake" --build "$build/$abi" --parallel 4
    "$readelf" -lW "$build/$abi/libxlib_comic_link_probe.so" | python3 -c '
import sys
loads = [line.split() for line in sys.stdin if line.lstrip().startswith("LOAD ")]
if not loads or any(int(line[-1], 0) < 16384 for line in loads):
    raise SystemExit("ELF LOAD alignment is below 16 KiB")
print("ELF LOAD alignment >= 16 KiB:", len(loads), "segments")
'
    echo "Passed common native API23 compile/link/ELF: $abi"
done
if "$cmake" -S "$root/packages/native-archive" -B "$build/reject-api22" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$ninja" -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=armeabi-v7a -DANDROID_PLATFORM=android-22 > "$build/api22.log" 2>&1; then
    echo "Minimum-API guard incorrectly accepted API22" >&2; exit 1
fi
if ! rg -q 'require API 23 or newer' "$build/api22.log"; then
    echo "API22 configuration failed for an unexpected reason; inspect $build/api22.log" >&2; exit 1
fi
echo "Common native checks passed; outputs: $build (not APK/runtime acceptance)"
