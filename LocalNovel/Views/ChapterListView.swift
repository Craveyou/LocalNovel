import SwiftUI

// MARK: - 第二栏：章节目录
// 支持：
//   * 左滑删除单章（二次确认）
//   * 多选批量删除：点右上「选择」进入，勾选后底部「删除」
//   * 小说单文件：首次进入时在后台按「第X章」切分，切完自动刷新
//   * 「上次读到哪一章」的记忆在换书 / 再次进入时可靠恢复
//   * 短剧：每集一行，显示「大小 · 时长」；剧照包单独一段
//
// 注意：book 是 RootView 传下来的值快照，删除章节 / 分章完成后它不会自动更新。
// 因此列表一律读 currentBook —— 每次渲染从 LibraryStore 的最新扫描结果里取。
//
// 分组：漫画的章节带 groupName（卷名 / 格式包名）。同一部漫画若按格式分成
// 「PDF 包」和「图片包」，列表就分成两段，包下面再列各包的章节。

/// 章节列表里的一段（一个卷 / 一个格式包）
private struct ChapterGroup: Identifiable {
    let id: String
    let title: String?
    let chapters: [Chapter]
}

struct ChapterListView: View {
    let book: Book?
    @Binding var selection: Chapter?
    /// 自动恢复「上次读到哪一章」时回调：让上层知道这次不是用户点的，
    /// 别把这一章的阅读位置重置成章首（漫画 / 整理 / 短剧靠它续读）。
    var onAutoRestore: (Chapter) -> Void = { _ in }

    @EnvironmentObject private var library: LibraryStore
    /// 短剧每集的大小 / 时长（按需加载，行滚到才读）
    @ObservedObject private var videoMeta = VideoMetaStore.shared

    @State private var pendingDelete: Chapter?
    @State private var resultMessage: String?
    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @State private var confirmBatchDelete = false
    /// 由「上次读到哪一章」自动恢复的章节 id：这次 selection 变化不算用户主动选章
    @State private var autoRestoredChapterId: String?

    private var currentBook: Book? {
        guard let book else { return nil }
        return library.library?.books.first(where: { $0.id == book.id }) ?? book
    }

