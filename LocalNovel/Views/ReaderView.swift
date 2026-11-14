import SwiftUI

// MARK: - 第三栏：连续滚动阅读器
// 固定三段：正文 → 按序号图片（含动图）→ 章末音视频。
//
// 本版关键修复：
// 1) 去掉 .task + @State content 的异步状态机。自动恢复「上次读的章节」时
//    task 不重跑，content 永远为 nil，表现就是「一直显示载入章节」。
//    现在内容全部同步取自 LibraryStore 的缓存，压根不存在 nil 状态。
// 2) 滚动时不再修改任何 @State：锚点记录改为节流写盘（ProgressStore.noteAnchor），
//    动图可见性下沉到每个 InlineMediaView 自己的 @State。
//    之前每滑过一段就整页重绘 + 同步写 UserDefaults，是一卡一卡的主因。

struct ReaderView: View {
    let chapter: Chapter

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences

    @State private var galleryItem: MediaItem?
    @State private var showSettings = false

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
                        Label("阅读设置", systemImage: "textformat.size")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(item: $galleryItem) { item in
                MediaGalleryView(items: content.images, initial: item)
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
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 14)
    }
}
