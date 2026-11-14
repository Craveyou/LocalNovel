import SwiftUI
import Foundation

// MARK: - 书库状态
// 交互模型：零交互主路径（App 文档目录，启动/前台自动扫描） + 唯一一个文件选择器作为备用。
// 不再依赖「系统选择器一定回调」这一脆弱假设：用户把书放进「文件」App → 我的 iPhone →
// 本地小说 后，切回 App 即自动出现，全程无需点任何按钮、无需授权。

/// 唯一的导入通道类型。视图里只挂一个 .fileImporter，
/// 由 activeImport 决定 allowedContentTypes，避免多个 importer 叠加导致都不弹出。
enum ImportMode: String {
    case folder
    case file
    var label: String {
        switch self {
        case .folder: return "选择书库目录"
        case .file:   return "选择书库内任意文件"
        }
    }
}

final class LibraryStore: ObservableObject {
    @Published private(set) var library: Library?
    @Published private(set) var errorMessage: String?
    /// 扫描诊断（成功或失败都显示）
    @Published private(set) var diagnostics: String?
    /// 醒目状态标题：显示在书库主体，替代底部极小的灰字
    @Published private(set) var headline: String?
    /// 当前载入方式：true = 读 App 文档目录（零权限），false = 用户选的外部目录
    @Published private(set) var usingAppDocuments = false
    /// 全工程唯一一个 fileImporter 的驱动状态
    @Published var activeImport: ImportMode? = nil

    private var contentCache: [String: ChapterContent] = [:]
    private var textCache: [String: String] = [:]
    private let animatedDetector: (URL) -> Bool

    init(animatedDetector: @escaping (URL) -> Bool = FrameDetector.isAnimated) {
        self.animatedDetector = animatedDetector
    }

    // MARK: - 零交互主路径

    /// 启动恢复：优先读 App 文档目录（零权限、零交互），没书再尝试上次选中的外部目录。
    /// 任何一步失败都不 return 死锁、不吞掉诊断。
    func restore() {
        let docs = appDocumentsURL()
        var docsReport: ScanDiagnostics?
        if let docs {
            let report = BookScanner.scanWithDiagnostics(
                rootURL: docs,
                cleanTitles: Preferences.shared.cleanTitles
            )
            if !report.library.books.isEmpty {
                usingAppDocuments = true
                invalidateCaches()
                apply(report, root: docs,
                      headline: "已从 App 文档目录载入 \(report.library.books.count) 本书")
                return
            }
            docsReport = report
        }

        if let external = RootFolderAccess.shared.restoreRootFolder() {
            usingAppDocuments = false
            invalidateCaches()
            let report = BookScanner.scanWithDiagnostics(
                rootURL: external,
                cleanTitles: Preferences.shared.cleanTitles
            )
            if !report.library.books.isEmpty {
                apply(report, root: external, headline: "已载入书库")
                return
            }
            applyEmpty(report, docsReport: docsReport)
            return
        }

        applyEmpty(docsReport, docsReport: docsReport)
    }

    /// 每次回到前台：当前没有书时自动补扫 App 文档目录。
    /// 用户在「文件」App 把作者文件夹放进去后，切回 App 书就自动出现，零点击。
    func refreshOnForeground() {
        guard library?.books.isEmpty != false else { return }
        guard let docs = appDocumentsURL() else { return }
        let report = BookScanner.scanWithDiagnostics(
            rootURL: docs,
            cleanTitles: Preferences.shared.cleanTitles
        )
        if !report.library.books.isEmpty {
            usingAppDocuments = true
            invalidateCaches()
            apply(report, root: docs, headline: "已自动载入新放入的书")
        } else {
            applyEmpty(report, docsReport: report)
        }
    }

    /// 点导入按钮的瞬间给【醒目】反馈，且明确给出不依赖选择器的退路。
    func noteImportStarted(_ label: String) {
        headline = "正在打开「\(label)」…"
        errorMessage = nil
        diagnostics = "若没有弹出文件选择器，说明系统选择器在当前环境不可用：请改用「文件」App → 我的 iPhone → 本地小说，把作者文件夹放进去，回到本 App 会自动出现。"
    }

    // MARK: - 备用：唯一的文件选择器

