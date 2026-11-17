import SwiftUI

// MARK: - 目录面板（从下方浮出：目录 / 书签 / 笔记 三个 Tab）

private enum CatalogTab: Int, CaseIterable, Identifiable {
    case catalog, bookmark, note
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .catalog:  return "目录"
        case .bookmark: return "书签"
        case .note:     return "笔记"
        }
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ReaderCatalogView: View {
    let chapters: [Chapter]
    let currentId: String
    let bookId: String
    let bookTitle: String
    /// 整本文件（重新分章从这里取样本）
    let bookURL: URL?
    /// 这本书当前的分章规则（没设置 = 空串）
    let chapterRule: String
    /// 只有小说能重新分章（漫画 / 整理是目录结构，没有「切章」这回事）
    let canResplit: Bool
    /// 当前章与当前段落（加书签 / 记笔记时记录位置）
    let currentChapter: Chapter
    let currentParagraph: Int
    let theme: ReaderTheme
    let onAddBookmark: (Int) -> Void
    /// 精确跳段：点书签 / 笔记时连段落一起带回去
    let onSelectParagraph: (Chapter, Int) -> Void
    let onSelect: (Chapter) -> Void
    /// 应用新的分章规则（nil = 恢复自动分章）
    let onResplit: (String?) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var annotations = AnnotationStore.shared
    @State private var tab: CatalogTab = .catalog
    @State private var query = ""
    @State private var descending = false
    @State private var editingNote: ReaderNote?
    @State private var shareItem: ShareItem?
    @State private var showResplit = false

    private var sorted: [Chapter] {
        descending ? Array(chapters.reversed()) : chapters
    }

    private var filtered: [Chapter] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return sorted }
        return sorted.filter { $0.displayTitle.localizedCaseInsensitiveContains(keyword) }
    }

    private func indexLabel(_ chapter: Chapter) -> String {
        guard let index = chapters.firstIndex(where: { $0.id == chapter.id }) else { return "" }
        return "\(index + 1)"
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.22))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                VStack(spacing: 0) {
                    handle
                    header
                    if tab == .catalog { searchBar }
                    Divider().overlay(theme.uiSeparator)
                    content
                    footer
                }
                .frame(height: geo.size.height * 0.72)
                .background(theme.uiBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, y: -2)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(item: $editingNote) { note in
            NoteEditorSheet(note: note, theme: theme) { updated in
                AnnotationStore.shared.update(updated)
            }
        }
        .sheet(item: $shareItem) { item in
            VStack(spacing: 18) {
                Text("笔记已导出").font(.headline)
                ShareLink(item: item.url) {
                    Label("保存 / 分享", systemImage: "square.and.arrow.up")
                }
                Button("完成") { shareItem = nil }
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .presentationDetents([.height(200)])
        }
        .sheet(isPresented: $showResplit) {
            ChapterRuleSheet(initialRule: chapterRule, bookURL: bookURL) { rule in
                onResplit(rule)
            }
        }
    }

    // MARK: 局部

    private var handle: some View {
        Capsule()
            .fill(theme.uiSeparator)
            .frame(width: 36, height: 4)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Picker("", selection: $tab) {
                    ForEach(CatalogTab.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 210)

                Spacer(minLength: 8)

                if tab == .catalog {
                    Button {
                        descending.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: descending ? "arrow.up" : "arrow.down")
                                .font(.system(size: 11, weight: .semibold))
                            Text(descending ? "倒序" : "正序").font(.system(size: 12))
                        }
                        .foregroundStyle(theme.uiText)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(theme.uiSeparator.opacity(0.35), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.uiHeaderFooter)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.uiHeaderFooter)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var subtitle: String {
        switch tab {
        case .catalog:  return "共 \(chapters.count) 章"
        case .bookmark: return "共 \(annotations.bookmarks(in: bookId).count) 条书签"
        case .note:     return "共 \(annotations.notes(in: bookId).count) 条笔记"
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(theme.uiHeaderFooter)
            TextField("搜索章节", text: $query)
                .font(.system(size: 14))
                .foregroundStyle(theme.uiText)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.uiHeaderFooter)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(theme.uiSeparator.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .catalog:  chapterList
        case .bookmark: bookmarkList
        case .note:     noteList
        }
    }

    private var chapterList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { chapter in
                        chapterRow(chapter).id(chapter.id)
                    }
                    if filtered.isEmpty { emptyHint("没有匹配的章节") }
                }
                .padding(.bottom, 8)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    proxy.scrollTo(currentId, anchor: .center)
                }
            }
        }
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        let isCurrent = chapter.id == currentId
        return Button {
            onSelect(chapter)
        } label: {
            HStack(spacing: 8) {
                Text(indexLabel(chapter))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(isCurrent ? Color.accentColor : theme.uiHeaderFooter)
                    .frame(width: 34, alignment: .trailing)
                Text(chapter.displayTitle)
                    .font(.system(size: 14, weight: isCurrent ? .medium : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : theme.uiText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                if isCurrent { Circle().fill(Color.accentColor).frame(width: 6, height: 6) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bookmarkList: some View {
        let list = annotations.bookmarks(in: bookId)
        return ScrollView {
            LazyVStack(spacing: 0) {
                if list.isEmpty { emptyHint("还没有书签。下方「加书签」会记住当前位置。") }
                ForEach(list) { mark in
                    Button {
                        if let chapter = chapters.first(where: { $0.id == mark.chapterId }) {
                            onSelectParagraph(chapter, mark.paragraph)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(mark.chapterTitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(theme.uiText)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text("第 \(mark.paragraph + 1) 段")
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.uiHeaderFooter)
                            }
                            if !mark.preview.isEmpty {
                                Text(mark.preview)
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.uiHeaderFooter)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("删除", role: .destructive) { annotations.remove(mark) }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var noteList: some View {
        let list = annotations.notes(in: bookId)
        return ScrollView {
            LazyVStack(spacing: 0) {
                if list.isEmpty { emptyHint("还没有笔记。下方「记笔记」会记录当前章节与段落。") }
                ForEach(list) { note in
                    Button {
                        if let chapter = chapters.first(where: { $0.id == note.chapterId }) {
                            onSelectParagraph(chapter, note.paragraph)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(note.chapterTitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(theme.uiText)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text("第 \(note.paragraph + 1) 段")
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.uiHeaderFooter)
                            }
                            if !note.quote.isEmpty {
                                Text(note.quote)
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.uiHeaderFooter)
                                    .lineLimit(2)
                            }
                            Text(note.text.isEmpty ? "（空笔记，点开编辑）" : note.text)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.uiText)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("编辑") { editingNote = note }
                        Button("删除", role: .destructive) { annotations.remove(note) }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(theme.uiHeaderFooter)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 40)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(theme.uiSeparator)
            HStack(spacing: 0) {
                switch tab {
                case .catalog:
                    footerButton("定位到当前章") {
                        if let chapter = chapters.first(where: { $0.id == currentId }) {
                            onSelect(chapter)
                        }
                    }
                    if canResplit {
                        footerButton("重新分章") { showResplit = true }
                    }
                case .bookmark:
                    footerButton("加书签") { onAddBookmark(currentParagraph) }
                case .note:
                    footerButton("记笔记") {
                        let note = AnnotationStore.shared.addNote(
                            bookId: bookId,
                            chapterId: currentChapter.id,
                            chapterTitle: currentChapter.displayTitle,
                            paragraph: currentParagraph,
                            quote: "",
                            text: "")
                        editingNote = note
                    }
                    footerButton("导出") {
                        if let url = AnnotationStore.shared.exportFile(bookTitle: bookTitle,
                                                                      bookId: bookId) {
                            shareItem = ShareItem(url: url)
                        }
                    }
                }
            }
        }
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.uiText)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 笔记编辑

struct NoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let note: ReaderNote
    let theme: ReaderTheme
    let onSave: (ReaderNote) -> Void

    @State private var text: String
    @State private var quote: String

    init(note: ReaderNote, theme: ReaderTheme, onSave: @escaping (ReaderNote) -> Void) {
        self.note = note
        self.theme = theme
        self.onSave = onSave
        _text = State(initialValue: note.text)
        _quote = State(initialValue: note.quote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("位置") {
                    Text(note.chapterTitle).font(.system(size: 13))
                    Text("第 \(note.paragraph + 1) 段")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Section("摘录（可留空）") {
                    TextField("摘录一段原文", text: $quote, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("笔记") {
                    TextField("写点什么…", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                }
            }
            .navigationTitle("笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = note
                        updated.text = text
                        updated.quote = quote
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}
