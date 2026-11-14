import SwiftUI

// MARK: - 书库状态（S2 / S3 桥接）
// 持有扫描结果，缓存章节装配与正文，避免滚动时反复读磁盘。

final class LibraryStore: ObservableObject {
    @Published private(set) var library: Library?
    @Published private(set) var errorMessage: String?
    @Published var isImporting = false

    private var contentCache: [String: ChapterContent] = [:]
    private var textCache: [String: String] = [:]
    private let animatedDetector: (URL) -> Bool

    init(animatedDetector: @escaping (URL) -> Bool = FrameDetector.isAnimated) {
        self.animatedDetector = animatedDetector
    }

    /// App 启动：恢复上次选中的书库根目录
    func restore() {
        guard let root = RootFolderAccess.shared.restoreRootFolder() else { return }
        rebuild(root: root)
    }

    /// 用户重新选择书库根目录
    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = "导入失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try RootFolderAccess.shared.saveRootFolder(url)
                // 保存后重新解析书签并保持访问权，避免 saveRootFolder 里临时释放权限导致读不到
                guard let root = RootFolderAccess.shared.restoreRootFolder() else {
                    errorMessage = "目录访问权限已失效，请重新选择书库目录。"
                    return
                }
                invalidateCaches()
                rebuild(root: root)
            } catch {
                errorMessage = "无法保存目录访问权限：\(error.localizedDescription)"
            }
        }
    }

    func reload() {
        guard let root = library?.rootURL else { return }
        invalidateCaches()
        rebuild(root: root)
    }

    private func rebuild(root: URL) {
        errorMessage = nil
        let library = BookScanner.scan(rootURL: root, cleanTitles: Preferences.shared.cleanTitles)
        if library.books.isEmpty {
            errorMessage = "这个目录里没有找到「作者文件夹 / 章节文件夹」结构。请选择最外层的书库根目录。"
        }
        self.library = library
    }

    /// 章节内容（带缓存）
    func content(for chapter: Chapter) -> ChapterContent {
        if let cached = contentCache[chapter.id] { return cached }
        let value = MediaResolver.resolveChapter(chapter, animatedDetector: animatedDetector)
        contentCache[chapter.id] = value
        return value
    }

    /// 正文（带缓存）；失败时返回可读的错误说明而非乱码
    func text(for chapter: Chapter) -> String {
        if let cached = textCache[chapter.id] { return cached }
        guard let url = content(for: chapter).textURL else {
            let msg = "（本章没有正文文件）"
            textCache[chapter.id] = msg
            return msg
        }
        do {
            let value = try TextLoader.load(url)
            textCache[chapter.id] = value
            return value
        } catch {
            let msg = "（\(error.localizedDescription)）"
            textCache[chapter.id] = msg
            return msg
        }
    }

    func ignoredHint(for chapter: Chapter) -> String? {
        let ignored = content(for: chapter).ignoredFiles
        guard !ignored.isEmpty else { return nil }
        return "已忽略 \(ignored.count) 个未识别文件：\(ignored.prefix(3).joined(separator: "、"))"
    }

    private func invalidateCaches() {
        contentCache.removeAll()
        textCache.removeAll()
    }
}
