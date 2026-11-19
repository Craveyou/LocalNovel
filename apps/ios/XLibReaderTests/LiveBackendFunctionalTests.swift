import AppleShared
import Foundation
import XCTest
@testable import XLibReader

/// Explicitly opt-in public-API checks against an already deployed HTTPS server.
/// Never opens a server database, installs trust anchors, or uses existing identities.
@MainActor final class LiveBackendFunctionalTests: XCTestCase {
    @MainActor private final class Context {
        let address: String
        let api: SyncAPIClient
        let session = URLSession(configuration: .ephemeral)
        let email = "xlib-live-\(UUID().uuidString.lowercased())@example.com"
        var accounts: [SyncCredentials] = []
        var keys: Set<SyncBookKey> = []
        var coordinators: [ProgressSyncCoordinator] = []
        var localResources: [(URL, LocalDatabase)] = []

        init() throws {
            let env = ProcessInfo.processInfo.environment
            guard env["XLIB_LIVE_BACKEND_OPT_IN"] == "1" else {
                throw XCTSkip("Explicit deployed-server test opt-in required")
            }
            let address = try XCTUnwrap(env["XLIB_LIVE_BACKEND_URL"])
            let url = try XCTUnwrap(URL(string: address))
            guard url.scheme == "https", let host = url.host,
                  !["localhost", "127.0.0.1", "::1"].contains(host),
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                throw SyncAPIError.notConfigured
            }
            self.address = address
            api = .live(address: address, session: session)
        }

        func register(_ name: String, email: String? = nil, id: UUID = UUID()) async throws -> SyncCredentials {
            let value = try await api.startSync(.init(email: email ?? self.email, device: .init(
                deviceId: id, deviceName: name, platform: "ios", appVersion: "live-functional-test"))).credentials
            accounts.append(value)
            print("LIVE isolated identity: \(value.email), device: \(value.device.deviceId.uuidString.lowercased())")
            return value
        }

