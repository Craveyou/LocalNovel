import SwiftUI

// MARK: - 第一栏：书库（一个作者文件夹 = 一本书）

struct LibrarySidebar: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var selection: Book?

    var body: some View {
        Group {
            if let lib = library.library {
                List(lib.books, id: \.id, selection: $selection) { book in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.title)
                            .font(.headline)
                        Text("\(book.chapters.count) 章")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .tag(book)
                }
            } else {
                List {
                    Text("尚未选择书库目录")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("书库")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    library.isImporting = true
                } label: {
                    Label("选择目录", systemImage: "folder.badge.plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    library.reload()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .disabled(library.library == nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = library.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.08))
            }
        }
    }
}
