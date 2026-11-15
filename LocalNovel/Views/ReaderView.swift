import SwiftUI

// MARK: - 第三栏：阅读器
// 四种形态：
//   · 小说（左右翻页）：CoreText 分页 + 仿真翻页，页内点击左右边缘翻页
//   · 小说（上下滚动，可在设置里切换）：正文 → 图片 → 章末音视频 → 下一章
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
    /// 所在分区。翻页只给「小说」；漫画连排、整理图文混排，都必须滚动
    let category: BookCategory
    let onOpenNext: (Chapter) -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences

    @State private var galleryItem: MediaItem?
    @State private var showSettings = false
    /// 关闭全屏大图后要滚回的插图锚点（如 "blk-i3"）
    @State private var pendingAnchor: String?

    init(chapter: Chapter,
         nextChapter: Chapter? = nil,
         category: BookCategory = .novel,
         onOpenNext: @escaping (Chapter) -> Void = { _ in }) {
        self.chapter = chapter
        self.nextChapter = nextChapter
        self.category = category
        self.onOpenNext = onOpenNext
    }

    private var isComic: Bool { category == .comic }

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
    private var paragraphs: [String] { library.paragraphs(for: chapter) }
    private var ignoredHint: String? { library.ignoredHint(for: chapter) }

    var body: some View {
        Group {
            if let pdf = content.pdfURL {
                PdfChapterView(url: pdf)
            } else if usesComicLayout {
                comicBody(content)
            } else if usePaging {
                pagedBody(content)
            } else {
                scrollBody(content)
            }
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(item: $galleryItem) { item in
            // 关闭时回传当前图片 → 换算成插图锚点，滚动定位回这张
            MediaGalleryView(items: content.images, initial: item) { closed in
                pendingAnchor = imageAnchor(for: closed, in: content)
            }
        }
        .onDisappear { ProgressStore.shared.flushAnchors() }
    }

    // MARK: 小说 / 整理：段落流

    private func scrollBody(_ content: ChapterContent) -> some View {
        let paragraphs = self.paragraphs
        let hint = self.ignoredHint
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: prefs.lineSpacing) {
                    // 1. 正文（逐段懒加载）
                    ForEach(paragraphs.indices, id: \.self) { index in
                        Text(paragraphs[index])
                            .font(.system(size: prefs.fontSize))
                            .lineSpacing(prefs.lineSpacing)
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
                        sectionLabel("章末媒体")
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
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onAppear { restoreAnchor(proxy) }
            .onChange(of: pendingAnchor) { _, anchor in
                scrollToPendingAnchor(anchor, proxy: proxy)
            }
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
            && prefs.pageTurn == .page
            && content.pdfURL == nil
            && !paragraphs.isEmpty
    }

    /// 阅读记忆存的是段落锚点（blk-pN），翻页按段落反查页码
    private var restoreParagraph: Int {
        guard let anchor = ProgressStore.shared.anchor(for: chapter.id),
              anchor.hasPrefix("blk-p"),
              let value = Int(anchor.dropFirst("blk-p".count)) else { return 0 }
        return value
    }

    private func pagedBody(_ content: ChapterContent) -> some View {
        PagedReaderView(
            input: PagedReaderInput(chapterId: chapter.id,
                                    paragraphs: paragraphs,
                                    images: content.images,
                                    avMedia: content.avMedia,
                                    fontSize: prefs.fontSize,
                                    lineSpacing: prefs.lineSpacing,
                                    restoreParagraph: restoreParagraph,
                                    hasNextChapter: nextChapter != nil,
                                    nextTitle: nextChapter?.displayTitle ?? "",
                                    isComic: isComic,
                                    boostRate: prefs.longPressRate),
            onProgress: { paragraph in
                ProgressStore.shared.noteAnchor("blk-p\(paragraph)", for: chapter.id)
            },
            onTapMedia: { item in galleryItem = item },
            onOpenNext: {
                if let next = nextChapter { onOpenNext(next) }
            }
        )
        .id("paged-\(prefs.pageTurn.rawValue)")
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

    private var chapterFooter: some View {
        Group {
            if let next = nextChapter {
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
        }
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
