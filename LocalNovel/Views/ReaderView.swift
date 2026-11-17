import SwiftUI
import UIKit

// MARK: - 第三栏：阅读器
// 四种形态：
//   · 小说（左右翻页）：CoreText 分页 + 仿真翻页，页内点击左右边缘翻页，末页再翻即进下一章
//   · 小说（上下滚动，可在设置里切换）：正文 → 图片 → 章末音视频 → 到底继续上拉进下一章
//   · 整理（始终上下滚动）：图文混排，插图与音视频跟在正文后面
//   · 漫画（图片章节 / pdf 单话）：满宽逐页连排，点击进全屏
//   · 短剧（剧照包）：与漫画同一套满宽连排；视频集则走整理那套内联播放器
//
// 翻页只属于「小说」：漫画要连排、整理是图文混排，两者都固定滚动，不受设置影响。
//
// 需长期保留的三条约束：
// 1) 不用 .task + @State content 的异步状态机。自动恢复「上次读的章节」时
//    task 不重跑，content 永远为 nil，表现就是「一直显示载入章节」。
//    内容全部同步取自 LibraryStore 的缓存。
// 2) 滚动时不修改任何上层 @State：锚点记录走 ProgressStore.noteAnchor 节流写盘，
//    动图可见性下沉到子视图自己的 @State，避免整页重绘导致卡顿。
// 3) 全屏大图关闭后要能定位回刚看的那张图（pendingAnchor + ScrollViewReader）。

struct ReaderView: View {
    let chapter: Chapter
    let nextChapter: Chapter?
    /// 本书全部章节（供控制菜单里的目录弹层跳转）
    let chapters: [Chapter]
    /// 书名：页眉可以选「书名」（小说专属排版），也是书签 / 笔记的归属键
    let bookTitle: String
    let bookId: String
    /// 所在分区。翻页只给「小说」；漫画连排、整理图文混排，都必须滚动
    let category: BookCategory
    let onOpenNext: (Chapter) -> Void
    /// 目录弹层里主动跳章
    let onSelectChapter: (Chapter) -> Void
    /// 退出阅读回到书库
    let onExit: () -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences

    @State private var galleryItem: MediaItem?
    @State private var showSettings = false
    /// 关闭全屏大图后要滚回的插图锚点（如 "blk-i3"）
    @State private var pendingAnchor: String?
    /// 上下菜单栏（顶部条 + 底部条）
    @State private var showMenu = false
    /// 排版 / 主题面板
    @State private var showStylePanel = false
    /// 目录面板（从下方浮出）
    @State private var showCatalog = false
    /// 拖动进度滑杆时浮出的目标章节名
    @State private var scrubTitle: String?
    /// 音量键翻页：给分页引擎发指令（序号 + 方向）
    @State private var pageCommandSeq = 0
    @State private var pageCommandDelta = 0
    /// 音量键监听器（开启时才创建）
    @State private var volumePager: VolumeKeyPager?
    /// 主题管理（自定义主题增删改）
    @State private var showThemeManager = false
    /// 净化规则管理
    @State private var showPurifyManager = false
    /// 书签 / 笔记数据（右侧浮钮上的书签状态要用）
    @ObservedObject private var annotations = AnnotationStore.shared
    /// 滚动模式：到底之后的上拉是否还有效（切过章或松手回弹后重新武装，保证一次一记）
    @State private var bottomPullArmed = true

    init(chapter: Chapter,
         nextChapter: Chapter? = nil,
         chapters: [Chapter] = [],
         bookTitle: String = "",
         bookId: String = "",
         category: BookCategory = .novel,
         onOpenNext: @escaping (Chapter) -> Void = { _ in },
         onSelectChapter: @escaping (Chapter) -> Void = { _ in },
         onExit: @escaping () -> Void = {}) {
        self.chapter = chapter
        self.nextChapter = nextChapter
        self.chapters = chapters
        self.bookTitle = bookTitle
        self.bookId = bookId
        self.category = category
        self.onOpenNext = onOpenNext
        self.onSelectChapter = onSelectChapter
        self.onExit = onExit
    }

