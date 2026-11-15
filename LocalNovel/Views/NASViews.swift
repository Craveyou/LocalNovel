import SwiftUI

// MARK: - NAS 页（底部 Tab 第二个）
//
// 层级：连接列表 → 分类入口（漫画 / 整理 / 短剧，固定访问飞牛目录）→ 目录 → 图片 / 视频。
// 右下角 ➕ 新建连接：内网地址 + 外网地址，连接时自动判断走哪条。

struct NASRoute: Hashable {
    let connection: NASConnection
    let url: URL
    let title: String
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
                                }
                            }
                        } footer: {
                            Text("SMB 共享请在「文件」App 里连接，再用书库的「导入书籍文件夹」加入；"
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
                NASBrowserView(route: route)
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

// MARK: - 连接下的分类入口

struct NASSectionView: View {
    let connection: NASConnection

    @ObservedObject private var store = NASStore.shared
    @State private var endpoint: NASStore.Endpoint?
    @State private var errorMessage: String?
    @State private var isConnecting = false

    var body: some View {
        List {
            Section {
                ForEach(NASConnection.categories) { category in
                    if let endpoint {
                        NavigationLink(value: NASRoute(connection: connection,
                                                       url: store.categoryURL(category,
                                                                              connection: connection,
                                                                              endpoint: endpoint),
                                                       title: category.label)) {
                            HStack(spacing: 12) {
                                Image(systemName: category.symbol)
                                    .font(.title3)
                                    .frame(width: 30)
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.label).font(.headline)
                                    Text(connection.path(for: category))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: category.symbol)
                                .font(.title3)
                                .frame(width: 30)
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.label).font(.headline).foregroundStyle(.tertiary)
                                Text(connection.path(for: category))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } header: {
                Text("分类（固定访问飞牛目录）")
            } footer: {
                Text("分类里的路径可在连接的「编辑」里改；NAS 页不含小说。")
            }

            Section("连接状态") {
                HStack(spacing: 8) {
                    if isConnecting { ProgressView().controlSize(.small) }
                    Text(store.status(for: connection).text)
                        .font(.footnote)
                        .foregroundStyle(errorMessage == nil ? .secondary : .red)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("重新判断内外网") {
                    Task { await connect(force: true) }
                }
                .font(.footnote)
            }
        }
        .navigationTitle(connection.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await connect() }
        .refreshable { await connect(force: true) }
    }

    private func connect(force: Bool = false) async {
        guard !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        let value = await store.resolve(connection, force: force)
        endpoint = value
        if value == nil {
            errorMessage = store.lastError
        }
        isConnecting = false
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
                            .foregroundStyle(testOK ? .green : .red)
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
                testResult = "\(label)可直连：\(base.absoluteString)"
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
