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
    }
}

// MARK: - 首次使用引导

struct WelcomeView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("本地小说阅读器")
                .font(.title.bold())

            Text("选择你的书库根目录（包含「作者名文件夹 / 章节名文件夹」的那一层）。\n所有内容仅在本机读取，不联网、不上传、不修改你的文件。")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            if let message = library.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            Button {
                library.isImporting = true
            } label: {
                Label(library.library == nil ? "选择书库目录" : "重新选择书库目录", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)

            if library.library != nil {
                Text("已载入书库，从左侧选择一本书开始阅读。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
