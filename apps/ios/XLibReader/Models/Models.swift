import AppleShared
import Foundation

struct Book: Codable, Identifiable, Hashable, Sendable {
    static let schemaVersion = 1

    let id: UUID
    var title: String
    var sourceName: String
    var author: String
    var relativePath: String
    var fileSize: Int64
    var modifiedAt: Date
    var encoding: TextEncoding
    var offset: Int64
    var updatedAt: Date
    var schemaVersion: Int

    var format: String = "txt"
    var documentLocator: DocumentLocator?

    var progress: Double {
        if format != "txt" { return documentLocator?.progress ?? 0 }
        guard fileSize > 0 else { return 0 }
        return min(1, max(0, Double(offset) / Double(fileSize)))
    }

    var displayAuthor: String { author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "佚名" : author }
}

extension Book {
    private enum CodingKeys: String, CodingKey {
        case id, title, sourceName, author, relativePath, fileSize, modifiedAt, encoding, offset, updatedAt, schemaVersion, format, documentLocator
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sourceName = try c.decode(String.self, forKey: .sourceName)
        author = try c.decode(String.self, forKey: .author)
        relativePath = try c.decode(String.self, forKey: .relativePath)
        fileSize = try c.decode(Int64.self, forKey: .fileSize)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        encoding = try c.decode(TextEncoding.self, forKey: .encoding)
        offset = try c.decode(Int64.self, forKey: .offset)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? "txt"
        documentLocator = try c.decodeIfPresent(DocumentLocator.self, forKey: .documentLocator)
    }
}

struct DocumentBookmark: Identifiable, Hashable, Sendable {
    let id: UUID
    let locator: DocumentLocator
    let excerpt: String
    let createdAt: Date
}

struct Bookmark: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let bookID: UUID
    let offset: Int64
    let excerpt: String
    let createdAt: Date
}

struct TocEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let offset: Int64
    let level: Int
}

struct TocDocument: Codable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let fileSize: Int64
    let modifiedAt: Date
    let entries: [TocEntry]
}

struct LibrarySnapshot: Codable, Sendable {
    var schemaVersion = 1
    var books: [Book] = []
    var tombstones: [UUID] = []
}

struct BookmarksSnapshot: Codable, Sendable {
    var schemaVersion = 1
    var bookmarks: [Bookmark] = []
}
