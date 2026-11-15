import Foundation
import CoreFoundation
import PDFKit

// MARK: - 正文读取：编码自动检测 + 段落切分
// 支持 txt / md（自动识别 UTF-8 / UTF-16 / GB18030 / Big5）、epub（解包取文字）、pdf（抽取文字）。
// 检测失败时给出明确错误，不静默返回乱码。

enum TextLoader {
    enum TextError: LocalizedError {
        case unreadable(URL)
        case undecodable(URL)
        case pdfWithoutText(URL)
        case epubUnreadable(URL)
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let u):     return "无法读取文件：\(u.lastPathComponent)"
            case .undecodable(let u):    return "无法识别文本编码：\(u.lastPathComponent)（建议另存为 UTF-8）"
            case .pdfWithoutText(let u): return "这个 PDF 没有可选文字（可能是扫描件）：\(u.lastPathComponent)。漫画 PDF 请放进「漫画」分区，会按页显示。"
            case .epubUnreadable(let u): return "无法解析 epub：\(u.lastPathComponent)（文件可能损坏或加密）"
            case .unsupported(let s):    return "不支持的格式：\(s)"
            }
        }
    }

    /// 依次尝试常见编码
    private static let encodings: [String.Encoding] = [
        .utf8, .utf16, .utf16BigEndian
    ]

    /// 整本文本缓存：epub 解包 / pdf 抽文字都不便宜，切章与阅读共用一次结果。
    /// 只留最近 8 本，避免大书库把内存吃满。
    private static let documentCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 8
        return cache
    }()

    /// GB18030 / Big5 在 Swift 里用 CFString 编码常量桥接
    private static let cfEncodings: [CFStringEncodings] = [.GB_18030_2000, .big5]

    /// 纯文本读取（txt / md）
    static func load(_ url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url) else { throw TextError.unreadable(url) }
        if let text = decode(data) { return normalize(text) }
        throw TextError.undecodable(url)
    }

    /// 已下载到内存的正文（NAS 远端章节用）：编码检测与本地文件同一套规则
    static func text(from data: Data) -> String? {
        guard let decoded = decode(data) else { return nil }
        return normalize(decoded)
    }

    /// 按扩展名读取「一本书的全文」：txt / md / epub / pdf
    static func loadDocument(_ url: URL) throws -> String {
        let key = cacheKey(url)
        if let hit = documentCache.object(forKey: key) { return hit as String }
        let text = try loadDocumentUncached(url)
        documentCache.setObject(text as NSString, forKey: key)
        return text
    }

    private static func loadDocumentUncached(_ url: URL) throws -> String {
        let ext = MediaResolver.fileExtension(url.lastPathComponent)
        switch ext {
        case "epub":
            return try EpubParser.plainText(url: url)
        case "pdf":
            return try loadPDF(url)
        case "txt", "text", "md", "markdown", "":
            return try load(url)
        default:
            throw TextError.unsupported(ext)
        }
    }

    private static func cacheKey(_ url: URL) -> NSString {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let stamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        return "\(url.path)|\(stamp)|\(size)" as NSString
    }

    private static func loadPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw TextError.unreadable(url) }
        guard let text = document.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextError.pdfWithoutText(url)
        }
        return normalize(text)
    }

    /// 按区间取正文（章节切片）；区间越界时返回整段可用的部分
    static func substring(_ text: String, range: NSRange) -> String {
        let ns = text as NSString
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        guard safe.length > 0 else { return "" }
        return ns.substring(with: safe)
    }

    private static func decode(_ data: Data) -> String? {
        for enc in encodings {
            if let s = String(data: data, encoding: enc), !s.isEmpty { return s }
        }
        for cf in cfEncodings {
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue))
            let encoding = String.Encoding(rawValue: UInt(nsEnc))
            if let s = String(data: data, encoding: encoding), !s.isEmpty { return s }
        }
        return nil
    }

    /// 去 BOM、统一换行、去掉行尾空白
    static func normalize(_ s: String) -> String {
        var t = s
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        return t
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// 按空行/换行切分为段落，供 LazyVStack 逐段渲染（长文本不一次性塞进一个 Text）
    static func paragraphs(_ text: String) -> [String] {
        let raw = text.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [String] = []
        var buffer: [String] = []

        func flush() {
            let joined = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { result.append(joined) }
            buffer.removeAll(keepingCapacity: true)
        }

        for line in raw {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else {
                buffer.append(String(line))
            }
        }
        flush()
        return result
    }
}
