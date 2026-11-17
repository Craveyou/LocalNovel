import SwiftUI
import UIKit
import Foundation

// MARK: - 阅读排版与主题（只作用于「小说」分区）
//
// 这一层只放「数据与换算」，不含任何 UI 状态：
//   · ReaderTypography   一次排版所需的全部参数（字号 / 字体 / 字重 / 各种间距 / 对齐 / 缩进 / 繁简）
//   · ChapterTitleStyle   章节标题的独立样式（与正文分开，可细调）
//   · ReaderTheme         配色（内置 6 套 + 用户自定义，可带背景图）
//
// 分页引擎与滚动引擎都从这里取参数，保证两种阅读方式切换时视觉一致。

// MARK: 对齐

enum ReaderTextAlign: Int, CaseIterable, Identifiable {
    case justified = 0
    case leading = 1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .justified: return "两端对齐"
        case .leading:   return "左对齐"
        }
    }

    var nsAlignment: NSTextAlignment {
        self == .justified ? .justified : .left
    }
}

// MARK: 字重

enum ReaderFontWeight: Int, CaseIterable, Identifiable {
    case regular = 0
    case medium = 1
    case semibold = 2
    case bold = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .regular:  return "常规"
        case .medium:   return "中黑"
        case .semibold: return "次粗"
        case .bold:     return "加粗"
        }
    }

    var weight: UIFont.Weight {
        switch self {
        case .regular:  return .regular
        case .medium:   return .medium
        case .semibold: return .semibold
        case .bold:     return .bold
        }
    }

    /// 指定了自定义字体家族时，UIFont(name:) 只有一个字面，只能用符号特征加粗
    var needsBoldTrait: Bool { self == .bold || self == .semibold }
}

// MARK: 字体

struct ReaderFontOption: Identifiable, Hashable {
    /// 家族名；空串表示系统默认（iOS 中文即苹方）
    let id: String
    let label: String
}

enum ReaderFonts {
    /// 内置可选字体。都是 iOS 自带、无需下载的家族；装了自定义字体后由 Preferences 追加。
    static let builtIn: [ReaderFontOption] = [
        ReaderFontOption(id: "", label: "系统默认"),
        ReaderFontOption(id: "Songti SC", label: "宋体"),
        ReaderFontOption(id: "Kaiti SC", label: "楷体"),
        ReaderFontOption(id: "Yuanti SC", label: "圆体"),
        ReaderFontOption(id: "PingFang SC", label: "苹方"),
        ReaderFontOption(id: "Hiragino Sans GB", label: "冬青黑"),
        ReaderFontOption(id: "STFangsong", label: "仿宋")
    ]

    /// 正文 / 标题统一取字体的入口；家族不存在时静默退回系统字体，不让排版崩掉
    static func font(size: CGFloat, family: String, weight: ReaderFontWeight, italic: Bool = false) -> UIFont {
        var base: UIFont
        if !family.isEmpty, let custom = UIFont(name: family, size: size) {
            base = custom
            if weight.needsBoldTrait || italic {
                var traits: UIFontDescriptor.SymbolicTraits = []
                if weight.needsBoldTrait { traits.insert(.traitBold) }
                if italic { traits.insert(.traitItalic) }
                if let d = base.fontDescriptor.withSymbolicTraits(traits) {
                    base = UIFont(descriptor: d, size: size)
                }
            }
        } else {
            base = UIFont.systemFont(ofSize: size, weight: weight.weight)
            if italic, let d = base.fontDescriptor.withSymbolicTraits([.traitItalic]) {
                base = UIFont(descriptor: d, size: size)
            }
        }
        return base
    }
}

// MARK: 章节标题样式

struct ChapterTitleStyle: Equatable {
    /// 相对正文字号的比例（未开启固定字号时生效）
    var scale: Double
    /// 固定字号：与正文脱钩
    var isFixed: Bool
    var fixedSize: CGFloat
    var weight: ReaderFontWeight
    var isItalic: Bool
    /// 0 跟随主题，1 用自定义颜色
    var colorMode: Int
    var colorHex: String
    var topPadding: CGFloat
    var bottomPadding: CGFloat
    /// 标题下方细线
    var showBottomLine: Bool
    /// 分两行排版：「第10章」/「夜行」——按第一个空白切开
    var splitTwoLines: Bool

    func fontSize(bodySize: CGFloat) -> CGFloat {
        isFixed ? fixedSize : max(12, bodySize * CGFloat(scale))
    }

