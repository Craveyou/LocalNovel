import Foundation

/// 纯文本小说。新版只认这一类，不再混 epub / pdf / 图片 / 音视频。
public struct TextBook: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let url: URL

    public init(id: String? = nil, title: String, url: URL) {
        self.id = id ?? url.standardizedFileURL.path
        self.title = title
        self.url = url
    }
}

public struct TextChapter: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let range: NSRange
    public let text: String

    public init(id: String, title: String, range: NSRange, text: String) {
        self.id = id
        self.title = title
        self.range = range
        self.text = text
    }
}

public struct TextSearchHit: Identifiable, Hashable {
    public let id: String
    public let chapterIndex: Int
    public let chapterTitle: String
    public let paragraph: Int
    public let snippet: String
}

public struct TextBookmark: Codable, Identifiable, Hashable {
    public var id: String
    public var bookID: String
    public var chapterIndex: Int
    public var chapterTitle: String
    public var paragraph: Int
    public var preview: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString,
                bookID: String,
                chapterIndex: Int,
                chapterTitle: String,
                paragraph: Int,
                preview: String,
                createdAt: Date = Date()) {
        self.id = id
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.paragraph = paragraph
        self.preview = preview
        self.createdAt = createdAt
    }
}

public struct TextNote: Codable, Identifiable, Hashable {
    public var id: String
    public var bookID: String
    public var chapterIndex: Int
    public var chapterTitle: String
    public var paragraph: Int
    public var quote: String
    public var text: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString,
                bookID: String,
                chapterIndex: Int,
                chapterTitle: String,
                paragraph: Int,
                quote: String,
                text: String,
                createdAt: Date = Date()) {
        self.id = id
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.paragraph = paragraph
        self.quote = quote
        self.text = text
        self.createdAt = createdAt
    }
}

public enum TextReaderMode: String, CaseIterable, Identifiable {
    case paged
    case scroll

    public var id: String { rawValue }
    public var label: String { self == .paged ? "翻页" : "滚动" }
}
