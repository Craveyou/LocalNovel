import SwiftUI

public struct TextReaderRootView: View {
    public let books: [TextBook]
    @StateObject private var session = TextReaderSession()

    public init(books: [TextBook]) {
        self.books = books
    }

    public var body: some View {
        NavigationStack {
            List(books) { book in
                NavigationLink(value: book) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).font(.headline)
                        Text(book.url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("纯文本小说")
            .navigationDestination(for: TextBook.self) { book in
                TextReaderView()
                    .onAppear {
                        if session.book?.id != book.id { session.open(book) }
                    }
            }
        }
        .environmentObject(session)
        .environmentObject(session.store)
    }
}

public struct TextReaderView: View {
    @EnvironmentObject private var session: TextReaderSession
    @EnvironmentObject private var store: TextReaderStore
    @State private var showCatalog = false
    @State private var showNote = false
    @State private var noteText = ""

    public init() {}

    private var isBookmarked: Bool {
        guard let book = session.book else { return false }
        return store.bookmark(in: book.id,
                              chapterIndex: session.chapterIndex,
                              paragraph: session.currentParagraph) != nil
    }

    public var body: some View {
        GeometryReader { geo in
            Group {
                if session.mode == .paged {
                    TabView(selection: $session.pageIndex) {
                        ForEach(session.pages.indices, id: \.self) { index in
                            ScrollView {
                                Text(session.pages[index].text)
                                    .font(.system(size: session.fontSize))
                                    .lineSpacing(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(session.paragraphs.indices, id: \.self) { index in
                                    Text(session.paragraphs[index])
                                        .font(.system(size: session.fontSize))
                                        .lineSpacing(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id("p\(index)")
                                        .onAppear { session.noteParagraph(index) }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        .onAppear {
                            proxy.scrollTo("p\(session.currentParagraph)", anchor: .top)
                        }
                    }
                }
            }
            .onAppear { session.setContentSize(geo.size) }
            .onChange(of: geo.size) { _, newSize in session.setContentSize(newSize) }
        }
        .navigationTitle(session.currentChapter?.title ?? "阅读")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("阅读方式", selection: $session.mode) {
                    ForEach(TextReaderMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    session.toggleBookmark()
                } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(isBookmarked ? "取消书签" : "加书签")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCatalog = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("目录")
            }
            ToolbarItem(placement: .bottomBar) {
                HStack(spacing: 24) {
                    Button { session.movePage(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("上一页")
                    Button { showNote = true } label: { Image(systemName: "note.text") }
                        .accessibilityLabel("记笔记")
                    Button { session.movePage(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("下一页")
                }
            }
        }
        .sheet(isPresented: $showCatalog) { TextCatalogSheet() }
        .alert("记笔记", isPresented: $showNote) {
            TextField("笔记内容", text: $noteText)
            Button("取消", role: .cancel) { noteText = "" }
            Button("保存") {
                session.addNote(text: noteText)
                noteText = ""
            }
        }
    }
}

private struct TextCatalogSheet: View {
    @EnvironmentObject private var session: TextReaderSession
    @EnvironmentObject private var store: TextReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var query = ""

    private var hits: [TextSearchHit] {
        TextSearchEngine.search(query: query, chapters: session.chapters)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("目录").tag(0)
                    Text("书签").tag(1)
                    Text("笔记").tag(2)
                    Text("搜索").tag(3)
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch tab {
                    case 0: chapterList
                    case 1: bookmarkList
                    case 2: noteList
                    default: searchList
                    }
                }
            }
            .navigationTitle("目录与标注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var chapterList: some View {
        List(session.chapters.indices, id: \.self) { index in
            Button {
                session.goChapter(index, paragraph: index == session.chapterIndex ? nil : 0)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: index == session.chapterIndex ? "checkmark.circle.fill" : "circle")
                    Text(session.chapters[index].title)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var bookmarkList: some View {
        List {
            if let book = session.book {
                ForEach(store.bookmarks(in: book.id)) { mark in
                    Button {
                        session.goChapter(mark.chapterIndex, paragraph: mark.paragraph)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mark.chapterTitle).font(.subheadline.weight(.medium))
                            Text("第 \(mark.paragraph + 1) 段 · \(mark.preview)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) { store.removeBookmark(mark) }
                    }
                }
            }
        }
    }

    private var noteList: some View {
        List {
            if let book = session.book {
                ForEach(store.notes(in: book.id)) { note in
                    Button {
                        session.goChapter(note.chapterIndex, paragraph: note.paragraph)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.chapterTitle).font(.subheadline.weight(.medium))
                            Text(note.text.isEmpty ? "（空笔记）" : note.text)
                                .font(.caption)
                                .lineLimit(3)
                        }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) { store.removeNote(note) }
                    }
                }
            }
        }
    }

    private var searchList: some View {
        List {
            TextField("至少输入 2 个字", text: $query)
                .textFieldStyle(.roundedBorder)
            if query.count >= 2 {
                ForEach(hits) { hit in
                    Button {
                        session.goChapter(hit.chapterIndex, paragraph: hit.paragraph)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hit.chapterTitle).font(.subheadline.weight(.medium))
                            Text(hit.snippet).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
