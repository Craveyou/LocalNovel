import Foundation

public enum TextSearchEngine {
    public static func search(query raw: String,
                              chapters: [TextChapter],
                              limit: Int = 200) -> [TextSearchHit] {
        let keyword = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.count >= 2 else { return [] }

        var hits: [TextSearchHit] = []
        for (chapterIndex, chapter) in chapters.enumerated() {
            let paragraphs = TextPaginator.paragraphs(in: chapter.text)
            for (paragraph, text) in paragraphs.enumerated() {
                guard let snippet = snippet(in: text, keyword: keyword) else { continue }
                hits.append(TextSearchHit(id: "\(chapter.id)#\(paragraph)",
                                          chapterIndex: chapterIndex,
                                          chapterTitle: chapter.title,
                                          paragraph: paragraph,
                                          snippet: snippet))
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }

    private static func snippet(in text: String, keyword: String) -> String? {
        let ns = text as NSString
        let found = ns.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive])
        guard found.location != NSNotFound else { return nil }
        let start = max(0, found.location - 12)
        let end = min(ns.length, found.location + found.length + 12)
        let window = ns.rangeOfComposedCharacterSequences(for: NSRange(location: start,
                                                                        length: end - start))
        var result = ns.substring(with: window)
        if window.location > 0 { result = "…" + result }
        if window.location + window.length < ns.length { result += "…" }
        return result
    }
}
