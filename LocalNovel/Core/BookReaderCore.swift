import UIKit
import SwiftUI
import Foundation

// MARK: - 阅读核心（纯 UIKit，对齐千阅 ReaderService 的状态模型）
//
// 千阅的阅读会话状态只有两个整数：currentChapterIndex / currentPageIndex。
// 章与章之间的导航（章末续章、目录跳章、进度条跨章、上一章 / 下一章）都在
// UIKit 层内一步完成：`goChapterWithIndex:withPageIndex:` 改状态 →
// 呈现层把那一页装上去。它从来没有「把指令抛回外层、由外层重建整个阅读页」
// 这条路。
//
// 我们之前的问题恰恰在这条路上：引擎在 UIKit 里，章间导航却要绕一圈
// SwiftUI（onOpenNext → RootView.startIntent → ReaderView `.id(chapter.id)`
// 整体重建）。重建的瞬间 @State 全部归零，时序稍微错一点就表现为
// 「跳到最后一页 / 跳回首页」这类随机 bug。
//
// 本轮下沉：BookReaderController 持有全书章节表与那两个整数，翻页引擎
// （PagedBaseController 的五个子类）原样保留，作为它的 child。
// SwiftUI 只留壳（菜单栏 / 目录面板 / 排版面板），通过 ReaderCoreHandle
// 下发指令，通过回调收回「当前章变了」的通知。
//
// 不变的约定：
//   · 页码即状态，绝不从滚动偏移反推；
//   · 越界锚点一律回章首；
//   · 锚点仍写 ProgressStore（书架进度 / 书签 / 续读都读它）。

/// SwiftUI 侧持有的命令通道：面板按钮通过它给核心下发指令。
/// 核心尚未就绪时指令静默丢弃（面板只在阅读中可见，正常不会发生）。
final class ReaderCoreHandle {
    fileprivate weak var controller: BookReaderController?

    /// 目录 / 上下章 / 书签跨章：paragraph 为 nil 表示从章首开始
    func goChapter(_ chapter: Chapter, paragraph: Int?) {
        controller?.goChapter(chapter, paragraph: paragraph)
    }

    /// 进度条跨章跳转：章 + 章内比例（0-1），核心负责换算成段落
    func jumpTo(chapter: Chapter, fraction: Double) {
        controller?.jumpTo(chapter: chapter, fraction: fraction)
    }

    /// 同章内精确跳段（书签 / 笔记 / 搜索结果）
    func jumpToParagraph(_ paragraph: Int) {
        controller?.jumpToParagraph(paragraph)
    }
}

/// 进阅读器时的明确意图：哪一章、从第几段开始。
/// 只在核心创建时消费一次，之后核心自己管位置。
struct BookReaderEntry {
    let chapterId: String
    let paragraph: Int
}

// MARK: - SwiftUI 桥

struct BookReaderView: UIViewControllerRepresentable {
    let entry: BookReaderEntry
    let chapters: [Chapter]
    let bookId: String
    let bookTitle: String
    /// 正文内容指纹（净化规则 / 繁简变了要重建分页）
    let contentStamp: String
    let handle: ReaderCoreHandle
    let library: LibraryStore
    let prefs: Preferences
    var onChapterChange: (Chapter) -> Void
    var onTapMedia: (MediaItem) -> Void
    var onTapCenter: () -> Void
    var onSessionEmpty: () -> Void

    func makeUIViewController(context: Context) -> BookReaderController {
        let controller = BookReaderController(entry: entry,
                                              chapters: chapters,
                                              bookId: bookId,
                                              bookTitle: bookTitle,
                                              library: library,
                                              prefs: prefs)
        wire(controller)
        handle.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: BookReaderController, context: Context) {
        wire(controller)
        controller.applyExternal(chapters: chapters,
                                 bookTitle: bookTitle,
                                 contentStamp: contentStamp)
    }

    private func wire(_ controller: BookReaderController) {
        controller.onChapterChange = onChapterChange
        controller.onTapMedia = onTapMedia
        controller.onTapCenter = onTapCenter
        controller.onSessionEmpty = onSessionEmpty
    }
}

