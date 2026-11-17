import SwiftUI
import UniformTypeIdentifiers

// MARK: - 三栏布局（iPad）/ 自动折叠为导航栈（iPhone）

struct RootView: View {
    /// 打开某一章时「从第几段开始」的明确意图。
    ///
    /// 以前是先把段落锚点写进 ProgressStore、再让 ReaderView 去读：读的那一刻
    /// 谁后写谁赢，任何残留状态（旧锚点、书签跳段留下的 pendingJump）都能把
    /// 位置顶掉，表现就是「点目录里的某一章，却落到了这一章的最后几页」。
    /// 现在由 RootView 明确指定，阅读器只认这个值，不再去猜。
    struct ChapterStart: Equatable {
        let chapterId: String
        let paragraph: Int
    }

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var chrome = ReadingChrome.shared

    @State private var selectedBook: Book?
    @State private var selectedChapter: Chapter?
    /// 书库侧栏的层级（分区 / 小说系列）：放在这里而不是侧栏内部，
    /// 否则两栏 ↔ 三栏切换时侧栏被重建，层级归零、跳回首页。
    @State private var sidebarSection: BookCategory?
    @State private var sidebarSeries: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// 手机（紧凑宽度）下当前该显示哪一栏。
    /// 选到漫画 / 整理 / 短剧时外层会从两栏切成三栏，新分栏视图是「凭空创建」的，
    /// 不能指望它自己按 selection 补一次 push —— 显式指定要展示的栏，否则会停回书库。
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    /// restore 只在首次出现时跑一次；此前每次 onAppear 都全量重扫 + 清缓存，
    /// 会让阅读器内容反复失效，也是「再次点书一直载入」的诱因之一。
    @State private var didRestore = false
    /// 由「打开小说自动定位」或「恢复上次章节」设进来的章节 id。
    /// 它的 selection 变化不算用户主动选章：保留该章的段落锚点，从上次位置续读。
    @State private var autoRestoredChapterId: String?
    /// 本次切章要落的段落（点目录 = 段 0；书签 = 书记的段；进度条 = 换算出的段）
    @State private var startIntent: ChapterStart?
    /// 正在准备打开的小说（后台切章 / 解码整本）。非 nil 时 detail 显示进度而不是阅读器。
    @State private var preparingBook: Book?
    /// 防止「准备完之前用户又点了别的书」：旧任务回来时直接丢弃（序号比对）
    @State private var prepareSeq = 0

