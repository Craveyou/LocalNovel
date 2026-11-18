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
                                LibraryBookRow(book: book,
                                               subtitle: library.isImported(book) ? "导入的书" : "内置样例")
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

/// 书架行：色块封面 + 书名 + 来源（对齐主 App 书架的观感）。
struct LibraryBookRow: View {
    let book: TextBook
    let subtitle: String

    private var coverColors: [Color] {
        let palette: [[Color]] = [
            [Color(red: 0.58, green: 0.44, blue: 0.86), Color(red: 0.42, green: 0.28, blue: 0.72)],
            [Color(red: 0.36, green: 0.62, blue: 0.82), Color(red: 0.22, green: 0.44, blue: 0.68)],
            [Color(red: 0.84, green: 0.55, blue: 0.40), Color(red: 0.68, green: 0.38, blue: 0.26)],
            [Color(red: 0.44, green: 0.70, blue: 0.50), Color(red: 0.28, green: 0.52, blue: 0.36)],
        ]
        var hash = 0
        for byte in book.title.utf8 { hash = (hash &* 31 &+ Int(byte)) & 0xFFFF }
        return palette[abs(hash) % palette.count]
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: coverColors,
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                Text(String(book.title.prefix(6)))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(5)
            }
            .frame(width: 48, height: 66)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("《\(book.title)》，\(subtitle)")
    }
}

// MARK: - 阅读器：全屏正文 + 页眉页脚 + 菜单浮层 + 目录抽屉

public struct TextReaderView: View {
    @EnvironmentObject private var session: TextReaderSession
    @Environment(\.dismiss) private var dismiss

    @State private var showMenu = false
    @State private var showCatalog = false
    @State private var showSearch = false
    @State private var showMore = false
    @State private var showTapEditor = false
    @State private var showSettingsPanel = false
    @State private var showThemePanel = false

    private var theme: TextTheme { session.settings.theme }

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            // 正文排版区：给页眉/页脚各留 44pt，左右各留 20pt 边距。
            let viewport = CGSize(width: max(geo.size.width - 40, 60),
                                  height: max(geo.size.height - 88, 100))
            ZStack {
                theme.background.ignoresSafeArea()
                content
                    .padding(.top, 44)
                    .padding(.bottom, 44)
                    .padding(.horizontal, 20)
                VStack(spacing: 0) {
                    ReaderHeader(theme: theme)
                    Spacer(minLength: 0)
                    ReaderFooter(theme: theme)
                }
                .allowsHitTesting(false)
                if showMenu {
                    ReaderMenuOverlay(isPresented: $showMenu,
                                      theme: theme,
                                      showSettingsPanel: $showSettingsPanel,
                                      showThemePanel: $showThemePanel,
                                      onCatalog: { showCatalog = true },
                                      onSearch: { showSearch = true },
                                      onBack: { dismiss() },
                                      onMoreSettings: {
                                          showMenu = false
                                          showMore = true
                                      },
                                      onTapZoneEditor: {
                                          showMenu = false
                                          showTapEditor = true
                                      })
                        .transition(.opacity)
                }
                if showTapEditor {
                    TapZoneEditorOverlay(isPresented: $showTapEditor, theme: theme)
                        .transition(.opacity)
                }
                if showCatalog {
                    catalogOverlay(width: geo.size.width)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showMenu)
            .animation(.easeInOut(duration: 0.25), value: showCatalog)
            .animation(.easeInOut(duration: 0.2), value: showTapEditor)
            .onAppear { session.setContentSize(viewport) }
            .onChange(of: geo.size) { _, newSize in
                session.setContentSize(CGSize(width: max(newSize.width - 40, 60),
                                              height: max(newSize.height - 88, 100)))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showMore) {
            MoreSettingsSheet(theme: theme)
                .environmentObject(session)
        }
        .sheet(isPresented: $showSearch) {
            ReaderSearchSheet(theme: theme, onJump: {})
                .environmentObject(session)
        }
        .onDisappear {
            if session.settings.keepAwake { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }

    // MARK: 正文

    @ViewBuilder
    private var content: some View {
        if session.mode == .paged {
            TextPagerView(theme: theme,
                          onTapMenu: { showMenu = true })
                .id(session.settings.transition)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(session.paragraphs.indices, id: \.self) { index in
                            Text(indented(session.paragraphs[index]))
                                .font(session.settings.fontDesign.swiftFont(size: session.settings.fontSize))
                                .foregroundStyle(theme.text)
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("p\(index)")
                                .onAppear { session.noteParagraph(index) }
                        }
                    }
                }
                .onTapGesture { showMenu = true }
                .onAppear {
                    proxy.scrollTo("p\(session.currentParagraph)", anchor: .top)
                }
            }
        }
    }

    private func indented(_ paragraph: String) -> String {
        guard session.settings.indentParagraphs, !paragraph.isEmpty else { return paragraph }
        return "　　" + paragraph
    }

    // MARK: 目录抽屉

    private func catalogOverlay(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { showCatalog = false }
                .accessibilityLabel("关闭目录")
            TextCatalogDrawer(theme: theme,
                              onClose: { showCatalog = false })
                .frame(width: width * 0.88)
                .environmentObject(session)
                .transition(.move(edge: .leading))
        }
    }
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
