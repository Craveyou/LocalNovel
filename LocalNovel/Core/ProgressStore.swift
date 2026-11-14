import Foundation

// MARK: - 阅读进度（全本地）
// 记录每章滚动位置、章末音视频播放秒数、每本书最近阅读章节。
// 只存轻量数值，不复制任何用户文件。

final class ProgressStore {
    static let shared = ProgressStore()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let offsets = "LocalNovel.chapterOffsets"
        static let mediaTimes = "LocalNovel.mediaTimes"
        static let lastChapters = "LocalNovel.lastChapters"
        static let anchors = "LocalNovel.chapterAnchors"
    }

    private init() {}

    // 滚动位置
    func offset(for chapterId: String) -> CGFloat {
        let map = defaults.dictionary(forKey: Keys.offsets) as? [String: Double] ?? [:]
        return CGFloat(map[chapterId] ?? 0)
    }

    func setOffset(_ value: CGFloat, for chapterId: String) {
        var map = defaults.dictionary(forKey: Keys.offsets) as? [String: Double] ?? [:]
        map[chapterId] = Double(value)
        defaults.set(map, forKey: Keys.offsets)
    }

    // 音视频播放进度（秒）
    func mediaTime(for chapterId: String) -> Double {
        let map = defaults.dictionary(forKey: Keys.mediaTimes) as? [String: Double] ?? [:]
        return map[chapterId] ?? 0
    }

    func setMediaTime(_ value: Double, for chapterId: String) {
        var map = defaults.dictionary(forKey: Keys.mediaTimes) as? [String: Double] ?? [:]
        map[chapterId] = max(0, value)
        defaults.set(map, forKey: Keys.mediaTimes)
    }

    // 每本书最近阅读的章节
    func lastChapterId(for bookId: String) -> String? {
        (defaults.dictionary(forKey: Keys.lastChapters) as? [String: String] ?? [:])[bookId]
    }

    func setLastChapter(_ chapterId: String, for bookId: String) {
        var map = defaults.dictionary(forKey: Keys.lastChapters) as? [String: String] ?? [:]
        map[bookId] = chapterId
        defaults.set(map, forKey: Keys.lastChapters)
    }

    // 章内滚动位置（用内容块锚点 id，字号变化后仍能恢复）
    func anchor(for chapterId: String) -> String? {
        (defaults.dictionary(forKey: Keys.anchors) as? [String: String] ?? [:])[chapterId]
    }

    func setAnchor(_ anchor: String, for chapterId: String) {
        var map = defaults.dictionary(forKey: Keys.anchors) as? [String: String] ?? [:]
        map[chapterId] = anchor
        defaults.set(map, forKey: Keys.anchors)
    }
}
