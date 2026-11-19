import AppleShared
import PDFKit
import SwiftUI
import WebKit
import XCTest
@testable import XLibReader

@MainActor final class DocumentReaderTests:XCTestCase {
    private func fixture(_ name:String) throws -> URL {try XCTUnwrap(Bundle(for:Self.self).url(forResource:name,withExtension:nil,subdirectory:"fixtures/documents"))}
    private func context(api:SyncAPIClient = .unconfigured,credentials:SyncCredentials? = nil) throws -> (URL,LocalDatabase,LibraryStore,ProgressSyncCoordinator) {
        let root = FileManager.default.temporaryDirectory.appending(path:"DocumentTests-"+UUID().uuidString)
        let database = testDatabase(root:root)
        let store = LibraryStore(root:root,database:database)
        let sync = ProgressSyncCoordinator(api:api,vault:.init(load:{credentials},save:{_ in},clear:{}),stateStore:SyncStateStore(database:database),connectivity:SyncConnectivityMonitor(started:false,initialOnline:true),database:database)
        return (root,database,store,sync)
    }
    private func host<V:View>(_ view:V) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene:scene);window.frame = scene.coordinateSpace.bounds;window.rootViewController = UIHostingController(rootView:view);window.makeKeyAndVisible();return window
    }
    private func waitUntil(file:StaticString = #filePath,line:UInt = #line,_ condition:() -> Bool) async throws {
        for _ in 0..<150 {if condition() {return};try await Task.sleep(for:.milliseconds(100))}
        XCTFail("document flow timed out",file:file,line:line);throw DocumentError.unsupported("timeout")
    }
    private func webView(_ view:UIView) -> WKWebView? {if let web = view as? WKWebView {return web};for child in view.subviews {if let web = webView(child) {return web}};return nil}
    private func waitForStyledWeb(in window: UIWindow, font: String) async throws -> WKWebView {
        for _ in 0..<150 {
            if let web = webView(window),
               let ready = try? await web.evaluateJavaScript("typeof window.xlibHighlight==='function' && getComputedStyle(document.body).fontFamily.includes('\(font)')") as? Bool,
               ready { return web }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("EPUB style and mapping did not finish loading")
        throw DocumentError.unsupported("timeout")
    }
    private func pdfView(_ view: UIView) -> PDFView? {
        if let pdf = view as? PDFView { return pdf }
        return view.subviews.lazy.compactMap { self.pdfView($0) }.first
    }
    private func searchPDF() -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x:0,y:0,width:600,height:800)).pdfData { context in
            context.beginPage()
            ("needle above" as NSString).draw(at:CGPoint(x:40,y:60),withAttributes:[.font:UIFont.systemFont(ofSize:12)])
            (String(repeating:"needle ",count:250) as NSString).draw(in:CGRect(x:40,y:600,width:500,height:150),withAttributes:[.font:UIFont.systemFont(ofSize:4)])
        }
    }
    func testPDFSearchUsesPagePositionAndFixedOriginAcrossBatchesAndPreview() async throws {
        let (root,database,store,sync) = try context()
        defer {database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        let url = root.appending(path:"search.pdf");try searchPDF().write(to:url)
        let book = try await store.importBook(from:url)
        let model = DocumentReaderModel(book:book,store:store,sync:sync)
        await model.open();defer {model.close()}
        model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
        model.userScrolled(.pdf(page:0,pageCount:1,y:0.5))
        try await waitUntil {model.formal == .pdf(page:0,pageCount:1,y:0.5)}
        let formal = model.formal, time = model.readAt
        model.query = "needle";model.search(reset:true)
        try await waitUntil {!model.searching}
        XCTAssertEqual(model.hits.count,200);XCTAssertFalse(model.searchExhausted)
        XCTAssertFalse(model.searchCanWrap)
        model.showHit(try XCTUnwrap(model.hits.first))
        model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
        model.search();try await waitUntil {!model.searching}
        XCTAssertEqual(model.hits.count,250);XCTAssertTrue(model.searchCanWrap)
        model.search(wrap:true);try await waitUntil {!model.searching}
        XCTAssertEqual(model.hits.count,251);XCTAssertEqual(model.hits.last?.offset,0)
        XCTAssertEqual(Set(model.hits).count,251);XCTAssertFalse(model.searchCanWrap)
        model.search(wrap:true);XCTAssertEqual(model.hits.count,251)
        XCTAssertEqual(model.formal,formal);XCTAssertEqual(model.readAt,time)
        model.search(reset:true,fromBeginning:true);try await waitUntil {!model.searching}
        XCTAssertEqual(model.hits.count,200)
        model.search();try await waitUntil {!model.searching}
        XCTAssertEqual(model.hits.count,251);XCTAssertTrue(model.searchExhausted)
        XCTAssertFalse(model.searchCanWrap);XCTAssertFalse(model.searchWrapped)
    }
    func testPDFSearchOffsetMatchesDisplayedAxisAtAllRotationsAndCropZoom() throws {
        let document = try XCTUnwrap(PDFDocument(data:searchPDF()))
        let page = try XCTUnwrap(document.page(at:0))
        let original = page.bounds(for:.cropBox)
        let view = PDFView(frame:CGRect(x:0,y:0,width:360,height:640))
        view.document = document;view.displayBox = .cropBox
        for rotation in [0,90,180,270] {
            page.rotation = rotation
            page.setBounds(original,for:.cropBox)
            for cropped in [false,true] {
                page.setBounds(PDFCropSettings(enabled:cropped,left:0.12,right:0.18).bounds(original:original,rotation:rotation),for:.cropBox)
                view.layoutDocumentView();view.scaleFactor = cropped ? 2 : 0.5
                let displayed = view.convert(original,from:page)
                for y in [0.0,0.1,0.5,0.9,1.0] {
                    let length = min(page.numberOfCharacters,(page.string! as NSString).length)
                    let expected = y == 0 ? 0 : (0..<length).first { index in
                        let rect = page.characterBounds(at:index)
                        return !rect.isEmpty && view.convert(rect,from:page).maxY > displayed.minY + displayed.height * y
                    } ?? length
                    XCTAssertEqual(DocumentReaderModel.pdfSearchOffset(page:page,y:y,original:original),expected,"rotation=\(rotation), crop=\(cropped), y=\(y)")
                }
            }
        }
        view.document = nil
    }
    func testEPUBSearchFromBeginningFinishesWithoutWrapAndCurrentOriginCanWrap() async throws {
        let (root,database,store,sync) = try context()
        defer {database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        let book = try await store.importBook(from:fixture("reflow.epub"))
        let model = DocumentReaderModel(book:book,store:store,sync:sync)
        await model.open();defer {model.close()}
        model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
        model.moveUnit(1);model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
        try await waitUntil {model.formal?.unit == 1}
        let formal = model.formal, time = model.readAt
        model.query = "needle";model.search(reset:true)
        try await waitUntil {!model.searching}
        XCTAssertTrue(model.searchCanWrap)
        model.search(wrap:true);try await waitUntil {!model.searching}
        XCTAssertEqual(model.hits.count,102);XCTAssertFalse(model.searchCanWrap)
        model.search(reset:true,fromBeginning:true);try await waitUntil {!model.searching}
        XCTAssertEqual(model.hits.count,102);XCTAssertTrue(model.searchExhausted)
        XCTAssertFalse(model.searchCanWrap)
        model.search(wrap:true);XCTAssertFalse(model.searchWrapped)
        XCTAssertEqual(model.formal,formal);XCTAssertEqual(model.readAt,time)
    }
    func testPDFCropGeometryClampsMarginsAndRespectsRotation() {
        let original = CGRect(x: 20, y: 30, width: 600, height: 800)
        var crop = PDFCropSettings(enabled: true, left: 0.10, right: 0.20)
        XCTAssertEqual(crop.bounds(original: original, rotation: 0), CGRect(x: 80, y: 30, width: 420, height: 800))
        XCTAssertEqual(crop.bounds(original: original, rotation: 90), CGRect(x: 20, y: 110, width: 600, height: 560))
        XCTAssertEqual(crop.bounds(original: original, rotation: 180), CGRect(x: 140, y: 30, width: 420, height: 800))
        XCTAssertEqual(crop.bounds(original: original, rotation: -90), CGRect(x: 20, y: 190, width: 600, height: 560))
        crop.left = .infinity; crop.right = -1
        XCTAssertEqual(crop.normalized().left, 0.10); XCTAssertEqual(crop.normalized().right, 0)
        crop.enabled = false
        XCTAssertEqual(crop.bounds(original: original, rotation: 90), original)
    }
    func testPDFCropIsSharedAcrossBooksAndNotPersisted() async throws {
        let (root, database, store, sync) = try context()
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        let first = try await store.importBook(from: fixture("text-rotated.pdf"))
        let second = try await store.importBook(from: fixture("text-rotated.pdf"))
        let settings = SettingsStore(database: database)
        let firstModel = DocumentReaderModel(book: first, store: store, sync: sync, cropState: settings.pdfCropState)
        let secondModel = DocumentReaderModel(book: second, store: store, sync: sync, cropState: settings.pdfCropState)
        await firstModel.open(); await secondModel.open()
        firstModel.rendererCompleted(try XCTUnwrap(firstModel.command).id, success: true)
        let crop = PDFCropSettings(enabled: true, left: 0.12, right: 0.18)
        firstModel.setPDFCrop(crop)
        XCTAssertEqual(secondModel.pdfCrop, crop)
        firstModel.close(); secondModel.close()
        let reopened = DocumentReaderModel(book: second, store: store, sync: sync, cropState: settings.pdfCropState)
        await reopened.open(); XCTAssertEqual(reopened.pdfCrop, crop); reopened.close()
        // A new app settings owner starts with defaults even with the same database.
        XCTAssertEqual(SettingsStore(database: database).pdfCropState.settings, PDFCropSettings())
    }
    func testPDFCropChangesDisplayWithoutChangingOriginalProgressOrFile() async throws {
        let (root, database, store, sync) = try context()
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        let book = try await store.importBook(from: fixture("text-rotated.pdf"))
        let file = await store.url(for: book)
        let originalData = try Data(contentsOf: file)
        let state = PDFCropState()
        let model = DocumentReaderModel(book: book, store: store, sync: sync, cropState: state)
        await model.open()
        let document = try XCTUnwrap(model.pdf)
        let page = try XCTUnwrap(document.page(at: 0))
        let originalBox = page.bounds(for: .cropBox)
        let window = try host(PDFReadingSurface(document: document, model: model))
        defer { window.isHidden = true; window.rootViewController = nil; model.close() }
        try await waitUntil { model.ready }
        let formal = model.formal, time = model.readAt
        let crop = PDFCropSettings(enabled: true, left: 0.12, right: 0.18)
        model.setPDFCrop(crop)
        try await waitUntil { page.bounds(for: .cropBox) == crop.bounds(original: originalBox, rotation: page.rotation) }
        let view = try XCTUnwrap(pdfView(window))
        let visibleWidth = view.convert(page.bounds(for: .cropBox), from: page).width
        XCTAssertEqual(visibleWidth, view.bounds.width, accuracy: 2)
        XCTAssertEqual(view.convert(page.bounds(for: .cropBox), from: page).minX, view.bounds.minX, accuracy: 2)
        XCTAssertEqual(view.convert(page.bounds(for: .cropBox), from: page).maxX, view.bounds.maxX, accuracy: 2)
        // Simulate a narrower reader surface, without issuing a navigation command.
        view.frame.size.width *= 0.75
        view.setNeedsLayout(); view.layoutIfNeeded()
        try await waitUntil { abs(view.convert(page.bounds(for: .cropBox), from: page).width - view.bounds.width) < 2 }
        XCTAssertEqual(view.convert(page.bounds(for: .cropBox), from: page).midX, view.bounds.midX, accuracy: 2)
        XCTAssertEqual(model.formal, formal); XCTAssertEqual(model.readAt, time)
        XCTAssertNil(try database.documentPosition(bookID: book.id))
        XCTAssertEqual(try Data(contentsOf: file), originalData)
        model.query = "needle"; model.search(reset: true)
        try await waitUntil { !model.searching }
        model.showHit(try XCTUnwrap(model.hits.first))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(model.temporary)
        XCTAssertEqual(view.convert(page.bounds(for: .cropBox), from: page).midX, view.bounds.midX, accuracy: 2)
        model.returnToFormal()
        let reloaded = DocumentReaderModel(book: book, store: store, sync: sync, cropState: state)
        await reloaded.open(); XCTAssertEqual(reloaded.pdfCrop, crop); reloaded.close()
        model.setPDFCrop(PDFCropSettings())
        try await waitUntil { page.bounds(for: .cropBox) == originalBox }
        XCTAssertEqual(model.formal, formal); XCTAssertEqual(model.readAt, time)
    }
    func testEPUBOfflineResourcesReflowSelectionTemporarySearchAndReopen() async throws {
        let (root,database,store,sync) = try context();defer{database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        let book = try await store.importBook(from:fixture("reflow.epub"))
        XCTAssertEqual(book.format,"epub");XCTAssertEqual(book.updatedAt.timeIntervalSince1970,0)
        let model = DocumentReaderModel(book:book,store:store,sync:sync);await model.open()
        XCTAssertNil(model.error)
        let document = try XCTUnwrap(model.epub)
        let window = try host(EPUBReadingSurface(document:document,model:model,settings:ReaderSettings(),link:{_ in}))
        defer{window.isHidden = true;window.rootViewController = nil;model.close()}
        try await waitUntil{model.ready}
        let web = try XCTUnwrap(webView(window))
        let resources = try await web.evaluateJavaScript("JSON.stringify([document.images[0].naturalWidth,window.authoredScriptExecuted===true])") as? String
        XCTAssertEqual(resources,"[1,false]")
        let time = model.readAt
        var historical = ReaderSettings();historical.fontName = "serif"
        try database.saveReaderSettings(historical)
        var larger = try database.readerSettings();larger.fontSize = 30
        XCTAssertEqual(larger.fontName,"Songti SC")
        window.rootViewController = UIHostingController(rootView:EPUBReadingSurface(document:document,model:model,settings:larger,link:{_ in}))
        model.reflow()
        let changedWeb = try await waitForStyledWeb(in: window, font: "Songti SC")
        XCTAssertEqual(model.readAt,time);XCTAssertEqual(model.formal?.unit,0)
        let family = try await changedWeb.evaluateJavaScript("getComputedStyle(document.body).fontFamily") as? String
        XCTAssertTrue(family?.contains("Songti SC") == true)
        _ = try await changedWeb.evaluateJavaScript("window.xlibHighlight(9,2)")
        try await waitUntil{model.selection == "继续"}
        XCTAssertEqual(model.readAt,time)
        model.selection = ""
        await model.addBookmark();XCTAssertEqual(model.bookmarks.count,1)
        model.query = "needle";model.search(reset:true)
        try await waitUntil{!model.searching}
        XCTAssertEqual(model.hits.count,102)
        let hit = try XCTUnwrap(model.hits.last)
        model.showHit(hit)
        try await waitUntil{model.temporary && model.current?.unit == 1 && model.selection == "needle"}
        let previewWeb = try XCTUnwrap(webView(window))
        XCTAssertFalse(previewWeb === changedWeb)
        XCTAssertEqual(model.formal?.unit,0);XCTAssertEqual(model.readAt,time)
        model.returnToFormal()
        try await waitUntil{self.webView(window) === changedWeb && model.selection.isEmpty}
        model.moveUnit(1)
        try await waitUntil{model.formal?.unit == 1 && model.readAt > time}
        XCTAssertTrue(webView(window) === previewWeb)
        let savedTime = model.readAt
        let stored = try XCTUnwrap(database.documentPosition(bookID:book.id));XCTAssertEqual(stored.locator.unit,1)
        model.close();window.isHidden = true;window.rootViewController = nil
        let restoredBooks = try await store.load()
        let restoredBook = try XCTUnwrap(restoredBooks.first)
        let reopened = DocumentReaderModel(book:restoredBook,store:store,sync:sync);await reopened.open()
        XCTAssertEqual(reopened.formal?.unit,1);XCTAssertEqual(reopened.readAt.timeIntervalSince1970,savedTime.timeIntervalSince1970,accuracy:0.001)
        reopened.close()
    }
    func testPasswordPDFRetryNavigateReopenAndOriginalEncryption() async throws {
        let (root,database,store,sync) = try context();defer{database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        let source = root.appending(path:"password.pdf")
        let plain = try XCTUnwrap(PDFDocument(url:fixture("text-rotated.pdf")))
        XCTAssertTrue(plain.write(to:source,withOptions:[.userPasswordOption:"fixture-password",.ownerPasswordOption:"fixture-owner"]))
        let book = try await store.importBook(from:source)
        let model = DocumentReaderModel(book:book,store:store,sync:sync);await model.open()
        XCTAssertTrue(model.needsPassword);XCTAssertFalse(model.ready);XCTAssertNil(try database.documentPosition(bookID:book.id))
        await model.unlock("wrong");XCTAssertTrue(model.passwordError)
        await model.unlock("fixture-password");XCTAssertFalse(model.needsPassword)
        let window = try host(PDFReadingSurface(document:try XCTUnwrap(model.pdf),model:model))
        defer{window.isHidden = true;window.rootViewController = nil;model.close()}
        try await waitUntil{model.ready}
        XCTAssertEqual(model.readAt.timeIntervalSince1970,0)
        model.moveUnit(1);try await waitUntil{model.formal?.unit == 1}
        let time = model.readAt;XCTAssertGreaterThan(time.timeIntervalSince1970,0)
        model.close();window.isHidden = true;window.rootViewController = nil
        let savedBooks = try await store.load()
        let saved = try XCTUnwrap(savedBooks.first)
        let reopened = DocumentReaderModel(book:saved,store:store,sync:sync);await reopened.open()
        XCTAssertTrue(reopened.needsPassword)
        await reopened.unlock("fixture-password")
        XCTAssertEqual(reopened.formal?.unit,1);XCTAssertEqual(reopened.readAt.timeIntervalSince1970,time.timeIntervalSince1970,accuracy:0.001)
        let file = await store.url(for:book);XCTAssertTrue(try XCTUnwrap(PDFDocument(url:file)).isLocked)
        reopened.close()
    }
    func testTypedDatabaseIdentityBookmarksAndDeletionStaySeparateFromTXT() async throws {
        let (root,database,store,_) = try context();defer{database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        let source = root.appending(path:"text.txt");try Data("你好😀旧版进度".utf8).write(to:source)
        let txt = try await store.importBook(from:source)
        try await store.saveProgress(bookID:txt.id,offset:6,updatedAt:Date(timeIntervalSince1970:100))
        _ = try await store.addBookmark(bookID:txt.id,offset:6,excerpt:"TXT")
        let pdf = try await store.importBook(from:fixture("text-rotated.pdf"))
        let key = try await store.documentIdentity(book:pdf)
        let locator = DocumentLocator.pdf(page:1,pageCount:2,y:0.5)
        try database.saveDocumentPosition(bookID:pdf.id,hash:key.bookHash,locator:locator,readAt:Date(timeIntervalSince1970:200))
        try database.addDocumentBookmark(bookID:pdf.id,locator:locator,excerpt:"PDF")
        XCTAssertThrowsError(try database.addDocumentBookmark(bookID:pdf.id,locator:locator,excerpt:"duplicate"))
        let books = try database.loadBooks();XCTAssertEqual(books.first?.id,pdf.id);XCTAssertEqual(books.first?.progress,0.75)
        XCTAssertEqual(books.last?.offset,6);XCTAssertEqual(try database.bookmarks(bookID:txt.id).count,1)
        try database.deleteBooks(ids:[pdf.id]);XCTAssertNil(try database.documentPosition(bookID:pdf.id));XCTAssertTrue(try database.documentBookmarks(bookID:pdf.id).isEmpty)
        XCTAssertEqual(try database.loadBooks().map(\.id),[txt.id])
    }

    func testBackgroundOpenAndInterruptedNavigationKeepTheLastRenderedPosition() async throws {
        let (root,database,store,sync) = try context()
        defer{database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        let book = try await store.importBook(from:fixture("text-rotated.pdf"))
        let model = DocumentReaderModel(book:book,store:store,sync:sync)
        model.setActive(false);await model.open()
        XCTAssertNotNil(model.pdf);XCTAssertNotNil(model.command)
        model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
        model.setActive(true)
        let original = try XCTUnwrap(model.formal)
        model.moveUnit(1)
        let interrupted = try XCTUnwrap(model.command).id
        model.setActive(false)
        model.rendererCompleted(interrupted,success:true)
        XCTAssertEqual(model.formal,original);XCTAssertEqual(model.current,original)
        XCTAssertNil(try database.documentPosition(bookID:book.id))
        model.setActive(true);model.moveUnit(1)
        let cancelled = try XCTUnwrap(model.command).id
        model.navigate(original)
        model.rendererCompleted(cancelled,success:true)
        XCTAssertEqual(model.current,original);XCTAssertEqual(model.readAt.timeIntervalSince1970,0)
        model.moveUnit(1)
        model.rendererCompleted(try XCTUnwrap(model.command).id,success:false)
        XCTAssertEqual(model.current,original);XCTAssertNotNil(model.openFailure)
        model.close();await model.open()
        XCTAssertNil(model.pdf);XCTAssertNil(model.command)
    }

    func testInvalidReplacementStopsSearchAndRetryInitializesItsOwnCursor() async throws {
        let (root,database,store,sync) = try context()
        defer{database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        let book = try await store.importBook(from:fixture("reflow.epub"))
        let model = DocumentReaderModel(book:book,store:store,sync:sync)
        await model.open();defer{model.close()}
        model.query = "needle";model.search(reset:true)
        model.query = "x";model.search(reset:true)
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertFalse(model.searching);XCTAssertTrue(model.hits.isEmpty)
        XCTAssertNotNil(model.error)
        model.query = "继续";model.search()
        try await waitUntil{!model.searching}
        XCTAssertFalse(model.hits.isEmpty)
        XCTAssertTrue(model.hits.allSatisfy{$0.excerpt.contains("继续")})
        XCTAssertEqual(model.readAt.timeIntervalSince1970,0)
    }

    func testChapterCacheIsBoundedAndStyleInvalidationReleasesDelegates() async throws {
        let (root,database,store,sync) = try context()
        defer{database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        let book = try await store.importBook(from:fixture("reflow.epub"))
        let model = DocumentReaderModel(book:book,store:store,sync:sync);await model.open()
        let document = try XCTUnwrap(model.epub)
        let surface = EPUBReadingSurface(document:document,model:model,settings:ReaderSettings(),link:{_ in})
        let coordinator = surface.makeCoordinator()
        let container = UIView(frame:CGRect(x:0,y:0,width:360,height:640))
        // Exercise the cache directly in addition to the mounted reader integration above.
        let first = coordinator.makePage(chapter:0,in:container,background:.white)
        let second = coordinator.makePage(chapter:1,in:container,background:.white)
        coordinator.activate(first,in:container)
        XCTAssertTrue(coordinator.web === first.web)
        XCTAssertNil(second.web.superview)
        XCTAssertEqual(coordinator.pages.count,2)
        _ = coordinator.makePage(chapter:0,in:container,background:.white)
        XCTAssertEqual(coordinator.pages.count,2)
        XCTAssertNil(second.web.navigationDelegate)
        coordinator.invalidateStyle("dark")
        XCTAssertTrue(coordinator.pages.isEmpty);XCTAssertNil(coordinator.web)
        XCTAssertNil(first.web.navigationDelegate)
        model.close()
    }

    func testOpenFailureCanBeRetriedWithoutChangingSavedProgress() async throws {
        let (root,database,store,sync) = try context()
        defer{database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        let book = try await store.importBook(from:fixture("text-rotated.pdf"))
        let url = await store.url(for:book)
        let original = try Data(contentsOf:url)
        try FileManager.default.removeItem(at:url)
        let model = DocumentReaderModel(book:book,store:store,sync:sync);await model.open()
        XCTAssertNotNil(model.openFailure);XCTAssertFalse(model.loading)
        try original.write(to:url);await model.open()
        XCTAssertNil(model.openFailure);XCTAssertNotNil(model.command)
        XCTAssertEqual(model.readAt.timeIntervalSince1970,0)
        model.close()
    }

    func testEPUBWidthChangeRestoresContentAnchorWithoutCreatingReadingTime() async throws {
        let (root,database,store,sync) = try context()
        defer{database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        let book = try await store.importBook(from:fixture("reflow.epub"))
        let model = DocumentReaderModel(book:book,store:store,sync:sync);await model.open()
        let document = try XCTUnwrap(model.epub)
        let window = try host(EPUBReadingSurface(document:document,model:model,settings:ReaderSettings(),link:{_ in}))
        defer{window.isHidden = true;window.rootViewController = nil;model.close()}
        try await waitUntil{model.ready}
        let target = document.locator(chapter:0,offset:800)
        model.navigate(target);try await waitUntil{model.formal == target}
        let time = model.readAt, command = model.command?.id
        window.frame = CGRect(x:0,y:0,width:600,height:500)
        try await waitUntil{model.command?.id != command}
        let web = try XCTUnwrap(webView(window))
        guard case .epub(_,_,_,let offset,_) = target else { return XCTFail("Expected EPUB anchor") }
        var visible = false
        for _ in 0..<30 {
            let top = try await web.evaluateJavaScript("(function(){var sum=0;for(var n of window.xlibNodes){if(sum+n.length>\(offset)){var r=document.createRange();r.setStart(n,\(offset)-sum);r.setEnd(n,Math.min(n.length,\(offset)-sum+1));return r.getBoundingClientRect().top;}sum+=n.length;}return -9999;})()") as? Double
            if let top, abs(top-16)<60 {visible = true;break}
            try await Task.sleep(for:.milliseconds(50))
        }
        XCTAssertTrue(visible);XCTAssertEqual(model.formal,target);XCTAssertEqual(model.readAt,time)
    }

    func testPDFAndEPUBRemoteChoicePreviewDeletionPauseAndReopen() async throws {
        for name in ["text-rotated.pdf","reflow.epub"] {
            let server = DocumentSyncTestServer()
            let credentials = SyncCredentials(token:"test-document-token",userID:UUID(),email:"reader@example.com",device:.init(deviceId:UUID(),deviceName:"Test iPhone",platform:"ios"))
            let (root,database,store,sync) = try context(api:await server.client(),credentials:credentials)
            defer{database.closeForTesting();try? FileManager.default.removeItem(at:root)}
            let book = try await store.importBook(from:fixture(name))
            let key = try await store.documentIdentity(book:book)
            await sync.start()
            let model = DocumentReaderModel(book:book,store:store,sync:sync);await model.open()
            let cloud:DocumentLocator = model.epub?.locator(chapter:1,offset:3) ?? .pdf(page:1,pageCount:2,y:0.25)
            let remote = DocumentRemoteState(bookHash:key.bookHash,fileSize:key.fileSize,locator:cloud,progress:cloud.progress,readAtMs:1_700_000_000_000,version:"remote",device:.init(deviceId:UUID(),deviceName:"Other device",platform:"android"))
            await server.seed(remote)
            model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
            try await waitUntil{model.remote != nil}
            XCTAssertEqual(model.readAt.timeIntervalSince1970,0)
            model.acceptRemote();model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
            try await waitUntil{model.formal == cloud && !model.preparingSync}
            XCTAssertEqual(FormalReadingProgress.milliseconds(model.readAt),remote.readAtMs)
            let initialUploads = await server.uploadCount
            XCTAssertEqual(initialUploads,0)
            let target:DocumentLocator = model.epub?.locator(chapter:0,offset:8) ?? .pdf(page:0,pageCount:2,y:0.5)
            model.navigate(target,preview:true);await model.compare()
            XCTAssertEqual(model.formal,cloud);XCTAssertEqual(FormalReadingProgress.milliseconds(model.readAt),remote.readAtMs)
            model.returnToFormal()
            try await waitUntil{!model.preparingSync}
            model.navigate(target);model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
            try await waitUntil{model.formal == target && !model.preparingSync}
            let uploaded = await server.uploadCount
            XCTAssertEqual(uploaded,1)
            await model.deleteCloud()
            let deleted = await server.stored
            XCTAssertNil(deleted)
            model.navigate(cloud);model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
            try await waitUntil{model.formal == cloud && !model.preparingSync}
            await model.compare()
            let paused = await server.uploadCount
            XCTAssertEqual(paused,uploaded)
            XCTAssertEqual(model.bookmarks.count,0)
            model.close()
            let books = try await store.load()
            let reopened = DocumentReaderModel(book:try XCTUnwrap(books.first),store:store,sync:sync)
            await reopened.open();reopened.rendererCompleted(try XCTUnwrap(reopened.command).id,success:true)
            try await waitUntil{reopened.syncMessage == "同步比较完成"}
            let resumed = await server.uploadCount
            XCTAssertEqual(resumed,uploaded+1)
            XCTAssertEqual(reopened.formal,cloud)
            reopened.close()
        }
    }
}

private actor DocumentSyncTestServer {
    private(set) var stored:DocumentRemoteState?
    private(set) var uploadCount = 0
    func seed(_ value:DocumentRemoteState) { stored = value }
    private func pull() -> DocumentPullResponse { .init(items:stored.map{[$0]} ?? []) }
    private func upload(_ request:DocumentSyncRequest) throws -> DocumentSyncResponse {
        let item = try XCTUnwrap(request.items.first)
        uploadCount += 1
        let state = DocumentRemoteState(bookHash:item.bookHash,fileSize:item.fileSize,locator:item.locator,progress:item.locator.progress,readAtMs:item.readAtMs,version:"upload-\(uploadCount)",device:.init(deviceId:UUID(),deviceName:"Test iPhone",platform:"ios"))
        stored = state
        return .init(results:[.init(state:state)])
    }
    private func delete() { stored = nil }
    func client() -> SyncAPIClient {
        SyncAPIClient(isConfigured:true,
            startSync:{_ in throw SyncAPIError.notConfigured},
            pullProgress:{_ in .init(serverTimeMs:0,items:[])},
            syncProgress:{_,_ in throw SyncAPIError.invalidResponse},
            deleteBookProgress:{_,_ in},listDevices:{_ in []},deleteDevice:{_,_ in},health:{true},
            pullDocument:{key,_ in await self.pull()},
            syncDocument:{request,_ in try await self.upload(request)},
            deleteDocument:{_,_ in await self.delete()})
    }
}
