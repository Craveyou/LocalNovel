import Foundation

public enum TextChapterSplitter {
    /// 只处理纯文本小说：第X章 / Chapter N / 序章 / 番外。
    public static let defaultPattern = #"(?m)^\s*(第[零〇一二三四五六七八九十百千万0-9]+[章节回卷部篇][^\n]*|Chapter\s+\d+[^\n]*|序章[^\n]*|番外[^\n]*)$"#

    public static func split(text: String, customPattern: String? = nil) -> [TextChapter] {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard ns.length > 0 else { return [] }

        let trimmed = customPattern?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pattern = trimmed.isEmpty ? defaultPattern : trimmed
        let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])

        var starts: [Int] = [0]
        var titles: [String] = ["开篇"]
        if let regex {
            for match in regex.matches(in: text, options: [], range: fullRange) where match.range.location > 0 {
                let title = ns.substring(with: match.range)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                starts.append(match.range.location)
                titles.append(title)
            }
        }

        // 正则写错或一个都没命中：整本一章，绝不把书切空。
        if starts.count == 1 {
            return [TextChapter(id: "c0", title: "全文", range: fullRange, text: text)]
        }

        var chapters: [TextChapter] = []
        chapters.reserveCapacity(starts.count)
        for index in starts.indices {
            let location = starts[index]
            let length: Int
            if index + 1 < starts.count {
                length = starts[index + 1] - location
            } else {
                length = ns.length - location
            }
            guard length > 0 else { continue }
            let range = NSRange(location: location, length: length)
            chapters.append(TextChapter(id: "c\(location)",
                                        title: titles[index],
                                        range: range,
                                        text: ns.substring(with: range)))
        }
        return chapters.isEmpty
            ? [TextChapter(id: "c0", title: "全文", range: fullRange, text: text)]
            : chapters
    }
}
