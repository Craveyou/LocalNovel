import SwiftUI

// MARK: - NAS 上的书库三层
//
// 呈现刻意与本地书库一致：
//   书名列表   ≈ 书库分区里的书籍行（标题 + N 章）
//   章节列表   ≈ 章节栏（标题 + 类型，短剧的每集带「大小 · 时长」，有包名时分段）
//   阅读页     ≈ 阅读器（正文 → 插图 → 章末音视频）
//
// 所有内容都在进入某一层时才 PROPFIND，不在分类入口预扫整棵树。

// MARK: - 书籍层

struct NASBookListView: View {
    let route: NASRoute

    @ObservedObject private var store = NASStore.shared
    @State private var books: [RemoteEntry] = []
    @State private var counts: [String: Int] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var account: WebDAVAccount { store.account(for: route.connection) }
    private var category: BookCategory { route.category ?? .organized }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在读取目录…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("读取失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load() } }
                }
            } else if books.isEmpty {
                // 结构不规范（分类根下直接放文件）：把根目录当成唯一一本，仍按书库方式看
                List {
                    Section {
                        NavigationLink(value: NASRoute(connection: route.connection,
                                                       url: route.url,
                                                       title: route.title,
                                                       category: category,
                                                       level: .chapters)) {
                            bookRow(title: route.title, count: nil, note: "目录本身")
                        }
                    } footer: {
                        Text("这个目录下没有书名文件夹，已把目录本身当成一本书；"
                             + "按书库结构整理成「书名 → 章节 → 正文 / 图片 / 视频」后会自动分层。")
                    }
                }
            } else {
                List {
                    Section {
                        ForEach(books) { entry in
                            NavigationLink(value: NASRoute(connection: route.connection,
                                                           url: entry.url,
                                                           title: entry.name,
                                                           category: category,
                                                           level: .chapters)) {
                                bookRow(title: entry.name, count: counts[entry.id])
                            }
                            .task(id: entry.id) {
                                await probe(entry)
                            }
                        }
                    } header: {
                        Text(category == .organized ? "书名" : "名称")
                    } footer: {
                        Text(footerText)
                    }
                }
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: NASRoute(connection: route.connection,
                                               url: route.url,
                                               title: route.title,
                                               category: category,
                                               level: .browse)) {
                    Label("原始目录", systemImage: "folder")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var footerText: String {
        switch category {
        case .organized:
            return "每个文件夹是一本书；进入后按「章节 → 正文 / 图片 / 音视频」呈现，和书库「整理」一致。"
        case .comic:
            return "每部漫画一个文件夹；进入后按「部 → 话 → 图片 / PDF」呈现，和书库「漫画」一致。"
        case .shortDrama:
            return "每部短剧一个文件夹；进入后按「剧照包 / 视频集」呈现，和书库「短剧」一致。"
        case .novel:
            return "每个文件夹是一本书。"
        }
    }

    private func bookRow(title: String, count: Int?, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 5) {
                if let note {
                    Text(note)
                } else if let count {
                    Text("\(count) \(unit)")
                } else {
                    Text("正在读取…")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var unit: String {
        switch category {
        case .organized, .novel: return "章"
        case .comic:             return "话"
        case .shortDrama:        return "个包"
        }
    }

    private func probe(_ entry: RemoteEntry) async {
        guard counts[entry.id] == nil else { return }
        let value = await NASPlanner.itemCount(bookURL: entry.url,
                                               category: category,
                                               account: account)
        if let value { counts[entry.id] = value }
    }

    private func load() async {
        isLoading = books.isEmpty
        errorMessage = nil
        do {
            books = try await NASPlanner.books(at: route.url, category: category, account: account)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 章节层

private struct NASChapterGroup: Identifiable {
    let id: String
    let title: String?
    let chapters: [NASChapterRef]
}

struct NASChapterListView: View {
    let route: NASRoute

    @ObservedObject private var store = NASStore.shared
    @ObservedObject private var videoMeta = VideoMetaStore.shared
    @State private var chapters: [NASChapterRef] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// 上次读到的那一章（与书库共用同一份进度，key 见 NASProgress）
    @State private var lastChapterId: String?

    private var account: WebDAVAccount { store.account(for: route.connection) }
    private var category: BookCategory { route.category ?? .organized }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在读取章节…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("读取失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load() } }
                }
            } else if chapters.isEmpty {
                ContentUnavailableView {
                    Label("没有找到章节", systemImage: "folder")
                } description: {
                    Text("检查这本书的目录里是否有图片、PDF 或 txt；结构说明见书库「短剧与 NAS 说明」。")
                }
            } else {
                list
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        // 从阅读页返回时刷新「在读」标记（进度与书库共用）
        .onAppear {
            lastChapterId = ProgressStore.shared.lastChapterId(for: NASProgress.bookKey(route.url))
        }
        .refreshable { await load() }
    }

    private var groups: [NASChapterGroup] {
        var order: [String] = []
        var buckets: [String: [NASChapterRef]] = [:]
        for chapter in chapters {
            let key = chapter.group ?? ""
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(chapter)
        }
        let hasNamed = order.contains { !$0.isEmpty }
        return order.map { key in
            NASChapterGroup(id: key,
                            title: key.isEmpty ? (hasNamed ? "未分组" : nil) : key,
                            chapters: buckets[key] ?? [])
        }
    }

    private var list: some View {
        let groups = self.groups
        return List {
            if groups.count <= 1 {
                ForEach(chapters) { chapter in
                    row(chapter)
                }
            } else {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.chapters) { chapter in
                            row(chapter)
                        }
                    } header: {
                        if let title = group.title {
                            Text(title)
                                .font(.footnote.weight(.semibold))
                                .textCase(nil)
                        }
                    }
                }
            }
        }
    }

    private func row(_ chapter: NASChapterRef) -> some View {
        // 阅读层要拿到兄弟章节才能做「下一章 / 下一集」，所以这里用 destination 形式推入
        NavigationLink {
            NASChapterReaderView(route: route, chapter: chapter, siblings: chapters)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: chapter.kind.symbol)
                    .font(.footnote)
                    .foregroundStyle(.tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.name)
                        .font(.body)
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        Text(chapter.kind.label)
                        if chapter.kind == .video, let line = metaLine(chapter) {
                            Text("·")
                            Text(line).monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                // 与书库一致：这一章就是上次读到的地方
                if lastChapterId == NASProgress.chapterKey(chapter.url) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
        }
        .task(id: chapter.id) {
            guard chapter.kind == .video else { return }
            await VideoMetaStore.shared.load(chapter.url,
                                             headers: WebDAVClient.headers(account: account),
                                             knownSize: nil)
        }
    }

    private func metaLine(_ chapter: NASChapterRef) -> String? {
        VideoMetaFormat.line(videoMeta.info(for: chapter.url))
    }

    private func load() async {
        isLoading = chapters.isEmpty
        errorMessage = nil
        do {
            chapters = try await NASPlanner.chapters(bookURL: route.url,
                                                     category: category,
                                                     account: account)
        } catch {
            errorMessage = error.localizedDescription
        }
        lastChapterId = ProgressStore.shared.lastChapterId(for: NASProgress.bookKey(route.url))
        isLoading = false
    }
}

// MARK: - 阅读层
//
// 与书库「整理」的阅读器同一套：正文 → 插图 → 章末音视频，
// 章末同样有「下一章 / 下一集」和「已是最后一章」。
// 差别只在数据来源：这里全部按需从 WebDAV 取，图片走磁盘缓存、视频带认证头流式播放。
//
// 进度与书库共用 ProgressStore（key 加 nas. 前缀，不会和本地书 id 撞）：
// 书 → 读到哪一章，章 → 读到第几段 / 第几张图，重进能回到原位。
// 换「下一章」时是页内替换，和书库分栏里点下一章的行为一致。

/// NAS 阅读进度的 key
enum NASProgress {
    static func bookKey(_ bookURL: URL) -> String { "nas.b:" + bookURL.absoluteString }
    static func chapterKey(_ chapterURL: URL) -> String { "nas.c:" + chapterURL.absoluteString }
}

struct NASChapterReaderView: View {
    let route: NASRoute
    /// 进入的这一章；之后由 current 接管（章末「下一章」页内替换）
    let chapter: NASChapterRef
    /// 同一本书的兄弟章节：「下一章 / 下一集」与「已是最后一章」靠它判断
    let siblings: [NASChapterRef]

    @EnvironmentObject private var prefs: Preferences
    @ObservedObject private var store = NASStore.shared
    @ObservedObject private var chrome = ReadingChrome.shared

    /// 当前正在读的章节
    @State private var current: NASChapterRef
    /// 切好的段落：只在这一章加载后算一次，滚动时不再重复切分整章正文
    @State private var paragraphs: [String] = []
    @State private var images: [RemoteEntry] = []
    @State private var videos: [RemoteEntry] = []
    @State private var audios: [RemoteEntry] = []
    @State private var pdfLocalURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var galleryIndex: Int?
    /// 关闭全屏大图后要滚回的锚点
    @State private var pendingAnchor: String?

    init(route: NASRoute, chapter: NASChapterRef, siblings: [NASChapterRef]) {
        self.route = route
        self.chapter = chapter
        self.siblings = siblings
        _current = State(initialValue: chapter)
    }

    private var account: WebDAVAccount { store.account(for: route.connection) }
    private var progressKey: String { NASProgress.chapterKey(current.url) }
    private var category: BookCategory { route.category ?? .organized }

    private var encodingKey: String { TextEncodingStore.bookKey(forURL: current.url) }
    private var encoding: TextEncodingOption { TextEncodingStore.option(for: encodingKey) }

    /// 只有读到文字时才需要编码开关
    private var showsEncodingMenu: Bool {
        MediaResolver.isPlainText(current.url)
            || MediaResolver.isEpub(current.url)
            || !paragraphs.isEmpty
    }

    /// 章 / 话 / 集：章节列表、章末导航、空态都用同一个词
    private var unitText: String {
        switch category {
        case .comic:      return "话"
        case .shortDrama: return "集"
        default:          return "章"
        }
    }

    private var nextChapter: NASChapterRef? {
        guard let index = siblings.firstIndex(where: { $0.id == current.id }),
              index + 1 < siblings.count else { return nil }
        return siblings[index + 1]
    }

    var body: some View {
        Group {
            // pdf 自带滚动容器，不能嵌进外层 ScrollView（高度会算成 0）
            if let pdfLocalURL {
                PdfChapterView(url: pdfLocalURL)
            } else if isLoading {
                ProgressView("正在读取…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollBody
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        // 与书库阅读页同一套：由阅读页自己声明隐藏标签栏，不依赖外层状态时序
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if showsEncodingMenu {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section {
                            ForEach(TextEncodingOption.allCases) { option in
                                Button {
                                    TextEncodingStore.set(option, for: encodingKey)
                                    RemoteTextCache.shared.invalidate()
                                    Task { await load() }
                                } label: {
                                    if option == encoding {
                                        Label(option.label, systemImage: "checkmark")
                                    } else {
                                        Text(option.label)
                                    }
                                }
                            }
                        } header: {
                            Text("文本编码 · 当前 \(encoding.label)")
                        }
                    } label: {
                        Label("文本编码", systemImage: "textformat")
                    }
                }
            }
        }
        .onAppear {
            chrome.enter()
            noteLastChapter()
        }
        .onDisappear {
            chrome.leave()
            ProgressStore.shared.flushAnchors()
        }
        .task(id: current.id) { await load() }
        .fullScreenCover(item: Binding(
            get: { galleryIndex.map(RemoteGalleryTarget.init(index:)) },
            set: { galleryIndex = $0?.index }
        )) { target in
            RemoteGalleryView(entries: images, startIndex: target.index,
                              account: account, title: current.name) { closed in
                // 关掉大图后滚回刚看的那一张（与书库同一体验）
                if images.indices.contains(closed) { pendingAnchor = "blk-i\(closed)" }
            }
        }
    }

    private func noteLastChapter() {
        ProgressStore.shared.setLastChapter(progressKey, for: NASProgress.bookKey(route.url))
    }

    private var scrollBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: usesComicLayout ? 0 : prefs.lineSpacing) {
                    if let errorMessage {
                        ContentUnavailableView {
                            Label("读取失败", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("重试") { Task { await load() } }
                        }
                        .padding(.top, 40)
                    } else if isEmptyContent {
                        ContentUnavailableView {
                            Label("这一章没有可显示的内容", systemImage: "doc.questionmark")
                        } description: {
                            Text("该目录里没有 txt / 图片 / 音视频；也可能是文件还在同步。")
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(paragraphs.indices, id: \.self) { index in
                            Text(paragraphs[index])
                                .font(.system(size: prefs.fontSize))
                                .lineSpacing(prefs.lineSpacing)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("blk-p\(index)")
                                .onAppear { note("blk-p\(index)") }
                        }

                        if !images.isEmpty && !usesComicLayout {
                            sectionLabel("插图 · \(images.count)")
                        }
                        ForEach(images.indices, id: \.self) { index in
                            RemoteImage(url: images[index].url,
                                        account: account,
                                        cornerRadius: usesComicLayout ? 0 : 10)
                                .padding(.vertical, usesComicLayout ? 0 : 4)
                                .contentShape(Rectangle())
                                .onTapGesture { galleryIndex = index }
                                .onAppear {
                                    note("blk-i\(index)")
                                    prefetch(around: index)
                                }
                                .id("blk-i\(index)")
                        }

                        if showsMediaLabel {
                            sectionLabel(category == .shortDrama ? "本集视频" : "章末媒体")
                        }
                        ForEach(mediaItems) { item in
                            MediaAttachmentView(item: item,
                                                chapterId: progressKey,
                                                boostRate: prefs.longPressRate,
                                                headers: WebDAVClient.headers(account: account))
                                .padding(.horizontal, usesComicLayout ? 16 : 0)
                                .padding(.top, usesComicLayout ? 16 : 0)
                        }

                        chapterFooter

                        Color.clear.frame(height: 30)
                    }
                }
                .padding(.horizontal, usesComicLayout ? 0 : 20)
                .padding(.vertical, 16)
            }
            .onAppear { restoreAnchor(proxy) }
            // 切章时重建滚动视图：位置回到这一章记住的锚点，而不是停在上一章的底部
            .id(current.id)
            .onChange(of: pendingAnchor) { _, anchor in
                guard let anchor else { return }
                // 等全屏大图收起动画结束再定位，避免滚动被覆盖视图吞掉
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(anchor, anchor: .center)
                    }
                    ProgressStore.shared.noteAnchor(anchor, for: progressKey)
                    pendingAnchor = nil
                }
            }
        }
    }

    /// 章末：下一章 / 下一集；没有下一章时说清楚「已是最后一章」
    private var chapterFooter: some View {
        Group {
            if let next = nextChapter {
                Button {
                    open(next)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("下一\(unitText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(next.displayName)
                                .font(.body.weight(.medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, usesComicLayout ? 20 : 0)
                .padding(.top, 28)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                    Text("已是最后一\(unitText)")
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
            }
        }
    }

    /// 页内切到下一章：与书库分栏里点「下一章」同一效果，返回仍回到章节列表
    private func open(_ next: NASChapterRef) {
        ProgressStore.shared.flushAnchors()
        pendingAnchor = nil
        current = next
        noteLastChapter()
        // 内容由 .task(id: current.id) 自动重载，这里不再手动触发避免重复请求
    }

    private func note(_ anchor: String) {
        ProgressStore.shared.noteAnchor(anchor, for: progressKey)
    }

    private func restoreAnchor(_ proxy: ScrollViewProxy) {
        guard let anchor = ProgressStore.shared.anchor(for: progressKey) else { return }
        // LazyVStack 首屏布局需要一点时间，太早 scrollTo 会被忽略
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    /// 漫画 / 短剧的纯图片章节用「满宽连排」，与书库这两个分区看到的一致
    private var usesComicLayout: Bool {
        guard category == .comic || category == .shortDrama else { return false }
        return !images.isEmpty && paragraphs.isEmpty && pdfLocalURL == nil
    }

    /// 只有一段视频的集，播放器本身就是主体，不再顶一个「本集视频」小标题
    private var showsMediaLabel: Bool {
        guard !videos.isEmpty || !audios.isEmpty else { return false }
        let singleVideo = videos.count == 1 && audios.isEmpty
        let nothingElse = paragraphs.isEmpty && images.isEmpty && pdfLocalURL == nil
        return !(singleVideo && nothingElse)
    }

    private var isEmptyContent: Bool {
        pdfLocalURL == nil && paragraphs.isEmpty
            && images.isEmpty && videos.isEmpty && audios.isEmpty
    }

    /// 视频 / 音频统一成 MediaItem，交给与本地同一套播放器（全屏、旋转、长按倍速）
    private var mediaItems: [MediaItem] {
        let v = videos.map { MediaItem(url: $0.url, kind: .video, sequence: nil) }
        let a = audios.map { MediaItem(url: $0.url, kind: .audio, sequence: nil) }
        return v + a
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 14)
    }

    private func prefetch(around index: Int) {
        var urls: [URL] = []
        for offset in [-2, -1, 1, 2] {
            let target = index + offset
            if target >= 0, target < images.count, target != index {
                urls.append(images[target].url)
            }
        }
        guard !urls.isEmpty else { return }
        RemoteImageCache.shared.prefetch(urls, account: account)
    }

    /// 目录名也可能带点（如「S01.E01」），所以只认已知的文档 / 媒体扩展名
    private func isFileLike(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return MediaResolver.isPDF(url)
            || MediaResolver.isEpub(url)
            || MediaResolver.classify(name) != nil
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        pendingAnchor = nil
        paragraphs = []
        images = []
        videos = []
        audios = []
        pdfLocalURL = nil
        defer { isLoading = false }

        let fileLike = isFileLike(current.url)
        // 1. 单文件章节（短剧的一集视频、漫画的单话 pdf、单独的 txt）
        if fileLike {
            if MediaResolver.isPDF(current.url) {
                do { pdfLocalURL = try await RemoteFileStore.localCopy(of: current.url, account: account) }
                catch { errorMessage = error.localizedDescription }
                return
            }
            if MediaResolver.isVideoFile(current.url) {
                videos = [RemoteEntry(name: current.name, url: current.url,
                                      isDirectory: false, byteCount: nil)]
                return
            }
            if MediaResolver.isAudioFile(current.url) {
                audios = [RemoteEntry(name: current.name, url: current.url,
                                      isDirectory: false, byteCount: nil)]
                return
            }
            if let value = await RemoteTextCache.shared.text(for: current.url, account: account) {
                paragraphs = TextLoader.paragraphs(value)
            } else {
                errorMessage = "无法读取这个文件（编码不支持或已被移走）"
            }
            return
        }

        // 2. 目录章节：正文 → 图片 → 音视频 → pdf（与本地「整理」同一顺序）
        do {
            let entries = try await WebDAVClient.list(dir: current.url, account: account)
            let files = entries.filter { !$0.isDirectory }
            let textFile = files
                .filter { MediaResolver.isPlainText($0.url) || MediaResolver.isEpub($0.url) }
                .sorted { NaturalSort.less($0.name, $1.name) }
                .first
            images = files.filter { MediaResolver.imageExtensions.contains(MediaResolver.fileExtension($0.name)) }
            videos = files.filter { MediaResolver.isVideoFile($0.url) }
            audios = files.filter { MediaResolver.isAudioFile($0.url) }
            if let pdf = files.first(where: { MediaResolver.isPDF($0.url) }) {
                do { pdfLocalURL = try await RemoteFileStore.localCopy(of: pdf.url, account: account) }
                catch { /* pdf 失败不阻断其余内容 */ }
            }
            if let textFile,
               let value = await RemoteTextCache.shared.text(for: textFile.url, account: account) {
                paragraphs = TextLoader.paragraphs(value)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
