import CryptoKit
import XCTest

/// Real settings and reading UI, with normal HTTPS transport and isolated data.
@MainActor final class LiveBackendUITests: XCTestCase {
    private func launch(_ backend: LiveUIBackend) throws -> XCUIApplication {
        let app = XCUIApplication()
        let testID = UUID().uuidString
        app.launchEnvironment["XLIB_UI_TEST_ID"] = testID
        print("LIVE UI isolated container: \(testID), test identity: \(backend.email)")
        app.launchEnvironment["XLIB_UI_TEST_SCENARIO"] = "kindle"
        app.launchEnvironment["XLIB_LIVE_BACKEND_OPT_IN"] = "1"
        app.launchEnvironment["XLIB_LIVE_BACKEND_URL"] = backend.address
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "kindle-long.mobi", withExtension: nil, subdirectory: "fixtures/documents"))
        let bytes = try Data(contentsOf: fixture)
        backend.bookHash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        backend.fileSize = bytes.count
        app.launchEnvironment["XLIB_UI_KINDLE"] = bytes.base64EncodedString()
        app.launch()
        XCTAssertTrue(app.staticTexts["我的书架"].waitForExistence(timeout: 15))
        return app
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func replace(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 100))
        field.typeText(value)
    }

    private func back(_ app: XCUIApplication) {
        let back = app.buttons["返回"]
        XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
    }

    private func configure(_ app: XCUIApplication, backend: LiveUIBackend) {
        app.buttons["常规设置"].tap(); app.buttons["settings.progressSync"].tap()
        let action = app.buttons["sync.startStop"]
        XCTAssertTrue(action.waitForExistence(timeout: 5)); action.tap()
        XCTAssertTrue(app.staticTexts["sync.statusError"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["sync.statusError"].label.contains("请先完成同步配置"))
        app.buttons["sync.emailSettings"].tap()
        replace(app.textFields["sync.emailField"], with: backend.email)
        XCTAssertFalse(app.buttons["sync.emailSave"].exists); back(app)
        let email = app.buttons["sync.emailSettings"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", backend.email), object: email)], timeout: 8), .completed)
        app.buttons["sync.deviceNameSettings"].tap()
        replace(app.textFields["sync.deviceNameField"], with: "Live UI iOS")
        XCTAssertFalse(app.buttons["sync.deviceNameSave"].exists); back(app)
        app.buttons["sync.serverAddress"].tap()
        XCTAssertEqual(app.textFields["sync.serverAddressField"].value as? String, backend.address)
        XCTAssertFalse(app.buttons["sync.serverAddressSave"].exists); back(app)
        action.tap()
        XCTAssertTrue(app.staticTexts["已连接"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["sync.statusError"].exists)
    }

    func testLiveSettingsAutosaveTwentySecondReconnectAndRemoveDevice() async throws {
        continueAfterFailure = true
        let backend = try LiveUIBackend()
        try await backend.start()
        let app = try launch(backend)
        addTeardownBlock { @MainActor in app.terminate(); await backend.cleanup() }
        configure(app, backend: backend)
        capture("live-settings-connected", app)
        app.buttons["sync.deviceNameSettings"].tap()
        replace(app.textFields["sync.deviceNameField"], with: "Live UI renamed")
        back(app)
        XCTAssertTrue(app.staticTexts["未同步"].waitForExistence(timeout: 5))
        // No refresh tap: exercise the production interval while staying in Settings.
        XCTAssertTrue(app.staticTexts["已连接"].waitForExistence(timeout: 30))
        let devices = try await backend.request("GET", "v1/devices")["items"] as? [[String: Any]] ?? []
        XCTAssertTrue(devices.contains { $0["deviceName"] as? String == "Live UI renamed" })
        app.buttons["sync.devices"].tap()
        let remove = app.buttons["sync.removeDevice.\(backend.deviceID.uuidString.lowercased())"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10)); remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 15))
        capture("live-device-removed", app)
        back(app); app.buttons["sync.devices"].tap()
        XCTAssertTrue(app.staticTexts["同步设备"].waitForExistence(timeout: 5))
        // A revoked historical record must not reappear as an active removable device.
        XCTAssertTrue(remove.waitForNonExistence(timeout: 10))
        let status = try await backend.statusAfterRevocation()
        XCTAssertEqual(status, 403)
        // Reactivate only our verifier, so teardown can remove this run's data/devices.
        try await backend.start()
    }

    func testLiveKindleUIUploadSearchPreviewBookmarkCloudDeleteAndReopen() async throws {
        continueAfterFailure = true
        let backend = try LiveUIBackend()
        try await backend.start()
        let app = try launch(backend)
        addTeardownBlock { @MainActor in app.terminate(); await backend.cleanup() }
        configure(app, backend: backend)
        back(app); back(app)
        let book = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Kindle验收")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10)); book.tap()
        let web = app.webViews["document.content.ready"]
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        let next = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
        next.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "第 2 章"), object: web)], timeout: 15), .completed)
        let state = try await backend.waitForProgress()
        XCTAssertEqual((state["locator"] as? [String: Any])?["format"] as? String, "kindle")
        XCTAssertEqual((state["device"] as? [String: Any])?["deviceName"] as? String, "Live UI iOS")
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45))
        middle.tap()
        XCTAssertTrue(app.buttons["添加书签"].waitForExistence(timeout: 5)); app.buttons["添加书签"].tap()
        app.buttons["搜索"].tap()
        let query = app.textFields["document.searchQuery"]
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("needle")
        app.buttons["document.searchStart"].tap()
        let hit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "document.searchHit.")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 10)); hit.tap()
        XCTAssertTrue(app.buttons["返回正式阅读位置"].waitForExistence(timeout: 5))
        let preview = try await backend.progress()
        XCTAssertEqual(preview?["readAtMs"] as? Int64, state["readAtMs"] as? Int64)
        XCTAssertEqual(preview?["version"] as? String, state["version"] as? String)
        app.buttons["返回正式阅读位置"].tap()
        app.buttons["阅读设置"].tap()
        let delete = app.buttons["删除此书云端进度"]
        if !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        let confirm = app.buttons["删除云端进度"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["云端进度已删除，本次阅读暂停上传"].waitForExistence(timeout: 15))
        let deleted = try await backend.progress(); XCTAssertNil(deleted)
        capture("live-kindle-cloud-deleted-local-retained", app)
        // Turn again and wait through a real document timer: cloud must stay empty.
        if app.buttons["回到书架"].exists { middle.tap() }
        next.tap()
        try await Task.sleep(for: .seconds(22))
        let paused = try await backend.progress(); XCTAssertNil(paused)
        middle.tap()
        XCTAssertTrue(app.buttons["回到书架"].waitForExistence(timeout: 5)); app.buttons["回到书架"].tap()
        XCTAssertTrue(book.waitForExistence(timeout: 10)); book.tap()
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        _ = try await backend.waitForProgress()
        middle.tap(); app.buttons["书签"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "comic.bookmark.")).firstMatch.waitForExistence(timeout: 5))
        capture("live-kindle-reopened-bookmark-retained", app)
    }

    func testLiveTXTUIPageTurnsTimerUploadAndCloudDeletionKeepsBookmark() async throws {
        continueAfterFailure = true
        let backend = try LiveUIBackend()
        try await backend.start()
        let app = try launch(backend)
        addTeardownBlock { @MainActor in app.terminate(); await backend.cleanup() }
        let text = (1...30).map { "第\($0)章\n这是第\($0)段测试正文。needle 用于验证搜索与临时阅读。\n" }.joined()
        let bytes = Data(text.utf8)
        backend.bookHash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        backend.fileSize = bytes.count
        configure(app, backend: backend); back(app); back(app)
        let book = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "能力验收")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10)); book.tap()
        XCTAssertTrue(app.staticTexts["reader.textCanvas"].waitForExistence(timeout: 10))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
        right.tap()
        let forward = try await backend.waitForTXTProgress()
        XCTAssertGreaterThan(forward["offset"] as? Int64 ?? 0, 0)
        XCTAssertEqual((forward["device"] as? [String: Any])?["deviceName"] as? String, "Live UI iOS")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.45)).tap()
        // Backward movement must win by newer time, not by larger offset.
        try await Task.sleep(for: .seconds(23))
        let receivedBackward = try await backend.txtProgress()
        let backward = try XCTUnwrap(receivedBackward)
        XCTAssertLessThan(backward["offset"] as? Int64 ?? -1, forward["offset"] as? Int64 ?? 0)
        XCTAssertGreaterThan(backward["readAtMs"] as? Int64 ?? 0, forward["readAtMs"] as? Int64 ?? 0)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45)).tap()
        XCTAssertTrue(app.buttons["目录"].waitForExistence(timeout: 5)); app.buttons["目录"].tap()
        let add = app.buttons["添加当前书签"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        app.buttons["catalog.deleteCloudProgress"].tap()
        let confirm = app.buttons["删除本书云端进度"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["本书云端进度已删除，本次阅读暂停上传。"].waitForExistence(timeout: 15))
        let deleted = try await backend.txtProgress(); XCTAssertNil(deleted)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "catalog.bookmark.")).firstMatch.exists)
        capture("live-txt-cloud-deleted-bookmark-retained", app)
    }
}

