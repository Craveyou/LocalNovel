import SwiftUI

// MARK: - NAS 页（底部 Tab 第二个）
//
// 层级：连接列表 → 分类入口（漫画 / 整理 / 短剧，固定访问飞牛目录）
//       → 书名 → 章节 → 阅读（与本地书库完全同样的三层）
// 右下角 ➕ 新建连接：内网地址 + 外网地址，连接时自动判断走哪条。

/// 目录在「书库式层级」里的位置
enum NASLevel: String, Hashable {
    /// 原始目录浏览（旧行为，结构不规范时的兜底）
    case browse
    /// 分类根：书名列表
    case books
    /// 一本书：章节列表
    case chapters
    /// 一章：正文 / 图片 / 音视频
    case reader
}

struct NASRoute: Hashable {
    let connection: NASConnection
    let url: URL
    let title: String
    /// 所在分类；决定书名 / 章节的识别规则与阅读页的措辞
    var category: BookCategory? = nil
    var level: NASLevel = .browse
}

struct RemoteImagesRoute: Hashable {
    let connection: NASConnection
    let title: String
    let entries: [RemoteEntry]
}

struct RemoteVideoRoute: Hashable {
    let connection: NASConnection
    let entry: RemoteEntry
}

struct NASRootView: View {
    @ObservedObject private var store = NASStore.shared
    @State private var editing: NASConnection?
    @State private var pendingDelete: NASConnection?

