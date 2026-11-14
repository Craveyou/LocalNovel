import SwiftUI

// MARK: - 第一栏：书库首页 = 三个文件夹（小说 / 漫画 / 整理）
//
// 分类由目录决定：书放在哪个分区就是哪一类，不再按内容猜测、也不再手动改分类。
// 层级：书库 → 分区 → 系列（小说区的中间文件夹）→ 书 → 章节。
// 每一层都支持两种返回：左上角「‹ 上级」按钮，以及从左边缘向右滑。

struct LibrarySidebar: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var selection: Book?

    @State private var openedSection: BookCategory?
    /// 小说分区里的系列文件夹；nil 表示还在分区这一层
    @State private var openedSeries: String?
    @State private var pendingDelete: Book?
    @State private var resultMessage: String?
    @State private var showSettings = false

    private var allBooks: [Book] { library.library?.books ?? [] }

    private var currentTitle: String {
        openedSeries ?? openedSection?.label ?? "书库"
    }

    var body: some View {
        Group {
            if allBooks.isEmpty {
                EmptyLibraryState()
            } else if let section = openedSection, let series = openedSeries {
                seriesBooks(section, series: series)
            } else if let section = openedSection {
                sectionBooks(section)
            } else {
                sectionHome
            }
        }
        .navigationTitle(currentTitle)
        // 分区 / 系列页：从左边缘向右滑返回上一级（与系统返回手势一致）
        .simultaneousGesture(backSwipe)
        // 书架（首页）直达独立设置页：字号、行距、外观等所有偏好都集中在那里
        .sheet(isPresented: $showSettings) { SettingsView() }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if let section = openedSection {
                    Button {
                        backToParent()
                    } label: {
                        Label(openedSeries == nil ? "书库" : section.label,
                              systemImage: "chevron.left")
                    }
                } else {
                    Button { showSettings = true } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        library.importTargetSection = openedSection
                        library.importTargetSeries = openedSeries
                        library.noteImportStarted(ImportMode.file.label)
                        library.activeImport = .file
                    } label: {
                        Label(importLabel(isFolder: false), systemImage: "doc.badge.plus")
                    }
                    Button {
                        library.importTargetSection = openedSection
                        library.importTargetSeries = openedSeries
                        library.noteImportStarted(ImportMode.folder.label)
                        library.activeImport = .folder
                    } label: {
                        Label(importLabel(isFolder: true), systemImage: "folder.badge.plus")
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
            if openedSection != nil {
                ToolbarItem(placement: .secondaryAction) {
                    Button { showSettings = true } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { statusBar }
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
            Text("《\(book.title)》（\(book.chapters.count) \(unit(for: book))）将从书库移除。若在 App 文档目录内，源文件会被一并删除且不可恢复；若在只读目录，则改为隐藏。")
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

    // MARK: - 层级返回（按钮 + 右滑手势共用）

    private func backToParent() {
        withAnimation(.easeOut(duration: 0.2)) {
            if openedSeries != nil {
                openedSeries = nil
            } else {
                openedSection = nil
            }
        }
    }

    /// 左边缘起手、明显向右、纵向几乎不动 —— 才当作返回，避免和列表滚动 / 行内左滑冲突
    private var backSwipe: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                guard openedSection != nil else { return }
                guard value.startLocation.x <= 44,
                      value.translation.width >= 80,
                      abs(value.translation.height) <= 70 else { return }
                backToParent()
            }
    }

    private func importLabel(isFolder: Bool) -> String {
        let action = isFolder ? "导入文件夹" : "导入文件"
        if let series = openedSeries { return "\(action)到「\(series)」" }
        if let section = openedSection { return "\(action)到「\(section.label)」" }
        return isFolder ? "导入书籍文件夹" : "导入书籍文件"
    }

    // MARK: - 首页：三个文件夹

    private var sectionHome: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(BookCategory.allCases) { category in
                    sectionCard(category)
                }
            }
            .padding(16)
        }
    }

    private func sectionCard(_ category: BookCategory) -> some View {
        let count = library.count(in: category)
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                openedSection = category
                openedSeries = nil
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: category.symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 46, height: 46)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(category.label)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(category.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(count == 0 ? Color.secondary : Color.primary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 分区内：系列文件夹 + 未分组的书

    private func sectionBooks(_ category: BookCategory) -> some View {
        let seriesNames = library.seriesNames(in: category)
        let loose = library.books(in: category, series: nil)
        return Group {
            if seriesNames.isEmpty && loose.isEmpty {
                ContentUnavailableView {
                    Label("「\(category.label)」是空的", systemImage: category.symbol)
                } description: {
                    Text(category.emptyDescription)
                }
            } else if seriesNames.isEmpty {
                List(loose, id: \.id, selection: $selection) { book in
                    row(book)
                }
            } else {
                List(selection: $selection) {
                    Section {
                        ForEach(seriesNames, id: \.self) { name in
                            seriesRow(name, category: category)
                        }
                    } header: {
                        Text("系列")
                    }
                    if !loose.isEmpty {
                        Section {
                            ForEach(loose, id: \.id) { book in
                                row(book)
                            }
                        } header: {
                            Text("未分组")
                        }
                    }
                }
            }
        }
    }

    private func seriesRow(_ name: String, category: BookCategory) -> some View {
        let count = library.count(in: category, series: name)
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                openedSeries = name
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.body)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text("\(count) 本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 系列内：书列表

    private func seriesBooks(_ category: BookCategory, series: String) -> some View {
        let books = library.books(in: category, series: series)
        return Group {
            if books.isEmpty {
                ContentUnavailableView {
                    Label("「\(series)」里还没有书", systemImage: "folder")
                } description: {
                    Text("把 txt / md / epub / pdf 放进这个文件夹，回到本 App 会自动出现。")
                }
            } else {
                List(books, id: \.id, selection: $selection) { book in
                    row(book)
                }
            }
        }
    }

    private func row(_ book: Book) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    if library.isSplitting(book) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在分章…")
                    } else {
                        Text("\(book.chapters.count) \(unit(for: book))")
                        if book.category == .comic, let first = book.chapters.first {
                            Text("·")
                            Text(first.displayTitle)
                                .lineLimit(1)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
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

    private func unit(for book: Book) -> String {
        book.category == .comic ? "话" : "章"
    }

    // MARK: - 底部状态（只显示进行中的任务与错误，不放常驻说明）

    private var statusBar: some View {
        VStack(spacing: 0) {
            if library.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在扫描书库…")
                        .font(.footnote)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.10))
            }
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

// MARK: - 分区空态文案

private extension BookCategory {
    var emptyDescription: String {
        switch self {
        case .novel:
            return "把 txt / md / epub / pdf 直接放进「小说」就是一个文件一本书；"
                + "也可以先建一个文件夹当系列，把同一系列的书放进去。打开时自动按「第X章」分章。"
        case .comic:
            return "每部漫画一个文件夹：漫画名 → 第1部 → 第1话 → 图片；也可以 漫画名 → 第5话.pdf。"
        case .organized:
            return "结构：作者名文件夹 → 章节名文件夹 → 正文.txt + 按序号命名的图片 + 章末音视频。"
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

                Label("把书放进三个文件夹（无需点按钮、无需授权）", systemImage: "star.fill")
                    .font(.headline)

                Text("打开「文件」App → 我的 iPhone → 本地小说，你会看到：\n"
                   + "小说/    每个 txt / md / epub / pdf 就是一本；文件夹 = 一个系列\n"
                   + "漫画/    漫画名 → 第1部 → 第1话 → 图片，或直接用 pdf\n"
                   + "整理/    作者名 → 章节名 → 正文.txt + 按序号图片 + 音视频")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                Text("放好后回到本 App，书会自动出现。看不到「本地小说」目录，可在「文件」App 顶部搜索框搜它。")
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
                        library.importTargetSection = nil
                        library.importTargetSeries = nil
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