    /// 选择目录（.folder）
    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            applyImportFailure(error)
        case .success(let urls):
            guard let url = urls.first else {
                applyNoSelection()
                return
            }
            let root = RootFolderAccess.shared.saveRootFolder(url)
            usingAppDocuments = false
            invalidateCaches()
            let report = BookScanner.scanWithDiagnostics(
                rootURL: root, cleanTitles: Preferences.shared.cleanTitles)
            apply(report, root: root,
                  headline: report.library.books.isEmpty ? "未识别到书" : "已载入书库")
        }
    }

    /// 选择书库内任意文件（.item），由该文件向上反推书库根
    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            applyImportFailure(error)
        case .success(let urls):
            guard let file = urls.first else {
                applyNoSelection()
                return
            }
            let root = BookScanner.bestRoot(from: file,
                                            cleanTitles: Preferences.shared.cleanTitles)
            let saved = RootFolderAccess.shared.saveRootFolder(root)
            usingAppDocuments = false
            invalidateCaches()
            let report = BookScanner.scanWithDiagnostics(
                rootURL: saved, cleanTitles: Preferences.shared.cleanTitles)
            apply(report, root: saved,
                  headline: report.library.books.isEmpty ? "未识别到书" : "已载入书库")
            if library?.books.isEmpty == true {
                diagnostics = (diagnostics ?? "")
                    + " · 由「\(file.lastPathComponent)」定位到「\(root.lastPathComponent)」但未识别出书，请确认所选文件确实在书库目录内。"
            }
        }
    }

    private func applyImportFailure(_ error: Error) {
        headline = "导入失败"
        errorMessage = "导入失败：\(error.localizedDescription)"
        diagnostics = "可改用零交互方式：把作者文件夹放进「文件」App → 我的 iPhone → 本地小说，回到本 App 会自动出现。"
    }

    private func applyNoSelection() {
        headline = "没有拿到文件/文件夹"
        errorMessage = "系统没有返回所选内容。请直接把作者文件夹放进「文件」App → 我的 iPhone → 本地小说，回到本 App 会自动出现（这条路径不需要文件选择器）。"
        diagnostics = nil
    }

    /// 手动「重新扫描」
    func reload() {
        let root: URL? = usingAppDocuments
            ? appDocumentsURL()
            : (RootFolderAccess.shared.currentRootURL()
               ?? RootFolderAccess.shared.restoreRootFolder())
        guard let url = root else {
            restore()
            return
        }
        invalidateCaches()
        let report = BookScanner.scanWithDiagnostics(
            rootURL: url, cleanTitles: Preferences.shared.cleanTitles)
        apply(report, root: url,
              headline: report.library.books.isEmpty ? "重新扫描完成：没有书" : "重新扫描完成")
    }

    /// 切换到「文件 App → 我的 iPhone → 本地小说」里的书（零权限路径）
    func useAppDocuments() {
        guard let docs = appDocumentsURL() else {
            headline = "无法访问 App 文档目录"
            errorMessage = "请重启 App 再试；或点右上角「＋」用文件选择器导入。"
            return
        }
        usingAppDocuments = true
        invalidateCaches()
        let report = BookScanner.scanWithDiagnostics(
            rootURL: docs, cleanTitles: Preferences.shared.cleanTitles)
        if report.library.books.isEmpty {
            applyEmpty(report, docsReport: report)
            errorMessage = "App 文档目录里还没有书。把作者文件夹放进「文件」App → 我的 iPhone → 本地小说，然后回到本 App（会自动出现）。"
        } else {
            apply(report, root: docs,
                  headline: "已从 App 文档目录载入 \(report.library.books.count) 本书")
        }
    }

    private func appDocumentsURL() -> URL? {
        try? FileManager.default.url(for: .documentDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)
    }

    // MARK: - 结果应用（始终给可见反馈）

    private func apply(_ report: ScanDiagnostics, root: URL, headline: String) {
        self.library = report.library
        var line = buildDiagnosticsLine(root: root, report: report)
        // 书签没存上：本次仍能读，但重启后要重选；明确告知并指向免授权路径
        if !usingAppDocuments && !RootFolderAccess.shared.hasSavedRoot() {
            line += " · 目录权限未能持久化，重启后需重新选择；也可改用「App 文档目录里的书（免授权）」"
        }
        self.diagnostics = line
        self.errorMessage = report.library.books.isEmpty ? report.failureHint : nil
        self.headline = headline
    }

    private func applyEmpty(_ report: ScanDiagnostics?, docsReport: ScanDiagnostics?) {
        let docs = appDocumentsURL()
        var line = "目录：\(docs?.lastPathComponent ?? "本地小说")"
        if let r = report { line += " · \(r.summary)" }
        if let err = report?.readError { line += " · 错误：\(err)" }
        self.library = Library(rootURL: docs ?? URL(fileURLWithPath: NSHomeDirectory()),
                               books: [])
        self.diagnostics = line
        self.headline = "书库为空"
        self.errorMessage = "把【作者文件夹】放进「文件」App → 我的 iPhone → 本地小说，然后回到本 App（会自动出现，无需点按钮）。也可点右上角「＋」用文件选择器导入。"
        self.usingAppDocuments = false
        _ = docsReport
    }

    private func buildDiagnosticsLine(root: URL, report: ScanDiagnostics) -> String {
        var parts: [String] = ["目录：\(root.lastPathComponent)", report.summary]
        if let err = report.readError { parts.append("错误：\(err)") }
        if usingAppDocuments { parts.append("来源：App 文档目录（无需授权）") }
        return parts.joined(separator: " · ")
    }

    // MARK: - 章节内容（带缓存）

    func content(for chapter: Chapter) -> ChapterContent {
        if let cached = contentCache[chapter.id] { return cached }
        let value = MediaResolver.resolveChapter(chapter, animatedDetector: animatedDetector)
        contentCache[chapter.id] = value
        return value
    }

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
