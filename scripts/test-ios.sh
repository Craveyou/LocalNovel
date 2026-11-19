#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
if [ "${1:-}" != "--build-locked" ]; then
    mkdir -p "$root/artifacts/.build"
    exec ruby "$root/scripts/with-build-lock.rb" "$root/artifacts/.build/ios-build.lock" sh "$0" --build-locked "$@"
fi
shift
sh "$root/scripts/prepare-build-version.sh" ios
stamp="$(date '+%Y%m%d-%H%M%S')-$$"
output="$root/artifacts/ios-tests"
mkdir -p "$output"
destination="${XLIB_IOS_TEST_DESTINATION:-}"
if [ -z "$destination" ]; then
    simulator_id="$(xcrun simctl list devices available --json | ruby -rjson -e '
      devices = JSON.parse(STDIN.read).fetch("devices").values.flatten.select { |d| d["name"] == "XLib Test iPhone" }
      device = devices.find { |d| d["state"] == "Booted" } || devices.first
      abort "Create XLib Test iPhone or set XLIB_IOS_TEST_DESTINATION" unless device
      puts device.fetch("udid")')"
    destination="platform=iOS Simulator,id=$simulator_id"
fi
exec xcodebuild -project "$root/apps/ios/XLibReader.xcodeproj" -scheme XLibReader \
    -configuration Debug -destination "$destination" \
    -derivedDataPath "$root/artifacts/.build/ios-tests" \
    -resultBundlePath "$output/ios-$stamp.xcresult" -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "$@" test
