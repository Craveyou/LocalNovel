import AppleShared
import Foundation
import Security
import XCTest
@testable import XLibReader

/// Opt-in: native iOS transport and reader session against the disposable HTTPS/PostgreSQL harness.
@MainActor final class DocumentInteropTests:XCTestCase {
    private func waitUntil(_ condition:() -> Bool) async throws {
        for _ in 0..<100 {if condition(){return};try await Task.sleep(for:.milliseconds(100))}
        throw DocumentError.unsupported("Document interop operation timed out")
    }
    /// Native transport + real PostgreSQL; deliberately not called Android acceptance.
    func testKindleHTTPSRoundTripCanonicalConflictAndSessionDeletion() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["XLIB_DOC_INTEROP_URL"],let run = env["XLIB_DOC_INTEROP_RUN"],let cert = env["XLIB_DOC_INTEROP_CERT"],let certificate = Data(base64Encoded:cert) else {throw XCTSkip("Requires disposable HTTPS/PostgreSQL interop harness")}
        guard let url = URL(string:address),url.scheme == "https",url.host == "localhost" else {throw SyncAPIError.notConfigured}
        let session = URLSession(configuration:.ephemeral,delegate:LocalCertificate(certificate:certificate),delegateQueue:nil)
        defer {session.invalidateAndCancel()}
        let api = SyncAPIClient.live(address:address,session:session),email = run+"-kindle@example.com"
        let credentials = try await api.startSync(.init(email:email,device:.init(deviceId:UUID(),deviceName:"iOS Kindle",platform:"ios",appVersion:"test"))).credentials
        let peer = try await api.startSync(.init(email:email,device:.init(deviceId:UUID(),deviceName:"iOS peer",platform:"ios",appVersion:"test"))).credentials
        for name in ["kindle-mobi6.mobi","kindle-palmdoc.azw","kindle-huff.mobi","kindle-kf8.azw3","kindle-mixed.mobi","kindle-long.mobi"] {
            let root = FileManager.default.temporaryDirectory.appending(path:"KindleInterop-\(UUID())")
            let database = testDatabase(root:root),store = LibraryStore(root:root,database:database)
            defer {database.closeForTesting();try? FileManager.default.removeItem(at:root)}
            try database.setSyncString(address,for:SyncServerConfiguration.storageKey)
            let fixture = try XCTUnwrap(Bundle(for:Self.self).url(forResource:name,withExtension:nil,subdirectory:"fixtures/documents"))
            let book = try await store.importBook(from:fixture),key = try await store.documentIdentity(book:book)
            let document = try KindleDocument(url:fixture),unit = document.chapters.count-1
            let seed = document.locator(chapter:unit,offset:3),target = document.locator(chapter:unit,offset:10)
            let seedTime = FormalReadingProgress.milliseconds(.now)-10_000
            _ = try await api.syncDocument(.init(items:[.init(bookHash:key.bookHash,fileSize:key.fileSize,locator:seed,readAtMs:seedTime)]),peer.authorization)
            let sync = ProgressSyncCoordinator(api:api,vault:.init(load:{credentials},save:{_ in},clear:{}),stateStore:SyncStateStore(database:database),connectivity:SyncConnectivityMonitor(started:false),database:database)
            await sync.start()
            let model = DocumentReaderModel(book:book,store:store,sync:sync);defer {model.close()}
            await model.open();XCTAssertEqual(model.readAt.timeIntervalSince1970,0)
            model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
            try await waitUntil {model.remote != nil}
            XCTAssertEqual(model.remote?.locator,seed,name)
            model.acceptRemote();model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
            try await waitUntil {model.remote == nil && !model.preparingSync && model.formal == seed}
            XCTAssertEqual(FormalReadingProgress.milliseconds(model.readAt),seedTime)
            model.navigate(target);model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
            try await waitUntil {model.formal == target && !model.preparingSync && model.syncMessage == "同步比较完成"}
            let uploaded = try await api.pullDocument(key,peer.authorization)
            XCTAssertEqual(uploaded.items.first?.locator,target,name)
            XCTAssertEqual(uploaded.items.first?.progress ?? -1,target.progress,accuracy:1e-12)
            XCTAssertEqual(uploaded.items.first?.device.deviceName,"iOS Kindle")
            for time in [seedTime-1,FormalReadingProgress.milliseconds(model.readAt)+1] {
                let invalid = DocumentLocator.kindle(textHash:String(repeating:"0",count:64),textOffset:0,textLength:document.canonicalText.utf16.count)
                do {
                    _ = try await api.syncDocument(.init(items:[.init(bookHash:key.bookHash,fileSize:key.fileSize,locator:invalid,readAtMs:time)]),peer.authorization)
                    XCTFail("Canonical mismatch accepted",file:#filePath,line:#line)
                } catch SyncAPIError.http(let status,let code,_,_) {XCTAssertEqual(status,422);XCTAssertEqual(code,"VALIDATION_FAILED")}
            }
            await model.deleteCloud();XCTAssertNil(model.error)
            let deleted = try await api.pullDocument(key,peer.authorization);XCTAssertTrue(deleted.items.isEmpty)
            let local = document.locator(chapter:unit,offset:15)
            model.navigate(local);model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
            try await waitUntil {model.formal == local && !model.preparingSync}
            await model.compare()
            let paused = try await api.pullDocument(key,peer.authorization);XCTAssertTrue(paused.items.isEmpty)
            model.close()
            let reopened = DocumentReaderModel(book:book,store:store,sync:sync);defer {reopened.close()}
            await reopened.open();XCTAssertEqual(reopened.formal,local)
            reopened.rendererCompleted(try XCTUnwrap(reopened.command).id,success:true)
            try await waitUntil {reopened.syncMessage == "同步比较完成"}
            let restored = try await api.pullDocument(key,peer.authorization);XCTAssertEqual(restored.items.first?.locator,local)
        }
        let legacy = try await api.pullProgress(credentials.authorization);XCTAssertTrue(legacy.items.isEmpty)
    }
    /// Native iOS phases of a real Android/iOS continuation, not host HTTP impersonation.
    func testKindleAndroidIOSStagedHandoff() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["XLIB_DOC_INTEROP_URL"],let run = env["XLIB_DOC_INTEROP_RUN"],
              let cert = env["XLIB_DOC_INTEROP_CERT"],let certificate = Data(base64Encoded:cert),
              let stage = env["XLIB_KINDLE_INTEROP_STAGE"] else {
            throw XCTSkip("Requires staged Android/iOS Kindle HTTPS/PostgreSQL harness")
        }
        guard ["accept-android","accept-android-delete"].contains(stage),
              let url = URL(string:address),url.scheme == "https",url.host == "localhost" else {
            throw SyncAPIError.notConfigured
        }
        let session = URLSession(configuration:.ephemeral,delegate:LocalCertificate(certificate:certificate),delegateQueue:nil)
        defer {session.invalidateAndCancel()}
        let api = SyncAPIClient.live(address:address,session:session)
        let credentials = try await api.startSync(.init(email:run+"-cross-kindle@example.com",device:.init(
            deviceId:try XCTUnwrap(UUID(uuidString:"584c4942-0141-4000-8000-000000000012")),
            deviceName:"iOS cross Kindle",platform:"ios",
            appVersion:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"))).credentials
        for name in ["kindle-mobi6.mobi","kindle-palmdoc.azw","kindle-huff.mobi","kindle-kf8.azw3","kindle-mixed.mobi","kindle-long.mobi"] {
            try await exerciseKindleHandoff(name:name,stage:stage,address:address,credentials:credentials,api:api)
        }
        let legacy = try await api.pullProgress(credentials.authorization)
        XCTAssertTrue(legacy.items.isEmpty)
    }
    private func exerciseKindleHandoff(name:String,stage:String,address:String,
                                        credentials:SyncCredentials,api:SyncAPIClient) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path:"KindleCrossInterop-\(UUID())")
        let database = testDatabase(root:root),store = LibraryStore(root:root,database:database)
        defer {database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        try database.setSyncString(address,for:SyncServerConfiguration.storageKey)
        let fixture = try XCTUnwrap(Bundle(for:Self.self).url(forResource:name,withExtension:nil,subdirectory:"fixtures/documents"))
        let original = try Data(contentsOf:fixture)
        let book = try await store.importBook(from:fixture),key = try await store.documentIdentity(book:book)
        let document = try KindleDocument(url:fixture),unit = document.chapters.count-1
        let expected = document.locator(chapter:unit,offset:stage == "accept-android" ? 3 : 1)
        let incoming = try await api.pullDocument(key,credentials.authorization)
        let android = try XCTUnwrap(incoming.items.first)
        XCTAssertEqual(incoming.items.count,1);XCTAssertEqual(android.device.platform,"android")
        XCTAssertEqual(android.locator,expected,name);XCTAssertGreaterThan(android.readAtMs,0)
        let sync = ProgressSyncCoordinator(api:api,vault:.init(load:{credentials},save:{_ in},clear:{}),stateStore:SyncStateStore(database:database),connectivity:SyncConnectivityMonitor(started:false),database:database)
        await sync.start()
        let model = DocumentReaderModel(book:book,store:store,sync:sync);defer {model.close()}
        await model.open();XCTAssertEqual(model.readAt.timeIntervalSince1970,0)
        model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
        try await waitUntil {model.remote != nil}
        XCTAssertEqual(model.remote,android)
        model.acceptRemote();model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
        try await waitUntil {model.remote == nil && !model.preparingSync && model.formal == expected}
        XCTAssertEqual(FormalReadingProgress.milliseconds(model.readAt),android.readAtMs)
        let accepted = try await api.pullDocument(key,credentials.authorization)
        XCTAssertEqual(accepted.items.first,android) // Accepting is not a new reading event.
        let bookmarkAdded = await model.addBookmark();XCTAssertTrue(bookmarkAdded)
        let bookmarks = model.bookmarks
        if stage == "accept-android" {
            let target = document.locator(chapter:unit,offset:10)
            model.navigate(target);model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
            try await waitUntil {model.formal == target && !model.preparingSync && model.syncMessage == "同步比较完成"}
            let response = try await api.pullDocument(key,credentials.authorization)
            let uploaded = try XCTUnwrap(response.items.first)
            XCTAssertEqual(uploaded.locator,target);XCTAssertEqual(uploaded.device.platform,"ios")
            XCTAssertEqual(uploaded.device.deviceId,credentials.device.deviceId)
            XCTAssertGreaterThan(uploaded.readAtMs,android.readAtMs)
            let incompatible:[DocumentLocator] = [
                .kindle(textHash:String(repeating:"0",count:64),textOffset:0,textLength:document.canonicalText.utf16.count),
                .kindle(textHash:document.textHash,textOffset:0,textLength:document.canonicalText.utf16.count+1)
            ]
            for locator in incompatible {
                for timestamp in [android.readAtMs-1,uploaded.readAtMs+1] {
                    do {
                        _ = try await api.syncDocument(.init(items:[.init(bookHash:key.bookHash,fileSize:key.fileSize,locator:locator,readAtMs:timestamp)]),credentials.authorization)
                        XCTFail("Foreign canonical identity must fail before time arbitration")
                    } catch SyncAPIError.http(let status,let code,_,_) {
                        XCTAssertEqual(status,422);XCTAssertEqual(code,"VALIDATION_FAILED")
                    }
                }
            }
            let retained = try await api.pullDocument(key,credentials.authorization)
            XCTAssertEqual(retained.items.first,uploaded)
        } else {
            await model.deleteCloud();XCTAssertNil(model.error)
            let deleted = try await api.pullDocument(key,credentials.authorization);XCTAssertTrue(deleted.items.isEmpty)
            XCTAssertEqual(model.formal,expected)
            let localOnly = document.locator(chapter:unit,offset:15)
            model.navigate(localOnly);model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
            try await waitUntil {model.formal == localOnly && !model.preparingSync}
            await model.compare()
            let stillDeleted = try await api.pullDocument(key,credentials.authorization);XCTAssertTrue(stillDeleted.items.isEmpty)
            let saved = try await store.documentPosition(bookID:book.id)
            XCTAssertEqual(saved?.locator,localOnly)
            XCTAssertGreaterThan(FormalReadingProgress.milliseconds(model.readAt),android.readAtMs)
        }
        XCTAssertEqual(model.bookmarks,bookmarks)
        let copy = await store.url(for:book)
        XCTAssertEqual(try Data(contentsOf:copy),original)
    }
    /// Runs between Android instrumentation phases; never seeds an Android
    /// identity with host HTTP calls or substitutes a second iOS session.
    func testComicAndroidIOSStagedHandoff() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["XLIB_DOC_INTEROP_URL"], let run = env["XLIB_DOC_INTEROP_RUN"],
              let cert = env["XLIB_DOC_INTEROP_CERT"], let certificate = Data(base64Encoded: cert),
              let stage = env["XLIB_COMIC_INTEROP_STAGE"] else {
            throw XCTSkip("Requires staged Android/iOS HTTPS/PostgreSQL harness")
        }
        guard ["accept-android", "accept-android-delete"].contains(stage),
              let url = URL(string: address), url.scheme == "https", url.host == "localhost" else {
            throw SyncAPIError.notConfigured
        }
        let session = URLSession(configuration: .ephemeral, delegate: LocalCertificate(certificate: certificate), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let api = SyncAPIClient.live(address: address, session: session)
        // Stable across the two phases, but scoped to a fresh disposable account.
        let credentials = try await api.startSync(.init(email: run + "-cross-comic@example.com", device: .init(
            deviceId: try XCTUnwrap(UUID(uuidString: "584c4942-0141-4000-8000-000000000002")),
            deviceName: "iOS cross comic", platform: "ios",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"))).credentials
        for name in ["comic-basic.cbz", "comic-basic-rar4.cbr", "comic-basic-rar5.cbr", "comic-basic-rar4-solid.cbr"] {
            try await exerciseComicHandoff(name: name, stage: stage, address: address, credentials: credentials, api: api)
        }
        let legacy = try await api.pullProgress(credentials.authorization)
        XCTAssertTrue(legacy.items.isEmpty)
    }
    private func exerciseComicHandoff(name: String, stage: String, address: String,
                                      credentials: SyncCredentials, api: SyncAPIClient) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ComicCrossInterop-" + UUID().uuidString)
        let database = testDatabase(root: root)
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        try database.setSyncString(address, for: SyncServerConfiguration.storageKey)
        let store = LibraryStore(root: root, database: database)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "fixtures/documents"))
        let book = try await store.importBook(from: fixture)
        let key = try await store.documentIdentity(book: book)
        let manifest = try ComicDocument(url: fixture).manifest
        let expected = try manifest.locator(format: book.format, page: 10, y: stage == "accept-android" ? 0.234567 : 0.500001)
        let incoming = try await api.pullDocument(key, credentials.authorization)
        let android = try XCTUnwrap(incoming.items.first)
        XCTAssertEqual(incoming.items.count, 1)
        XCTAssertEqual(android.device.platform, "android")
        XCTAssertEqual(android.locator, expected)
        XCTAssertGreaterThan(android.readAtMs, 0)
        let sync = ProgressSyncCoordinator(api: api, vault: .init(load: { credentials }, save: { _ in }, clear: {}),
            stateStore: SyncStateStore(database: database), connectivity: SyncConnectivityMonitor(started: false), database: database)
        await sync.start()
        let model = DocumentReaderModel(book: book, store: store, sync: sync)
        defer { model.close() }
        await model.open()
        XCTAssertEqual(model.readAt.timeIntervalSince1970, 0)
        model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        try await waitUntil { model.remote != nil }
        XCTAssertEqual(model.remote, android)
        model.acceptRemote()
        model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        try await waitUntil { model.remote == nil && !model.preparingSync && model.formal == expected }
        XCTAssertEqual(FormalReadingProgress.milliseconds(model.readAt), android.readAtMs)
        let accepted = try await api.pullDocument(key, credentials.authorization)
        XCTAssertEqual(accepted.items.first, android) // Accepting never manufactures an iOS reading event.
        if stage == "accept-android" {
            let target = try manifest.locator(format: book.format, page: 11)
            model.navigate(target)
            model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
            try await waitUntil { model.formal == target && !model.preparingSync && model.syncMessage == "同步比较完成" }
            let response = try await api.pullDocument(key, credentials.authorization)
            let uploaded = try XCTUnwrap(response.items.first)
            XCTAssertEqual(uploaded.locator, target)
            XCTAssertEqual(uploaded.device.platform, "ios")
            XCTAssertEqual(uploaded.device.deviceId, credentials.device.deviceId)
            XCTAssertEqual(uploaded.progress, 0.5)
            XCTAssertGreaterThan(uploaded.readAtMs, android.readAtMs)
            // Conflict must precede time arbitration in both directions.
            let incompatible = DocumentLocator.comic(format: book.format, manifestHash: String(repeating: "0", count: 64),
                pageKey: manifest.pages[11].pageKey, page: 11, pageCount: 24, y: 0)
            for timestamp in [android.readAtMs - 1, uploaded.readAtMs + 1] {
                do {
                    _ = try await api.syncDocument(.init(items: [.init(bookHash: key.bookHash, fileSize: key.fileSize,
                        locator: incompatible, readAtMs: timestamp)]), credentials.authorization)
                    XCTFail("Foreign comic manifest must fail before time arbitration")
                } catch SyncAPIError.http(let status, let code, _, _) {
                    XCTAssertEqual(status, 422); XCTAssertEqual(code, "VALIDATION_FAILED")
                }
            }
            let retained = try await api.pullDocument(key, credentials.authorization)
            XCTAssertEqual(retained.items.first, uploaded)
        } else {
            await model.deleteCloud()
            XCTAssertNil(model.error)
            let deleted = try await api.pullDocument(key, credentials.authorization)
            XCTAssertTrue(deleted.items.isEmpty)
            XCTAssertEqual(model.formal, expected)
            let localOnly = try manifest.locator(format: book.format, page: 12)
            model.navigate(localOnly)
            model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
            try await waitUntil { model.formal == localOnly && !model.preparingSync }
            await model.compare()
            let stillDeleted = try await api.pullDocument(key, credentials.authorization)
            XCTAssertTrue(stillDeleted.items.isEmpty)
            let saved = try await store.documentPosition(bookID: book.id)
            XCTAssertEqual(saved?.locator, localOnly)
            XCTAssertGreaterThan(FormalReadingProgress.milliseconds(model.readAt), android.readAtMs)
        }
    }
    /// Two independent iOS sessions against the real service; not Android-client acceptance.
    func testComicHTTPSRoundTripManifestConflictAndSessionDeletion() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["XLIB_DOC_INTEROP_URL"], let run = env["XLIB_DOC_INTEROP_RUN"],
              let cert = env["XLIB_DOC_INTEROP_CERT"], let certificate = Data(base64Encoded: cert) else {
            throw XCTSkip("Requires disposable HTTPS/PostgreSQL interop harness")
        }
        guard let url = URL(string: address), url.scheme == "https", url.host == "localhost" else { throw SyncAPIError.notConfigured }
        let session = URLSession(configuration: .ephemeral, delegate: LocalCertificate(certificate: certificate), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let api = SyncAPIClient.live(address: address, session: session)
        let email = run + "-comic@example.com"
        let credentials = try await api.startSync(.init(email: email, device: .init(deviceId: UUID(), deviceName: "iOS comic reader", platform: "ios", appVersion: "0.14.1"))).credentials
        let peer = try await api.startSync(.init(email: email, device: .init(deviceId: UUID(), deviceName: "iOS comic peer", platform: "ios", appVersion: "0.14.1"))).credentials
        for name in ["comic-basic.cbz", "comic-basic-rar4.cbr", "comic-basic-rar5.cbr", "comic-basic-rar4-solid.cbr"] {
            try await exerciseComic(name: name, address: address, credentials: credentials, peer: peer, api: api)
        }
    }
    private func exerciseComic(name: String, address: String, credentials: SyncCredentials, peer: SyncCredentials, api: SyncAPIClient) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ComicInterop-" + UUID().uuidString)
        let database = testDatabase(root: root)
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        try database.setSyncString(address, for: SyncServerConfiguration.storageKey)
        let store = LibraryStore(root: root, database: database)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "fixtures/documents"))
        let book = try await store.importBook(from: fixture)
        let key = try await store.documentIdentity(book: book)
        let manifest = try ComicDocument(url: fixture).manifest
        let seed = try manifest.locator(format: book.format, page: 10, y: 0.234567)
        let seedTime = FormalReadingProgress.milliseconds(Date()) - 10_000
        _ = try await api.syncDocument(.init(items: [.init(bookHash: key.bookHash, fileSize: key.fileSize, locator: seed, readAtMs: seedTime)]), peer.authorization)
        let sync = ProgressSyncCoordinator(api: api, vault: .init(load: { credentials }, save: { _ in }, clear: {}),
            stateStore: SyncStateStore(database: database), connectivity: SyncConnectivityMonitor(started: false), database: database)
        await sync.start()
        let model = DocumentReaderModel(book: book, store: store, sync: sync)
        await model.open()
        defer { model.close() }
        // Opening/restoring has no reading timestamp and cannot upload over the seed.
        XCTAssertEqual(model.readAt.timeIntervalSince1970, 0)
        let beforeRender = try await api.pullDocument(key, credentials.authorization)
        XCTAssertEqual(beforeRender.items.first?.readAtMs, seedTime)
        model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        try await waitUntil { model.remote != nil }
        XCTAssertEqual(model.remote?.locator, seed)
        model.acceptRemote()
        model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        try await waitUntil { model.remote == nil && !model.preparingSync && model.formal == seed }
        XCTAssertEqual(FormalReadingProgress.milliseconds(model.readAt), seedTime)
        let target = try manifest.locator(format: book.format, page: 11)
        model.navigate(target)
        model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        try await waitUntil { model.formal == target && !model.preparingSync && model.syncMessage == "同步比较完成" }
        let uploaded = try await api.pullDocument(key, peer.authorization)
        XCTAssertEqual(uploaded.items.first?.locator, target)
        XCTAssertEqual(uploaded.items.first?.device.deviceName, "iOS comic reader")
        XCTAssertEqual(uploaded.items.first?.progress, 0.5)
        // The service must reject a newer incompatible manifest without replacing the row.
        let page = manifest.pages[11]
        let incompatible = DocumentLocator.comic(format: book.format, manifestHash: String(repeating: "0", count: 64),
            pageKey: page.pageKey, page: 11, pageCount: 24, y: 0)
        do {
            _ = try await api.syncDocument(.init(items: [.init(bookHash: key.bookHash, fileSize: key.fileSize,
                locator: incompatible, readAtMs: FormalReadingProgress.milliseconds(Date()))]), peer.authorization)
            XCTFail("Incompatible comic manifests must be rejected")
        } catch SyncAPIError.http(let status, let code, _, _) {
            XCTAssertEqual(status, 422); XCTAssertEqual(code, "VALIDATION_FAILED")
        }
        let retained = try await api.pullDocument(key, peer.authorization)
        XCTAssertEqual(retained.items.first?.locator, target)
        await model.deleteCloud()
        XCTAssertNil(model.error)
        let deleted = try await api.pullDocument(key, peer.authorization)
        XCTAssertTrue(deleted.items.isEmpty)
        let afterDelete = try manifest.locator(format: book.format, page: 12)
        model.navigate(afterDelete)
        model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        try await waitUntil { model.formal == afterDelete && !model.preparingSync }
        await model.compare()
        let stillDeleted = try await api.pullDocument(key, peer.authorization)
        XCTAssertTrue(stillDeleted.items.isEmpty)
        model.close()
        let reopened = DocumentReaderModel(book: book, store: store, sync: sync)
        await reopened.open()
        defer { reopened.close() }
        reopened.rendererCompleted(try XCTUnwrap(reopened.command).id, success: true)
        try await waitUntil { reopened.syncMessage == "同步比较完成" }
        let restored = try await api.pullDocument(key, peer.authorization)
        XCTAssertEqual(restored.items.first?.locator, afterDelete)
        let legacy = try await api.pullProgress(credentials.authorization)
        XCTAssertTrue(legacy.items.isEmpty)
    }
    func testAndroidIOSRoundTripAndSessionDeletion() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["XLIB_DOC_INTEROP_URL"],let run = env["XLIB_DOC_INTEROP_RUN"],let cert = env["XLIB_DOC_INTEROP_CERT"],let certificate = Data(base64Encoded:cert) else {throw XCTSkip("Requires disposable HTTPS/PostgreSQL interop harness")}
        guard let url = URL(string:address),url.scheme == "https",url.host == "localhost" else {throw SyncAPIError.notConfigured}
        let phase = env["XLIB_DOC_INTEROP_PHASE"] ?? "1"
        let session = URLSession(configuration:.ephemeral,delegate:LocalCertificate(certificate:certificate),delegateQueue:nil)
        defer {session.invalidateAndCancel()}
        let api = SyncAPIClient.live(address:address,session:session)
        let root = FileManager.default.temporaryDirectory.appending(path:"DocInterop-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let database = testDatabase(root:root)
        try database.setSyncString(address,for:SyncServerConfiguration.storageKey)
        let credentials = try await api.startSync(.init(email:run+"@example.com",device:.init(deviceId:UUID(),deviceName:"iOS interoperability",platform:"ios",appVersion:"0.12.0"))).credentials
        let store = LibraryStore(root:root,database:database)
        let sync = ProgressSyncCoordinator(api:api,vault:.init(load:{credentials},save:{_ in},clear:{}),stateStore:SyncStateStore(database:database),connectivity:SyncConnectivityMonitor(started:false),database:database)
        await sync.start()
        for name in ["text-rotated.pdf","reflow.epub"] {
            let fixture = try XCTUnwrap(Bundle(for:Self.self).url(forResource:name,withExtension:nil,subdirectory:"fixtures/documents"))
            let book = try await store.importBook(from:fixture)
            let key = try await store.documentIdentity(book:book)
            let model = DocumentReaderModel(book:book,store:store,sync:sync);await model.open()
            let initial = try XCTUnwrap(model.command);model.rendererCompleted(initial.id,success:true)
            try await waitUntil{model.remote != nil}
            let received = try XCTUnwrap(model.remote)
            XCTAssertEqual(received.device.platform,"android")
            let expected:DocumentLocator
            if book.format == "pdf" {expected = .pdf(page:1,pageCount:2,y:phase == "1" ? 0.123457 : 0)}
            else {expected = try XCTUnwrap(model.epub).locator(chapter:0,offset:8)}
            XCTAssertEqual(received.locator,expected)
            model.acceptRemote();model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
            try await waitUntil{model.remote == nil && !model.preparingSync}
            XCTAssertEqual(model.formal,expected);XCTAssertEqual(FormalReadingProgress.milliseconds(model.readAt),received.readAtMs)
            let target:DocumentLocator = book.format == "pdf" ? .pdf(page:0,pageCount:2,y:0.5) : try XCTUnwrap(model.epub).locator(chapter:1,offset:3)
            if phase == "1" {
                model.navigate(target);model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
                try await waitUntil{model.formal == target && !model.preparingSync}
                let state = try await api.pullDocument(key,credentials.authorization)
                XCTAssertEqual(state.items.first?.locator,target);XCTAssertEqual(state.items.first?.device.platform,"ios")
                XCTAssertGreaterThan(FormalReadingProgress.milliseconds(model.readAt),received.readAtMs)
            } else {
                let before = model.formal
                await model.deleteCloud()
                let deleted = try await api.pullDocument(key,credentials.authorization);XCTAssertTrue(deleted.items.isEmpty)
                XCTAssertEqual(model.formal,before)
                model.navigate(target);model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
                try await waitUntil{model.formal == target && !model.preparingSync}
                await model.compare()
                let remainsDeleted = try await api.pullDocument(key,credentials.authorization);XCTAssertTrue(remainsDeleted.items.isEmpty)
                model.close()
                let books = try await store.load();let updated = try XCTUnwrap(books.first(where:{$0.id == book.id}))
                let reopened = DocumentReaderModel(book:updated,store:store,sync:sync);await reopened.open()
                reopened.rendererCompleted(try XCTUnwrap(reopened.command).id,success:true)
                try await waitUntil{reopened.syncMessage == "同步比较完成"}
                let restored = try await api.pullDocument(key,credentials.authorization);XCTAssertEqual(restored.items.first?.locator,target)
                reopened.close()
            }
            model.close()
        }
        let old = try await api.pullProgress(credentials.authorization);XCTAssertTrue(old.items.isEmpty)
    }
}
private final class LocalCertificate:NSObject,URLSessionDelegate,@unchecked Sendable {
    let certificate:Data
    init(certificate:Data){self.certificate = certificate}
    func urlSession(_ session:URLSession,didReceive challenge:URLAuthenticationChallenge,completionHandler:@escaping (URLSession.AuthChallengeDisposition,URLCredential?)->Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {completionHandler(.performDefaultHandling,nil);return}
        guard challenge.protectionSpace.host == "localhost",let trust = challenge.protectionSpace.serverTrust,
              let anchor = SecCertificateCreateWithData(nil,certificate as CFData) else {XCTFail("Missing temporary localhost trust");completionHandler(.cancelAuthenticationChallenge,nil);return}
        SecTrustSetAnchorCertificates(trust,[anchor] as CFArray);SecTrustSetAnchorCertificatesOnly(trust,true)
        var trustError:CFError?
        guard SecTrustEvaluateWithError(trust,&trustError),
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              SecCertificateCopyData(leaf) as Data == certificate else {XCTFail("Temporary localhost certificate failed: \(String(describing:trustError))");completionHandler(.cancelAuthenticationChallenge,nil);return}
        completionHandler(.useCredential,URLCredential(trust:trust))
    }
}
