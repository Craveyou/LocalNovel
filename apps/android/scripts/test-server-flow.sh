#!/bin/sh
# Explicitly authorized, isolated writes against the deployed backend; no TLS bypass or local server.
set -eu
: "${XLIB_TEST_SERVER_URL:?Set the deployed HTTPS backend URL}"
: "${XLIB_TEST_SERVER_WRITES:?Set isolated-test-data to allow isolated server writes}"
[ "$XLIB_TEST_SERVER_WRITES" = isolated-test-data ]
case "$XLIB_TEST_SERVER_URL" in https://*) ;; *) exit 2 ;; esac
: "${ANDROID_HOME:=$HOME/Library/Android/sdk}"
: "${ANDROID_SERIAL:=emulator-5554}"
case "$ANDROID_SERIAL" in emulator-*) ;; *) echo 'Use a disposable emulator' >&2; exit 2 ;; esac
result="$(mktemp /tmp/xlib-android-server-flow.XXXXXX)"
trap 'rm -f "$result"' EXIT
"$ANDROID_HOME/platform-tools/adb" -s "$ANDROID_SERIAL" shell am instrument -w -r \
    -e class com.xlib.txtreader.ServerBackendFlowDeviceTest \
    -e serverUrl "$XLIB_TEST_SERVER_URL" \
    -e allowServerWrites "$XLIB_TEST_SERVER_WRITES" \
    -e previousRun "${XLIB_TEST_PREVIOUS_RUN:-}" \
    com.xlib.txtreader.test/androidx.test.runner.AndroidJUnitRunner >"$result" 2>&1
cat "$result"
grep -Eq '^OK \(1 test\)$' "$result"
