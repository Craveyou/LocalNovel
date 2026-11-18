import Foundation
import SwiftUI
import UIKit

// MARK: - 主题

/// 四套阅读主题：白 / 羊皮纸 / 夜间 / 纯黑。
public enum TextTheme: String, CaseIterable, Identifiable, Codable {
    case white, sepia, dark, black

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .white: return "白"
        case .sepia: return "羊皮纸"
        case .dark: return "夜间"
        case .black: return "纯黑"
        }
    }

    public var isDark: Bool { self == .dark || self == .black }

    public var background: Color {
        switch self {
        case .white: return Color(red: 0.97, green: 0.97, blue: 0.96)
        case .sepia: return Color(red: 0.94, green: 0.89, blue: 0.78)
        case .dark: return Color(red: 0.10, green: 0.10, blue: 0.11)
        case .black: return .black
        }
    }

    public var text: Color {
        isDark ? Color(red: 0.78, green: 0.79, blue: 0.80) : Color(red: 0.17, green: 0.16, blue: 0.15)
    }

    public var secondary: Color {
        isDark ? Color(white: 0.55) : Color(white: 0.45)
    }

    /// 菜单浮层底色：半透明，正文隐约可见（对齐截图 5216）。
    public var menuBackground: Color {
        isDark ? Color.black.opacity(0.88) : Color.white.opacity(0.97)
    }

    /// 面板 / 抽屉实底色。
    public var chrome: Color {
        isDark ? Color(red: 0.13, green: 0.13, blue: 0.14) : Color(red: 0.96, green: 0.96, blue: 0.95)
    }

    public var accent: Color { .green }
}

// MARK: - 翻页模式

/// 仿真 = pageCurl；平移 = scroll；覆盖 = 系统不提供覆盖过渡，用 scroll 近似；
/// 上下 = 竖向 scroll；无 = 只保留点击翻页，不做动画。
public enum TextPageTransition: String, CaseIterable, Identifiable, Codable {
    case curl, scroll, cover, vertical, none

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .curl: return "仿真"
        case .scroll: return "平移"
        case .cover: return "覆盖"
        case .vertical: return "上下"
        case .none: return "无"
        }
    }
}

// MARK: - 字体风格

public enum TextFontDesign: String, CaseIterable, Identifiable, Codable {
    case system, rounded, serif

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .system: return "系统-常规"
        case .rounded: return "系统-圆体"
        case .serif: return "宋体"
        }
    }

    public func uiFont(size: CGFloat) -> UIFont {
        switch self {
        case .system: return UIFont.systemFont(ofSize: size)
        case .rounded:
            let descriptor = UIFontDescriptor.default.withDesign(.rounded)
            return UIFont(descriptor: descriptor ?? .default, size: size)
        case .serif:
            let descriptor = UIFontDescriptor.default.withDesign(.serif)
            return UIFont(descriptor: descriptor ?? .default, size: size)
        }
    }

    public func swiftFont(size: CGFloat) -> Font {
        switch self {
        case .system: return .system(size: size)
        case .rounded: return .system(size: size, design: .rounded)
        case .serif: return .system(size: size, design: .serif)
        }
    }
}

// MARK: - 点击区域动作

public enum TextTapAction: String, CaseIterable, Identifiable, Codable {
    case prev, next, menu

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .prev: return "上一页"
        case .next: return "下一页"
        case .menu: return "菜单"
        }
    }
}

// MARK: - 阅读设置

/// 全部可持久化的阅读偏好。分页相关字段变化时才触发重新分页。
public struct TextReaderSettings: Codable, Equatable {
    public var theme: TextTheme = .dark
    public var fontSize: CGFloat = 20
    public var fontDesign: TextFontDesign = .system
    public var transition: TextPageTransition = .cover
    public var indentParagraphs: Bool = true
    public var purified: Bool = false
    public var showChapterTitle: Bool = true
    public var showChapterIndex: Bool = true
    public var showBatteryTime: Bool = true
    public var showPageNumber: Bool = true
    /// 3 列 × 3 行九宫格点击区域，cell = row * 3 + col。
    public var tapZones: [Int: TextTapAction] = TextReaderSettings.standardTapZones()
    /// 亮度常亮（屏幕不息屏）。
    public var keepAwake: Bool = false

    public init() {}

    public static func standardTapZones() -> [Int: TextTapAction] {        var zones: [Int: TextTapAction] = [:]
        for row in 0..<3 {
            for col in 0..<3 {
                zones[row * 3 + col] = col == 0 ? .prev : (col == 1 ? .menu : .next)
            }
        }
        return zones
    }

    /// 默认动作兜底（用户清空字典时也不会失控）。
    public func action(forCell cell: Int) -> TextTapAction {
        let col = cell % 3
        if let action = tapZones[cell] { return action }
        return col == 0 ? .prev : (col == 1 ? .menu : .next)
    }

    public func tapAction(at point: CGPoint, in size: CGSize) -> TextTapAction {
        guard size.width > 10, size.height > 10 else { return .menu }
        let col = min(Int(point.x / size.width * 3), 2)
        let row = min(Int(point.y / size.height * 3), 2)
        return action(forCell: row * 3 + col)
    }

    /// 只有影响排版的字段变化才需要重新分页。
    public func needsRepagination(from old: TextReaderSettings) -> Bool {
        fontSize != old.fontSize || fontDesign != old.fontDesign || indentParagraphs != old.indentParagraphs
    }

    // MARK: 持久化

    private static let defaultsKey = "TextReaderKit.settings.v1"

    public static func load() -> TextReaderSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(TextReaderSettings.self, from: data) else {
            return TextReaderSettings()
        }
        return settings
    }

    public static func persist(_ settings: TextReaderSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

// MARK: - 净化

/// 纯文本小说的广告行清理：命中特征词 / URL 的整行剔除，
/// 连续空行压缩为一行。只在用户打开「净化」开关时生效。
public enum TextPurifier {
    private static let patterns: [NSRegularExpression] = {
        let raw = [
            #"[hH][tT][tT][pP][sS]?://"#,
            #"www\."#,
            #"\.(com|net|cc|org|info|la|me|top|vip|xyz)\b"#,
            #"笔趣阁|笔趣库|顶点小说|乐文|听风|书楼|言情|武侠楼|海棠|po18|PO18"#,
            #"最新章节|章节目录|无错|手打|首发|更新最快|完本|TXT下载|txt下载|下载本书|本书来自|本章未完|点击下一页|求收藏|求推荐|求月票|书友群#",
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    public static func clean(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let lines = text.components(separatedBy: "\n")
        var kept: [String] = []
        kept.reserveCapacity(lines.count)
        var blankRun = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blankRun += 1
                if blankRun <= 1 { kept.append("") }
                continue
            }
            blankRun = 0
            if isAdLine(trimmed) { continue }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    private static func isAdLine(_ line: String) -> Bool {
        // 特征行通常很短；长正文即使含「最新章节」也按句清洗，避免误杀。
        guard line.count < 80 else { return false }
        let range = NSRange(location: 0, length: (line as NSString).length)
        return patterns.contains { $0.firstMatch(in: line, options: [], range: range) != nil }
    }
}
