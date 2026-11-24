import Foundation

// MARK: - 目录访问权（兼容旧版本留下的外部书库书签）
// 现在主路径是 App 文档目录 + 导入复制，这里只用于恢复旧版 App 曾选中的外部目录。
// 修正：.minimalBookmark 会生成【不含 security scope】的最小书签，iOS 上
// 重启后 resolve 出来的 URL 读不了外部目录；应改用默认选项，让系统把
// security scope 一并写进书签。反复 start/stop 会让内核 access count 错乱，
// 因此这里 start 一次并保持，不在同一次会话里来回倒手。

final class RootFolderAccess {
    static let shared = RootFolderAccess()

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "LocalNovel.rootFolderBookmark"
    private var activeURL: URL?
    private var isAccessing = false

    private init() {}

    /// 用户选中书库目录后调用：保存书签并返回【仍然持有访问权】的原始 URL。
    /// 调用方应立即用这个 URL 扫描，不要丢弃后再 resolve 一次。
    ///
    /// 关键：书签持久化失败【不抛错、不阻断本次扫描】。文件选择器回调期间
    /// 该 URL 本身可读，若因 bookmarkData 失败就直接 return，会表现成
    /// 「文件夹选了但一本书都进不来」。最坏情况只是重启后需重选一次目录。
    @discardableResult
    func saveRootFolder(_ url: URL) -> URL {
        releaseAccess()
        // iOS 上从文件选择器返回的 URL 已带访问权限；start 一次并保持
        if url.startAccessingSecurityScopedResource() {
            isAccessing = true
        }
        activeURL = url

        // 默认选项会保留 iOS 的 security scope；.minimalBookmark 会丢掉它
        if let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(data, forKey: bookmarkKey)
            defaults.synchronize()
        }
        return url
    }

    /// 启动时恢复。bookmark 失效（目录被移动/删除）时返回 nil 并清除。
    @discardableResult
    func restoreRootFolder() -> URL? {
        // 同一次会话内复用，避免重复 resolve 累积隐式 access count
        if let activeURL { return activeURL }
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            clear()
            return nil
        }
        // iOS 上 resolve 已隐式授权；这里 start 一次并保持到 App 结束，
        // 避免「读一下就 stop」造成后续章节读取失败。
        if url.startAccessingSecurityScopedResource() {
            isAccessing = true
        }
        activeURL = url
        if stale {
            if let refreshed = try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                defaults.set(refreshed, forKey: bookmarkKey)
                defaults.synchronize()
            }
        }
        return url
    }

    func hasSavedRoot() -> Bool {
        defaults.data(forKey: bookmarkKey) != nil
    }

    /// 已解析的目录（供「重新扫描」复用，不再 resolve 一次）
    func currentRootURL() -> URL? { activeURL }

    func releaseAccess() {
        if isAccessing, let url = activeURL {
            url.stopAccessingSecurityScopedResource()
        }
        isAccessing = false
        activeURL = nil
    }

    func clear() {
        releaseAccess()
        defaults.removeObject(forKey: bookmarkKey)
        defaults.synchronize()
    }
}
