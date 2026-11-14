import SwiftUI
import UniformTypeIdentifiers

// MARK: - 三栏布局（iPad）/ 自动折叠为导航栈（iPhone）

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences

    @State private var selectedBook: Book?
    @State private var selectedChapter: Chapter?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebar(selection: $selectedBook)
        } content: {
            ChapterListView(book: selectedBook, selection: $selectedChapter)
        } detail: {
            if let chapter = selectedChapter {
                ReaderView(chapter: chapter)
                    .id(chapter.id) // 切章时重建，重置滚动与播放器
            } else {
                WelcomeView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(prefs.isDarkMode ? .dark : .light)
        .onAppear { library.restore() }
        .fileImporter(
            isPresented: Binding(
                get: { library.isImporting },
                set: { library.isImporting = $0 }
            ),
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            library.handleImport(result)
            selectedBook = nil
            selectedChapter = nil
        }
        .fileImporter(
            isPresented: Binding(
                get: { library.isFileImporting },
                set: { library.isFileImporting = $0 }
            ),
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            library.handleFileImport(result)
            selectedBook = nil
            selectedChapter = nil
        }
    }
}

// MARK: - 首次使用引导 / 导入诊断

struct WelcomeView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)

                Text("本地小说阅读器")
                    .font(.title.bold())

                Text("书库结构：作者文件夹（= 一本书）→ 章节文件夹（= 一章）→ 正文.txt、按序号命名的图片、音视频。")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)

                // iOS 上 .folder 目录选择器要求「选中一个文件夹项目」，
                // 只浏览到某一层直接点「打开」不会返回目录（表现为点了没反应、也没提示）。
                VStack(alignment: .leading, spacing: 8) {
                    Label("如何添加书籍", systemImage: "hand.tap.fill")
                        .font(.headline)
                    Text("推荐：点「选择书库内任意文件」→ 进入书库，选中任意章节里的 txt / 图片 / 视频 → 点「打开」，App 会自动向上找到整个书库。\n"
                       + "备选：选文件夹时，在 iOS 上必须【点选一个文件夹】再点「打开」；只浏览到某一层直接点「打开」，系统不会返回目录。\n"
                       + "免授权：把书放进「文件」App → 我的 iPhone → 本地小说，再点「改用 App 文档目录里的书」。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: 520, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

                Button {
                    library.noteImportStarted("选择书库内任意文件")
                    library.isFileImporting = true
                } label: {
                    Label("选择书库内任意文件（推荐）", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    library.noteImportStarted("选择书库目录")
                    library.isImporting = true
                } label: {
                    Label(library.library?.books.isEmpty == false ? "重新选择书库目录" : "选择书库目录（文件夹）",
                          systemImage: "folder.badge.plus")
                }
                .font(.footnote)

                // 零权限兜底：把书放进「文件」App → 我的 iPhone → 本地小说
                Button {
                    library.useAppDocuments()
                } label: {
                    Label("改用 App 文档目录里的书（免授权）", systemImage: "doc.text.magnifyingglass")
                }
                .font(.footnote)

                Text("若外部目录始终读不到，可在「文件」App → 我的 iPhone → 本地小说 中放入作者文件夹，再点上方的按钮，无需任何目录授权。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)

                if let info = library.diagnostics {
                    Label(info, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                        .padding(10)
                        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                if let message = library.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                        .padding(10)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                if library.library?.books.isEmpty == false {
                    Label("已载入书库，从左侧选择一本书开始阅读。", systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
