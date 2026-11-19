#!/bin/sh
# Five actual client phases on one disposable HTTPS/PostgreSQL instance.
# Android owns its installed app/instrumentation; this script never builds,
# installs, resets, or edits that application, and never impersonates a client.
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
if [ "${1:-}" != --client ]; then
    exec sh "$root/scripts/start-document-interop-test.sh" sh "$root/scripts/test-comic-cross-client-interop.sh" --client
fi
: "${TEST_RUNNER_XLIB_DOC_INTEROP_URL:?Requires disposable HTTPS harness}"
: "${TEST_RUNNER_XLIB_DOC_INTEROP_RUN:?Requires unique test run}"
: "${TEST_RUNNER_XLIB_DOC_INTEROP_CERT:?Requires test-only certificate}"
case "$TEST_RUNNER_XLIB_DOC_INTEROP_URL" in
    https://localhost:*) ;;
    *) echo 'Only the disposable localhost HTTPS service is allowed' >&2; exit 2 ;;
esac
android_script="$root/apps/android/scripts/test-cross-comic-stage.sh"
if [ ! -f "$android_script" ]; then echo 'Android staged instrumentation entry is missing' >&2; exit 2; fi
android_phase() {
    printf 'Cross-client Android phase: %s\n' "$1"
    XLIB_COMIC_INTEROP_STAGE="$1" sh "$android_script"
}
ios_phase() {
    printf 'Cross-client iOS phase: %s\n' "$1"
    TEST_RUNNER_XLIB_COMIC_INTEROP_STAGE="$1" \
        "${MAKE:-make}" -C "$root" test-ios \
        IOS_TEST_ARGS='-collect-test-diagnostics never -only-testing:XLibReaderTests/DocumentInteropTests/testComicAndroidIOSStagedHandoff'
}
android_phase seed
ios_phase accept-android
android_phase accept-ios
ios_phase accept-android-delete
android_phase verify-deleted
echo 'Four original comics passed Android -> iOS -> Android -> iOS deletion handoff (simulators, not physical-device performance)'
