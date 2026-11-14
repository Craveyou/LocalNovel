import SwiftUI

// MARK: - 第一栏：书库（一个作者文件夹 = 一本书）
// iPhone 折叠模式下这一栏就是第一屏，状态与导入入口必须都在这里大字可见。

struct LibrarySidebar: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var selection: Book?

    @State private var pendingDelete: Book?
    @State private var resultMessage: String?
    @State private var showSettings = false

    var body: some View {
        Group {
            if let lib = library.library, !lib.books.isEmpty {
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = book
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } else {
                EmptyLibraryState()
            }
        }
        .navigationTitle("书库")
        // 书架（首页）直达独立设置页：字号、行距、外观等所有偏好都集中在那里
        .sheet(isPresented: $showSettings) { SettingsView() }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showSettings = true } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        library.noteImportStarted(ImportMode.file.label)
                        library.activeImport = .file
                    } label: {
                        Label("导入书里的任意文件（推荐）", systemImage: "doc.badge.plus")
                    }
                    Button {
                        library.noteImportStarted(ImportMode.folder.label)
                        library.activeImport = .folder
                    } label: {
                        Label("导入书库目录（文件夹）", systemImage: "folder.badge.plus")
                    }
                    Button {
                        library.useAppDocuments()
                    } label: {
                        Label("重新读取「本地小说」目录", systemImage: "doc.text.magnifyingglass")
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
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let progress = library.importProgress {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(progress)
                            .font(.footnote)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                }
                if let info = library.diagnostics {
                    Text(info)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.08))
                }
                if let message = library.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                }
            }
        }
        .confirmationDialog(
            "删除书籍",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { book in
            Button("删除《\(book.title)》", role: .destructive) {
                let message = library.deleteBook(book)
                if selection?.id == book.id { selection = nil }
                pendingDelete = nil
                resultMessage = message
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { book in
            Text("《\(book.title)》（\(book.chapters.count) 章）将从书库移除。若在 App 文档目录内，源文件会被一并删除且不可恢复；若在只读目录，则改为隐藏。")
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
}

// MARK: - 空态：状态与操作路径大字可见

private struct EmptyLibraryState: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)

                Text(library.headline ?? "书库为空")
                    .font(.title2.bold())

                if let progress = library.importProgress {
                    Label(progress, systemImage: "square.and.arrow.down")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label("最省事的做法（无需点按钮、无需授权）", systemImage: "star.fill")
                    .font(.headline)

                Text("打开「文件」App → 我的 iPhone → 本地小说，把【作者文件夹】整个复制进去（里面是章节文件夹），然后回到本 App —— 书会自动出现。")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                Text("也可以在下面点「导入」：选中的书会被复制进「本地小说」，之后重启也能读。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("在文件选择器里：进入文件夹后要点右上角「打开」才会确认选择；或直接点书里任意一个 txt / 图片文件，会立即开始导入。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let info = library.diagnostics {
                    Label(info, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                if let message = library.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                HStack(spacing: 12) {
                    Button {
                        library.noteImportStarted(ImportMode.file.label)
                        library.activeImport = .file
                    } label: {
                        Label("导入书籍", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        library.useAppDocuments()
                    } label: {
                        Label("重新读取文档目录", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
