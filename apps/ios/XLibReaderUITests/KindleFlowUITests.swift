import XCTest

@MainActor final class KindleFlowUITests:XCTestCase {
    private func capture(_ name:String,app:XCUIApplication) {
        let attachment = XCTAttachment(screenshot:app.screenshot());attachment.name = name;attachment.lifetime = .keepAlways;add(attachment)
    }
    func testKindleLongPressDragCancelAndCopyPreserveFormalPosition() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["XLIB_UI_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["XLIB_UI_TEST_SCENARIO"] = "kindle"
        let url = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"kindle-long.mobi",withExtension:nil,subdirectory:"fixtures/documents"))
        app.launchEnvironment["XLIB_UI_KINDLE"] = try Data(contentsOf:url).base64EncodedString();app.launch()
        let book = app.buttons.containing(NSPredicate(format:"label CONTAINS %@","Kindle验收")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout:15));book.tap()
        let web = app.webViews["document.content.ready"]
        XCTAssertTrue(web.waitForExistence(timeout:15))
        app.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.45)).tap()
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@","第 2 章"),object:web)],timeout:10),.completed)
        let middle = app.coordinate(withNormalizedOffset:CGVector(dx:0.45,dy:0.45))
        middle.tap();let position = app.staticTexts["document.position"]
        XCTAssertTrue(position.waitForExistence(timeout:5));let original = position.label;middle.tap()
        let probe = app.staticTexts["testing.clipboardGeneration"]
        XCTAssertTrue(probe.waitForExistence(timeout:5));let generation = try XCTUnwrap(Int(probe.label))
        let start = web.coordinate(withNormalizedOffset:CGVector(dx:0.23,dy:0.14))
        let end = web.coordinate(withNormalizedOffset:CGVector(dx:0.50,dy:0.25))
        start.press(forDuration:0.8,thenDragTo:end)
        let copy = app.buttons["document.copySelection"]
        XCTAssertTrue(copy.waitForExistence(timeout:5));XCTAssertGreaterThan((copy.value as? String)?.count ?? 0,2)
        XCTAssertFalse((copy.value as? String ?? "").contains("\u{fffc}"))
        XCTAssertEqual(Int(probe.label),generation)
        capture("kindle-native-selection-copy-cancel",app:app)
        app.buttons["document.cancelSelection"].tap();XCTAssertTrue(copy.waitForNonExistence(timeout:5))
        XCTAssertEqual(Int(probe.label),generation)
        start.press(forDuration:0.8,thenDragTo:end)
        XCTAssertTrue(copy.waitForExistence(timeout:5));copy.tap()
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label != %@",String(generation)),object:probe)],timeout:5),.completed)
        middle.tap();XCTAssertTrue(position.waitForExistence(timeout:5));XCTAssertEqual(position.label,original)
    }
    func testKindleReadingMenuSearchPreviewPreferencesBookmarksAndReopen() throws {
        continueAfterFailure = false
        let app = XCUIApplication(),id = UUID().uuidString
        app.launchEnvironment["XLIB_UI_TEST_ID"] = id
        app.launchEnvironment["XLIB_UI_TEST_SCENARIO"] = "kindle"
        let url = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"kindle-long.mobi",withExtension:nil,subdirectory:"fixtures/documents"))
        app.launchEnvironment["XLIB_UI_KINDLE"] = try Data(contentsOf:url).base64EncodedString()
        app.launch()
        let book = app.buttons.containing(NSPredicate(format:"label CONTAINS %@","Kindle验收")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout:15));book.tap()
        XCTAssertTrue(app.webViews["document.content.ready"].waitForExistence(timeout:15))
        let middle = app.coordinate(withNormalizedOffset:CGVector(dx:0.45,dy:0.45))
        let next = app.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.45))
        next.tap()
        let content = app.webViews["document.content.ready"]
        XCTAssertTrue(NSPredicate(format:"value == %@","第 2 章").evaluate(with:content) || XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@","第 2 章"),object:content)],timeout:10) == .completed)
        middle.tap()
        capture("kindle-after-first-taps",app:app)
        XCTAssertTrue(app.buttons["搜索"].waitForExistence(timeout:5))
        capture("kindle-txt-aligned-chrome",app:app)
        app.buttons["添加书签"].tap()
        XCTAssertTrue(app.staticTexts["comic.operationMessage"].waitForExistence(timeout:5))
        app.buttons["搜索"].tap()
        let query = app.textFields["document.searchQuery"]
        XCTAssertTrue(query.waitForExistence(timeout:5));query.tap();query.typeText("needle")
        app.buttons["document.searchStart"].tap()
        let hit = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","document.searchHit.")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout:8));capture("kindle-search-results",app:app);hit.tap()
        XCTAssertTrue(app.buttons["返回正式阅读位置"].waitForExistence(timeout:5))
        app.buttons["返回正式阅读位置"].tap()
        app.buttons["阅读设置"].tap()
        XCTAssertTrue(app.steppers["document.fontSize"].waitForExistence(timeout:5))
        capture("kindle-settings-txt-cards",app:app)
        app.steppers["document.fontSize"].buttons.element(boundBy:1).tap()
        app.buttons["完成"].tap()
        app.buttons["书签"].tap()
        let bookmark = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","comic.bookmark.")).firstMatch
        XCTAssertTrue(bookmark.waitForExistence(timeout:5));bookmark.tap()
        XCTAssertTrue(app.buttons["返回正式阅读位置"].waitForExistence(timeout:5));app.buttons["返回正式阅读位置"].tap()
        XCTAssertTrue(app.buttons["选择阅读进度"].exists)
        app.buttons["选择阅读进度"].tap()
        XCTAssertTrue(app.buttons["前往"].waitForExistence(timeout:5));capture("kindle-progress-wheels",app:app);app.buttons["前往"].tap()
        app.buttons["回到书架"].tap();XCTAssertTrue(book.waitForExistence(timeout:5));book.tap()
        XCTAssertTrue(app.webViews["document.content.ready"].waitForExistence(timeout:10));middle.tap()
        XCTAssertTrue(app.staticTexts["document.position"].waitForExistence(timeout:5))
        capture("kindle-reopen-restored",app:app)
    }
}
