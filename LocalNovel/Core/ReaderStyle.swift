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

/// 正文 / 标题统一用系统默认字体（iOS 中文即苹方）。
/// 这一版去掉了字体家族切换与字体导入：只保留字重、斜体这类系统原生变体，
/// 避免「用户导入的字体在某些字号下缺字 / 行高诡异」这类问题。
enum ReaderFonts {
    static func font(size: CGFloat, weight: ReaderFontWeight, italic: Bool = false) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight.weight)
        guard italic, let d = base.fontDescriptor.withSymbolicTraits([.traitItalic]) else {
            return base
        }
        return UIFont(descriptor: d, size: size)
    }
}

// MARK: 点击区域

/// 屏幕左 / 中 / 右三块区域各自做什么（对齐千阅的可配置点击区）
enum TapZoneAction: Int, CaseIterable, Identifiable {
    case prevPage = 0
    case nextPage = 1
    case menu = 2
    case none = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .prevPage: return "上一页"
        case .nextPage: return "下一页"
        case .menu:     return "菜单"
        case .none:     return "无"
        }
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
    var weight: ReaderFontWeight
    var lineSpacing: CGFloat
    var paragraphSpacing: CGFloat
    var wordSpacing: CGFloat
    var horizontalPadding: CGFloat
    var alignment: ReaderTextAlign
    var firstLineIndent: Bool
    var title: ChapterTitleStyle

    /// 影响分页结果的全部参数（改任何一项都要重建排版）
    var identity: String {
        "\(fontSize)|\(weight.rawValue)|\(lineSpacing)|\(paragraphSpacing)"
            + "|\(wordSpacing)|\(horizontalPadding)|\(alignment.rawValue)"
            + "|\(firstLineIndent)|\(title.identity)"
    }

    /// 兜底参数（输入尚未就绪时用，正常不会走到）
    static let fallback = ReaderTypography(
        fontSize: 18,
        weight: .regular,
        lineSpacing: 10,
        paragraphSpacing: 6,
        wordSpacing: 0,
        horizontalPadding: 20,
        alignment: .justified,
        firstLineIndent: true,
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

    /// 主题固定六套内置；未知 id（老数据里的自定义主题）退回纸白
    static func theme(id: String) -> ReaderTheme {
        builtIns.first(where: { $0.id == id }) ?? fallback
    }

    /// 某一天的日/夜主题（跟随系统或手动切换时用）
    static func night(_ isNight: Bool) -> ReaderTheme? {
        builtIns.first { $0.isNight == isNight }
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

    /// 取回 #RRGGBB，供 ColorPicker 回写
    var hexRGB: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((min(max(r, 0), 1)) * 255),
                      Int((min(max(g, 0), 1)) * 255),
                      Int((min(max(b, 0), 1)) * 255))
    }
}

extension Color {
    var hexRGB: String { UIColor(self).hexRGB }
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

