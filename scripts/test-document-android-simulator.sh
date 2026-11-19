#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
serial="${XLIB_ANDROID_SIMULATOR_SERIAL:?Set XLIB_ANDROID_SIMULATOR_SERIAL to the dedicated emulator serial}"
adb="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
output="$root/artifacts/document-performance"
runs="${XLIB_DOCUMENT_PERF_RUNS:-3}"
# This test clears the target DB. Refuse other simulators or any physical device.
name="$("$adb" -s "$serial" emu avd name | tr -d '\r' | head -n 1)"
if [ "$name" != "xlib013-performance" ]; then
    echo "Expected dedicated AVD xlib013-performance; refusing to reset $name" >&2
    exit 2
fi
python3 "$root/scripts/document-performance.py" generate
make -C "$root" build-android-debug
(
    cd "$root/apps/android"
    ./gradlew :app:assembleDebugAndroidTest "-PdocumentPerfFixtures=$output/fixtures"
)
"$adb" -s "$serial" install -r "$root/apps/android/app/build/outputs/apk/debug/xlib-debug.apk"
"$adb" -s "$serial" install -r "$root/apps/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
for sample in pdf-small pdf-large pdf-images epub-small epub-large epub-long-chapter; do
    log="$output/android-$sample.log"
    "$adb" -s "$serial" shell am instrument -w -r \
        -e class com.xlib.txtreader.DocumentPerformanceTest -e documentPerformance 1 \
        -e sample "$sample" -e runs "$runs" \
        com.xlib.txtreader.test/androidx.test.runner.AndroidJUnitRunner > "$log" 2>&1
    if ! rg -q 'OK \(1 test\)' "$log"; then
        cat "$log" >&2
        exit 1
    fi
    echo "Measured Android $sample; log: $log"
done
python3 "$root/scripts/document-performance.py" report "$output"/android-*.log
