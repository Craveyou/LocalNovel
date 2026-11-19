#!/bin/sh
# Real installed clients, five stages, one disposable HTTPS/PostgreSQL service.
# Android owns its APK and instrumentation: never build/reset/install it here.
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
android_script="$root/apps/android/scripts/test-cross-kindle-stage.sh"
if [ ! -f "$android_script" ]; then
    echo 'Android Kindle staged instrumentation entry is missing' >&2
    exit 2
fi
if [ "${1:-}" != --client ]; then
    exec sh "$root/scripts/start-document-interop-test.sh" sh "$root/scripts/test-kindle-cross-client-interop.sh" --client
fi
: "${TEST_RUNNER_XLIB_DOC_INTEROP_URL:?Requires disposable HTTPS harness}"
: "${TEST_RUNNER_XLIB_DOC_INTEROP_RUN:?Requires unique test run}"
: "${TEST_RUNNER_XLIB_DOC_INTEROP_CERT:?Requires test-only certificate}"
case "$TEST_RUNNER_XLIB_DOC_INTEROP_URL" in
    https://localhost:*) ;;
    *) echo 'Only the disposable localhost HTTPS service is allowed' >&2; exit 2 ;;
esac
android_phase() {
    printf 'Cross-client Kindle Android phase: %s\n' "$1"
    XLIB_KINDLE_INTEROP_STAGE="$1" sh "$android_script"
}
ios_phase() {
    printf 'Cross-client Kindle iOS phase: %s\n' "$1"
    TEST_RUNNER_XLIB_KINDLE_INTEROP_STAGE="$1" \
        "${MAKE:-make}" -C "$root" test-ios \
        IOS_TEST_ARGS='-collect-test-diagnostics never -only-testing:XLibReaderTests/DocumentInteropTests/testKindleAndroidIOSStagedHandoff'
}
android_phase seed
ios_phase accept-android
android_phase accept-ios
ios_phase accept-android-delete
android_phase verify-deleted
echo 'Six original Kindle publications passed Android -> iOS -> Android -> iOS deletion handoff (simulators, not physical-device acceptance)'
