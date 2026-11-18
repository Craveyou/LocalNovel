import Foundation
import CoreFoundation

public enum TextFileLoader {
    public static let supportedExtensions: Set<String> = ["txt", "md", "text"]

    public static func load(url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return "" }
        let candidates: [String.Encoding] = [
            .utf8,
            String.Encoding(rawValue: cfEncoding(.GB_18030_2000)),
            String.Encoding(rawValue: cfEncoding(.big5)),
            .utf16
        ]
        for encoding in candidates {
            if let text = String(data: data, encoding: encoding), looksReadable(text) {
                return text
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// 扫描一个目录里的纯文本文件；子目录名作为系列前缀写进标题。
    public static func books(in folder: URL) -> [TextBook] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder,
                                             includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return [] }
        var result: [TextBook] = []
        for case let url as URL in enumerator {
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let relative = url.deletingLastPathComponent().path
                .replacingOccurrences(of: folder.standardizedFileURL.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let base = url.deletingPathExtension().lastPathComponent
            let title = relative.isEmpty ? base : "\(relative.replacingOccurrences(of: "/", with: " · ")) · \(base)"
            result.append(TextBook(title: title, url: url))
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func cfEncoding(_ encoding: CFStringEncodings) -> UInt {
        UInt(CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
    }

    private static func looksReadable(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let sample = text.prefix(400)
        let replacement = sample.filter { $0 == "\u{FFFD}" }.count
        return replacement * 20 < sample.count
    }
}
