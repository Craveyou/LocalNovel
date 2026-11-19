#!/bin/sh
# Consume one already-running shared service; never create a new DB per stage.
set -eu
stage="${1:-${XLIB_KINDLE_INTEROP_STAGE:-}}"
case "$stage" in seed|accept-ios|verify-deleted) ;; *) echo 'Usage: test-cross-kindle-stage.sh seed|accept-ios|verify-deleted' >&2; exit 2 ;; esac
: "${TEST_RUNNER_XLIB_DOC_INTEROP_URL:?Requires the shared disposable HTTPS service}"
: "${TEST_RUNNER_XLIB_DOC_INTEROP_RUN:?Requires the shared run ID}"
: "${TEST_RUNNER_XLIB_DOC_INTEROP_CERT:?Requires the shared one-run certificate}"
: "${ANDROID_HOME:=$HOME/Library/Android/sdk}"
: "${ANDROID_SERIAL:=emulator-5554}"
case "$ANDROID_SERIAL" in emulator-*) ;; *) echo 'Use a disposable Android emulator' >&2; exit 1 ;; esac
case "$TEST_RUNNER_XLIB_DOC_INTEROP_URL" in https://localhost:*) ;; *) exit 1 ;; esac
port="${TEST_RUNNER_XLIB_DOC_INTEROP_URL##*:}"
case "$port" in ''|*[!0-9]*) exit 1 ;; esac
adb="$ANDROID_HOME/platform-tools/adb"
result="$(mktemp /tmp/xlib-cross-kindle-android.XXXXXX)"
trap '"$adb" -s "$ANDROID_SERIAL" reverse --remove "tcp:$port" >/dev/null 2>&1 || true; rm -f "$result"' EXIT
"$adb" -s "$ANDROID_SERIAL" reverse "tcp:$port" "tcp:$port" >/dev/null
"$adb" -s "$ANDROID_SERIAL" shell am instrument -w -r \
  -e class com.xlib.txtreader.CrossKindleInteropDeviceTest \
  -e interopStage "$stage" \
  -e interopUrl "$TEST_RUNNER_XLIB_DOC_INTEROP_URL" \
  -e interopRun "$TEST_RUNNER_XLIB_DOC_INTEROP_RUN" \
  -e interopCertificate "$TEST_RUNNER_XLIB_DOC_INTEROP_CERT" \
  com.xlib.txtreader.test/androidx.test.runner.AndroidJUnitRunner >"$result" 2>&1
cat "$result"
grep -Eq '^OK \(1 test\)$' "$result"
