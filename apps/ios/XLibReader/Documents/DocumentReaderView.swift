import AppleShared
import SwiftUI
import PDFKit
import WebKit

struct DocumentReaderView: View {
    let book: Book
    let store: LibraryStore
    @Bindable var settings: SettingsStore
    @Environment(ProgressSyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: DocumentReaderModel?
    @State private var password = ""
    @State private var sheet: ReaderSheet?
    @State private var jumpPage = ""
    @State private var confirmCloudDelete = false
    @State private var externalLink: URL?
    @State private var deletedBookmark: DocumentBookmark?
    private enum ReaderSheet: String, Identifiable { case search, bookmarks, contents, preferences, pdfCrop; var id:String { rawValue } }
    var body: some View {
        Group {
            if let model { reader(model) }
            else { ProgressView("正在打开文档…") }
        }
        .task {
            UIApplication.shared.isIdleTimerDisabled = settings.settings.keepScreenAwake
            guard model == nil else { return }
            let reader = DocumentReaderModel(book:book,store:store,sync:sync,cropState:settings.pdfCropState); model = reader
            await reader.open()
        }
        .onDisappear { password = ""; model?.close(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of:scenePhase) { _, phase in
            guard phase != .inactive else { return }
            model?.setActive(phase == .active)
            UIApplication.shared.isIdleTimerDisabled = phase == .active && settings.settings.keepScreenAwake
        }
        .onChange(of:settings.settings) { _, value in
            UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && value.keepScreenAwake
            model?.reflow()
        }
        .toolbar(.hidden,for:.navigationBar)
        .background(settings.settings.theme.background)
    }
    private func reader(_ model: DocumentReaderModel) -> some View {
        @Bindable var reader = model
        return VStack(spacing:0) {
            HStack {
                Button { dismiss() } label: { Image(systemName:"chevron.left").padding(10) }.accessibilityLabel("返回书架")
                Text(book.title).font(.headline).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                Menu {
                    Button("搜索") { sheet = .search }
                    Button("书签") { sheet = .bookmarks }
                    Button("添加书签") { Task { await model.addBookmark() } }
                    if model.pdf != nil {
                        Button("PDF 裁边", systemImage: "crop") { sheet = .pdfCrop }
                            .accessibilityIdentifier("document.pdfCrop")
                    }
                    if model.reflowDocument != nil {
                        Button("目录") { sheet = .contents }
                        Button("排版") { sheet = .preferences }
                    }
                    Button("刷新同步") { Task { await model.compare() } }
                    Button("删除此书云端进度",role:.destructive) { confirmCloudDelete = true }
                } label: { Image(systemName:"ellipsis.circle").padding(10) }
                .accessibilityLabel("文档菜单").disabled(!model.ready)
            }.padding(.horizontal,6)
            if model.loading { ProgressView("正在读取原文件…").frame(maxWidth:.infinity,maxHeight:.infinity) }
            else if let failure = model.openFailure {
                ContentUnavailableView {
                    Label("文档暂时无法打开",systemImage:"doc.badge.exclamationmark")
                } description: { Text(failure) } actions: {
                    Button("重试打开") { Task { await model.open() } }.accessibilityIdentifier("document.retryOpen")
                }
            }
            else if !model.needsPassword {
                if let pdf = model.pdf {
                    PDFReadingSurface(document:pdf,model:model)
                } else if let epub = model.reflowDocument {
                    EPUBReadingSurface(document:epub,model:model,settings:settings.settings,link:{ handleLink($0,model:model) })
                }
            } else { ContentUnavailableView("需要打开密码",systemImage:"lock.doc",description:Text("密码仅用于本次阅读，关闭后需要重新输入")) }
            if let notice = model.textNotice { Text(notice).font(.caption).padding(6).frame(maxWidth:.infinity).background(settings.settings.theme.surfaceVariant) }
            if !model.selection.isEmpty {
                HStack {
                    Button("复制") { UIPasteboard.general.string = model.selection; model.selection = "" }
                        .accessibilityIdentifier("document.copySelection").accessibilityValue(model.selection)
                    Button("取消选取") { model.selection = "" }
                        .accessibilityIdentifier("document.cancelSelection")
                }.padding(8)
            }
            if model.temporary { Button("返回正式阅读位置") { model.returnToFormal() }.padding(8) }
            HStack {
                Button(model.pdf != nil ? "上一页" : "上一章") { model.moveUnit(-1) }.disabled(!model.canNavigate || model.currentUnit == 0)
                Spacer()
                if let current = model.current { Text(model.description(current)).font(.caption).lineLimit(2).multilineTextAlignment(.center).accessibilityIdentifier("document.position") }
                Spacer()
                Button(model.pdf != nil ? "下一页" : "下一章") { model.moveUnit(1) }.disabled(!model.canNavigate || model.currentUnit == model.count - 1)
            }.padding(10)
            if model.pdf != nil {
                HStack { TextField("页码",text:$jumpPage).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width:90)
                    Button("前往") {
                        guard let page = Int(jumpPage), (1...model.count).contains(page) else { model.error = "请输入有效页码"; return }
                        model.navigate(.pdf(page:page-1,pageCount:model.count,y:0)); jumpPage = ""; UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
                    }.disabled(!model.canNavigate)
                }.padding(.bottom,5)
            }
            Text(model.preparingSync ? "正在比较云端位置…" : model.syncMessage).font(.caption2).padding(4)
        }
        .foregroundStyle(settings.settings.theme.text).tint(settings.settings.theme.accent)
        .sheet(item:$sheet) { selected in
            NavigationStack {
                Group {
                    switch selected {
                    case .search: search(model)
                    case .bookmarks: bookmarks(model)
                    case .contents:
                        List(Array((model.reflowDocument?.toc ?? []).enumerated()),id:\.offset) { _, entry in
                            Button(entry.title) { if let epub = model.reflowDocument { model.navigate(epub.locator(chapter:entry.chapter,offset:entry.offset)); sheet = nil } }
                        }.overlay { if model.reflowDocument?.toc.isEmpty == true { ContentUnavailableView("此书没有有效内置目录",systemImage:"list.bullet") } }.navigationTitle("目录")
                    case .preferences: preferences
                    case .pdfCrop: PDFCropControls(model: model)
                    }
                }.toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { model.cancelSearch(); sheet = nil } } }
            }
            .presentationDetents(selected == .pdfCrop ? [.height(360), .large] : [.large])
            .alert("操作未完成",isPresented:Binding(get:{model.error != nil && sheet != nil},set:{if !$0 {model.error = nil}})) {
                Button("好") {model.error = nil}
            } message: {Text(model.error ?? "")}
            .confirmationDialog("删除书签？",isPresented:Binding(get:{deletedBookmark != nil},set:{if !$0 {deletedBookmark = nil}}),titleVisibility:.visible) {
                Button("删除",role:.destructive) { if let bookmark = deletedBookmark { Task { await model.removeBookmark(bookmark) } }; deletedBookmark = nil }
            }
            .onDisappear { model.cancelSearch() }
        }
        .alert(model.passwordError ? "密码错误，请重试" : "请输入 PDF 打开密码",isPresented:$reader.needsPassword) {
            SecureField("密码",text:$password).textContentType(.password).autocorrectionDisabled()
            Button("打开") { let value = password; password = ""; Task { await model.unlock(value) } }
            Button("取消",role:.cancel) { password = ""; dismiss() }
        } message: { Text("密码仅保留在当前会话内存中") }
        .alert("操作未完成",isPresented:Binding(get:{model.error != nil && sheet == nil},set:{if !$0 {model.error = nil}})) { Button("好") {model.error = nil} } message: {Text(model.error ?? "")}
        .alert("发现更新的云端位置",isPresented:Binding(get:{model.remote != nil},set:{_ in})) {
            Button("采用云端位置") { model.acceptRemote() }
            Button("保留当前位置",role:.cancel) { model.rejectRemote() }
        } message: {
            Text("当前：\(model.formal.map(model.description) ?? "")\n云端：\(model.remote.map {model.description($0.locator)} ?? "")")
        }
        .confirmationDialog("删除此书的云端阅读进度？",isPresented:$confirmCloudDelete,titleVisibility:.visible) {
            Button("删除云端进度",role:.destructive) { Task { await model.deleteCloud() } }
        } message: {Text("保留本地书籍和阅读位置；成功后本次阅读暂停上传，退出重开后恢复比较。")}
        .confirmationDialog("在浏览器中打开外部链接？",isPresented:Binding(get:{externalLink != nil},set:{if !$0 {externalLink = nil}}),titleVisibility:.visible) {
            Button("打开") { if let externalLink { UIApplication.shared.open(externalLink) }; externalLink = nil }
        } message: { Text(externalLink?.absoluteString ?? "") }
    }
    private func search(_ model: DocumentReaderModel) -> some View {
        @Bindable var reader = model
        return VStack {
            HStack { TextField("2–32 个字素簇",text:$reader.query).accessibilityIdentifier("document.searchQuery").textFieldStyle(.roundedBorder).onSubmit { model.search(reset:true) }; Button("搜索") {model.search(reset:true)}.accessibilityIdentifier("document.searchStart") }.padding()
            Button("从书首搜索") { model.search(reset:true,fromBeginning:true) }.accessibilityIdentifier("document.searchFromBeginning")
            List(Array(model.hits.enumerated()),id:\.offset) { _, hit in
                Button { model.showHit(hit); sheet = nil } label: { VStack(alignment:.leading) { Text("第 \(hit.unit + 1) \(model.pdf != nil ? "页" : "章")").font(.caption); Text(hit.excerpt).lineLimit(3) } }.accessibilityIdentifier("document.searchHit.\(hit.unit).\(hit.offset)")
            }
            Text(model.searching ? "正在搜索…" : "\(model.hits.count) 条结果").font(.caption).accessibilityIdentifier("document.searchStatus")
            if model.searching { HStack { ProgressView(); Button("停止搜索") { model.cancelSearch() } } }
            else if !model.hits.isEmpty || model.searchExhausted {
                if !model.searchExhausted { Button("继续加载 200 条") {model.search()} }
                else if model.searchCanWrap { Button("已到书尾，从书首回绕") {model.search(wrap:true)}.accessibilityIdentifier("document.searchWrap") }
                else { Text("已完成一轮搜索").font(.caption).accessibilityIdentifier("document.searchComplete") }
            }
        }.navigationTitle("搜索原文")
    }
    private func bookmarks(_ model: DocumentReaderModel) -> some View {
        List {
            Button("添加当前位置书签") { Task { await model.addBookmark() } }
            ForEach(model.bookmarks) { bookmark in
                Button(model.description(bookmark.locator)) {model.navigate(bookmark.locator);sheet = nil}
                    .accessibilityIdentifier("document.bookmark.\(bookmark.id)")
                    .swipeActions {Button("删除",role:.destructive) {deletedBookmark = bookmark}}
            }
            if model.bookmarks.isEmpty { Text("还没有书签").foregroundStyle(.secondary) }
        }.navigationTitle("本地书签")
    }
    private var preferences: some View {
        Form {
            Stepper("字号 \(Int(settings.settings.fontSize))",value:Binding(get:{settings.settings.fontSize},set:{value in settings.update {$0.fontSize = value}}),in:14...34,step:2)
                .accessibilityIdentifier("document.fontSize")
            Stepper("行距 \(Int(settings.settings.lineSpacing))",value:Binding(get:{settings.settings.lineSpacing},set:{value in settings.update {$0.lineSpacing = value}}),in:0...12)
            Picker("字体",selection:Binding(get:{settings.settings.fontName},set:{value in settings.update {$0.fontName = value}})) {
                Text("系统").tag(".AppleSystemUIFont"); Text("黑体").tag("PingFangSC-Regular")
                Text("宋体").tag("Songti SC"); Text("仿宋").tag("FangSong"); Text("等宽").tag("Menlo")
            }
            Picker("主题",selection:Binding(get:{settings.settings.theme},set:{value in settings.update {$0.theme = value}})) {Text("浅色").tag(AppTheme.light);Text("深色").tag(AppTheme.dark)}
        }.navigationTitle("EPUB 排版")
    }
    private func handleLink(_ url: URL, model: DocumentReaderModel) {
        if url.scheme == "xlib-book", let epub = model.reflowDocument {
            let path = String(url.path.dropFirst())
            guard let i = epub.chapters.firstIndex(where:{$0.resource == path}) else {model.error = "链接目标不在支持的正文范围内";return}
            let fragment = URLComponents(url:url,resolvingAgainstBaseURL:false)?.fragment
            guard fragment == nil || epub.chapters[i].anchors[fragment!] != nil else {model.error = "链接内容锚点无效";return}
            model.navigate(epub.locator(chapter:i,offset:fragment.flatMap{epub.chapters[i].anchors[$0]} ?? 0))
        } else if ["https","http"].contains(url.scheme?.lowercased() ?? "") { externalLink = url }
        else {model.error = "此链接类型暂不支持"}
    }
}