    var body: some View {
        // 小说只有两栏：书库 → 阅读器（小说没有「章节目录」中间页，换章走阅读器目录面板）。
        // 漫画 / 短剧 / 整理仍是三栏：书库 → 章节列表 → 正文，点章节在中间栏切换。
        Group {
            if showsCatalogColumn {
                NavigationSplitView(columnVisibility: $columnVisibility,
                                    preferredCompactColumn: $compactColumn) {
                    sidebar
                } content: {
                    ChapterListView(book: selectedBook,
                                    selection: $selectedChapter,
                                    onAutoRestore: { chapter in
                                        // 自动续读：沿用这一章的记忆位置，不重置成章首
                                        autoRestoredChapterId = chapter.id
                                        startIntent = nil
                                    })
                } detail: {
                    readerDetail
                }
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility,
                                    preferredCompactColumn: $compactColumn) {
                    sidebar
                } detail: {
                    readerDetail
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        // 与 MainTabView 同一份状态：分栏布局下 TabView 那层不一定生效，这里补一刀
        .toolbar(chrome.isImmersive ? .hidden : .visible, for: .tabBar)
        // nil = 跟随系统外观；浅色 / 深色则手动固定
        .preferredColorScheme(prefs.preferredScheme)
        .onAppear {
            guard !didRestore else { return }
            didRestore = true
            library.restore()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.refreshOnForeground() }
        }
        // 选书副作用：小说「选书即读」直接进阅读器；
        // 漫画 / 短剧 / 整理停在中间栏的章节列表，等用户点某一话 / 某一集。
        .onChange(of: selectedBook?.id) { _, _ in
            guard let book = selectedBook else {
                selectedChapter = nil
                compactColumn = .sidebar      // 回到书库首页
                return
            }
            if book.category == .novel {
                openBook(book)
                compactColumn = .detail       // 手机：选书即读，直接到正文
            } else {
                selectedChapter = nil
                startIntent = nil
                compactColumn = .content      // 手机：停在章节列表
            }
        }
        // 切章完成（占位章 → 真实章节）后，若当前章已失效或还没选中，重新定位到记忆章节。
        // 准备中的打开由 openNovel 自己接手：这里再抢一次会让阅读器在正文没解码完时就渲染。
        .onChange(of: chapterSignature) { _, _ in
            guard preparingBook == nil else { return }
            guard let book = selectedBook, book.category == .novel else { return }
            let fresh = latestBook() ?? book
            let stale = selectedChapter.map { current in
                !fresh.chapters.contains(where: { $0.id == current.id })
            } ?? true
            guard stale, let target = preferredChapter(in: fresh, allowFirst: true) else { return }
            autoRestoredChapterId = target.id
            startIntent = nil          // 自动定位：按这一章的记忆位置续读
            selectedChapter = target
        }
        // 选章副作用统一到 RootView：记「最近读的章」并区分续读 / 主动选章。
        // 中间那层目录页删掉后，漫画 / 短剧 / 整理也靠这里记忆「上次读到第几话 / 第几集」。
        .onChange(of: selectedChapter?.id) { _, _ in
            guard let chapter = selectedChapter, let book = selectedBook else { return }
            // 占位章（切章前的整本）id 会在切完后失效，不能覆盖记忆里的真实章节 id，
            // 否则下次切完章就找不到上次读的章，被重置到第一章。
            guard !chapter.isPlaceholder else { return }
            ProgressStore.shared.setLastChapter(chapter.id, for: book.id)
            // 手机（紧凑宽度）：选中章节就展示正文栏（三栏布局里 detail 是第三栏）
            compactColumn = .detail
            // 意图不是给这一章的（换书 / 换章后残留）→ 直接作废，别拿别处的位置定位本章
            if startIntent?.chapterId != chapter.id { startIntent = nil }

            if autoRestoredChapterId == chapter.id {
                autoRestoredChapterId = nil   // 自动恢复：保留该章段落锚点，续读
                startIntent = nil
            } else if startIntent != nil {
                // 点目录 / 书签 / 进度条：起始段落已明确，锚点也已写好，不再覆盖
            } else {
                ProgressStore.shared.setAnchor("blk-p0", for: chapter.id) // 主动选章：从章首
            }
        }
        // 全工程【唯一】一个 fileImporter：多个同类弹层叠加会互相冲突、两个都弹不出来
        .fileImporter(
            isPresented: Binding(
                get: { library.activeImport != nil },
                set: { if !$0 { library.activeImport = nil } }
            ),
            // 两种模式都同时允许选文件夹和选文件：用户点文件夹是「进入浏览」，
            // 点文件则会立即回调；这样任一操作都能进入导入流程，不再出现「点了没反应」。
            allowedContentTypes: library.activeImport == .folder
                ? [.folder, .item]
                : [.item, .folder],
            allowsMultipleSelection: false
        ) { result in
            let mode = library.activeImport
            library.activeImport = nil
            if mode == .folder {
                library.handleImport(result)
            } else {
                library.handleFileImport(result)
            }
            selectedBook = nil
            selectedChapter = nil
            preparingBook = nil
            startIntent = nil
        }
    }

    /// 书库第一栏（两栏 / 三栏共用同一份状态，切布局时不丢层级）
    private var sidebar: some View {
        LibrarySidebar(selection: $selectedBook,
                       openedSection: $sidebarSection,
                       openedSeries: $sidebarSeries)
    }

    /// 是否保留中间「章节列表」栏：只有小说不要。
    private var showsCatalogColumn: Bool {
        guard let book = selectedBook else { return false }
        return book.category != .novel
    }

    @ViewBuilder
    private var readerDetail: some View {
        if let book = preparingBook {
            PreparingNovelView(title: book.title)
        } else if let chapter = selectedChapter {
            ReaderView(chapter: chapter,
                       nextChapter: nextChapter(after: chapter),
                       chapters: (latestBook()?.chapters ?? []).filter { !$0.isPlaceholder },
                       bookTitle: latestBook()?.title ?? "",
                       bookId: latestBook()?.id ?? "",
                       category: latestBook()?.category ?? .novel,
                       // 明确告诉阅读器「这一章从第几段开始」：点目录就是 0，
                       // 书签 / 进度条是算出来的段。没指定就按记忆位置续读。
                       startParagraph: startIntent?.chapterId == chapter.id
                           ? startIntent?.paragraph
                           : nil,
                       onOpenNext: { next in selectChapter(next, paragraph: nil) },
                       onSelectChapter: { picked, paragraph in
                           selectChapter(picked, paragraph: paragraph)
                       },
                       onJumpToChapter: { chapter, fraction in
                           jumpToChapter(chapter, fraction: fraction)
                       },
                       // 分页核心在 UIKit 层内换章后同步外层：标成「自动恢复」，
                       // 这样 onChange 不会按主动选章把锚点重置成章首
                       onCoreChapterChange: { coreChapter in
                           autoRestoredChapterId = coreChapter.id
                           selectedChapter = coreChapter
                       },
                       onExit: {
                           selectedChapter = nil
                           selectedBook = nil   // 回到书库首页，再点同一本也会重新触发「选书即读」
                           preparingBook = nil
                           startIntent = nil
                       })
                .id(readerIdentity) // 分页核心整本书一个会话；其余形态按章重建，重置滚动与播放器
        } else {
            WelcomeView()
        }
    }

    /// 用最新扫描结果里的书：删除章节后 selectedBook 仍是旧快照
    private func latestBook() -> Book? {
        guard let book = selectedBook else { return nil }
        return library.library?.books.first(where: { $0.id == book.id }) ?? book
    }

    /// 阅读器身份：小说 + 分页模式走「纯 UIKit 核心」，整本书一个会话，
    /// 章间导航不重建阅读页（这是「跳到最后一页 / 跳回首页」那类 bug 的根源）；
    /// 其余形态保持按章重建（重置滚动位置与播放器）。
    private var readerIdentity: String {
        let pagedCore = latestBook()?.category == .novel && prefs.pageTurn.isPaged
        if pagedCore, let book = latestBook() { return "core-\(book.id)" }
        return selectedChapter?.id ?? "none"
    }

    /// 章节集合的指纹：单文件小说首次打开时后台切章，切完 id 全变，
    /// 用它触发「当前章节失效 → 重新定位」，避免阅读停在已不存在的占位章。
    private var chapterSignature: String {
        (latestBook()?.chapters ?? []).map(\.id).joined(separator: "|")
    }

    /// 选书：小说走「先准备再进阅读器」，漫画 / 短剧 / 整理停在中间栏选章。
    private func openBook(_ book: Book) {
        guard book.category == .novel else {
            selectedChapter = nil
            startIntent = nil
            return
        }
        openNovel(book)
    }

    /// 小说「选书即读」：后台切章 + 解码整本，准备妥了再进阅读器。
    ///
    /// 以前是立刻拿占位章（= 整本书）进阅读页：主线程上要先解码整个文件，
    /// 分页器还要对整本正文做一遍 CoreText 排版，大书点一下能僵好几秒。
    /// 现在准备阶段全部在后台，界面只显示一个明确的进度。
    private func openNovel(_ book: Book) {
        prepareSeq += 1
        let token = prepareSeq
        preparingBook = book
        selectedChapter = nil
        startIntent = nil          // 选书进阅读器 = 续读，位置交给记忆锚点
        library.prepareNovel(book) { fresh in
            // 准备期间用户可能已经点了别的书 / 退出：旧任务直接丢弃
            guard prepareSeq == token, selectedBook?.id == book.id else { return }
            guard let target = preferredChapter(in: fresh, allowFirst: true) else {
                preparingBook = nil
                return
            }
            // 净化 / 繁简也先在后台算好，进页时只剩分页排版
            library.prefetchParagraphs(for: target) {
                guard prepareSeq == token, selectedBook?.id == book.id else { return }
                preparingBook = nil
                autoRestoredChapterId = target.id
                startIntent = nil
                selectedChapter = target
            }
        }
    }

    /// 记忆章节优先；allowFirst = true 时没有记忆则退到第一章（还没有真实章时用占位章）。
    private func preferredChapter(in book: Book, allowFirst: Bool) -> Chapter? {
        let chapters = book.chapters.filter { !$0.isPlaceholder }
        if let last = ProgressStore.shared.lastChapterId(for: book.id),
           let hit = chapters.first(where: { $0.id == last }) {
            return hit
        }
        if allowFirst { return chapters.first ?? book.chapters.first }
        return nil
    }

    /// 主动切章：`paragraph` 为 nil 表示从这一章开头开始。
    ///
    /// 起始段落既写成「明确意图」（`startIntent`，阅读器只认它），也同步写进
    /// ProgressStore（书架进度、书签位置、下次续读都读它）。两处都在
    /// `selectedChapter` 变化之前完成，阅读器重建时读到的一定是本次的目标位置。
    private func selectChapter(_ chapter: Chapter, paragraph: Int?) {
        autoRestoredChapterId = nil
        openChapter(chapter, paragraph: paragraph)
    }

    /// 打开某一章的公共实现：先定位置，再切章。
    private func openChapter(_ chapter: Chapter, paragraph: Int?) {
        // 点的就是当前这一章、也没指定要跳到哪一段（目录里点当前行 / 「定位到当前章」）：
        // 什么都不做。否则会把这一章的阅读记忆重置成章首，退出再进就回到开头了。
        guard paragraph != nil || chapter.id != selectedChapter?.id else { return }
        let target = max(0, paragraph ?? 0)
        if !chapter.isPlaceholder {
            startIntent = ChapterStart(chapterId: chapter.id, paragraph: target)
            ProgressStore.shared.setAnchor("blk-p\(target)", for: chapter.id)
        }
        selectedChapter = chapter
    }

    /// 进度条跨章跳转：按章内比例换算出目标段落，先把锚点写好再切章，
    /// 这样目标章首帧就落在拖动的位置，而不是章首（也不会被当成主动选章重置）。
    private func jumpToChapter(_ chapter: Chapter, fraction: Double) {
        // 标成「自动恢复」，让 onChange 不要按主动选章再重置一次
        autoRestoredChapterId = chapter.id
        var paragraph = 0
        if !chapter.isPlaceholder {
            let count = library.paragraphs(for: chapter).count
            let clamped = min(max(fraction, 0), 1)
            paragraph = count > 0
                ? min(max(Int((Double(count - 1) * clamped).rounded()), 0), count - 1)
                : 0
        }
        openChapter(chapter, paragraph: paragraph)
    }

    private func nextChapter(after chapter: Chapter) -> Chapter? {
        guard let chapters = latestBook()?.chapters,
              let index = chapters.firstIndex(where: { $0.id == chapter.id }),
              index + 1 < chapters.count else { return nil }
        return chapters[index + 1]
    }
}

// MARK: - 打开小说前的准备页

/// 点小说后到正文出现之间的过渡页。
/// 这一版把切章与整本解码都放到后台，所以这里会短暂出现；
/// 关键是它期间**界面不卡**（主线程不再解码整本、不再对整本排版）。
struct PreparingNovelView: View {
    let title: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("正在准备《\(title)》")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("第一次打开会先把整本切成章节、读进内存，之后点开就是秒进。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - 首次使用引导 / 导入诊断（大字、放在主体可视区）

struct WelcomeView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // 扫描已挪到后台：大书库 / 大文件时先给个「在读」提示，不再白屏几秒
                if library.isScanning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在读取书库…")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)

                Text("本地小说阅读器")
                    .font(.title.bold())

                Text("书库分三个文件夹：小说（每本一个 txt / epub / pdf 文件，子文件夹 = 一个系列）、漫画（部 → 话，图片或 pdf）、整理（原来那种 作者 → 章节 的图文混排）。")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)

