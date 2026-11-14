import SwiftUI
import UniformTypeIdentifiers

// MARK: - 三栏布局（iPad）/ 自动折叠为导航栈（iPhone）

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.scenePhase) private var scenePhase

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
        // 每次切回前台自动补扫 App 文档目录：书放进去后回到 App 即出现，零点击
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.refreshOnForeground() }
        }
        // 全工程【唯一】一个 fileImporter：多个同类弹层叠加会互相冲突、两个都弹不出来
        .fileImporter(
            isPresented: Binding(
                get: { library.activeImport != nil },
                set: { if !$0 { library.activeImport = nil } }
            ),
            allowedContentTypes: library.activeImport == .folder ? [.folder] : [.item],
            allowsMultipleSelection: false
        ) { result in
            let mode = library.activeImport
            library.activeImport = nil
            if mode == .folder {
                library.handleImport(result)
            } else {
                library.handleFileImport(result)
            }
            selectedBook = nil
            selectedChapter = nil
        }
    }
}

// MARK: - 首次使用引导 / 导入诊断（大字、放在主体可视区）

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

                // 零交互主路径：不依赖任何系统选择器
                VStack(alignment: .leading, spacing: 10) {
                    Label("最省事：把书放进 App 文档目录", systemImage: "star.fill")
                        .font(.headline)
                    Text("1. 打开「文件」App → 我的 iPhone → 本地小说\n"
                       + "2. 把【作者文件夹】整个复制进去（里面是章节文件夹）\n"
                       + "3. 回到本 App —— 书会自动出现，无需点任何按钮、无需授权\n\n"
                       + "提示：放的是作者文件夹本身，不要再多包一层「书」文件夹。\n"
                       + "看不到「本地小说」目录？在「文件」App 顶部搜索框搜「本地小说」即可找到；"
                       + "目录里有一份「放书说明.txt」，App 启动时会自动生成。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: 520, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

                // 当前状态：大字号显示，不再藏在底部小灰字
                if let headline = library.headline {
                    Text(headline)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
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
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                        .padding(10)
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
                        library.noteImportStarted(ImportMode.folder.label)
                        library.activeImport = .folder
                    } label: {
                        Label("选择书库目录（文件夹）", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    library.useAppDocuments()
                } label: {
                    Label("重新读取 App 文档目录（免授权）", systemImage: "arrow.clockwise")
                }
                .font(.footnote)

                if library.library?.books.isEmpty == false {
                    Label("已载入书库，从左侧选择一本书开始阅读。", systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
