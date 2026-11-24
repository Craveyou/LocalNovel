import Foundation
import CoreFoundation

// MARK: - 文本编码：自动识别 + 手动指定 + 按书记忆
//
// 为什么需要这份东西：
//   txt 不是「一种格式」，只是一串字节，编码写在文件外面（没有 BOM 时全靠猜）。
//   中文 txt 现实里至少四种：UTF-8、GBK/GB18030、Big5、UTF-16（记事本另存）。
//   同一个字节序列用错编码解，不会报错，只会变成一屏看不懂的字——这就是「乱码」。
//
// 自动识别的三条硬规则（按顺序）：
//   1. 有 BOM 就照 BOM 来，这是文件自己声明的，最可信。
//   2. UTF-8 严格解码：Foundation 遇到非法字节会返回 nil，不会悄悄替换，所以能过就是对的。
//   3. **UTF-16 只在有 BOM 或明显 NUL 特征时才试**。
//      这是之前「有的 txt 乱码」的根因：UTF-16 几乎能「成功」解码任意偶数长度的字节，
//      GBK 文件被它抢先解掉，就成了一屏乱码汉字。
//   4. GB18030 / Big5 各解一次，按「常用字 + 中文标点 + 扩展区惩罚」打分取高分者。
//      解错时全角标点会消失、常用字比例骤降，这个特征比任何猜测都稳。
//
// 自动识别仍可能判错（比如极短的片段、GBK 与 Big5 都合法的字节），
// 所以阅读器菜单里给了「文本编码」开关，按书记忆，用户改一次以后都按这个来。

/// 用户在阅读器里可选的编码；`auto` 表示交给检测器
enum TextEncodingOption: String, CaseIterable, Identifiable {
    case auto
    case utf8
    case gb18030
    case big5
    case utf16

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:    return "自动识别"
        case .utf8:    return "UTF-8"
        case .gb18030: return "简体（GBK / GB18030）"
        case .big5:    return "繁体（Big5）"
        case .utf16:   return "UTF-16"
        }
    }

    /// nil 表示不指定，走自动检测
    var stringEncoding: String.Encoding? {
        switch self {
        case .auto:    return nil
        case .utf8:    return .utf8
        case .utf16:   return .utf16
        case .gb18030: return TextEncodingOption.cfEncoding(.GB_18030_2000)
        case .big5:    return TextEncodingOption.cfEncoding(.big5)
        }
    }

    static func cfEncoding(_ cf: CFStringEncodings) -> String.Encoding {
        let ns = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue))
        return String.Encoding(rawValue: UInt(ns))
    }
}

// MARK: - 按书记忆

/// 一本书一次选择，全书生效。
/// key 取「书」这一层：目录章节取父目录，单文件 / 整本切片取文件本身。
enum TextEncodingStore {
    private static let defaultsKey = "text.encoding.byBook"

    /// 章节 → 书级 key
    static func bookKey(for chapter: Chapter) -> String {
        switch chapter.kind {
        case .folder:
            // 整理：书名/章节 —— 父目录就是书；小说：系列/书名/章节 —— 父目录还是书
            return chapter.folderURL.deletingLastPathComponent().standardizedFileURL.path
        case .file, .slice:
            // 单文件小说、整本切片：文件本身就是这本书
            return chapter.folderURL.standardizedFileURL.path
        }
    }

    /// NAS 上的文件没有 Chapter 模型，按完整地址记（同名的两个目录不会串）
    static func bookKey(forURL url: URL) -> String {
        "url:" + url.absoluteString
    }

    static func option(for key: String) -> TextEncodingOption {
        guard let map = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String],
              let raw = map[key],
              let value = TextEncodingOption(rawValue: raw) else { return .auto }
        return value
    }

    static func set(_ option: TextEncodingOption, for key: String) {
        var map = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
        if option == .auto {
            map.removeValue(forKey: key)
        } else {
            map[key] = option.rawValue
        }
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }
}
