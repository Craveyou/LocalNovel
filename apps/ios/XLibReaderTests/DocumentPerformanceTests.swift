import AppleShared
import Darwin
import PDFKit
import SwiftUI
import WebKit
import XCTest
@testable import XLibReader

private final class DocumentMemorySample: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Double = 0
    static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let code = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return code == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
    func sample() { let current = Self.footprint(); lock.withLock { peak = max(peak,current) } }
    var value: Double { lock.withLock { peak } }
}

@MainActor final class DocumentPerformanceTests: XCTestCase {
    private func now() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = now() + 120_000
        while now() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Document performance operation timed out")
        throw DocumentError.unsupported("performance timeout")
    }
    private func host(_ model: DocumentReaderModel) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        if let document = model.epub {
            window.rootViewController = UIHostingController(rootView: EPUBReadingSurface(document: document,model:model,settings:ReaderSettings(),link:{_ in}))
        } else {
            window.rootViewController = UIHostingController(rootView: PDFReadingSurface(document:try XCTUnwrap(model.pdf),model:model))
        }
        window.makeKeyAndVisible()
        return window
    }
    private func webView(_ view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap { self.webView($0) }.first
    }
    private func assertVisible(_ model: DocumentReaderModel, _ window: UIWindow) async throws {
        guard case .epub(_,_,_,let offset,_) = model.formal else { return }
        let web = try XCTUnwrap(webView(window))
        try await Task.sleep(for:.milliseconds(50))
        let top = try await web.evaluateJavaScript("(function(){var offset=\(offset),sum=0;for(var n of window.xlibNodes){if(sum+n.length>offset){var r=document.createRange();r.setStart(n,offset-sum);r.setEnd(n,Math.min(n.length,offset-sum+1));return r.getBoundingClientRect().top;}sum+=n.length;}return -9999;})()") as? Double
        XCTAssertEqual(try XCTUnwrap(top),16,accuracy:60,"Restored text must actually be visible, including deferred paragraphs")
        let text = model.epub!.chapters[model.formal!.unit].text as NSString
        let match = text.range(of:"DOCNEEDLE",range:NSRange(location:offset,length:text.length-offset))
        if match.location != NSNotFound {
            _ = try await web.evaluateJavaScript("window.xlibHighlight(\(match.location),\(match.length))")
            try await waitUntil { model.selection == "DOCNEEDLE" }
            _ = try await web.evaluateJavaScript("window.getSelection().removeAllRanges()")
            try await waitUntil { model.selection.isEmpty }
        }
    }
    private func measureDocument(_ name: String) async throws {
        let env = ProcessInfo.processInfo.environment
        guard let folder = env["XLIB_DOCUMENT_PERF_FIXTURES"] else { throw XCTSkip("Opt-in document performance test") }
#if targetEnvironment(simulator)
        let platform = "ios\(UIDevice.current.systemVersion)-simulator"
#else
        guard env["XLIB_DOCUMENT_PERF_DEVICE"] == "1" else { throw XCTSkip("Physical-device measurements require explicit opt-in") }
        let platform = "ios\(UIDevice.current.systemVersion)-physical"
#endif
#if DEBUG
        let configuration = "debug"
#else
        let configuration = "release"
#endif
        let runs = Int(env["XLIB_DOCUMENT_PERF_RUNS"] ?? "3") ?? 3
        guard (1...10).contains(runs) else { throw DocumentError.unsupported("Performance runs must be in 1...10") }
        // A Mac absolute path cannot be used in the phone's sandbox. The device
        // runner transfers only generated samples to this dedicated cache folder.
        let fixtures = folder == "device-cache"
            ? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "XLibDocumentPerformance")
            : URL(fileURLWithPath: folder)
        let source = fixtures.appending(path:name + (name.hasPrefix("epub") ? ".epub" : ".pdf"))
        XCTAssertTrue(FileManager.default.fileExists(atPath:source.path),"Generate fixtures before running this opt-in test")
        for run in 1...runs {
            let root = FileManager.default.temporaryDirectory.appending(path:"DocumentPerformance-" + UUID().uuidString)
            let database = testDatabase(root:root)
            let store = LibraryStore(root:root,database:database)
            let sync = ProgressSyncCoordinator(api:.unconfigured,vault:.init(load:{nil},save:{_ in},clear:{}),stateStore:SyncStateStore(database:database),connectivity:SyncConnectivityMonitor(started:false),database:database)
            let memory = DocumentMemorySample()
            let timer = DispatchSource.makeTimerSource(queue:DispatchQueue.global(qos:.utility))
            timer.schedule(deadline:.now(),repeating:.milliseconds(50));timer.setEventHandler { memory.sample() };timer.resume()
            var mainGap: Double = 0
            let pulse = Task { @MainActor in
                var previous = now()
                while !Task.isCancelled {
                    do { try await Task.sleep(for:.milliseconds(20)) } catch { return }
                    let current = now();mainGap = max(mainGap,current-previous);previous = current
                }
            }
            defer { timer.cancel();pulse.cancel();database.closeForTesting();try? FileManager.default.removeItem(at:root) }
            var result: [String:Any] = ["platform":"\(platform)-\(configuration)","sample":name,"run":run,"source_bytes":try source.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0]
            var start = now()
            let book = try await store.importBook(from:source)
            result["import_ms"] = now()-start
            var model: DocumentReaderModel? = DocumentReaderModel(book:book,store:store,sync:sync)
            start = now();await model!.open()
            XCTAssertNil(model!.error)
            var window: UIWindow? = try host(model!)
            defer { model?.close();window?.isHidden = true;window?.rootViewController = nil }
            try await waitUntil { model!.ready }
            await Task.yield() // renderer acknowledgement, not a frame-presentation signpost
            result["open_ms"] = now()-start
            XCTAssertEqual(model!.readAt.timeIntervalSince1970,0)
            let count = model!.count
            var navigation: [Double] = []
            for index in 0..<10 {
                let target = index.isMultiple(of:2) ? count-1 : 0
                let offset = model!.epub.map { $0.chapters[target].text.utf16.count/2 } ?? 0
                let locator: DocumentLocator = model!.epub?.locator(chapter:target,offset:offset) ?? .pdf(page:target,pageCount:count,y:0)
                start = now();model!.navigate(locator)
                try await waitUntil { model!.formal == locator }
                navigation.append(now()-start)
            }
            result["navigation_ms"] = navigation
            try await assertVisible(model!,window!)
            let formal = model!.formal, time = model!.readAt
            model!.query = "DOCNEEDLE";start = now();model!.search(reset:true,fromBeginning:true)
            try await waitUntil { !model!.searching }
            result["search_first_ms"] = now()-start;result["first_hits"] = model!.hits.count
            if name != "pdf-images" && name != "epub-small" { XCTAssertEqual(model!.hits.count,200) }
            let first = model!.hits.count;start = now();model!.search()
            try await waitUntil { !model!.searching }
            result["search_second_ms"] = now()-start;result["second_hits"] = model!.hits.count-first
            model!.query = "ABSENTPERFTOKEN";start = now();model!.search(reset:true,fromBeginning:true)
            try await waitUntil { !model!.searching }
            result["miss_ms"] = now()-start;XCTAssertTrue(model!.hits.isEmpty);XCTAssertTrue(model!.searchExhausted)
            // Replace an in-flight full scan; stale results must not overwrite the new query.
            model!.query = "ABSENTPERFTOKEN";model!.search(reset:true,fromBeginning:true)
            try await Task.sleep(for:.milliseconds(20));start = now()
            model!.query = "DOCNEEDLE";model!.search(reset:true,fromBeginning:true)
            try await waitUntil { !model!.searching }
            result["cancel_replace_ms"] = now()-start
            if name != "pdf-images" { XCTAssertFalse(model!.hits.isEmpty) }
            XCTAssertEqual(model!.formal,formal);XCTAssertEqual(model!.readAt,time)
            weak var closedPDF = model!.pdf
            model!.close();window!.isHidden = true;window!.rootViewController = nil;window = nil;model = nil
            start = now()
            let saved = try await store.load()
            model = DocumentReaderModel(book:try XCTUnwrap(saved.first),store:store,sync:sync)
            await model!.open();window = try host(model!);try await waitUntil { model!.ready }
            result["reopen_ms"] = now()-start
            XCTAssertEqual(model!.formal,formal);XCTAssertEqual(model!.readAt.timeIntervalSince1970,time.timeIntervalSince1970,accuracy:0.001)
            try await assertVisible(model!,window!)
            weak var lastPDF = model!.pdf
            model!.close();window!.isHidden = true;window!.rootViewController = nil;window = nil;model = nil
            let closedAt = now()
            repeat { try await Task.sleep(for:.milliseconds(100)) }
            while (closedPDF != nil || lastPDF != nil) && now()-closedAt < 5000
            result["close_settle_ms"] = now()-closedAt
            result["closed_app_mib"] = DocumentMemorySample.footprint();result["peak_app_mib"] = memory.value;result["main_gap_ms"] = mainGap
            result["pdfs_released_after_close"] = closedPDF == nil && lastPDF == nil
            let data = try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
            print("XLIB_DOC_PERF " + String(decoding:data,as:UTF8.self))
            let attachment = XCTAttachment(data:data,uniformTypeIdentifier:"public.json");attachment.name = "\(name)-\(run)";attachment.lifetime = .keepAlways;add(attachment)
        }
    }
    func testPDFSmall() async throws { try await measureDocument("pdf-small") }
    func testPDFLarge() async throws { try await measureDocument("pdf-large") }
    func testPDFImages() async throws { try await measureDocument("pdf-images") }
    func testEPUBSmall() async throws { try await measureDocument("epub-small") }
    func testEPUBLarge() async throws { try await measureDocument("epub-large") }
    func testEPUBLongChapter() async throws { try await measureDocument("epub-long-chapter") }

    func testRepeatedMixedDocumentSessions() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["XLIB_DOCUMENT_PERF_DEVICE"] == "1", env["XLIB_DOCUMENT_PERF_FIXTURES"] == "device-cache" else {
            throw XCTSkip("Opt-in physical-device mixed-session stress test")
        }
        let fixtures = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "XLibDocumentPerformance")
        let root = FileManager.default.temporaryDirectory.appending(path: "DocumentChurn-" + UUID().uuidString)
        let database = testDatabase(root: root)
        let store = LibraryStore(root: root, database: database)
        let sync = ProgressSyncCoordinator(api: .unconfigured, vault: .init(load: {nil}, save: {_ in}, clear: {}), stateStore: SyncStateStore(database: database), connectivity: SyncConnectivityMonitor(started: false), database: database)
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        let books = try await [store.importBook(from: fixtures.appending(path: "pdf-large.pdf")), store.importBook(from: fixtures.appending(path: "epub-long-chapter.epub"))]
        let started = now()
        var observations: [[String: Any]] = []
        for cycle in 0..<30 {
            let book = books[cycle % books.count]
            var model: DocumentReaderModel? = DocumentReaderModel(book: book, store: store, sync: sync)
            await model!.open()
            XCTAssertNil(model!.error)
            var window: UIWindow? = try host(model!)
            try await waitUntil { model!.ready }
            let unit = cycle.isMultiple(of: 4) ? model!.count - 1 : 0
            let offset = model!.epub.map { $0.chapters[unit].text.utf16.count / 2 } ?? 0
            let target: DocumentLocator = model!.epub?.locator(chapter: unit, offset: offset) ?? .pdf(page: unit, pageCount: model!.count, y: 0)
            model!.navigate(target)
            try await waitUntil { model!.formal == target }
            try await assertVisible(model!, window!)
            let saved = try await store.load()
            XCTAssertEqual(saved.first(where: { $0.id == book.id })?.documentLocator, target)
            weak var releasedWeb = webView(window!)
            weak var releasedPDF = model!.pdf
            model!.close()
            window!.isHidden = true
            window!.rootViewController = nil
            window = nil
            model = nil
            // Give asynchronous WebKit/PDFKit teardown a bounded settling period.
            let closed = now()
            repeat { try await Task.sleep(for: .milliseconds(100)) }
            while (releasedWeb != nil || releasedPDF != nil) && now() - closed < 5000
            XCTAssertNil(releasedWeb, "The app must release the chapter WebView when leaving the reader")
            observations.append(["cycle": cycle + 1, "format": book.format, "closed_app_mib": DocumentMemorySample.footprint(), "pdf_released": releasedPDF == nil, "web_released": releasedWeb == nil])
        }
        let result: [String: Any] = ["cycles": observations, "elapsed_ms": now() - started]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("XLIB_DOC_CHURN " + String(decoding: data, as: UTF8.self))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "mixed-document-sessions"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
