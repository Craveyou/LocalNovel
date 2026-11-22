import SwiftUI
#if canImport(FoundationXML)
import FoundationXML
#endif
import AMSMB2

// MARK: - 飞牛 NAS 连接模型

/// NAS 访问协议。SMB 走内网直连，WebDAV 走外网。
enum NASProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case smb = "smb"
    case webdav = "webdav"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smb: "SMB（内网）"
        case .webdav: "WebDAV（外网）"
        }
    }

    var defaultPort: Int {
        switch self {
        case .smb: 445
        case .webdav: 5005
        }
    }
}

/// 一条飞牛 NAS 的连接配置，持久化在 UserDefaults。
/// 兼容旧版只有 WebDAV 的 v1 数据：缺少的字段由 Codable 默认值补齐。
struct FeiniuConnection: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String = "飞牛 NAS"
    var proto: NASProtocol = .webdav
    var scheme: String = "http"       // WebDAV: http / https
    var host: String = ""
    var port: Int = 5005              // SMB 445 / WebDAV HTTP 5005 / HTTPS 5006
    var username: String = ""
    var password: String = ""
    var rootPath: String = "/"        // WebDAV 初始路径
    var share: String = ""            // SMB 共享名
    var createdAt: Date = Date()

    /// 旧版 v1 JSON 没有 proto/share 字段，用自定义解码补默认值，避免升级后连接丢失。
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try box.decodeIfPresent(String.self, forKey: .name) ?? "飞牛 NAS"
        proto = try box.decodeIfPresent(NASProtocol.self, forKey: .proto) ?? .webdav
        scheme = try box.decodeIfPresent(String.self, forKey: .scheme) ?? "http"
        host = try box.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try box.decodeIfPresent(Int.self, forKey: .port) ?? (proto == .smb ? 445 : 5005)
        username = try box.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try box.decodeIfPresent(String.self, forKey: .password) ?? ""
        rootPath = try box.decodeIfPresent(String.self, forKey: .rootPath) ?? "/"
        share = try box.decodeIfPresent(String.self, forKey: .share) ?? ""
        createdAt = try box.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    init() {}

    var displayAddress: String {
        guard !host.isEmpty else { return "未配置地址" }
        switch proto {
        case .smb:
            return "smb://\(host):\(port)/\(share)"
        case .webdav:
            return "\(scheme)://\(host):\(port)\(rootPath)"
        }
    }

    /// 去掉用户可能一并粘贴的 scheme 与端口，只保留主机部分。
    static func cleanedHost(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), url.scheme != nil, let host = url.host { value = host }
        if let colon = value.firstIndex(of: ":") { value = String(value[..<colon]) }
        return value
    }
}

@MainActor
final class FeiniuConnectionStore: ObservableObject {
    @Published private(set) var connections: [FeiniuConnection] = []
    private let defaults: UserDefaults
    private let key = "nas.feiniu.connections.v2"
    private let legacyKey = "nas.feiniu.connections.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private func load() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([FeiniuConnection].self, from: data) {
            connections = decoded
            return
        }
        // 迁移旧版纯 WebDAV 数据
        if let data = defaults.data(forKey: legacyKey),
           let decoded = try? JSONDecoder().decode([FeiniuConnection].self, from: data) {
            connections = decoded
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        defaults.set(data, forKey: key)
    }

    func upsert(_ connection: FeiniuConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        persist()
    }

    func delete(_ connection: FeiniuConnection) {
        connections.removeAll { $0.id == connection.id }
        persist()
    }
}

// MARK: - WebDAV 客户端

private struct NASEntry: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String          // 服务器路径（WebDAV 解码后的路径 / SMB share 内相对路径）
    let name: String
    let isDirectory: Bool
    let size: Int64
}

private enum FeiniuError: LocalizedError {
    case invalidAddress
    case missingShare
    case http(Int)
    case nonHTTP
    case invalidXML
    case smb(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "地址或端口无效，请检查主机填的是 IP 或域名（不含协议和端口）"
        case .missingShare: "SMB 需要填写共享名（飞牛「文件服务 → SMB」里共享文件夹的名称）"
        case .http(let code):
            switch code {
            case 401: "账号或密码错误，或该账号没有 WebDAV 权限（飞牛需使用独立 WebDAV 账号）"
            case 403: "账号没有该目录的访问权限"
            case 404: "路径不存在，请检查初始路径（飞牛根目录一般填 /）"
            default: "服务器返回 HTTP \(code)"
            }
        case .nonHTTP: "服务器返回的不是 HTTP 响应"
        case .invalidXML: "WebDAV 返回的目录数据无法解析"
        case .smb(let detail): "SMB 连接失败：\(detail)"
        }
    }
}

