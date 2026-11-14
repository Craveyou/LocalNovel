import SwiftUI

// MARK: - 第三栏：连续滚动阅读器
// 固定三段：正文 → 按序号图片（含动图）→ 章末音视频。

struct ReaderView: View {
    let chapter: Chapter

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences

    @State private var content: ChapterContent?
    @State private var paragraphs: [String] = []
    @State private var visibleAnimated: Set<String> = []
    @State private var currentAnchor: String = ""
    @State private var galleryItem: MediaItem?
    @State private var showSettings = false

    var body: some View {
        Group {
            if let content {
                scrollBody(content)
            } else {
                ProgressView("载入章节…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
            MediaGalleryView(items: content?.images ?? [], initial: item)
        }
        .task(id: chapter.id) {
            let resolved = library.content(for: chapter)
            content = resolved
            paragraphs = TextLoader.paragraphs(library.text(for: chapter))
        }
    }

    // MARK: 滚动内容

    private func scrollBody(_ content: ChapterContent) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: prefs.lineSpacing) {
                    // 1. 正文（逐段懒加载）
                    ForEach(paragraphs.indices, id: \.self) { index in
                        Text(paragraphs[index])
                            .font(.system(size: prefs.fontSize))
                            .lineSpacing(prefs.lineSpacing)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("blk-p\(index)")
                            .onAppear { remember("blk-p\(index)") }
                    }

                    // 2. 图片（按序号；动图离屏暂停）
                    if !content.images.isEmpty {
                        sectionLabel("插图 · \(content.images.count)")
                    }
                    ForEach(content.images.indices, id: \.self) { index in
                        let item = content.images[index]
                        InlineMediaView(item: item, isVisible: visibleAnimated.contains(item.id)) {
                            galleryItem = item
                        }
                        .id("blk-i\(index)")
                        .onAppear {
                            visibleAnimated.insert(item.id)
                            remember("blk-i\(index)")
                        }
                        .onDisappear { visibleAnimated.remove(item.id) }
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

                    if let hint = library.ignoredHint(for: chapter) {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    // 底部留白，避免最后一块贴边
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onAppear {
                if let anchor = ProgressStore.shared.anchor(for: chapter.id) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
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

    private func remember(_ anchor: String) {
        guard anchor != currentAnchor else { return }
        currentAnchor = anchor
        ProgressStore.shared.setAnchor(anchor, for: chapter.id)
    }
}