        func cleanup() async {
            for coordinator in coordinators { await coordinator.disableSync() }
            // Keep identity metadata (there is deliberately no account-delete API),
            // remove only this run's progress and revoke only this run's devices.
            for group in Dictionary(grouping: accounts, by: \.userID).values {
                guard let owner = group.first else { continue }
                let uniqueDevices = Dictionary(grouping: group, by: { $0.device.deviceId }).values.compactMap(\.last)
                for (index, key) in keys.enumerated() {
                    do {
                        // v1/v2 DELETE intentionally share single-book semantics.
                        // Split cleanup over our devices, below 10 deletes/device/min.
                        let authorization = uniqueDevices[index % uniqueDevices.count].authorization
                        try await api.deleteBookProgress(key, authorization)
                        let legacy = try await api.pullProgress(owner.authorization)
                        let typed = try await api.pullDocument(key, owner.authorization)
                        XCTAssertFalse(legacy.items.contains { $0.key == key }, "Live cleanup retained TXT progress")
                        XCTAssertTrue(typed.items.isEmpty, "Live cleanup retained document progress")
                    } catch { XCTFail("Live progress cleanup failed: \(error.localizedDescription)") }
                }
                let devices = (try? await api.listDevices(owner.authorization)) ?? []
                for device in devices where device.deviceId != owner.device.deviceId {
                    do { try await api.deleteDevice(device.deviceId, owner.authorization) }
                    catch { XCTFail("Live peer cleanup failed: \(error.localizedDescription)") }
                }
                do { try await api.deleteDevice(owner.device.deviceId, owner.authorization) }
                catch { XCTFail("Live owner cleanup failed: \(error.localizedDescription)") }
            }
            for (root, database) in localResources {
                database.closeForTesting()
                try? FileManager.default.removeItem(at: root)
            }
            session.invalidateAndCancel()
        }
    }

    private func run(_ body: (Context) async throws -> Void) async throws {
        continueAfterFailure = true // Ensure cleanup continues after a failed assertion.
        let context = try Context()
        do { try await body(context) }
        catch { await context.cleanup(); throw error }
        await context.cleanup()
    }

    private func wait(_ description: String, seconds: Int = 30, _ condition: () -> Bool) async throws {
        for _ in 0..<(seconds * 10) {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw DocumentError.unsupported("Live test timeout: \(description)")
    }

    private func rejects(_ statuses: [Int], _ operation: () async throws -> Void) async throws {
        do { try await operation(); XCTFail("Deployed API accepted a forbidden operation") }
        catch SyncAPIError.http(let status, _, _, _) { XCTAssertTrue(statuses.contains(status), "Unexpected HTTP \(status)") }
    }

    func testLiveIdentityDevicesTXTArbitrationIsolationAndDeletion() async throws {
        try await run { context in
            let api = context.api
            let healthy = try await api.health(); XCTAssertTrue(healthy)
            let owner = try await context.register("Live owner")
            let peer = try await context.register("Live peer")
            let outsider = try await context.register("Live isolated", email: "xlib-live-\(UUID().uuidString.lowercased())@example.com")
            XCTAssertTrue(owner.userID == peer.userID)
            XCTAssertTrue(owner.token == peer.token, "Same email did not recover the same token")
            XCTAssertTrue(owner.userID != outsider.userID)
            let devices = try await api.listDevices(owner.authorization)
            XCTAssertEqual(Set(devices.map(\.deviceId)), [owner.device.deviceId, peer.device.deviceId])
            let key = SyncBookKey(bookHash: String(repeating: "a", count: 64), fileSize: 1024)
            context.keys.insert(key)
            let time = FormalReadingProgress.milliseconds(.now) - 10_000
            func upload(_ offset: Int64, _ timestamp: Int64, _ credentials: SyncCredentials) async throws -> ProgressSyncResponse {
                try await api.syncProgress(.init(items: [.init(bookHash: key.bookHash, fileSize: key.fileSize,
                    offset: offset, readAtMs: timestamp)]), credentials.authorization)
            }
            let initial = try await upload(800, time, owner)
            XCTAssertEqual(initial.results.first?.decision, "accepted")
            let older = try await upload(900, time - 1, peer)
            XCTAssertEqual(older.results.first?.state.offset, 800)
            let backward = try await upload(200, time + 1, peer)
            XCTAssertEqual(backward.results.first?.state.offset, 200)
            XCTAssertEqual(backward.results.first?.state.device.deviceId, peer.device.deviceId)
            let unchanged = try await upload(200, time + 1, peer)
            XCTAssertEqual(unchanged.results.first?.decision, "unchanged")
            XCTAssertEqual(unchanged.results.first?.state.version, backward.results.first?.state.version)
            let other = try await api.pullProgress(outsider.authorization); XCTAssertTrue(other.items.isEmpty)
            let typed = try await api.pullDocument(key, owner.authorization); XCTAssertTrue(typed.items.isEmpty)
            try await self.rejects([422]) { _ = try await upload(1025, time + 2, owner) }
            try await self.rejects([401]) {
                _ = try await api.pullProgress(.init(token: "invalid-live-test-token", deviceID: owner.device.deviceId))
            }
            try await api.deleteDevice(peer.device.deviceId, owner.authorization) // Native DELETE with {}.
            let afterRemoval = try await api.listDevices(owner.authorization)
            // The public list includes revoked device history; authorization,
            // not physical absence from that list, proves successful revocation.
            XCTAssertTrue(afterRemoval.contains { $0.deviceId == peer.device.deviceId })
            XCTAssertNotNil(afterRemoval.first { $0.deviceId == peer.device.deviceId }?.revokedAtMs)
            try await self.rejects([403]) { _ = try await api.pullProgress(peer.authorization) }
            let resumed = try await context.register("Live peer renamed", id: peer.device.deviceId)
            XCTAssertTrue(resumed.userID == owner.userID)
            let retained = try await api.pullProgress(resumed.authorization)
            XCTAssertEqual(retained.items.first?.offset, 200)
            try await api.deleteBookProgress(key, owner.authorization)
            try await api.deleteBookProgress(key, owner.authorization)
            let deleted = try await api.pullProgress(owner.authorization); XCTAssertTrue(deleted.items.isEmpty)
            print("LIVE PASS identity/devices/revocation/recovery/TXT time arbitration/isolation/delete")
        }
    }

    func testLiveDeleteRateLimitReturns429RatherThanInternalError() async throws {
        try await run { context in
            let owner = try await context.register("Live limit boundary")
            let key = SyncBookKey(bookHash: String(repeating: "b", count: 64), fileSize: 1)
            // Eleven idempotent deletes of our own absent key, not a load test.
            // The declared limit is ten/minute; the next response must be 429.
            for _ in 0..<10 { try await context.api.deleteBookProgress(key, owner.authorization) }
            try await self.rejects([429]) { try await context.api.deleteBookProgress(key, owner.authorization) }
        }
    }

    func testLiveEveryDocumentFormatReaderAcceptUploadPreviewDeleteAndReopen() async throws {
        try await run { context in
            let owner = try await context.register("Live iOS reader")
            let peer = try await context.register("Live iOS peer")
            for (index, name) in ["text-rotated.pdf", "reflow.epub", "comic-basic.cbz", "comic-basic-rar4.cbr",
                         "comic-basic-rar5.cbr", "comic-basic-rar4-solid.cbr", "kindle-mobi6.mobi",
                         "kindle-palmdoc.azw", "kindle-huff.mobi", "kindle-kf8.azw3", "kindle-mixed.mobi", "kindle-long.mobi"].enumerated() {
                if index == 10 {
                    // These are user-flow tests, not the separate limit-boundary
                    // test: respect ten deletes/device/minute even on fast hosts.
                    print("LIVE respecting document deletion budget: waiting 60 seconds")
                    try await Task.sleep(for: .seconds(60))
                }
                let previousFailures = self.testRun?.failureCount ?? 0
                try await self.exerciseDocument(name, context: context, owner: owner, peer: peer)
                let outcome = (self.testRun?.failureCount ?? 0) == previousFailures ? "PASS" : "FAIL"
                print("LIVE \(outcome) reader/import/accept/upload/preview/bookmark/delete/pause/reopen: \(name)")
            }
            let legacy = try await context.api.pullProgress(owner.authorization); XCTAssertTrue(legacy.items.isEmpty)
        }
    }

    private func exerciseDocument(_ name: String, context: Context, owner: SyncCredentials, peer: SyncCredentials) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "LiveDocument-\(UUID())")
        let database = testDatabase(root: root), store = LibraryStore(root: root, database: database)
        context.localResources.append((root, database))
        try database.setSyncString(context.address, for: SyncServerConfiguration.storageKey)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "fixtures/documents"))
        let bytes = try Data(contentsOf: fixture), book = try await store.importBook(from: fixture)
        let key = try await store.documentIdentity(book: book); context.keys.insert(key)
        let sync = ProgressSyncCoordinator(api: context.api, vault: .init(load: { owner }, save: { _ in }, clear: {}),
            connectivity: SyncConnectivityMonitor(started: false), database: database)
        context.coordinators.append(sync)
        await sync.start()
        let model = DocumentReaderModel(book: book, store: store, sync: sync)
        defer { model.close() }
        await model.open(); XCTAssertNil(model.openFailure)
        let seed: DocumentLocator, target: DocumentLocator, local: DocumentLocator
        if let comic = model.comic {
            seed = try comic.manifest.locator(format: book.format, page: 10, y: 0.234567)
            target = try comic.manifest.locator(format: book.format, page: 11)
            local = try comic.manifest.locator(format: book.format, page: 12)
        } else if let reflow = model.reflowDocument {
            let chapter = reflow.chapters.count - 1
            seed = reflow.locator(chapter: chapter, offset: 3)
            target = reflow.locator(chapter: chapter, offset: 10)
            local = reflow.locator(chapter: chapter, offset: 15)
        } else {
            seed = .pdf(page: 1, pageCount: 2, y: 0.234567)
            target = .pdf(page: 0, pageCount: 2, y: 0.5)
            local = .pdf(page: 1, pageCount: 2, y: 0.6)
        }
        let seedTime = FormalReadingProgress.milliseconds(.now) - 10_000
        _ = try await context.api.syncDocument(.init(items: [.init(bookHash: key.bookHash, fileSize: key.fileSize,
            locator: seed, readAtMs: seedTime)]), peer.authorization)
        XCTAssertEqual(model.readAt.timeIntervalSince1970, 0)
        model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        try await wait("remote suggestion \(name)") { model.remote != nil }
        XCTAssertEqual(model.remote?.locator, seed)
        model.acceptRemote(); model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        try await wait("accepted \(name)") { model.formal == seed && model.remote == nil && !model.preparingSync }
        XCTAssertEqual(FormalReadingProgress.milliseconds(model.readAt), seedTime)
        let added = await model.addBookmark(); XCTAssertTrue(added)
        let bookmarks = model.bookmarks
        model.navigate(target, preview: true); model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        XCTAssertEqual(model.formal, seed); XCTAssertEqual(FormalReadingProgress.milliseconds(model.readAt), seedTime)
        let preview = try await context.api.pullDocument(key, peer.authorization)
        XCTAssertEqual(preview.items.first?.locator, seed)
        model.returnToFormal(); model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        model.navigate(target); model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        try await wait("uploaded \(name)") { model.formal == target && !model.preparingSync && model.syncMessage == "同步比较完成" }
        let uploaded = try await context.api.pullDocument(key, peer.authorization)
        let state = try XCTUnwrap(uploaded.items.first)
        XCTAssertEqual(state.locator, target); XCTAssertEqual(state.device.deviceId, owner.device.deviceId)
        XCTAssertGreaterThan(state.readAtMs, seedTime)
        if let kindle = model.kindle {
            for invalid in [DocumentLocator.kindle(textHash: String(repeating: "0", count: 64), textOffset: 0, textLength: kindle.canonicalText.utf16.count),
                            .kindle(textHash: kindle.textHash, textOffset: 0, textLength: kindle.canonicalText.utf16.count + 1)] {
                for timestamp in [seedTime - 1, state.readAtMs + 1] {
                    try await rejects([422]) {
                        _ = try await context.api.syncDocument(.init(items: [.init(bookHash: key.bookHash, fileSize: key.fileSize,
                            locator: invalid, readAtMs: timestamp)]), peer.authorization)
                    }
                }
            }
        }
        if let comic = model.comic {
            let invalid = DocumentLocator.comic(format: book.format, manifestHash: String(repeating: "0", count: 64),
                pageKey: comic.manifest.pages[11].pageKey, page: 11, pageCount: comic.manifest.pages.count, y: 0)
            try await rejects([422]) {
                _ = try await context.api.syncDocument(.init(items: [.init(bookHash: key.bookHash, fileSize: key.fileSize,
                    locator: invalid, readAtMs: state.readAtMs + 1)]), peer.authorization)
            }
        }
        let retained = try await context.api.pullDocument(key, peer.authorization); XCTAssertEqual(retained.items.first, state)
        await model.deleteCloud(); XCTAssertNil(model.error)
        let deleted = try await context.api.pullDocument(key, peer.authorization); XCTAssertTrue(deleted.items.isEmpty)
        model.navigate(local); model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        try await wait("local-only position \(name)") { model.formal == local && !model.preparingSync }
        await model.compare()
        let paused = try await context.api.pullDocument(key, peer.authorization); XCTAssertTrue(paused.items.isEmpty)
        XCTAssertEqual(model.bookmarks, bookmarks)
        model.close()
        let reopened = DocumentReaderModel(book: book, store: store, sync: sync)
        defer { reopened.close() }
        await reopened.open(); XCTAssertEqual(reopened.formal, local)
        reopened.rendererCompleted(try XCTUnwrap(reopened.command).id, success: true)
        try await wait("reopen uploads \(name)") { reopened.syncMessage == "同步比较完成" && !reopened.preparingSync }
        let restored = try await context.api.pullDocument(key, peer.authorization); XCTAssertEqual(restored.items.first?.locator, local)
        XCTAssertEqual(reopened.bookmarks, bookmarks)
        let copy = await store.url(for: book); XCTAssertEqual(try Data(contentsOf: copy), bytes)
        await sync.disableSync()
    }

    func testLiveConfigurationPersistenceTwentySecondTimerAndOfflineRecovery() async throws {
        try await run { context in
            let root = FileManager.default.temporaryDirectory.appending(path: "LiveTimer-\(UUID())")
            let database = testDatabase(root: root), store = LibraryStore(root: root, database: database)
            context.localResources.append((root, database))
            try database.setSyncString(context.address, for: SyncServerConfiguration.storageKey)
            let vault = LiveMemoryCredentials()
            let connectivity = SyncConnectivityMonitor(started: false)
            let sync = ProgressSyncCoordinator(vault: .init(load: { await vault.load() }, save: { await vault.save($0) }, clear: { await vault.clear() }),
                connectivity: connectivity, database: database) // Real defaults, including the 20-second interval.
            context.coordinators.append(sync)
            await sync.start()
            let savedEmail = await sync.saveConfiguredEmail(context.email); XCTAssertTrue(savedEmail)
            let savedName = await sync.saveDeviceName("Live timer iOS"); XCTAssertTrue(savedName)
            let started = await sync.syncRefresh(); XCTAssertTrue(started, sync.lastFailureMessage ?? "Start failed")
            let loadedCredentials = await vault.load()
            let credentials = try XCTUnwrap(loadedCredentials); context.accounts.append(credentials)
            let source = root.appending(path: "live-timer.txt")
            try Data(String(repeating: "这是线上同步测试正文😀。\n", count: 100).utf8).write(to: source)
            let book = try await store.importBook(from: source), file = await store.url(for: book)
            let key = try await store.documentIdentity(book: book); context.keys.insert(key)
            await sync.beginReading(book: book, fileURL: file)
            try await self.wait("initial TXT comparison") { !sync.isPreparingReading(bookID: book.id) }
            let readAt = Date()
            sync.recordLocalProgress(bookID: book.id, offset: 300, changedAt: readAt)
            let before = try await context.api.pullProgress(credentials.authorization)
            XCTAssertFalse(before.items.contains { $0.key == key })
            // Do not invoke syncRefresh or shorten the timer: wait for the real scheduled upload.
            try await Task.sleep(for: .seconds(23))
            let timed = try await context.api.pullProgress(credentials.authorization)
            XCTAssertEqual(timed.items.first(where: { $0.key == key })?.offset, 300)
            connectivity.setOnlineForTesting(false)
            try await self.wait("offline") { sync.availability == .offline }
            sync.recordLocalProgress(bookID: book.id, offset: 600, changedAt: .now)
            let offline = try await context.api.pullProgress(credentials.authorization)
            XCTAssertEqual(offline.items.first(where: { $0.key == key })?.offset, 300)
            connectivity.setOnlineForTesting(true)
            try await self.wait("online recovery") { sync.availability == .available && !sync.isPreparingReading(bookID: book.id) }
            try await Task.sleep(for: .seconds(2))
            let recovered = try await context.api.pullProgress(credentials.authorization)
            XCTAssertEqual(recovered.items.first(where: { $0.key == key })?.offset, 600)
            await sync.endReading(bookID: book.id)
            let renamed = await sync.saveDeviceName("Live timer renamed"); XCTAssertTrue(renamed)
            XCTAssertFalse(sync.isSyncEnabled); XCTAssertNil(sync.lastSuccessAt)
            XCTAssertEqual(database.syncString(for: SyncConfigurationSession.deviceNameKey), "Live timer renamed")
            try await Task.sleep(for: .seconds(23))
            XCTAssertTrue(sync.isSyncEnabled, sync.lastFailureMessage ?? "Timer did not restore credentials")
            XCTAssertEqual(sync.currentDeviceName, "Live timer renamed")
            let loadedRestored = await vault.load()
            let restored = try XCTUnwrap(loadedRestored); context.accounts.append(restored)
            let devices = try await context.api.listDevices(restored.authorization)
            XCTAssertEqual(devices.first(where: { $0.deviceId == restored.device.deviceId })?.deviceName, "Live timer renamed")
            let configuration = SyncConfigurationSession(database: database)
            XCTAssertEqual(configuration.configuredEmailValue, context.email)
            XCTAssertEqual(configuration.serverAddress, context.address)
            await sync.disableSync()
            print("LIVE PASS autosave/local configuration/real 20s upload/offline recovery/20s automatic re-registration")
        }
    }
}

private actor LiveMemoryCredentials {
    private var value: SyncCredentials?
    func load() -> SyncCredentials? { value }
    func save(_ value: SyncCredentials) { self.value = value }
    func clear() { value = nil }
}