/// 飞牛自签证书信任：行为与项目整体设置一致（忽略证书错误）。
/// 单独实现以免 NAS 页依赖额外模块，保持本文件自包含。
private final class FeiniuTrustDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = FeiniuTrustDelegate()

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// SMB2/3 客户端（内网直连）：基于 AMSMB2/libsmb2。
/// 每条连接独立创建 SMB2Manager，Swift 对象释放时库会自动断开共享。
private enum FeiniuSMB {
    static func probe(_ connection: FeiniuConnection) async throws {
        let manager = try makeManager(connection)
        try await manager.connectShare(name: connection.share)
    }

    static func list(_ connection: FeiniuConnection, path: String) async throws -> [NASEntry] {
        let manager = try makeManager(connection)
        try await manager.connectShare(name: connection.share)
        let items = try await manager.contentsOfDirectory(atPath: path, recursive: false)
        return items.compactMap { entry in
            guard let name = entry[.nameKey] as? String, !name.isEmpty else { return nil }
            let resolvedPath = smbPath(entry[.pathKey] as? String, parent: path, name: name)
            let isDirectory = (entry[.fileResourceTypeKey] as? URLFileResourceType) == .directory
            let size = (entry[.fileSizeKey] as? NSNumber)?.int64Value ?? 0
            return NASEntry(path: resolvedPath, name: name, isDirectory: isDirectory, size: size)
        }
    }

    static func download(_ connection: FeiniuConnection, entry: NASEntry) async throws -> URL {
        let manager = try makeManager(connection)
        try await manager.connectShare(name: connection.share)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("feiniu-smb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = entry.name.isEmpty ? "download" : entry.name
        let target = folder.appendingPathComponent(filename)
        try await manager.downloadItem(atPath: entry.path, to: target, progress: nil)
        return target
    }

    private static func makeManager(_ connection: FeiniuConnection) throws -> SMB2Manager {
        guard !connection.host.isEmpty, (1...65535).contains(connection.port),
              let url = URL(string: "smb://\(connection.host):\(connection.port)") else {
            throw FeiniuError.invalidAddress
        }
        guard !connection.share.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FeiniuError.missingShare
        }
        let credential = URLCredential(user: connection.username, password: connection.password, persistence: .forSession)
        guard let manager = SMB2Manager(url: url, domain: "", credential: credential) else {
            throw FeiniuError.smb("无法初始化 SMB 客户端")
        }
        return manager
    }

    /// libsmb2 的 pathKey 一般是 share 内完整路径；缺失时用父路径 + 文件名兜底。
    private static func smbPath(_ raw: String?, parent: String, name: String) -> String {
        if var value = raw?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
            if !value.hasPrefix("/") { value = "/" + value }
            return value
        }
        let base = parent.isEmpty ? "/" : parent
        return (base as NSString).appendingPathComponent(name)
    }
}

/// 飞牛 WebDAV 最小实现：PROPFIND 探测与列目录、GET 下载。
private enum FeiniuWebDAV {
    static func probe(_ connection: FeiniuConnection) async throws {
        let (_, response) = try await request(connection, method: "PROPFIND", path: connection.rootPath, depth: "0")
        guard response.statusCode == 200 || response.statusCode == 207 else {
            throw FeiniuError.http(response.statusCode)
        }
    }

    static func list(_ connection: FeiniuConnection, path: String) async throws -> [NASEntry] {
        let (data, response) = try await request(connection, method: "PROPFIND", path: path, depth: "1")
        guard response.statusCode == 200 || response.statusCode == 207 else {
            throw FeiniuError.http(response.statusCode)
        }
        let parser = PropfindParser()
        let xml = XMLParser(data: data)
        xml.shouldProcessNamespaces = false
        xml.delegate = parser
        guard xml.parse() else { throw xml.parserError ?? FeiniuError.invalidXML }

        let root = normalized(path)
        return parser.items.compactMap { item in
            let itemPath = normalized(item.path)
            guard !itemPath.isEmpty, itemPath != root else { return nil }  // 过滤目录自身
            let name = item.name.isEmpty ? (item.path as NSString).lastPathComponent : item.name
            return NASEntry(path: item.path, name: name, isDirectory: item.isDirectory, size: item.size)
        }
    }

