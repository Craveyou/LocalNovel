import Foundation

/// 书库：内置样例 + 从文件导入的小说。
/// 导入 = 把选中的文件复制进 Documents/Novels/，App 卸载前一直有效；
/// 记住「导入过哪些书」，下次启动从目录重建书架，顺序稳定。
public final class TextLibraryStore: ObservableObject {
    @Published public private(set) var books: [TextBook] = []

    /// 内置书（bundle 里的样例）永远排在最前，且不可删除。
    private let bundled: [TextBook]
    private let libraryDir: URL

    public init(bundled: [TextBook] = []) {
        self.bundled = bundled
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        libraryDir = docs.appendingPathComponent("Novels", isDirectory: true)
        try? FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)
        reload()
    }

    /// 某本书是否是用户导入的（内置样例返回 false）。
    public func isImported(_ book: TextBook) -> Bool {
        book.url.standardizedFileURL.path.hasPrefix(libraryDir.standardizedFileURL.path)
    }

    /// 从文件选择器导入。安全作用域访问期间复制文件，选完即与原位置解耦。
    /// 返回值：nil = 成功；String = 用户可读的失败原因。
    @discardableResult
    public func importBook(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        guard TextFileLoader.supportedExtensions.contains(ext) else {
            return "暂不支持的格式：.\(ext)（只认 txt / md / text）"
        }

        let gotAccess = url.startAccessingSecurityScopedResource()
        defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }

        // 同名文件不静默覆盖：加序号成《书名 2.txt》
        let base = url.deletingPathExtension().lastPathComponent
        var target = libraryDir.appendingPathComponent("\(base).\(ext)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = libraryDir.appendingPathComponent("\(base) \(suffix).\(ext)")
            suffix += 1
        }

        // 文档选择器返回的 URL（尤其是「最近项目」/ iCloud / 第三方网盘里的）
        // 必须经 NSFileCoordinator 协调读取，直接 copyItem 会拿不到内容。
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url,
                                       options: .withoutChanges,
                                       error: &coordinatorError) { readURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: target)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError {
            return "读取失败：\(coordinatorError.localizedDescription)"
        }
        if let copyError {
            return "复制失败：\(copyError.localizedDescription)"
        }
        reload()
        return nil
    }

    /// 只删导入的书（复制进 Documents 的文件 + 记录）；内置书不可删。
    public func remove(_ book: TextBook) {
        guard isImported(book) else { return }
        try? FileManager.default.removeItem(at: book.url)
        reload()
    }

    /// 目录是唯一事实来源：目录里有什么就显示什么，
    /// UserDefaults 只留一份已删除容错的记录（防御文件被外部改动）。
    private func reload() {
        let fm = FileManager.default
        var imported: [TextBook] = []
        if let files = try? fm.contentsOfDirectory(at: libraryDir,
                                                   includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles]) {
            imported = files
                .filter { TextFileLoader.supportedExtensions.contains($0.pathExtension.lowercased()) }
                .map { TextBook(title: $0.deletingPathExtension().lastPathComponent, url: $0) }
        }
        books = bundled + imported.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
