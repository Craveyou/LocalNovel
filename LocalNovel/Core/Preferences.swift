import Foundation
import SwiftUI

// MARK: - 阅读偏好（全本地，UserDefaults）

/// 外观模式：跟随系统 / 浅色 / 深色。rawValue 直接存盘，Int 比字符串稳定。
enum AppearanceMode: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }
}

/// 阅读方式：上下滚动 / 仿真翻页 / 滑动翻页
///
/// 三种手感对应主流阅读器的三类交互：
///   · scroll — 连续滚动，段落无分页，适合长文与图文混排
///   · page   — 仿真卷曲（UIPageViewController.pageCurl），翻页时有纸张卷起
///   · slide  — 滑动翻页（跟手横移 + 页边阴影 + 松手吸附），与系统「图书」一致
enum PageTurnMode: Int, CaseIterable, Identifiable {
    case scroll = 0
    case page = 1
    case slide = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .scroll: return "上下滚动"
        case .page:   return "仿真翻页"
        case .slide:  return "滑动翻页"
        }
    }

    /// 是否走「分页阅读」引擎（卷曲与滑动都是分页，只是呈现方式不同）
    var isPaged: Bool { self != .scroll }

    /// 分页引擎的呈现样式
    var flipStyle: PageFlipStyle {
        self == .page ? .curl : .slide
    }

    var detail: String {
        switch self {
        case .scroll:
            return "上下滚动：连续长页，段落流畅衔接，适合长篇与图文混排。"
        case .page:
            return "仿真翻页：纸张卷起的立体动画，点屏幕左 / 右侧翻页，底部显示页码。"
        case .slide:
            return "滑动翻页：整页跟手横移，翻动时带页边阴影，松手自动吸附到下一页；也可点左右边缘翻页。"
        }
    }
}

/// 页眉内容
enum ReaderHeaderMode: Int, CaseIterable, Identifiable {
    case none = 0
    case chapter = 1
    case book = 2

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .none:    return "不显示"
        case .chapter: return "章节名"
        case .book:    return "书名"
        }
    }
}