    static func download(_ connection: FeiniuConnection, entry: NASEntry) async throws -> URL {
        var urlRequest = try makeRequest(connection, method: "GET", path: entry.path)
        let session = makeSession()
        defer { session.finishTasksAndInvalidate() }
        let (tempURL, response) = try await session.download(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw FeiniuError.nonHTTP }
        guard (200...299).contains(http.statusCode) else { throw FeiniuError.http(http.statusCode) }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("feiniu-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = entry.name.isEmpty ? "download" : entry.name
        let target = folder.appendingPathComponent(filename)
        try FileManager.default.moveItem(at: tempURL, to: target)
        return target
    }

    private static func request(_ connection: FeiniuConnection, method: String, path: String, depth: String?) async throws -> (Data, HTTPURLResponse) {
        var urlRequest = try makeRequest(connection, method: method, path: path)
        if let depth { urlRequest.setValue(depth, forHTTPHeaderField: "Depth") }
        if method == "PROPFIND" { urlRequest.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        let session = makeSession()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw FeiniuError.nonHTTP }
        return (data, http)
    }

    private static func makeRequest(_ connection: FeiniuConnection, method: String, path: String) throws -> URLRequest {
        guard !connection.host.isEmpty, (1...65535).contains(connection.port) else { throw FeiniuError.invalidAddress }
        var components = URLComponents()
        components.scheme = connection.scheme
        components.host = connection.host
        components.port = connection.port
        let target = path.isEmpty ? "/" : path
        components.path = target.hasPrefix("/") ? target : "/" + target
        guard let url = components.url else { throw FeiniuError.invalidAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        let basic = Data("\(connection.username):\(connection.password)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("小浣熊阅读/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config, delegate: FeiniuTrustDelegate.shared, delegateQueue: nil)
    }

    private static func normalized(_ path: String) -> String {
        var value = path.removingPercentEncoding ?? path
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }
}

/// 统一门面：按连接协议分发到 SMB 或 WebDAV 客户端。
private enum FeiniuNASService {
    static func probe(_ connection: FeiniuConnection) async throws {
        switch connection.proto {
        case .smb: try await FeiniuSMB.probe(connection)
        case .webdav: try await FeiniuWebDAV.probe(connection)
        }
    }

    static func list(_ connection: FeiniuConnection, path: String) async throws -> [NASEntry] {
        switch connection.proto {
        case .smb: try await FeiniuSMB.list(connection, path: path)
        case .webdav: try await FeiniuWebDAV.list(connection, path: path)
        }
    }

    static func download(_ connection: FeiniuConnection, entry: NASEntry) async throws -> URL {
        switch connection.proto {
        case .smb: try await FeiniuSMB.download(connection, entry: entry)
        case .webdav: try await FeiniuWebDAV.download(connection, entry: entry)
        }
    }

    /// SMB share 内的初始路径用 "/"；WebDAV 用连接里保存的 rootPath。
    static func initialPath(_ connection: FeiniuConnection) -> String {
        switch connection.proto {
        case .smb: "/"
        case .webdav: connection.rootPath
        }
    }
}

/// 解析 WebDAV multistatus：response / href / displayname / collection / getcontentlength。
private final class PropfindParser: NSObject, XMLParserDelegate {
    struct Item {
        var path = ""
        var name = ""
        var isDirectory = false
        var size: Int64 = 0
    }

    var items: [Item] = []
    private var current: Item?
    private var activeField: String?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch local(elementName) {
        case "response":
            current = Item()
        case "href", "displayname", "getcontentlength":
            activeField = local(elementName)
            text = ""
        case "collection":
            current?.isDirectory = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if activeField != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch local(elementName) {
        case "href":
            current?.path = text.trimmingCharacters(in: .whitespacesAndNewlines)
            activeField = nil
        case "displayname":
            current?.name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            activeField = nil
        case "getcontentlength":
            current?.size = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            activeField = nil
        case "response":
            if let item = current { items.append(item) }
            current = nil
        default:
            break
        }
    }

    private func local(_ name: String) -> String {
        (name.split(separator: ":").last.map(String.init) ?? name).lowercased()
    }
}

// MARK: - NAS 主页面

struct NASView: View {
    @EnvironmentObject private var library: BookLibraryModel
    @StateObject private var store = FeiniuConnectionStore()
    @State private var showingAdd = false
    @State private var editing: FeiniuConnection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if store.connections.isEmpty {
                    emptyState
                } else {
                    connectionList
                }
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(ReadingTheme.canvas.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("nas.add.connection")
            }
        }
        .sheet(isPresented: $showingAdd) {
            FeiniuConnectionFormView(store: store)
        }
        .sheet(item: $editing) { connection in
            FeiniuConnectionFormView(store: store, connection: connection)
        }
        .accessibilityIdentifier("nas.scroll")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("NAS")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Image(systemName: "network")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(ReadingTheme.ink.opacity(0.6))
                    .frame(width: 44, height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(ReadingTheme.groupedCanvas.opacity(0.75))
                    }
                    .accessibilityHidden(true)
            }
            Text("网络存储，随处阅读")
                .font(.subheadline)
                .foregroundStyle(ReadingTheme.ink.opacity(0.55))
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
        .padding(.bottom, 26)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(ReadingTheme.ink.opacity(0.35))
                .accessibilityHidden(true)
            Text("连接你的飞牛 NAS")
                .font(.headline)
                .foregroundStyle(ReadingTheme.ink.opacity(0.75))
            Text("内网用 SMB 直连、外网用 WebDAV 访问飞牛私有云里的书籍，直接导入书架阅读。")
                .font(.subheadline)
                .foregroundStyle(ReadingTheme.ink.opacity(0.5))
                .multilineTextAlignment(.center)
            Button {
                showingAdd = true
            } label: {
                Label("添加飞牛 NAS", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(ReadingTheme.accentFill)
            .padding(.top, 6)
            .accessibilityIdentifier("nas.add.first")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 90)
    }

