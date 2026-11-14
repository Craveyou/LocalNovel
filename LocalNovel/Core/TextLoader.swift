import Foundation
import CoreFoundation

// MARK: - 正文读取：编码自动检测 + 段落切分
// TXT 常见编码为 UTF-8 / GB18030 / Big5；检测失败时给出明确错误，不静默返回乱码。

enum TextLoader {
    enum TextError: LocalizedError {
        case unreadable(URL)
        case undecodable(URL)

        var errorDescription: String? {
            switch self {
            case .unreadable(let u):  return "无法读取文件：\(u.lastPathComponent)"
            case .undecodable(let u): return "无法识别文本编码：\(u.lastPathComponent)（建议另存为 UTF-8）"
            }
        }
    }

    /// 依次尝试常见编码
    private static let encodings: [String.Encoding] = [
        .utf8, .utf16, .utf16BigEndian
    ]

    /// GB18030 / Big5 在 Swift 里用 CFString 编码常量桥接
    private static let cfEncodings: [CFStringEncodings] = [.GB_18030_2000, .big5]

    static func load(_ url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url) else { throw TextError.unreadable(url) }
        if let text = decode(data) { return normalize(text) }
        throw TextError.undecodable(url)
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
    private static func normalize(_ s: String) -> String {
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
