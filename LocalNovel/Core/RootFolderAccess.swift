import Foundation

// MARK: - 目录访问权（S2）
// 通过 .fileImporter 选中的文件夹返回的是 security-scoped URL。
// iOS 与 macOS 的关键差异：
//   * iOS 不支持 security-scoped bookmark（.withSecurityScope 仅 macOS 可用），
//     因此用 .minimalBookmark 保存「普通书签」即可持久化访问。
//   * iOS 上 resolvingBookmarkData 本身会隐式获得访问权；反复
//     start/stopAccessingSecurityScopedResource 会让内核的 access count 错乱。
// 所以这里：选中后立刻 startAccessing 并【保持】，直接用原始 URL 扫描；
// 书签只用于下次启动恢复，不在同一次会话里 stop→resolve→start 来回倒手。
// 全程不复制、不移动、不写回用户目录。

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

        // .minimalBookmark 是 iOS 上正确的持久化方式（无需 .withSecurityScope）
        if let data = try? url.bookmarkData(
            options: .minimalBookmark,
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
                options: .minimalBookmark,
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