    /// 只对小说生效：漫画 / 整理 / 短剧仍按原来的样子（不读这些排版与主题设置）
    private var isComic: Bool { category == .comic }

    // MARK: 菜单栏数据

    private var topBarTitle: String {
        bookTitle.isEmpty ? chapter.title : bookTitle
    }

    private var chapterIndex: Int? {
        chapters.firstIndex { $0.id == chapter.id }
    }

    private var previousChapter: Chapter? {
        guard let index = chapterIndex, index > 0, index <= chapters.count else { return nil }
        return chapters[index - 1]
    }

    /// 全书进度：章节位置 + 本章段落位置（取阅读记忆里的锚点，不额外记录状态，
    /// 避免每滚动一段就刷新整个阅读页）
    private var bookProgress: Double {
        guard !chapters.isEmpty, let index = chapterIndex else { return 0 }
        var ratio = 0.0
        let count = paragraphs.count
        if count > 1,
           let anchor = ProgressStore.shared.anchor(for: chapter.id),
           anchor.hasPrefix("blk-p"),
           let value = Int(anchor.dropFirst("blk-p".count)) {
            ratio = Double(min(max(value, 0), count - 1)) / Double(count - 1)
        }
        return min(max((Double(index) + ratio) / Double(chapters.count), 0), 1)
    }

    private func chapterTitle(at progress: Double) -> String? {
        guard !chapters.isEmpty else { return nil }
        let index = min(max(Int(progress * Double(chapters.count)), 0), chapters.count - 1)
        return chapters[index].displayTitle
    }

    private func jump(to progress: Double) {
        guard !chapters.isEmpty else { return }
        let index = min(max(Int(progress * Double(chapters.count)), 0), chapters.count - 1)
        let target = chapters[index]
        guard target.id != chapter.id else { return }
        open(target)
    }

    /// 切章（菜单栏操作后收起菜单，回到正文）
    private func open(_ target: Chapter) {
        withAnimation(.easeOut(duration: 0.18)) { showMenu = false }
        onSelectChapter(target)
    }

    /// 白天 / 夜间一键切：在主题里挑对应的一套
    private func toggleDayNight() {
        let wantNight = !prefs.theme.isNight
        let pool = ReaderTheme.builtIns + prefs.customThemes
        if let hit = pool.first(where: { $0.isNight == wantNight }) {
            prefs.themeId = hit.id
        }
    }