// MARK: - 核心

final class BookReaderController: UIViewController {
    // 千阅 ReaderService 的那两个整数：整个会话的状态
    private(set) var chapterIndex = 0
    private(set) var pageIndex = 0

    var onChapterChange: ((Chapter) -> Void)?
    var onTapMedia: ((MediaItem) -> Void)?
    var onTapCenter: (() -> Void)?
    var onSessionEmpty: (() -> Void)?

    private let entry: BookReaderEntry
    private let library: LibraryStore
    private let prefs: Preferences
    private let bookId: String
    private var bookTitle: String
    private var chapters: [Chapter]
    private var contentStamp: String

    private var engine: PagedBaseController?
    /// 当前引擎对应的阅读方式；变了就换引擎（对齐旧版 `.id(pageTurn)` 的重建语义）
    private var engineStyleKey = ""
    private var didEnter = false
    /// 进阅读器时那一次明确的起始段，只在首个 apply 消费。
    /// 以前 entry.paragraph 完全没被读，等于丢掉了上层给的位置意图。
    private var initialRestore: Int?
    private var warmWorkItem: DispatchWorkItem?

    init(entry: BookReaderEntry,
         chapters: [Chapter],
         bookId: String,
         bookTitle: String,
         library: LibraryStore,
         prefs: Preferences) {
        self.entry = entry
        self.chapters = chapters
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.library = library
        self.prefs = prefs
        self.contentStamp = ""
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { warmWorkItem?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = prefs.theme.uiBackgroundColor
    }

    // MARK: 外部更新（SwiftUI 每次 render 调）

    func applyExternal(chapters: [Chapter], bookTitle: String, contentStamp: String) {
        self.chapters = chapters
        self.bookTitle = bookTitle
        self.contentStamp = contentStamp

        guard !chapters.isEmpty else {
            // 章节全没了（目录里删光 / 书被移走）：交还外层退出
            DispatchQueue.main.async { [weak self] in self?.onSessionEmpty?() }
            return
        }

        relocateIfStale()
        if !didEnter { enter() }
        swapEngineIfNeeded()
        // 首帧用上层给的明确段落；之后一律读锚点，不再被入口意图顶住。
        let restore = initialRestore
        initialRestore = nil
        applyCurrent(restoring: restore)
    }

    // MARK: 导航（全部在本层完成，不经 SwiftUI）

    /// 跳到某一章。paragraph 为 nil = 章首（与旧「主动选章写 blk-p0」一致）。
    func goChapter(_ chapter: Chapter, paragraph: Int?) {
        guard let index = chapters.firstIndex(where: { $0.id == chapter.id }) else { return }
        // 点的就是当前章、又没指定段落：什么都不做（不把阅读记忆重置成章首）
        guard index != chapterIndex || paragraph != nil else { return }
        if index == chapterIndex {
            if let paragraph { jumpToParagraph(max(0, paragraph)) }
            return
        }
        chapterIndex = index
        let target = max(0, paragraph ?? 0)
        ProgressStore.shared.setAnchor("blk-p\(target)", for: chapter.id)
        ProgressStore.shared.setLastChapter(chapter.id, for: bookId)
        applyCurrent(restoring: target)
        notifyChapterChange()
    }

    /// 进度条跨章：按「章索引 + 章内比例」换算出目标段落再定位
    func jumpTo(chapter: Chapter, fraction: Double) {
        guard let index = chapters.firstIndex(where: { $0.id == chapter.id }) else { return }
        // 与阅读器 / RootView 同口径：净化删掉的空段不能算进章内比例
        let count = ReaderTextPipeline.displayCount(
            chapterId: chapter.id,
            raw: library.paragraphs(for: chapter),
            rules: prefs.activePurifyRules)
        let clamped = min(max(fraction, 0), 1)
        let paragraph = count > 0
            ? min(max(Int((Double(count - 1) * clamped).rounded()), 0), count - 1)
            : 0
        if index == chapterIndex {
            jumpToParagraph(paragraph)
            return
        }
        chapterIndex = index
        ProgressStore.shared.setAnchor("blk-p\(paragraph)", for: chapter.id)
        ProgressStore.shared.setLastChapter(chapter.id, for: bookId)
        applyCurrent(restoring: paragraph)
        notifyChapterChange()
    }

    /// 同章内精确跳段（点书签 / 笔记 / 搜索结果）
    func jumpToParagraph(_ paragraph: Int) {
        engine?.jumpToParagraph(paragraph)
        pageIndex = engine?.currentIndex ?? pageIndex
    }

    /// 上一章 / 下一章按钮：step = ±1
    func stepChapter(_ step: Int) {
        let target = chapterIndex + step
        guard target >= 0, target < chapters.count else { return }
        goChapter(chapters[target], paragraph: 0)
    }

    /// 章末续章：引擎翻过本章最后一页时回调到这里。
    /// 直接在本层换章 + 装页，不再回 SwiftUI 绕一圈。
    private func advanceChapter() {
        let next = chapterIndex + 1
        guard next < chapters.count else { return }
        chapterIndex = next
        let chapter = chapters[next]
        ProgressStore.shared.setAnchor("blk-p0", for: chapter.id)
        ProgressStore.shared.setLastChapter(chapter.id, for: bookId)
        applyCurrent(restoring: 0)
        notifyChapterChange()
    }

    // MARK: 章内容装载与引擎

    /// 用当前章的内容构建引擎输入并 apply。引擎内部按 signature 决定是否重排。
    /// restoring = 明确的起始段落（跳章 / 续章）；nil = 按这一章的记忆锚点。
    private func applyCurrent(restoring: Int?) {
        guard let engine, chapterIndex < chapters.count else { return }
        let chapter = chapters[chapterIndex]
        let raw = library.paragraphs(for: chapter)
        let paragraphs = ReaderTextPipeline.paragraphs(chapterId: chapter.id,
                                                       raw: raw,
                                                       rules: prefs.activePurifyRules)
        let content = library.content(for: chapter)
        let restore = restoring ?? anchorParagraph(for: chapter, count: paragraphs.count)
        let stamp = contentStamp.isEmpty
            ? ReaderTextPipeline.stamp(rules: prefs.activePurifyRules)
            : contentStamp

        let input = PagedReaderInput(chapterId: chapter.id,
                                     paragraphs: paragraphs,
                                     images: content.images,
                                     avMedia: content.avMedia,
                                     typography: prefs.typography,
                                     theme: prefs.theme,
                                     title: chapter.displayTitle,
                                     bookTitle: bookTitle,
                                     restoreParagraph: restore,
                                     hasNextChapter: chapterIndex + 1 < chapters.count,
                                     isComic: false,
                                     boostRate: prefs.longPressRate,
                                     style: prefs.pageTurn.flipStyle,
                                     headerMode: prefs.headerMode,
                                     footerMode: prefs.footerMode,
                                     headerTopPadding: prefs.headerTopPadding,
                                     footerBottomPadding: prefs.footerBottomPadding,
                                     showsProgress: prefs.showReadingProgress,
                                     flipDuration: prefs.flipDuration,
                                     tapLeft: prefs.tapLeft,
                                     tapCenterAction: prefs.tapCenter,
                                     tapRight: prefs.tapRight,
                                     pageCommand: 0,
                                     pageCommandDelta: 0,
                                     jumpParagraph: -1,
                                     jumpSeq: 0,
                                     contentStamp: stamp)
        engine.apply(input)
        pageIndex = engine.currentIndex
        schedulePrefetch()
    }

    /// 首次进入：按入口意图定位（点目录 / 书签 / 进度条带来的明确段落）
    private func enter() {
        didEnter = true
        initialRestore = max(0, entry.paragraph)
        if let index = chapters.firstIndex(where: { $0.id == entry.chapterId }) {
            chapterIndex = index
        } else if let last = ProgressStore.shared.lastChapterId(for: bookId),
                  let index = chapters.firstIndex(where: { $0.id == last }) {
            chapterIndex = index
        } else {
            chapterIndex = 0
        }
    }

    /// 引擎类型没建过、或阅读方式变了（平移 ↔ 卷曲 ↔ 覆盖…）：换引擎。
    /// 分页 / 锚点 / 页码逻辑全部在引擎基类里，换的只是「怎么呈现」。
    private func swapEngineIfNeeded() {
        let key = "\(prefs.pageTurn.rawValue)"
        guard engine == nil || engineStyleKey != key else { return }
        if let old = engine {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        engineStyleKey = key
        let fresh = makeEngine()
        fresh.onProgress = { [weak self] paragraph in
            self?.handleEngineProgress(paragraph)
        }
        fresh.onTapMedia = { [weak self] item in self?.onTapMedia?(item) }
        fresh.onTapCenter = { [weak self] in self?.onTapCenter?() }
        fresh.onOpenNext = { [weak self] in self?.advanceChapter() }
        addChild(fresh)
        fresh.view.frame = view.bounds
        fresh.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(fresh.view)
        fresh.didMove(toParent: self)
        engine = fresh
    }

    private func makeEngine() -> PagedBaseController {
        switch prefs.pageTurn.flipStyle {
        case .curl:     return CurlPageController()
        case .slide:    return SlidePageController()
        case .cover:    return CoverPageController()
        case .vertical: return VerticalPageController()
        case .none:     return InstantPageController()
        }
    }

    /// 引擎翻页后回传：写锚点（书架进度 / 书签 / 续读都读它），同步 pageIndex
    private func handleEngineProgress(_ paragraph: Int) {
        guard chapterIndex < chapters.count else { return }
        pageIndex = engine?.currentIndex ?? pageIndex
        ProgressStore.shared.noteAnchor("blk-p\(paragraph)", for: chapters[chapterIndex].id)
    }

    /// 当前章失效（重新分章 / 删除章节后章节表变了）：按「最近读的章」重定位，
    /// 找不到就回第一章；都按该章记忆锚点续读。
    private func relocateIfStale() {
        guard didEnter else { return }
        let currentId = chapterIndex < chapters.count ? chapters[chapterIndex].id : nil
        if let currentId, chapters.contains(where: { $0.id == currentId }) { return }
        let last = ProgressStore.shared.lastChapterId(for: bookId)
        guard let index = chapters.firstIndex(where: { $0.id == last }) ?? chapters.indices.first else {
            DispatchQueue.main.async { [weak self] in self?.onSessionEmpty?() }
            return
        }
        chapterIndex = index
        applyCurrent(restoring: nil)
        notifyChapterChange()
    }

    /// 章变了的通知。relocateIfStale 发生在 SwiftUI 视图更新期间，
    /// 回调里改 @State 必须丢到下一轮主线程，否则就是「更新中改状态」。
    private func notifyChapterChange() {
        guard chapterIndex < chapters.count else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.chapterIndex < self.chapters.count else { return }
            self.onChapterChange?(self.chapters[self.chapterIndex])
        }
    }

    /// 记忆锚点换算成段落；没有记忆或越界都回章首
    private func anchorParagraph(for chapter: Chapter, count: Int) -> Int {
        guard count > 0,
              let anchor = ProgressStore.shared.anchor(for: chapter.id),
              anchor.hasPrefix("blk-p"),
              let value = Int(anchor.dropFirst("blk-p".count)),
              value >= 0, value < count else { return 0 }
        return value
    }

    /// 预取下一章正文：提前「空转」一次，翻过去时内容已在缓存里
    private func schedulePrefetch() {
        warmWorkItem?.cancel()
        guard chapterIndex + 1 < chapters.count else { return }
        let next = chapters[chapterIndex + 1]
        let item = DispatchWorkItem { [weak self] in
            _ = self?.library.paragraphs(for: next)
        }
        warmWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
    }
}