    /// 变化指纹：任一项改动都要重新分页
    var identity: String {
        "\(scale)|\(isFixed)|\(fixedSize)|\(weight.rawValue)|\(isItalic)|\(colorMode)|\(colorHex)"
            + "|\(topPadding)|\(bottomPadding)|\(showBottomLine)|\(splitTwoLines)"
    }
}

// MARK: 一次排版的全套参数

struct ReaderTypography: Equatable {
    var fontSize: CGFloat
    var fontFamily: String
    var weight: ReaderFontWeight
    var lineSpacing: CGFloat
    var paragraphSpacing: CGFloat
    var wordSpacing: CGFloat
    var horizontalPadding: CGFloat
    var alignment: ReaderTextAlign
    var firstLineIndent: Bool
    var isTraditional: Bool
    var title: ChapterTitleStyle

    /// 影响分页结果的全部参数（改任何一项都要重建排版）
    var identity: String {
        "\(fontSize)|\(fontFamily)|\(weight.rawValue)|\(lineSpacing)|\(paragraphSpacing)"
            + "|\(wordSpacing)|\(horizontalPadding)|\(alignment.rawValue)"
            + "|\(firstLineIndent)|\(isTraditional)|\(title.identity)"
    }

    /// 兜底参数（输入尚未就绪时用，正常不会走到）
    static let fallback = ReaderTypography(
        fontSize: 18,
        fontFamily: "",
        weight: .regular,
        lineSpacing: 10,
        paragraphSpacing: 6,
        wordSpacing: 0,
        horizontalPadding: 20,
        alignment: .justified,
        firstLineIndent: true,
        isTraditional: false,
        title: ChapterTitleStyle(scale: 1.3, isFixed: false, fixedSize: 20, weight: .bold,
                                 isItalic: false, colorMode: 0, colorHex: "#333333",
                                 topPadding: 16, bottomPadding: 16,
                                 showBottomLine: false, splitTwoLines: false)
    )
}

// MARK: 主题

struct ReaderTheme: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var isBuiltIn: Bool
    /// 夜晚主题：日/夜切换时用它
    var isNight: Bool

    /// 全部颜色都是十六进制串，Codable 直接存 JSON
    var textColor: String
    var backgroundColor: String
    var titleColor: String
    var pageIndexColor: String
    var headerFooterColor: String
    var separatorColor: String

    /// 背景图文件名（存在 Application Support/ReaderBG 下），nil = 纯色
    var backgroundImage: String?
    /// 0 填充裁切 / 1 适应留边 / 2 平铺
    var backgroundImageMode: Int

    // MARK: 取色

    var uiText: Color { Color(hex: textColor) }
    var uiBackground: Color { Color(hex: backgroundColor) }
    var uiTitle: Color { Color(hex: titleColor) }
    var uiPageIndex: Color { Color(hex: pageIndexColor) }
    var uiHeaderFooter: Color { Color(hex: headerFooterColor) }
    var uiSeparator: Color { Color(hex: separatorColor) }

    var uiTextColor: UIColor { UIColor(hex: textColor) }
    var uiBackgroundColor: UIColor { UIColor(hex: backgroundColor) }
    var uiTitleColor: UIColor { UIColor(hex: titleColor) }
    var uiPageIndexColor: UIColor { UIColor(hex: pageIndexColor) }
    var uiHeaderFooterColor: UIColor { UIColor(hex: headerFooterColor) }
    var uiSeparatorColor: UIColor { UIColor(hex: separatorColor) }

    /// 当前主题对应的状态栏风格：浅色底用深色字
    var statusBarIsDarkText: Bool {
        Self.luminance(of: backgroundColor) > 0.55
    }

    static func luminance(of hex: String) -> Double {
        let (r, g, b) = rgbComponents(hex)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    static func rgbComponents(_ hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count >= 6, let v = UInt32(s.prefix(6), radix: 16) else { return (0.5, 0.5, 0.5) }
        return (Double((v >> 16) & 0xFF) / 255.0,
                Double((v >> 8) & 0xFF) / 255.0,
                Double(v & 0xFF) / 255.0)
    }

    // MARK: 内置主题

    static let builtIns: [ReaderTheme] = [
        ReaderTheme(id: "paper", name: "纸白", isBuiltIn: true, isNight: false,
                    textColor: "#2B2B2B", backgroundColor: "#F7F3EA", titleColor: "#1F1F1F",
                    pageIndexColor: "#9A9388", headerFooterColor: "#9A9388", separatorColor: "#DED7C8",
                    backgroundImage: nil, backgroundImageMode: 0),
        ReaderTheme(id: "white", name: "纯白", isBuiltIn: true, isNight: false,
                    textColor: "#1A1A1A", backgroundColor: "#FFFFFF", titleColor: "#000000",
                    pageIndexColor: "#AAAAAA", headerFooterColor: "#AAAAAA", separatorColor: "#E5E5E5",
                    backgroundImage: nil, backgroundImageMode: 0),
        ReaderTheme(id: "sepia", name: "米黄", isBuiltIn: true, isNight: false,
                    textColor: "#4A3B2A", backgroundColor: "#F2E4C9", titleColor: "#3A2E20",
                    pageIndexColor: "#A79477", headerFooterColor: "#A79477", separatorColor: "#DCC9A6",
                    backgroundImage: nil, backgroundImageMode: 0),
        ReaderTheme(id: "green", name: "护眼", isBuiltIn: true, isNight: false,
                    textColor: "#2B3A2B", backgroundColor: "#CCE8CF", titleColor: "#1F2B1F",
                    pageIndexColor: "#7F9A82", headerFooterColor: "#7F9A82", separatorColor: "#AED2B2",
                    backgroundImage: nil, backgroundImageMode: 0),
        ReaderTheme(id: "night", name: "夜间", isBuiltIn: true, isNight: true,
                    textColor: "#A8A8A8", backgroundColor: "#1C1C1E", titleColor: "#C8C8C8",
                    pageIndexColor: "#6A6A6A", headerFooterColor: "#6A6A6A", separatorColor: "#333333",
                    backgroundImage: nil, backgroundImageMode: 0),
        ReaderTheme(id: "black", name: "纯黑", isBuiltIn: true, isNight: true,
                    textColor: "#8C8C8C", backgroundColor: "#000000", titleColor: "#B0B0B0",
                    pageIndexColor: "#5A5A5A", headerFooterColor: "#5A5A5A", separatorColor: "#262626",
                    backgroundImage: nil, backgroundImageMode: 0)
    ]

    static let fallback = builtIns[0]

    static func theme(id: String, custom: [ReaderTheme]) -> ReaderTheme {
        if let hit = builtIns.first(where: { $0.id == id }) { return hit }
        if let hit = custom.first(where: { $0.id == id }) { return hit }
        return fallback
    }

    /// 某一天的日/夜主题（跟随系统或手动切换时用）
    static func night(_ isNight: Bool, custom: [ReaderTheme]) -> ReaderTheme? {
        (builtIns + custom).first { $0.isNight == isNight }
    }
}

