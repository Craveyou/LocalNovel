import Foundation

// MARK: - 单文件小说自动分章
//
// 小说分区里「一个文件 = 一本书」，但阅读器是按章翻的，所以要把整本正文
// 按「第X章 / 第X卷 / Chapter N / 序章 / 番外」这类标题行切开。
// 切不出来（或只有一处）就整本一章，绝不因为正则不匹配把书弄丢。
//
// 用户可在目录面板里给某一本写「重新分章」规则（Preferences.chapterRules）。
// 规则只对那一本生效，且永远是「自定义优先、内置兜底」——
// 规则写错或切不出章时退回内置正则，最差也是整本一章，不会变成空书。

enum ChapterSplitter {

    struct Slice {
        let title: String
        /// UTF-16 区间，与 NSString / NSAttributedString 一致
        let range: NSRange
    }

    /// 预览结果：能切出多少章、前几条标题、是否退回了内置规则
    struct Preview {
        /// 用这条规则（在这段样本上）切出的章节数
        let count: Int
        let titles: [String]
        /// true = 这条规则切不出两章，实际会退回内置正则
        let usesFallback: Bool
        /// 规则本身的编译错误 / 提示
        let message: String?
        /// 预览用的样本行数（不是全书）
        let sampleLines: Int
    }

    /// 标题行最大长度：超过这个长度的行多半是正文里恰好以「第一章」开头的句子
    private static let maxTitleLength = 48

    /// 内置规则：只在行首匹配，避免正文中提及「第三章」时被误判
    private static let headingPatternText = "^[\\s　]*("
        + "第[0-9０-９一二三四五六七八九十百千万零〇两]{1,8}[章节回卷话集篇部]"
        + "|Chapter\\s+\\d{1,4}"
        + "|(序章|序言|楔子|引子|前言|尾声|终章|后记|番外|外传)[\\s　:：·、-]*"
        + ")"

    private static let headingPattern: NSRegularExpression? = makePattern(headingPatternText)

    /// 界面上的几条常用规则（点一下就填进输入框，可再改）
    struct Preset: Identifiable {
        let label: String
        let pattern: String
        var id: String { label }
    }

    static let presets: [Preset] = [
        Preset(label: "第X章", pattern: "^第[0-9０-９一二三四五六七八九十百千万零〇两]{1,8}[章节回卷话集篇部]"),
        Preset(label: "数字开头", pattern: "^\\s*\\d{1,5}\\s*[.、,，:：]?\\s*\\S"),
        Preset(label: "Chapter N", pattern: "^Chapter\\s+\\d{1,4}"),
        Preset(label: "卷 / 部", pattern: "^第[0-9一二三四五六七八九十百千零〇两]{1,6}[卷部篇]"),
    ]

    /// 编译用户写的正则；写错返回 nil（调用方据此回退内置规则）
    static func makePattern(_ pattern: String) -> NSRegularExpression? {
        let text = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: text, options: [.caseInsensitive])
    }

    /// 编译失败的原因（给界面显示，空串表示没问题）
    static func validate(_ pattern: String) -> String? {
        let text = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "规则为空" }
        do {
            _ = try NSRegularExpression(pattern: text, options: [.caseInsensitive])
            return nil
        } catch {
            return "正则写错了：\(error.localizedDescription)"
        }
    }

    /// 切章。customPattern 非空时优先用它；切不出两章就退回内置规则，
    /// 任何情况下都至少返回一章（整本），绝不让书变空。
    static func split(_ text: String, customPattern: NSRegularExpression? = nil) -> [Slice] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard ns.length > 0 else { return [Slice(title: "", range: full)] }

        if let customPattern {
            let custom = slices(in: ns, pattern: customPattern)
            if custom.count >= 2 { return custom }
        }
        guard let headingPattern else { return [Slice(title: "", range: full)] }
        let builtIn = slices(in: ns, pattern: headingPattern)
        guard builtIn.count >= 2 else { return [Slice(title: "", range: full)] }
        return builtIn
    }

    /// 预览：只在一段样本上跑规则，告诉用户「能切出多少章、前几条标题」
    static func preview(_ text: String, pattern: String, limit: Int = 6) -> Preview {
        let ns = text as NSString
        let lines = lineCount(ns)
        if let problem = validate(pattern) {
            return Preview(count: 0, titles: [], usesFallback: true,
                           message: problem, sampleLines: lines)
        }
        guard let regex = makePattern(pattern) else {
            return Preview(count: 0, titles: [], usesFallback: true,
                           message: "规则无效", sampleLines: lines)
        }
        let found = slices(in: ns, pattern: regex)
        let titles = found.prefix(limit).map(\.title)
        if found.count >= 2 {
            return Preview(count: found.count, titles: titles, usesFallback: false,
                           message: nil, sampleLines: lines)
        }
        return Preview(count: found.count, titles: titles, usesFallback: true,
                       message: "这条规则在样本里切不出多章（命中标题行少于 2 条），应用时会退回自动分章",
                       sampleLines: lines)
    }

    /// 取正文前 maxLines 行做预览样本（整本几十 MB 时不必把全文读进界面）
    static func sample(from url: URL,
                       maxLines: Int = 2000,
                       preferred: TextEncodingOption = .auto) -> String? {
        guard let full = try? TextLoader.loadDocument(url, preferred: preferred) else { return nil }
        let ns = full as NSString
        guard ns.length > 0 else { return "" }
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        var index = 0
        var count = 0
        var cut = ns.length
        while index < ns.length {
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                            for: NSRange(location: index, length: 0))
            count += 1
            if count >= maxLines {
                cut = lineEnd
                break
            }
            let next = lineEnd
            if next <= index { break }
            index = next
        }
        return ns.substring(with: NSRange(location: 0, length: cut))
    }

    // MARK: - 内部

    /// 逐行找标题行，返回标题与其在整段文本里的区间
    private static func slices(in ns: NSString, pattern: NSRegularExpression) -> [Slice] {
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
                   pattern.firstMatch(in: line,
                                      options: [],
                                      range: NSRange(location: 0, length: (line as NSString).length)) != nil {
                    headings.append((compact(line), lineStart, lineEnd))
                }
            }
            let next = lineEnd
            if next <= index { break }
            index = next
        }

        guard headings.count >= 2 else { return [] }

        var result: [Slice] = []

        // 第一章之前若有正文（书名页 / 简介），单独作为「开篇」
        if let first = headings.first, first.start > 0 {
            let head = NSRange(location: 0, length: first.start)
            if !ns.substring(with: head).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(Slice(title: "开篇", range: head))
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
            result.append(Slice(title: title, range: range))
        }
        return result
    }

    /// 样本行数（预览里告诉用户「这是前 N 行」）
    private static func lineCount(_ ns: NSString) -> Int {
        guard ns.length > 0 else { return 0 }
        var count = 0
        var index = 0
        while index < ns.length {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                            for: NSRange(location: index, length: 0))
            count += 1
            let next = lineEnd
            if next <= index { break }
            index = next
        }
        return count
    }

    /// 标题压缩：去掉多余空白与章节号后的全角空格
    private static func compact(_ line: String) -> String {
        var s = line
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        if s.count > maxTitleLength { s = String(s.prefix(maxTitleLength)) }
        return s
    }
}