@MainActor private final class LiveUIBackend {
    let address: String
    let email = "xlib-live-ui-\(UUID().uuidString.lowercased())@example.com"
    let deviceID = UUID()
    private var token: String?
    private let session = URLSession(configuration: .ephemeral)
    var bookHash: String?
    var fileSize: Int?

    init() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["XLIB_LIVE_BACKEND_OPT_IN"] == "1" else { throw XCTSkip("Explicit live-server opt-in required") }
        address = try XCTUnwrap(env["XLIB_LIVE_BACKEND_URL"])
        let url = try XCTUnwrap(URL(string: address))
        guard url.scheme == "https", let host = url.host, !["localhost", "127.0.0.1", "::1"].contains(host),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw URLError(.badURL) }
    }

    private func send(_ method: String, _ path: String, body: [String: Any]? = nil, authorized: Bool = true) async throws -> (Data, Int) {
        let url = path.split(separator: "/").reduce(URL(string: address)!) { $0.appendingPathComponent(String($1)) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized {
            request.setValue("Bearer \(try XCTUnwrap(token))", forHTTPHeaderField: "Authorization")
            request.setValue(deviceID.uuidString.lowercased(), forHTTPHeaderField: "X-Device-Id")
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        else if method == "DELETE" { request.httpBody = Data("{}".utf8) }
        let (data, response) = try await session.data(for: request)
        return (data, try XCTUnwrap(response as? HTTPURLResponse).statusCode)
    }

    func request(_ method: String, _ path: String) async throws -> [String: Any] {
        let (data, status) = try await send(method, path)
        guard (200..<300).contains(status) else { throw NSError(domain: "LiveUIHTTP", code: status) }
        return data.isEmpty ? [:] : try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func start() async throws {
        let (data, status) = try await send("POST", "v1/auth/start-sync", body: ["email": email, "device": [
            "deviceId": deviceID.uuidString.lowercased(), "deviceName": "Live UI verifier", "platform": "ios", "appVersion": "live-ui-test"]], authorized: false)
        guard status == 200 else { throw NSError(domain: "LiveUIStart", code: status) }
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        token = try XCTUnwrap(result["token"] as? String)
    }

    func statusAfterRevocation() async throws -> Int { try await send("GET", "v1/devices").1 }

    func progress() async throws -> [String: Any]? {
        let path = "v2/progress/\(try XCTUnwrap(bookHash))/\(try XCTUnwrap(fileSize))"
        let response = try await request("GET", path)
        return (response["items"] as? [[String: Any]])?.first
    }

    func waitForProgress() async throws -> [String: Any] {
        for _ in 0..<30 {
            if let state = try await progress() { return state }
            try await Task.sleep(for: .seconds(1))
        }
        throw NSError(domain: "LiveUIProgressTimeout", code: 1)
    }

    func txtProgress() async throws -> [String: Any]? {
        let response = try await request("GET", "v1/progress")
        return (response["items"] as? [[String: Any]])?.first {
            $0["bookHash"] as? String == bookHash && $0["fileSize"] as? Int == fileSize
        }
    }

    func waitForTXTProgress() async throws -> [String: Any] {
        for _ in 0..<35 {
            if let state = try await txtProgress() { return state }
            try await Task.sleep(for: .seconds(1))
        }
        throw NSError(domain: "LiveUITXTProgressTimeout", code: 1)
    }

    func cleanup() async {
        // Only our unique account; no database access or account-wide progress purge.
        do {
            try await start() // Also works if this test just revoked its verifier.
            if let bookHash, let fileSize {
                _ = try await request("DELETE", "v2/progress/\(bookHash)/\(fileSize)")
                let deleted = try await progress(); XCTAssertNil(deleted)
                let deletedTXT = try await txtProgress(); XCTAssertNil(deletedTXT)
            }
            let devices = try await request("GET", "v1/devices")["items"] as? [[String: Any]] ?? []
            for device in devices {
                if let id = device["deviceId"] as? String, id != deviceID.uuidString.lowercased() {
                    _ = try await request("DELETE", "v1/devices/\(id)")
                }
            }
            _ = try await request("DELETE", "v1/devices/\(deviceID.uuidString.lowercased())")
        } catch { XCTFail("Live UI cleanup failed (no credentials logged): \(error.localizedDescription)") }
        session.invalidateAndCancel()
    }
}
