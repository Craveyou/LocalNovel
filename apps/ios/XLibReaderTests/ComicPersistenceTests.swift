import AppleShared
import Foundation
import SQLite3
import XCTest
@testable import XLibReader

final class ComicPersistenceTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let txtID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let pdfID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    private let epubID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    private let pdfBookmarkID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let epubBookmarkID = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
    private let pdf = DocumentLocator.pdf(page: 1, pageCount: 3, y: 0.25)
    private let epub = DocumentLocator.epub(resource: "OPS/a.xhtml", spineIndex: 1, spineCount: 2, textOffset: 8, textLength: 40)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ComicPersistenceTests-\(UUID().uuidString)")
        suiteName = "com.xlib.comic-persistence.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        try FileManager.default.createDirectory(at: root.appending(path: "Metadata"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "Books"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
        if let suiteName { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    }

    func testGenuineV3MigrationPreservesEveryOldRowAndReopensIdempotently() throws {
        try seedGenuineV3()
        let before = try oldRows()
        let bytes = try ["txt", "pdf", "epub"].map { try Data(contentsOf: root.appending(path: "Books/old.\($0)")) }
        XCTAssertEqual(try rows("PRAGMA user_version"), [["3"]])
        XCTAssertFalse(try columns("document_positions").contains("profile"))
        XCTAssertFalse(try rows("SELECT sql FROM sqlite_master WHERE name='books'")[0][0]!.contains("cbz"))

        for _ in 0..<2 {
            let database = try LocalDatabase.open(root: root, defaults: defaults)
            defer { database.closeForTesting() }
            XCTAssertEqual(try rows("PRAGMA user_version"), [[String(LocalDatabase.schemaVersion)]])
            XCTAssertEqual(try oldRows(), before)
            XCTAssertEqual(try rows("PRAGMA foreign_key_check"), [])
            XCTAssertEqual(try rows("PRAGMA integrity_check"), [["ok"]])
            XCTAssertEqual(try rows("SELECT COUNT(*) FROM document_positions WHERE profile IS NOT NULL OR manifest_hash IS NOT NULL OR page_key IS NOT NULL"), [["0"]])
            XCTAssertEqual(try rows("SELECT COUNT(*) FROM document_bookmarks WHERE profile IS NOT NULL OR manifest_hash IS NOT NULL OR page_key IS NOT NULL"), [["0"]])
            let books = try database.loadBooks()
            XCTAssertEqual(Set(books.map(\.id)), Set([txtID, pdfID, epubID]))
            XCTAssertEqual(books.first { $0.id == txtID }?.offset, 3)
            XCTAssertEqual(books.first { $0.id == txtID }?.updatedAt, Date(timeIntervalSince1970: 1_700_000_100))
            XCTAssertEqual(books.first { $0.id == pdfID }?.documentLocator, pdf)
            XCTAssertEqual(books.first { $0.id == epubID }?.documentLocator, epub)
            XCTAssertEqual(try database.documentPosition(bookID: pdfID)?.hash, String(repeating: "a", count: 64))
            XCTAssertEqual(try database.documentPosition(bookID: pdfID)?.readAt, Date(timeIntervalSince1970: 1_700_000_200))
            XCTAssertEqual(try database.documentPosition(bookID: epubID)?.readAt, Date(timeIntervalSince1970: 1_700_000_300))
            let pdfMarks = try database.documentBookmarks(bookID: pdfID)
            let epubMarks = try database.documentBookmarks(bookID: epubID)
            XCTAssertEqual(pdfMarks.map(\.id), [pdfBookmarkID])
            XCTAssertEqual(pdfMarks.map(\.locator), [pdf])
            XCTAssertEqual(pdfMarks.first?.excerpt, "PDF 原书签")
            XCTAssertEqual(pdfMarks.first?.createdAt, Date(timeIntervalSince1970: 1_700_000_201))
            XCTAssertEqual(epubMarks.map(\.id), [epubBookmarkID])
            XCTAssertEqual(epubMarks.map(\.locator), [epub])
            XCTAssertEqual(try database.bookmarks(bookID: txtID).first?.offset, 2)
            XCTAssertEqual(try database.bookmarks(bookID: txtID).first?.excerpt, "TXT 原书签")
            XCTAssertEqual(try database.readerSettings().theme, .dark)
            XCTAssertEqual(try database.readerSettings().fontSize, 19)
            XCTAssertEqual(try database.readerSettings().lineSpacing, 8)
            XCTAssertEqual(database.syncString(for: "sync.email.v1"), "reader@example.com")
            XCTAssertTrue(database.syncBool(for: "sync.has.started.v1"))
            // The migration must not rewrite the retained original source bytes.
            XCTAssertEqual(try ["txt", "pdf", "epub"].map { try Data(contentsOf: root.appending(path: "Books/old.\($0)")) }, bytes)
        }
    }

    func testMigratedForeignKeysStillRejectOrphansAndCascadeOnlyDeletedBook() throws {
        try seedGenuineV3()
        let database = try LocalDatabase.open(root: root, defaults: defaults)
        defer { database.closeForTesting() }
        try raw { handle in
            try execute(handle, "PRAGMA foreign_keys=ON")
            XCTAssertThrowsError(try execute(handle, "INSERT INTO reading_progress VALUES('missing-book',0,NULL)"))
            XCTAssertThrowsError(try execute(handle, "INSERT INTO document_positions(book_id,book_hash,format,locator_version,page_index,page_count,page_y) VALUES('missing-book','\(String(repeating: "a", count: 64))','pdf',1,0,1,0)"))
            for table in ["reading_progress", "bookmarks", "toc_documents", "book_hash_cache", "document_positions", "document_bookmarks"] {
                let keys = try rows(handle, "PRAGMA foreign_key_list(\(table))")
                XCTAssertTrue(keys.contains { $0[2] == "books" && $0[6] == "CASCADE" }, table)
            }
        }
        try database.deleteBooks(ids: [pdfID])
        XCTAssertNil(try database.documentPosition(bookID: pdfID))
        XCTAssertTrue(try database.documentBookmarks(bookID: pdfID).isEmpty)
        XCTAssertEqual(try database.documentPosition(bookID: epubID)?.locator, epub)
        XCTAssertEqual(try database.documentBookmarks(bookID: epubID).map(\.id), [epubBookmarkID])
        XCTAssertEqual(try database.bookmarks(bookID: txtID).count, 1)
        XCTAssertEqual(try rows("SELECT COUNT(*) FROM book_hash_cache WHERE book_id='\(key(pdfID))'"), [["0"]])
        XCTAssertEqual(try rows("SELECT COUNT(*) FROM reading_progress WHERE book_id='\(key(pdfID))'"), [["0"]])
        XCTAssertEqual(try rows("PRAGMA foreign_key_check"), [])
    }

    func testCBZAndCBRPersistTypedCoordinatesBookmarksAndExactReadingTime() throws {
        try seedGenuineV3()
        let manifest = try ComicManifest(paths: ["10.png", "2.jpg", "1.jpg"])
        let hash = String(repeating: "c", count: 64)
        let readAt = Date(timeIntervalSince1970: 1_700_000_400.123)
        var saved: [(Book, DocumentLocator, UUID)] = []
        do {
            let database = try LocalDatabase.open(root: root, defaults: defaults)
            defer { database.closeForTesting() }
            for format in ["cbz", "cbr"] {
                var book = try makeBook(format: format)
                book.updatedAt = Date(timeIntervalSince1970: 0)
                try database.insertBook(book)
                XCTAssertNil(try database.documentPosition(bookID: book.id))
                let unrounded = DocumentLocator.comic(format: format, manifestHash: manifest.hash, pageKey: manifest.pageKeys[1], page: 1, pageCount: 3, y: 0.1234565)
                let locator = try unrounded.validated()
                try database.saveDocumentPosition(bookID: book.id, hash: hash, locator: unrounded, readAt: readAt)
                try database.addDocumentBookmark(bookID: book.id, locator: unrounded, excerpt: "漫画页 2")
                XCTAssertThrowsError(try database.addDocumentBookmark(bookID: book.id, locator: locator, excerpt: "重复不能覆盖"))
                let marks = try database.documentBookmarks(bookID: book.id)
                XCTAssertEqual(marks.count, 1)
                XCTAssertEqual(marks.first?.locator, locator)
                let markID = try XCTUnwrap(marks.first?.id)
                saved.append((book, locator, markID))
                let foreign = try manifest.locator(format: format == "cbz" ? "cbr" : "cbz", page: 1)
                XCTAssertThrowsError(try database.saveDocumentPosition(bookID: book.id, hash: hash, locator: foreign, readAt: .now))
                XCTAssertThrowsError(try database.addDocumentBookmark(bookID: book.id, locator: foreign, excerpt: "不匹配"))
                XCTAssertEqual(try database.documentPosition(bookID: book.id)?.readAt, readAt)
            }
            // Typed columns, not JSON blobs, hold the stable comic identity; unrelated coordinates stay NULL.
            XCTAssertEqual(try rows("SELECT COUNT(*) FROM document_positions WHERE format IN ('cbz','cbr') AND profile='comic-order-v1' AND manifest_hash='\(manifest.hash)' AND resource IS NULL AND spine_index IS NULL AND text_offset IS NULL AND text_hash IS NULL"), [["2"]])
            XCTAssertEqual(try database.documentPosition(bookID: pdfID)?.locator, pdf)
        }
        for _ in 0..<2 {
            let reopened = try LocalDatabase.open(root: root, defaults: defaults)
            defer { reopened.closeForTesting() }
            for (book, locator, markID) in saved {
                let stored = try XCTUnwrap(reopened.documentPosition(bookID: book.id))
                XCTAssertEqual(stored.locator, locator)
                XCTAssertEqual(stored.hash, hash)
                XCTAssertEqual(stored.readAt, readAt)
                XCTAssertTrue(manifest.valid(stored.locator, format: book.format))
                let loaded = try XCTUnwrap(reopened.loadBooks().first { $0.id == book.id })
                XCTAssertEqual(loaded.format, book.format)
                XCTAssertEqual(loaded.documentLocator, locator)
                XCTAssertEqual(loaded.updatedAt, readAt)
                XCTAssertEqual(loaded.progress, 2.0 / 3.0)
                XCTAssertEqual(try reopened.documentBookmarks(bookID: book.id).map(\.id), [markID])
                XCTAssertEqual(try reopened.documentBookmarks(bookID: book.id).first?.excerpt, "漫画页 2")
            }
            XCTAssertEqual(try rows("PRAGMA foreign_key_check"), [])
        }
    }

    func testFailedV3MigrationRollsBackSchemaAndAllRows() throws {
        try seedGenuineV3()
        // A genuinely corrupt old FK must fail the upgrade without publishing a partial v4 schema.
        try raw { try execute($0, "PRAGMA foreign_keys=OFF; INSERT INTO bookmarks VALUES('orphan','missing-book',0,'preserve for recovery',1)") }
        let before = try oldRows()
        XCTAssertThrowsError(try LocalDatabase.open(root: root, defaults: defaults))
        XCTAssertEqual(try rows("PRAGMA user_version"), [["3"]])
        XCTAssertEqual(try oldRows(), before)
        XCTAssertFalse(try columns("document_positions").contains("profile"))
        XCTAssertTrue(try rows("SELECT name FROM sqlite_master WHERE name LIKE '%_v4'").isEmpty)
    }

    func testGenuineV4MigrationPreservesComicIdentityAndAllExistingRows() throws {
        try seedGenuineV3(comicV4: true)
        let id = UUID(), hash = String(repeating: "c", count: 64), pageKey = String(repeating: "d", count: 64)
        let locator = DocumentLocator.comic(format:"cbr",manifestHash:hash,pageKey:pageKey,page:1,pageCount:3,y:0.25)
        try raw { handle in
            try execute(handle, """
                INSERT INTO books VALUES('\(key(id))','漫画','book.cbr','作者','Books/book.cbr',123,1700000000000,'UTF-8','cbr');
                INSERT INTO document_positions(book_id,book_hash,format,locator_version,page_index,page_count,page_y,profile,manifest_hash,page_key,read_at_ms)
                VALUES('\(key(id))','\(hash)','cbr',1,1,3,0.25,'comic-order-v1','\(hash)','\(pageKey)',1700000400123);
                INSERT INTO document_bookmarks(local_id,book_id,position_key,format,locator_version,page_index,page_count,page_y,profile,manifest_hash,page_key,excerpt,created_at_ms)
                VALUES('20000000-0000-0000-0000-000000000004','\(key(id))','\(locator.positionKey)','cbr',1,1,3,0.25,'comic-order-v1','\(hash)','\(pageKey)','漫画原书签',1700000400124);
                """)
        }
        XCTAssertEqual(try rows("PRAGMA user_version"), [["4"]])
        XCTAssertFalse(try rows("SELECT sql FROM sqlite_master WHERE name='books'")[0][0]!.contains("kindle"))
        let before = try oldRows()
        let positions = try rows("SELECT * FROM document_positions ORDER BY book_id")
        let marks = try rows("SELECT * FROM document_bookmarks ORDER BY local_id")
        for _ in 0..<2 {
            let database = try LocalDatabase.open(root:root,defaults:defaults)
            defer { database.closeForTesting() }
            XCTAssertEqual(try oldRows(),before)
            XCTAssertEqual(try rows("SELECT * FROM document_positions ORDER BY book_id"),positions)
            XCTAssertEqual(try rows("SELECT * FROM document_bookmarks ORDER BY local_id"),marks)
            XCTAssertEqual(try database.documentPosition(bookID:id)?.locator,locator)
            XCTAssertEqual(try database.documentPosition(bookID:id)?.readAt.timeIntervalSince1970 ?? 0,1700000400.123,accuracy:0.001)
            XCTAssertEqual(try database.documentBookmarks(bookID:id).first?.locator,locator)
            XCTAssertEqual(try rows("PRAGMA foreign_key_check"),[])
            XCTAssertEqual(try rows("PRAGMA integrity_check"),[["ok"]])
            XCTAssertEqual(try rows("PRAGMA user_version"),[[String(LocalDatabase.schemaVersion)]])
        }
    }

    // These are the actual pre-comic v3 definitions, not a freshly created v4 database with a lower pragma.
    private func seedGenuineV3(comicV4:Bool = false) throws {
        let formats = comicV4 ? "'pdf','epub','cbz','cbr'" : "'pdf','epub'"
        let v4Checks = """
            ,CHECK((format='pdf' AND page_index IS NOT NULL AND page_count IS NOT NULL AND page_y IS NOT NULL
                AND page_index>=0 AND page_index<page_count AND page_count BETWEEN 1 AND 100000 AND page_y BETWEEN 0 AND 1
                AND resource IS NULL AND spine_index IS NULL AND spine_count IS NULL AND text_offset IS NULL AND text_length IS NULL
                AND profile IS NULL AND manifest_hash IS NULL AND page_key IS NULL AND text_hash IS NULL)
              OR (format='epub' AND resource IS NOT NULL AND spine_index IS NOT NULL AND spine_count IS NOT NULL
                AND text_offset IS NOT NULL AND text_length IS NOT NULL AND spine_index>=0 AND spine_index<spine_count
                AND spine_count BETWEEN 1 AND 10000 AND text_offset BETWEEN 0 AND text_length AND text_length BETWEEN 0 AND 2147483647
                AND page_index IS NULL AND page_count IS NULL AND page_y IS NULL
                AND profile IS NULL AND manifest_hash IS NULL AND page_key IS NULL AND text_hash IS NULL)
              OR (format IN ('cbz','cbr') AND page_index IS NOT NULL AND page_count IS NOT NULL AND page_y IS NOT NULL
                AND page_index>=0 AND page_index<page_count AND page_count BETWEEN 1 AND 10000 AND page_y BETWEEN 0 AND 1
                AND profile IS NOT NULL AND profile='comic-order-v1' AND manifest_hash IS NOT NULL AND page_key IS NOT NULL
                AND length(manifest_hash)=64 AND manifest_hash NOT GLOB '*[^0-9a-f]*'
                AND length(page_key)=64 AND page_key NOT GLOB '*[^0-9a-f]*'
                AND resource IS NULL AND spine_index IS NULL AND spine_count IS NULL AND text_offset IS NULL AND text_length IS NULL AND text_hash IS NULL))
            """
        let coordinates = "format TEXT NOT NULL CHECK(format IN (\(formats))),locator_version INTEGER NOT NULL CHECK(locator_version=1),page_index INTEGER,page_count INTEGER,page_y REAL,resource TEXT,spine_index INTEGER,spine_count INTEGER,text_offset INTEGER,text_length INTEGER" + (comicV4 ? ",profile TEXT,manifest_hash TEXT,page_key TEXT,text_hash TEXT" + v4Checks : "")
        let oldCoordinates = "format,locator_version,page_index,page_count,page_y,resource,spine_index,spine_count,text_offset,text_length"
        let positionColumns = comicV4 ? "read_at_ms INTEGER,\(coordinates)" : "\(coordinates),read_at_ms INTEGER"
        let bookmarkColumns = comicV4 ? "excerpt TEXT NOT NULL,created_at_ms INTEGER NOT NULL,\(coordinates)" : "\(coordinates),excerpt TEXT NOT NULL,created_at_ms INTEGER NOT NULL"
        try raw { handle in
            try execute(handle, """
                PRAGMA foreign_keys=ON;
                CREATE TABLE books(local_id TEXT PRIMARY KEY,title TEXT NOT NULL,source_name TEXT NOT NULL,author TEXT NOT NULL,
                    relative_path TEXT NOT NULL UNIQUE,file_size INTEGER NOT NULL CHECK(file_size>=0),source_modified_at_ms INTEGER,
                    encoding TEXT NOT NULL,format TEXT NOT NULL DEFAULT 'txt' CHECK(format IN ('txt',\(formats))));
                CREATE TABLE reading_progress(book_id TEXT PRIMARY KEY REFERENCES books(local_id) ON DELETE CASCADE,offset_bytes INTEGER NOT NULL CHECK(offset_bytes>=0),read_at_ms INTEGER);
                CREATE TABLE bookmarks(local_id TEXT PRIMARY KEY,book_id TEXT NOT NULL REFERENCES books(local_id) ON DELETE CASCADE,offset_bytes INTEGER NOT NULL CHECK(offset_bytes>=0),excerpt TEXT NOT NULL,created_at_ms INTEGER NOT NULL,UNIQUE(book_id,offset_bytes));
                CREATE TABLE toc_documents(book_id TEXT PRIMARY KEY REFERENCES books(local_id) ON DELETE CASCADE,source_file_size INTEGER NOT NULL,source_modified_at_ms INTEGER NOT NULL,encoding TEXT,generator_schema_version INTEGER NOT NULL);
                CREATE TABLE toc_entries(book_id TEXT NOT NULL REFERENCES toc_documents(book_id) ON DELETE CASCADE,ordinal INTEGER NOT NULL,entry_id TEXT NOT NULL,title TEXT NOT NULL,offset_bytes INTEGER NOT NULL,level INTEGER NOT NULL,PRIMARY KEY(book_id,ordinal));
                CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                CREATE TABLE sync_configuration(singleton_id INTEGER PRIMARY KEY CHECK(singleton_id=1),configured_email TEXT,authenticated_email TEXT,device_id TEXT,device_name TEXT,server_url TEXT,has_started INTEGER NOT NULL DEFAULT 0 CHECK(has_started IN (0,1)),credential_server_url TEXT,active_email TEXT,active_device_name TEXT);
                CREATE TABLE book_hash_cache(book_id TEXT PRIMARY KEY REFERENCES books(local_id) ON DELETE CASCADE,source_file_size INTEGER NOT NULL,source_modified_at_ms INTEGER NOT NULL,book_hash TEXT NOT NULL);
                CREATE TABLE remote_progress_cache(account_scope TEXT NOT NULL,book_hash TEXT NOT NULL,file_size INTEGER NOT NULL,offset_bytes INTEGER NOT NULL,read_at_ms INTEGER NOT NULL,version TEXT NOT NULL,source_device_id TEXT NOT NULL,source_device_name TEXT NOT NULL,source_platform TEXT NOT NULL,fetched_at_ms INTEGER,PRIMARY KEY(account_scope,book_hash,file_size));
                CREATE TABLE pending_file_deletions(relative_path TEXT PRIMARY KEY,requested_at_ms INTEGER NOT NULL);
                CREATE TABLE legacy_migrations(migration_id TEXT PRIMARY KEY,source_fingerprint TEXT NOT NULL,completed_at_ms INTEGER NOT NULL,imported_rows INTEGER NOT NULL);
                CREATE TABLE legacy_cleanup(migration_id TEXT PRIMARY KEY REFERENCES legacy_migrations(migration_id),source_fingerprint TEXT NOT NULL,state TEXT NOT NULL CHECK(state IN ('in_progress','completed')),started_at_ms INTEGER NOT NULL,completed_at_ms INTEGER,removed_items INTEGER NOT NULL DEFAULT 0 CHECK(removed_items>=0));
                CREATE TABLE document_positions(book_id TEXT PRIMARY KEY REFERENCES books(local_id) ON DELETE CASCADE,book_hash TEXT NOT NULL,\(positionColumns));
                CREATE TABLE document_bookmarks(local_id TEXT PRIMARY KEY,book_id TEXT NOT NULL REFERENCES books(local_id) ON DELETE CASCADE,position_key TEXT NOT NULL,\(bookmarkColumns),UNIQUE(book_id,position_key));
                PRAGMA user_version=\(comicV4 ? 4 : 3);
                """)
            for (id, format) in [(txtID, "txt"), (pdfID, "pdf"), (epubID, "epub")] {
                let content = Data("unchanged original \(format) bytes".utf8)
                try content.write(to: root.appending(path: "Books/old.\(format)"))
                try execute(handle, """
                    INSERT INTO books VALUES('\(key(id))','原书 \(format)','old.\(format)','原作者','Books/old.\(format)',\(content.count),1700000000000,'UTF-8','\(format)');
                    INSERT INTO reading_progress VALUES('\(key(id))',\(format == "txt" ? 3 : 0),1700000100000);
                    INSERT INTO book_hash_cache VALUES('\(key(id))',\(content.count),1700000000000,'\(String(repeating: "d", count: 64))');
                    """)
            }
            try execute(handle, """
                INSERT INTO bookmarks VALUES('20000000-0000-0000-0000-000000000001','\(key(txtID))',2,'TXT 原书签',1700000101000);
                INSERT INTO document_positions(book_id,book_hash,\(oldCoordinates),read_at_ms) VALUES('\(key(pdfID))','\(String(repeating: "a", count: 64))','pdf',1,1,3,0.25,NULL,NULL,NULL,NULL,NULL,1700000200000);
                INSERT INTO document_positions(book_id,book_hash,\(oldCoordinates),read_at_ms) VALUES('\(key(epubID))','\(String(repeating: "b", count: 64))','epub',1,NULL,NULL,NULL,'OPS/a.xhtml',1,2,8,40,1700000300000);
                INSERT INTO document_bookmarks(local_id,book_id,position_key,\(oldCoordinates),excerpt,created_at_ms) VALUES('\(key(pdfBookmarkID))','\(key(pdfID))','\(pdf.positionKey)','pdf',1,1,3,0.25,NULL,NULL,NULL,NULL,NULL,'PDF 原书签',1700000201000);
                INSERT INTO document_bookmarks(local_id,book_id,position_key,\(oldCoordinates),excerpt,created_at_ms) VALUES('\(key(epubBookmarkID))','\(key(epubID))','\(epub.positionKey)','epub',1,NULL,NULL,NULL,'OPS/a.xhtml',1,2,8,40,'EPUB 原书签',1700000301000);
                INSERT INTO settings VALUES('reader.theme','dark'),('reader.font_size','19'),('reader.line_spacing','8'),('future.unknown.setting','preserve');
                INSERT INTO sync_configuration VALUES(1,'reader@example.com','reader@example.com','30000000-0000-0000-0000-000000000001','原设备','https://sync.example.com',1,'https://sync.example.com','reader@example.com','原设备');
                INSERT INTO toc_documents VALUES('\(key(txtID))',28,1700000000000,'UTF-8',2);
                INSERT INTO toc_entries VALUES('\(key(txtID))',0,'40000000-0000-0000-0000-000000000001','原目录',0,0);
                INSERT INTO remote_progress_cache VALUES('reader@example.com','\(String(repeating: "d", count: 64))',28,3,1700000100000,'7','30000000-0000-0000-0000-000000000001','原设备','ios',1700000101000);
                INSERT INTO legacy_migrations VALUES('older-migration','unchanged-fingerprint',1700000000000,3);
                INSERT INTO legacy_cleanup VALUES('older-migration','unchanged-fingerprint','completed',1700000000000,1700000001000,2);
                """)
        }
    }

    private func makeBook(format: String) throws -> Book {
        let id = UUID(), content = Data("comic original \(format)".utf8)
        let relativePath = "Books/\(id.uuidString).\(format)"
        try content.write(to: root.appending(path: relativePath))
        var book = Book(id: id, title: "漫画", sourceName: "source.\(format)", author: "作者", relativePath: relativePath,
                        fileSize: Int64(content.count), modifiedAt: Date(timeIntervalSince1970: 1_700_000_000), encoding: .utf8,
                        offset: 0, updatedAt: Date(timeIntervalSince1970: 0), schemaVersion: Book.schemaVersion)
        book.format = format
        return book
    }

    private func oldRows() throws -> [String: [[String?]]] {
        let oldCoordinates = "format,locator_version,page_index,page_count,page_y,resource,spine_index,spine_count,text_offset,text_length"
        var selections = [
            "books": "local_id,title,source_name,author,relative_path,file_size,source_modified_at_ms,encoding,format",
            "document_positions": "book_id,book_hash," + oldCoordinates + ",read_at_ms",
            "document_bookmarks": "local_id,book_id,position_key," + oldCoordinates + ",excerpt,created_at_ms",
        ]
        for table in ["reading_progress", "bookmarks", "toc_documents", "toc_entries", "settings", "sync_configuration", "book_hash_cache", "remote_progress_cache", "pending_file_deletions", "legacy_migrations", "legacy_cleanup"] { selections[table] = "*" }
        var snapshot: [String: [[String?]]] = [:]
        for (table, columns) in selections { snapshot[table] = try rows("SELECT \(columns) FROM \(table) ORDER BY 1") }
        return snapshot
    }

    private func key(_ id: UUID) -> String { id.uuidString.lowercased() }
    private func columns(_ table: String) throws -> [String] { try rows("PRAGMA table_info(\(table))").compactMap { $0[1] } }
    private func rows(_ sql: String) throws -> [[String?]] { try raw { try rows($0, sql) } }
    private func raw<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(root.appending(path: "Metadata/xlib.db").path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil)
        guard status == SQLITE_OK, let handle else { throw LocalDatabaseError.sqlite("test database open failed") }
        defer { sqlite3_close(handle) }
        return try body(handle)
    }
    private func execute(_ handle: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw LocalDatabaseError.sqlite(String(cString: sqlite3_errmsg(handle))) }
    }
    private func rows(_ handle: OpaquePointer, _ sql: String) throws -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw LocalDatabaseError.sqlite(String(cString: sqlite3_errmsg(handle))) }
        defer { sqlite3_finalize(statement) }
        var result: [[String?]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw LocalDatabaseError.sqlite(String(cString: sqlite3_errmsg(handle))) }
            result.append((0..<sqlite3_column_count(statement)).map { index in
                sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_text(statement, index).map { String(cString: $0) }
            })
        }
    }
}