    var body: some View {
        Group {
            if let book = currentBook {
                chapterList(book)
                    .navigationTitle(book.title)
                    .onAppear {
                        library.ensureChapters(for: book)
                        restoreSelection(in: book)
                    }
                    .onChange(of: book.id) { _, _ in restoreSelection(in: book) }
                    .onChange(of: book.chapters.count) { _, _ in restoreSelection(in: book) }
                    .onChange(of: selection) { _, new in
                        guard let chapter = new else {
                            autoRestoredChapterId = nil
                            return
                        }
                        // lastChapter 与段落锚点统一由 RootView 写（那里还会优先消费书签 / 笔记
                        // 带过来的锚点）。这里再写一次会把跳段锚点覆盖成 blk-p0，
                        // 也会和「选书即读」判定的手动/自动选章互相打架，所以只清本地标记。
                        if autoRestoredChapterId == chapter.id {
                            autoRestoredChapterId = nil
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button(isSelecting ? "完成" : "选择") {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isSelecting.toggle()
                                    selectedIds.removeAll()
                                }
                            }
                            .disabled(book.chapters.isEmpty)
                        }
                    }
            } else {
                ContentUnavailableView(
                    "选择一本书",
                    systemImage: "book.closed",
                    description: Text("从左侧书库里选择一本开始阅读")
                )
            }
        }
        // 单章删除确认
        .confirmationDialog(
            "删除章节",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { chapter in
            Button("删除《\(chapter.displayTitle)》", role: .destructive) {
                let message = library.deleteChapter(chapter)
                if selection?.id == chapter.id { selection = nil }
                pendingDelete = nil
                resultMessage = message
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { chapter in
            Text(deleteHint(for: chapter))
        }
        .alert(
            "删除结果",
            isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    // MARK: 列表

    @ViewBuilder
    private func chapterList(_ book: Book) -> some View {
        if isSelecting {
            List(book.chapters) { chapter in
                selectionRow(chapter)
            }
            .safeAreaInset(edge: .bottom) { batchBar(book) }
            // 批量确认挂这里：与单章确认分属不同视图，避免两个
            // confirmationDialog 挂同一视图时只有一个生效
            .confirmationDialog(
                "删除选中的 \(selectedIds.count) 个章节",
                isPresented: $confirmBatchDelete,
                titleVisibility: .visible
            ) {
                Button("删除 \(selectedIds.count) 个章节", role: .destructive) {
                    deleteSelected(in: book)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("源文件会被删除且不可恢复；整本小说里切出来的章节与只读目录则改为隐藏，可在「设置 → 书库」里恢复。")
            }
        } else if library.isSplitting(book) && book.chapters.count <= 1 {
            VStack(spacing: 14) {
                ProgressView()
                Text("正在按「第X章」分章…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("第一次打开需要读一遍整本正文，之后会记住结果。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let groups = chapterGroups(of: book)
            if groups.count <= 1 {
                List(book.chapters, id: \.id, selection: $selection) { chapter in
                    chapterRow(chapter)
                }
            } else {
                // 有分组（卷名 / 格式包名）时按段列：同一部漫画的「PDF 包」「图片包」
                // 各自成一段，包下面再列该包的章节，不合并、不丢任何一种格式。
                List(selection: $selection) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.chapters) { chapter in
                                chapterRow(chapter, showsGroup: false)
                            }
                        } header: {
                            if let title = group.title {
                                Text(title)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(nil)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 章节分组：按 groupName（卷名 / 格式包名）聚合，保持扫描结果的组顺序
    private func chapterGroups(of book: Book) -> [ChapterGroup] {
        var order: [String] = []
        var buckets: [String: [Chapter]] = [:]
        for chapter in book.chapters {
            let key = chapter.groupName ?? ""
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(chapter)
        }
        let hasNamedGroup = order.contains { !$0.isEmpty }
        return order.map { key in
            let title: String? = key.isEmpty
                ? (hasNamedGroup ? "未分组" : nil)
                : key
            return ChapterGroup(id: key, title: title, chapters: buckets[key] ?? [])
        }
    }

    private func chapterRow(_ chapter: Chapter, showsGroup: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsGroup, let group = chapter.groupName, !group.isEmpty {
                Text(group)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(chapter.title)
                .font(.body)
                .padding(.vertical, 1)
            if let line = videoLine(for: chapter) {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .task(id: chapter.id) {
            // 只有视频才读元信息；图片 / 正文行直接返回
            if isVideoChapter(chapter) {
                await VideoMetaStore.shared.load(chapter.folderURL)
            }
        }
        .tag(chapter)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = chapter
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func selectionRow(_ chapter: Chapter) -> some View {
        let isOn = selectedIds.contains(chapter.id)
        return Button {
            if isOn {
                selectedIds.remove(chapter.id)
            } else {
                selectedIds.insert(chapter.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                Text(chapter.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "已选中 \(chapter.displayTitle)" : chapter.displayTitle)
    }

    private func batchBar(_ book: Book) -> some View {
        HStack(spacing: 12) {
            Button(allSelected(in: book) ? "取消全选" : "全选") {
                toggleSelectAll(in: book)
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)

            Text("已选 \(selectedIds.count) \(unit)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(role: .destructive) {
                confirmBatchDelete = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedIds.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var unit: String {
        switch currentBook?.category {
        case .comic:      return "话"
        case .shortDrama: return "集"
        default:          return "章"
        }
    }

    /// 单文件视频章节（短剧的每一集）
    private func isVideoChapter(_ chapter: Chapter) -> Bool {
        chapter.kind == .file && MediaResolver.isVideoFile(chapter.folderURL)
    }

    private func videoLine(for chapter: Chapter) -> String? {
        guard isVideoChapter(chapter) else { return nil }
        return VideoMetaFormat.line(videoMeta.info(for: chapter.folderURL))
    }

    private func deleteHint(for chapter: Chapter) -> String {
        if !chapter.canDeleteFromDisk {
            return "《\(chapter.displayTitle)》是整本文件里切出来的一章，只能隐藏，不会删除原文件；可在「设置 → 书库」里恢复。"
        }
        return "《\(chapter.displayTitle)》将从书库移除。若该文件在 App 文档目录内，源文件会被一并删除且不可恢复；若在只读的外部目录，则改为隐藏。"
    }

    // MARK: 选择与删除

    private func allSelected(in book: Book) -> Bool {
        !book.chapters.isEmpty && selectedIds.count == book.chapters.count
    }

    private func toggleSelectAll(in book: Book) {
        if allSelected(in: book) {
            selectedIds.removeAll()
        } else {
            selectedIds = Set(book.chapters.map { $0.id })
        }
    }

    private func deleteSelected(in book: Book) {
        let targets = book.chapters.filter { selectedIds.contains($0.id) }
        guard !targets.isEmpty else { return }
        let message = library.deleteChapters(targets)
        if let current = selection, targets.contains(where: { $0.id == current.id }) {
            selection = nil
        }
        selectedIds.removeAll()
        isSelecting = false
        resultMessage = message
    }

    /// 只在「当前选中项不属于这本书」时恢复记忆，避免换书后仍停留在旧书的章节
    private func restoreSelection(in book: Book) {
        if let current = selection,
           book.chapters.contains(where: { $0.id == current.id }) { return }
        if let last = ProgressStore.shared.lastChapterId(for: book.id),
           let chapter = book.chapters.first(where: { $0.id == last }) {
            // 标记来源：这次 selection 变化不是用户点的，别把它当成「主动选章」重置到章首
            autoRestoredChapterId = chapter.id
            onAutoRestore(chapter)
            selection = chapter
        } else {
            selection = nil
        }
    }
}