    private var connectionList: some View {
        VStack(spacing: 12) {
            ForEach(store.connections) { connection in
                NavigationLink {
                    FeiniuBrowserView(connection: connection)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: connection.proto == .smb ? "externaldrive.connected.to.line.below" : "externaldrive")
                            .font(.system(size: 22))
                            .foregroundStyle(ReadingTheme.accent)
                            .frame(width: 42, height: 42)
                            .background(ReadingTheme.groupedCanvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connection.name).font(.headline).foregroundStyle(ReadingTheme.ink)
                            Text(connection.displayAddress)
                                .font(.caption)
                                .foregroundStyle(ReadingTheme.ink.opacity(0.5))
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ReadingTheme.ink.opacity(0.3))
                    }
                    .padding(14)
                    .background(ReadingTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nas.connection.\(connection.id.uuidString)")
                .contextMenu {
                    Button("编辑") { editing = connection }
                    Button("删除", role: .destructive) { store.delete(connection) }
                }
            }

            Button {
                showingAdd = true
            } label: {
                Label("添加另一台飞牛 NAS", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(ReadingTheme.accent)
            .padding(.top, 4)
        }
        .padding(.horizontal, 26)
    }
}

// MARK: - 连接表单

struct FeiniuConnectionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: FeiniuConnectionStore

    let connection: FeiniuConnection?
    @State private var name: String
    @State private var proto: NASProtocol
    @State private var scheme: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var rootPath: String
    @State private var share: String
    @State private var testing = false
    @State private var testResult: String?
    @State private var errorMessage: String?

    init(store: FeiniuConnectionStore, connection: FeiniuConnection? = nil) {
        self.store = store
        self.connection = connection
        let initialProto = connection?.proto ?? .smb
        _name = State(initialValue: connection?.name ?? "飞牛 NAS")
        _proto = State(initialValue: initialProto)
        _scheme = State(initialValue: connection?.scheme ?? "http")
        _host = State(initialValue: connection?.host ?? "")
        _port = State(initialValue: String(connection?.port ?? initialProto.defaultPort))
        _username = State(initialValue: connection?.username ?? "")
        _password = State(initialValue: connection?.password ?? "")
        _rootPath = State(initialValue: connection?.rootPath ?? "/")
        _share = State(initialValue: connection?.share ?? "")
    }

