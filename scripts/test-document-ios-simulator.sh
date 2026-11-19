#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
simulator="${XLIB_IOS_SIMULATOR_ID:?Set XLIB_IOS_SIMULATOR_ID to a booted test simulator}"
output="$root/artifacts/document-performance"
runs="${XLIB_DOCUMENT_PERF_RUNS:-3}"
xcrun simctl list devices booted -j | python3 -c '
import json,sys
items=[d for group in json.load(sys.stdin)["devices"].values() for d in group]
if not any(d["udid"]==sys.argv[1] and d["state"]=="Booted" for d in items):
    raise SystemExit("Select a booted test simulator")
' "$simulator"
python3 "$root/scripts/document-performance.py" generate
make -C "$root" build-ios-debug
mkdir -p "$output/runs"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
for sample in PDFSmall PDFLarge PDFImages EPUBSmall EPUBLarge EPUBLongChapter; do
    log="$output/runs/ios-$sample-$stamp.log"
    # Separate test launches keep one sample's PDFKit caches out of the next sample.
    TEST_RUNNER_XLIB_DOCUMENT_PERF_FIXTURES="$output/fixtures" \
    TEST_RUNNER_XLIB_DOCUMENT_PERF_RUNS="$runs" \
    xcodebuild -project "$root/apps/ios/XLibReader.xcodeproj" -scheme XLibReader \
        -configuration Debug -destination "platform=iOS Simulator,id=$simulator" \
        -derivedDataPath "$root/artifacts/.build/ios-debug" \
        -resultBundlePath "$output/runs/ios-$sample-$stamp.xcresult" -parallel-testing-enabled NO \
        "-only-testing:XLibReaderTests/DocumentPerformanceTests/test$sample" CODE_SIGNING_ALLOWED=NO test > "$log" 2>&1
    echo "Measured iOS $sample; log: $log"
done
python3 "$root/scripts/document-performance.py" report "$output/runs"/ios-*-"$stamp".log
