import Foundation

// MARK: - 单文件小说自动分章
//
// 小说分区里「一个文件 = 一本书」，但阅读器是按章翻的，所以要把整本正文
// 按「第X章 / 第X卷 / Chapter N / 序章 / 番外」这类标题行切开。
// 切不出来（或只有一处）就整本一章，绝不因为正则不匹配把书弄丢。

enum ChapterSplitter {

    struct Slice {
        let title: String
        /// UTF-16 区间，与 NSString / NSAttributedString 一致
        let range: NSRange
    }

    /// 标题行最大长度：超过这个长度的行多半是正文里恰好以「第一章」开头的句子
    private static let maxTitleLength = 48

    /// 只在行首匹配，避免正文中提及「第三章」时被误判
    private static let headingPattern: NSRegularExpression? = {
        let pattern = "^[\\s　]*("
            + "第[0-9０-９一二三四五六七八九十百千万零〇两]{1,8}[章节回卷话集篇部]"
            + "|Chapter\\s+\\d{1,4}"
            + "|(序章|序言|楔子|引子|前言|尾声|终章|后记|番外|外传)[\\s　:：·、-]*"
            + ")"
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    static func split(_ text: String) -> [Slice] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard ns.length > 0 else { return [Slice(title: "", range: full)] }

        var headings: [(title: String, start: Int, bodyStart: Int)] = []
        var index = 0
        while index < ns.length {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                            for: NSRange(location: index, length: 0))
            let contentLength = max(0, contentsEnd - lineStart)
            // 先看长度，再决定要不要把这一行取出来。
            // 整本几十 MB 有上百万行，原来每行都 substring 一次，
            // 会瞬间产生上百万个临时字符串，主线程直接卡到被系统杀掉
            // （表现就是「加载大文件小说时闪退」）。
            if contentLength > 0, contentLength <= maxTitleLength * 2 {
                let line = ns.substring(with: NSRange(location: lineStart, length: contentLength))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty,
                   line.count <= maxTitleLength,
                   headingPattern?.firstMatch(in: line,
                                              options: [],
                                              range: NSRange(location: 0, length: (line as NSString).length)) != nil {
                    headings.append((compact(line), lineStart, lineEnd))
                }
            }
            let next = lineEnd
            if next <= index { break }
            index = next
        }

        guard headings.count >= 2 else {
            return [Slice(title: "", range: full)]
        }

        var slices: [Slice] = []

        // 第一章之前若有正文（书名页 / 简介），单独作为「开篇」
        if let first = headings.first, first.start > 0 {
            let head = NSRange(location: 0, length: first.start)
            if !ns.substring(with: head).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                slices.append(Slice(title: "开篇", range: head))
            }
        }

        for (i, heading) in headings.enumerated() {
            let end = i + 1 < headings.count ? headings[i + 1].start : ns.length
            // 正文从标题行的下一行开始：标题已经在阅读器顶部显示，不重复出现
            let bodyStart = min(heading.bodyStart, end)
            let range: NSRange
            if bodyStart < end {
                range = NSRange(location: bodyStart, length: end - bodyStart)
            } else {
                range = NSRange(location: heading.start, length: max(0, end - heading.start))
            }
            let title = heading.title.isEmpty ? "第 \(i + 1) 章" : heading.title
            slices.append(Slice(title: title, range: range))
        }
        return slices
    }

    /// 标题压缩：去掉多余空白与章节号后的全角空格
    private static func compact(_ line: String) -> String {
        var s = line
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        if s.count > maxTitleLength { s = String(s.prefix(maxTitleLength)) }
        return s
    }
}
