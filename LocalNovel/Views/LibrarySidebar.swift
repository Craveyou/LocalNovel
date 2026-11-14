import SwiftUI

// MARK: - 第一栏：书库（一个作者文件夹 = 一本书）
// iPhone 折叠模式下这一栏就是第一屏，状态与导入入口必须都在这里大字可见。

struct LibrarySidebar: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var selection: Book?

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
                }
            } else {
                // 空态：把「当前状态 + 下一步怎么做」放在主体大字号显示
                EmptyLibraryState()
            }
        }
        .navigationTitle("书库")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        library.noteImportStarted(ImportMode.file.label)
                        library.activeImport = .file
                    } label: {
                        Label("选择书库内任意文件（推荐）", systemImage: "doc.badge.plus")
                    }
                    Button {
                        library.noteImportStarted(ImportMode.folder.label)
                        library.activeImport = .folder
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
            }
        }
        .safeAreaInset(edge: .bottom) {
            // 底部只作补充，字号已提升到正常可读级别
            VStack(spacing: 0) {
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

                Label("最省事的做法（无需点按钮、无需授权）", systemImage: "star.fill")
                    .font(.headline)

                Text("打开「文件」App → 我的 iPhone → 本地小说，把【作者文件夹】整个复制进去（里面是章节文件夹），然后回到本 App —— 书会自动出现。")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                Text("注意：放的是作者文件夹本身，不要再多包一层「书」文件夹。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

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
                        Label("选择书库内任意文件", systemImage: "doc.badge.plus")
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
