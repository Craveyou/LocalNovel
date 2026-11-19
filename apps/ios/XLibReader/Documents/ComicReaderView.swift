import AppleShared
import SwiftUI

struct ComicReaderView: View {
    let book: Book
    let store: LibraryStore
    @Bindable var settings: SettingsStore
    @Environment(ProgressSyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: DocumentReaderModel?
    @State private var menuVisible = false
    @State private var progressVisible = false
    @State private var sheet: Panel?
    @State private var cloudDelete = false
    @State private var cloudDeleteAfterDismiss = false
    @State private var bookmarkDelete: DocumentBookmark?
    @State private var operationMessage: String?
    @State private var externalLink: URL?
    private var isKindle: Bool { book.format == "kindle" }
    private enum Panel: String, Identifiable {
        case pages, bookmarks, options, search
        var id: String { rawValue }
        var title: String { switch self { case .pages: "目录"; case .bookmarks: "书签"; case .options: "阅读设置"; case .search: "搜索原文" } }
    }
    private var theme: AppTheme { settings.settings.theme }

    var body: some View {
        Group {
            if let model { reader(model) }
            else { ProgressView("正在打开文档…") }
        }
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.text).tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .toolbar(.hidden, for: .navigationBar)
        .background(XLInteractivePopGestureEnabler())
        .task {
            guard model == nil else { return }
            let value = DocumentReaderModel(book: book, store: store, sync: sync)
            model = value; updateIdleTimer()
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if let id = environment["XLIB_UI_TEST_ID"], UUID(uuidString: id) != nil,
               environment["XLIB_UI_COMIC_MISSING_SOURCE"] == "1" {
                let url = await store.url(for: book)
                // Only the isolated UI fixture container may lose its source.
                if url.path.contains("/XLibUITests-\(id)/Books/") { try? FileManager.default.removeItem(at: url) }
            }
            #endif
            await value.open()
        }
        .onDisappear { model?.close(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, value in
            guard value != .inactive else { return }
            model?.setActive(value == .active); updateIdleTimer()
        }
        .onChange(of: settings.settings.keepScreenAwake) { _, _ in updateIdleTimer() }
        .onChange(of: settings.settings) { _, _ in model?.reflow() }
        .task(id: operationMessage) {
            guard operationMessage != nil else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            operationMessage = nil
        }
    }

    private func reader(_ model: DocumentReaderModel) -> some View {
        ZStack {
            theme.background.ignoresSafeArea()
            if model.loading { ProgressView("正在读取原文件…") }
            else if let failure = model.openFailure {
                ContentUnavailableView {
                    Label(isKindle ? "文档暂时无法打开" : "漫画暂时无法打开", systemImage: "doc.badge.exclamationmark")
                } description: { Text(failure) } actions: {
                    Button("重试打开") { Task { await model.open() } }
                    Button("返回书架") { dismiss() }
                }
            } else if let reflow = model.reflowDocument {
                EPUBReadingSurface(document:reflow,model:model,settings:settings.settings,link:{ handleLink($0,model:model) },tapped:{ menuVisible.toggle() },interactionEnabled:!menuVisible && !progressVisible)
            } else if let comic = model.comic {
                ComicReadingSurface(document: comic, model: model, fitWidth: settings.settings.comicFitWidth, theme: theme, interactionEnabled: !menuVisible && !progressVisible,
                    tapped: { action in
                        if menuVisible { menuVisible = false; return }
                        switch action {
                        case .toggleMenu: menuVisible = true
                        case .previousPage: turn(-1, model: model)
                        case .nextPage: turn(1, model: model)
                        }
                    }, swiped: { turn($0, model: model) })
            }
            if model.preparingSync { ProgressView("正在比较阅读进度…").padding().background(theme.surface, in: RoundedRectangle(cornerRadius: 12)) }
            if model.rendering { ProgressView("正在准备正文…").padding().background(theme.surface, in: RoundedRectangle(cornerRadius: 12)).allowsHitTesting(false) }
            if !model.selection.isEmpty {
                VStack { Spacer(); HStack {
                    Button("复制") { UIPasteboard.general.string = model.selection; model.selection = ""; operationMessage = "已复制" }
                        .accessibilityIdentifier("document.copySelection").accessibilityValue(model.selection)
                    Button("取消") { model.selection = "" }.accessibilityIdentifier("document.cancelSelection")
                }.padding(12).background(theme.surface,in:Capsule()).padding(.bottom,80) }
            }
            if model.loading {
                VStack { HStack {
                    XLIconButton(theme: theme, size: 44, action: { dismiss() }) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("回到书架")
                    Spacer()
                }; Spacer() }.padding(12)
            }
            if menuVisible { chrome(model) }
            if let operationMessage {
                Text(operationMessage).font(.footnote).padding(12).background(theme.surface, in: Capsule())
                    .accessibilityIdentifier("comic.operationMessage").allowsHitTesting(false)
            }
            if progressVisible {
                Color.black.opacity(0.34).ignoresSafeArea().onTapGesture { progressVisible = false }
                VStack { Spacer(); ReaderProgressSelectionPanel(progress: model.current?.progress ?? 0, theme: theme) { value in
                    guard model.canNavigate else { return }
                    if let kindle = model.kindle {
                        let offset = Int((value * Double(kindle.canonicalText.utf16.count)).rounded())
                        let raw = DocumentLocator.kindle(textHash:kindle.textHash,textOffset:offset,textLength:kindle.canonicalText.utf16.count)
                        if let unit = kindle.chapterIndex(for:raw), let local = kindle.localOffset(for:raw) { model.navigate(kindle.locator(chapter:unit,offset:local)) }
                    } else if let comic = model.comic {
                        let page = Self.page(for: value, count: model.count)
                        if let locator = try? comic.manifest.locator(format: comic.format, page: page) { model.navigate(locator) }
                    }
                    progressVisible = false
                } }.ignoresSafeArea(edges: .bottom)
            }
        }
        .sheet(item: $sheet, onDismiss: {
            model.cancelSearch()
            if cloudDeleteAfterDismiss { cloudDeleteAfterDismiss = false; cloudDelete = true }
        }) { panel in
            VStack(spacing: 10) {
                XLGlassToolbar(theme: theme, cornerRadius: 22, padding: 6) {
                    HStack {
                        Text(panel.title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        Button("完成") { sheet = nil }.foregroundStyle(theme.accent).frame(minWidth: 44, minHeight: 44)
                    }
                }.padding(.horizontal, 12).padding(.top, 10)
                panelContent(panel, model: model)
            }
            .background(theme.background).foregroundStyle(theme.text).tint(theme.accent)
            .preferredColorScheme(theme.colorScheme)
            .alert("操作未完成", isPresented: Binding(get: { model.error != nil && sheet != nil }, set: { if !$0 { model.error = nil } })) {
                Button("好") { model.error = nil }
            } message: { Text(model.error ?? "") }
            .confirmationDialog("删除书签？", isPresented: Binding(get: { bookmarkDelete != nil }, set: { if !$0 { bookmarkDelete = nil } }), titleVisibility: .visible) {
                Button("删除书签", role: .destructive) { if let value = bookmarkDelete { Task { await model.removeBookmark(value) } }; bookmarkDelete = nil }
                Button("取消", role: .cancel) { bookmarkDelete = nil }
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil && sheet == nil }, set: { if !$0 { model.error = nil } })) {
            Button("好") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("发现更新的云端位置", isPresented: Binding(get: { model.remote != nil }, set: { _ in })) {
            Button("采用云端位置") { model.acceptRemote() }
            Button("保留当前位置", role: .cancel) { model.rejectRemote() }
        } message: {
            Text("当前：\(model.formal.map(model.description) ?? "未知")\n云端：\(model.remote.map { model.description($0.locator) } ?? "未知")")
        }
        .confirmationDialog("删除此书的云端阅读进度？", isPresented: $cloudDelete, titleVisibility: .visible) {
            Button("删除云端进度", role: .destructive) { Task { await model.deleteCloud() } }
            Button("取消", role: .cancel) {}
        } message: { Text("保留本地书籍和阅读位置；成功后本次阅读暂停上传，退出重开后恢复比较。") }
        .confirmationDialog("在浏览器中打开外部链接？",isPresented:Binding(get:{externalLink != nil},set:{if !$0 {externalLink = nil}}),titleVisibility:.visible) {
            Button("打开") { if let externalLink { UIApplication.shared.open(externalLink) }; externalLink = nil }
            Button("取消",role:.cancel) { externalLink = nil }
        } message: { Text(externalLink?.absoluteString ?? "") }
    }

    private func chrome(_ model: DocumentReaderModel) -> some View {
        VStack(spacing: 0) {
            XLGlassToolbar(theme: theme, cornerRadius: 22, padding: 8) {
                HStack(spacing: 0) {
                    XLIconButton(theme: theme, size: 42, action: { dismiss() }) { Image(systemName: "chevron.left") }.accessibilityLabel("回到书架")
                    Text(book.title).lineLimit(1).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    XLIconButton(theme: theme, size: 42, action: { settings.update { $0.theme = $0.theme == .light ? .dark : .light } }) {
                        Image(systemName: theme == .dark ? "sun.max.fill" : "moon.fill")
                    }.accessibilityLabel("切换主题")
                    XLIconButton(theme: theme, size: 42, foreground: settings.settings.keepScreenAwake ? theme.accent : theme.text, action: { settings.update { $0.keepScreenAwake.toggle() } }) {
                        Image(systemName: settings.settings.screenLockIconName)
                    }.accessibilityLabel("阅读时锁屏").accessibilityValue(settings.settings.keepScreenAwake ? "开启" : "关闭")
                    XLIconButton(theme: theme, size: 42, action: { sheet = .options }) { Image(systemName: "gearshape") }.accessibilityLabel("阅读设置")
                }
            }.shadow(color: .black.opacity(theme == .dark ? 0.45 : 0.16), radius: 8, y: 3)
                .padding(.horizontal, 8).padding(.top, 8)
            Spacer()
            if model.temporary { Button("返回正式阅读位置") { model.returnToFormal() }.padding(8).background(theme.surface, in: Capsule()) }
            Text(model.preparingSync ? "正在比较云端位置…" : model.syncMessage).font(.caption2).padding(6).background(theme.surface, in: Capsule())
            XLGlassToolbar(theme: theme, cornerRadius: 24, padding: 10) {
                HStack(spacing: 4) {
                    if isKindle {
                        XLIconButton(theme:theme,size:44,action:{sheet = .search}) {Image(systemName:"magnifyingglass")}.accessibilityLabel("搜索")
                    }
                    XLIconButton(theme: theme, size: 44, action: { sheet = .pages }) { Image(systemName: "list.bullet") }.accessibilityLabel("目录")
                    XLIconButton(theme: theme, size: 44, action: { Task {
                        if await model.addBookmark() { operationMessage = "书签已保存" }
                    } }) { Image(systemName: "bookmark") }.accessibilityLabel("添加书签")
                        .disabled(!model.canNavigate || model.rendering)
                    XLIconButton(theme: theme, size: 44, action: { sheet = .bookmarks }) { Image(systemName: "bookmark.fill") }.accessibilityLabel("书签")
                    Spacer(minLength: 4)
                    Button { progressVisible = true } label: {
                        ReaderProgressLabel(progress: model.current?.progress ?? 0, theme: theme).padding(.horizontal, 8).frame(minHeight: 44)
                    }.buttonStyle(.borderless).accessibilityLabel("选择阅读进度").accessibilityIdentifier("reader.progressButton")
                        .accessibilityValue(Text(model.current?.progress ?? 0, format: .percent.precision(.fractionLength(2))))
                        .disabled(!model.canNavigate || model.rendering)
                }
            }.shadow(color: .black.opacity(theme == .dark ? 0.48 : 0.18), radius: 10, y: 4)
                .padding(.horizontal, 12).padding(.bottom, 8)
            Text(model.current.map(model.description) ?? "").font(.caption).accessibilityIdentifier("document.position")
        }.tint(theme.accent)
    }

    @ViewBuilder private func panelContent(_ panel: Panel, model: DocumentReaderModel) -> some View {
        switch panel {
        case .pages:
            if let reflow = model.reflowDocument {
                List(Array(reflow.toc.enumerated()),id:\.offset) { _,entry in
                    Button(entry.title) { model.navigate(reflow.locator(chapter:entry.chapter,offset:entry.offset)); sheet = nil; menuVisible = false }
                        .disabled(!model.canNavigate).listRowBackground(theme.surface)
                }.scrollContentBackground(.hidden).overlay { if reflow.toc.isEmpty { Text("此书没有有效内置目录").foregroundStyle(theme.secondaryText) } }
            } else {
            List(0..<model.count, id: \.self) { page in
                Button("第 \(page + 1) 页") {
                    if let comic = model.comic, let locator = try? comic.manifest.locator(format: comic.format, page: page) { model.navigate(locator); sheet = nil; menuVisible = false }
                }.disabled(!model.canNavigate || model.rendering).listRowBackground(theme.surface)
            }.scrollContentBackground(.hidden)
            }
        case .bookmarks:
            List(model.bookmarks) { bookmark in
                Button(model.description(bookmark.locator)) { model.navigate(bookmark.locator, preview: true); sheet = nil; menuVisible = true }
                    .disabled(!model.canNavigate || model.rendering)
                    .accessibilityIdentifier("comic.bookmark.\(bookmark.id)")
                    .listRowBackground(theme.surface)
                    .swipeActions { Button("删除", role: .destructive) { bookmarkDelete = bookmark } }
            }.scrollContentBackground(.hidden).overlay {
                if model.bookmarks.isEmpty {
                    Text("还没有书签\n在阅读页点击书签按钮即可保存当前位置")
                        .font(.system(size: 15)).foregroundStyle(theme.secondaryText).multilineTextAlignment(.center).lineSpacing(6)
                        .accessibilityIdentifier("comic.emptyBookmarks")
                }
            }
        case .options:
            ScrollView {
                VStack(spacing: 18) {
                    if isKindle {
                        SettingsSection(title:"排版",theme:theme) {
                            Stepper("字号 \(Int(settings.settings.fontSize))",value:Binding(get:{settings.settings.fontSize},set:{v in settings.update{$0.fontSize = v}}),in:14...34,step:2).padding(.vertical,12).accessibilityIdentifier("document.fontSize")
                            SettingsDivider(theme:theme)
                            Stepper("行距 \(Int(settings.settings.lineSpacing))",value:Binding(get:{settings.settings.lineSpacing},set:{v in settings.update{$0.lineSpacing = v}}),in:0...12).padding(.vertical,12)
                            SettingsDivider(theme:theme)
                            Picker("字体",selection:Binding(get:{settings.settings.fontName},set:{v in settings.update{$0.fontName = v}})) {
                                Text("系统").tag(".AppleSystemUIFont"); Text("黑体").tag("PingFangSC-Regular"); Text("宋体").tag("Songti SC"); Text("仿宋").tag("FangSong"); Text("等宽").tag("Menlo")
                            }.padding(.vertical,12)
                        }
                    } else {
                    SettingsSection(title: "漫画阅读", theme: theme) {
                        Toggle("从右向左翻页", isOn: Binding(get: { settings.settings.comicRightToLeft }, set: { value in settings.update { $0.comicRightToLeft = value } }))
                            .padding(.vertical, 12).accessibilityIdentifier("comic.rightToLeft")
                        SettingsDivider(theme: theme)
                        Toggle("适合宽度", isOn: Binding(get: { settings.settings.comicFitWidth }, set: { value in settings.update { $0.comicFitWidth = value } }))
                            .padding(.vertical, 12).accessibilityIdentifier("comic.fitWidth")
                    }
                    Text("关闭适合宽度后显示整页；双指缩放、单指拖动查看图片。")
                        .font(.footnote).foregroundStyle(theme.secondaryText).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
                    SettingsSection(title: "正文能力", theme: theme) {
                        Text("图片漫画暂不支持正文搜索/复制；不执行 OCR。")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                    }
                    }
                    SettingsSection(title: "阅读进度同步", theme: theme) {
                        Text(model.preparingSync ? "正在比较云端位置…" : model.syncMessage)
                            .font(.footnote).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                        SettingsDivider(theme: theme)
                        Button("刷新同步") { Task { await model.compare() } }
                            .foregroundStyle(theme.accent).frame(maxWidth: .infinity, minHeight: 48).disabled(!model.canNavigate || model.rendering)
                        SettingsDivider(theme: theme)
                        Button("删除此书云端进度", role: .destructive) { cloudDeleteAfterDismiss = true; sheet = nil }
                            .foregroundStyle(.red).frame(maxWidth: .infinity, minHeight: 48).disabled(!model.canNavigate || model.rendering)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 20)
            }
        case .search:
            search(model)
        }
    }
    private func search(_ model:DocumentReaderModel) -> some View {
        @Bindable var reader = model
        return VStack {
            HStack {
                TextField("2–32 个字素簇",text:$reader.query).textFieldStyle(.roundedBorder).accessibilityIdentifier("document.searchQuery").onSubmit {model.search(reset:true)}
                Button("搜索") {model.search(reset:true)}.accessibilityIdentifier("document.searchStart")
            }.padding(.horizontal,12)
            Button("从书首搜索") {model.search(reset:true,fromBeginning:true)}.accessibilityIdentifier("document.searchFromBeginning")
            List(Array(model.hits.enumerated()),id:\.offset) { _,hit in
                Button(hit.excerpt) {model.showHit(hit);sheet = nil;menuVisible = true}.listRowBackground(theme.surface)
                    .accessibilityIdentifier("document.searchHit.\(hit.unit).\(hit.offset)")
            }.scrollContentBackground(.hidden)
            Text(model.searching ? "正在搜索…" : "\(model.hits.count) 条结果").font(.caption).accessibilityIdentifier("document.searchStatus")
            if model.searching { Button("停止搜索") {model.cancelSearch()} }
            else if !model.searchExhausted && !model.hits.isEmpty {Button("继续加载 200 条") {model.search()} }
            else if model.searchCanWrap {Button("已到书尾，从书首回绕") {model.search(wrap:true)} }
            else if model.searchExhausted {Text("已完成一轮搜索").font(.caption)}
        }
    }
    private func handleLink(_ url:URL,model:DocumentReaderModel) {
        if url.scheme == "xlib-book",url.host == "book.xlib.invalid",let document = model.reflowDocument {
            let path = String(url.path.dropFirst()),fragment = URLComponents(url:url,resolvingAgainstBaseURL:false)?.fragment
            guard let unit = document.chapters.firstIndex(where:{$0.resource == path}),fragment == nil || document.chapters[unit].anchors[fragment!] != nil else { model.error = "链接内容锚点无效"; return }
            model.navigate(document.locator(chapter:unit,offset:fragment.flatMap{document.chapters[unit].anchors[$0]} ?? 0))
        } else if ["https","http"].contains(url.scheme?.lowercased() ?? "") { externalLink = url }
        else { model.error = "此链接类型暂不支持" }
    }
    private func turn(_ delta: Int, model: DocumentReaderModel) {
        guard !menuVisible, !progressVisible else { return }
        model.moveUnit(settings.settings.comicRightToLeft ? -delta : delta)
    }
    private func updateIdleTimer() { UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && settings.settings.keepScreenAwake }
    static func page(for progress: Double, count: Int) -> Int {
        guard count > 0, progress.isFinite else { return 0 }
        return min(count - 1, max(0, Int(ceil(min(1, max(0, progress)) * Double(count))) - 1))
    }
}
