import AppleShared
import Foundation
import PDFKit

enum BookmarkError: LocalizedError {
    case duplicatePosition
    var errorDescription: String? { "当前位置已有书签" }
}

actor LibraryStore {
    struct Paths: Sendable {
        let root: URL
        var books: URL { root.appending(path: "Books", directoryHint: .isDirectory) }
        var metadata: URL { root.appending(path: "Metadata", directoryHint: .isDirectory) }
    }

    private let paths: Paths
    private let database: LocalDatabase
    typealias ImportCapacity = @Sendable (URL) throws -> Int64?
    private let availableImportCapacity: ImportCapacity
    private var loaded = false

    init(root: URL? = nil, database: LocalDatabase, availableImportCapacity: @escaping ImportCapacity = { url in
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        return values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init)
    }) {
        self.database = database
        self.availableImportCapacity = availableImportCapacity
        if let root {
            paths = Paths(root: root)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            paths = Paths(root: base.appending(path: "XLibReader", directoryHint: .isDirectory))
        }
    }

    func load() throws -> [Book] {
        try prepareIfNeeded()
        return try database.loadBooks()
    }

    func url(for book: Book) -> URL { paths.root.appending(path: book.relativePath) }
    func documentPosition(bookID: UUID) throws -> LocalDatabase.DocumentPosition? { try database.documentPosition(bookID: bookID) }
    func saveDocumentPosition(bookID: UUID, hash: String, locator: DocumentLocator, readAt: Date) throws { try database.saveDocumentPosition(bookID: bookID, hash: hash, locator: locator, readAt: readAt) }
    func documentBookmarks(bookID: UUID) throws -> [DocumentBookmark] { try database.documentBookmarks(bookID: bookID) }
    func addDocumentBookmark(bookID: UUID, locator: DocumentLocator, excerpt: String) throws { try database.addDocumentBookmark(bookID: bookID, locator: locator, excerpt: excerpt) }
    func removeDocumentBookmark(id: UUID) throws { try database.removeDocumentBookmark(id: id) }
    func documentIdentity(book: Book) async throws -> SyncBookKey { try await SyncStateStore(database: database).identity(for: book, fileURL: url(for: book)).key }
    func documentSyncConfiguration() -> (String, String?) {
        (database.syncString(for: SyncServerConfiguration.storageKey) ?? SyncServerConfiguration.resolvedAddress(), database.syncString(for: SyncServerConfiguration.credentialServerKey))
    }


    func importBook(from sourceURL: URL) throws -> Book {
        try prepareIfNeeded()
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        let id = UUID()
        let temporary = paths.books.appending(path: ".\(id.uuidString).importing")
        do {
            try coordinatedCopy(from: sourceURL, to: temporary)
            let headerHandle = try FileHandle(forReadingFrom: temporary)
            let header = try headerHandle.read(upToCount: 96) ?? Data()
            try headerHandle.close()
            let format: String
            // Content identity, not a filename, selects the publication parser.
            if header.count >= 68, header.subdata(in: 60..<68) == Data("BOOKMOBI".utf8) {
                try validateDocumentSize(temporary,limitMiB:1024)
                _ = try KindleDocument(url: temporary)
                format = "kindle"
            } else if header.starts(with: Data("%PDF-".utf8)) {
                try validateDocumentSize(temporary)
                format = "pdf"
                guard let pdf = PDFDocument(url: temporary), pdf.isLocked || (1...100_000).contains(pdf.pageCount) else { throw DocumentError.unsupported("PDF 损坏或页数不受支持") }
            } else if header.starts(with: Data([0x50,0x4b])) {
                let archive = try ComicArchive(url: temporary)
                let paths = Set(archive.entries.map(\.path))
                if paths.contains("mimetype") || paths.contains("META-INF/container.xml") || sourceURL.pathExtension.lowercased() == "epub" {
                    try validateDocumentSize(temporary)
                    format = "epub"
                    _ = try EPUBDocument(url: temporary)
                } else {
                    format = "cbz"
                    _ = try ComicDocument(url: temporary, validatePages: true)
                }
            } else if header.starts(with: Data([0x52,0x61,0x72,0x21,0x1a,0x07])) {
                format = "cbr"
                _ = try ComicDocument(url: temporary, validatePages: true)
            } else {
                let ext = sourceURL.pathExtension.lowercased()
                let utf16BOM = header.starts(with: [0xff, 0xfe]) || header.starts(with: [0xfe, 0xff])
                guard !["pdf","epub","cbz","cbr","zip","rar","mobi","azw","azw3","kfx","azw4"].contains(ext),
                      (!header.contains(0) || utf16BOM), !header.starts(with:Data([0xea,0x44,0x52,0x4d])) else {
                    throw DocumentError.unsupported("文件内容不受支持；不支持 DRM、KFX、Print Replica 或损坏的 Kindle 文档")
                }
                try validateText(temporary)
                format = "txt"
            }
            let declared = sourceURL.pathExtension.lowercased()
            let declaredFormat = ["mobi","azw","azw3"].contains(declared) ? "kindle" : declared
            if ["pdf","epub","cbz","cbr","kindle","kfx","azw4"].contains(declaredFormat), declaredFormat != format { throw DocumentError.unsupported("文件内容与扩展名不符") }
            let destination = paths.books.appending(path: "\(id.uuidString).\(format)")
            let encoding = format == "txt" ? try TextEncoding.detect(at: temporary) : TextEncoding.utf8
            let values = try temporary.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: temporary, to: destination)
            var book = Book(
                id: id,
                title: sourceURL.deletingPathExtension().lastPathComponent,
                sourceName: sourceURL.lastPathComponent,
                author: "",
                relativePath: "Books/\(id.uuidString).\(format)",
                fileSize: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .now,
                encoding: encoding,
                offset: 0,
                // Importing is not a reading event; retain the existing Date storage format.
                updatedAt: Date(timeIntervalSince1970: 0),
                schemaVersion: Book.schemaVersion
            )
            book.format = format
            book.title = book.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名书籍" : book.title
            do { try Task.checkCancellation(); try database.insertBook(book) }
            catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            return book
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    func updateBook(_ book: Book) throws {
        try prepareIfNeeded()
        try database.updateBook(book)
    }

    func saveProgress(bookID: UUID, offset: Int64, updatedAt: Date = .now) throws {
        try prepareIfNeeded()
        try database.saveProgress(bookID: bookID, offset: offset, updatedAt: updatedAt)
    }

    func deleteBooks(ids: Set<UUID>) throws {
        try prepareIfNeeded()
        try database.deleteBooks(ids: ids)
    }

    func bookmarks(for bookID: UUID) throws -> [Bookmark] {
        try prepareIfNeeded()
        return try database.bookmarks(bookID: bookID)
    }

    func addBookmark(bookID: UUID, offset: Int64, excerpt: String) throws -> Bookmark {
        try prepareIfNeeded()
        let bookmark = Bookmark(id: UUID(), bookID: bookID, offset: offset, excerpt: excerpt, createdAt: .now)
        try database.addBookmark(bookmark)
        return bookmark
    }

    func removeBookmark(id: UUID) throws {
        try prepareIfNeeded()
        try database.removeBookmark(id: id)
    }

    func cachedTOC(for book: Book) throws -> [TocEntry]? {
        try prepareIfNeeded()
        return try database.cachedTOC(for: book)
    }

    func booksWithCachedTOC(_ books: [Book]) throws -> Set<UUID> {
        try prepareIfNeeded()
        return try database.booksWithCachedTOC(books)
    }

    func saveTOC(_ entries: [TocEntry], for book: Book) throws {
        try prepareIfNeeded()
        let document = TocDocument(
            schemaVersion: TocDocument.schemaVersion,
            fileSize: book.fileSize,
            modifiedAt: book.modifiedAt,
            entries: entries
        )
        try database.saveTOC(document, bookID: book.id)
    }

    func deleteTOC(for bookID: UUID) throws {
        try prepareIfNeeded()
        try database.deleteTOC(bookID: bookID)
    }

    private func prepareIfNeeded() throws {
        guard !loaded else { return }
        try FileManager.default.createDirectory(at: paths.books, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.metadata, withIntermediateDirectories: true)
        let references = Set(try database.loadBooks().map { URL(fileURLWithPath: $0.relativePath).lastPathComponent })
        let contents = try FileManager.default.contentsOfDirectory(at: paths.books, includingPropertiesForKeys: nil)
        for url in contents {
            let managed = UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil && ["txt","pdf","epub","cbz","cbr","kindle"].contains(url.pathExtension)
            if url.lastPathComponent.hasSuffix(".importing") || (managed && !references.contains(url.lastPathComponent)) { try? FileManager.default.removeItem(at: url) }
        }
        loaded = true
    }

    private func coordinatedCopy(from source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try Task.checkCancellation()
                let expected = Int64(try coordinatedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                guard expected <= 1024 * 1024 * 1024 else { throw DocumentError.unsupported("文档超过 1 GiB") }
                try ensureImportSpace(required: max(0, expected))
                let input = try FileHandle(forReadingFrom: coordinatedURL)
                FileManager.default.createFile(atPath: destination.path, contents: nil)
                let output = try FileHandle(forWritingTo: destination)
                defer { try? input.close(); try? output.close() }
                var copied: Int64 = 0
                while true {
                    try Task.checkCancellation()
                    let chunk = try input.read(upToCount: 256 * 1_024) ?? Data()
                    if chunk.isEmpty { break }
                    copied += Int64(chunk.count)
                    if copied > 1024 * 1024 * 1024 { throw DocumentError.unsupported("文档超过 1 GiB") }
                    try ensureImportSpace(required: Int64(chunk.count))
                    try output.write(contentsOf: chunk)
                }
                try output.synchronize()
            } catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }

    private func ensureImportSpace(required: Int64) throws {
        // Keep a reserve for SQLite/atomic publication; write errors remain
        // authoritative because available capacity can change after this check.
        if let available = try availableImportCapacity(paths.books), available < required + 16 * 1024 * 1024 {
            throw DocumentError.unsupported("存储空间不足，请至少保留导入文件大小及 16 MiB 可用空间")
        }
    }

    private func validateDocumentSize(_ url: URL, limitMiB:Int = 256) throws {
        guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 <= limitMiB * 1024 * 1024 else {
            throw DocumentError.unsupported("文档超过 \(limitMiB) MiB 支持限制")
        }
    }

    private func validateText(_ url: URL) throws {
        let encoding = try TextEncoding.detect(at: url)
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var pending = Data()
        while true {
            try Task.checkCancellation()
            let chunk = try input.read(upToCount: 64 * 1024) ?? Data()
            pending.append(chunk)
            if pending.isEmpty { return }
            guard let decoded = try? encoding.decodeCompletePrefix(pending),
                  !decoded.text.unicodeScalars.contains(where: {
                      ($0.value < 32 && ![9, 10, 13].contains($0.value)) || (0x7f...0x9f).contains($0.value)
                  }) else { throw DocumentError.unsupported("未知二进制或损坏文本不能作为 TXT 导入") }
            pending.removeFirst(decoded.bytesConsumed)
            if chunk.isEmpty {
                guard pending.isEmpty else { throw DocumentError.unsupported("文本末尾包含不完整字符") }
                return
            }
        }
    }
}