    var body: some View {
        NavigationStack {
            Group {
                if store.connections.isEmpty {
                    ContentUnavailableView {
                        Label("还没有网络连接", systemImage: "externaldrive.badge.wifi")
                    } description: {
                        Text("点右下角 ➕ 新建：填飞牛的内网地址与外网地址，\n连上后即可在这里看漫画、整理和短剧。")
                    }
                } else {
                    List {
                        Section {
                            ForEach(store.connections) { connection in
                                NavigationLink(value: connection) {
                                    row(connection)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDelete = connection
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    Button {
                                        editing = connection
                                    } label: {
                                        Label("编辑", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        editing = connection
                                    } label: {
                                        Label("编辑", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                .contextMenu {
                                    Button {
                                        editing = connection
                                    } label: {
                                        Label("编辑连接", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        pendingDelete = connection
                                    } label: {
                                        Label("删除连接", systemImage: "trash")
                                    }
                                }
                            }
                        } footer: {
                            Text("左滑或长按连接可编辑 / 删除；进入连接后右上角 ✏️ 也能改地址与分类目录。\n"
                                 + "SMB 共享请在「文件」App 里连接，再用书库的「导入书籍文件夹」加入；"
                                 + "App 内直连走 WebDAV（飞牛：控制面板 → 文件共享 → WebDAV）。")
                        }
                        Color.clear.frame(height: 72).listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("NAS")
            .overlay(alignment: .bottomTrailing) { addButton }
            .sheet(item: $editing) { connection in
                NASConnectionEditor(connection: connection) { saved, password in
                    store.save(saved, password: password)
                }
            }
            .confirmationDialog("删除这个连接？",
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                presenting: pendingDelete) { connection in
                Button("删除「\(connection.name)」", role: .destructive) {
                    store.delete(connection)
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: { _ in
                Text("只删除本机保存的地址与密码，不会动 NAS 上的文件。")
            }
            .navigationDestination(for: NASConnection.self) { connection in
                NASSectionView(connection: connection)
            }
            .navigationDestination(for: NASRoute.self) { route in
                switch route.level {
                case .browse:
                    NASBrowserView(route: route)
                case .books:
                    NASBookListView(route: route)
                case .chapters:
                    NASChapterListView(route: route)
                case .reader:
                    NASChapterReaderView(route: route)
                }
            }
            .navigationDestination(for: RemoteImagesRoute.self) { route in
                RemoteImageSequenceView(title: route.title,
                                        entries: route.entries,
                                        account: store.account(for: route.connection))
            }
            .navigationDestination(for: RemoteVideoRoute.self) { route in
                RemoteVideoView(entry: route.entry,
                                account: store.account(for: route.connection))
            }
        }
    }

    private func row(_ connection: NASConnection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(connection.name)
                    .font(.headline)
                Spacer(minLength: 0)
                statusBadge(store.status(for: connection))
            }
            if !connection.lanAddress.isEmpty {
                Text("内网 \(connection.lanAddress)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !connection.wanAddress.isEmpty {
                Text("外网 \(connection.wanAddress)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: NASStatus) -> some View {
        Group {
            switch status {
            case .idle:
                Text("未连接").foregroundStyle(.secondary)
            case .connecting:
                Text("连接中…").foregroundStyle(.orange)
            case .connected(let isLAN):
                Label(isLAN ? "内网" : "外网",
                      systemImage: isLAN ? "house" : "globe")
                    .foregroundStyle(.green)
            case .failed:
                Label("失败", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption2.weight(.semibold))
    }

    private var addButton: some View {
        Button {
            editing = NASConnection(name: "", lanAddress: "", wanAddress: "",
                                    username: "",
                                    categoryPaths: NASConnection.defaultCategoryPaths)
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        }
        .padding(24)
        .accessibilityLabel("新建网络连接")
    }
}

// MARK: - 连接下的分类入口（呈现与书库首页完全一致）
//
// 书库首页的「小说 / 漫画 / 整理 / 短剧」是 CategoryCard；NAS 这里用同一个组件，
// 只是把副标题换成飞牛上的目录路径、数量换成该目录下的部数（进入时并发数一次）。

struct NASSectionView: View {
    let connection: NASConnection

    @ObservedObject private var store = NASStore.shared
    @State private var endpoint: NASStore.Endpoint?
    @State private var errorMessage: String?
    @State private var isConnecting = false
    /// 分类目录下的部数；nil = 还没数到（连不上或正在读）
    @State private var counts: [String: Int] = [:]
    @State private var editing = false
    /// 上次请求实际用的协议（https 会显示 HTTP/2，说明多路复用已生效）
    @State private var protocolName: String?

    /// 连接可能在别处被编辑过，一律读 store 里的最新值
    private var current: NASConnection {
        store.connections.first(where: { $0.id == connection.id }) ?? connection
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(NASConnection.categories) { category in
                    card(category)
                }
            }
            .padding(16)
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = true } label: {
                    Label("编辑连接", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $editing) {
            NASConnectionEditor(connection: current) { saved, password in
                store.save(saved, password: password)
                Task { await connect(force: true) }
            }
        }
        .safeAreaInset(edge: .bottom) { statusBar }
        .task { await connect() }
        .refreshable { await connect(force: true) }
    }

    private func card(_ category: BookCategory) -> some View {
        let countText = counts[category.rawValue].map { "\($0)" }
        return Group {
            if let endpoint {
                NavigationLink(value: NASRoute(connection: current,
                                               url: store.categoryURL(category,
                                                                      connection: current,
                                                                      endpoint: endpoint),
                                               title: category.label,
                                               category: category,
                                               level: .books)) {
                    CategoryCard(symbol: category.symbol,
                                 title: category.label,
                                 subtitle: current.path(for: category),
                                 countText: countText)
                }
                .buttonStyle(.plain)
            } else {
                CategoryCard(symbol: category.symbol,
                             title: category.label,
                             subtitle: isConnecting ? "正在连接…" : current.path(for: category),
                             countText: countText,
                             isDimmed: true)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if isConnecting { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 1) {
                Text(errorMessage ?? store.status(for: current).text)
                    .font(.footnote)
                    .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                    .lineLimit(2)
                if let protocolName {
                    Text(protocolName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Button("重探") { Task { await connect(force: true) } }
                .font(.footnote)
                .disabled(isConnecting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @MainActor
    private func connect(force: Bool = false) async {
        guard !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        let value = await store.resolve(current, force: force)
        endpoint = value
        if value == nil {
            errorMessage = store.lastError
            counts = [:]
        }
        isConnecting = false
        if let value { await countItems(endpoint: value) }
        protocolName = ProtocolProbe.shared.displayName
    }

    /// 三个分类各列一层目录，取子目录数（并发，失败就留空不显示数字）
    @MainActor
    private func countItems(endpoint: NASStore.Endpoint) async {
        let account = store.account(for: current)
        var result: [String: Int] = [:]
        await withTaskGroup(of: (String, Int?).self) { group in
            for category in NASConnection.categories {
                let url = store.categoryURL(category, connection: current, endpoint: endpoint)
                group.addTask {
                    guard let entries = try? await WebDAVClient.list(dir: url, account: account)
                    else { return (category.rawValue, nil) }
                    return (category.rawValue, entries.filter { $0.isDirectory }.count)
                }
            }
            for await (key, value) in group {
                if let value { result[key] = value }
            }
        }
        counts = result
    }
}

// MARK: - 远端目录浏览（逐层 PROPFIND，不预扫整棵树）

struct NASBrowserView: View {
    let route: NASRoute

    @ObservedObject private var store = NASStore.shared
    @ObservedObject private var videoMeta = VideoMetaStore.shared

    @State private var entries: [RemoteEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var account: WebDAVAccount { store.account(for: route.connection) }
    private var images: [RemoteEntry] {
        entries.filter { !$0.isDirectory && MediaResolver.imageExtensions.contains(ext($0)) }
    }
    private var dirs: [RemoteEntry] { entries.filter { $0.isDirectory } }
    private var videos: [RemoteEntry] {
        entries.filter { !$0.isDirectory && MediaResolver.videoExtensions.contains(ext($0)) }
    }
    private var others: [RemoteEntry] {
        entries.filter {
            !$0.isDirectory && !MediaResolver.imageExtensions.contains(ext($0))
                && !MediaResolver.videoExtensions.contains(ext($0))
        }
    }

    private func ext(_ entry: RemoteEntry) -> String {
        MediaResolver.fileExtension(entry.name)
    }

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
            } else if entries.isEmpty {
                ContentUnavailableView("这个目录是空的", systemImage: "folder")
            } else {
                list
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var list: some View {
        List {
            if !images.isEmpty {
                Section {
                    NavigationLink(value: RemoteImagesRoute(connection: route.connection,
                                                            title: route.title,
                                                            entries: images)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("查看图片")
                                    .font(.headline)
                                Text("\(images.count) 张 · 按漫画方式满宽连排")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "photo.on.rectangle.angled")
                        }
                    }
                }
            }

            if !dirs.isEmpty || !videos.isEmpty {
                Section {
                    ForEach(dirs) { entry in
                        NavigationLink(value: NASRoute(connection: route.connection,
                                                       url: entry.url,
                                                       title: entry.name)) {
                            Label {
                                Text(entry.name).font(.body)
                            } icon: {
                                Image(systemName: "folder")
                            }
                        }
                    }
                    ForEach(videos) { entry in
                        NavigationLink(value: RemoteVideoRoute(connection: route.connection,
                                                               entry: entry)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name).font(.body)
                                if !metaLine(entry).isEmpty {
                                    Text(metaLine(entry))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .task(id: entry.id) {
                            await videoMeta.load(entry.url,
                                                 headers: WebDAVClient.headers(account: account),
                                                 knownSize: entry.byteCount)
                        }
                    }
                }
            }

            if !others.isEmpty {
                Section("其他文件") {
                    ForEach(others) { entry in
                        HStack {
                            Text(entry.name).font(.body).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if let size = VideoMetaFormat.size(entry.byteCount) {
                                Text(size).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func metaLine(_ entry: RemoteEntry) -> String {
        let info = videoMeta.info(for: entry.url)
        let size = VideoMetaFormat.size(entry.byteCount ?? info?.byteCount)
        let duration = VideoMetaFormat.duration(info?.seconds)
        let parts = [size, duration].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        isLoading = entries.isEmpty
        errorMessage = nil
        do {
            entries = try await store.list(route.url, connection: route.connection)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 新建 / 编辑连接

struct NASConnectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NASConnection
    @State private var password: String
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testOK = false

    private let onSave: (NASConnection, String?) -> Void
    private let isNew: Bool

    init(connection: NASConnection, onSave: @escaping (NASConnection, String?) -> Void) {
        _draft = State(initialValue: connection)
        _password = State(initialValue: Keychain.password(for: connection.id.uuidString) ?? "")
        self.onSave = onSave
        self.isNew = connection.name.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如：家里的飞牛", text: $draft.name)
                }

                Section {
                    TextField("内网地址，如 http://192.168.1.10:5005", text: $draft.lanAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("外网地址，如 https://nas.example.com:5006", text: $draft.wanAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("地址")
                } footer: {
                    Text("连接时先探内网、失败再探外网，成功后显示「内网直连」或「外网连接」。"
                         + "只填一个也可以；内网常用 http，外网建议 https。")
                }

                Section("账号") {
                    TextField("飞牛用户名", text: $draft.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码（只存在系统钥匙串）", text: $password)
                }

                Section {
                    ForEach(NASConnection.categories) { category in
                        HStack {
                            Text(category.label)
                                .frame(width: 52, alignment: .leading)
                            TextField("目录名", text: binding(for: category))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                } header: {
                    Text("分类目录")
                } footer: {
                    Text("分类固定访问这些目录（相对 WebDAV 根）。默认 漫画 / 整理 / 短剧，飞牛里改了名字就在这里改。")
                }

                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            if isTesting { ProgressView().controlSize(.small) }
                            Text(isTesting ? "正在判断内外网…" : "测试连接")
                        }
                    }
                    .disabled(isTesting || (draft.lanAddress.isEmpty && draft.wanAddress.isEmpty))
                    if let testResult {
                        Label(testResult,
                              systemImage: testOK ? "checkmark.circle" : "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(testOK ? Color.green : Color.red)
                    }
                }

                Section {
                    Text("App 内只支持 WebDAV。飞牛：控制面板 → 文件共享 → WebDAV 开启，端口默认 5005 / 5006。"
                         + "SMB 共享请在「文件」App 里连接后用「导入书籍文件夹」加入书库（系统不允许 App 直接连 SMB）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isNew ? "新建连接" : "编辑连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(draft, password.isEmpty ? nil : password)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || (draft.lanAddress.isEmpty && draft.wanAddress.isEmpty))
                }
            }
        }
    }

    private func binding(for category: BookCategory) -> Binding<String> {
        Binding(
            get: { draft.categoryPaths[category.rawValue] ?? category.folderName },
            set: { draft.categoryPaths[category.rawValue] = $0 }
        )
    }

    private func test() async {
        isTesting = true
        testResult = nil
        testOK = false

        let account = WebDAVAccount(username: draft.username, password: password)
        var attempts: [(String, String)] = []
        if !draft.lanAddress.isEmpty { attempts.append(("内网", draft.lanAddress)) }
        if !draft.wanAddress.isEmpty { attempts.append(("外网", draft.wanAddress)) }

        for (label, raw) in attempts {
            guard let base = WebDAVClient.baseURL(from: raw) else {
                testResult = "\(label)地址格式不对"
                continue
            }
            do {
                try await WebDAVClient.probe(base: base, account: account)
                // 顺手把实际协议带出来：https + 服务端支持时会显示 HTTP/2
                let proto = ProtocolProbe.shared.displayName.map { "（\($0)）" } ?? ""
                testResult = "\(label)可直连\(proto)：\(base.absoluteString)"
                testOK = true
                isTesting = false
                return
            } catch {
                testResult = "\(label)不通：\(error.localizedDescription)"
            }
        }
        isTesting = false
    }
}
