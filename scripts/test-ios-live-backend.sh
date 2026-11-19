#!/bin/sh
# Public API only. Never runs migrations, starts a server, or opens its database.
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
: "${XLIB_LIVE_BACKEND_URL:?Set the deployed HTTPS API base URL explicitly}"
: "${XLIB_LIVE_BACKEND_OPT_IN:?Set to 1 to allow creating isolated live test identities}"
if [ "$XLIB_LIVE_BACKEND_OPT_IN" != 1 ]; then
    echo 'Explicit live API test opt-in required' >&2
    exit 2
fi
export TEST_RUNNER_XLIB_LIVE_BACKEND_URL="$XLIB_LIVE_BACKEND_URL"
export TEST_RUNNER_XLIB_LIVE_BACKEND_OPT_IN=1
exec "${MAKE:-make}" -C "$root" test-ios \
    IOS_TEST_ARGS="-collect-test-diagnostics never -only-testing:XLibReaderTests/LiveBackendFunctionalTests -only-testing:XLibReaderUITests/LiveBackendUITests"
