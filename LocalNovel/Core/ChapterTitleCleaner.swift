import Foundation

// MARK: - 章节标题清洗（可选工具）
// 章节名就是文件夹名，默认原样展示；本工具用于用户将来想去掉「01_」「第1章 」这类前缀时启用。
// 排序始终用文件夹原名走自然排序，因此不依赖本工具也能保证 1,2,...,10 的顺序正确。

enum ChapterTitleCleaner {
    private static let patterns = [
        // 01_ / 1. / 2、 / [3] / 【4】 开头的纯序号前缀
        "^\\s*[\\[\\(【]?\\d+[\\]\\)】]?\\s*[._\\-、:：]?\\s*",
        "^\\s*[\\[\\(【]?\\d+[\\]\\)】]\\s*",
        // 第01章 / 第三章 形式的前缀（保留其后标题）
        "^\\s*第[0-9一二三四五六七八九十百千零〇两]+[章节回部卷集篇]\\s*[.、:：]?\\s*"
    ]

    static func clean(_ raw: String) -> String {
        let normalized = NaturalSort.normalize(raw)
        var result = normalized
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p, options: []) else { continue }
            let range = NSRange(location: 0, length: result.utf16.count)
            if let m = regex.firstMatch(in: result, options: [], range: range),
               let r = Range(m.range, in: result), !r.isEmpty {
                result = String(result[r.upperBound...])
                break
            }
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? raw : trimmed
    }
}
