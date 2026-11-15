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
    /// restore 只在首次出现时跑一次；此前每次 onAppear 都全量重扫 + 清缓存，
    /// 会让阅读器内容反复失效，也是「再次点书一直载入」的诱因之一。
    @State private var didRestore = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebar(selection: $selectedBook)
        } content: {
            ChapterListView(book: selectedBook, selection: $selectedChapter)
        } detail: {
            if let chapter = selectedChapter {
                ReaderView(chapter: chapter,
                           nextChapter: nextChapter(after: chapter),
                           category: latestBook()?.category ?? .novel,
                           onOpenNext: { next in selectedChapter = next })
                    .id(chapter.id) // 切章时重建，重置滚动与播放器
            } else {
                WelcomeView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        // nil = 跟随系统外观；浅色 / 深色则手动固定
        .preferredColorScheme(prefs.preferredScheme)
        .onAppear {
            guard !didRestore else { return }
            didRestore = true
            library.restore()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.refreshOnForeground() }
        }
        // 全工程【唯一】一个 fileImporter：多个同类弹层叠加会互相冲突、两个都弹不出来
        .fileImporter(
            isPresented: Binding(
                get: { library.activeImport != nil },
                set: { if !$0 { library.activeImport = nil } }
            ),
            // 两种模式都同时允许选文件夹和选文件：用户点文件夹是「进入浏览」，
            // 点文件则会立即回调；这样任一操作都能进入导入流程，不再出现「点了没反应」。
            allowedContentTypes: library.activeImport == .folder
                ? [.folder, .item]
                : [.item, .folder],
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

    /// 用最新扫描结果里的书：删除章节后 selectedBook 仍是旧快照
    private func latestBook() -> Book? {
        guard let book = selectedBook else { return nil }
        return library.library?.books.first(where: { $0.id == book.id }) ?? book
    }

    private func nextChapter(after chapter: Chapter) -> Chapter? {
        guard let chapters = latestBook()?.chapters,
              let index = chapters.firstIndex(where: { $0.id == chapter.id }),
              index + 1 < chapters.count else { return nil }
        return chapters[index + 1]
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

                Text("书库分三个文件夹：小说（每本一个 txt / epub / pdf 文件，子文件夹 = 一个系列）、漫画（部 → 话，图片或 pdf）、整理（原来那种 作者 → 章节 的图文混排）。")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)

                VStack(alignment: .leading, spacing: 10) {
                    Label("最省事：把书放进「本地小说」的三个文件夹", systemImage: "star.fill")
                        .font(.headline)
                    Text("1. 打开「文件」App → 我的 iPhone → 本地小说\n"
                       + "2. 小说/ 放 txt、md、epub、pdf（一个文件就是一本；建文件夹就是一个系列）\n"
                       + "3. 漫画/ 放漫画名文件夹：第1部 → 第1话 → 图片，或直接用 第5话.pdf\n"
                       + "4. 整理/ 放作者文件夹 → 章节文件夹 → 正文.txt + 按序号图片 + 音视频\n\n"
                       + "回到本 App —— 书会自动出现，无需点任何按钮、无需授权。\n"
                       + "小说默认左右翻页（点屏幕左右边缘翻页），可在「设置 → 阅读方式」改成上下滚动；"
                       + "「整理」与「漫画」始终上下滚动。\n"
                       + "看不到「本地小说」目录？在「文件」App 顶部搜索框搜「本地小说」即可找到；"
                       + "目录里有一份「放书说明.txt」，App 启动时会自动生成。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: 520, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Label("用「导入」按钮也可以", systemImage: "square.and.arrow.down")
                        .font(.headline)
                    Text("选中的书会被复制进「本地小说」，之后重启也能读（会占用一份额外空间）。"
                       + "在文件选择器里：进入文件夹后要点右上角「打开」才会确认选择；"
                       + "或直接点任意一个 txt / 图片 / pdf 文件，会立即开始导入。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: 520, alignment: .leading)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                if let headline = library.headline {
                    Text(headline)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                if let progress = library.importProgress {
                    Label(progress, systemImage: "square.and.arrow.down")
                        .font(.callout)
                        .foregroundStyle(.orange)
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
                        library.importTargetSection = nil
                        library.importTargetSeries = nil
                        library.noteImportStarted(ImportMode.file.label)
                        library.activeImport = .file
                    } label: {
                        Label("导入书籍文件（推荐）", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        library.importTargetSection = nil
                        library.importTargetSeries = nil
                        library.noteImportStarted(ImportMode.folder.label)
                        library.activeImport = .folder
                    } label: {
                        Label("导入书籍文件夹", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    library.useAppDocuments()
                } label: {
                    Label("重新读取「本地小说」目录（免授权）", systemImage: "arrow.clockwise")
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
