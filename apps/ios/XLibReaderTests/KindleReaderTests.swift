import AppleShared
import SwiftUI
import WebKit
import XCTest
@testable import XLibReader

@MainActor final class KindleReaderTests: XCTestCase {
    private func fixture(_ name:String) throws -> URL {
        try XCTUnwrap(Bundle(for:Self.self).url(forResource:name,withExtension:nil,subdirectory:"fixtures/documents"))
    }
    private func wait(_ condition:() -> Bool) async throws {
        for _ in 0..<150 { if condition() {return};try await Task.sleep(for:.milliseconds(100)) }
        throw DocumentError.unsupported("Kindle test timed out")
    }
    private func web(in view:UIView) -> WKWebView? {
        if let web = view as? WKWebView {return web}
        return view.subviews.lazy.compactMap{self.web(in:$0)}.first
    }
    func testContentIdentificationAliasesAndRejectedDRMKeepExistingLibraryUntouched() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path:"KindleImport-\(UUID())")
        let database = testDatabase(root:root),store = LibraryStore(root:root,database:database)
        defer {database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        let bytes = try Data(contentsOf:fixture("kindle-mobi6.mobi"))
        let cache = ComicCoverCache()
        let first = try await cache.cover(url:fixture("kindle-mobi6.mobi"),kindle:true)
        XCTAssertLessThanOrEqual(max(first.image.width,first.image.height),192)
        await cache.removeAll()
        let rebuilt = try await cache.cover(url:fixture("kindle-mobi6.mobi"),kindle:true)
        XCTAssertEqual(rebuilt.image.width,first.image.width)
        var ids:[UUID] = []
        for name in ["renamed.mobi","renamed.azw","renamed.azw3","renamed.data","renamed.txt"] {
            let source = root.appending(path:name);try bytes.write(to:source)
            let book = try await store.importBook(from:source)
            XCTAssertEqual(book.format,"kindle");ids.append(book.id)
            let copy = await store.url(for:book)
            XCTAssertEqual(try Data(contentsOf:copy),bytes)
        }
        let before = try database.loadBooks().map(\.id)
        XCTAssertEqual(Set(before),Set(ids))
        let files = try FileManager.default.contentsOfDirectory(atPath:root.appending(path:"Books").path).sorted()
        var drm = bytes
        let headerStart = (78..<82).reduce(0) {($0 << 8) | Int(bytes[$1])}
        drm[headerStart+12] = 0;drm[headerStart+13] = 2
        for (index,invalid) in [drm,Data(bytes.prefix(100))].enumerated() {
            let source = root.appending(path:"rejected-\(index).azw3");try invalid.write(to:source)
            do { _ = try await store.importBook(from:source);XCTFail("Rejected Kindle was published") }
            catch { if index == 0 {XCTAssertTrue(error.localizedDescription.contains("DRM"))} }
            XCTAssertEqual(try database.loadBooks().map(\.id),before)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.appending(path:"Books").path).sorted(),files)
            XCTAssertEqual(try Data(contentsOf:source),invalid)
        }
    }
    func testReadableFormatsRenderCanonicalDOMOfflineImagesSelectionAndReflowWithoutReadingEvents() async throws {
        for name in ["kindle-mobi6.mobi","kindle-palmdoc.azw","kindle-huff.mobi","kindle-kf8.azw3","kindle-mixed.mobi","kindle-long.mobi"] {
            let root = FileManager.default.temporaryDirectory.appending(path:"KindleRender-\(UUID())")
            let database = testDatabase(root:root),store = LibraryStore(root:root,database:database)
            defer {database.closeForTesting();try? FileManager.default.removeItem(at:root)}
            let book = try await store.importBook(from:fixture(name))
            XCTAssertEqual(book.format,"kindle")
            let sync = ProgressSyncCoordinator(api:.unconfigured,vault:.init(load:{nil},save:{_ in},clear:{}),stateStore:SyncStateStore(database:database),connectivity:SyncConnectivityMonitor(started:false,initialOnline:false),database:database)
            let model = DocumentReaderModel(book:book,store:store,sync:sync)
            await model.open();defer {model.close()}
            XCTAssertNil(model.openFailure,name)
            let document = try XCTUnwrap(model.reflowDocument)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene:scene);window.frame = scene.coordinateSpace.bounds
            window.rootViewController = UIHostingController(rootView:EPUBReadingSurface(document:document,model:model,settings:ReaderSettings(),link:{_ in}))
            window.makeKeyAndVisible();defer {window.isHidden = true;window.rootViewController = nil}
            try await wait {model.ready}
            let formal = model.formal,time = model.readAt
            for unit in document.chapters.indices {
                model.navigate(document.locator(chapter:unit,offset:0),preview:true)
                let command = try XCTUnwrap(model.command).id
                try await wait {model.ready && !model.rendering && model.command?.id == command && self.web(in:window) != nil}
                var text:String?
                for _ in 0..<100 {
                    text = try? await self.web(in:window)?.evaluateJavaScript("window.xlibNodes?.map(n=>n.data).join('')") as? String
                    if text == document.chapters[unit].text {break}
                    try await Task.sleep(for:.milliseconds(50))
                }
                let web = try XCTUnwrap(web(in:window))
                XCTAssertEqual(text,document.chapters[unit].text,name)
                if document.chapters[unit].text.contains("😀") {
                    let offset = (document.chapters[unit].text as NSString).range(of:"😀").location
                    let selected = try await web.evaluateJavaScript("window.xlibHighlight(\(offset),2);String(window.getSelection())") as? String
                    XCTAssertEqual(selected,"😀",name)
                    try await wait {model.selection == "😀"}
                    model.selection = ""
                }
                if document.chapters[unit].text.contains("\u{fffc}") {
                    var loaded = false
                    for _ in 0..<50 {
                        loaded = (try? await web.evaluateJavaScript("Array.from(document.images).every(i=>i.complete&&i.naturalWidth>0)") as? Bool) == true
                        if loaded {break};try await Task.sleep(for:.milliseconds(50))
                    }
                    XCTAssertTrue(loaded,name)
                }
            }
            model.reflow()
            try await Task.sleep(for:.milliseconds(150))
            XCTAssertEqual(model.formal,formal,name);XCTAssertEqual(model.readAt,time,name)
            let saved = try await store.documentPosition(bookID:book.id)
            XCTAssertNil(saved,name)
        }
    }
    func testKindleSearchPreviewBookmarksFormalRestoreAndMissingSourceProtection() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path:"KindleFlow-\(UUID())")
        let database = testDatabase(root:root),store = LibraryStore(root:root,database:database)
        defer {database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        let book = try await store.importBook(from:fixture("kindle-long.mobi"))
        let sync = ProgressSyncCoordinator(api:.unconfigured,vault:.init(load:{nil},save:{_ in},clear:{}),stateStore:SyncStateStore(database:database),connectivity:SyncConnectivityMonitor(started:false,initialOnline:false),database:database)
        let model = DocumentReaderModel(book:book,store:store,sync:sync)
        await model.open();defer {model.close()}
        model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
        let document = try XCTUnwrap(model.kindle),target = document.locator(chapter:1,offset:5)
        model.navigate(target);model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
        try await wait {model.formal == target}
        let time = model.readAt
        let added = await model.addBookmark(),duplicate = await model.addBookmark()
        XCTAssertTrue(added);XCTAssertFalse(duplicate);model.error = nil
        model.query = "NEEDLE";model.search(reset:true,fromBeginning:true)
        try await wait {!model.searching};XCTAssertEqual(model.hits.count,200)
        model.search();try await wait {!model.searching};XCTAssertEqual(model.hits.count,400)
        model.search();try await wait {!model.searching};XCTAssertEqual(model.hits.count,450)
        XCTAssertTrue(model.searchExhausted);XCTAssertFalse(model.searchCanWrap)
        model.showHit(try XCTUnwrap(model.hits.last));model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
        XCTAssertTrue(model.temporary);XCTAssertEqual(model.formal,target);XCTAssertEqual(model.readAt,time)
        model.returnToFormal();model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
        model.close()
        let reopened = DocumentReaderModel(book:book,store:store,sync:sync)
        await reopened.open();defer {reopened.close()}
        XCTAssertEqual(reopened.formal,target);XCTAssertEqual(reopened.readAt.timeIntervalSince1970,time.timeIntervalSince1970,accuracy:0.001)
        XCTAssertEqual(reopened.bookmarks.count,1)
        await reopened.removeBookmark(try XCTUnwrap(reopened.bookmarks.first));XCTAssertTrue(reopened.bookmarks.isEmpty)
        let url = await store.url(for:book)
        try FileManager.default.removeItem(at:url)
        await reopened.open();XCTAssertNotNil(reopened.openFailure)
        let saved = try await store.documentPosition(bookID:book.id)
        XCTAssertEqual(saved?.locator,target)
    }

    func testKindleBackgroundAndStaleNavigationCallbacksCannotCommitUnrenderedProgress() async throws {
        for name in ["kindle-long.mobi","kindle-mixed.mobi"] {
            let root = FileManager.default.temporaryDirectory.appending(path:"KindleLifecycle-\(UUID())")
            let database = testDatabase(root:root),store = LibraryStore(root:root,database:database)
            defer {database.closeForTesting();try? FileManager.default.removeItem(at:root)}
            let book = try await store.importBook(from:fixture(name))
            let sync = ProgressSyncCoordinator(api:.unconfigured,vault:.init(load:{nil},save:{_ in},clear:{}),stateStore:SyncStateStore(database:database),connectivity:SyncConnectivityMonitor(started:false,initialOnline:false),database:database)
            let model = DocumentReaderModel(book:book,store:store,sync:sync)
            await model.open();defer {model.close()}
            model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
            let document = try XCTUnwrap(model.kindle),original = try XCTUnwrap(model.formal)
            let target = document.locator(chapter:0,offset:5)
            model.navigate(target)
            let interrupted = try XCTUnwrap(model.command).id
            model.setActive(false)
            model.rendererCompleted(interrupted,success:true)
            XCTAssertEqual(model.formal,original,name)
            XCTAssertEqual(model.readAt.timeIntervalSince1970,0,name)
            XCTAssertNil(try database.documentPosition(bookID:book.id),name)
            model.setActive(true)
            model.navigate(target)
            let superseded = try XCTUnwrap(model.command).id
            model.navigate(original)
            model.rendererCompleted(superseded,success:true)
            XCTAssertEqual(model.formal,original,name)
            model.rendererCompleted(try XCTUnwrap(model.command).id,success:true)
            model.navigate(target)
            let closed = try XCTUnwrap(model.command).id
            model.close();model.rendererCompleted(closed,success:true)
            XCTAssertEqual(model.readAt.timeIntervalSince1970,0,name)
            XCTAssertNil(try database.documentPosition(bookID:book.id),name)
        }
    }

    func testKindleViewportWidthChangeRestoresCanonicalAnchorWithoutCreatingReadingTime() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path:"KindleWidth-\(UUID())")
        let database = testDatabase(root:root),store = LibraryStore(root:root,database:database)
        defer {database.closeForTesting();try? FileManager.default.removeItem(at:root)}
        let book = try await store.importBook(from:fixture("kindle-long.mobi"))
        let sync = ProgressSyncCoordinator(api:.unconfigured,vault:.init(load:{nil},save:{_ in},clear:{}),stateStore:SyncStateStore(database:database),connectivity:SyncConnectivityMonitor(started:false,initialOnline:false),database:database)
        let model = DocumentReaderModel(book:book,store:store,sync:sync)
        await model.open();defer {model.close()}
        let document = try XCTUnwrap(model.reflowDocument)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene:scene);window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView:EPUBReadingSurface(document:document,model:model,settings:ReaderSettings(),link:{_ in}))
        window.makeKeyAndVisible();defer {window.isHidden = true;window.rootViewController = nil}
        try await wait {model.ready && !model.rendering}
        // Unit zero is the six-character TOC; use the long body, not a
        // clamped end-of-short-unit anchor that cannot scroll to the top.
        let target = document.locator(chapter:document.chapters.count-1,offset:800)
        model.navigate(target);try await wait {model.formal == target && !model.rendering}
        let time = model.readAt,command = model.command?.id
        let offset = try XCTUnwrap(document.localOffset(for:target))
        XCTAssertEqual(offset,800)
        window.frame = CGRect(x:0,y:0,width:600,height:500)
        try await wait {model.command?.id != command && !model.rendering}
        let web = try XCTUnwrap(web(in:window))
        var visible = false
        for _ in 0..<50 {
            let top = try await web.evaluateJavaScript("(function(){var sum=0;for(var n of window.xlibNodes){if(sum+n.length>\(offset)){var r=document.createRange();r.setStart(n,\(offset)-sum);r.setEnd(n,Math.min(n.length,\(offset)-sum+1));return r.getBoundingClientRect().top;}sum+=n.length;}return -9999;})()") as? Double
            if let top,abs(top-16)<60 {visible = true;break}
            try await Task.sleep(for:.milliseconds(50))
        }
        XCTAssertTrue(visible)
        XCTAssertEqual(model.formal,target);XCTAssertEqual(model.readAt,time)
        let saved = try await store.documentPosition(bookID:book.id)
        XCTAssertEqual(saved?.locator,target)
    }
}
