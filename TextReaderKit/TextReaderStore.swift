import Foundation
import SwiftUI

private struct TextReaderSnapshot: Codable {
    var anchors: [String: Int] = [:]
    var bookmarks: [TextBookmark] = []
    var notes: [TextNote] = []
}

public final class TextReaderStore: ObservableObject {
    @Published private(set) var anchors: [String: Int] = [:]
    @Published private(set) var bookmarks: [TextBookmark] = []
    @Published private(set) var notes: [TextNote] = []

    private let fileURL: URL
    private var snapshot = TextReaderSnapshot()

    public init(fileURL: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = fileURL ?? directory
            .appendingPathComponent("TextReaderKit", isDirectory: true)
            .appendingPathComponent("state.json")
        load()
    }

    public func anchor(for bookID: String) -> Int? { anchors[bookID] }

    public func setAnchor(_ paragraph: Int, for bookID: String) {
        anchors[bookID] = max(0, paragraph)
        save()
    }

    public func bookmarks(in bookID: String) -> [TextBookmark] {
        bookmarks.filter { $0.bookID == bookID }.sorted { $0.createdAt > $1.createdAt }
    }

    public func notes(in bookID: String) -> [TextNote] {
        notes.filter { $0.bookID == bookID }.sorted { $0.createdAt > $1.createdAt }
    }

    public func bookmark(in bookID: String, chapterIndex: Int, paragraph: Int) -> TextBookmark? {
        bookmarks.first {
            $0.bookID == bookID && $0.chapterIndex == chapterIndex && $0.paragraph == paragraph
        }
    }

    @discardableResult
    public func addBookmark(_ bookmark: TextBookmark) -> TextBookmark {
        bookmarks.append(bookmark)
        save()
        return bookmark
    }

    public func removeBookmark(_ bookmark: TextBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        save()
    }

    @discardableResult
    public func addNote(_ note: TextNote) -> TextNote {
        notes.append(note)
        save()
        return note
    }

    public func updateNote(_ note: TextNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index] = note
        save()
    }

    public func removeNote(_ note: TextNote) {
        notes.removeAll { $0.id == note.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(TextReaderSnapshot.self, from: data) else { return }
        snapshot = decoded
        anchors = decoded.anchors
        bookmarks = decoded.bookmarks
        notes = decoded.notes
    }

    private func save() {
        snapshot.anchors = anchors
        snapshot.bookmarks = bookmarks
        snapshot.notes = notes
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
