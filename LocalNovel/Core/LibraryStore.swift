import SwiftUI
import Foundation

// MARK: - 书库状态
// 主路径：书放在 App 文档目录（「文件」App → 我的 iPhone → 本地小说），零权限、零交互自动扫描。
// 三个固定分区：小说 / 漫画 / 整理 —— 分类由目录决定，用户在「文件」App 里怎么整理就怎么显示。
// 导入按钮：把选中的内容【复制】进对应分区，之后走同一条稳定路径。

/// 导入通道类型。仍保留两种模式，只用于给用户不同的操作提示；
/// 视图里始终只有【唯一一个】fileImporter，避免多个弹层叠加导致都不弹出。
enum ImportMode: String {
    case folder
    case file
    var label: String {
        switch self {
        case .folder: return "选择书籍文件夹"
        case .file:   return "选择书籍文件"
        }
    }
}

final class LibraryStore: ObservableObject {
    @Published private(set) var library: Library?
    @Published private(set) var errorMessage: String?
    /// 扫描 / 导入诊断（成功或失败都显示）
    @Published private(set) var diagnostics: String?
    /// 醒目状态标题：显示在书库主体
    @Published private(set) var headline: String?
    /// 当前载入方式：true = 读 App 文档目录（零权限）
    @Published private(set) var usingAppDocuments = false
    /// 导入进行中的可见反馈
    @Published private(set) var importProgress: String?
    /// 后台扫描中（避免重复触发）
    @Published private(set) var isScanning = false
    /// 全工程唯一一个 fileImporter 的驱动状态
    @Published var activeImport: ImportMode? = nil
    /// 导入目标分区：当前在哪个分区页就导到哪；首页为 nil（按内容自动判断）
    @Published var importTargetSection: BookCategory? = nil
    /// 导入目标系列：当前在系列详情页时，复制进该系列的文件夹（「系列 · 子系列」按层拆开）
    @Published var importTargetSeries: String? = nil

    private var contentCache: [String: ChapterContent] = [:]
    private var textCache: [String: String] = [:]
    private var paragraphCache: [String: [String]] = [:]
    /// 已经切过章的小说：重扫 / 删除章节后不必再解析一次整本正文
    private var splitCache: [String: [Chapter]] = [:]
    /// 正在切章的书，防止 onAppear 反复触发
    private var splittingBooks: Set<String> = []
    /// 扫描进行中又有新的重扫请求（连续删除时）
    private var pendingRescan = false
    private let animatedDetector: (URL) -> Bool

    init(animatedDetector: @escaping (URL) -> Bool = FrameDetector.isAnimated) {
        self.animatedDetector = animatedDetector
    }

    var hiddenChapterCount: Int { ProgressStore.shared.hiddenChapterCount }

    // MARK: - 零交互主路径

