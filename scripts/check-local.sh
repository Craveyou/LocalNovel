#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

"$root/scripts/check-sensitive-data.py"
ruby "$root/scripts/check-contract.rb"
ruby "$root/scripts/check-contract-fixtures.rb"
"$root/scripts/check-legacy-cleanup-plan.py"
"$root/scripts/check-migrator-retirement.py"
ruby "$root/scripts/test-release-check.rb"
if [ -n "${RELEASE_VERSION:-}" ]; then
    "$root/scripts/release-check.sh" "$RELEASE_VERSION"
fi
"$root/scripts/test-backend.sh"
make -C "$root" test-kindle-core
swift test --package-path "$root/packages/apple-shared"

cd "$root/apps/android"
./gradlew :app:testDebugUnitTest lintDebug

"$root/scripts/build-ios-debug.sh"

echo "local checks passed"