                VStack(alignment: .leading, spacing: 10) {
                    Label("最省事：把书放进「本地小说」的三个文件夹", systemImage: "star.fill")
                        .font(.headline)
                    Text("1. 打开「文件」App → 我的 iPhone → 本地小说\n"
                       + "2. 小说/ 放 txt、md、epub、pdf（一个文件就是一本；建文件夹就是一个系列）\n"
                       + "3. 漫画/ 放漫画名文件夹：第1部 → 第1话 → 图片，或直接用 第5话.pdf\n"
                       + "4. 整理/ 放作者文件夹 → 章节文件夹 → 正文.txt + 按序号图片 + 音视频\n\n"
                       + "回到本 App —— 书会自动出现，无需点任何按钮、无需授权。\n"
                       + "小说默认左右翻页（点屏幕左右边缘翻页），可在「设置 → 阅读方式」改成上下滚动；"
                       + "「整理」与「漫画」始终上下滚动。\n"
                       + "看不到「本地小说」目录？在「文件」App 顶部搜索框搜「本地小说」即可找到；"
                       + "目录里有一份「放书说明.txt」，App 启动时会自动生成。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: 520, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Label("用「导入」按钮也可以", systemImage: "square.and.arrow.down")
                        .font(.headline)
                    Text("选中的书会被复制进「本地小说」，之后重启也能读（会占用一份额外空间）。"
                       + "在文件选择器里：进入文件夹后要点右上角「打开」才会确认选择；"
                       + "或直接点任意一个 txt / 图片 / pdf 文件，会立即开始导入。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: 520, alignment: .leading)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                if let headline = library.headline {
                    Text(headline)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                if let progress = library.importProgress {
                    Label(progress, systemImage: "square.and.arrow.down")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                if let info = library.diagnostics {
                    Label(info, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                        .padding(10)
                        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                if let message = library.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                        .padding(10)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                HStack(spacing: 12) {
                    Button {
                        library.importTargetSection = nil
                        library.importTargetSeries = nil
                        library.noteImportStarted(ImportMode.file.label)
                        library.activeImport = .file
                    } label: {
                        Label("导入书籍文件（推荐）", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        library.importTargetSection = nil
                        library.importTargetSeries = nil
                        library.noteImportStarted(ImportMode.folder.label)
                        library.activeImport = .folder
                    } label: {
                        Label("导入书籍文件夹", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    library.useAppDocuments()
                } label: {
                    Label("重新读取「本地小说」目录（免授权）", systemImage: "arrow.clockwise")
                }
                .font(.footnote)

                if library.library?.books.isEmpty == false {
                    Label("已载入书库，从左侧选择一本书开始阅读。", systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
