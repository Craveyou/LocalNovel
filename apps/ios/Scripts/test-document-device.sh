#!/bin/sh
# Run from any directory. Generated documents never enter the normal book library.
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
device="${XLIB_IOS_DEVICE_UDID:?Set the connected test iPhone UDID}"
team="${XLIB_IOS_DEVELOPMENT_TEAM:?Set the existing development team}"
runs="${XLIB_DOCUMENT_PERF_RUNS:-3}"
output="${XLIB_DOCUMENT_DEVICE_OUTPUT:-$root/artifacts/ios-document-device}"
derived="$output/derived-data"
mkdir -p "$output"
python3 "$root/scripts/document-performance.py" generate > "$output/fixtures.log"
if [ "${XLIB_DOCUMENT_DEVICE_PREBUILT:-0}" != 1 ]; then
    sh "$root/scripts/prepare-build-version.sh" ios
    xcodebuild -project "$root/apps/ios/XLibReader.xcodeproj" -scheme XLibReader \
        -configuration Release -destination "platform=iOS,id=$device" \
        -derivedDataPath "$derived" -parallel-testing-enabled NO \
        -allowProvisioningUpdates DEVELOPMENT_TEAM="$team" ENABLE_TESTABILITY=YES \
        'OTHER_SWIFT_FLAGS=$(inherited) -D XLIB_DOCUMENT_DEVICE_PERFORMANCE' \
        -only-testing:XLibReaderTests/DocumentPerformanceTests build-for-testing > "$output/build.log" 2>&1
fi
xcrun devicectl device install app --device "$device" \
    "$derived/Build/Products/Release-iphoneos/XLibReader.app" > "$output/install.log"
xcrun devicectl device copy to --device "$device" \
    --source "$root/artifacts/document-performance/fixtures" \
    --destination Library/Caches/XLibDocumentPerformance \
    --domain-type appDataContainer --domain-identifier com.xlib.txtreader > "$output/transfer.log"
for sample in PDFSmall PDFLarge PDFImages EPUBSmall EPUBLarge EPUBLongChapter; do
    TEST_RUNNER_XLIB_DOCUMENT_PERF_FIXTURES=device-cache \
    TEST_RUNNER_XLIB_DOCUMENT_PERF_DEVICE=1 \
    TEST_RUNNER_XLIB_DOCUMENT_PERF_RUNS="$runs" \
    xcodebuild -project "$root/apps/ios/XLibReader.xcodeproj" -scheme XLibReader \
        -configuration Release -destination "platform=iOS,id=$device" \
        -derivedDataPath "$derived" -resultBundlePath "$output/$sample.xcresult" \
        -parallel-testing-enabled NO -only-testing:"XLibReaderTests/DocumentPerformanceTests/test$sample" \
        DEVELOPMENT_TEAM="$team" ENABLE_TESTABILITY=YES test-without-building > "$output/$sample.log" 2>&1
    printf 'Completed physical-device sample: %s\n' "$sample"
done
TEST_RUNNER_XLIB_DOCUMENT_PERF_FIXTURES=device-cache \
TEST_RUNNER_XLIB_DOCUMENT_PERF_DEVICE=1 \
xcodebuild -project "$root/apps/ios/XLibReader.xcodeproj" -scheme XLibReader \
    -configuration Release -destination "platform=iOS,id=$device" \
    -derivedDataPath "$derived" -resultBundlePath "$output/MixedSessions.xcresult" \
    -parallel-testing-enabled NO -only-testing:XLibReaderTests/DocumentPerformanceTests/testRepeatedMixedDocumentSessions \
    DEVELOPMENT_TEAM="$team" ENABLE_TESTABILITY=YES test-without-building > "$output/MixedSessions.log" 2>&1
python3 "$root/apps/ios/Scripts/summarize-document-device.py" "$output" --runs "$runs"
# Keep the original simulator measurements and reports intact. Each xcresult also
# contains one JSON attachment per run, including sampled app memory and timings.
printf 'Physical-device results: %s\n' "$output"
