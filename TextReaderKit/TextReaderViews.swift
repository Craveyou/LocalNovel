import SwiftUI
import UniformTypeIdentifiers
import UIKit

public struct TextReaderRootView: View {
    @StateObject private var library: TextLibraryStore
    @StateObject private var session = TextReaderSession()
    @State private var importError: String?
    @State private var showImportError = false
    @State private var debugLog: [String] = []
    @State private var showDebug = false
    /// 命令式弹出的文档选择器 delegate 必须强持有到回调结束，
    /// 否则回调被丢弃 —— 这正是之前 sheet 方案「点打开无反应」的根因。
    @State private var pickerKeeper: NSObject?

    public init(bundledBooks: [TextBook] = []) {
        _library = StateObject(wrappedValue: TextLibraryStore(bundled: bundledBooks))
    }

    private func log(_ line: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLog.append("[\(stamp)] \(line)")
        if debugLog.count > 300 { debugLog.removeFirst(debugLog.count - 300) }
    }

    private func handlePicked(_ urls: [URL]) {
        pickerKeeper = nil
        guard !urls.isEmpty else {
            log("选择器：用户取消")
            return
        }
        log("选择器回调：\(urls.count) 个文件")
        for url in urls {
            log("  来源路径：\(url.path)")
        }
        let failures = urls.compactMap { library.importBook(from: $0) }
        if let first = failures.first {
            importError = failures.count == 1
                ? first
                : "\(failures.count) 个文件导入失败，例如：\(first)"
            showImportError = true
        }
    }

    /// 不经 sheet、不经 SwiftUI 包装，直接把 UIKit 选择器压到当前视图栈顶。
    /// delegate 由 pickerKeeper 强持有，回调保证可达。
    /// asCopy: true = 系统直接把选中文件拷贝进 App 沙盒（tmp），
    /// 不依赖文件提供方授权 —— 对「最近项目」/网盘里的文件成功率高得多。
    private func presentPicker() {
        log("准备弹出文档选择器（拷贝模式）")
        let coordinator = PickerCoordinator(onPick: handlePicked)
        coordinator.onEvent = { line in log(line) }
        pickerKeeper = coordinator
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: Self.importableTypes,
                                                    asCopy: true)
        picker.delegate = coordinator
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var top = scene.keyWindow?.rootViewController else {
            log("错误：找不到根视图控制器")
            return
        }
        while let presented = top.presentedViewController { top = presented }
        top.present(picker, animated: true)
        log("选择器已弹出")
    }

    public var body: some View {
        NavigationStack {
            Group {
                if library.books.isEmpty {
                    ContentUnavailableView("书架空空", systemImage: "book",
                                           description: Text("右上角 + 导入 txt 小说"))
                } else {
                    List {
                        ForEach(library.books) { book in
                            NavigationLink(value: book) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title).font(.headline)
                                    Text(library.isImported(book) ? "导入的书" : "内置样例")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                library.remove(library.books[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("纯文本小说")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentPicker()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("导入小说")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDebug = true
                    } label: {
                        Image(systemName: "terminal")
                    }
                    .accessibilityLabel("调试日志")
                }
            }
            .navigationDestination(for: TextBook.self) { book in
                TextReaderView()
                    .onAppear {
                        if session.book?.id != book.id { session.open(book) }
                    }
            }
            .onOpenURL { url in
                // 第二条导入路：文件 App 里分享 → 拷贝到本 App
                log("外部打开：\(url.lastPathComponent)")
                if let failure = library.importBook(from: url) {
                    importError = failure
                    showImportError = true
                }
            }
            .onAppear { library.onLog = log }
            .alert("导入失败", isPresented: $showImportError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .sheet(isPresented: $showDebug) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if debugLog.isEmpty {
                                Text("暂无日志。点 + 导入一次，这里会显示每一步。")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(debugLog.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding()
                    }
                    .navigationTitle("调试日志")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showDebug = false }
                        }
                        ToolbarItem(placement: .destructiveAction) {
                            Button("清空") { debugLog.removeAll() }
                        }
                    }
                }
            }
        }
        .environmentObject(session)
        .environmentObject(session.store)
    }

    /// txt / md / text；兜底放行 data，避免个别系统把 txt 标成冷门 UTI 选不了。
    private static let importableTypes: [UTType] = [.plainText, .data]
}

final class PickerCoordinator: NSObject, UIDocumentPickerDelegate {
    let onPick: ([URL]) -> Void
    var onEvent: ((String) -> Void)?

    init(onPick: @escaping ([URL]) -> Void) {
        self.onPick = onPick
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        onEvent?("系统回调：didPick（\(urls.count) 个）")
        DispatchQueue.main.async { self.onPick(urls) }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onEvent?("系统回调：wasCancelled（用户取消或文件提供方拒绝授权）")
        DispatchQueue.main.async { self.onPick([]) }
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
