import Foundation
import SwiftUI

// MARK: - 阅读偏好（全本地，UserDefaults）

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
    @Published var isDarkMode: Bool = false {
        didSet { if loaded { save() } }
    }
    /// 可选：去掉章节文件夹名的「01_」类前缀（默认关闭，原样展示）
    @Published var cleanTitles: Bool = false {
        didSet { if loaded { save() } }
    }
    /// 长按视频/音频时的临时倍速（默认 2 倍）
    @Published var longPressRate: Double = 2.0 {
        didSet { if loaded { save() } }
    }

    private init() {
        let f = defaults.double(forKey: Keys.fontSize)
        let l = defaults.double(forKey: Keys.lineSpacing)
        let r = defaults.double(forKey: Keys.longPressRate)
        fontSize = f > 0 ? CGFloat(f) : 18
        lineSpacing = l > 0 ? CGFloat(l) : 10
        isDarkMode = defaults.bool(forKey: Keys.dark)
        cleanTitles = defaults.bool(forKey: Keys.cleanTitles)
        longPressRate = r > 0 ? r : 2.0
        loaded = true
    }

    private enum Keys {
        static let fontSize = "LocalNovel.fontSize"
        static let lineSpacing = "LocalNovel.lineSpacing"
        static let dark = "LocalNovel.darkMode"
        static let cleanTitles = "LocalNovel.cleanTitles"
        static let longPressRate = "LocalNovel.longPressRate"
    }

    private func save() {
        defaults.set(Double(fontSize), forKey: Keys.fontSize)
        defaults.set(Double(lineSpacing), forKey: Keys.lineSpacing)
        defaults.set(isDarkMode, forKey: Keys.dark)
        defaults.set(cleanTitles, forKey: Keys.cleanTitles)
        defaults.set(longPressRate, forKey: Keys.longPressRate)
    }
}
