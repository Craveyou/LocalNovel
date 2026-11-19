import Foundation

/// A shared display adapter, not a conversion of Kindle coordinates into EPUB coordinates.
public struct ReflowDocument: Sendable {
    public struct Chapter: Sendable {
        public let resource: String
        public let html: String
        public let text: String
        public let anchors: [String: Int]
    }
    public struct Toc: Sendable { public let title: String; public let chapter: Int; public let offset: Int }
    private enum Source: Sendable { case epub(EPUBDocument), kindle(KindleDocument) }
    private let source: Source
    public let chapters: [Chapter]
    public let toc: [Toc]
    public let isKindle: Bool
    public init(_ document: EPUBDocument) {
        source = .epub(document); isKindle = false
        chapters = document.chapters.map { Chapter(resource: $0.resource, html: $0.html, text: $0.text, anchors: $0.anchors) }
        toc = document.toc.map { Toc(title: $0.title, chapter: $0.chapter, offset: $0.offset) }
    }
    public init(_ document: KindleDocument) {
        source = .kindle(document); isKindle = true
        chapters = document.chapters.map { Chapter(resource: $0.resource, html: $0.html, text: $0.text, anchors: $0.anchors) }
        toc = document.toc.map { Toc(title: $0.title, chapter: $0.unit, offset: $0.offset) }
    }
    public func locator(chapter: Int, offset: Int) -> DocumentLocator {
        switch source { case .epub(let d): d.locator(chapter: chapter, offset: offset); case .kindle(let d): d.locator(chapter: chapter, offset: offset) }
    }
    public func valid(_ value: DocumentLocator) -> Bool {
        switch source { case .epub(let d): d.valid(value); case .kindle(let d): d.valid(value) }
    }
    public func chapterIndex(for value: DocumentLocator) -> Int? {
        guard valid(value) else { return nil }
        switch source { case .epub: return value.unit; case .kindle(let d): return d.chapterIndex(for: value) }
    }
    public func localOffset(for value: DocumentLocator) -> Int? {
        guard valid(value) else { return nil }
        switch source {
        case .epub: if case .epub(_, _, _, let offset, _) = value { return offset }; return nil
        case .kindle(let d): return d.localOffset(for: value)
        }
    }
    public func read(_ path: String) throws -> Data {
        switch source { case .epub(let d): try d.read(path); case .kindle(let d): try d.read(path) }
    }
}
