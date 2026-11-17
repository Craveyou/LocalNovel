import Foundation
import SwiftUI

// MARK: - 书签与笔记（本地存储，按书分组）
//
// 只存三样东西：哪本书、哪一章、第几段，加上当时摘录的一小段原文。
// 位置沿用阅读记忆的段落锚点（blk-pN），所以章节重新分章后只要 id 不变就能对上。

struct ReaderBookmark: Codable, Identifiable, Equatable {
    var id: String
    var bookId: String
    var chapterId: String
    var chapterTitle: String
    /// 段落下标（0 开始）
    var paragraph: Int
    /// 摘录的原文片段，列表里做预览
    var preview: String
    var createdAt: Date
}

struct ReaderNote: Codable, Identifiable, Equatable {
    var id: String
    var bookId: String
    var chapterId: String
    var chapterTitle: String
    var paragraph: Int
    /// 摘录（可空）
    var quote: String
    /// 笔记正文
    var text: String
    var createdAt: Date
}

final class AnnotationStore: ObservableObject {
    static let shared = AnnotationStore()

    @Published private(set) var bookmarks: [ReaderBookmark] = []
    @Published private(set) var notes: [ReaderNote] = []

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let bookmarks = "LocalNovel.bookmarks"
        static let notes = "LocalNovel.notes"
    }

    private init() {
        if let data = defaults.data(forKey: Keys.bookmarks),
           let list = try? JSONDecoder().decode([ReaderBookmark].self, from: data) {
            bookmarks = list
        }
        if let data = defaults.data(forKey: Keys.notes),
           let list = try? JSONDecoder().decode([ReaderNote].self, from: data) {
            notes = list
        }
    }

    // MARK: 查询

    func bookmarks(in bookId: String) -> [ReaderBookmark] {
        bookmarks.filter { $0.bookId == bookId }.sorted { $0.createdAt > $1.createdAt }
    }

    func notes(in bookId: String) -> [ReaderNote] {
        notes.filter { $0.bookId == bookId }.sorted { $0.createdAt > $1.createdAt }
    }

    func bookmark(in bookId: String, chapterId: String, paragraph: Int) -> ReaderBookmark? {
        bookmarks.first {
            $0.bookId == bookId && $0.chapterId == chapterId && $0.paragraph == paragraph
        }
    }

    // MARK: 书签

    @discardableResult
    func addBookmark(bookId: String, chapterId: String, chapterTitle: String,
                     paragraph: Int, preview: String) -> ReaderBookmark {
        let mark = ReaderBookmark(id: UUID().uuidString, bookId: bookId,
                                  chapterId: chapterId, chapterTitle: chapterTitle,
                                  paragraph: paragraph, preview: preview,
                                  createdAt: Date())
        bookmarks.append(mark)
        persist()
        return mark
    }

    func remove(_ bookmark: ReaderBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        persist()
    }

    // MARK: 笔记

    @discardableResult
    func addNote(bookId: String, chapterId: String, chapterTitle: String,
                 paragraph: Int, quote: String, text: String) -> ReaderNote {
        let note = ReaderNote(id: UUID().uuidString, bookId: bookId,
                              chapterId: chapterId, chapterTitle: chapterTitle,
                              paragraph: paragraph, quote: quote, text: text,
                              createdAt: Date())
        notes.append(note)
        persist()
        return note
    }

    func update(_ note: ReaderNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index] = note
        persist()
    }

    func remove(_ note: ReaderNote) {
        notes.removeAll { $0.id == note.id }
        persist()
    }

    // MARK: 导出

    /// 导出成纯文本（章节 + 摘录 + 笔记），返回可用 ShareLink 的临时文件
    func exportFile(bookTitle: String, bookId: String) -> URL? {
        let list = notes(in: bookId)
        guard !list.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var text = "《\(bookTitle)》读书笔记\n共 \(list.count) 条\n\n"
        for note in list.reversed() {
            text += "【\(note.chapterTitle)】  \(formatter.string(from: note.createdAt))\n"
            if !note.quote.isEmpty { text += "摘录：\(note.quote)\n" }
            text += "笔记：\(note.text)\n"
            text += String(repeating: "-", count: 24) + "\n"
        }

        let safeTitle = bookTitle.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeTitle) 笔记.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            defaults.set(data, forKey: Keys.bookmarks)
        }
        if let data = try? JSONEncoder().encode(notes) {
            defaults.set(data, forKey: Keys.notes)
        }
    }
}
