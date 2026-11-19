#!/bin/sh
# Android-only client for the shared disposable HTTPS/PostgreSQL harness.
set -eu
android_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
repo_root="$(CDPATH= cd -- "$android_root/../.." && pwd)"
if [ "${1:-}" != --client ]; then
  exec sh "$repo_root/scripts/start-document-interop-test.sh" sh "$android_root/scripts/test-comic-interop.sh" --client
fi
: "${ANDROID_HOME:=$HOME/Library/Android/sdk}"
: "${ANDROID_SERIAL:=emulator-5554}"
case "$ANDROID_SERIAL" in emulator-*) ;; *) echo 'Use a disposable Android emulator' >&2; exit 1 ;; esac
adb="$ANDROID_HOME/platform-tools/adb"
port="${TEST_RUNNER_XLIB_DOC_INTEROP_URL##*:}"
case "$port" in ''|*[!0-9]*) exit 1 ;; esac
"$adb" -s "$ANDROID_SERIAL" reverse "tcp:$port" "tcp:$port" >/dev/null
result="$(mktemp /tmp/xlib-android-comic-interop.XXXXXX)"
trap '"$adb" -s "$ANDROID_SERIAL" reverse --remove "tcp:$port" >/dev/null 2>&1 || true; rm -f "$result"' EXIT
"$adb" -s "$ANDROID_SERIAL" shell am instrument -w -r \
  -e class com.xlib.txtreader.ComicInteropDeviceTest \
  -e interopUrl "$TEST_RUNNER_XLIB_DOC_INTEROP_URL" \
  -e interopRun "$TEST_RUNNER_XLIB_DOC_INTEROP_RUN" \
  -e interopCertificate "$TEST_RUNNER_XLIB_DOC_INTEROP_CERT" \
  com.xlib.txtreader.test/androidx.test.runner.AndroidJUnitRunner >"$result" 2>&1
cat "$result"
grep -Eq '^OK \([0-9]+ tests?\)$' "$result"
