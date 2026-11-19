import XCTest
import UIKit
import PDFKit

final class XLibReaderUITests: XCTestCase {
    @MainActor
    func testLibraryLongPressDeletionConfirmsTargetAndKeepsOtherBooks() {
        let app = launchApp(scenario: "library")
        let book = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "能力验收")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.press(forDuration: 0.8)
        let delete = app.buttons["library.deleteBook"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["reader.textCanvas"].exists)
        delete.tap()
        let confirm = app.buttons["删除书籍"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["删除《能力验收》？"].exists)
        cancelConfirmation(in: app)
        XCTAssertTrue(book.exists)
        book.tap()
        showReaderMenu(app)
        app.buttons["目录"].tap()
        XCTAssertTrue(app.buttons["书签"].waitForExistence(timeout: 5))
        app.buttons["书签"].tap()
        let bookmarks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "catalog.bookmark."))
        XCTAssertTrue(bookmarks.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(bookmarks.count, 1)
        app.buttons["返回阅读"].tap()
        showReaderMenu(app)
        app.buttons["回到书架"].tap()
        book.press(forDuration: 0.8)
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(book.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "保留书籍")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["12 本本地书籍"].exists)
    }

    @MainActor
    func testLibrarySwipeScrollAndManagementDoNotAlsoOpenBooks() {
        let app = launchApp(scenario: "library")
        let book = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "能力验收")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        let swipeStart = book.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
        let swipeEnd = book.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.54))
        swipeStart.press(forDuration: 0.05, thenDragTo: swipeEnd)
        XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["目录管理"].exists)
        book.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["编辑"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["reader.textCanvas"].exists)
        book.swipeLeft()
        XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout: 5))
        book.swipeRight()
        XCTAssertTrue(app.buttons["编辑"].waitForNonExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()
        XCTAssertFalse(app.staticTexts["reader.textCanvas"].exists)
        XCTAssertFalse(app.buttons["library.deleteBook"].exists)
        app.swipeDown()
        app.swipeDown()
        app.buttons["管理书籍"].tap()
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.book.")).firstMatch
        first.press(forDuration: 0.8)
        XCTAssertFalse(app.buttons["library.deleteBook"].exists)
        XCTAssertFalse(app.staticTexts["reader.textCanvas"].exists)
        if !app.buttons["删除书籍 1"].exists { first.tap() }
        app.buttons["删除书籍 1"].tap()
        XCTAssertTrue(app.buttons["删除书籍"].waitForExistence(timeout: 5))
        cancelConfirmation(in: app)
        app.buttons["完成管理"].tap()
        XCTAssertTrue(app.staticTexts["13 本本地书籍"].exists)
    }

    @MainActor
    func testProgressWheelsPreviewWithoutCommittingAndReopenAtConfirmedPosition() {
        let app = launchApp(scenario: "reading")
        openFixtureReader(app)
        let progress = app.buttons["reader.progressButton"]
        let original = progress.value as? String
        progress.tap()
        let whole = app.pickers["reader.progressWholePicker"].pickerWheels.firstMatch
        let fraction = app.pickers["reader.progressFractionPicker"].pickerWheels.firstMatch
        XCTAssertTrue(whole.waitForExistence(timeout: 5))
        whole.adjust(toPickerWheelValue: "73")
        fraction.adjust(toPickerWheelValue: "54")
        XCTAssertEqual(app.staticTexts["reader.progressPreview"].label, "73.54%")
        XCTAssertEqual(progress.value as? String, original)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertFalse(whole.exists)
        XCTAssertEqual(progress.value as? String, original)
        progress.tap()
        XCTAssertEqual(whole.value as? String, "0")
        XCTAssertEqual(fraction.value as? String, "00")
        whole.adjust(toPickerWheelValue: "73")
        fraction.adjust(toPickerWheelValue: "54")
        app.buttons["reader.progressGo"].tap()
        expectation(for: NSPredicate(format: "value == %@", "73.54%"), evaluatedWith: progress)
        waitForExpectations(timeout: 5)
        progress.tap()
        XCTAssertEqual(whole.value as? String, "73")
        XCTAssertEqual(fraction.value as? String, "54")
        whole.adjust(toPickerWheelValue: "100")
        XCTAssertEqual(fraction.value as? String, "00")
        fraction.swipeUp()
        XCTAssertEqual(fraction.value as? String, "00")
        XCTAssertEqual(app.staticTexts["reader.progressPreview"].label, "100.00%")
        attachScreenshot(app, name: "浅色进度选择 100%")
        app.buttons["reader.progressGo"].tap()
        expectation(for: NSPredicate(format: "value == %@", "100.00%"), evaluatedWith: progress)
        waitForExpectations(timeout: 5)
        app.buttons["切换主题"].tap()
        progress.tap()
        XCTAssertEqual(whole.value as? String, "100")
        fraction.swipeUp()
        XCTAssertEqual(fraction.value as? String, "00")
        attachScreenshot(app, name: "深色进度选择 100%")
        whole.adjust(toPickerWheelValue: "0")
        XCTAssertTrue(fraction.isEnabled)
        XCTAssertEqual(app.staticTexts["reader.progressPreview"].label, "0.00%")
        app.buttons["reader.progressGo"].tap()
        expectation(for: NSPredicate(format: "value == %@", "0.00%"), evaluatedWith: progress)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testSelectionCopiesOnlyOnRequestAndKeepsFormalProgressAndAutoPagingStopped() {
        let app = launchApp(scenario: "reading")
        openFixtureReader(app)
        let original = app.buttons["reader.progressButton"].value as? String
        app.buttons["自动翻页"].tap()
        XCTAssertEqual(app.buttons["自动翻页"].value as? String, "开启")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        let canvas = app.staticTexts["reader.textCanvas"]
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.08))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.14))
        let clipboardChanges = clipboardGeneration(app)
        start.press(forDuration: 0.8, thenDragTo: end)
        XCTAssertTrue(app.buttons["reader.copySelection"].waitForExistence(timeout: 5))
        app.buttons["reader.cancelSelection"].tap()
        XCTAssertEqual(clipboardGeneration(app), clipboardChanges)
        showReaderMenu(app)
        XCTAssertEqual(app.buttons["自动翻页"].value as? String, "关闭")
        XCTAssertEqual(app.buttons["reader.progressButton"].value as? String, original)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        start.press(forDuration: 0.8, thenDragTo: end)
        let copy = app.buttons["reader.copySelection"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        let expected = copy.value as? String
        XCTAssertTrue(expected?.contains("\n") == true)
        copy.tap()
        XCTAssertFalse(copy.exists)
        assertClipboardChanged(app, after: clipboardChanges)
        showReaderMenu(app)
        XCTAssertEqual(app.buttons["reader.progressButton"].value as? String, original)
        app.buttons["回到书架"].tap()
        let book = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "能力验收")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        XCTAssertTrue(book.label.contains("暂无阅读记录"))
        book.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertFalse(copy.exists)
    }

    @MainActor
    private func cancelConfirmation(in app: XCUIApplication) {
        if app.buttons["取消"].exists {
            app.buttons["取消"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.1)).tap()
        }
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLongPressDragCopySelectionAndCancel() throws {
        let app = launchApp(scenario: "reading")
        openFixtureReader(app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        let canvas = app.staticTexts["reader.textCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.08))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.14))
        start.press(forDuration: 0.8, thenDragTo: end)
        let copy = app.buttons["reader.copySelection"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertGreaterThan((copy.value as? String)?.count ?? 0, 2)
        let beforeAdjustment = copy.value as? String
        let endHandle = try selectionHandle("end", in: canvas)
        let adjustedEnd = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.19))
        endHandle.press(forDuration: 0.05, thenDragTo: adjustedEnd)
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertNotEqual(copy.value as? String, beforeAdjustment)
        let beforeStartAdjustment = copy.value as? String
        let startHandle = try selectionHandle("start", in: canvas)
        let adjustedStart = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.065))
        startHandle.press(forDuration: 0.05, thenDragTo: adjustedStart)
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertNotEqual(copy.value as? String, beforeStartAdjustment)
        let selectionScreenshot = XCTAttachment(screenshot: app.screenshot())
        selectionScreenshot.lifetime = .keepAlways
        add(selectionScreenshot)
        app.buttons["reader.cancelSelection"].tap()
        XCTAssertFalse(copy.exists)
    }

    @MainActor
    private func launchApp(scenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["XLIB_UI_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["XLIB_UI_TEST_SCENARIO"] = scenario
        if scenario == "documents" {
            for (key,name) in [("XLIB_UI_PDF","text-rotated.pdf"),("XLIB_UI_EPUB","reflow.epub")] {
                let url = Bundle(for:Self.self).url(forResource:name,withExtension:nil,subdirectory:"fixtures/documents")!
                app.launchEnvironment[key] = try! Data(contentsOf:url).base64EncodedString()
            }
            let source = Bundle(for:Self.self).url(forResource:"text-rotated.pdf",withExtension:nil,subdirectory:"fixtures/documents")!
            let document = PDFDocument(url:source)!
            let bytes = document.dataRepresentation(options:[PDFDocumentWriteOption.userPasswordOption.rawValue:"test-password",PDFDocumentWriteOption.ownerPasswordOption.rawValue:"test-owner"])!
            XCTAssertTrue(PDFDocument(data:bytes)?.isLocked == true)
            app.launchEnvironment["XLIB_UI_LOCKED_PDF"] = bytes.base64EncodedString()
        }
        app.launch()
        return app
    }

    @MainActor
    private func clipboardGeneration(_ app: XCUIApplication) -> Int {
        let probe = app.staticTexts["testing.clipboardGeneration"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let generation = Int(probe.label)
        XCTAssertNotNil(generation)
        return generation ?? -1
    }

    @MainActor
    private func selectionHandle(_ name: String, in canvas: XCUIElement) throws -> XCUICoordinate {
        let raw = try XCTUnwrap(canvas.value as? String)
        let points = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Double])
        return canvas.coordinate(withNormalizedOffset: CGVector(dx: try XCTUnwrap(points[name + "X"]), dy: try XCTUnwrap(points[name + "Y"])))
    }

    @MainActor
    private func assertClipboardChanged(_ app: XCUIApplication, after generation: Int) {
        let probe = app.staticTexts["testing.clipboardGeneration"]
        expectation(for: NSPredicate(format: "label != %@", String(generation)), evaluatedWith: probe)
        waitForExpectations(timeout: 5)
        XCTAssertGreaterThan(clipboardGeneration(app), generation)
    }

    @MainActor
    func testPDFNavigationSearchBookmarksAndReopenThroughTheActualScreen() {
        let app = launchApp(scenario:"documents")
        openDocument("PDF验收",in:app)
        let position = app.staticTexts["document.position"]
        XCTAssertTrue(position.waitForExistence(timeout:10))
        XCTAssertTrue(position.label.contains("第 1 页"))
        app.buttons["下一页"].tap()
        expectation(for:NSPredicate(format:"label CONTAINS %@","第 2 页"),evaluatedWith:position)
        waitForExpectations(timeout:5)
        documentMenu("书签",in:app)
        app.buttons["添加当前位置书签"].tap()
        let marks = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","document.bookmark."))
        XCTAssertTrue(marks.firstMatch.waitForExistence(timeout:5))
        app.buttons["添加当前位置书签"].tap()
        XCTAssertTrue(app.staticTexts["当前位置已有书签"].waitForExistence(timeout:5))
        app.alerts.buttons["好"].tap()
        XCTAssertEqual(marks.count,1)
        app.buttons["完成"].tap()
        documentMenu("搜索",in:app)
        let query = app.textFields["document.searchQuery"]
        query.tap();query.typeText("absent-token")
        app.buttons["document.searchStart"].tap()
        XCTAssertTrue(app.staticTexts["0 条结果"].waitForExistence(timeout:5))
        app.buttons["完成"].tap()
        app.buttons["返回书架"].tap()
        openDocument("PDF验收",in:app)
        XCTAssertTrue(position.waitForExistence(timeout:10))
        XCTAssertTrue(position.label.contains("第 2 页"))
        documentMenu("书签",in:app)
        XCTAssertEqual(marks.count,1)
        marks.firstMatch.swipeLeft()
        app.buttons["删除"].tap()
        app.buttons["删除"].tap()
        XCTAssertTrue(app.staticTexts["还没有书签"].waitForExistence(timeout:5))
    }

    @MainActor
    func testEPUBSearchPreviewReturnAndReflowThroughTheActualScreen() {
        let app = launchApp(scenario:"documents")
        openDocument("EPUB验收",in:app)
        let position = app.staticTexts["document.position"]
        XCTAssertTrue(position.waitForExistence(timeout:10))
        let original = position.label
        documentMenu("搜索",in:app)
        let query = app.textFields["document.searchQuery"]
        query.tap();query.typeText("needle")
        app.buttons["document.searchStart"].tap()
        XCTAssertTrue(app.staticTexts["102 条结果"].waitForExistence(timeout:10))
        let hit = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","document.searchHit.")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout:5));hit.tap()
        XCTAssertTrue(app.buttons["返回正式阅读位置"].waitForExistence(timeout:5))
        app.buttons["返回正式阅读位置"].tap()
        XCTAssertEqual(position.label,original)
        documentMenu("排版",in:app)
        XCTAssertTrue(app.staticTexts["EPUB 排版"].waitForExistence(timeout:5))
        app.steppers["document.fontSize"].buttons.element(boundBy:1).tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(position.label,original)
        app.buttons["下一章"].tap()
        expectation(for:NSPredicate(format:"label CONTAINS %@","第 2 章"),evaluatedWith:position)
        waitForExpectations(timeout:10)
        app.buttons["返回书架"].tap()
        openDocument("EPUB验收",in:app)
        XCTAssertTrue(position.waitForExistence(timeout:10))
        XCTAssertTrue(position.label.contains("第 2 章"))
    }

    @MainActor
    func testPasswordPDFWrongRetryCancelAndReopenRequireUnlock() {
        let app = launchApp(scenario:"documents")
        openDocument("密码验收",in:app)
        let password = app.secureTextFields["密码"]
        XCTAssertTrue(password.waitForExistence(timeout:10))
        password.tap();password.typeText("wrong")
        app.alerts.buttons["打开"].tap()
        XCTAssertTrue(app.alerts["密码错误，请重试"].waitForExistence(timeout:5))
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["我的书架"].waitForExistence(timeout:5))
        openDocument("密码验收",in:app)
        XCTAssertTrue(password.waitForExistence(timeout:10))
        password.tap();password.typeText("test-password");app.alerts.buttons["打开"].tap()
        XCTAssertTrue(app.buttons["下一页"].waitForExistence(timeout:10))
        app.buttons["下一页"].tap()
        let position = app.staticTexts["document.position"]
        expectation(for:NSPredicate(format:"label CONTAINS %@","第 2 页"),evaluatedWith:position)
        waitForExpectations(timeout:5)
        app.buttons["返回书架"].tap()
        openDocument("密码验收",in:app)
        XCTAssertTrue(password.waitForExistence(timeout:10))
        password.tap();password.typeText("test-password");app.alerts.buttons["打开"].tap()
        XCTAssertTrue(position.waitForExistence(timeout:10));XCTAssertTrue(position.label.contains("第 2 页"))
    }

    @MainActor
    func testEPUBLongPressDragCopyAndCancelKeepFormalPosition() {
        let app = launchApp(scenario:"documents")
        openDocument("EPUB验收",in:app)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout:10))
        let position = app.staticTexts["document.position"]
        let original = position.label
        let before = clipboardGeneration(app)
        let start = web.coordinate(withNormalizedOffset:CGVector(dx:0.23,dy:0.14))
        let end = web.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.23))
        start.press(forDuration:0.8,thenDragTo:end)
        let copy = app.buttons["document.copySelection"]
        XCTAssertTrue(copy.waitForExistence(timeout:5))
        XCTAssertGreaterThan((copy.value as? String)?.count ?? 0,2)
        XCTAssertEqual(clipboardGeneration(app),before)
        app.buttons["document.cancelSelection"].tap()
        XCTAssertTrue(copy.waitForNonExistence(timeout:5))
        XCTAssertEqual(position.label,original)
        start.press(forDuration:0.8,thenDragTo:end)
        XCTAssertTrue(copy.waitForExistence(timeout:5));copy.tap()
        assertClipboardChanged(app, after: before)
        XCTAssertEqual(position.label,original)
        app.buttons["返回书架"].tap()
        let book = app.buttons.containing(NSPredicate(format:"label CONTAINS %@","EPUB验收")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout:5));XCTAssertTrue(book.label.contains("暂无阅读记录"))
    }

    @MainActor
    func testPDFLongPressDragSelectionDoesNotCreateReadingProgress() {
        let app = launchApp(scenario:"documents")
        openDocument("PDF验收",in:app)
        let pdf = app.descendants(matching:.any).matching(identifier:"PDF 正文").firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout:10))
        let position = app.staticTexts["document.position"]
        let original = position.label
        let before = clipboardGeneration(app)
        attachScreenshot(app,name:"PDF 选文前布局")
        pdf.coordinate(withNormalizedOffset:CGVector(dx:0.20,dy:0.135)).press(forDuration:0.8,thenDragTo:pdf.coordinate(withNormalizedOffset:CGVector(dx:0.60,dy:0.20)))
        let copy = app.buttons["document.copySelection"]
        XCTAssertTrue(copy.waitForExistence(timeout:5))
        XCTAssertGreaterThan((copy.value as? String)?.count ?? 0,2)
        XCTAssertEqual(clipboardGeneration(app),before)
        app.buttons["document.cancelSelection"].tap()
        XCTAssertTrue(copy.waitForNonExistence(timeout:5));XCTAssertEqual(position.label,original)
        app.buttons["返回书架"].tap()
        let book = app.buttons.containing(NSPredicate(format:"label CONTAINS %@","PDF验收")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout:5));XCTAssertTrue(book.label.contains("暂无阅读记录"))
    }

    @MainActor
    func testDocumentFastScrollSavesPositionAndRestoresAfterReopen() {
        let app = launchApp(scenario:"documents")
        for title in ["PDF验收","EPUB验收"] {
            openDocument(title,in:app)
            let menu = app.buttons["文档菜单"]
            expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:menu)
            waitForExpectations(timeout:10)
            let position = app.staticTexts["document.position"]
            let original = position.label
            let surface = title == "PDF验收" ? app.descendants(matching:.any).matching(identifier:"PDF 正文").firstMatch : app.webViews.firstMatch
            surface.swipeUp(velocity:.fast)
            expectation(for:NSPredicate(format:"label != %@",original),evaluatedWith:position)
            waitForExpectations(timeout:10)
            // Wait for deceleration to finish before comparing the persisted anchor.
            XCTAssertTrue(menu.isHittable)
            let saved = position.label
            app.buttons["返回书架"].tap()
            let book = app.buttons.containing(NSPredicate(format:"label CONTAINS %@",title)).firstMatch
            XCTAssertTrue(book.waitForExistence(timeout:5));XCTAssertFalse(book.label.contains("暂无阅读记录"))
            openDocument(title,in:app)
            expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:menu)
            waitForExpectations(timeout:10)
            XCTAssertEqual(position.label,saved)
            app.buttons["返回书架"].tap()
        }
    }

    @MainActor
    func testPDFCropMenuIsGlobalAndResetKeepsProgress() {
        let app = launchApp(scenario: "documents")
        openDocument("PDF验收", in: app)
        let position = app.staticTexts["document.position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        let original = position.label
        documentMenu("PDF 裁边", in: app)
        let enabled = app.switches["pdfCrop.enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let left = app.sliders["pdfCrop.left"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: left)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(left.isEnabled)
        left.adjust(toNormalizedSliderPosition: 0.5)
        let value = left.value as? String
        XCTAssertNotEqual(value, "10%")
        attachScreenshot(app, name: "PDF 裁边配置面板")
        app.buttons["完成"].tap()
        XCTAssertEqual(position.label, original)
        attachScreenshot(app, name: "PDF 左右裁边后")
        app.buttons["返回书架"].tap()
        openDocument("密码验收", in: app)
        // Another PDF in the same application run shares the crop controls.
        let password = app.secureTextFields.firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap(); password.typeText("test-password"); app.alerts.buttons["打开"].tap()
        documentMenu("PDF 裁边", in: app)
        XCTAssertEqual(app.switches["pdfCrop.enabled"].value as? String, "1")
        XCTAssertEqual(app.sliders["pdfCrop.left"].value as? String, value)
        app.buttons["pdfCrop.reset"].tap()
        XCTAssertEqual(app.switches["pdfCrop.enabled"].value as? String, "0")
        app.buttons["完成"].tap()
        app.buttons["返回书架"].tap()
        openDocument("PDF验收", in: app)
        XCTAssertEqual(position.label, original)
        app.buttons["返回书架"].tap()
        openDocument("EPUB验收", in: app)
        let menu = app.buttons["文档菜单"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: menu)
        waitForExpectations(timeout: 10); menu.tap()
        XCTAssertFalse(app.buttons["PDF 裁边"].exists)
    }

    @MainActor
    func testDocumentSearchWrapOnlyWhenOriginalStartHasUnsearchedPrefix() {
        let app = launchApp(scenario:"documents")
        for (title,next,unit) in [("PDF验收","下一页","第 2 页"),("EPUB验收","下一章","第 2 章")] {
            openDocument(title,in:app)
            let position = app.staticTexts["document.position"]
            XCTAssertTrue(position.waitForExistence(timeout:10))
            let nextButton = app.buttons[next]
            expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:nextButton)
            waitForExpectations(timeout:10);nextButton.tap()
            expectation(for:NSPredicate(format:"label CONTAINS %@",unit),evaluatedWith:position)
            waitForExpectations(timeout:10)
            let original = position.label
            documentMenu("搜索",in:app)
            let query = app.textFields["document.searchQuery"]
            query.tap();query.typeText("absent-token")
            app.buttons["document.searchStart"].tap()
            let wrap = app.buttons["document.searchWrap"]
            XCTAssertTrue(wrap.waitForExistence(timeout:10));wrap.tap()
            let completed = app.staticTexts["document.searchComplete"]
            XCTAssertTrue(completed.waitForExistence(timeout:10));XCTAssertFalse(wrap.exists)
            app.buttons["document.searchFromBeginning"].tap()
            XCTAssertTrue(completed.waitForExistence(timeout:10));XCTAssertFalse(wrap.exists)
            let proof = XCTAttachment(screenshot:app.screenshot());proof.lifetime = .keepAlways;add(proof)
            app.buttons["完成"].tap()
            XCTAssertEqual(position.label,original)
            app.buttons["返回书架"].tap()
        }
    }

    @MainActor private func openDocument(_ title:String,in app:XCUIApplication) {
        let book = app.buttons.containing(NSPredicate(format:"label CONTAINS %@",title)).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout:10));book.tap()
    }
    @MainActor private func documentMenu(_ title:String,in app:XCUIApplication) {
        let menu = app.buttons["文档菜单"]
        XCTAssertTrue(menu.waitForExistence(timeout:10))
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:menu)
        waitForExpectations(timeout:10);menu.tap();app.buttons[title].tap()
    }

    @MainActor
    private func openFixtureReader(_ app: XCUIApplication) {
        let book = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "能力验收")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        showReaderMenu(app)
    }

    @MainActor
    private func showReaderMenu(_ app: XCUIApplication) {
        let progress = app.buttons["reader.progressButton"]
        if !progress.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        }
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
    }

    @MainActor
    func testBookmarkDuplicateAndSingleDeletion() {
        let app = launchApp(scenario: "reading")
        openFixtureReader(app)
        app.buttons["目录"].tap()
        let add = app.buttons["添加当前书签"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.staticTexts["书签已保存"].waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.staticTexts["当前位置已有书签"].waitForExistence(timeout: 5))
        let marks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "catalog.bookmark."))
        XCTAssertEqual(marks.count, 1)
        marks.firstMatch.press(forDuration: 1)
        let delete = app.buttons["删除书签"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "还没有书签")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(marks.count, 0)
    }

    @MainActor
    func testSearchTemporaryReadingPreservesFormalProgress() {
        let app = launchApp(scenario: "reading")
        openFixtureReader(app)
        let original = app.buttons["reader.progressButton"].value as? String
        app.buttons["搜索当前书籍"].tap()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("NEEDLE")
        app.buttons["开始搜索"].tap()
        let status = app.staticTexts["search.status"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "30 条结果"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.result.")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        showReaderMenu(app)
        XCTAssertNotEqual(app.buttons["reader.progressButton"].value as? String, original)
        app.buttons["回到书架"].tap()
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        app.buttons["返回阅读"].tap()
        showReaderMenu(app)
        XCTAssertEqual(app.buttons["reader.progressButton"].value as? String, original)
        app.buttons["回到书架"].tap()
        openFixtureReader(app)
        XCTAssertEqual(app.buttons["reader.progressButton"].value as? String, original)
    }

    @MainActor
    func testCloudDeletionConfirmationAndLocalDataSurvive() {
        let app = launchApp(scenario: "sync")
        openFixtureReader(app)
        let original = app.buttons["reader.progressButton"].value as? String
        app.buttons["目录"].tap()
        let add = app.buttons["添加当前书签"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let delete = app.buttons["catalog.deleteCloudProgress"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons["删除本书云端进度"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        if app.buttons["取消"].exists {
            app.buttons["取消"].tap()
        } else {
            // iOS may present this as a popover; tapping outside is its cancel action.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.1)).tap()
        }
        XCTAssertFalse(confirm.exists)
        delete.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["本书云端进度已删除，本次阅读暂停上传。"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "catalog.bookmark.")).count, 1)
        app.buttons["返回阅读"].tap()
        showReaderMenu(app)
        XCTAssertEqual(app.buttons["reader.progressButton"].value as? String, original)
    }

    @MainActor
    func testLaunchesLibrary() {
        let app = launchApp()
        let headerExists = app.staticTexts["我的书架"].waitForExistence(timeout: 10)
        let addButtonExists = app.buttons["添加书籍"].waitForExistence(timeout: 10)
        XCTAssertTrue(headerExists)
        XCTAssertTrue(addButtonExists)
    }

    @MainActor
    func testOpensNativeGlassSettingsHierarchy() {
        let app = launchApp()
        let settings = app.buttons["常规设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.staticTexts["应用主题"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["TXT 自动生成目录"].exists)
        XCTAssertTrue(app.switches["settings.keepScreenAwake"].exists)
        XCTAssertTrue(app.buttons["settings.autoPageSeconds"].exists)
        XCTAssertTrue(app.buttons["settings.progressSync"].exists)
        XCTAssertFalse(app.buttons["常规"].exists)
        XCTAssertFalse(app.buttons["阅读"].exists)

        app.buttons["settings.theme"].tap()
        XCTAssertTrue(app.staticTexts["外观"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["浅色"].exists)
        XCTAssertTrue(app.buttons["深色"].exists)
    }

    @MainActor
    func testProgressSyncUsesEditableDefaultServerAddress() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["我的书架"].waitForExistence(timeout: 5))

        app.buttons["常规设置"].tap()
        let sync = app.buttons["settings.progressSync"]
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        sync.tap()

        XCTAssertTrue(app.staticTexts["阅读进度同步"].waitForExistence(timeout: 5))
        let serverAddress = app.buttons["sync.serverAddress"]
        XCTAssertTrue(serverAddress.waitForExistence(timeout: 5))
        XCTAssertEqual(serverAddress.value as? String, "https://xunit.cc/xlib/backend")
        XCTAssertTrue(app.staticTexts["未同步"].exists)
        XCTAssertFalse(app.staticTexts["服务未配置"].exists)
        serverAddress.tap()

        let addressField = app.textFields["sync.serverAddressField"]
        XCTAssertTrue(addressField.waitForExistence(timeout: 5))
        XCTAssertEqual(addressField.value as? String, "https://xunit.cc/xlib/backend")
        XCTAssertFalse(app.buttons["sync.serverAddressSave"].exists)
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
    }

    @MainActor
    func testSyncEmailAutoSavesWhenLeavingField() {
        let app = launchApp()
        app.buttons["常规设置"].tap()
        app.buttons["settings.progressSync"].tap()

        let emailSettings = app.buttons["sync.emailSettings"]
        XCTAssertTrue(emailSettings.waitForExistence(timeout: 5))
        emailSettings.tap()

        let emailField = app.textFields["sync.emailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 100))
        emailField.typeText("autosave@example.com")

        edgeSwipeBack(in: app)
        XCTAssertTrue(emailSettings.waitForExistence(timeout: 5))
        let savedEmail = NSPredicate(format: "value == %@", "autosave@example.com")
        expectation(for: savedEmail, evaluatedWith: emailSettings)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testProgressSyncUsesStatusAndCombinedSettingsCards() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["我的书架"].waitForExistence(timeout: 5))

        app.buttons["常规设置"].tap()
        app.buttons["settings.progressSync"].tap()
        let status = app.staticTexts["同步状态"]
        let serverAddress = app.buttons["sync.serverAddress"]
        let emailSettings = app.buttons["sync.emailSettings"]
        let deviceNameSettings = app.buttons["sync.deviceNameSettings"]
        let startStop = app.buttons["sync.startStop"]
        let devices = app.buttons["sync.devices"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["最后同步"].exists)
        XCTAssertTrue(startStop.exists)
        XCTAssertTrue(serverAddress.exists)
        XCTAssertTrue(emailSettings.exists)
        XCTAssertTrue(deviceNameSettings.exists)
        XCTAssertTrue(devices.exists)
        XCTAssertLessThan(status.frame.minY, emailSettings.frame.minY)
        XCTAssertLessThan(emailSettings.frame.minY, deviceNameSettings.frame.minY)
        XCTAssertLessThan(deviceNameSettings.frame.minY, serverAddress.frame.minY)
        XCTAssertLessThan(serverAddress.frame.minY, devices.frame.minY)
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
        XCTAssertFalse(app.segmentedControls.firstMatch.exists)

        emailSettings.tap()
        XCTAssertTrue(app.staticTexts["邮箱"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["sync.emailField"].exists)
        XCTAssertFalse(app.buttons["sync.emailSave"].exists)

        edgeSwipeBack(in: app)
        XCTAssertTrue(deviceNameSettings.waitForExistence(timeout: 5))
        deviceNameSettings.tap()
        XCTAssertTrue(app.staticTexts["设备名称"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["sync.deviceNameField"].exists)
        XCTAssertFalse(app.buttons["sync.deviceNameSave"].exists)

        edgeSwipeBack(in: app)
        XCTAssertTrue(devices.waitForExistence(timeout: 5))
        devices.tap()
        XCTAssertTrue(app.staticTexts["当前设备"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testNumericSettingOpensSavePanel() {
        let app = launchApp()
        let settings = app.buttons["常规设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let interval = app.buttons["settings.autoPageSeconds"]
        XCTAssertTrue(interval.waitForExistence(timeout: 5))
        interval.tap()

        let picker = app.pickers["settings.numericPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.numericSave"].exists)
        let originalValue = interval.value as? String
        let targetValue = originalValue == "3 秒" ? "4 秒" : "3 秒"
        let pickerWheel = app.pickerWheels.firstMatch
        XCTAssertTrue(pickerWheel.exists)
        pickerWheel.adjust(toPickerWheelValue: targetValue)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertFalse(app.pickers["settings.numericPicker"].exists)
        XCTAssertTrue(app.buttons["settings.autoPageSeconds"].exists)
        XCTAssertEqual(interval.value as? String, originalValue)

        app.buttons["settings.autoPageSeconds"].tap()
        XCTAssertTrue(app.pickers["settings.numericPicker"].waitForExistence(timeout: 5))
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: targetValue)
        app.buttons["settings.numericSave"].tap()
        XCTAssertFalse(app.pickers["settings.numericPicker"].exists)
        XCTAssertTrue(app.buttons["settings.autoPageSeconds"].exists)
        XCTAssertEqual(interval.value as? String, targetValue)
    }

    @MainActor
    func testButtonFramesAcceptEdgeTaps() {
        let app = launchApp()

        let settings = app.buttons["常规设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["应用主题"].waitForExistence(timeout: 5))

        let theme = app.buttons["settings.theme"]
        XCTAssertTrue(theme.exists)
        theme.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["外观"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsPagesSupportNativeEdgeSwipeBack() {
        let app = launchApp()

        XCTAssertTrue(app.buttons["常规设置"].waitForExistence(timeout: 5))
        app.buttons["常规设置"].tap()
        XCTAssertTrue(app.buttons["settings.theme"].waitForExistence(timeout: 5))
        app.buttons["settings.theme"].tap()
        XCTAssertTrue(app.staticTexts["外观"].waitForExistence(timeout: 5))

        edgeSwipeBack(in: app)
        XCTAssertTrue(app.buttons["settings.theme"].waitForExistence(timeout: 5))

        edgeSwipeBack(in: app)
        XCTAssertTrue(app.staticTexts["我的书架"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func edgeSwipeBack(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.001, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
