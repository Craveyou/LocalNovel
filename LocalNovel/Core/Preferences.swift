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
    case cover = 3
    case vertical = 4
    case none = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .scroll:   return "上下滚动"
        case .page:     return "仿真"
        case .slide:    return "平移"
        case .cover:    return "覆盖"
        case .vertical: return "上下翻页"
        case .none:     return "无动画"
        }
    }

    /// 是否走「分页阅读」引擎（除连续滚动外都是分页，只是呈现方式不同）
    var isPaged: Bool { self != .scroll }

    /// 分页引擎的呈现样式
    var flipStyle: PageFlipStyle {
        switch self {
        case .page:     return .curl
        case .slide:    return .slide
        case .cover:    return .cover
        case .vertical: return .vertical
        case .none:     return .none
        case .scroll:   return .slide   // 不参与分页，兜底
        }
    }

    var detail: String {
        switch self {
        case .scroll:
            return "上下滚动：连续长页，段落流畅衔接，适合长篇与图文混排。"
        case .page:
            return "仿真：纸张卷起的立体动画，点屏幕左 / 右侧翻页。"
        case .slide:
            return "平移：整页跟手横移，翻动时带页边阴影，松手自动吸附到下一页。"
        case .cover:
            return "覆盖：新页从右侧压上来、旧页不动，往回翻则旧页滑走露出上一页。"
        case .vertical:
            return "上下翻页：整页纵向吸附，上下滑动翻页（不是连续滚动）。"
        case .none:
            return "无动画：左右滑或点左右边缘直接换页，不加过渡，最省电最跟手。"
        }
    }
}

/// 页眉内容
/// 自动阅读的方式（I 组）：翻页 = 每页定时翻；滚动 = 匀速往下推
enum AutoReadMode: Int, CaseIterable, Identifiable {
    case flip = 0
    case scroll = 1