    /// 阅读时常亮（小说设置项，退出阅读自动还原）
    private func syncIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = prefs.keepScreenOn
    }

    /// 音量键翻页：只给小说开，且必须是分页模式（滚动模式没有「翻一页」的概念）
    private func syncVolumePager() {
        guard category == .novel, prefs.pageTurn.isPaged, prefs.volumeKeyFlip else {
            volumePager?.stop()
            volumePager = nil
            return
        }
        if volumePager == nil {
            let pager = VolumeKeyPager()
            pager.onUp = { sendPageCommand(1) }
            pager.onDown = { sendPageCommand(-1) }
            pager.start()
            volumePager = pager
        }
    }

    /// 当前段落（阅读记忆里的锚点），书签 / 笔记用它记位置
    private var currentParagraphIndex: Int {
        guard let anchor = ProgressStore.shared.anchor(for: chapter.id),
              anchor.hasPrefix("blk-p"),
              let value = Int(anchor.dropFirst("blk-p".count)) else { return 0 }
        return max(0, value)
    }

    /// 当前位置是否已有书签
    private var currentBookmark: ReaderBookmark? {
        annotations.bookmark(in: bookId,
                             chapterId: chapter.id,
                             paragraph: currentParagraphIndex)
    }

    /// 浮钮上的书签：有就取消，没有就加上（同一个位置不重复记）
    private func toggleBookmark() {
        if let mark = currentBookmark {
            annotations.remove(mark)
        } else {
            addBookmark(at: currentParagraphIndex)
        }
    }

    /// 跳到某章某段：先记下待应用锚点，再切章（RootView 选中后按它设锚点）
    private func jump(to target: Chapter, paragraph: Int) {
        AnnotationStore.shared.pendingJump = (target.id, "blk-p\(paragraph)")
        withAnimation(.easeOut(duration: 0.18)) {
            showCatalog = false
            showMenu = false
        }
        onSelectChapter(target)
    }

    /// 加书签：位置 + 当时段落的一小段原文做预览
    private func addBookmark(at paragraph: Int) {
        let list = paragraphs
        let preview = (paragraph >= 0 && paragraph < list.count)
            ? String(list[paragraph].prefix(40))
            : ""
        AnnotationStore.shared.addBookmark(bookId: bookId,
                                           chapterId: chapter.id,
                                           chapterTitle: chapter.displayTitle,
                                           paragraph: paragraph,
                                           preview: preview)
    }

    private func sendPageCommand(_ delta: Int) {
        pageCommandDelta = delta
        pageCommandSeq += 1
    }

    /// 预取下一章正文：本地书不用等网络，但切章要重新读文件 + 分段 + 切章判断，
    /// 提前在主线程上「空转」一次，翻到下一章时内容已经在缓存里。
    private func warmNextChapter() {
        guard category == .novel, let next = nextChapter else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            _ = library.paragraphs(for: next)
        }
    }

    /// 这一章只有媒体、没有正文（短剧的每一集视频 / 单集音频）
    private var isMediaOnly: Bool {
        content.textURL == nil && paragraphs.isEmpty && !content.avMedia.isEmpty
    }

    /// 章节目录里什么都没有（结构不对或文件被移走）
    private var isEmptyChapter: Bool {
        content.pdfURL == nil && content.textURL == nil
            && content.images.isEmpty && content.avMedia.isEmpty
    }

    /// 漫画的图片章节、短剧的剧照包，都用「满宽连排」这一套
    private var usesComicLayout: Bool {
        if category == .comic { return true }
        return category == .shortDrama && !content.images.isEmpty
    }

    /// 章末文案：漫画说「话」、短剧说「集」、其余说「章」
    private var lastUnitText: String {
        switch category {
        case .comic:      return "已是最后一话"
        case .shortDrama: return "已是最后一集"
        default:          return "已是最后一章"
        }
    }

    private var content: ChapterContent { library.content(for: chapter) }
    /// 正文段落：开了「繁体」就转换一次（带缓存，避免每次 body 重算都跑一遍 ICU）
    private var paragraphs: [String] {
        let raw = library.paragraphs(for: chapter)
        guard category == .novel else { return raw }
        // 净化 → 繁简，一条流水线（带缓存，规则或章节变了才重算）
        return ReaderTextPipeline.paragraphs(chapterId: chapter.id,
                                             raw: raw,
                                             rules: prefs.activePurifyRules,
                                             traditional: prefs.isTraditional)
    }

    /// 滚动模式的正文字体（家族 / 字重 / 字号都跟面板设置）
    private var bodyFont: UIFont {
        ReaderFonts.font(size: prefs.fontSize, family: prefs.fontFamily, weight: prefs.fontWeight)
    }

    /// 章节标题块（滚动模式）。分页模式由 TextPaginator 排版到第一页顶部，两边样式同源。
    private var chapterTitleBlock: some View {
        let style = prefs.titleStyle
        let size = style.fontSize(bodySize: prefs.fontSize)
        let color = style.colorMode == 1 ? Color(hex: style.colorHex) : prefs.theme.uiTitle
        let title = chapter.displayTitle
        let parts = style.splitTwoLines ? TextPaginator.splitTitle(title) : nil
        return VStack(alignment: .leading, spacing: 4) {
            if let parts {
                Text(parts.0)
                    .font(Font(ReaderFonts.font(size: size,
                                                family: prefs.fontFamily,
                                                weight: style.weight,
                                                italic: style.isItalic)))
                    .foregroundStyle(color)
                Text(parts.1)
                    .font(Font(ReaderFonts.font(size: max(12, size * 0.72),
                                                family: prefs.fontFamily,
                                                weight: .regular,
                                                italic: style.isItalic)))
                    .foregroundStyle(color.opacity(0.82))
            } else {
                Text(title)
                    .font(Font(ReaderFonts.font(size: size,
                                                family: prefs.fontFamily,
                                                weight: style.weight,
                                                italic: style.isItalic)))
                    .foregroundStyle(color)
            }
            if style.showBottomLine {
                Rectangle()
                    .fill(prefs.theme.uiSeparator)
                    .frame(height: 1)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, style.topPadding)
        .padding(.bottom, style.bottomPadding)
    }

    /// 阅读亮度：只在阅读层压一层黑，不改系统亮度，退出阅读自动恢复
    @ViewBuilder
    private var brightnessOverlay: some View {
        if prefs.readerBrightness < 0.999 {
            Color.black
                .opacity((1 - prefs.readerBrightness) * 0.8)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
    private var ignoredHint: String? { library.ignoredHint(for: chapter) }

    /// 只有读文字的章节才需要编码开关；pdf 按页渲染、漫画/短剧没有正文
    private var showsEncodingMenu: Bool {
        content.pdfURL == nil && content.textURL != nil
    }

    /// 文本编码：自动识别判错时手动指定，按书记忆
    private var encodingMenu: some View {
        Menu {
            Section {
                ForEach(TextEncodingOption.allCases) { option in
                    Button {
                        library.setTextEncoding(option, for: chapter)
                    } label: {
                        if option == library.textEncoding(for: chapter) {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } header: {
                Text("文本编码 · 当前 \(library.textEncoding(for: chapter).label)")
            }
        } label: {
            Label("文本编码", systemImage: "textformat")
        }
    }

    var body: some View {
        Group {
            if let pdf = content.pdfURL {
                centerTappable(PdfChapterView(url: pdf))
            } else if usesComicLayout {
                centerTappable(comicBody(content))
            } else if isMediaOnly {
                // 短剧的每一集就是一段视频：不进「正文」流程，直接给播放器
                centerTappable(mediaOnlyBody(content))
            } else if usePaging {
                // 翻页引擎自己处理中间点击（UIKit handleTap），这里不重复挂，避免双重触发
                pagedBody(content)
            } else {
                centerTappable(scrollBody(content))
            }
        }
        // 主题底色铺满整页：分页引擎自己也会铺，这里是滚动模式与插图页的底
        .background(prefs.theme.uiBackground)
        .overlay { brightnessOverlay }
        // 阅读区自己定状态栏明暗，跟主题底色走（否则深色主题配浅色状态栏会看不清）
        .preferredColorScheme(prefs.theme.statusBarIsDarkText ? .light : .dark)
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        // 阅读页自己声明隐藏底部标签栏：只在 TabView / NavigationSplitView 外层改状态，
        // 在 iOS 27 的分栏布局里会被 detail 的导航栏更新覆盖掉（表现就是读书时标签栏还在）。
        // 视图存在即隐藏、退出自动恢复，不再依赖 ReadingChrome 的时序。
        .toolbar(.hidden, for: .tabBar)
        // 分栏布局下上面的声明可能被外层覆盖：直接压住宿主 UITabBarController
        .background {
            TabBarAutoHide()
                .allowsHitTesting(false)
        }
        .toolbar {
            // 顶部仍保留「设置」与编码的快捷入口；中间单击另有一套完整控制菜单
            ToolbarItem(placement: .primaryAction) {
                Button { showStylePanel = true } label: {
                    Label("显示选项", systemImage: "textformat.size")
                }
            }
        }
        // 顶部条 / 底部条：贴安全区，单击正文中间弹出或收起
        .overlay(alignment: .top) {
            if showMenu {
                ReaderTopBar(title: topBarTitle,
                             subtitle: chapter.displayTitle,
                             trailing: "净化",
                             theme: prefs.theme,
                             onBack: onExit,
                             onTrailing: { showPurifyManager = true })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if showMenu {
                ReaderBottomBar(theme: prefs.theme,
                                progress: bookProgress,
                                draggingTitle: scrubTitle,
                                hasPrevious: previousChapter != nil,
                                hasNext: nextChapter != nil,
                                isNight: prefs.theme.isNight,
                                onPreviousChapter: {
                                    if let previous = previousChapter { open(previous) }
                                },
                                onNextChapter: {
                                    if let next = nextChapter { open(next) }
                                },
                                onScrub: { value in
                                    scrubTitle = chapterTitle(at: value)
                                },
                                onScrubEnd: { value in
                                    scrubTitle = nil
                                    jump(to: value)
                                },
                                onCatalog: { showCatalog = true },
                                onDayNight: toggleDayNight,
                                onTheme: { showStylePanel = true },
                                onTypography: { showStylePanel = true },
                                onSettings: { showSettings = true })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // 右侧浮动圆钮：书签 / 目录 / 主题（只在菜单展开时出现）
        .overlay(alignment: .trailing) {
            if showMenu {
                ReaderFloatingActions(theme: prefs.theme,
                                      isBookmarked: currentBookmark != nil,
                                      onBookmark: toggleBookmark,
                                      onCatalog: { showCatalog = true },
                                      onTheme: { showStylePanel = true })
                    .transition(.opacity)
            }
        }
        // 目录面板：从下方浮出，自带半透明遮罩，点遮罩收起
        .overlay {
            if showCatalog {
                ReaderCatalogView(chapters: chapters,
                                  currentId: chapter.id,
                                  bookId: bookId,
                                  bookTitle: bookTitle,
                                  currentChapter: chapter,
                                  currentParagraph: currentParagraphIndex,
                                  theme: prefs.theme,
                                  onAddBookmark: addBookmark(at:),
                                  onSelectParagraph: { target, paragraph in
                                      jump(to: target, paragraph: paragraph)
                                  },
                                  onSelect: { picked in
                                      showCatalog = false
                                      showMenu = false
                                      onSelectChapter(picked)
                                  },
                                  onDismiss: { showCatalog = false })
                    .transition(.opacity)
            }
        }
        // 排版 / 主题面板（字号、字体、间距、标题、页眉页脚、主题、亮度）
        .overlay {
            if showStylePanel {
                ReaderControlsPanel(
                    chapterTitle: chapter.displayTitle,
                    showsEncoding: showsEncodingMenu,
                    encodingMenu: AnyView(encodingMenu),
                    onTOC: { showStylePanel = false; showCatalog = true },
                    onSettings: { showSettings = true },
                    onThemeEditor: { showThemeManager = true },
                    onExit: onExit,
                    onDismiss: { showStylePanel = false }
                )
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showThemeManager) { ThemeManagerView() }
        .sheet(isPresented: $showPurifyManager) { PurifyManagerView() }
        .fullScreenCover(item: $galleryItem) { item in
            // 关闭时回传当前图片 → 换算成插图锚点，滚动定位回这张
            MediaGalleryView(items: content.images, initial: item) { closed in
                pendingAnchor = imageAnchor(for: closed, in: content)
            }
        }
        .onAppear {
            ReadingChrome.shared.enter()
            syncIdleTimer()
            syncVolumePager()
            warmNextChapter()
        }
        .onChange(of: prefs.keepScreenOn) { _, _ in syncIdleTimer() }
        .onChange(of: prefs.volumeKeyFlip) { _, _ in syncVolumePager() }
        .onDisappear {
            ReadingChrome.shared.leave()
            // 兜底隐藏是在布局阶段强制设置的，退出阅读时显式还原一次，
            // 避免 representable 销毁顺序不同导致标签栏一直不回来
            TabBarVisibility.setHidden(false, animated: false)
            UIApplication.shared.isIdleTimerDisabled = false
            volumePager?.stop()
            volumePager = nil
            ProgressStore.shared.flushAnchors()
        }
    }

    // MARK: 小说 / 整理：段落流

    private func scrollBody(_ content: ChapterContent) -> some View {
        let paragraphs = self.paragraphs
        let hint = self.ignoredHint
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: prefs.paragraphSpacing) {
                    if isEmptyChapter {
                        ContentUnavailableView {
                            Label("这一章没有可显示的内容", systemImage: "doc.questionmark")
                        } description: {
                            Text("检查该文件夹里是否有 txt / md 正文、按序号命名的图片"
                                 + "或 mp4 等音视频；也可以在「文件」App 里重新整理后回到本 App。")
                        }
                        .padding(.top, 40)
                    }

                    // 0. 章节标题（小说专属排版：字号 / 字重 / 颜色 / 上下间距都可在面板里调）
                    if category == .novel {
                        chapterTitleBlock
                    }

                    // 1. 正文（逐段懒加载）
                    ForEach(paragraphs.indices, id: \.self) { index in
                        Text(paragraphs[index])
                            .font(Font(bodyFont))
                            .kerning(prefs.wordSpacing)
                            .lineSpacing(prefs.lineSpacing)
                            .foregroundStyle(prefs.theme.uiText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("blk-p\(index)")
                            .onAppear {
                                ProgressStore.shared.noteAnchor("blk-p\(index)",
                                                                for: chapter.id)
                            }
                    }

                    // 2. 图片（按序号；动图离屏暂停由子视图自己管理）
                    if !content.images.isEmpty {
                        sectionLabel("插图 · \(content.images.count)")
                    }
                    ForEach(content.images.indices, id: \.self) { index in
                        let item = content.images[index]
                        InlineMediaView(item: item) { galleryItem = item }
                            .id("blk-i\(index)")
                            .onAppear {
                                ProgressStore.shared.noteAnchor("blk-i\(index)",
                                                                for: chapter.id)
                            }
                    }

                    // 3. 章末音视频（点击播放；无则不显示）
                    if !content.avMedia.isEmpty {
                        sectionLabel(category == .shortDrama ? "本集视频" : "章末媒体")
                        ForEach(content.avMedia) { item in
                            MediaAttachmentView(item: item,
                                                chapterId: chapter.id,
                                                boostRate: prefs.longPressRate)
                                .id("blk-a-\(item.id)")
                        }
                    }

                    if let hint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    chapterFooter

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, category == .novel ? prefs.horizontalPadding : 20)
                .padding(.vertical, 16)
            }
            // 小说上下滚动：读到底还继续上拉 = 下一章（章末不再有「下一章」按钮）。
            // 「整理」是图文混排的另一类，保持原样，所以这里按分区拦一道。
            // 始终允许回弹：不足一屏的短章也得能「拉一下」进下一章，否则会卡死在末页。
            .scrollBounceBehavior(.always, axes: .vertical)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // 距底部还能再拉出多少：正常滚动恒 ≤ 0，只有橡皮筋越界才变正
                let bottom = max(geometry.contentSize.height, geometry.containerSize.height)
                return geometry.contentOffset.y + geometry.containerSize.height
                    - bottom - geometry.contentInsets.bottom
            } action: { _, pull in
                advanceIfPulledPastBottom(pull)
            }
            .onAppear { restoreAnchor(proxy) }
            .onChange(of: pendingAnchor) { _, anchor in
                scrollToPendingAnchor(anchor, proxy: proxy)
            }
        }
    }

    // MARK: 纯媒体章节（短剧的每一集）
    //
    // 视频直接走 MediaAttachmentView：内联画面 → 全屏（FullscreenVideoView 内可旋转画面）
    // → 长按临时倍速，三条能力与「整理」章末视频完全同一套实现。

    private func mediaOnlyBody(_ content: ChapterContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(content.avMedia) { item in
                    MediaAttachmentView(item: item,
                                        chapterId: chapter.id,
                                        boostRate: prefs.longPressRate)
                }

                if content.avMedia.contains(where: { $0.kind == .video }) {
                    Label("点右上角全屏 → 全屏里右上角旋转画面；长按画面临时倍速，松手还原",
                          systemImage: "hand.tap")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                chapterFooter
                Color.clear.frame(height: 30)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: 漫画：满宽逐页

    private func comicBody(_ content: ChapterContent) -> some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(content.images.indices, id: \.self) { index in
                            let item = content.images[index]
                            ComicPageView(item: item, width: geo.size.width) {
                                galleryItem = item
                            }
                            .id("blk-i\(index)")
                            .onAppear {
                                ProgressStore.shared.noteAnchor("blk-i\(index)",
                                                                for: chapter.id)
                            }
                        }

                        if content.images.isEmpty {
                            ContentUnavailableView("这一话没有图片",
                                                   systemImage: "photo",
                                                   description: Text("检查该文件夹里是否放进去了 jpg / png 等图片"))
                                .padding(.top, 60)
                        }

                        VStack(spacing: 8) {
                            Text("\(content.images.count) \(category == .shortDrama ? "张" : "页")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            chapterFooter
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                        Color.clear.frame(height: 40)
                    }
                }
                .frame(width: geo.size.width)
                .onAppear { restoreAnchor(proxy) }
                .onChange(of: pendingAnchor) { _, anchor in
                    scrollToPendingAnchor(anchor, proxy: proxy)
                }
            }
        }
    }

    // MARK: 翻页模式

    private var usePaging: Bool {
        category == .novel
            && prefs.pageTurn.isPaged
            && content.pdfURL == nil
            && !paragraphs.isEmpty
    }

    /// 阅读记忆存的是段落锚点（blk-pN），翻页按段落反查页码。
    /// 锚点必须落在本章段落范围内：章节内容变了（重新切章 / 换源）时旧锚点会越界，
    /// 越界后 pageIndex 会把页码收敛到最后一页 —— 表现就是「点开章节直接翻到末尾」。
    ///
    /// 另外，旧版本曾把「插图 / 章末页」的页码误写成最后一段，这类锚点至今还留在
    /// UserDefaults 里，会让每次进这一章都停在末页。落在本章末尾的锚点按脏数据处理：
    /// 真正读到最后一段的场景极少，从章首重读的代价远小于「每次都跳末页」。
    private var restoreParagraph: Int {
        guard let anchor = ProgressStore.shared.anchor(for: chapter.id),
              anchor.hasPrefix("blk-p"),
              let value = Int(anchor.dropFirst("blk-p".count)),
              value >= 0,
              value < paragraphs.count else { return 0 }
        if paragraphs.count > 3, value >= paragraphs.count - 1 { return 0 }
        return value
    }

    private func pagedBody(_ content: ChapterContent) -> some View {
        PagedReaderView(
            input: PagedReaderInput(chapterId: chapter.id,
                                    paragraphs: paragraphs,
                                    images: content.images,
                                    avMedia: content.avMedia,
                                    typography: prefs.typography,
                                    theme: prefs.theme,
                                    title: chapter.displayTitle,
                                    bookTitle: bookTitle,
                                    restoreParagraph: restoreParagraph,
                                    hasNextChapter: nextChapter != nil,
                                    isComic: isComic,
                                    boostRate: prefs.longPressRate,
                                    style: prefs.pageTurn.flipStyle,
                                    headerMode: prefs.headerMode,
                                    footerMode: prefs.footerMode,
                                    headerTopPadding: prefs.headerTopPadding,
                                    footerBottomPadding: prefs.footerBottomPadding,
                                    flipDuration: prefs.flipDuration,
                                    tapLeft: prefs.tapLeft,
                                    tapCenterAction: prefs.tapCenter,
                                    tapRight: prefs.tapRight,
                                    pageCommand: pageCommandSeq,
                                    pageCommandDelta: pageCommandDelta),
            onProgress: { paragraph in
                ProgressStore.shared.noteAnchor("blk-p\(paragraph)", for: chapter.id)
            },
            onTapMedia: { item in galleryItem = item },
            onOpenNext: {
                if let next = nextChapter { onOpenNext(next) }
            },
            onTapCenter: {
                withAnimation(.easeOut(duration: 0.2)) { showMenu.toggle() }
            }
        )
        .id("paged-\(prefs.pageTurn.rawValue)")
    }

    /// 非翻页模式：中间 28%~72% 区域单击弹出控制菜单。
    /// 用带坐标的 tap 手势挂在内容上：子视图（图片看大图、按钮）有自己的手势时优先响应，
    /// 只有落在纯文字 / 空白处的点击才冒泡到这里，再按 x 判断是不是中间区域。
    private func centerTappable<V: View>(_ content: V) -> some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in
                    // .local 原点即本视图左上；iPad 分栏下 geo.size.width 是 detail 列真实宽度
                    let w = geo.size.width
                    if point.x > w * 0.28 && point.x < w * 0.72 {
                        withAnimation(.easeOut(duration: 0.2)) { showMenu.toggle() }
                    }
                }
        }
    }

    // MARK: 锚点

    private func restoreAnchor(_ proxy: ScrollViewProxy) {
        guard let anchor = ProgressStore.shared.anchor(for: chapter.id) else { return }
        // LazyVStack 首屏布局需要一点时间，太早 scrollTo 会被忽略，导致「记忆不生效」
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private func scrollToPendingAnchor(_ anchor: String?, proxy: ScrollViewProxy) {
        guard let anchor else { return }
        // 等 fullScreenCover 收起动画结束再定位，避免滚动被覆盖视图吞掉
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(anchor, anchor: .center)
            }
            ProgressStore.shared.noteAnchor(anchor, for: chapter.id)
            pendingAnchor = nil
        }
    }

    // MARK: 章末导航
    //
    // 小说：章末不放「下一章」了。翻页读到底（或滚动模式下继续上拉）就是下一章，
    //       只在整本最后一章留一行「已是最后一章」，避免用户以为卡住。
    // 漫画 / 整理 / 短剧：本来就靠「连排到底 + 点按钮」，翻页设置不影响它们，按钮保留。

    private var chapterFooter: some View {
        Group {
            if category == .novel {
                if nextChapter == nil { endMark }
            } else if let next = nextChapter {
                Button {
                    onOpenNext(next)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("下一章")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(next.displayTitle)
                                .font(.body.weight(.medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 28)
            } else {
                endMark
            }
        }
    }

    private var endMark: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.title3)
            Text(lastUnitText)
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    /// 滚动模式：读到底再往上拉一截 = 下一章。
    /// 阈值给得比翻页那套大（120pt）：惯性甩到底的橡皮筋不会误触发，
    /// 但刻意往上拉一定能过。一次上拉只切一次，回落（pull ≤ 4）后重新武装。
    private func advanceIfPulledPastBottom(_ pull: CGFloat) {
        guard category == .novel, let next = nextChapter else { return }
        guard pull > 4 else {
            bottomPullArmed = true
            return
        }
        guard bottomPullArmed, pull > 120 else { return }
        bottomPullArmed = false
        onOpenNext(next)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 14)
    }

    /// 插图 → 滚动锚点（与 ForEach 里的 .id("blk-i\(index)") 对应）
    private func imageAnchor(for item: MediaItem, in content: ChapterContent) -> String? {
        guard let index = content.images.firstIndex(where: { $0.id == item.id }) else { return nil }
        return "blk-i\(index)"
    }
}