    /// 启动恢复：优先读 App 文档目录；没有分区再尝试上次选中的外部目录（兼容旧版本数据）。
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
                      headline: "已从 App 文档目录载入 \(report.library.books.count) 本")
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

    /// 每次回到前台：补写说明文件 + 后台重扫，文件 App 里刚整理的结构立刻生效。
    func refreshOnForeground() {
        DocumentsBootstrap.ensureVisibleInFilesApp()
        ProgressStore.shared.flushAnchors()
        rescan(headline: "已同步「文件」App 里的改动")
    }

    /// 点导入按钮的瞬间给【醒目】反馈
    func noteImportStarted(_ label: String) {
        headline = "正在打开「\(label)」…"
        errorMessage = nil
        diagnostics = "在文件选择器里：进入文件夹后请点右上角「打开」确认选择；"
            + "或直接点书里任意一个文件，会立即开始导入。"
            + "导入会复制进「本地小说」对应分区，之后重启也能读。"
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
            // 直接导入所选内容：不再反推「书库根」，避免把一个分区整批重复复制一遍
            let source = picked
            let target = importTargetSection
            let targetSeries = importTargetSeries

            headline = "正在导入…"
            errorMessage = nil
            importProgress = "正在复制《\(source.lastPathComponent)》…（大文件可能需要一点时间）"
            diagnostics = "复制完成后会自动重新扫描；书会保存在 App 内，占用一份额外空间。"

            DispatchQueue.global(qos: .userInitiated).async {
                let report = BookImporter.importIntoDocuments(from: source, documents: docs,
                                                              preferred: target,
                                                              preferredSeries: targetSeries)
                DispatchQueue.main.async {
                    self.importProgress = nil
                    guard !report.imported.isEmpty else {
                        self.headline = "导入未完成"
                        self.errorMessage = report.error ?? "没有内容被导入。"
                        self.diagnostics = "最稳妥的做法：把书直接放进「文件」App → 我的 iPhone → 本地小说 → 小说 / 漫画 / 整理，回到本 App 会自动出现。"
                        return
                    }
                    self.usingAppDocuments = true
                    self.invalidateCaches()
                    let scan = BookScanner.scanWithDiagnostics(rootURL: docs, cleanTitles: clean)
                    self.apply(scan, root: docs,
                               headline: "已导入 \(report.imported.count) 项，书库共 \(scan.library.books.count) 本")
                    self.diagnostics = (self.diagnostics ?? "")
                        + " · " + report.summary
                        + (targetSeries.map { "（系列：\($0)）" } ?? "")
                        + " · 已存入 App 内，重启后仍可阅读"
                }
            }
        }
    }

    private func applyImportFailure(_ error: Error) {
        headline = "导入失败"
        errorMessage = "导入失败：\(error.localizedDescription)"
        diagnostics = "可把书直接放进「文件」App → 我的 iPhone → 本地小说 的对应分区，回到本 App 会自动出现。"
    }

    private func applyNoSelection() {
        headline = "没有拿到所选内容"
        errorMessage = "系统没有返回所选内容。进入文件夹后请点右上角「打开」，或直接点书里任意一个文件。"
        diagnostics = "若在「文件」App 看不到目录，可在顶部搜索框搜索「本地小说」；把书放进去后回到本 App 会自动出现。"
    }

    // MARK: - 重新扫描

    func reload() {
        rescan(headline: "重新扫描完成")
    }

    private func currentRoot() -> URL? {
        if usingAppDocuments { return appDocumentsURL() }
        if let external = RootFolderAccess.shared.currentRootURL()
            ?? RootFolderAccess.shared.restoreRootFolder() {
            return external
        }
        return appDocumentsURL()
    }

    /// 后台扫描：漫画目录可能很深，主线程扫描会卡住列表滚动
    private func rescan(headline: String, completion: (() -> Void)? = nil) {
        guard let url = currentRoot() else { restore(); return }
        if isScanning {
            pendingRescan = true
            return
        }
        isScanning = true
        let clean = Preferences.shared.cleanTitles
        DispatchQueue.global(qos: .userInitiated).async {
            let report = BookScanner.scanWithDiagnostics(rootURL: url, cleanTitles: clean)
            DispatchQueue.main.async {
                self.isScanning = false
                self.apply(report, root: url, headline: headline)
                completion?()
                if self.pendingRescan {
                    self.pendingRescan = false
                    self.rescan(headline: headline)
                }
            }
        }
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
            errorMessage = "App 文档目录里还没有书。把文件放进「小说 / 漫画 / 整理」，回到本 App 会自动出现。"
        } else {
            apply(report, root: docs,
                  headline: "已从 App 文档目录载入 \(report.library.books.count) 本")
        }
    }

    private func appDocumentsURL() -> URL? {
        try? FileManager.default.url(for: .documentDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true)
    }

    // MARK: - 小说分章（首次打开时解析正文）

    /// 小说区的书扫描时只给一章占位；进入该书时在后台按「第X章」切分。
    func ensureChapters(for book: Book) {
        guard book.chaptersDeferred, book.category == .novel else { return }
        guard !splittingBooks.contains(book.id) else { return }
        if splitCache[book.id] != nil { return }
        splittingBooks.insert(book.id)
        let clean = Preferences.shared.cleanTitles
        let fileURL = book.folderURL
        DispatchQueue.global(qos: .userInitiated).async {
            let chapters = BookScanner.makeSliceChapters(fileURL: fileURL, cleanTitles: clean)
            DispatchQueue.main.async {
                self.splittingBooks.remove(book.id)
                guard !chapters.isEmpty else { return }
                self.splitCache[book.id] = chapters
                self.applySplit(bookId: book.id, chapters: chapters)
            }
        }
    }

    /// 这本书的分章是否还在准备中（用于目录列表显示进度）
    func isSplitting(_ book: Book) -> Bool {
        book.chaptersDeferred && splitCache[book.id] == nil
    }

    private func applySplit(bookId: String, chapters: [Chapter]) {
        guard let lib = library else { return }
        let hidden = ProgressStore.shared.hiddenChapterIds()
        let visible = chapters.filter { !hidden.contains($0.id) }
        guard !visible.isEmpty else { return }
        let books = lib.books.map { book -> Book in
            guard book.id == bookId else { return book }
            return Book(folderURL: book.folderURL,
                        title: book.title,
                        category: book.category,
                        chapters: visible,
                        chaptersDeferred: false,
                        series: book.series)
        }
        library = Library(rootURL: lib.rootURL, books: books)
        invalidateCaches()
    }

    // MARK: - 删除章节 / 书籍

    /// 删除章节：能删就删源文件；整本小说的切片、只读目录改为隐藏（可在设置里恢复）。
    @discardableResult
    func deleteChapter(_ chapter: Chapter) -> String {
        invalidateCaches()
        var removed = false
        if chapter.canDeleteFromDisk {
            do {
                try FileManager.default.removeItem(at: chapter.folderURL)
                removed = true
            } catch {
                removed = false
            }
        }
        if !removed { ProgressStore.shared.hideChapter(chapter.id) }
        ProgressStore.shared.clearProgress(for: chapter.id)
        let message: String
        if removed {
            message = "《\(chapter.displayTitle)》的源文件已删除，不可恢复。"
        } else if !chapter.canDeleteFromDisk {
            message = "《\(chapter.displayTitle)》是整本文件里的一章，已隐藏；可在「设置 → 书库」里恢复。"
        } else {
            message = "源文件无法删除（目录只读），《\(chapter.displayTitle)》已从书库隐藏；可在「设置 → 书库」里恢复。"
        }
        rescan(headline: "章节已删除") { [weak self] in
            self?.diagnostics = message
            self?.errorMessage = nil
            self?.headline = "章节已删除"
        }
        return message
    }

    /// 批量删除：一次重扫，避免逐章 reload 反复全量扫描整个书库。
    @discardableResult
    func deleteChapters(_ chapters: [Chapter]) -> String {
        guard !chapters.isEmpty else { return "没有选中任何章节。" }
        invalidateCaches()
        var deleted = 0
        var hidden = 0
        for chapter in chapters {
            var removed = false
            if chapter.canDeleteFromDisk {
                do {
                    try FileManager.default.removeItem(at: chapter.folderURL)
                    removed = true
                } catch {
                    removed = false
                }
            }
            if removed { deleted += 1 } else {
                ProgressStore.shared.hideChapter(chapter.id)
                hidden += 1
            }
            ProgressStore.shared.clearProgress(for: chapter.id)
        }
        var parts: [String] = []
        if deleted > 0 { parts.append("已删除 \(deleted) 章（源文件已移除，不可恢复）") }
        if hidden > 0 { parts.append("\(hidden) 章改为隐藏（整本切片或目录只读，可在「设置 → 书库」恢复）") }
        let message = parts.joined(separator: "；") + "。"
        rescan(headline: "已删除 \(chapters.count) 章") { [weak self] in
            self?.diagnostics = message
            self?.errorMessage = nil
            self?.headline = "已删除 \(chapters.count) 章"
        }
        return message
    }

    @discardableResult
    func deleteBook(_ book: Book) -> String {
        invalidateCaches()
        splitCache.removeValue(forKey: book.id)
        var removed = false
        do {
            try FileManager.default.removeItem(at: book.folderURL)
            removed = true
        } catch {
            removed = false
            book.chapters.forEach { ProgressStore.shared.hideChapter($0.id) }
        }
        book.chapters.forEach { ProgressStore.shared.clearProgress(for: $0.id) }
        ProgressStore.shared.clearLastChapter(for: book.id)
        let message = removed
            ? "《\(book.title)》的源文件已删除，不可恢复。"
            : "源文件无法删除（目录只读），《\(book.title)》已从书库隐藏；可在「设置 → 书库」里恢复。"
        rescan(headline: "书籍已删除") { [weak self] in
            self?.diagnostics = message
            self?.errorMessage = nil
            self?.headline = "书籍已删除"
        }
        return message
    }

    func restoreHiddenChapters() {
        ProgressStore.shared.unhideAllChapters()
        rescan(headline: "已恢复隐藏的章节") { [weak self] in
            self?.diagnostics = "隐藏记录已清空，重新扫描完成。"
            self?.errorMessage = nil
        }
    }

    // MARK: - 结果应用（始终给可见反馈）

    private func apply(_ report: ScanDiagnostics, root: URL, headline: String) {
        let hidden = ProgressStore.shared.hiddenChapterIds()
        var books: [Book] = []
        for book in report.library.books {
            let source = splitCache[book.id] ?? book.chapters
            let chapters = source.filter { !hidden.contains($0.id) }
            guard !chapters.isEmpty else { continue }
            books.append(Book(folderURL: book.folderURL,
                              title: book.title,
                              category: book.category,
                              chapters: chapters,
                              chaptersDeferred: book.chaptersDeferred && splitCache[book.id] == nil,
                              series: book.series))
        }
        self.library = Library(rootURL: report.library.rootURL, books: books)
        var line = buildDiagnosticsLine(root: root, report: report)
        if !hidden.isEmpty { line += " · 已隐藏 \(hidden.count) 章" }
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
        self.errorMessage = "在「文件」App → 我的 iPhone → 本地小说 里建三个文件夹：小说 / 漫画 / 整理，把书放进去，回到本 App 自动出现。"
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
        let value = loadText(for: chapter)
        textCache[chapter.id] = value
        return value
    }

    private func loadText(for chapter: Chapter) -> String {
        // 小说切片：整本读一次（TextLoader 内部缓存），再按区间取
        if chapter.kind == .slice, let range = chapter.range {
            do {
                let full = try TextLoader.loadDocument(chapter.folderURL)
                let part = TextLoader.substring(full, range: range)
                return part.isEmpty ? "（本章没有内容）" : part
            } catch {
                return "（\(error.localizedDescription)）"
            }
        }
        guard let url = content(for: chapter).textURL else {
            // 纯媒体章节（短剧某一集视频、单张剧照）本来就没有正文，
            // 返回空串让阅读器只渲染媒体，不再塞一句「没有正文文件」。
            return ""
        }
        do {
            if chapter.kind == .folder {
                return try TextLoader.load(url)
            }
            return try TextLoader.loadDocument(url)
        } catch {
            return "（\(error.localizedDescription)）"
        }
    }

    /// 段落切分结果也缓存：阅读器 body 重算时不再重复处理整本正文
    func paragraphs(for chapter: Chapter) -> [String] {
        if let cached = paragraphCache[chapter.id] { return cached }
        let value = TextLoader.paragraphs(text(for: chapter))
        paragraphCache[chapter.id] = value
        return value
    }

    // MARK: - 分区

    func books(in category: BookCategory) -> [Book] {
        library?.books(in: category) ?? []
    }

    func count(in category: BookCategory) -> Int {
        library?.count(in: category) ?? 0
    }

    func seriesNames(in category: BookCategory) -> [String] {
        library?.seriesNames(in: category) ?? []
    }

    func books(in category: BookCategory, series: String?) -> [Book] {
        library?.books(in: category, series: series) ?? []
    }

    func count(in category: BookCategory, series: String?) -> Int {
        library?.count(in: category, series: series) ?? 0
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
