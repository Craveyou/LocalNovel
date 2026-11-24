import SwiftUI

/// 目录抽屉（对齐截图 5220）：书卡 / 目录·书签·笔记 / 目录搜索 + 排序 /
/// 当前章绿色高亮 / 重新分章（支持自定义正则）。
struct TextCatalogDrawer: View {
    @EnvironmentObject private var session: TextReaderSession
    let theme: TextTheme
    let onClose: () -> Void

    @State private var tab: DrawerTab = .catalog
    @State private var query = ""
    @State private var descending = false
    @State private var showResplit = false
    @State private var customPattern = ""
    @State private var showNewNote = false
    @State private var noteDraft = ""

    enum DrawerTab { case catalog, bookmarks, notes }

    private var filteredIndices: [Int] {
        let all = Array(session.chapters.indices)
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = keyword.isEmpty
            ? all
            : all.filter { session.chapters[$0].title.localizedCaseInsensitiveContains(keyword) }
        return descending ? matched.reversed() : matched
    }

    var body: some View {
        VStack(spacing: 0) {
            bookCard
            tabRow
            Group {
                switch tab {
                case .catalog: catalogBody
                case .bookmarks: bookmarkBody
                case .notes: noteBody
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.chrome.ignoresSafeArea())
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .alert("重新分章", isPresented: $showResplit) {
            TextField("留空 = 默认规则（第X章 / Chapter N）", text: $customPattern)
            Button("取消", role: .cancel) {}
            Button("重切") {
                session.resplit(pattern: customPattern)
            }
        } message: {
            Text("输入分章正则（匹配整行作为章节标题），留空恢复默认规则。")
        }
        .alert("记笔记", isPresented: $showNewNote) {
            TextField("笔记内容", text: $noteDraft)
            Button("取消", role: .cancel) { noteDraft = "" }
            Button("保存") {
                session.addNote(text: noteDraft)
                noteDraft = ""
            }
        }
    }

    // MARK: 书卡

    private var bookCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: coverColors,
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                Text(String((session.book?.title.prefix(6) ?? "书"))
                        .split(separator: " ").prefix(3).joined(separator: "\n"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(6)
            }
            .frame(width: 64, height: 88)
            VStack(alignment: .leading, spacing: 6) {
                Text(session.book?.title ?? "未打开")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("暂无作者")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("共 \(session.chapters.count) 章")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var coverColors: [Color] {
        let palette: [[Color]] = [
            [Color(red: 0.58, green: 0.44, blue: 0.86), Color(red: 0.42, green: 0.28, blue: 0.72)],
            [Color(red: 0.36, green: 0.62, blue: 0.82), Color(red: 0.22, green: 0.44, blue: 0.68)],
            [Color(red: 0.84, green: 0.55, blue: 0.40), Color(red: 0.68, green: 0.38, blue: 0.26)],
            [Color(red: 0.44, green: 0.70, blue: 0.50), Color(red: 0.28, green: 0.52, blue: 0.36)],
        ]
        var hash = 0
        for byte in (session.book?.title ?? "").utf8 { hash = (hash &* 31 &+ Int(byte)) & 0xFFFF }
        return palette[abs(hash) % palette.count]
    }

    // MARK: 标签行：目录 / 书签 / 笔记 + 重新分章

    private var tabRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                tabButton("目录", .catalog)
                tabButton("书签", .bookmarks)
                tabButton("笔记", .notes)
                Spacer()
                if tab == .catalog {
                    Button {
                        customPattern = ""
                        showResplit = true
                    } label: {
                        Image(systemName: "square.and.line.vertical.and.square.delegate")
                            .font(.body)
                            .foregroundStyle(theme.text)
                    }
                    .accessibilityLabel("重新分章")
                }
                if tab == .notes {
                    Button {
                        showNewNote = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.body)
                            .foregroundStyle(theme.text)
                    }
                    .accessibilityLabel("给当前位置加笔记")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Rectangle().fill(Color.gray.opacity(0.25)).frame(height: 0.5)
        }
    }

    private func tabButton(_ title: String, _ target: DrawerTab) -> some View {
        Button {
            tab = target
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(tab == target ? theme.accent : .secondary)
                Rectangle()
                    .fill(tab == target ? theme.accent : Color.clear)
                    .frame(width: 24, height: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: 目录

    private var catalogBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("输入关键字搜索目录", text: $query)
                        .font(.subheadline)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Capsule().fill(theme.isDark ? Color(white: 0.18) : Color(white: 0.9)))
                Button {
                    descending.toggle()
                } label: {
                    Image(systemName: descending ? "arrow.down.1x2" : "arrow.up.1x2")
                        .font(.body)
                        .foregroundStyle(theme.text)
                }
                .accessibilityLabel(descending ? "倒序" : "正序")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollViewReader { proxy in
                List {
                    ForEach(filteredIndices, id: \.self) { index in
                        chapterRow(index)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Color.gray.opacity(0.2))
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear {
                    proxy.scrollTo(session.chapterIndex, anchor: .center)
                }
            }
        }
    }

    private func chapterRow(_ index: Int) -> some View {
        let isCurrent = index == session.chapterIndex
        return Button {
            session.goChapter(index)
            onClose()
        } label: {
            Text(session.chapters[index].title)
                .font(.subheadline)
                .foregroundStyle(isCurrent ? theme.accent : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(index)
        .accessibilityLabel(isCurrent ? "当前章：\(session.chapters[index].title)" : session.chapters[index].title)
    }

    // MARK: 书签

    private var bookmarkBody: some View {
        List {
            if let book = session.book {
                let marks = session.store.bookmarks(in: book.id)
                if marks.isEmpty {
                    emptyRow("还没有书签。阅读时点右上角的书签按钮加一个。")
                }
                ForEach(marks) { mark in
                    Button {
                        session.goChapter(mark.chapterIndex, paragraph: mark.paragraph)
                        onClose()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mark.chapterTitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("第 \(mark.paragraph + 1) 段 · \(mark.preview)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            session.store.removeBookmark(mark)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: 笔记

    private var noteBody: some View {
        List {
            if let book = session.book {
                let notes = session.store.notes(in: book.id)
                if notes.isEmpty {
                    emptyRow("还没有笔记。点右上角 + 给当前位置记一条。")
                }
                ForEach(notes) { note in
                    Button {
                        session.goChapter(note.chapterIndex, paragraph: note.paragraph)
                        onClose()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.chapterTitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(note.text.isEmpty ? "（空笔记）" : note.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            session.store.removeNote(note)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
