import SwiftUI

// MARK: - 第二栏：章节目录（文件夹名即章节名，天然准确）
// 支持：
//   * 左滑删除单章（二次确认）
//   * 多选批量删除：点右上「选择」进入，勾选后底部「删除」
//   * 「上次读到哪一章」的记忆在换书 / 再次进入时可靠恢复
//
// 注意：book 是 RootView 传下来的值快照，删除章节后它不会自动更新。
// 因此列表一律读 currentBook —— 每次渲染从 LibraryStore 的最新扫描结果里取，
// 否则删完还显示已删的章节。

struct ChapterListView: View {
    let book: Book?
    @Binding var selection: Chapter?

    @EnvironmentObject private var library: LibraryStore

    @State private var pendingDelete: Chapter?
    @State private var resultMessage: String?
    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @State private var confirmBatchDelete = false

    private var currentBook: Book? {
        guard let book else { return nil }
        return library.library?.books.first(where: { $0.id == book.id }) ?? book
    }

    var body: some View {
        Group {
            if let book = currentBook {
                chapterList(book)
                    .navigationTitle(book.title)
                    .onAppear { restoreSelection(in: book) }
                    .onChange(of: book.id) { _, _ in restoreSelection(in: book) }
                    .onChange(of: selection) { _, new in
                        if let chapter = new {
                            ProgressStore.shared.setLastChapter(chapter.id, for: book.id)
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
            Button("删除《\(chapter.title)》", role: .destructive) {
                let message = library.deleteChapter(chapter)
                if selection?.id == chapter.id { selection = nil }
                pendingDelete = nil
                resultMessage = message
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { chapter in
            Text("《\(chapter.title)》将从书库移除。若该文件夹在 App 文档目录内，源文件会被一并删除且不可恢复；若在只读的外部目录，则改为隐藏，可在「设置 → 书库」里恢复。")
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
                Text("这些章节的文件夹会被删除且不可恢复；若在只读的外部目录，则改为隐藏，可在「设置 → 书库」里恢复。")
            }
        } else {
            List(book.chapters, id: \.id, selection: $selection) { chapter in
                Text(chapter.title)
                    .font(.body)
                    .padding(.vertical, 3)
                    .tag(chapter)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = chapter
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
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
                Text(chapter.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "已选中 \(chapter.title)" : chapter.title)
    }

    private func batchBar(_ book: Book) -> some View {
        HStack(spacing: 12) {
            Button(allSelected(in: book) ? "取消全选" : "全选") {
                toggleSelectAll(in: book)
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)

            Text("已选 \(selectedIds.count) 章")
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
            selection = chapter
        } else {
            selection = nil
        }
    }
}
