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

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private var loaded = false

    @Published var fontSize: CGFloat = 18 {
        didSet { if loaded { save() } }
    }
    @Published var lineSpacing: CGFloat = 10 {
        didSet { if loaded { save() } }
    }
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

    private init() {
        let f = defaults.double(forKey: Keys.fontSize)
        let l = defaults.double(forKey: Keys.lineSpacing)
        let r = defaults.double(forKey: Keys.longPressRate)
        fontSize = f > 0 ? CGFloat(f) : 18
        lineSpacing = l > 0 ? CGFloat(l) : 10
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
        cleanTitles = defaults.bool(forKey: Keys.cleanTitles)
        longPressRate = r > 0 ? r : 2.0
        // 默认 512 MB；用户显式选「不限制」时存的就是 0，要能区分「没设置过」
        networkImageCacheMB = defaults.object(forKey: Keys.imageCacheMB) == nil
            ? 512
            : max(0, defaults.integer(forKey: Keys.imageCacheMB))
        loaded = true
    }

    private enum Keys {
        static let fontSize = "LocalNovel.fontSize"
        static let lineSpacing = "LocalNovel.lineSpacing"
        static let appearance = "LocalNovel.appearance"
        static let dark = "LocalNovel.darkMode" // 旧键，仅用于迁移读取
        static let cleanTitles = "LocalNovel.cleanTitles"
        static let longPressRate = "LocalNovel.longPressRate"
        static let pageTurn = "LocalNovel.pageTurn"
        static let imageCacheMB = "LocalNovel.imageCacheMB"
    }

    private func save() {
        defaults.set(Double(fontSize), forKey: Keys.fontSize)
        defaults.set(Double(lineSpacing), forKey: Keys.lineSpacing)
        defaults.set(appearance.rawValue, forKey: Keys.appearance)
        defaults.set(cleanTitles, forKey: Keys.cleanTitles)
        defaults.set(longPressRate, forKey: Keys.longPressRate)
        defaults.set(pageTurn.rawValue, forKey: Keys.pageTurn)
        defaults.set(networkImageCacheMB, forKey: Keys.imageCacheMB)
    }
}