struct PDFReadingSurface: UIViewRepresentable {
    let document: PDFDocument
    let model: DocumentReaderModel
    func makeCoordinator() -> Coordinator { Coordinator(model:model) }
    func makeUIView(context:Context) -> PDFView {
        let view = PDFCropView();view.document = document;view.autoScales = true;view.displayBox = .cropBox;view.displayMode = .singlePageContinuous;view.displayDirection = .vertical;view.backgroundColor = .secondarySystemBackground
        view.accessibilityLabel = "PDF 正文"
        context.coordinator.view = view
        view.onWidthChange = { [weak coordinator = context.coordinator] in coordinator?.refitForWidthChange() }
        context.coordinator.observe()
        return view
    }
    func updateUIView(_ view:PDFView,context:Context) {
        let coordinator = context.coordinator
        if model.selection.isEmpty, view.currentSelection != nil, coordinator.selectionWasPresent {view.clearSelection();coordinator.selectionWasPresent = false}
        guard let command = model.command, coordinator.command != command.id || coordinator.cropNeedsUpdate, case .pdf(let p,_,let y) = command.locator, let page = document.page(at:p) else {return}
        coordinator.command = command.id; coordinator.restoring = true; coordinator.userMoved = false
        coordinator.applyCrop(around: page)
        view.go(to:page)
        DispatchQueue.main.async {
            guard coordinator.command == command.id else {return}
            view.layoutIfNeeded()
            coordinator.fitCropWidth(page)
            let rect = view.convert(coordinator.originalBounds(page),from:page)
            let point = view.convert(CGPoint(x:rect.midX,y:rect.minY+rect.height*y),to:page)
            view.go(to:PDFDestination(page:page,at:point))
            if let range = command.highlight, document.allowsCopying, let selection = page.selection(for:range) {view.setCurrentSelection(selection,animate:false);view.go(to:selection)}
            coordinator.centerCroppedPage(page)
            coordinator.restoring = false
            model.rendererCompleted(command.id,success:true)
        }
    }
    static func dismantleUIView(_ uiView:PDFView,coordinator:Coordinator) {coordinator.stop();uiView.document = nil}
    @MainActor final class Coordinator:NSObject {
        let model:DocumentReaderModel
        weak var view:PDFView?
        var command:UUID?
        var restoring = false
        var selectionWasPresent = false
        var userMoved = false
        weak var observedScroll:UIScrollView?
        var timer:Timer?
        private var originalBoxes: [Int: CGRect] = [:]
        private var appliedCrop: PDFCropSettings?
        var cropNeedsUpdate: Bool { appliedCrop != model.pdfCrop }
        private var applyingCrop = false
        init(model:DocumentReaderModel) {self.model = model}
        func observe() {
            NotificationCenter.default.addObserver(self,selector:#selector(selectionChanged),name:.PDFViewSelectionChanged,object:view)
            NotificationCenter.default.addObserver(self,selector:#selector(visiblePagesChanged),name:.PDFViewVisiblePagesChanged,object:view)
            observedScroll = view?.subviews.compactMap({$0 as? UIScrollView}).first
            observedScroll?.panGestureRecognizer.addTarget(self,action:#selector(panned(_:)))
            timer = Timer.scheduledTimer(withTimeInterval:0.3,repeats:true) {[weak self] _ in MainActor.assumeIsolated {self?.capture()}}
        }
        @objc private func panned(_ gesture:UIPanGestureRecognizer) {
            if gesture.state == .began,gesture.numberOfTouches == 1 {userMoved = true}
            if gesture.state == .ended || gesture.state == .cancelled {capture()}
        }
        @objc private func selectionChanged() {
            guard let view else {return}
            model.selection = view.document?.allowsCopying == true ? view.currentSelection?.string ?? "" : ""
            selectionWasPresent = !model.selection.isEmpty
        }
        func originalBounds(_ page: PDFPage) -> CGRect {
            guard let document = view?.document else { return page.bounds(for: .cropBox) }
            return originalBoxes[document.index(for: page)] ?? model.originalPDFBounds(page)
        }
        @discardableResult func applyCrop(around page: PDFPage) -> Bool {
            guard !applyingCrop, let view, let document = view.document else { return false }
            applyingCrop = true
            defer { applyingCrop = false }
            let crop = model.pdfCrop
            let changed = appliedCrop != crop
            var indexes = Set(view.visiblePages.map { document.index(for: $0) })
            let index = document.index(for: page)
            for i in max(0, index - 1)...min(document.pageCount - 1, index + 1) { indexes.insert(i) }
            if changed { indexes.formUnion(originalBoxes.keys) }
            var layoutChanged = false
            for i in indexes {
                guard let candidate = document.page(at: i) else { continue }
                let original = originalBoxes[i] ?? model.originalPDFBounds(candidate)
                // Lazy: never materialize every page of a large PDF to crop it.
                if crop.enabled { originalBoxes[i] = original }
                let bounds = crop.bounds(original: original, rotation: candidate.rotation)
                if candidate.bounds(for: .cropBox) != bounds {
                    candidate.setBounds(bounds, for: .cropBox)
                    layoutChanged = true
                }
            }
            appliedCrop = crop
            if layoutChanged { view.layoutDocumentView() }
            if changed, !crop.enabled, !originalBoxes.isEmpty { view.minScaleFactor = 0.01 }
            view.autoScales = !crop.enabled
            if changed, !crop.enabled, !originalBoxes.isEmpty { view.scaleFactor = view.scaleFactorForSizeToFit }
            return layoutChanged
        }
        func fitCropWidth(_ page: PDFPage) {
            guard model.pdfCrop.enabled, let view, view.bounds.width > 0 else { return }
            let box = page.bounds(for: .cropBox)
            let width = page.rotation % 180 == 0 ? box.width : box.height
            guard width > 0 else { return }
            let scale = view.bounds.width / width
            view.minScaleFactor = scale
            view.maxScaleFactor = max(scale * 4, view.maxScaleFactor)
            view.scaleFactor = scale
        }
        func centerCroppedPage(_ page: PDFPage) {
            guard model.pdfCrop.enabled, let view, let scroll = observedScroll else { return }
            let rect = view.convert(page.bounds(for: .cropBox), from: page)
            // PDFDestination positions its x coordinate at the viewport edge,
            // not its center. Correct only x; leave the original y anchor intact.
            let delta = rect.midX - view.bounds.midX
            let minimum = -scroll.adjustedContentInset.left
            let maximum = max(minimum, scroll.contentSize.width - scroll.bounds.width + scroll.adjustedContentInset.right)
            let x = min(maximum, max(minimum, scroll.contentOffset.x + delta))
            scroll.setContentOffset(CGPoint(x: x, y: scroll.contentOffset.y), animated: false)
        }
        func refitForWidthChange() {
            guard !restoring, model.pdfCrop.enabled, let view,
                  let page = view.page(for: CGPoint(x: view.bounds.midX, y: view.bounds.minY + 20), nearest: true) else { return }
            let anchor = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.minY + 20), to: page)
            restoring = true
            applyCrop(around: page)
            fitCropWidth(page)
            view.go(to: PDFDestination(page: page, at: anchor))
            centerCroppedPage(page)
            restoring = false
        }
        @objc private func visiblePagesChanged() {
            guard !restoring, !applyingCrop, model.pdfCrop.enabled, let view,
                  let page = view.page(for: CGPoint(x: view.bounds.midX, y: view.bounds.minY + 20), nearest: true) else { return }
            let anchor = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.minY + 20), to: page)
            restoring = true
            if applyCrop(around: page) {
                fitCropWidth(page)
                view.go(to: PDFDestination(page: page, at: anchor))
                centerCroppedPage(page)
            }
            restoring = false
        }
        private func capture() {
            guard userMoved,!restoring,let view,let document = view.document,let scroll = observedScroll,
                  !scroll.isZooming, view.currentSelection == nil else {return}
            let top = CGPoint(x:view.bounds.midX,y:view.bounds.minY+20)
            guard let page = view.page(for:top,nearest:true) else {return}
            let rect = view.convert(originalBounds(page),from:page)
            let y = min(1,max(0,(top.y-rect.minY)/max(1,rect.height)))
            guard let locator = try? DocumentLocator.pdf(page:document.index(for:page),pageCount:document.pageCount,y:y).validated() else {return}
            model.userScrolled(locator)
            if !scroll.isDragging && !scroll.isDecelerating {userMoved = false}
        }
        func stop() {
            timer?.invalidate();timer = nil
            observedScroll?.panGestureRecognizer.removeTarget(self,action:#selector(panned(_:)))
            observedScroll = nil;NotificationCenter.default.removeObserver(self)
            // This PDFDocument is session-owned; never write cropped boxes to disk.
            if let document = view?.document {
                for (index, box) in originalBoxes { document.page(at: index)?.setBounds(box, for: .cropBox) }
            }
            originalBoxes.removeAll()
        }
    }
}
