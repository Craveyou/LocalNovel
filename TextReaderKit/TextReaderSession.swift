import Foundation
import SwiftUI

/// 新版阅读器唯一状态源：章节号 + 页码，所有导航都走这里，
/// UI 不各自记一份位置，也不从滚动偏移反推页码。
public final class TextReaderSession: ObservableObject {
    public let store: TextReaderStore

    @Published public var mode: TextReaderMode = .paged
    @Published public var fontSize: CGFloat = 18 {
        didSet { rebuildPages(restoreParagraph: currentParagraph) }
    }
    @Published public private(set) var book: TextBook?
    @Published public private(set) var chapters: [TextChapter] = []
    @Published public var chapterIndex = 0
    @Published public var pageIndex = 0 {
        didSet { saveAnchor() }
    }
    @Published public private(set) var pages: [TextPageSlice] = []

    private var contentSize = CGSize(width: 375, height: 600)

    public init(store: TextReaderStore = TextReaderStore()) {
        self.store = store
    }

    public var currentChapter: TextChapter? {
        guard chapters.indices.contains(chapterIndex) else { return nil }
        return chapters[chapterIndex]
    }

    public var paragraphs: [String] {
        guard let chapter = currentChapter else { return [] }
        return TextPaginator.paragraphs(in: chapter.text)
    }

    public var currentParagraph: Int {
        guard pages.indices.contains(pageIndex) else { return 0 }
        return pages[pageIndex].paragraph
    }

    private var anchorKey: String? {
        guard let book else { return nil }
        return "\(book.id)#\(chapterIndex)"
    }

    public func setContentSize(_ size: CGSize) {
        guard size.width > 40, size.height > 60, size != contentSize else { return }
        contentSize = size
        rebuildPages(restoreParagraph: currentParagraph)
    }

    public func open(_ book: TextBook, customPattern: String? = nil) {
        self.book = book
        let text = TextFileLoader.load(url: book.url)
        chapters = TextChapterSplitter.split(text: text, customPattern: customPattern)
        chapterIndex = 0
        let key = "\(book.id)#0"
        rebuildPages(restoreParagraph: store.anchor(for: key))
    }

    public func goChapter(_ index: Int, paragraph: Int? = nil) {
        guard chapters.indices.contains(index) else { return }
        chapterIndex = index
        let key = anchorKey
        rebuildPages(restoreParagraph: paragraph ?? store.anchor(for: key))
    }

    public func movePage(_ delta: Int) {
        let target = pageIndex + delta
        if target < 0, chapterIndex > 0 {
            goChapter(chapterIndex - 1, paragraph: Int.max)
            return
        }
        if target >= pages.count, chapterIndex + 1 < chapters.count {
            goChapter(chapterIndex + 1, paragraph: 0)
            return
        }
        pageIndex = min(max(target, 0), max(pages.count - 1, 0))
    }

    public func jumpToParagraph(_ paragraph: Int) {
        pageIndex = TextPaginator.pageIndex(forParagraph: paragraph, in: pages)
    }

    /// 滚动模式只记录位置，不改页码状态（翻页页码与滚动偏移彻底分离）。
    public func noteParagraph(_ paragraph: Int) {
        guard let key = anchorKey else { return }
        store.setAnchor(paragraph, for: key)
    }

    public func toggleBookmark() {
        guard let book, let chapter = currentChapter else { return }
        if let existing = store.bookmark(in: book.id,
                                          chapterIndex: chapterIndex,
                                          paragraph: currentParagraph) {
            store.removeBookmark(existing)
            return
        }
        let list = paragraphs
        let preview = list.indices.contains(currentParagraph)
            ? String(list[currentParagraph].prefix(40))
            : ""
        store.addBookmark(TextBookmark(bookID: book.id,
                                       chapterIndex: chapterIndex,
                                       chapterTitle: chapter.title,
                                       paragraph: currentParagraph,
                                       preview: preview))
    }

    public func addNote(text: String) {
        guard let book, let chapter = currentChapter, !text.isEmpty else { return }
        let list = paragraphs
        let quote = list.indices.contains(currentParagraph)
            ? String(list[currentParagraph].prefix(60))
            : ""
        store.addNote(TextNote(bookID: book.id,
                               chapterIndex: chapterIndex,
                               chapterTitle: chapter.title,
                               paragraph: currentParagraph,
                               quote: quote,
                               text: text))
    }

    private func rebuildPages(restoreParagraph: Int?) {
        let all = paragraphs
        pages = TextPaginator.paginate(paragraphs: all,
                                       size: contentSize,
                                       fontSize: fontSize,
                                       lineSpacing: 6)
        let fallback = anchorKey.flatMap { store.anchor(for: $0) } ?? 0
        let target = min(max(restoreParagraph ?? fallback, 0), max(all.count - 1, 0))
        pageIndex = TextPaginator.pageIndex(forParagraph: target, in: pages)
        saveAnchor()
    }

    private func saveAnchor() {
        guard let key = anchorKey else { return }
        store.setAnchor(currentParagraph, for: key)
    }
}
