import SwiftUI

// MARK: - 第二栏：章节目录（文件夹名即章节名，天然准确）

struct ChapterListView: View {
    let book: Book?
    @Binding var selection: Chapter?

    var body: some View {
        Group {
            if let book {
                List(book.chapters, id: \.id, selection: $selection) { chapter in
                    Text(chapter.title)
                        .font(.body)
                        .padding(.vertical, 3)
                        .tag(chapter)
                }
                .navigationTitle(book.title)
                .onAppear {
                    if selection == nil,
                       let last = ProgressStore.shared.lastChapterId(for: book.id),
                       let chapter = book.chapters.first(where: { $0.id == last }) {
                        selection = chapter
                    }
                }
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
    }
}
