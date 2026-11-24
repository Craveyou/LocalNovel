import Foundation

// MARK: - epub 解析（只取文字）
// 结构：META-INF/container.xml → OPF（manifest / spine）→ 逐个 xhtml 取正文。
// 故意不做样式与内嵌图片：小说正文是文字；漫画请用「漫画」分区（图片或 pdf）。
// 解析结果按「路径 + 修改时间」缓存，切章与阅读共用一次解包。

enum EpubParser {

    final class Parsed {
        let fullText: String
        /// 每章的标题与在 fullText 中的 UTF-16 区间
        let chapters: [(title: String, range: NSRange)]

        init(fullText: String, chapters: [(title: String, range: NSRange)]) {
            self.fullText = fullText
            self.chapters = chapters
        }
    }

    private static let cache = NSCache<NSString, Parsed>()

    static func parsed(url: URL) -> Parsed? {
        let key = cacheKey(url)
        if let hit = cache.object(forKey: key) { return hit }
        guard let archive = ZipArchive(url: url) else { return nil }
        guard let value = build(archive: archive) else { return nil }
        cache.setObject(value, forKey: key)
        return value
    }

    static func plainText(url: URL) throws -> String {
        guard let parsed = parsed(url: url), !parsed.fullText.isEmpty else {
            throw TextLoader.TextError.epubUnreadable(url)
        }
        return parsed.fullText
    }

    static func slices(url: URL) -> [ChapterSplitter.Slice] {
        guard let parsed = parsed(url: url), !parsed.chapters.isEmpty else { return [] }
        return parsed.chapters.map { ChapterSplitter.Slice(title: $0.title, range: $0.range) }
    }

    // MARK: - 组装

    private static func build(archive: ZipArchive) -> Parsed? {
        guard let containerName = archive.entryName(endingWith: "META-INF/container.xml"),
              let container = archive.text(for: containerName),
              let opfPath = firstMatch(container, pattern: "full-path\\s*=\\s*\"([^\"]+)\"")
        else { return nil }

        let opfName = archive.entryName(endingWith: opfPath) ?? opfPath
        guard let opf = archive.text(for: opfName) else { return nil }
        let baseDir = (opfName as NSString).deletingLastPathComponent

        let manifest = manifestItems(opf)
        let spine = spineOrder(opf)

        var ordered: [(title: String, href: String)] = []
        if !spine.isEmpty {
            for id in spine {
                if let item = manifest[id] {
                    ordered.append((title: "", href: item))
                }
            }
        }
        if ordered.isEmpty {
            ordered = manifest.values.sorted().map { (title: "", href: $0) }
        }
        guard !ordered.isEmpty else { return nil }

        var full = ""
        var chapters: [(title: String, range: NSRange)] = []

        for (index, item) in ordered.enumerated() {
            let path = resolve(base: baseDir, href: item.href)
            guard let entryName = archive.entryName(endingWith: path),
                  let html = archive.text(for: entryName) else { continue }
            let text = plainText(fromHTML: html).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if !full.isEmpty { full += "\n\n" }
            let start = (full as NSString).length
            full += text

            var title = heading(in: html) ?? ""
            if title.isEmpty {
                title = ((item.href as NSString).lastPathComponent as NSString).deletingPathExtension
                title = title.removingPercentEncoding ?? title
            }
            if title.isEmpty { title = "第 \(index + 1) 章" }
            chapters.append((title: title, range: NSRange(location: start,
                                                          length: (text as NSString).length)))
        }

        guard !full.isEmpty else { return nil }
        return Parsed(fullText: full, chapters: chapters)
    }

    /// manifest：id → href（只保留 html / xhtml）
    private static func manifestItems(_ opf: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "(?is)<item\\b([^>]*)>") else { return result }
        let ns = opf as NSString
        for match in regex.matches(in: opf, range: NSRange(location: 0, length: ns.length)) {
            let attrs = ns.substring(with: match.range(at: 1))
            guard let id = firstMatch(attrs, pattern: "id\\s*=\\s*\"([^\"]+)\""),
                  let href = firstMatch(attrs, pattern: "href\\s*=\\s*\"([^\"]+)\"")
            else { continue }
            let media = firstMatch(attrs, pattern: "media-type\\s*=\\s*\"([^\"]+)\"") ?? ""
            if media.isEmpty || media.contains("html") {
                result[id] = href
            }
        }
        return result
    }

    private static func spineOrder(_ opf: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?is)<itemref\\b[^>]*idref\\s*=\\s*\"([^\"]+)\"")
        else { return [] }
        let ns = opf as NSString
        return regex.matches(in: opf, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    private static func resolve(base: String, href: String) -> String {
        let decoded = (href.removingPercentEncoding ?? href).trimmingCharacters(in: .whitespaces)
        if decoded.hasPrefix("/") { return String(decoded.dropFirst()) }
        var parts = base.isEmpty ? [] : base.split(separator: "/").map(String.init)
        for comp in decoded.split(separator: "/") {
            if comp == ".." {
                if !parts.isEmpty { parts.removeLast() }
            } else if comp == "." {
                continue
            } else {
                parts.append(String(comp))
            }
        }
        return parts.joined(separator: "/")
    }

    // MARK: - HTML → 纯文本

    static func plainText(fromHTML html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>",
                                   with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)</(p|div|h[1-6]|li|tr|section|article|blockquote)>",
                                   with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?s)<[^>]+>", with: "", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "[\\t\\u{00A0}\\u{3000}]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func heading(in html: String) -> String? {
        for tag in ["h1", "h2", "h3", "title"] {
            guard let regex = try? NSRegularExpression(pattern: "(?is)<\(tag)[^>]*>(.*?)</\(tag)>")
            else { continue }
            let ns = html as NSString
            guard let match = regex.firstMatch(in: html,
                                               range: NSRange(location: 0, length: ns.length))
            else { continue }
            let inner = ns.substring(with: match.range(at: 1))
            let text = plainText(fromHTML: inner).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
    }

    private static func decodeEntities(_ input: String) -> String {
        var t = input
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&hellip;", with: "…")
        guard t.contains("&#") else { return t }
        guard let regex = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);") else { return t }
        let matches = regex.matches(in: t, range: NSRange(location: 0, length: (t as NSString).length))
        for match in matches.reversed() {
            let ns = t as NSString
            let token = ns.substring(with: match.range(at: 1))
            let value: UInt32?
            if token.hasPrefix("x") || token.hasPrefix("X") {
                value = UInt32(token.dropFirst(), radix: 16)
            } else {
                value = UInt32(token, radix: 10)
            }
            guard let v = value, let scalar = Unicode.Scalar(v) else { continue }
            t = ns.replacingCharacters(in: match.range, with: String(Character(scalar)))
        }
        return t
    }

    private static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func cacheKey(_ url: URL) -> NSString {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let stamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        return "\(url.path)|\(stamp)|\(size)" as NSString
    }
}
