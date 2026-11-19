import AppleShared
import Foundation
import Observation
import PDFKit

private struct OpenedDocument: @unchecked Sendable {
    let pdf: PDFDocument?
    let epub: EPUBDocument?
    let comic: ComicDocument?
    var kindle: KindleDocument? = nil
}

@MainActor @Observable
final class DocumentReaderModel {
    struct Command: Equatable {
        let id = UUID()
        let locator: DocumentLocator
        var highlight: NSRange?
    }
    let book: Book
    let store: LibraryStore
    let sync: ProgressSyncCoordinator
    private(set) var pdf: PDFDocument?
    private(set) var epub: EPUBDocument?
    private(set) var kindle: KindleDocument?
    private(set) var reflowDocument: ReflowDocument?
    private(set) var comic: ComicDocument?
    private(set) var formal: DocumentLocator?
    private(set) var current: DocumentLocator?
    private(set) var readAt: Date
    private(set) var command: Command?
    private var renderedCommandID: UUID?
    private(set) var loading = true
    private(set) var rendering = false
    private(set) var openFailure: String?
    private(set) var preparingSync = false
    private(set) var ready = false
    private(set) var temporary = false
    private(set) var syncMessage = "未开启同步，可继续本地阅读"
    private(set) var bookmarks: [DocumentBookmark] = []
    private(set) var hits: [DocumentSearchHit] = []
    private(set) var searching = false
    private(set) var searchExhausted = false
    private(set) var searchWrapped = false
    var searchCanWrap: Bool { searchExhausted && !searchWrapped && searchHasPrefix }
    private var searchHasPrefix = false
    private var originalPDFBoxes: [Int: CGRect] = [:]
    var query = ""
    var error: String?
    var needsPassword = false
    var passwordError = false
    var remote: DocumentRemoteState?
    var selection = ""
    private let cropState: PDFCropState
    var pdfCrop: PDFCropSettings { cropState.settings }
    private var key: SyncBookKey?
    private var active = true
    private var generation = UUID()
    private var navigationGeneration = UUID()
    private var busy = false
    private var deleting = false
    private var uploadPaused = false
    private var promptedVersion: String?
    private var timer: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchCursor: DocumentTextSearch?
    private var searchGeneration = UUID()
    private var searchQuery: String?
    private var closed = false
    private var openGeneration = UUID()
    private var openingTask: Task<OpenedDocument, Error>?
    private var pendingNavigation: (locator: DocumentLocator, readAt: Date, completion: (@MainActor () -> Void)?)?

