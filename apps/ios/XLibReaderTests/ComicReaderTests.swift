import AppleShared
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import XLibReader

@MainActor final class ComicReaderTests: XCTestCase {
    private func storedZIP(_ files: [(String, Data)]) -> Data {
        func put<T: FixedWidthInteger>(_ value: T, into data: inout Data) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        var output = Data(), central = Data()
        for (path, data) in files {
            let name = Data(path.utf8), offset = UInt32(output.count)
            var crc: UInt32 = 0xffffffff
            for byte in data {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb88320 }
            }
            crc ^= 0xffffffff
            put(UInt32(0x04034b50), into: &output); put(UInt16(20), into: &output)
            put(UInt16(0x800), into: &output); put(UInt16(0), into: &output); put(UInt32(0), into: &output)
            put(crc, into: &output); put(UInt32(data.count), into: &output); put(UInt32(data.count), into: &output)
            put(UInt16(name.count), into: &output); put(UInt16(0), into: &output)
            output.append(name); output.append(data)
            put(UInt32(0x02014b50), into: &central); put(UInt16(0x314), into: &central); put(UInt16(20), into: &central)
            put(UInt16(0x800), into: &central); put(UInt16(0), into: &central); put(UInt32(0), into: &central)
            put(crc, into: &central); put(UInt32(data.count), into: &central); put(UInt32(data.count), into: &central)
            put(UInt16(name.count), into: &central); put(UInt16(0), into: &central); put(UInt16(0), into: &central)
            put(UInt32(0), into: &central); put(UInt32(0o100644 << 16), into: &central); put(offset, into: &central)
            central.append(name)
        }
        let offset = UInt32(output.count)
        output.append(central)
        put(UInt32(0x06054b50), into: &output); put(UInt32(0), into: &output)
        put(UInt16(files.count), into: &output); put(UInt16(files.count), into: &output)
        put(UInt32(central.count), into: &output); put(offset, into: &output); put(UInt16(0), into: &output)
        return output
    }

    func testJPEGOrientationAndColorSurviveReadingAndCoverSampling() async throws {
        let (root, database, store, _) = try context()
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 80, bitsPerComponent: 8, bytesPerRow: 160,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 80))
        let jpeg = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = root.appending(path: "orientation.cbz")
        let bytes = storedZIP([("1.jpg", jpeg as Data)])
        try bytes.write(to: source)
        let book = try await store.importBook(from: source)
        let document = try ComicDocument(url: source)
        let bitmap = try document.bitmap(page: 0)
        XCTAssertEqual(bitmap.naturalSize, CGSize(width: 80, height: 40))
        XCTAssertEqual(bitmap.image.width, 80); XCTAssertEqual(bitmap.image.height, 40)
        let cache = ComicCoverCache()
        let first = try await cache.cover(url: source)
        let hit = try await cache.cover(url: source)
        XCTAssertTrue(first.image === hit.image)
        XCTAssertLessThanOrEqual(max(first.image.width, first.image.height), 192)
        await cache.removeAll()
        let rebuilt = try await cache.cover(url: source)
        XCTAssertEqual(rebuilt.naturalSize, first.naturalSize)
        // Read one displayed pixel in a known color space; no dark-theme inversion.
        let pixel = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        pixel.draw(rebuilt.image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let rgba = try XCTUnwrap(pixel.data).assumingMemoryBound(to: UInt8.self)
        // JPEG is lossy and ImageIO performs color-space conversion. Check the
        // intended dominant red rather than requiring byte-exact components.
        XCTAssertGreaterThan(rgba[0], 200); XCTAssertLessThan(rgba[1], 80); XCTAssertLessThan(rgba[2], 80)
        XCTAssertNil(try database.documentPosition(bookID: book.id))
        XCTAssertEqual(try database.loadBooks().first?.updatedAt.timeIntervalSince1970, 0)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    func testBadLastImageAndUnsupportedPageDoNotPublishPartialBook() async throws {
        let (root, database, store, _) = try context()
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        let original = try await store.importBook(from: fixture())
        let archive = try ComicArchive(url: fixture())
        let good = try archive.read("pages/1.png")
        let cases: [[(String, Data)]] = [
            [("1.png", good), ("2.png", Data(good.prefix(20)))],
            [("1.png", good), ("2.jpg", good)],
            [("1.png", good), ("2.webp", Data("RIFFxxxxWEBP".utf8))]
        ]
        for (index, files) in cases.enumerated() {
            let source = root.appending(path: "bad-\(index).cbz")
            let bytes = storedZIP(files); try bytes.write(to: source)
            do { _ = try await store.importBook(from: source); XCTFail("Invalid page was silently skipped") } catch {}
            XCTAssertEqual(try Data(contentsOf: source), bytes)
            XCTAssertEqual(try database.loadBooks().map(\.id), [original.id])
        }
        let imported = await store.url(for: original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Books").path), [imported.lastPathComponent])
    }
    func testUnRARLicenseIsPackagedInApplication() throws {
        let resource = try XCTUnwrap(Bundle.main.url(forResource: "UnRAR-LICENSE", withExtension: "txt"))
        let notice = try String(contentsOf: resource, encoding: .utf8)
        XCTAssertTrue(notice.contains("UnRAR 7.23"))
        XCTAssertTrue(notice.contains("cannot be"))
        XCTAssertTrue(notice.contains("RAR (WinRAR) compatible archiver"))
        XCTAssertTrue(notice.contains("Intel Corporation"))
    }
    private func fixture() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "comic-basic.cbz", withExtension: nil, subdirectory: "fixtures/documents"))
    }
    private func context() throws -> (URL, LocalDatabase, LibraryStore, ProgressSyncCoordinator) {
        let root = FileManager.default.temporaryDirectory.appending(path: "ComicTests-" + UUID().uuidString)
        let database = testDatabase(root: root)
        let store = LibraryStore(root: root, database: database)
        let sync = ProgressSyncCoordinator(api: .unconfigured, vault: .init(load: { nil }, save: { _ in }, clear: {}),
            stateStore: SyncStateStore(database: database), connectivity: SyncConnectivityMonitor(started: false), database: database)
        return (root, database, store, sync)
    }
    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<100 { if condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("漫画导航未完成")
    }
    func testImportNavigationBookmarkPreviewAndReopenPreserveNaturalCoordinates() async throws {
        let (root, database, store, sync) = try context()
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        let book = try await store.importBook(from: fixture())
        XCTAssertEqual(book.format, "cbz"); XCTAssertEqual(book.updatedAt.timeIntervalSince1970, 0)
        let model = DocumentReaderModel(book: book, store: store, sync: sync)
        await model.open()
        XCTAssertNil(model.openFailure)
        XCTAssertEqual(model.count, 24)
        XCTAssertEqual(model.readAt.timeIntervalSince1970, 0)
        XCTAssertNil(try database.documentPosition(bookID: book.id))
        model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        let comic = try XCTUnwrap(model.comic)
        for page in 1...20 {
            model.moveUnit(1)
            model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
            try await settle { model.formal?.unit == page }
        }
        for page in (0..<20).reversed() {
            model.moveUnit(-1)
            model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
            try await settle { model.formal?.unit == page }
        }
        let longPosition = try comic.manifest.locator(format: "cbz", page: 10, y: 0.234567)
        model.navigate(longPosition)
        model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        try await settle { model.formal == longPosition }
        await model.addBookmark()
        XCTAssertEqual(model.bookmarks.first?.locator, longPosition)
        let time = model.readAt
        model.navigate(try comic.manifest.locator(format: "cbz", page: 4), preview: true)
        model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        XCTAssertEqual(model.formal, longPosition); XCTAssertEqual(model.readAt, time)
        model.returnToFormal(); model.close()
        let reopened = DocumentReaderModel(book: book, store: store, sync: sync)
        await reopened.open(); defer { reopened.close() }
        XCTAssertEqual(reopened.current, longPosition)
        XCTAssertEqual(reopened.readAt.timeIntervalSince1970, time.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(reopened.bookmarks.count, 1)
        reopened.query = "needle"; reopened.search()
        XCTAssertEqual(reopened.error, "图片漫画暂不支持正文搜索/复制")
    }

    func testRejectedImportLeavesNoBookOrTemporaryCopyAndContentWinsUnknownExtension() async throws {
        let (root, database, store, _) = try context()
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        _ = try await store.load()
        let broken = root.appending(path: "broken.cbz")
        try Data([0x50,0x4b,3,4,0,0,0,0]).write(to: broken)
        do { _ = try await store.importBook(from: broken); XCTFail("损坏归档不能入库") } catch {}
        XCTAssertTrue(try database.loadBooks().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Books").path).isEmpty)
        let renamed = root.appending(path: "真实漫画.data")
        try FileManager.default.copyItem(at: fixture(), to: renamed)
        let imported = try await store.importBook(from: renamed)
        XCTAssertEqual(imported.format, "cbz")
        let mismatch = root.appending(path: "错误后缀.cbr")
        try FileManager.default.copyItem(at: fixture(), to: mismatch)
        do { _ = try await store.importBook(from: mismatch); XCTFail("容器与明确格式冲突必须拒绝") } catch {}
        XCTAssertEqual(try database.loadBooks().count, 1)
    }

    func testProgressSelectionUsesComicCompletedPageSemantics() {
        XCTAssertEqual(ComicReaderView.page(for: 0, count: 24), 0)
        XCTAssertEqual(ComicReaderView.page(for: 1.0 / 24, count: 24), 0)
        XCTAssertEqual(ComicReaderView.page(for: 0.5, count: 24), 11)
        XCTAssertEqual(ComicReaderView.page(for: 1, count: 24), 23)
    }
    func testBookmarkRequiresReadyRenderedPositionAndDuplicateDoesNotChangeProgress() async throws {
        let (root, database, store, sync) = try context()
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        let book = try await store.importBook(from: fixture())
        let model = DocumentReaderModel(book: book, store: store, sync: sync)
        await model.open()
        let beforeReady = await model.addBookmark()
        XCTAssertFalse(beforeReady)
        XCTAssertTrue(model.bookmarks.isEmpty)
        let command = try XCTUnwrap(model.command).id
        model.rendererStarted(command)
        let rendering = await model.addBookmark()
        XCTAssertFalse(rendering)
        model.rendererCompleted(command, success: true)
        let saved = await model.addBookmark()
        XCTAssertTrue(saved)
        let locator = model.formal, time = model.readAt
        let duplicate = await model.addBookmark()
        XCTAssertFalse(duplicate)
        XCTAssertEqual(model.error, "当前位置已有书签")
        XCTAssertEqual(model.bookmarks.count, 1)
        XCTAssertEqual(model.formal, locator); XCTAssertEqual(model.readAt, time)
        XCTAssertNil(try database.documentPosition(bookID: book.id))
        model.close()
        let closed = await model.addBookmark()
        XCTAssertFalse(closed)
        XCTAssertEqual(try database.documentBookmarks(bookID: book.id).count, 1)
    }
    func testOldCanvasCannotCommitWhileReturningFromBookmarkPreview() async throws {
        let (root, database, store, sync) = try context()
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        let book = try await store.importBook(from: fixture())
        let model = DocumentReaderModel(book: book, store: store, sync: sync)
        await model.open(); defer { model.close() }
        model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        let comic = try XCTUnwrap(model.comic)
        model.moveUnit(1)
        model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
        try await settle { model.formal?.unit == 1 }
        let formal = model.formal, time = model.readAt
        model.navigate(try comic.manifest.locator(format: "cbz", page: 10), preview: true)
        let oldID = try XCTUnwrap(model.command).id
        model.rendererCompleted(oldID, success: true)
        model.returnToFormal()
        model.userScrolled(try comic.manifest.locator(format: "cbz", page: 1, y: 0.4))
        model.rendererCompleted(oldID, success: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.formal, formal); XCTAssertEqual(model.readAt, time)
        XCTAssertEqual(try database.documentPosition(bookID: book.id)?.locator, formal)
        model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
    }
    func testImageSurfaceRestoresLongPageAnchorAndZoomAndResizeDoNotCreateReadingTime() async throws {
        let (root, database, store, sync) = try context()
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        let book = try await store.importBook(from: fixture())
        let model = DocumentReaderModel(book: book, store: store, sync: sync)
        await model.open()
        let document = try XCTUnwrap(model.comic)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: ComicReadingSurface(document: document, model: model,
            fitWidth: true, theme: .light, tapped: { _ in }, swiped: { _ in }).frame(width: 360, height: 640))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; model.close() }
        try await settle { model.ready }
        let locator = try document.manifest.locator(format: "cbz", page: 10, y: 0.234567)
        model.navigate(locator)
        try await settle { model.formal == locator && !model.rendering }
        func find(_ view: UIView) -> ComicReadingSurface.Canvas? {
            if let canvas = view as? ComicReadingSurface.Canvas { return canvas }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let canvas = try XCTUnwrap(find(window))
        XCTAssertEqual(canvas.naturalSize, CGSize(width: 600, height: 3600))
        XCTAssertEqual(Double((canvas.contentOffset.y + canvas.contentInset.top) / canvas.contentSize.height), 0.234567, accuracy: 0.00001)
        let time = model.readAt
        canvas.setZoomScale(2, animated: false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.formal, locator); XCTAssertEqual(model.readAt, time)
        canvas.bounds.size = CGSize(width: 300, height: 640); canvas.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(canvas.anchorY, 0.234567, accuracy: 0.00001)
        XCTAssertEqual(model.formal, locator); XCTAssertEqual(model.readAt, time)
    }
    func testSamplingIsBoundedAndSettingsPersist() throws {
        XCTAssertTrue(ComicDocument.validPixelDimensions(width: 10_000, height: 10_000))
        XCTAssertFalse(ComicDocument.validPixelDimensions(width: 10_001, height: 10_000))
        XCTAssertFalse(ComicDocument.validPixelDimensions(width: Int.max, height: Int.max))
        XCTAssertFalse(ComicDocument.validPixelDimensions(width: Int.max, height: 1))
        XCTAssertFalse(ComicDocument.validPixelDimensions(width: 0, height: 10))
        XCTAssertFalse(ComicDocument.validPixelDimensions(width: 10, height: 0))
        let document = try ComicDocument(url: fixture())
        for page in document.manifest.pages.indices {
            let bitmap = try document.bitmap(page: page)
            XCTAssertLessThanOrEqual(bitmap.image.width * bitmap.image.height, 8_100_000)
        }
        let (root, database, _, _) = try context()
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        var settings = ReaderSettings(); settings.comicRightToLeft = true; settings.comicFitWidth = false
        try database.saveReaderSettings(settings)
        XCTAssertEqual(try database.readerSettings(), settings)
    }
    func testPurgedPageCacheRebuildsFromOriginalAndSessionExitRemovesIt() throws {
        let temporary = FileManager.default.temporaryDirectory
        func cacheDirectories() throws -> Set<URL> {
            Set(try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("XLibComicCache-") })
        }
        var document: ComicDocument? = try ComicDocument(url: fixture())
        let before = try cacheDirectories()
        let manifest = try XCTUnwrap(document).manifest
        let position = try manifest.locator(format: "cbz", page: 10, y: 0.234567)
        _ = try document?.bitmap(page: 10)
        let created = try cacheDirectories().subtracting(before)
        XCTAssertEqual(created.count, 1)
        let cache = try XCTUnwrap(created.first)
        let page = cache.appending(path: manifest.pages[10].pageKey)
        XCTAssertTrue(FileManager.default.fileExists(atPath: page.path))
        try FileManager.default.removeItem(at: cache)
        let rebuilt = try XCTUnwrap(document).bitmap(page: 10)
        XCTAssertEqual(rebuilt.naturalSize, CGSize(width: 600, height: 3600))
        XCTAssertTrue(FileManager.default.fileExists(atPath: page.path))
        XCTAssertEqual(try document?.manifest.locator(format: "cbz", page: 10, y: 0.234567), position)
        document = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        let reopened = try ComicDocument(url: fixture())
        XCTAssertEqual(reopened.manifest.manifestHash, manifest.manifestHash)
        XCTAssertEqual(try reopened.manifest.locator(format: "cbz", page: 10, y: 0.234567), position)
    }
    func testStoredAndSolidRARImagesImportNavigateBookmarkAndReopen() async throws {
        let (root, database, store, sync) = try context()
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        let cbz = try ComicDocument(url: fixture())
        let original = try await store.importBook(from: fixture())
        let originalKey = try await store.documentIdentity(book: original)
        var identities = Set([originalKey.bookHash])
        for name in ["comic-basic-rar4.cbr", "comic-basic-rar5.cbr", "comic-basic-rar4-solid.cbr"] {
            let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "fixtures/documents"))
            let book = try await store.importBook(from: source)
            XCTAssertEqual(book.format, "cbr")
            let key = try await store.documentIdentity(book: book)
            XCTAssertTrue(identities.insert(key.bookHash).inserted)
            let model = DocumentReaderModel(book: book, store: store, sync: sync)
            await model.open()
            XCTAssertNil(model.openFailure)
            XCTAssertEqual(model.readAt.timeIntervalSince1970, 0)
            let comic = try XCTUnwrap(model.comic)
            XCTAssertEqual(comic.manifest, cbz.manifest)
            // Reverse access verifies reopening/seeking, not merely first-header recognition.
            for index in comic.manifest.pages.indices.reversed() {
                let path = comic.manifest.pages[index].canonicalPath
                XCTAssertEqual(try comic.archive.read(path), try cbz.archive.read(path))
                let bitmap = try comic.bitmap(page: index)
                XCTAssertEqual(bitmap.naturalSize, CGSize(width: 600, height: index == 10 ? 3600 : 800))
            }
            model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
            let target = try comic.manifest.locator(format: "cbr", page: 10, y: 0.234567)
            model.navigate(target)
            model.rendererCompleted(try XCTUnwrap(model.command).id, success: true)
            try await settle { model.formal == target }
            await model.addBookmark()
            XCTAssertEqual(model.bookmarks.first?.locator, target)
            let time = model.readAt
            model.close()
            let reopened = DocumentReaderModel(book: book, store: store, sync: sync)
            await reopened.open()
            XCTAssertEqual(reopened.current, target)
            XCTAssertEqual(reopened.readAt.timeIntervalSince1970, time.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(reopened.bookmarks.first?.locator, target)
            reopened.close()
        }
        XCTAssertEqual(try database.loadBooks().count, 4)
    }
}
