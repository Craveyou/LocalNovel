import Foundation

// MARK: - 安全作用域书签（S2）
// 通过 .fileImporter 选中的文件夹 URL 只在本次会话有效；要重启后仍能读，
// 必须保存 security-scoped bookmark，并在每次启动时重新 startAccessingSecurityScopedResource()。
// 全程不复制、不移动、不写回用户目录。

final class RootFolderAccess {
    static let shared = RootFolderAccess()

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "LocalNovel.rootFolderBookmark"
    private var activeURL: URL?
    private var isAccessing = false

    private init() {}

    /// 保存用户选中的书库根目录
    func saveRootFolder(_ url: URL) throws {
        releaseAccess()
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        // iOS 上 .withSecurityScope 被标记为 unavailable（仅 macOS 可用）；
        // 用 .minimalBookmark 即可，安全作用域由 startAccessingSecurityScopedResource() 提供。
        let data = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: bookmarkKey)
        defaults.synchronize()
    }

    /// 启动时恢复；bookmark 失效（目录被移动/删除）时返回 nil 并清除
    @discardableResult
    func restoreRootFolder() -> URL? {
        // 多窗口 / 重复 onAppear 时避免重复 startAccessing
        if isAccessing, let activeURL { return activeURL }
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
        isAccessing = url.startAccessingSecurityScopedResource()
        activeURL = url
        if stale {
            // 目录被移动/重命名：从解析出的 URL 重建书签，不必让用户重新选
            if let refreshed = try? url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                defaults.set(refreshed, forKey: bookmarkKey)
            }
        }
        return url
    }

    func hasSavedRoot() -> Bool {
        defaults.data(forKey: bookmarkKey) != nil
    }

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