    var id: Int { rawValue }
    var label: String { self == .flip ? "翻页" : "滚动" }
    var detail: String {
        self == .flip
            ? "每页停留设定秒数后自动翻页，翻到章末自动进下一章。"
            : "按设定速度匀速向下滚动，滚到底自动进下一章。"
    }
}

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
    /// 是否显示页码 / 百分比（与「页脚内容」解耦：关掉就是纯正文，不留空白条）
    @Published var showReadingProgress: Bool = true {
        didSet { if loaded { save() } }
    }

    // MARK: 主题与亮度（F 组）

    @Published var themeId: String = "paper" {
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
    /// 覆盖翻页的动画时长（秒）。手势驱动的那几种翻页不受它影响。
    @Published var flipDuration: Double = 0.28 {
        didSet { if loaded { save() } }
    }

    // MARK: 自动阅读（I 组）

    @Published var autoReadMode: AutoReadMode = .flip {
        didSet {
            guard loaded else { return }
            save()
            // 模式必须和翻页方式一致：滚动靠推 contentOffset（只有滚动排版有它），
            // 翻页靠分页引擎的翻页指令。在面板里切模式时顺手把版式也切过去。
            switch autoReadMode {
            case .scroll: if pageTurn.isPaged { pageTurn = .scroll }
            case .flip:   if !pageTurn.isPaged { pageTurn = .slide }
            }
        }
    }
    /// 翻页模式：每页停留多少秒
    @Published var autoReadFlipSeconds: Double = 8 {
        didSet { if loaded { save() } }
    }
    /// 滚动模式：每秒推进多少点
    @Published var autoReadScrollSpeed: Double = 40 {
        didSet { if loaded { save() } }
    }
    /// 自动阅读时在底部显示进度条
    @Published var autoReadShowsProgress: Bool = true {
        didSet { if loaded { save() } }
    }

    // MARK: 手势与启动（A 组）

    /// 三块点击区各自的动作（默认左=上一页、中=菜单、右=下一页）
    @Published var tapLeft: TapZoneAction = .prevPage {
        didSet { if loaded { save() } }
    }
    @Published var tapCenter: TapZoneAction = .menu {
        didSet { if loaded { save() } }
    }
    @Published var tapRight: TapZoneAction = .nextPage {
        didSet { if loaded { save() } }
    }

    // MARK: 净化（K 组）

    /// 净化总开关（关掉后规则保留但不生效）
    @Published var purifyEnabled: Bool = true {
        didSet { if loaded { save(); ReaderTextPipeline.reset() } }
    }
    /// 正则替换规则
    @Published var purifyRules: [PurifyRule] = [] {
        didSet { if loaded { save(); ReaderTextPipeline.reset() } }
    }

    /// 真正生效的规则（总开关关掉时为空）
    var activePurifyRules: [PurifyRule] {
        purifyEnabled ? purifyRules : []
    }

    // MARK: 重新分章（G 组）
    //
    // 每本书一条自定义分章正则（bookId → 正则文本）。空串等同于没设置，
    // 表示走内置的「第X章 / Chapter N / 序章」那套。规则只影响分章，
    // 不动源文件；应用后该书的章节区间会整批重建。
    @Published var chapterRules: [String: String] = [:] {
        didSet { if loaded { save() } }
    }

    /// 这本书当前的分章规则；没写过（或写成空）返回 nil
    func chapterRule(for bookId: String) -> String? {
        let rule = (chapterRules[bookId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return rule.isEmpty ? nil : rule
    }

    /// 写入 / 清除某本书的分章规则（空串 = 恢复自动分章）
    func setChapterRule(_ rule: String?, for bookId: String) {
        let text = (rule ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            guard chapterRules[bookId] != nil else { return }
            chapterRules.removeValue(forKey: bookId)
        } else {
            guard chapterRules[bookId] != text else { return }
            chapterRules[bookId] = text
        }
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

    /// 当前主题（六套内置之一）
    var theme: ReaderTheme {
        ReaderTheme.theme(id: themeId)
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
                         weight: fontWeight,
                         lineSpacing: lineSpacing,
                         paragraphSpacing: paragraphSpacing,
                         wordSpacing: wordSpacing,
                         horizontalPadding: horizontalPadding,
                         alignment: textAlign,
                         firstLineIndent: firstLineIndent,
                         title: titleStyle)
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
            // 老数据里可能存着已删掉的自定义主题 id：归一化到内置六套，避免每次启动都兜底
            themeId = ReaderTheme.theme(id: id).id
        } else if appearance == .dark {
            themeId = "night"
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
        showReadingProgress = defaults.object(forKey: Keys.showProgress) == nil
            ? true : defaults.bool(forKey: Keys.showProgress)
        readerBrightness = Double(number(Keys.brightness, 1.0, 0.25, 1.0))
        flipDuration = Double(number(Keys.flipDuration, 0.28, 0.05, 0.8))
        autoReadMode = AutoReadMode(rawValue: defaults.object(forKey: Keys.autoReadMode) == nil
                                    ? 0 : defaults.integer(forKey: Keys.autoReadMode)) ?? .flip
        autoReadFlipSeconds = Double(number(Keys.autoFlipSeconds, 8, 2, 60))
        autoReadScrollSpeed = Double(number(Keys.autoScrollSpeed, 40, 10, 200))
        autoReadShowsProgress = defaults.object(forKey: Keys.autoProgress) == nil
            ? true : defaults.bool(forKey: Keys.autoProgress)
        tapLeft = TapZoneAction(rawValue: defaults.object(forKey: Keys.tapLeft) == nil
                                ? 0 : defaults.integer(forKey: Keys.tapLeft)) ?? .prevPage
        tapCenter = TapZoneAction(rawValue: defaults.object(forKey: Keys.tapCenter) == nil
                                  ? 2 : defaults.integer(forKey: Keys.tapCenter)) ?? .menu
        tapRight = TapZoneAction(rawValue: defaults.object(forKey: Keys.tapRight) == nil
                                 ? 1 : defaults.integer(forKey: Keys.tapRight)) ?? .nextPage
        purifyEnabled = defaults.object(forKey: Keys.purifyEnabled) == nil
            ? true : defaults.bool(forKey: Keys.purifyEnabled)
        if let data = defaults.data(forKey: Keys.purifyRules),
           let list = try? JSONDecoder().decode([PurifyRule].self, from: data) {
            purifyRules = list
        }
        if let data = defaults.data(forKey: Keys.chapterRules),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            chapterRules = map
        }
        firstLineIndent = defaults.object(forKey: Keys.indent) == nil
            ? true : defaults.bool(forKey: Keys.indent)
        keepScreenOn = defaults.bool(forKey: Keys.keepScreenOn)
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
        static let fontWeight = "LocalNovel.fontWeight"

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
        static let showProgress = "LocalNovel.showReadingProgress"

        static let themeId = "LocalNovel.themeId"
        static let brightness = "LocalNovel.readerBrightness"
        static let flipDuration = "LocalNovel.flipDuration"
        static let tapLeft = "LocalNovel.tapLeft"
        static let tapCenter = "LocalNovel.tapCenter"
        static let tapRight = "LocalNovel.tapRight"
        static let purifyEnabled = "LocalNovel.purifyEnabled"
        static let purifyRules = "LocalNovel.purifyRules"
        static let chapterRules = "LocalNovel.chapterRules"
        static let keepScreenOn = "LocalNovel.keepScreenOn"
        static let autoReadMode = "LocalNovel.autoReadMode"
        static let autoFlipSeconds = "LocalNovel.autoReadFlipSeconds"
        static let autoScrollSpeed = "LocalNovel.autoReadScrollSpeed"
        static let autoProgress = "LocalNovel.autoReadShowsProgress"
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
        defaults.set(fontWeight.rawValue, forKey: Keys.fontWeight)

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
        defaults.set(showReadingProgress, forKey: Keys.showProgress)

        defaults.set(themeId, forKey: Keys.themeId)
        defaults.set(readerBrightness, forKey: Keys.brightness)
        defaults.set(flipDuration, forKey: Keys.flipDuration)
        defaults.set(tapLeft.rawValue, forKey: Keys.tapLeft)
        defaults.set(tapCenter.rawValue, forKey: Keys.tapCenter)
        defaults.set(tapRight.rawValue, forKey: Keys.tapRight)
        defaults.set(purifyEnabled, forKey: Keys.purifyEnabled)
        if let data = try? JSONEncoder().encode(purifyRules) {
            defaults.set(data, forKey: Keys.purifyRules)
        }
        if let data = try? JSONEncoder().encode(chapterRules) {
            defaults.set(data, forKey: Keys.chapterRules)
        }
        defaults.set(keepScreenOn, forKey: Keys.keepScreenOn)
        defaults.set(autoReadMode.rawValue, forKey: Keys.autoReadMode)
        defaults.set(autoReadFlipSeconds, forKey: Keys.autoFlipSeconds)
        defaults.set(autoReadScrollSpeed, forKey: Keys.autoScrollSpeed)
        defaults.set(autoReadShowsProgress, forKey: Keys.autoProgress)
    }
}
