import SwiftUI

// MARK: - 第一栏：书库（一个作者文件夹 = 一本书）
// iPhone 折叠模式下这一栏就是第一屏，所以三种导入方式必须都在这里可达，
// 不能只放在 detail 页的 WelcomeView 里。

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
                    Text("尚未添加书籍")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("书库")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        library.noteImportStarted("选择书库内任意文件")
                        library.isFileImporting = true
                    } label: {
                        Label("选择书库内任意文件（推荐）", systemImage: "doc.badge.plus")
                    }
                    Button {
                        library.noteImportStarted("选择书库目录")
                        library.isImporting = true
                    } label: {
                        Label("选择书库目录（文件夹）", systemImage: "folder.badge.plus")
                    }
                    Button {
                        library.useAppDocuments()
                    } label: {
                        Label("App 文档目录（免授权）", systemImage: "doc.text.magnifyingglass")
                    }
                } label: {
                    Label("添加书籍", systemImage: "plus")
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
            // iPhone 上第一栏可见、WelcomeView 未必可见，诊断必须在这里也能看到
            VStack(spacing: 0) {
                if let info = library.diagnostics {
                    Text(info)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.08))
                }
                if let message = library.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                }
            }
        }
    }
}
