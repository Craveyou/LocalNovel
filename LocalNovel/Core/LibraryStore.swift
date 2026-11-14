import SwiftUI
import Foundation

// MARK: - 书库状态（S2 / S3 桥接）
// 持有扫描结果，缓存章节装配与正文，避免滚动时反复读磁盘。

final class LibraryStore: ObservableObject {
    @Published private(set) var library: Library?
    @Published private(set) var errorMessage: String?
    /// 扫描诊断（成功或失败都显示，便于用户判断选没选对层级）
    @Published private(set) var diagnostics: String?
    /// 当前载入方式：true = 读 App 自己的文档目录（零权限兜底），false = 用户选的外部目录
    @Published private(set) var usingAppDocuments = false
    @Published var isImporting = false

    private var contentCache: [String: ChapterContent] = [:]
    private var textCache: [String: String] = [:]
    private let animatedDetector: (URL) -> Bool

    init(animatedDetector: @escaping (URL) -> Bool = FrameDetector.isAnimated) {
        self.animatedDetector = animatedDetector
    }

    /// App 启动：恢复上次选中的书库根目录；若无记录，尝试读 App 自己的文档目录
    func restore() {
        if let root = RootFolderAccess.shared.restoreRootFolder() {
            usingAppDocuments = false
            invalidateCaches()
            rebuild(root: root)
            // 外部目录一扫为空时，再尝试零权限兜底，避免用户卡在空书库
            if library?.books.isEmpty == true, let docs = appDocumentsURL() {
                let probe = BookScanner.scan(rootURL: docs,
                                             cleanTitles: Preferences.shared.cleanTitles)
                if !probe.books.isEmpty {
                    usingAppDocuments = true
                    invalidateCaches()
                    rebuild(root: docs)
                }
            }
            return
        }
        if let docs = appDocumentsURL() {
            let probe = BookScanner.scan(rootURL: docs,
                                         cleanTitles: Preferences.shared.cleanTitles)
            if !probe.books.isEmpty {
                usingAppDocuments = true
                rebuild(root: docs)
            }
        }
    }

    /// 用户重新选择书库根目录
    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = "导入失败：\(error.localizedDescription)"
            diagnostics = nil
        case .success(let urls):
            guard let url = urls.first else {
                errorMessage = "没有拿到目录。请在文件选择器里【进入书库文件夹后点右上角「打开 / 选择」】来选中这一层，而不是只点进去浏览。"
                diagnostics = nil
                return
            }
            // 书签持久化失败不影响本次扫描：回调期间该 URL 本身可读
            let root = RootFolderAccess.shared.saveRootFolder(url)
            usingAppDocuments = false
            invalidateCaches()
            rebuild(root: root)
        }
    }

    /// 手动「重新扫描」：复用已解析的 URL，不再 resolve 一次
    func reload() {
        let root: URL?
        if usingAppDocuments {
            root = appDocumentsURL()
        } else {
            root = RootFolderAccess.shared.currentRootURL()
                ?? RootFolderAccess.shared.restoreRootFolder()
        }
        guard let url = root else {
            errorMessage = "还没有选择书库目录，请点「选择书库目录」。"
            return
        }
        invalidateCaches()
        rebuild(root: url)
    }

    /// 切换到「文件 App → 我的 iPhone → 本地小说」里的书（零权限路径）
    func useAppDocuments() {
        guard let docs = appDocumentsURL() else { return }
        usingAppDocuments = true
        invalidateCaches()
        rebuild(root: docs)
    }

    private func appDocumentsURL() -> URL? {
        try? FileManager.default.url(for: .documentDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)
    }

    private func rebuild(root: URL) {
        let report = BookScanner.scanWithDiagnostics(
            rootURL: root,
            cleanTitles: Preferences.shared.cleanTitles
        )
        self.library = report.library
        var line = buildDiagnosticsLine(root: root, report: report)
        // 书签没存上：本次仍能读，但重启后要重选；明确告知并指向免授权路径
        if !usingAppDocuments && !RootFolderAccess.shared.hasSavedRoot() {
            line += " · 目录权限未能持久化，重启后需重新选择；也可改用「App 文档目录里的书（免授权）」"
        }
        self.diagnostics = line
        self.errorMessage = report.library.books.isEmpty ? report.failureHint : nil
    }

    private func buildDiagnosticsLine(root: URL, report: ScanDiagnostics) -> String {
        var parts: [String] = ["目录：\(root.lastPathComponent)", report.summary]
        if let err = report.readError { parts.append("错误：\(err)") }
        if usingAppDocuments { parts.append("来源：App 文档目录（无需授权）") }
        return parts.joined(separator: " · ")
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
