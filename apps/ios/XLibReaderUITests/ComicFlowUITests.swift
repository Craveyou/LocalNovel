import XCTest

@MainActor final class ComicFlowUITests: XCTestCase {
    func testComicTwentyPagesBothDirectionsProgressWheelsBookmarkAndRestore() throws {
        try exerciseComic("comic-basic.cbz")
    }
    func testRAR4SolidTwentyPagesBothDirectionsProgressWheelsBookmarkAndRestore() throws {
        try exerciseComic("comic-basic-rar4-solid.cbr")
    }
    private func openComic(_ name: String, missingSource: Bool = false) throws -> (XCUIApplication, XCUIElement, XCUIElement) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["XLIB_UI_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["XLIB_UI_TEST_SCENARIO"] = "comics"
        app.launchEnvironment["XLIB_UI_COMIC_EXTENSION"] = name.hasSuffix(".cbr") ? "cbr" : "cbz"
        if missingSource { app.launchEnvironment["XLIB_UI_COMIC_MISSING_SOURCE"] = "1" }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "fixtures/documents"))
        app.launchEnvironment["XLIB_UI_COMIC"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launch()
        let book = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "漫画验收")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15)); book.tap()
        let canvas = app.scrollViews["comic.canvas"]
        if !missingSource { XCTAssertTrue(canvas.waitForExistence(timeout: 15)) }
        return (app, book, canvas)
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func cancelConfirmation(app: XCUIApplication) {
        // On popover presentations UIKit omits the cancel action; an outside
        // tap is the native cancel operation, and must not execute deletion.
        if app.buttons["取消"].exists { app.buttons["取消"].tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.2)).tap() }
    }
    func testComicEmptyBookmarksSaveDuplicatePreviewAndConfirmedDeletion() throws {
        let (app, _, canvas) = try openComic("comic-basic.cbz")
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45))
        middle.tap(); app.buttons["书签"].tap()
        XCTAssertTrue(app.staticTexts["comic.emptyBookmarks"].waitForExistence(timeout: 5))
        capture("comic-empty-bookmarks-txt-baseline", app: app)
        app.buttons["完成"].tap(); app.buttons["添加书签"].tap()
        XCTAssertTrue(app.staticTexts["comic.operationMessage"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["comic.operationMessage"].label, "书签已保存")
        app.buttons["添加书签"].tap()
        XCTAssertTrue(app.alerts["操作未完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["当前位置已有书签"].exists)
        capture("comic-duplicate-bookmark-feedback", app: app)
        app.alerts.buttons["好"].tap()
        middle.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)).tap()
        assertPage(2, canvas: canvas)
        middle.tap(); app.buttons["书签"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "comic.bookmark.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        assertPage(1, canvas: canvas)
        XCTAssertTrue(app.buttons["返回正式阅读位置"].waitForExistence(timeout: 5))
        app.buttons["返回正式阅读位置"].tap(); assertPage(2, canvas: canvas)
        app.buttons["书签"].tap(); XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft(); app.buttons["删除"].firstMatch.tap()
        XCTAssertTrue(app.buttons["删除书签"].waitForExistence(timeout: 5)); cancelConfirmation(app: app)
        XCTAssertTrue(row.exists)
        row.swipeLeft(); app.buttons["删除"].firstMatch.tap()
        XCTAssertTrue(app.buttons["删除书签"].waitForExistence(timeout: 5))
        app.buttons["删除书签"].tap()
        XCTAssertTrue(app.staticTexts["comic.emptyBookmarks"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap(); assertPage(2, canvas: canvas)
    }
    func testComicCloudConfirmationAfterOptionsDismissesAndFailureKeepsPage() throws {
        let (app, _, canvas) = try openComic("comic-basic.cbz")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45)).tap()
        app.buttons["阅读设置"].tap()
        XCTAssertTrue(app.staticTexts["图片漫画暂不支持正文搜索/复制；不执行 OCR。"].waitForExistence(timeout: 5))
        capture("comic-settings-txt-cards", app: app)
        let delete = app.buttons["删除此书云端进度"]
        if !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        XCTAssertTrue(app.buttons["删除云端进度"].waitForExistence(timeout: 5))
        capture("comic-cloud-delete-confirmation", app: app)
        cancelConfirmation(app: app); assertPage(1, canvas: canvas)
        app.buttons["阅读设置"].tap()
        if !delete.isHittable { app.swipeUp() }
        delete.tap()
        let confirmation = app.sheets["删除此书的云端阅读进度？"].buttons["删除云端进度"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: confirmation)
        waitForExpectations(timeout: 5)
        confirmation.tap()
        XCTAssertTrue(app.alerts["操作未完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["云端删除失败，本地阅读进度已保留"].exists)
        capture("comic-cloud-failure-retains-local", app: app)
        app.alerts.buttons["好"].tap(); assertPage(1, canvas: canvas)
    }
    func testComicMissingSourceErrorRetryAndReturnToLibrary() throws {
        let (app, _, _) = try openComic("comic-basic.cbz", missingSource: true)
        XCTAssertTrue(app.staticTexts["漫画暂时无法打开"].waitForExistence(timeout: 10))
        capture("comic-missing-original-error", app: app)
        app.buttons["重试打开"].tap()
        XCTAssertTrue(app.buttons["返回书架"].waitForExistence(timeout: 10))
        app.buttons["返回书架"].tap()
        XCTAssertTrue(app.buttons["添加书籍"].waitForExistence(timeout: 5))
    }
    private func assertPage(_ page: Int, canvas: XCUIElement) {
        expectation(for: NSPredicate(format: "value == %@", "第 \(page) 页"), evaluatedWith: canvas)
        waitForExpectations(timeout: 8)
    }
    private func setSwitch(_ element: XCUIElement, to value: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        if element.value as? String != value {
            // SwiftUI exposes the entire labeled row as a switch. Tap its
            // actual trailing control, not the center of the text label.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }
    func testComicGesturesDirectionFitThemeAndLongPageRestore() throws {
        let (app, book, canvas) = try openComic("comic-basic.cbz")
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45))
        middle.tap()
        app.buttons["阅读设置"].tap()
        setSwitch(app.switches["comic.rightToLeft"], to: "1")
        setSwitch(app.switches["comic.fitWidth"], to: "0")
        app.buttons["完成"].tap()
        // Same TXT toolbar, in both themes; content is never recolored.
        app.buttons["切换主题"].tap()
        let dark = XCTAttachment(screenshot: app.screenshot()); dark.name = "comic-dark-txt-toolbar"; dark.lifetime = .keepAlways; add(dark)
        app.buttons["切换主题"].tap()
        middle.tap()
        for page in 2...6 { canvas.swipeRight(); assertPage(page, canvas: canvas) }
        canvas.swipeLeft(); assertPage(5, canvas: canvas)
        canvas.pinch(withScale: 2, velocity: 2)
        canvas.swipeRight()
        assertPage(5, canvas: canvas) // At zoom > 1 this must pan, not turn a page.
        middle.tap(); app.buttons["阅读设置"].tap()
        setSwitch(app.switches["comic.fitWidth"], to: "1"); app.buttons["完成"].tap()
        app.buttons["reader.progressButton"].tap()
        let whole = app.pickers["reader.progressWholePicker"].pickerWheels.firstMatch
        XCTAssertTrue(whole.waitForExistence(timeout: 5))
        whole.adjust(toPickerWheelValue: "45")
        app.pickers["reader.progressFractionPicker"].pickerWheels.firstMatch.adjust(toPickerWheelValue: "00")
        app.buttons["reader.progressGo"].tap(); assertPage(11, canvas: canvas)
        middle.tap()
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
        assertPage(11, canvas: canvas)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        assertPage(11, canvas: canvas)
        XCUIDevice.shared.orientation = .portrait
        middle.tap(); app.buttons["添加书签"].tap()
        let longPage = XCTAttachment(screenshot: app.screenshot()); longPage.name = "comic-long-page-after-pan-and-rotation"; longPage.lifetime = .keepAlways; add(longPage)
        app.buttons["回到书架"].tap()
        XCTAssertTrue(book.waitForExistence(timeout: 5)); book.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10)); assertPage(11, canvas: canvas)
        middle.tap(); app.buttons["书签"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "第 11 / 24 页")).firstMatch.waitForExistence(timeout: 5))
    }
    private func exerciseComic(_ name: String) throws {
        let (app, book, canvas) = try openComic(name)
        let next = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45))
        let previous = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.45))
        for page in 2...21 {
            next.tap()
            expectation(for: NSPredicate(format: "value == %@", "第 \(page) 页"), evaluatedWith: canvas)
            waitForExpectations(timeout: 5)
        }
        for page in (1...20).reversed() {
            previous.tap()
            expectation(for: NSPredicate(format: "value == %@", "第 \(page) 页"), evaluatedWith: canvas)
            waitForExpectations(timeout: 5)
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45)).tap()
        XCTAssertTrue(app.buttons["reader.progressButton"].waitForExistence(timeout: 5))
        app.buttons["reader.progressButton"].tap()
        let whole = app.pickers["reader.progressWholePicker"].pickerWheels.firstMatch
        let fraction = app.pickers["reader.progressFractionPicker"].pickerWheels.firstMatch
        XCTAssertTrue(whole.waitForExistence(timeout: 5))
        whole.adjust(toPickerWheelValue: "50")
        fraction.adjust(toPickerWheelValue: "00")
        app.buttons["reader.progressGo"].tap()
        expectation(for: NSPredicate(format: "value == %@", "第 12 页"), evaluatedWith: canvas)
        waitForExpectations(timeout: 5)
        app.buttons["添加书签"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "comic-txt-chrome-and-position"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["回到书架"].tap()
        XCTAssertTrue(book.waitForExistence(timeout: 5)); book.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "value == %@", "第 12 页"), evaluatedWith: canvas)
        waitForExpectations(timeout: 5)
    }
}