    private var draft: FeiniuConnection {
        var value = connection ?? FeiniuConnection()
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "飞牛 NAS" : name
        value.proto = proto
        value.scheme = scheme
        value.host = FeiniuConnection.cleanedHost(host)
        value.port = Int(port) ?? (proto == .smb ? 445 : (scheme == "https" ? 5006 : 5005))
        value.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        value.password = password
        let path = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        value.rootPath = path.isEmpty ? "/" : (path.hasPrefix("/") ? path : "/" + path)
        value.share = share.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    private var canSave: Bool {
        !draft.host.isEmpty && !draft.username.isEmpty && !draft.password.isEmpty &&
        (proto == .webdav || !draft.share.isEmpty)
    }

    var body: some View {
        ReadingNavigationStack {
            Form {
                Section("协议") {
                    Picker("连接方式", selection: $proto) {
                        ForEach(NASProtocol.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: proto) { newValue in
                        if port.isEmpty || port == "5005" || port == "5006" || port == "445" {
                            port = String(newValue.defaultPort)
                        }
                    }
                    Text(proto == .smb
                         ? "SMB 适合在内网/Wi-Fi 下直连飞牛，速度更快；需先在飞牛「设置 → 文件服务 → SMB」启用并记下共享名。"
                         : "WebDAV 适合外网远程访问飞牛；需先在飞牛「设置 → 文件服务 → WebDAV」启用服务。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("服务器") {
                    TextField("名称", text: $name)
                    if proto == .webdav {
                        Picker("协议", selection: $scheme) {
                            Text("HTTP（默认 5005）").tag("http")
                            Text("HTTPS（默认 5006）").tag("https")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: scheme) { newValue in
                            port = newValue == "https" ? "5006" : "5005"
                        }
                    }
                    TextField("地址（IP 或域名）", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("nas.form.host")
                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                    if proto == .smb {
                        TextField("共享名", text: $share)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("nas.form.share")
                        Text("填飞牛 SMB 的共享文件夹名，例如「共享文件夹」或你的团队文件夹名。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("初始路径", text: $rootPath)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("飞牛根目录填 /；要直接进入团队文件夹可填 /团队文件夹名。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("账号") {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                    Text(proto == .smb
                         ? "使用飞牛 NAS 的 SMB 账号密码；仅在本机保存，用于内网连接。"
                         : "飞牛 WebDAV 需使用独立 WebDAV 账号，管理员账号默认不可直连；请先在飞牛「设置 → 文件服务 → WebDAV」启用服务，并确认目标文件夹已开启协议访问。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Label("测试连接", systemImage: "waveform.path.ecg")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing || !canSave)
                    if let testResult {
                        Label(testResult, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("连接参数仅保存在本机，不会上传到任何服务器。")
                }
            }
            .navigationTitle(connection == nil ? "添加飞牛 NAS" : "编辑连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.upsert(draft)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func testConnection() async {
        testing = true
        testResult = nil
        errorMessage = nil
        defer { testing = false }
        do {
            try await FeiniuNASService.probe(draft)
            testResult = "连接成功，可以保存了"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 目录浏览与导入

struct FeiniuBrowserView: View {
    @EnvironmentObject private var library: BookLibraryModel
    let connection: FeiniuConnection

    @State private var path: String
    @State private var entries: [NASEntry] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var downloading: String?
    @State private var toast: String?

    init(connection: FeiniuConnection, path: String? = nil) {
        self.connection = connection
        _path = State(initialValue: path ?? FeiniuNASService.initialPath(connection))
    }

    var body: some View {
        Group {
            if loading && entries.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在读取目录…").font(.subheadline).foregroundStyle(.secondary)
                }
            } else if let errorMessage, entries.isEmpty {
                ReadingUnavailableView("无法连接飞牛 NAS", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
            } else {
                List {
                    if !entries.isEmpty {
                        Section {
                            ForEach(entries) { entry in
                                if entry.isDirectory {
                                    NavigationLink {
                                        FeiniuBrowserView(connection: connection, path: entry.path)
                                    } label: {
                                        entryRow(entry, systemImage: "folder")
                                    }
                                } else {
                                    Button {
                                        Task { await importEntry(entry) }
                                    } label: {
                                        HStack {
                                            entryRow(entry, systemImage: "doc.text")
                                            if downloading == entry.path {
                                                ProgressView().padding(.leading, 6)
                                            }
                                        }
                                    }
                                    .disabled(downloading != nil)
                                }
                            }
                        } header: {
                            Text("\(entries.count) 项 · 点击文件导入书架")
                        }
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).font(.caption).foregroundStyle(.orange) }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(path == FeiniuNASService.initialPath(connection) ? connection.name : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: path) { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loading)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(ReadingTheme.emphasisSurface, in: Capsule())
                    .foregroundStyle(ReadingTheme.onAccent)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut, value: toast)
        .accessibilityIdentifier("nas.browser.list")
    }

    private func entryRow(_ entry: NASEntry, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(entry.isDirectory ? ReadingTheme.coral : ReadingTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.body).foregroundStyle(ReadingTheme.ink).lineLimit(1)
                if !entry.isDirectory {
                    Text(entry.size > 0 ? formattedSize(entry.size) : "文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            entries = try await FeiniuNASService.list(connection, path: path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importEntry(_ entry: NASEntry) async {
        guard downloading == nil else { return }
        downloading = entry.path
        defer { downloading = nil }
        do {
            let localURL = try await FeiniuNASService.download(connection, entry: entry)
            await library.importLocalFiles([localURL])
            try? FileManager.default.removeItem(at: localURL.deletingLastPathComponent())
            let message = library.errorMessage ?? "已导入《\(entry.name)》"
            toast = message
            library.clearError()
        } catch {
            toast = "导入失败：\(error.localizedDescription)"
        }
    }
}
