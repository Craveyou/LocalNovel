import SwiftUI
import Foundation

// MARK: - 书库状态
// 主路径：书放在 App 文档目录（「文件」App → 我的 iPhone → 本地小说），零权限、零交互自动扫描。
// 导入按钮：把用户在文件选择器里选中的书【复制】进该目录，之后走同一条稳定路径。
// 不再依赖临时授权 URL 的跨会话持久化。

/// 导入通道类型。仍保留两种模式，只用于给用户不同的操作提示；
/// 视图里始终只有【唯一一个】fileImporter，避免多个弹层叠加导致都不弹出。
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
    /// 扫描 / 导入诊断（成功或失败都显示）
    @Published private(set) var diagnostics: String?
    /// 醒目状态标题：显示在书库主体，替代底部极小的灰字
    @Published private(set) var headline: String?
    /// 当前载入方式：true = 读 App 文档目录（零权限）
    @Published private(set) var usingAppDocuments = false
    /// 导入进行中的可见反馈
    @Published private(set) var importProgress: String?
    /// 全工程唯一一个 fileImporter 的驱动状态
    @Published var activeImport: ImportMode? = nil

    private var contentCache: [String: ChapterContent] = [:]
    private var textCache: [String: String] = [:]
    private var paragraphCache: [String: [String]] = [:]
    private let animatedDetector: (URL) -> Bool

    init(animatedDetector: @escaping (URL) -> Bool = FrameDetector.isAnimated) {
        self.animatedDetector = animatedDetector
    }

    var hiddenChapterCount: Int { ProgressStore.shared.hiddenChapterCount }

    // MARK: - 零交互主路径

    /// 启动恢复：优先读 App 文档目录；没书再尝试上次选中的外部目录（兼容旧版本数据）。
    func restore() {
        let docs = appDocumentsURL()
        var docsReport: ScanDiagnostics?
        if let docs {
            let report = BookScanner.scanWithDiagnostics(
                rootURL: docs, cleanTitles: Preferences.shared.cleanTitles)
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
                rootURL: external, cleanTitles: Preferences.shared.cleanTitles)
            if !report.library.books.isEmpty {
                apply(report, root: external, headline: "已载入书库")
                return
            }
            applyEmpty(report, docsReport: docsReport)
            return
        }
        applyEmpty(docsReport, docsReport: docsReport)
    }

    /// 每次回到前台：补写说明文件（保证「文件」App 里目录可见），书库为空时自动补扫。
    func refreshOnForeground() {
        DocumentsBootstrap.ensureVisibleInFilesApp()
        ProgressStore.shared.flushAnchors()
        guard library?.books.isEmpty != false else { return }
        guard let docs = appDocumentsURL() else { return }
        let report = BookScanner.scanWithDiagnostics(
            rootURL: docs, cleanTitles: Preferences.shared.cleanTitles)
        if !report.library.books.isEmpty {
            usingAppDocuments = true
            invalidateCaches()
            apply(report, root: docs, headline: "已自动载入新放入的书")
        } else {
            applyEmpty(report, docsReport: report)
        }
    }

    /// 点导入按钮的瞬间给【醒目】反馈
    func noteImportStarted(_ label: String) {
        headline = "正在打开「\(label)」…"
        errorMessage = nil
        diagnostics = "在文件选择器里：进入文件夹后请点右上角「打开」确认选择；"
            + "或直接点书里任意一个 txt / 图片文件，会立即开始导入。"
            + "导入会把书复制进「本地小说」，之后重启也能读。"
    }

    // MARK: - 导入：复制进 App 文档目录

    func handleImport(_ result: Result<[URL], Error>) { performImport(result) }
    func handleFileImport(_ result: Result<[URL], Error>) { performImport(result) }

    private func performImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            applyImportFailure(error)
        case .success(let urls):
            guard let picked = urls.first else { applyNoSelection(); return }
            guard let docs = appDocumentsURL() else {
                headline = "无法访问 App 文档目录"
                errorMessage = "请重启 App 再试；或直接在「文件」App → 我的 iPhone → 本地小说 里放书。"
                return
            }
            let clean = Preferences.shared.cleanTitles
            // 选文件时在授权作用域内反推书库根；选文件夹则直接用
            let source: URL = {
                if picked.hasDirectoryPath { return picked }
                let accessing = picked.startAccessingSecurityScopedResource()
                defer { if accessing { picked.stopAccessingSecurityScopedResource() } }
                return BookScanner.bestRoot(from: picked, cleanTitles: clean)
            }()

            headline = "正在导入到「本地小说」…"
            errorMessage = nil
            importProgress = "正在复制《\(source.lastPathComponent)》…（大文件可能需要一点时间）"
            diagnostics = "复制完成后会自动重新扫描；书会保存在 App 内，占用一份额外空间。"

            DispatchQueue.global(qos: .userInitiated).async {
                let report = BookImporter.importIntoDocuments(from: source, documents: docs)
                DispatchQueue.main.async {
                    self.importProgress = nil
                    guard !report.imported.isEmpty else {
                        self.headline = "导入未完成"
                        self.errorMessage = report.error ?? "没有内容被导入。"
                        self.diagnostics = "最稳妥的做法：把【作者文件夹】整个放进「文件」App → 我的 iPhone → 本地小说，回到本 App 会自动出现。"
                        return
                    }
                    self.usingAppDocuments = true
                    self.invalidateCaches()
                    let scan = BookScanner.scanWithDiagnostics(rootURL: docs, cleanTitles: clean)
                    self.apply(scan, root: docs,
                               headline: "已导入 \(report.imported.count) 项，书库共 \(scan.library.books.count) 本书")
                    self.diagnostics = (self.diagnostics ?? "")
                        + " · " + report.summary + " · 已存入 App 内，重启后仍可阅读"
                }
            }
        }
    }

    private func applyImportFailure(_ error: Error) {
        headline = "导入失败"
        errorMessage = "导入失败：\(error.localizedDescription)"
        diagnostics = "可把作者文件夹直接放进「文件」App → 我的 iPhone → 本地小说，回到本 App 会自动出现。"
    }

    private func applyNoSelection() {
        headline = "没有拿到所选内容"
        errorMessage = "系统没有返回所选内容。进入文件夹后请点右上角「打开」，或直接点书里任意一个 txt 文件。"
        diagnostics = "若在「文件」App 看不到目录，可在顶部搜索框搜索「本地小说」；把作者文件夹放进去后回到本 App 会自动出现。"
    }

    // MARK: - 重新扫描 / 切换书库

    func reload() {
        let root: URL? = usingAppDocuments
            ? appDocumentsURL()
            : (RootFolderAccess.shared.currentRootURL()
               ?? RootFolderAccess.shared.restoreRootFolder())
        guard let url = root else { restore(); return }
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
            errorMessage = "请重启 App 再试；或点右上角「＋」导入。"
            return
        }
        usingAppDocuments = true
        invalidateCaches()
        let report = BookScanner.scanWithDiagnostics(
            rootURL: docs, cleanTitles: Preferences.shared.cleanTitles)
        if report.library.books.isEmpty {
            applyEmpty(report, docsReport: report)
            errorMessage = "App 文档目录里还没有书。把作者文件夹放进「文件」App → 我的 iPhone → 本地小说，回到本 App 会自动出现。"
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

    // MARK: - 删除章节 / 书籍

    /// 删除章节：能删就删源文件夹；只读目录删不掉时改为隐藏（可在设置里恢复）。
    /// 返回可直接展示的结果文案。
    @discardableResult
    func deleteChapter(_ chapter: Chapter) -> String {
        invalidateCaches()
        var removed = false
        do {
            try FileManager.default.removeItem(at: chapter.folderURL)
            removed = true
        } catch {
            ProgressStore.shared.hideChapter(chapter.id)
        }
        ProgressStore.shared.clearProgress(for: chapter.id)
        reload()
        let message = removed
            ? "《\(chapter.title)》的文件夹已删除，不可恢复。"
            : "源文件无法删除（目录只读），《\(chapter.title)》已从书库隐藏；可在「阅读设置 → 书库」里恢复。"
        headline = "章节已删除"
        diagnostics = message
        errorMessage = nil
        return message
    }

    /// 批量删除：一次重扫，避免逐章 reload 反复全量扫描整个书库。
    /// 能删源文件夹就删；只读外部目录删不掉时逐章改为隐藏。
    @discardableResult
    func deleteChapters(_ chapters: [Chapter]) -> String {
        guard !chapters.isEmpty else { return "没有选中任何章节。" }
        invalidateCaches()
        var deleted = 0
        var hidden = 0
        for chapter in chapters {
            do {
                try FileManager.default.removeItem(at: chapter.folderURL)
                deleted += 1
            } catch {
                ProgressStore.shared.hideChapter(chapter.id)
                hidden += 1
            }
            ProgressStore.shared.clearProgress(for: chapter.id)
        }
        reload()
        var parts: [String] = []
        if deleted > 0 {
            parts.append("已删除 \(deleted) 个章节（源文件夹已移除，不可恢复）")
        }
        if hidden > 0 {
            parts.append("\(hidden) 个章节因目录只读改为隐藏（可在「设置 → 书库」恢复）")
        }
        let message = parts.joined(separator: "；") + "。"
        headline = "已删除 \(chapters.count) 章"
        diagnostics = message
        errorMessage = nil
        return message
    }

    @discardableResult
    func deleteBook(_ book: Book) -> String {        invalidateCaches()
        var removed = false
        do {
            try FileManager.default.removeItem(at: book.folderURL)
            removed = true
        } catch {
            book.chapters.forEach { ProgressStore.shared.hideChapter($0.id) }
        }
        book.chapters.forEach { ProgressStore.shared.clearProgress(for: $0.id) }
        ProgressStore.shared.clearLastChapter(for: book.id)
        reload()
        let message = removed
            ? "《\(book.title)》的文件夹已删除，不可恢复。"
            : "源文件无法删除（目录只读），《\(book.title)》已从书库隐藏；可在「阅读设置 → 书库」里恢复。"
        headline = "书籍已删除"
        diagnostics = message
        errorMessage = nil
        return message
    }

    func restoreHiddenChapters() {
        ProgressStore.shared.unhideAllChapters()
        reload()
        headline = "已恢复隐藏的章节"
        diagnostics = "隐藏记录已清空，重新扫描完成。"
        errorMessage = nil
    }

    // MARK: - 结果应用（始终给可见反馈）

    private func apply(_ report: ScanDiagnostics, root: URL, headline: String) {
        let hidden = ProgressStore.shared.hiddenChapterIds()
        let books: [Book] = report.library.books.compactMap { book in
            let chapters = book.chapters.filter { !hidden.contains($0.id) }
            guard !chapters.isEmpty else { return nil }
            return Book(folderURL: book.folderURL, title: book.title, chapters: chapters)
        }
        self.library = Library(rootURL: report.library.rootURL, books: books)
        var line = buildDiagnosticsLine(root: root, report: report)
        if !hidden.isEmpty { line += " · 已隐藏 \(hidden.count) 个章节" }
        self.diagnostics = line
        self.errorMessage = books.isEmpty
            ? (report.failureHint ?? "书库里没有可显示的章节，可在「阅读设置 → 书库」里恢复隐藏的章节。")
            : nil
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
        self.errorMessage = "把【作者文件夹】放进「文件」App → 我的 iPhone → 本地小说，回到本 App 会自动出现；或点右上角「＋」把书导入进来。"
        self.usingAppDocuments = false
        _ = docsReport
    }

    private func buildDiagnosticsLine(root: URL, report: ScanDiagnostics) -> String {
        var parts: [String] = ["目录：\(root.lastPathComponent)", report.summary]
        if let err = report.readError { parts.append("错误：\(err)") }
        if usingAppDocuments { parts.append("来源：App 文档目录（无需授权）") }
        return parts.joined(separator: " · ")
    }

    // MARK: - 章节内容（全部带缓存，同步取值，无异步状态机）

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

    /// 段落切分结果也缓存：阅读器 body 重算时不再重复处理整本正文
    func paragraphs(for chapter: Chapter) -> [String] {
        if let cached = paragraphCache[chapter.id] { return cached }
        let value = TextLoader.paragraphs(text(for: chapter))
        paragraphCache[chapter.id] = value
        return value
    }

    func ignoredHint(for chapter: Chapter) -> String? {
        let ignored = content(for: chapter).ignoredFiles
        guard !ignored.isEmpty else { return nil }
        return "已忽略 \(ignored.count) 个未识别文件：\(ignored.prefix(3).joined(separator: "、"))"
    }

    private func invalidateCaches() {
        contentCache.removeAll()
        textCache.removeAll()
        paragraphCache.removeAll()
    }
}
