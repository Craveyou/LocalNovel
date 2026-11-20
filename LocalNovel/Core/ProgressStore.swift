import Foundation

// MARK: - 阅读进度 / 章节记忆（全本地）
// 只存轻量数值与 id，不复制任何用户文件。
//
// 性能要点：滚动时 onAppear 会高频回调，绝不能在回调里同步写 UserDefaults。
// noteAnchor 只改内存，停滚 0.6s 后才在后台队列合并写一次盘；
// 且不持有任何 @State，因此不会触发阅读器整页重绘（这是滑动卡顿的主因）。

final class ProgressStore {
    static let shared = ProgressStore()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let offsets = "LocalNovel.chapterOffsets"
        static let mediaTimes = "LocalNovel.mediaTimes"
        static let lastChapters = "LocalNovel.lastChapters"
        static let anchors = "LocalNovel.chapterAnchors"
        static let hiddenChapters = "LocalNovel.hiddenChapters"
    }

    private let lock = NSLock()
    private let anchorQueue = DispatchQueue(label: "LocalNovel.anchorWrite", qos: .utility)
    private var pendingAnchors: [String: String] = [:]
    private var pendingWork: DispatchWorkItem?

    private init() {}

    // MARK: 滚动位置（旧接口保留，兼容既有调用）

    func offset(for chapterId: String) -> CGFloat {
        let map = defaults.dictionary(forKey: Keys.offsets) as? [String: Double] ?? [:]
        return CGFloat(map[chapterId] ?? 0)
    }

    func setOffset(_ value: CGFloat, for chapterId: String) {
        var map = defaults.dictionary(forKey: Keys.offsets) as? [String: Double] ?? [:]
        map[chapterId] = Double(value)
        defaults.set(map, forKey: Keys.offsets)
    }

    // MARK: 音视频播放进度（秒）

    func mediaTime(for chapterId: String) -> Double {
        let map = defaults.dictionary(forKey: Keys.mediaTimes) as? [String: Double] ?? [:]
        return map[chapterId] ?? 0
    }

    func setMediaTime(_ value: Double, for chapterId: String) {
        var map = defaults.dictionary(forKey: Keys.mediaTimes) as? [String: Double] ?? [:]
        map[chapterId] = max(0, value)
        defaults.set(map, forKey: Keys.mediaTimes)
    }

    // MARK: 每本书最近阅读的章节

    func lastChapterId(for bookId: String) -> String? {
        (defaults.dictionary(forKey: Keys.lastChapters) as? [String: String] ?? [:])[bookId]
    }

    func setLastChapter(_ chapterId: String, for bookId: String) {
        var map = defaults.dictionary(forKey: Keys.lastChapters) as? [String: String] ?? [:]
        map[bookId] = chapterId
        defaults.set(map, forKey: Keys.lastChapters)
    }

    // MARK: 章内滚动锚点

    /// 读锚点：内存里还没落盘的优先。
    /// 滚动时 noteAnchor 有 0.6s 防抖，只读盘会拿到「0.6 秒前」的位置 ——
    /// 加书签 / 记笔记 / 进度百分比都读这里，必须是最新值。
    func anchor(for chapterId: String) -> String? {
        lock.lock()
        let pending = pendingAnchors[chapterId]
        lock.unlock()
        if let pending { return pending }
        return (defaults.dictionary(forKey: Keys.anchors) as? [String: String] ?? [:])[chapterId]
    }

    func setAnchor(_ anchor: String, for chapterId: String) {
        // 主动设置优先于防抖队列里还没落盘的旧值，否则「从章首开始」会被
        // 0.6 秒后的 flush 用上一次的位置覆盖回去。
        // 读改写整体加锁：否则会和 flushAnchors 的整表写回互相覆盖（丢失更新）。
        lock.lock()
        pendingAnchors.removeValue(forKey: chapterId)
        var map = defaults.dictionary(forKey: Keys.anchors) as? [String: String] ?? [:]
        map[chapterId] = anchor
        defaults.set(map, forKey: Keys.anchors)
        lock.unlock()
    }

    /// 滚动过程中调用：只记内存、重置防抖计时器，不写盘、不触发重绘。
    func noteAnchor(_ anchor: String, for chapterId: String) {
        lock.lock()
        pendingAnchors[chapterId] = anchor
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushAnchors()
        }
        pendingWork = work
        lock.unlock()
        anchorQueue.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// 离开章节 / 进入后台时立刻落盘，避免最后一次位置丢失
    func flushAnchors() {
        lock.lock()
        defer { lock.unlock() }
        let snapshot = pendingAnchors
        pendingAnchors.removeAll()
        guard !snapshot.isEmpty else { return }
        var map = defaults.dictionary(forKey: Keys.anchors) as? [String: String] ?? [:]
        for (id, anchor) in snapshot { map[id] = anchor }
        defaults.set(map, forKey: Keys.anchors)
    }

    // MARK: 删除 / 隐藏章节

    /// 外部只读目录删不掉源文件时，改为隐藏（可在设置里恢复）
    func hiddenChapterIds() -> Set<String> {
        Set(defaults.stringArray(forKey: Keys.hiddenChapters) ?? [])
    }

    var hiddenChapterCount: Int {
        (defaults.stringArray(forKey: Keys.hiddenChapters) ?? []).count
    }

    func hideChapter(_ chapterId: String) {
        var ids = defaults.stringArray(forKey: Keys.hiddenChapters) ?? []
        if !ids.contains(chapterId) { ids.append(chapterId) }
        defaults.set(ids, forKey: Keys.hiddenChapters)
    }

    func unhideAllChapters() {
        defaults.removeObject(forKey: Keys.hiddenChapters)
    }

    /// 删除章节后清掉它残留的所有进度，避免「记忆」指向已不存在的章节
    func clearProgress(for chapterId: String) {
        flushAnchors()
        var anchors = defaults.dictionary(forKey: Keys.anchors) as? [String: String] ?? [:]
        anchors.removeValue(forKey: chapterId)
        defaults.set(anchors, forKey: Keys.anchors)

        var offsets = defaults.dictionary(forKey: Keys.offsets) as? [String: Double] ?? [:]
        offsets.removeValue(forKey: chapterId)
        defaults.set(offsets, forKey: Keys.offsets)

        var times = defaults.dictionary(forKey: Keys.mediaTimes) as? [String: Double] ?? [:]
        times.removeValue(forKey: chapterId)
        defaults.set(times, forKey: Keys.mediaTimes)

        var last = defaults.dictionary(forKey: Keys.lastChapters) as? [String: String] ?? [:]
        // 先收集再删除，避免遍历字典时修改触发独占访问冲突
        let staleBooks = last.compactMap { $0.value == chapterId ? $0.key : nil }
        for book in staleBooks { last.removeValue(forKey: book) }
        defaults.set(last, forKey: Keys.lastChapters)
    }

    func clearLastChapter(for bookId: String) {
        var last = defaults.dictionary(forKey: Keys.lastChapters) as? [String: String] ?? [:]
        last.removeValue(forKey: bookId)
        defaults.set(last, forKey: Keys.lastChapters)
    }

    /// 重新分章：章节 id（文件路径 + 区间起点）与段落下标全部失效。
    /// 一次性清掉这本书的所有锚点 / 滚动位置 / 媒体进度与「最近读的章」，
    /// 让新章节一律从章首开始 —— 否则旧锚点会指向完全不存在的段落，
    /// 表现就是「重切后打开直接翻到末尾」。
    func resetAnchors(chapterPathPrefix prefix: String) {
        guard !prefix.isEmpty else { return }
        // 整段持锁：和滚动防抖的 flushAnchors 互斥，否则刚清掉的锚点会被
        // 后台 flush 用旧快照整表写回来。
        lock.lock()
        defer { lock.unlock() }
        pendingAnchors = pendingAnchors.filter { !$0.key.hasPrefix(prefix) }

        var anchors = defaults.dictionary(forKey: Keys.anchors) as? [String: String] ?? [:]
        // 先快照 key 再删：边遍历边改同一个字典会触发独占访问冲突
        for key in Array(anchors.keys) where key.hasPrefix(prefix) { anchors.removeValue(forKey: key) }
        defaults.set(anchors, forKey: Keys.anchors)

        var offsets = defaults.dictionary(forKey: Keys.offsets) as? [String: Double] ?? [:]
        for key in Array(offsets.keys) where key.hasPrefix(prefix) { offsets.removeValue(forKey: key) }
        defaults.set(offsets, forKey: Keys.offsets)

        var times = defaults.dictionary(forKey: Keys.mediaTimes) as? [String: Double] ?? [:]
        for key in Array(times.keys) where key.hasPrefix(prefix) { times.removeValue(forKey: key) }
        defaults.set(times, forKey: Keys.mediaTimes)

        var last = defaults.dictionary(forKey: Keys.lastChapters) as? [String: String] ?? [:]
        let staleBooks = last.compactMap { $0.value.hasPrefix(prefix) ? $0.key : nil }
        for book in staleBooks { last.removeValue(forKey: book) }
        defaults.set(last, forKey: Keys.lastChapters)
    }

    /// 重新分章后「隐藏章节」记录同样失配（存的是 chapter.id = 路径#起点）。
    /// 留着它们既不会命中新章节，也会让设置页的统计虚高，直接清掉这批。
    /// 返回清掉的条数，供界面提示「已删除的章节会恢复」。
    @discardableResult
    func resetHiddenChapters(chapterPathPrefix prefix: String) -> Int {
        guard !prefix.isEmpty else { return 0 }
        let ids = defaults.stringArray(forKey: Keys.hiddenChapters) ?? []
        guard !ids.isEmpty else { return 0 }
        let kept = ids.filter { !$0.hasPrefix(prefix) }
        guard kept.count != ids.count else { return 0 }
        if kept.isEmpty {
            defaults.removeObject(forKey: Keys.hiddenChapters)
        } else {
            defaults.set(kept, forKey: Keys.hiddenChapters)
        }
        return ids.count - kept.count
    }
}
