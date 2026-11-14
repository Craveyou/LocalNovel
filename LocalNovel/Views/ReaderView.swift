import SwiftUI

// MARK: - 第三栏：连续滚动阅读器
// 固定结构：正文 → 按序号图片（含动图）→ 章末音视频 → 下一章。
//
// 需长期保留的三条约束：
// 1) 不用 .task + @State content 的异步状态机。自动恢复「上次读的章节」时
//    task 不重跑，content 永远为 nil，表现就是「一直显示载入章节」。
//    内容全部同步取自 LibraryStore 的缓存。
// 2) 滚动时不修改任何上层 @State：锚点记录走 ProgressStore.noteAnchor 节流写盘，
//    动图可见性下沉到 InlineMediaView 自己的 @State，避免整页重绘导致卡顿。
// 3) 全屏大图关闭后要能定位回刚看的那张图（pendingAnchor + ScrollViewReader）。

struct ReaderView: View {
    let chapter: Chapter
    let nextChapter: Chapter?
    let onOpenNext: (Chapter) -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences

    @State private var galleryItem: MediaItem?
    @State private var showSettings = false
    /// 关闭全屏大图后要滚回的插图锚点（如 "blk-i3"）
    @State private var pendingAnchor: String?

    init(chapter: Chapter,
         nextChapter: Chapter? = nil,
         onOpenNext: @escaping (Chapter) -> Void = { _ in }) {
        self.chapter = chapter
        self.nextChapter = nextChapter
        self.onOpenNext = onOpenNext
    }

    private var content: ChapterContent { library.content(for: chapter) }
    private var paragraphs: [String] { library.paragraphs(for: chapter) }
    private var ignoredHint: String? { library.ignoredHint(for: chapter) }

    var body: some View {
        scrollBody(content)
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

    // MARK: 滚动内容

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

                    // 4. 章末：下一章 / 已是最后一章
                    chapterFooter

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onAppear {
                guard let anchor = ProgressStore.shared.anchor(for: chapter.id) else { return }
                // LazyVStack 首屏布局需要一点时间，太早 scrollTo 会被忽略，导致「记忆不生效」
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
            // 全屏大图关闭后：滚回刚看的那张图，并把记忆锚点更新为它
            .onChange(of: pendingAnchor) { _, anchor in
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
        }
    }

    // MARK: 章末导航

    @ViewBuilder
    private var chapterFooter: some View {
        if let next = nextChapter {
            Button {
                onOpenNext(next)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("下一章")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(next.title)
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
                Text("已是最后一章")
                    .font(.footnote.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
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