// MARK: 颜色换算

extension Color {
    init(hex: String) {
        let (r, g, b) = ReaderTheme.rgbComponents(hex)
        self.init(red: r, green: g, blue: b)
    }
}

extension UIColor {
    convenience init(hex: String) {
        let (r, g, b) = ReaderTheme.rgbComponents(hex)
        self.init(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }
}

// MARK: 主题背景图

enum ReaderBackgroundImage {
    /// 自定义背景图存放目录：Application Support/ReaderBG
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("ReaderBG", isDirectory: true)
    }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func load(_ name: String) -> UIImage? {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// 把用户选的图片存进沙盒，返回文件名。名字带时间戳，避免覆盖别的主题的图。
    static func save(imageData: Data, ext: String) -> String? {
        ensureDirectory()
        let name = "bg-\(Int(Date().timeIntervalSince1970)).\(ext.isEmpty ? "jpg" : ext)"
        do {
            try imageData.write(to: directory.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }
}

// MARK: 繁简

enum ChineseScript {
    /// 简体 → 繁体。
    ///
    /// Foundation 没有把「简繁转换」暴露成 StringTransform 的静态成员，
    /// 但 StringTransform 是 RawRepresentable，可以直接用 ICU 的转换器名：
    ///   · "Simplified-Traditional"（ICU 标准名）
    ///   · "Hans-Hant"（语言标签写法，部分系统只认这个）
    /// 两个都不认时原样返回，绝不能因为转换失败把正文吞掉。
    private static let traditionalTransformIDs = ["Simplified-Traditional", "Hans-Hant"]

    static func toTraditional(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        for id in traditionalTransformIDs {
            if let converted = text.applyingTransform(StringTransform(rawValue: id), reverse: false) {
                return converted
            }
        }
        return text
    }

    /// 小容量缓存：同一章反复重绘时不必重复转换
    private static var cache: [String: [String]] = [:]
    private static var order: [String] = []

    static func paragraphs(_ key: String, _ raw: [String]) -> [String] {
        if let hit = cache[key] { return hit }
        let converted = raw.map(toTraditional)
        cache[key] = converted
        order.append(key)
        if order.count > 3 {
            cache[order.removeFirst()] = nil
        }
        return converted
    }

    static func reset() {
        cache.removeAll()
        order.removeAll()
    }
}