/// 页脚内容
enum ReaderFooterMode: Int, CaseIterable, Identifiable {
    case none = 0
    case page = 1
    case percent = 2

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .none:    return "不显示"
        case .page:    return "页码"
        case .percent: return "百分比"
        }
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private var loaded = false

    // MARK: 排版（C 组）

    @Published var fontSize: CGFloat = 18 {
        didSet { if loaded { save() } }
    }
    @Published var lineSpacing: CGFloat = 10 {
        didSet { if loaded { save() } }
    }
    /// 段间距：与行距分开，段落之间更透气
    @Published var paragraphSpacing: CGFloat = 6 {
        didSet { if loaded { save() } }
    }
    /// 字距
    @Published var wordSpacing: CGFloat = 0 {
        didSet { if loaded { save() } }
    }
    /// 正文左右留白
    @Published var horizontalPadding: CGFloat = 20 {
        didSet { if loaded { save() } }
    }
    @Published var textAlign: ReaderTextAlign = .justified {
        didSet { if loaded { save() } }
    }
    /// 首行缩进两字
    @Published var firstLineIndent: Bool = true {
        didSet { if loaded { save() } }
    }
    /// 简体 → 繁体
    @Published var isTraditional: Bool = false {
        didSet { if loaded { save() } }
    }
    /// 字体家族；空串 = 系统默认
    @Published var fontFamily: String = "" {
        didSet { if loaded { save() } }
    }
    @Published var fontWeight: ReaderFontWeight = .regular {
        didSet { if loaded { save() } }
    }

    // MARK: 章节标题样式（D 组）

    @Published var titleScale: Double = 1.3 {
        didSet { if loaded { save() } }
    }
    @Published var titleFixedSize: Bool = false {
        didSet { if loaded { save() } }
    }
    @Published var titleFixedValue: CGFloat = 20 {
        didSet { if loaded { save() } }
    }
    @Published var titleWeight: ReaderFontWeight = .bold {
        didSet { if loaded { save() } }
    }
    @Published var titleItalic: Bool = false {
        didSet { if loaded { save() } }
    }
    /// 0 跟随主题，1 自定义
    @Published var titleColorMode: Int = 0 {
        didSet { if loaded { save() } }
    }
    @Published var titleColorHex: String = "#333333" {
        didSet { if loaded { save() } }
    }
    @Published var titleTopPadding: CGFloat = 16 {
        didSet { if loaded { save() } }
    }
    @Published var titleBottomPadding: CGFloat = 16 {
        didSet { if loaded { save() } }
    }
    @Published var titleShowBottomLine: Bool = false {
        didSet { if loaded { save() } }
    }
    @Published var titleSplitTwoLines: Bool = false {
        didSet { if loaded { save() } }
    }

    // MARK: 页眉页脚（E 组）

    @Published var headerMode: ReaderHeaderMode = .none {
        didSet { if loaded { save() } }
    }
    @Published var footerMode: ReaderFooterMode = .page {
        didSet { if loaded { save() } }
    }
    @Published var headerTopPadding: CGFloat = 8 {
        didSet { if loaded { save() } }
    }
    @Published var footerBottomPadding: CGFloat = 6 {
        didSet { if loaded { save() } }
    }

    // MARK: 主题与亮度（F 组）

    @Published var themeId: String = "paper" {
        didSet { if loaded { save() } }
    }
    @Published var customThemes: [ReaderTheme] = [] {
        didSet { if loaded { save() } }
    }
    /// 阅读页内亮度：1 = 原样，越小越暗（只压阅读层，不改系统亮度）
    @Published var readerBrightness: Double = 1.0 {
        didSet { if loaded { save() } }
    }
    /// 阅读时不息屏
    @Published var keepScreenOn: Bool = false {
        didSet { if loaded { save() } }
    }

    // MARK: 全局外观

    @Published var appearance: AppearanceMode = .system {
        didSet { if loaded { save() } }
    }

    /// 小说分区的阅读方式，默认滑动翻页；漫画与整理固定滚动，读这个值但不受它影响
    @Published var pageTurn: PageTurnMode = .slide {
        didSet { if loaded { save() } }
    }
    /// 交给 .preferredColorScheme：nil 表示不覆盖，即跟随系统外观。
    var preferredScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// 可选：去掉章节文件夹名的「01_」类前缀（默认关闭，原样展示）
    @Published var cleanTitles: Bool = false {
        didSet { if loaded { save() } }
    }
    /// 长按视频/音频时的临时倍速（默认 2 倍）
    @Published var longPressRate: Double = 2.0 {
        didSet { if loaded { save() } }
    }
    /// NAS 图片缓存上限（MB）；0 = 不限制。改小后立即按新上限裁一次。
    @Published var networkImageCacheMB: Int = 512 {
        didSet { if loaded { save() } }
    }

    /// 设置页可选的缓存上限（MB）
    static let imageCacheOptions = [128, 256, 512, 1024, 2048, 0]

    // MARK: 派生值

    /// 当前主题（内置或自定义）
    var theme: ReaderTheme {
        ReaderTheme.theme(id: themeId, custom: customThemes)
    }

    var titleStyle: ChapterTitleStyle {
        ChapterTitleStyle(scale: titleScale,
                          isFixed: titleFixedSize,
                          fixedSize: titleFixedValue,
                          weight: titleWeight,
                          isItalic: titleItalic,
                          colorMode: titleColorMode,
                          colorHex: titleColorHex,
                          topPadding: titleTopPadding,
                          bottomPadding: titleBottomPadding,
                          showBottomLine: titleShowBottomLine,
                          splitTwoLines: titleSplitTwoLines)
    }

    /// 一次排版所需的全部参数
    var typography: ReaderTypography {
        ReaderTypography(fontSize: fontSize,
                         fontFamily: fontFamily,
                         weight: fontWeight,
                         lineSpacing: lineSpacing,
                         paragraphSpacing: paragraphSpacing,
                         wordSpacing: wordSpacing,
                         horizontalPadding: horizontalPadding,
                         alignment: textAlign,
                         firstLineIndent: firstLineIndent,
                         isTraditional: isTraditional,
                         title: titleStyle)
    }

    /// 全部可选字体（内置 + 已导入）
    var fontOptions: [ReaderFontOption] {
        ReaderFonts.builtIn + customFontFamilies.map { ReaderFontOption(id: $0, label: $0) }
    }

    /// 已导入的自定义字体家族名（由 ReaderFontLibrary 维护）
    @Published var customFontFamilies: [String] = [] {
        didSet { if loaded { save() } }
    }

    // MARK: 读写

    private init() {
        let r = defaults.double(forKey: Keys.longPressRate)
        lineSpacing = number(Keys.lineSpacing, 10, 4, 24)
        // 新版三档；旧版只有「夜间模式」开关，做一次平滑迁移。
        if defaults.object(forKey: Keys.appearance) != nil {
            appearance = AppearanceMode(rawValue: defaults.integer(forKey: Keys.appearance)) ?? .system
        } else if defaults.bool(forKey: Keys.dark) {
            appearance = .dark
        } else {
            appearance = .system
        }
        // 未设置过时默认「滑动翻页」（与系统图书一致的手感）。
        // 注意不能用 defaults.integer(...)：未设置时它返回 0，会被当成 .scroll。
        if let raw = defaults.object(forKey: Keys.pageTurn) as? Int,
           let mode = PageTurnMode(rawValue: raw) {
            pageTurn = mode
        } else {
            pageTurn = .slide
        }
        // 2.10 之前「左右翻页」只有仿真卷曲一种，初始值就是 .page。
        // 升级到带滑动翻页的版本时迁移一次：老用户开机就能直接看到新手感，
        // 想回去可在设置里重选「仿真翻页」（迁移只做一次，之后尊重用户选择）。
        if !defaults.bool(forKey: Keys.slideMigrated) {
            defaults.set(true, forKey: Keys.slideMigrated)
            if pageTurn == .page {
                pageTurn = .slide
                defaults.set(PageTurnMode.slide.rawValue, forKey: Keys.pageTurn)
            }
        }
        cleanTitles = defaults.bool(forKey: Keys.cleanTitles)
        longPressRate = r > 0 ? r : 2.0
        // 默认 512 MB；用户显式选「不限制」时存的就是 0，要能区分「没设置过」
        networkImageCacheMB = defaults.object(forKey: Keys.imageCacheMB) == nil
            ? 512
            : max(0, defaults.integer(forKey: Keys.imageCacheMB))

        // 主题：老用户如果之前选了「深色」外观，第一次升级直接给夜间主题，避免白底黑字闪一下
        if let id = defaults.string(forKey: Keys.themeId), !id.isEmpty {
            themeId = id
        } else if appearance == .dark {
            themeId = "night"
        }
        if let data = defaults.data(forKey: Keys.customThemes),
           let list = try? JSONDecoder().decode([ReaderTheme].self, from: data) {
            customThemes = list
        }
        if let list = defaults.array(forKey: Keys.customFonts) as? [String] {
            customFontFamilies = list
        }

        fontSize = number(Keys.fontSize, 18, 14, 34)
        paragraphSpacing = number(Keys.paragraphSpacing, 6, 0, 24)
        wordSpacing = number(Keys.wordSpacing, 0, 0, 6)
        horizontalPadding = number(Keys.hPadding, 20, 12, 40)
        titleScale = Double(number(Keys.titleScale, 1.3, 0.8, 2.4))
        titleFixedValue = number(Keys.titleFixedSize, 20, 12, 40)
        titleTopPadding = number(Keys.titleTop, 16, 0, 60)
        titleBottomPadding = number(Keys.titleBottom, 16, 0, 60)
        headerTopPadding = number(Keys.headerTop, 8, 0, 40)
        footerBottomPadding = number(Keys.footerBottom, 6, 0, 40)
        readerBrightness = Double(number(Keys.brightness, 1.0, 0.25, 1.0))
        firstLineIndent = defaults.object(forKey: Keys.indent) == nil
            ? true : defaults.bool(forKey: Keys.indent)
        keepScreenOn = defaults.bool(forKey: Keys.keepScreenOn)
        isTraditional = defaults.bool(forKey: Keys.traditional)
        fontFamily = defaults.string(forKey: Keys.fontFamily) ?? ""
        textAlign = ReaderTextAlign(rawValue: defaults.object(forKey: Keys.align) == nil
                                    ? 0 : defaults.integer(forKey: Keys.align)) ?? .justified
        fontWeight = ReaderFontWeight(rawValue: defaults.integer(forKey: Keys.fontWeight)) ?? .regular
        titleWeight = ReaderFontWeight(rawValue: defaults.object(forKey: Keys.titleWeight) == nil
                                       ? 3 : defaults.integer(forKey: Keys.titleWeight)) ?? .bold
        titleColorMode = defaults.integer(forKey: Keys.titleColorMode)
        titleColorHex = defaults.string(forKey: Keys.titleColorHex) ?? "#333333"
        titleItalic = defaults.bool(forKey: Keys.titleItalic)
        titleShowBottomLine = defaults.bool(forKey: Keys.titleLine)
        titleSplitTwoLines = defaults.bool(forKey: Keys.titleSplit)
        titleFixedSize = defaults.bool(forKey: Keys.titleFixed)
        headerMode = ReaderHeaderMode(rawValue: defaults.integer(forKey: Keys.headerMode)) ?? .none
        footerMode = ReaderFooterMode(rawValue: defaults.object(forKey: Keys.footerMode) == nil
                                      ? 1 : defaults.integer(forKey: Keys.footerMode)) ?? .page
        loaded = true
    }

    /// 读一个带范围的数值项：没写过就用默认值，写过就收敛到区间内
    private func number(_ key: String, _ fallback: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return min(max(CGFloat(defaults.double(forKey: key)), lower), upper)
    }

    private enum Keys {
        static let fontSize = "LocalNovel.fontSize"
        static let lineSpacing = "LocalNovel.lineSpacing"
        static let appearance = "LocalNovel.appearance"
        static let dark = "LocalNovel.darkMode" // 旧键，仅用于迁移读取
        static let cleanTitles = "LocalNovel.cleanTitles"
        static let longPressRate = "LocalNovel.longPressRate"
        static let pageTurn = "LocalNovel.pageTurn"
        static let slideMigrated = "LocalNovel.slideMigrated"
        static let imageCacheMB = "LocalNovel.imageCacheMB"

        static let paragraphSpacing = "LocalNovel.paragraphSpacing"
        static let wordSpacing = "LocalNovel.wordSpacing"
        static let hPadding = "LocalNovel.hPadding"
        static let align = "LocalNovel.textAlign"
        static let indent = "LocalNovel.firstLineIndent"
        static let traditional = "LocalNovel.traditional"
        static let fontFamily = "LocalNovel.fontFamily"
        static let fontWeight = "LocalNovel.fontWeight"
        static let customFonts = "LocalNovel.customFonts"

        static let titleScale = "LocalNovel.titleScale"
        static let titleFixed = "LocalNovel.titleFixed"
        static let titleFixedSize = "LocalNovel.titleFixedSize"
        static let titleWeight = "LocalNovel.titleWeight"
        static let titleItalic = "LocalNovel.titleItalic"
        static let titleColorMode = "LocalNovel.titleColorMode"
        static let titleColorHex = "LocalNovel.titleColorHex"
        static let titleTop = "LocalNovel.titleTopPadding"
        static let titleBottom = "LocalNovel.titleBottomPadding"
        static let titleLine = "LocalNovel.titleBottomLine"
        static let titleSplit = "LocalNovel.titleSplitTwoLines"

        static let headerMode = "LocalNovel.headerMode"
        static let footerMode = "LocalNovel.footerMode"
        static let headerTop = "LocalNovel.headerTopPadding"
        static let footerBottom = "LocalNovel.footerBottomPadding"

        static let themeId = "LocalNovel.themeId"
        static let customThemes = "LocalNovel.customThemes"
        static let brightness = "LocalNovel.readerBrightness"
        static let keepScreenOn = "LocalNovel.keepScreenOn"
    }

    private func save() {
        defaults.set(Double(fontSize), forKey: Keys.fontSize)
        defaults.set(Double(lineSpacing), forKey: Keys.lineSpacing)
        defaults.set(appearance.rawValue, forKey: Keys.appearance)
        defaults.set(cleanTitles, forKey: Keys.cleanTitles)
        defaults.set(longPressRate, forKey: Keys.longPressRate)
        defaults.set(pageTurn.rawValue, forKey: Keys.pageTurn)
        defaults.set(networkImageCacheMB, forKey: Keys.imageCacheMB)

        defaults.set(Double(paragraphSpacing), forKey: Keys.paragraphSpacing)
        defaults.set(Double(wordSpacing), forKey: Keys.wordSpacing)
        defaults.set(Double(horizontalPadding), forKey: Keys.hPadding)
        defaults.set(textAlign.rawValue, forKey: Keys.align)
        defaults.set(firstLineIndent, forKey: Keys.indent)
        defaults.set(isTraditional, forKey: Keys.traditional)
        defaults.set(fontFamily, forKey: Keys.fontFamily)
        defaults.set(fontWeight.rawValue, forKey: Keys.fontWeight)
        defaults.set(customFontFamilies, forKey: Keys.customFonts)

        defaults.set(titleScale, forKey: Keys.titleScale)
        defaults.set(titleFixedSize, forKey: Keys.titleFixed)
        defaults.set(Double(titleFixedValue), forKey: Keys.titleFixedSize)
        defaults.set(titleWeight.rawValue, forKey: Keys.titleWeight)
        defaults.set(titleItalic, forKey: Keys.titleItalic)
        defaults.set(titleColorMode, forKey: Keys.titleColorMode)
        defaults.set(titleColorHex, forKey: Keys.titleColorHex)
        defaults.set(Double(titleTopPadding), forKey: Keys.titleTop)
        defaults.set(Double(titleBottomPadding), forKey: Keys.titleBottom)
        defaults.set(titleShowBottomLine, forKey: Keys.titleLine)
        defaults.set(titleSplitTwoLines, forKey: Keys.titleSplit)

        defaults.set(headerMode.rawValue, forKey: Keys.headerMode)
        defaults.set(footerMode.rawValue, forKey: Keys.footerMode)
        defaults.set(Double(headerTopPadding), forKey: Keys.headerTop)
        defaults.set(Double(footerBottomPadding), forKey: Keys.footerBottom)

        defaults.set(themeId, forKey: Keys.themeId)
        if let data = try? JSONEncoder().encode(customThemes) {
            defaults.set(data, forKey: Keys.customThemes)
        }
        defaults.set(readerBrightness, forKey: Keys.brightness)
        defaults.set(keepScreenOn, forKey: Keys.keepScreenOn)
    }
}
