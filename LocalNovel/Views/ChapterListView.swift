import SwiftUI

// MARK: - 第二栏：章节目录（文件夹名即章节名，天然准确）
// 支持左滑删除章节；「上次读到哪一章」的记忆在换书 / 再次进入时可靠恢复。

struct ChapterListView: View {
    let book: Book?
    @Binding var selection: Chapter?

    @EnvironmentObject private var library: LibraryStore
    @State private var pendingDelete: Chapter?
    @State private var resultMessage: String?

    var body: some View {
        Group {
            if let book {
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
                .navigationTitle(book.title)
                .onAppear { restoreSelection(in: book) }
                .onChange(of: book.id) { _, _ in restoreSelection(in: book) }
                .onChange(of: selection) { _, new in
                    if let chapter = new {
                        ProgressStore.shared.setLastChapter(chapter.id, for: book.id)
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
            Text("《\(chapter.title)》将从书库移除。若该文件夹在 App 文档目录内，源文件会被一并删除且不可恢复；若在只读的外部目录，则改为隐藏，可在「阅读设置 → 书库」里恢复。")
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