    init(book: Book, store: LibraryStore, sync: ProgressSyncCoordinator, cropState: PDFCropState = PDFCropState()) {
        self.book = book; self.store = store; self.sync = sync; readAt = book.updatedAt
        self.cropState = cropState
    }
    func open() async {
        guard !closed else { return }
        let request = UUID(); openGeneration = request
        openingTask?.cancel()
        generation = UUID(); navigationGeneration = UUID(); pendingNavigation = nil
        cancelSearch(); timer?.cancel(); timer = nil; remote = nil; temporary = false; selection = ""
        loading = true; ready = false; command = nil; renderedCommandID = nil; openFailure = nil; error = nil
        originalPDFBoxes.removeAll()
        do {
            let url = await store.url(for: book)
            let format = book.format
            let opening = Task.detached(priority: .userInitiated) {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                let isComic = ["cbz", "cbr"].contains(format)
                guard size <= (isComic || format == "kindle" ? 1024 : 256) * 1024 * 1024 else { throw DocumentError.unsupported("文档超过支持的大小限制") }
                if format == "pdf" {
                    guard let document = PDFDocument(url: url) else { throw DocumentError.unsupported("PDF 无法打开") }
                    return OpenedDocument(pdf: document, epub: nil, comic: nil)
                }
                if format == "epub" { return OpenedDocument(pdf: nil, epub: try EPUBDocument(url: url), comic: nil) }
                if format == "kindle" { return OpenedDocument(pdf: nil, epub: nil, comic: nil, kindle: try KindleDocument(url: url)) }
                if isComic { return OpenedDocument(pdf: nil, epub: nil, comic: try ComicDocument(url: url)) }
                throw DocumentError.unsupported("此文档格式暂不支持")
            }
            openingTask = opening
            let opened = try await withTaskCancellationHandler { try await opening.value } onCancel: { opening.cancel() }
            guard !closed, request == openGeneration, !Task.isCancelled else { return }
            openingTask = nil
            pdf = opened.pdf; epub = opened.epub; comic = opened.comic
            kindle = opened.kindle
            reflowDocument = opened.epub.map(ReflowDocument.init) ?? opened.kindle.map(ReflowDocument.init)
            if pdf?.isLocked == true { needsPassword = true; loading = false; return }
            try await prepare()
        } catch {
            guard !closed, request == openGeneration else { return }
            loading = false; openFailure = error.localizedDescription
        }
    }
    func unlock(_ password: String) async {
        guard let pdf, pdf.isLocked else { return }
        guard pdf.unlock(withPassword: password) else { passwordError = true; needsPassword = true; return }
        passwordError = false; needsPassword = false; loading = true
        do { try await prepare() } catch { loading = false; openFailure = error.localizedDescription }
    }
    private func prepare() async throws {
        if let pdf { guard (1...100_000).contains(pdf.pageCount) else { throw DocumentError.unsupported("PDF 页数超过支持范围") } }
        key = try await store.documentIdentity(book: book)
        let saved = try await store.documentPosition(bookID: book.id)
        guard !closed else { return }
        if let saved {
            guard saved.hash == key?.bookHash, valid(saved.locator) else { throw DocumentError.invalidPosition }
            formal = saved.locator; readAt = saved.readAt
        } else {
            formal = pdf.map { .pdf(page:0,pageCount:$0.pageCount,y:0) } ?? reflowDocument?.locator(chapter:0,offset:0)
            if let comic { formal = try comic.manifest.locator(format: comic.format, page: 0) }
            readAt = Date(timeIntervalSince1970:0)
        }
        current = formal
        command = formal.map { Command(locator:$0) }
        bookmarks = try await store.documentBookmarks(bookID:book.id)
        loading = false
        // Renderer must acknowledge a successful restore before comparison or uploads.
    }
    func valid(_ locator: DocumentLocator) -> Bool {
        guard (try? locator.validated()) != nil else { return false }
        switch locator {
        case .pdf(_, let n, _): return pdf?.isLocked == false && pdf?.pageCount == n
        case .epub: return epub?.valid(locator) == true
        case .kindle: return kindle?.valid(locator) == true
        case .comic: return comic?.manifest.valid(locator, format: book.format) == true
        }
    }
    var canNavigate: Bool { ready && !preparingSync && remote == nil && !loading && openFailure == nil }
    var count: Int { pdf?.pageCount ?? reflowDocument?.chapters.count ?? comic?.manifest.pages.count ?? 0 }
    var currentUnit: Int { current.flatMap { reflowDocument?.chapterIndex(for: $0) ?? $0.unit } ?? 0 }
    var textNotice: String? {
        if comic != nil { return "图片漫画暂不支持正文搜索/复制" }
        guard let pdf, let position = current else { return nil }
        if !pdf.allowsCopying { return "此 PDF 不允许提取文本，仍可阅读、书签和同步" }
        if (pdf.page(at: position.unit)?.string ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return "本页没有可提取文本，仍可阅读、书签和同步；不执行 OCR" }
        return nil
    }
    func rendererCompleted(_ id: UUID, success: Bool) {
        guard command?.id == id, !closed else { return }
        rendering = false
        if !success {
            renderedCommandID = nil
            pendingNavigation = nil; remote = nil; preparingSync = false; current = formal
            ready = false; openFailure = "正文位置无法映射，原阅读进度已保留"
            return
        }
        renderedCommandID = id
        let wasReady = ready; ready = true
        if let pending = pendingNavigation {
            pendingNavigation = nil
            let navigation = navigationGeneration
            Task {
                guard let key else { return }
                do {
                    try await store.saveDocumentPosition(bookID:book.id,hash:key.bookHash,locator:pending.locator,readAt:pending.readAt)
                    guard !closed, navigation == navigationGeneration else { return }
                    formal = pending.locator; current = pending.locator; readAt = pending.readAt
                    pending.completion?()
                    await compare()
                } catch { self.error = error.localizedDescription }
            }
        } else if !wasReady, active { startTimer(); Task { await compare() } }
    }
    func rendererStarted(_ id: UUID) {
        guard command?.id == id, !closed else { return }
        rendering = true
    }
    func navigate(_ locator: DocumentLocator, preview: Bool = false, highlight: NSRange? = nil, remoteTime: Date? = nil, completion: (@MainActor () -> Void)? = nil) {
        guard ready, active, valid(locator), remoteTime != nil || canNavigate else { return }
        selection = ""; navigationGeneration = UUID()
        if preview || temporary && remoteTime == nil {
            temporary = true; current = locator; command = Command(locator:locator,highlight:highlight); return
        }
        if locator == formal, remoteTime == nil {
            if pendingNavigation != nil {
                pendingNavigation = nil; current = locator; command = Command(locator:locator)
            }
            return
        }
        pendingNavigation = (locator, remoteTime ?? FormalReadingProgress.nextDate(.now,after:readAt),completion)
        current = locator; command = Command(locator:locator,highlight:highlight)
    }
    func userScrolled(_ locator: DocumentLocator) {
        guard canNavigate, !rendering, renderedCommandID == command?.id, active, valid(locator), selection.isEmpty else { return }
        current = locator
        guard !temporary, locator != formal, pendingNavigation == nil else { return }
        let time = FormalReadingProgress.nextDate(.now,after:readAt)
        let navigation = navigationGeneration
        Task {
            guard let key else { return }
            do {
                try await store.saveDocumentPosition(bookID:book.id,hash:key.bookHash,locator:locator,readAt:time)
                guard !closed, navigation == navigationGeneration else { return }
                formal = locator; readAt = time
                await compare()
            } catch { self.error = error.localizedDescription }
        }
    }
    func moveUnit(_ delta: Int) {
        guard let current else { return }
        let unit = (reflowDocument?.chapterIndex(for: current) ?? current.unit) + delta
        guard (0..<count).contains(unit) else { return }
        if let pdf { navigate(.pdf(page:unit,pageCount:pdf.pageCount,y:0)) }
        else if let reflowDocument { navigate(reflowDocument.locator(chapter:unit,offset:0)) }
        else if let comic, let locator = try? comic.manifest.locator(format:comic.format,page:unit) { navigate(locator) }
    }
    func returnToFormal() {
        guard let formal else { return }
        temporary = false; current = formal; selection = ""; navigationGeneration = UUID(); pendingNavigation = nil
        command = Command(locator:formal)
        Task { await compare() }
    }
    func reflow() {
        guard let current, reflowDocument != nil else { return }
        selection = ""; command = Command(locator:current)
    }
    func setPDFCrop(_ value: PDFCropSettings) {
        guard pdf != nil, ready else { return }
        let value = value.normalized()
        guard value != pdfCrop else { return }
        cropState.settings = value; selection = ""
        // Redisplay, never navigate: cropping is not a reading event.
        if let current { command = Command(locator: current) }
    }
    @discardableResult func addBookmark() async -> Bool {
        guard !closed, active, canNavigate, !rendering, let current else { return false }
        do {
            try await store.addDocumentBookmark(bookID:book.id,locator:current,excerpt:description(current))
            bookmarks = try await store.documentBookmarks(bookID:book.id)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func removeBookmark(_ bookmark: DocumentBookmark) async {
        do { try await store.removeDocumentBookmark(id:bookmark.id); bookmarks = try await store.documentBookmarks(bookID:book.id) }
        catch { self.error = error.localizedDescription }
    }
    func description(_ locator: DocumentLocator) -> String {
        switch locator {
        case .pdf(let p, _, _): return "第 \(p + 1) 页 · \(String(format:"%.2f",locator.progress * 100))%"
        case .epub(_, let i, _, let o, _): return "第 \(i + 1) 章 · 字符 \(o) · \(String(format:"%.2f",locator.progress * 100))%"
        case .kindle(_, let o, _): return "第 \((kindle?.chapterIndex(for: locator) ?? 0) + 1) 章 · 字符 \(o) · \(String(format:"%.2f",locator.progress * 100))%"
        case .comic(_, _, _, let p, let n, _): return "第 \(p + 1) / \(n) 页 · \(String(format:"%.2f",locator.progress * 100))%"
        }
    }
    /// Cache before display-only cropping changes PDFKit's page boxes.
    func originalPDFBounds(_ page: PDFPage) -> CGRect {
        guard let pdf else { return page.bounds(for: .cropBox) }
        let index = pdf.index(for: page)
        if let box = originalPDFBoxes[index] { return box }
        let box = page.bounds(for: .cropBox)
        originalPDFBoxes[index] = box
        return box
    }

    /// PDFKit text offsets and search ranges are UTF-16. Use the displayed
    /// vertical axis, not the cropped/zoomed viewport, to keep locators stable.
    static func pdfSearchOffset(page: PDFPage, y: Double, original: CGRect) -> Int {
        guard y > 0 else { return 0 }
        let length = min(page.numberOfCharacters, (page.string as NSString?)?.length ?? 0)
        guard y < 1 else { return length }
        let rotation = (page.rotation % 360 + 360) % 360
        for index in 0..<length {
            let rect = page.characterBounds(at: index)
            guard !rect.isEmpty, !rect.isNull else { continue }
            let bottom: Double
            switch rotation {
            case 90: bottom = (rect.maxX - original.minX) / original.width
            case 180: bottom = (rect.maxY - original.minY) / original.height
            case 270: bottom = (original.maxX - rect.minX) / original.width
            default: bottom = (original.maxY - rect.minY) / original.height
            }
            // Include a line intersecting the top edge, but never text above it.
            if bottom > y { return index }
        }
        return length
    }

    func search(reset: Bool = false, wrap: Bool = false, fromBeginning: Bool = false) {
        cancelSearch()
        guard comic == nil else { error = "图片漫画暂不支持正文搜索/复制"; return }
        query = query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard DocumentTextSearch.validQuery(query) else { error = "请输入 2–32 个字素簇"; return }
        guard reflowDocument != nil || pdf?.allowsCopying == true else { error = "此 PDF 不允许搜索或提取文本"; return }
        if reset || searchCursor == nil || searchQuery != query {
            hits = []; searchWrapped = false; searchExhausted = false; searchQuery = query
            var offset = 0
            if let current, let local = reflowDocument?.localOffset(for: current) { offset = local }
            if case .pdf(let index,_,let y) = current, let page = pdf?.page(at:index) {
                offset = Self.pdfSearchOffset(page:page,y:y,original:originalPDFBounds(page))
            }
            let unit = fromBeginning ? 0 : currentUnit
            if fromBeginning { offset = 0 }
            searchHasPrefix = unit > 0 || offset > 0
            searchCursor = DocumentTextSearch(unit:unit,offset:offset)
        }
        if wrap {
            guard searchCanWrap else { return }
            searchCursor?.wrap(); searchWrapped = true
        }
        searching = true; let query = query
        let request = UUID(); searchGeneration = request
        searchTask = Task {
            defer { if searchGeneration == request { searching = false } }
            do {
                guard var cursor = searchCursor else { return }
                var batch:[DocumentSearchHit] = []
                repeat {
                    batch += try cursor.next(query:query,count:count,limit:200-batch.count,unitBudget:4) { i in
                        if let reflowDocument { return reflowDocument.chapters[i].text.replacingOccurrences(of: "\u{fffc}", with: " ") }
                        // PDFKit creates autoreleased layout objects for each extracted page.
                        // Bound them to one unit even when an async scan stays on the main executor.
                        return autoreleasepool { pdf?.page(at:i)?.string ?? "" }
                    }
                    await Task.yield()
                    try Task.checkCancellation()
                } while batch.count < 200 && !cursor.exhausted
                guard searchGeneration == request else { return }
                hits += batch; searchCursor = cursor; searchExhausted = cursor.exhausted
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }

    func cancelSearch() {
        searchGeneration = UUID(); searchTask?.cancel(); searchTask = nil; searching = false
    }

    func showHit(_ hit: DocumentSearchHit) {
        if let reflowDocument { navigate(reflowDocument.locator(chapter:hit.unit,offset:hit.offset),preview:true,highlight:NSRange(location:hit.offset,length:hit.length)) }
        else if let pdf { navigate(.pdf(page:hit.unit,pageCount:pdf.pageCount,y:0),preview:true,highlight:NSRange(location:hit.offset,length:hit.length)) }
    }
    func acceptRemote() {
        guard let remote else { return }
        guard valid(remote.locator) else { self.remote = nil; preparingSync = false; error = DocumentError.invalidPosition.localizedDescription; return }
        temporary = false
        navigate(remote.locator,remoteTime:Date(timeIntervalSince1970:Double(remote.readAtMs)/1000)) { [weak self] in
            self?.promptedVersion = remote.version; self?.remote = nil; self?.preparingSync = false
        }
    }
    func rejectRemote() { promptedVersion = remote?.version; remote = nil; preparingSync = false }
    func compare() async {
        guard active, ready, !rendering, renderedCommandID == command?.id, openFailure == nil, !temporary, !busy, !deleting, remote == nil, let key else { return }
        busy = true; preparingSync = sync.isSyncEnabled
        let generation = generation, scope = sync.documentScope
        defer {
            busy = false
            if self.remote == nil { preparingSync = false }
            if active, self.generation != generation { Task { await compare() } }
        }
        do {
            guard let items = try await sync.pullDocument(key:key,scope:scope) else { syncMessage = "未开启同步，可继续本地阅读"; return }
            guard active, self.generation == generation, scope == sync.documentScope, !temporary else { return }
            let latest = try items.first?.validated(key:key,format:book.format)
            guard let formal = self.formal else { return }
            let localTime = FormalReadingProgress.milliseconds(readAt)
            if let latest, latest.readAtMs > localTime, latest.locator != formal, latest.version != promptedVersion {
                guard valid(latest.locator) else { throw DocumentError.invalidPosition }
                remote = latest; return
            }
            if !uploadPaused, !temporary, active, localTime > 0, latest == nil || localTime > latest!.readAtMs {
                let state = try await sync.uploadDocument(.init(bookHash:key.bookHash,fileSize:key.fileSize,locator:formal,readAtMs:localTime),scope:scope)
                _ = try state.validated(key:key,format:book.format)
                guard active, self.generation == generation, scope == sync.documentScope else { return }
            }
            syncMessage = uploadPaused ? "本次阅读已暂停上传；关闭重开后恢复" : "同步比较完成"
        } catch is CancellationError {} catch { syncMessage = "同步暂不可用，保留本地阅读；可刷新重试" }
    }
    func deleteCloud() async {
        guard active, !deleting, let key else { return }
        deleting = true; generation = UUID(); remote = nil; preparingSync = false
        defer { deleting = false }
        do {
            try await sync.deleteDocument(key:key,scope:sync.documentScope)
            uploadPaused = true; syncMessage = "云端进度已删除，本次阅读暂停上传"
        } catch { self.error = "云端删除失败，本地阅读进度已保留" }
    }
    func setActive(_ value: Bool) {
        guard !closed else { return }
        active = value; generation = UUID(); remote = nil; preparingSync = false
        // Backgrounding must not strand a rendered command with an uncommitted target.
        if pendingNavigation != nil {
            navigationGeneration = UUID(); pendingNavigation = nil; current = formal; command = formal.map { Command(locator:$0) }
        }
        if !value { cancelSearch(); selection = "" }
        timer?.cancel(); timer = nil
        if value, ready { startTimer(); Task { await compare() } }
    }
    private func startTimer() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for:.seconds(20)) } catch { return }
                await self?.compare()
            }
        }
    }
    func close() {
        setActive(false); closed = true; openGeneration = UUID(); openingTask?.cancel(); openingTask = nil; cancelSearch()
        selection = ""; needsPassword = false; pendingNavigation = nil; command = nil; pdf = nil; epub = nil; comic = nil; kindle = nil; reflowDocument = nil
    }
}
