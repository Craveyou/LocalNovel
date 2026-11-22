import SwiftUI

/// 三类共用阅读页（阶段 2：正文 + 插图；阶段 3 起加 [图NN] 混排；阶段 4-6 加媒体）。
struct LNReaderView: View {
    let book: LNBook
    let chapter: LNChapter
    let source: any LNLibrarySource

    @State private var content: LNChapterContent?
    @State private var errorMessage: String?
    @State private var showingImage: LNMediaItem?

    var body: some View {
        Group {
            if let content {
                readerBody(content)
            } else if let errorMessage {
                ReadingUnavailableView("读取失败", systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                ProgressView("正在读取…")
            }
        }
        .background(ReadingTheme.canvas.ignoresSafeArea())
        .navigationTitle(chapter.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: chapter.id) { await load() }
        .sheet(item: $showingImage) { item in
            LNImagePreview(item: item, source: source)
        }
    }

    @ViewBuilder
    private func readerBody(_ content: LNChapterContent) -> some View {
        if content.isEmpty {
            ReadingUnavailableView("这一章没有可显示的内容", systemImage: "doc.questionmark",
                                   description: Text("检查目录里是否有正文 txt / 图片 / 音视频。"))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    let flow = LNInlineFlow.blocks(paragraphs: content.paragraphs,
                                                   images: content.images,
                                                   category: book.category)
                    if flow.isEmpty {
                        // 原排布：正文逐段 → 插图 → 章末媒体
                        ForEach(content.paragraphs.indices, id: \.self) { i in
                            paragraphText(content.paragraphs[i])
                        }
                        if !content.images.isEmpty {
                            sectionLabel("插图 · \(content.images.count)")
                            ForEach(content.images) { item in
                                LNImageView(item: item, source: source) {
                                    showingImage = item
                                }
                            }
                        }
                    } else {
                        // [图NN] 混排：正文片段与图片交错
                        ForEach(flow.indices, id: \.self) { i in
                            switch flow[i] {
                            case .paragraph(let text, _, _):
                                paragraphText(text)
                            case .inlineImage(let index):
                                if content.images.indices.contains(index) {
                                    let item = content.images[index]
                                    LNImageView(item: item, source: source) {
                                        showingImage = item
                                    }
                                }
                            }
                        }
                        // 未被任何标记引用的图片：章末兜底
                        let matched = LNInlineFlow.matchedIndexes(flow)
                        let residual = content.images.indices.filter { !matched.contains($0) }
                        if !residual.isEmpty {
                            sectionLabel("插图 · \(residual.count)")
                            ForEach(residual, id: \.self) { index in
                                let item = content.images[index]
                                LNImageView(item: item, source: source) {
                                    showingImage = item
                                }
                            }
                        }
                    }
                    if !content.avMedia.isEmpty {
                        sectionLabel("章末媒体 · \(content.avMedia.count)")
                        ForEach(content.avMedia) { item in
                            Label(item.fileName,
                                  systemImage: item.kind == .video ? "play.rectangle" : "waveform")
                                .font(.subheadline)
                                .foregroundStyle(ReadingTheme.ink.opacity(0.7))
                        }
                    }
                    if content.ignoredCount > 0 {
                        Text("另有 \(content.ignoredCount) 个文件未显示")
                            .font(.caption)
                            .foregroundStyle(ReadingTheme.ink.opacity(0.4))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
    }

    private func paragraphText(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(ReadingTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ReadingTheme.ink.opacity(0.45))
            .padding(.top, 8)
    }

    private func load() async {
        do {
            content = try await LNContentLoader.load(chapter, source: source)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            content = nil
        }
    }
}

/// 全屏图片预览（阶段 2 占位：可双指缩放由系统 Image 提供基础能力）
private struct LNImagePreview: View {
    let item: LNMediaItem
    let source: any LNLibrarySource
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ReadingNavigationStack {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task {
            if let url = try? await source.localURL(for: item.path),
               let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                image = UIImage(data: data)
            }
        }
    }
}
