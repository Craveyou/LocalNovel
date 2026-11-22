import SwiftUI

/// 本地 tab 的根视图：漫画 / 整理 / 短剧三个入口。
/// NAS tab 的 CategoryView 复用同一个组件，只换 source。
struct LNCategoryView: View {
    let source: any LNLibrarySource
    let title: String
    let subtitle: String
    /// NAS 首屏不预统计（三类各一次远端探测会拖慢进入），进入分类时再加载
    var showsCounts: Bool = true
    /// 页面底部附加内容（NAS 用来放「浏览全部文件」入口）
    var extraContent: AnyView? = nil

    @State private var counts: [LNCategory: Int] = [:]
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                    GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(LNCategory.allCases) { cat in
                        NavigationLink {
                            LNBookListView(source: source, category: cat)
                        } label: {
                            card(cat)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ln.category.\(cat.rawValue)")
                    }
                }
                if let extraContent {
                    extraContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(ReadingTheme.canvas.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { if showsCounts { await loadCounts() } }
        .task { if showsCounts { await loadCounts() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(ReadingTheme.ink.opacity(0.55))
        }
        .padding(.top, 16)
    }

    private func card(_ cat: LNCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: cat.symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(ReadingTheme.accent)
            Text(cat.label)
                .font(.headline)
                .foregroundStyle(ReadingTheme.ink)
            Text(showsCounts ? (counts[cat].map { "\($0) 本" } ?? "—") : "点按进入")
                .font(.caption)
                .foregroundStyle(ReadingTheme.ink.opacity(0.5))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(16)
        .background(ReadingTheme.groupedCanvas,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ReadingTheme.separator.opacity(0.4), lineWidth: 0.5)
        }
    }

    private func loadCounts() async {
        isLoading = true
        defer { isLoading = false }
        var next: [LNCategory: Int] = [:]
        for cat in LNCategory.allCases {
            let path = source.categoryRoot(cat)
            guard let nodes = try? await source.list(at: path) else { continue }
            let books = try? await LNScanner.books(in: nodes, category: cat,
                                                    loadChildren: { node in
                                                        try await source.list(at: node.path)
                                                    })
            next[cat] = books?.count ?? 0
        }
        counts = next
    }
}

/// 阶段 1 占位：书列表页（阶段 2 填充完整交互）
struct LNBookListView: View {
    let source: any LNLibrarySource
    let category: LNCategory

    @State private var books: [LNBook] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if books.isEmpty {
                ReadingUnavailableView("还没有\(category.label)",
                                       systemImage: category.symbol,
                                       description: Text(category.hint))
            } else {
                List(books) { book in
                    NavigationLink {
                        LNChapterListView(source: source, book: book)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title).foregroundStyle(.primary)
                            Text("\(book.chapters.count) 章")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(category.label)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .alert("读取失败", isPresented: Binding(get: { errorMessage != nil },
                                             set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func load() async {
        do {
            let nodes = try await source.list(at: source.categoryRoot(category))
            books = try await LNScanner.books(in: nodes, category: category,
                                               loadChildren: { node in
                                                   try await source.list(at: node.path)
                                               })
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            books = []
        }
    }
}

/// 阶段 1 占位：章节列表页
struct LNChapterListView: View {
    let source: any LNLibrarySource
    let book: LNBook

    var body: some View {
        List(book.chapters) { chapter in
            NavigationLink {
                LNReaderView(book: book, chapter: chapter, source: source)
            } label: {
                HStack {
                    Image(systemName: symbol(for: chapter.kind))
                        .foregroundStyle(ReadingTheme.accent)
                    Text(chapter.displayName).foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func symbol(for kind: LNChapterKind) -> String {
        switch kind {
        case .folder: return "folder"
        case .images: return "photo.on.rectangle"
        case .pdf: return "doc.richtext"
        case .text: return "doc.text"
        case .video: return "play.rectangle"
        case .audio: return "waveform"
        }
    }
}
