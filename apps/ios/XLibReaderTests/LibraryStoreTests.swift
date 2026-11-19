import AppleShared
import Foundation
import XCTest
@testable import XLibReader

private final class ImportCapacityProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let failAt: Int
    init(failAt: Int) { self.failAt = failAt }
    func capacity(_ url: URL) -> Int64? {
        lock.withLock { calls += 1; return calls >= failAt ? 0 : Int64.max }
    }
    var count: Int { lock.withLock { calls } }
}
private final class ImportCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var entered = false
    let resume = DispatchSemaphore(value: 0)
    var started: Bool { lock.withLock { entered } }
    func capacity(_ url: URL) -> Int64? {
        lock.withLock { entered = true }
        _ = resume.wait(timeout: .now() + 5)
        return Int64.max
    }
}

final class LibraryStoreTests: XCTestCase {
    func testLowSpaceBeforeAndDuringCopyPreservesExistingBookAndCleansPartialFile() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let database = testDatabase(root: root)
        defer { database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root, database: database)
        let source = root.appending(path: "original.txt")
        try Data("旧书及书签不应受失败导入影响".utf8).write(to: source)
        let book = try await store.importBook(from: source)
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.saveProgress(bookID: book.id, offset: 3, updatedAt: time)
        _ = try await store.addBookmark(bookID: book.id, offset: 3, excerpt: "原书签")
        let large = root.appending(path: "large.txt")
        let bytes = Data(repeating: 0x61, count: 1024 * 1024)
        try bytes.write(to: large)
        for failAt in [1, 3] {
            let probe = ImportCapacityProbe(failAt: failAt)
            let lowSpace = LibraryStore(root: root, database: database, availableImportCapacity: { probe.capacity($0) })
            do { _ = try await lowSpace.importBook(from: large); XCTFail("Low-space import accepted") }
            catch { XCTAssertTrue(error.localizedDescription.contains("存储空间不足")) }
            XCTAssertEqual(probe.count, failAt)
            XCTAssertEqual(try database.loadBooks().map(\.id), [book.id])
            XCTAssertEqual(try database.loadBooks().first?.offset, 3)
            XCTAssertEqual(try database.loadBooks().first?.updatedAt, time)
            XCTAssertEqual(try database.bookmarks(bookID: book.id).count, 1)
            let original = await store.url(for: book)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Books").path), [original.lastPathComponent])
            XCTAssertEqual(try Data(contentsOf: large), bytes)
        }
    }

    @MainActor func testLibraryCancelImportStopsRunningWorkWithoutErrorOrPublication() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let database = testDatabase(root: root)
        let gate = ImportCancellationGate()
        defer { gate.resume.signal(); database.closeForTesting(); try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root, database: database, availableImportCapacity: { gate.capacity($0) })
        let model = LibraryModel(store: store)
        let source = root.appending(path: "cancel.txt")
        try Data(repeating: 0x61, count: 1_000_000).write(to: source)
        let importing = Task { await model.importBook(from: source) }
        for _ in 0..<100 {
            if gate.started { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(gate.started); XCTAssertTrue(model.isImporting)
        model.cancelImport(); gate.resume.signal()
        await importing.value
        XCTAssertFalse(model.isImporting); XCTAssertFalse(model.isLoading); XCTAssertNil(model.errorMessage)
        XCTAssertTrue(try database.loadBooks().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Books").path).isEmpty)
    }

    func testWholeTextValidationPreservesEncodingBoundariesAndOriginalBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = testLibraryStore(root: root)
        for encoding in TextEncoding.allCases {
            let prefix = String(repeating: "a", count: encoding == .utf16LittleEndian || encoding == .utf16BigEndian ? 32766 : 65535)
            let text = prefix + "🙂e\u{301}中文\n第二行\r\n\t结尾"
            var bytes = Data()
            if encoding == .utf16LittleEndian { bytes.append(contentsOf: [0xff, 0xfe]) }
            if encoding == .utf16BigEndian { bytes.append(contentsOf: [0xfe, 0xff]) }
            if encoding == .gb18030 { bytes.append(try XCTUnwrap("中文".data(using: encoding.foundationEncoding))) }
            bytes.append(try XCTUnwrap(text.data(using: encoding.foundationEncoding)))
            let source = root.appending(path: encoding.rawValue + ".txt")
            try bytes.write(to: source)
            let book = try await store.importBook(from: source)
            XCTAssertEqual(book.encoding, encoding)
            XCTAssertEqual(book.updatedAt.timeIntervalSince1970, 0)
            let imported = await store.url(for: book)
            XCTAssertEqual(try Data(contentsOf: imported), bytes)
        }
    }

    func testLateInvalidTextAndRenamedKindleLeaveExistingBookUnchanged() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = testLibraryStore(root: root)
        let original = root.appending(path: "original.txt")
        let originalBytes = Data("既有书籍🙂".utf8)
        try originalBytes.write(to: original)
        let book = try await store.importBook(from: original)
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.saveProgress(bookID: book.id, offset: 3, updatedAt: time)
        var kindle = Data(repeating: 0x41, count: 96)
        kindle.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8))
        var invalid: [Data] = []
        for suffix: [UInt8] in [[0, 0x61], [0xff], [0xf0, 0x9f]] {
            var bytes = Data(repeating: 0x61, count: 70_000)
            bytes.append(contentsOf: suffix); invalid.append(bytes)
        }
        var utf16 = Data([0xff, 0xfe])
        utf16.append(Data(repeating: 0x61, count: 70_000)); utf16.append(contentsOf: [0, 0])
        invalid.append(utf16)
        // A dangling byte after otherwise valid UTF-16 text.
        invalid.append(Data([0xff, 0xfe, 0x61, 0, 0xd8]))
        invalid.append(Data([0xfe, 0xff, 0, 0x61, 0xd8]))
        invalid.append(kindle)
        for (index, bytes) in invalid.enumerated() {
            let source = root.appending(path: "invalid-\(index).data")
            try bytes.write(to: source)
            do { _ = try await store.importBook(from: source); XCTFail("Invalid text accepted: \(index)") } catch {}
            XCTAssertEqual(try Data(contentsOf: source), bytes)
        }
        let saved = try await store.load()
        XCTAssertEqual(saved.map(\.id), [book.id])
        XCTAssertEqual(saved.first?.offset, 3); XCTAssertEqual(saved.first?.updatedAt, time)
        let imported = await store.url(for: book)
        XCTAssertEqual(try Data(contentsOf: imported), originalBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Books").path), [imported.lastPathComponent])
    }

    func testCancelledImportDoesNotPublishOrLeaveTemporaryCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = testLibraryStore(root: root)
        let source = root.appending(path: "cancelled.txt")
        let bytes = Data(repeating: 0x61, count: 100_000)
        try bytes.write(to: source)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.importBook(from: source)
        }
        do { _ = try await task.value; XCTFail("Cancelled import published") } catch is CancellationError {}
        let books = try await store.load()
        XCTAssertTrue(books.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Books").path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    func testSingleBookDeletionRemovesOnlyItsLocalFileProgressBookmarksAndTOC() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = testLibraryStore(root: root)
        let source = root.appending(path: "source.txt")
        try Data("第一章\n本地删除验证。".utf8).write(to: source)
        let target = try await store.importBook(from: source)
        let other = try await store.importBook(from: source)
        for book in [target, other] {
            try await store.saveProgress(bookID: book.id, offset: 3, updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
            _ = try await store.addBookmark(bookID: book.id, offset: 3, excerpt: "书签")
            try await store.saveTOC([TocEntry(id: UUID(), title: "第一章", offset: 0, level: 0)], for: book)
        }
        let targetURL = await store.url(for: target)
        let otherURL = await store.url(for: other)
        try await store.deleteBooks(ids: [target.id])
        let remaining = try await store.load()
        let deletedMarks = try await store.bookmarks(for: target.id)
        let deletedTOC = try await store.cachedTOC(for: target)
        let otherMarks = try await store.bookmarks(for: other.id)
        let otherTOC = try await store.cachedTOC(for: other)
        XCTAssertEqual(remaining.map(\.id), [other.id])
        XCTAssertEqual(remaining.first?.offset, 3)
        XCTAssertEqual(remaining.first?.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
        XCTAssertTrue(deletedMarks.isEmpty)
        XCTAssertNil(deletedTOC)
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherURL.path))
        XCTAssertEqual(otherMarks.count, 1)
        XCTAssertEqual(otherTOC?.count, 1)
    }

    func testImportAndReloadPreserveUnknownAndRealReadingTimes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "source.txt")
        try Data("阅读时间测试正文".utf8).write(to: source)
        let libraryRoot = root.appending(path: "library")
        let store = testLibraryStore(root: libraryRoot)
        var book = try await store.importBook(from: source)
        XCTAssertEqual(book.updatedAt.timeIntervalSince1970, 0)
        book.title = "编辑不产生阅读时间"
        try await store.updateBook(book)
        let unread = try await testLibraryStore(root: libraryRoot).load()
        XCTAssertEqual(unread.first?.updatedAt.timeIntervalSince1970, 0)
        let realTime = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.saveProgress(bookID: book.id, offset: 3, updatedAt: realTime)
        let read = try await testLibraryStore(root: libraryRoot).load()
        XCTAssertEqual(read.first?.updatedAt, realTime)
        XCTAssertEqual(read.first?.offset, 3)
    }

    func testBookmarkUniquenessPreservesOriginalAndOtherPositions() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = testLibraryStore(root: root)
        let firstSource = root.appending(path: "first.txt")
        let secondSource = root.appending(path: "second.txt")
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)
        let bookID = try await store.importBook(from: firstSource).id
        let otherBookID = try await store.importBook(from: secondSource).id
        let original = try await store.addBookmark(bookID: bookID, offset: 100, excerpt: "原摘要")
        do {
            _ = try await store.addBookmark(bookID: bookID, offset: 100, excerpt: "新摘要")
            XCTFail("Duplicate position accepted")
        } catch BookmarkError.duplicatePosition { }
        let adjacent = try await store.addBookmark(bookID: bookID, offset: 101, excerpt: "邻近位置")
        let other = try await store.addBookmark(bookID: otherBookID, offset: 100, excerpt: "另一书")
        let reopened = testLibraryStore(root: root)
        let marks = try await reopened.bookmarks(for: bookID)
        XCTAssertEqual(marks.map(\.id), [original.id, adjacent.id])
        XCTAssertEqual(marks.first?.excerpt, "原摘要")
        XCTAssertEqual(try XCTUnwrap(marks.first).createdAt.timeIntervalSince1970, original.createdAt.timeIntervalSince1970, accuracy: 1)
        try await reopened.removeBookmark(id: original.id)
        let remaining = try await reopened.bookmarks(for: bookID)
        let otherMarks = try await reopened.bookmarks(for: other.bookID)
        XCTAssertEqual(remaining.map(\.id), [adjacent.id])
        XCTAssertEqual(otherMarks.map(\.id), [other.id])
        try await reopened.removeBookmark(id: adjacent.id)
        let empty = try await reopened.bookmarks(for: bookID)
        XCTAssertTrue(empty.isEmpty)
    }

    func testImportEditProgressBookmarkAndDelete() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).txt")
        try "第一章\n你好，世界🙂\n".data(using: .utf8)!.write(to: source)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: source) }
        let store = testLibraryStore(root: root)
        var book = try await store.importBook(from: source)
        let importedBooks = try await store.load()
        XCTAssertEqual(importedBooks.count, 1)
        XCTAssertEqual(book.encoding, .utf8)
        book.title = "新书名"
        try await store.updateBook(book)
        try await store.saveProgress(bookID: book.id, offset: 4)
        let mark = try await store.addBookmark(bookID: book.id, offset: 4, excerpt: "你好")
        let marks = try await store.bookmarks(for: book.id)
        let updatedBooks = try await store.load()
        XCTAssertEqual(marks.map(\.id), [mark.id])
        XCTAssertEqual(marks.first?.bookID, mark.bookID)
        XCTAssertEqual(marks.first?.offset, mark.offset)
        XCTAssertEqual(marks.first?.excerpt, mark.excerpt)
        XCTAssertEqual(
            try XCTUnwrap(marks.first).createdAt.timeIntervalSince1970,
            mark.createdAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(updatedBooks.first?.title, "新书名")
        XCTAssertEqual(updatedBooks.first?.offset, 4)
        try await store.deleteBooks(ids: [book.id])
        let remainingBooks = try await store.load()
        XCTAssertTrue(remainingBooks.isEmpty)
    }

    func testSettingsNormalization() async {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = testDatabase(root: root)
        await MainActor.run {
            let store = SettingsStore(database: database)
            store.update { $0.fontSize = 100; $0.autoPageSeconds = 1 }
            XCTAssertEqual(store.settings.fontSize, 34)
            XCTAssertEqual(store.settings.autoPageSeconds, 3)
        }
    }

    func testScreenLockIconMatchesEnabledState() {
        var settings = ReaderSettings()
        XCTAssertEqual(settings.screenLockIconName, "lock.open")

        settings.keepScreenAwake = true
        XCTAssertEqual(settings.screenLockIconName, "lock.fill")
    }

    func testTOCCachePresenceAndDeletion() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).txt")
        try "第一章 开始\n正文\n".data(using: .utf8)!.write(to: source)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: source) }

        let store = testLibraryStore(root: root)
        let book = try await store.importBook(from: source)
        var cachedBookIDs = try await store.booksWithCachedTOC([book])
        XCTAssertTrue(cachedBookIDs.isEmpty)

        try await store.saveTOC([], for: book)
        cachedBookIDs = try await store.booksWithCachedTOC([book])
        let emptyTOC = try await store.cachedTOC(for: book)
        XCTAssertEqual(cachedBookIDs, [book.id])
        XCTAssertEqual(emptyTOC, [])

        try await store.deleteTOC(for: book.id)
        cachedBookIDs = try await store.booksWithCachedTOC([book])
        let deletedTOC = try await store.cachedTOC(for: book)
        XCTAssertTrue(cachedBookIDs.isEmpty)
        XCTAssertNil(deletedTOC)
    }

    @MainActor
    func testLibraryModelGeneratesAndDeletesTOC() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).txt")
        try "第一章 开始\n正文\n第二章 继续\n".data(using: .utf8)!.write(to: source)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: source) }

        let store = testLibraryStore(root: root)
        let book = try await store.importBook(from: source)
        let model = LibraryModel(store: store)
        await model.load()

        await model.generateTOC(ids: [book.id])
        let generatedTOC = try await store.cachedTOC(for: book)
        XCTAssertEqual(model.booksWithTOC, [book.id])
        XCTAssertEqual(generatedTOC?.count, 2)

        await model.deleteTOC(ids: [book.id])
        let deletedTOC = try await store.cachedTOC(for: book)
        XCTAssertTrue(model.booksWithTOC.isEmpty)
        XCTAssertNil(deletedTOC)
    }
}
