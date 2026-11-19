SHELL := /bin/sh

.PHONY: help bootstrap check check-alpha check-sensitive-data check-legacy-cleanup-plan check-migrator-retirement \
	prepare-p8-performance test-p8-ios-device check-p8-performance-record \
	test-backend test-backend-postgres test-apple-shared test-kindle-core test-kindle-ios-interop test-kindle-cross-client-interop test-ios test-ios-live-backend test-comic-ios-interop test-comic-cross-client-interop test-comic-native-security test-comic-native-android \
	build-android-debug build-android-release \
	build-ios-debug build-ios-release \
	build-macos-debug build-macos-release \
	build-backend-release prepare-release release-check

# Capture explicit selection before assigning the release-only default.
CHECK_RELEASE := $(if $(filter undefined,$(origin RELEASE)),$(RELEASE_VERSION),$(RELEASE))
RELEASE ?= $(or $(RELEASE_VERSION),0.12.0)

help:
	@printf '%s\n' \
		'make bootstrap             Check tools and install locked backend dependencies' \
		'make check                 Run development checks (optional RELEASE enables strict manifest check)' \
		'make check-alpha           Run the full Alpha verification suite' \
		'make check-sensitive-data  Reject tracked credentials and signing material' \
		'make check-legacy-cleanup-plan  Validate active P7 cleanup allowlists and protected data' \
		'make check-migrator-retirement  Validate the retired legacy migrator boundary' \
		'make prepare-p8-performance  Generate deterministic P8 performance fixtures and record template' \
		'make test-p8-ios-device  Run opt-in P8 Release measurements on one connected iPhone' \
		'make check-p8-performance-record  Validate P8 physical-device results (optional RECORD path)' \
		'make test-backend          Lint, typecheck, test and build the backend' \
		'make test-backend-postgres  Test backend with a disposable PostgreSQL 17 cluster' \
		'make test-apple-shared     Test the shared Swift package' \
		'make test-kindle-core      Check identical Kindle bundle and bounded reference vectors' \
		'make test-kindle-ios-interop Test Kindle iOS sync with disposable HTTPS/PostgreSQL 17' \
		'make test-kindle-cross-client-interop Run installed Android/iOS staged Kindle handoff' \
		'make test-ios              Test iOS on XLib Test iPhone (optional IOS_TEST_ARGS / XLIB_IOS_TEST_DESTINATION)' \
		'make test-ios-live-backend  Opt-in deployed HTTPS functional tests (XLIB_LIVE_BACKEND_URL / XLIB_LIVE_BACKEND_OPT_IN=1)' \
		'make test-comic-ios-interop  Test iOS comic sync with disposable local HTTPS/PostgreSQL 17' \
		'make test-comic-cross-client-interop  Run installed Android and iOS staged comic handoff' \
		'make test-comic-native-security  Run bounded native ASan/UBSan archive mutation regression' \
		'make test-comic-native-android  Verify pinned common native API23 ABI builds and 16 KiB ELF' \
		'make build-android-debug   Build an Android Debug APK (optional VERSION)' \
		'make build-android-release Build an Android Release APK (optional VERSION)' \
		'make build-ios-debug       Build an iOS Simulator Debug app (optional VERSION)' \
		'make build-ios-release     Build a signed iOS Release app (optional VERSION)' \
		'make build-macos-debug     Build macOS when a real target exists' \
		'make build-macos-release   Build macOS Release when a real target exists (optional VERSION)' \
		'make build-backend-release Build a backend release bundle (optional VERSION)' \
		'make release-check         Validate releases/$(RELEASE).yaml'

bootstrap:
	./scripts/bootstrap.sh

check:
	RELEASE_VERSION="$(CHECK_RELEASE)" ./scripts/check-local.sh

check-alpha:
	RELEASE_VERSION="$(RELEASE)" ./scripts/check-alpha.sh

check-sensitive-data:
	./scripts/check-sensitive-data.py

check-legacy-cleanup-plan:
	./scripts/check-legacy-cleanup-plan.py

check-migrator-retirement:
	./scripts/check-migrator-retirement.py

prepare-p8-performance:
	./scripts/p8-performance.py generate

test-p8-ios-device:
	./scripts/test-p8-ios-device.sh

check-p8-performance-record:
	./scripts/p8-performance.py validate $(if $(RECORD),--record "$(RECORD)",) --report artifacts/p8-performance/performance-results.md

test-backend:
	./scripts/test-backend.sh

test-kindle-core:
	node packages/kindle-core/build.mjs --check
	node --max-old-space-size=256 --test packages/kindle-core/test/core.test.mjs

test-apple-shared:
	swift test --package-path packages/apple-shared

test-ios:
	sh scripts/test-ios.sh $(IOS_TEST_ARGS)

test-ios-live-backend:
	sh scripts/test-ios-live-backend.sh

test-comic-ios-interop: test-backend
	sh scripts/start-document-interop-test.sh $(MAKE) test-ios IOS_TEST_ARGS=-only-testing:XLibReaderTests/DocumentInteropTests/testComicHTTPSRoundTripManifestConflictAndSessionDeletion

test-kindle-ios-interop: test-backend
	sh scripts/start-document-interop-test.sh $(MAKE) test-ios IOS_TEST_ARGS=-only-testing:XLibReaderTests/DocumentInteropTests/testKindleHTTPSRoundTripCanonicalConflictAndSessionDeletion

test-kindle-cross-client-interop: test-backend
	sh scripts/test-kindle-cross-client-interop.sh

test-comic-cross-client-interop: test-backend
	sh scripts/test-comic-cross-client-interop.sh

test-comic-native-security:
	bash scripts/build-comic-native.sh --security-test

test-comic-native-android:
	bash scripts/test-comic-native-android.sh

build-android-debug:
	@VERSION="$(VERSION)" ./scripts/build-android-debug.sh

build-android-release:
	@VERSION="$(VERSION)" ./scripts/build-android-release.sh

build-ios-debug:
	@VERSION="$(VERSION)" ./scripts/build-ios-debug.sh

build-ios-release:
	@VERSION="$(VERSION)" ./scripts/build-ios-release.sh

build-macos-debug:
	@VERSION="$(VERSION)" ./scripts/build-macos-debug.sh

build-macos-release:
	@VERSION="$(VERSION)" ./scripts/build-macos-release.sh

build-backend-release:
	@VERSION="$(VERSION)" ./scripts/build-backend-release.sh

prepare-release:
	./scripts/prepare-release.sh "$(RELEASE)"

release-check:
	./scripts/release-check.sh "$(RELEASE)"

test-backend-postgres:
	./scripts/test-backend-postgres.sh
