import SwiftUI
import Network
#if canImport(FoundationXML)
import FoundationXML
#endif
import AMSMB2

// MARK: - 飞牛 NAS 连接模型

/// NAS 访问协议。App 自动探测：内网走 SMB，外网走 WebDAV。
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

    var other: NASProtocol { self == .smb ? .webdav : .smb }
}

/// 一条飞牛 NAS 的连接配置（内外网共用一个入口，但两条链路各有各的地址），持久化在 UserDefaults。
/// - smbHost：局域网 IP，内网走 SMB2/3 直连
/// - webdavHost：外网域名（或公网 IP），外网走 WebDAV
/// App 自动探测当前可用链路并记住结果；两套账号可不同，WebDAV 留空时复用主账号。
struct FeiniuConnection: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String = "飞牛 NAS"
    var smbHost: String = ""              // 局域网 IP（SMB）
    var webdavHost: String = ""           // 外网域名（WebDAV）
    var username: String = ""             // SMB 账号（主账号）
    var password: String = ""
    var share: String = ""                // SMB 共享名
    var smbPort: Int = 445
    var webdavScheme: String = "http"     // http / https
    var webdavPort: Int = 5005
    var webdavRootPath: String = "/"
    var webdavUsername: String = ""       // 留空复用主账号
    var webdavPassword: String = ""
    var createdAt: Date = Date()

    init() {}

    var smbAddress: String {
        guard !smbHost.isEmpty else { return "未配置地址" }
        return "smb://\(smbHost):\(smbPort)/\(share)"
    }

    var webdavAddress: String {
        guard !webdavHost.isEmpty else { return "未配置地址" }
        return "\(webdavScheme)://\(webdavHost):\(webdavPort)\(webdavRootPath)"
    }

    /// 连接列表上的两行地址摘要：内网 IP / 外网域名。
    var lanAddressText: String { smbHost.isEmpty ? "内网：未配置" : "内网：\(smbHost)" }
    var wanAddressText: String { webdavHost.isEmpty ? "外网：未配置" : "外网：\(webdavHost)" }

    var effectiveWebDAVUsername: String { webdavUsername.isEmpty ? username : webdavUsername }
    var effectiveWebDAVPassword: String { webdavPassword.isEmpty ? password : webdavPassword }

    /// 去掉用户可能一并粘贴的 scheme 与端口，只保留主机部分。
    static func cleanedHost(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), url.scheme != nil, let host = url.host { value = host }
        if let colon = value.firstIndex(of: ":") { value = String(value[..<colon]) }
        return value
    }
}

/// 旧版 v3（单地址，SMB 与 WebDAV 共用一个 host）数据结构，仅用于迁移。
private struct FeiniuConnectionV3: Decodable {
    var id: UUID?
    var name: String?
    var host: String?
    var username: String?
    var password: String?
    var share: String?
    var smbPort: Int?
    var webdavScheme: String?
    var webdavPort: Int?
    var webdavRootPath: String?
    var webdavUsername: String?
    var webdavPassword: String?
    var createdAt: Date?
}

/// 旧版 v1/v2（单协议）数据结构，仅用于迁移。
private struct FeiniuConnectionV2: Decodable {
    var id: UUID?
    var name: String?
    var proto: String?
    var scheme: String?
    var host: String?
    var port: Int?
    var username: String?
    var password: String?
    var rootPath: String?
    var share: String?
    var createdAt: Date?
}

@MainActor
final class FeiniuConnectionStore: ObservableObject {
    @Published private(set) var connections: [FeiniuConnection] = []
    private let defaults: UserDefaults
    private let key = "nas.feiniu.connections.v4"
    private let legacyKeys = ["nas.feiniu.connections.v3", "nas.feiniu.connections.v2", "nas.feiniu.connections.v1"]

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
        // v3：单地址。旧地址先同时填入内网/外网，用户可在编辑页改成各自的 IP / 域名。
        if let data = defaults.data(forKey: "nas.feiniu.connections.v3"),
           let old = try? JSONDecoder().decode([FeiniuConnectionV3].self, from: data) {
            connections = old.map { item in
                var value = FeiniuConnection()
                value.id = item.id ?? UUID()
                value.name = item.name ?? "飞牛 NAS"
                let legacy = item.host ?? ""
                value.smbHost = legacy
                value.webdavHost = legacy
                value.username = item.username ?? ""
                value.password = item.password ?? ""
                value.share = item.share ?? ""
                value.smbPort = item.smbPort ?? 445
                value.webdavScheme = item.webdavScheme ?? "http"
                value.webdavPort = item.webdavPort ?? 5005
                value.webdavRootPath = item.webdavRootPath ?? "/"
                value.webdavUsername = item.webdavUsername ?? ""
                value.webdavPassword = item.webdavPassword ?? ""
                value.createdAt = item.createdAt ?? Date()
                return value
            }
            persist()
            return
        }
        for legacy in ["nas.feiniu.connections.v2", "nas.feiniu.connections.v1"] {
            guard let data = defaults.data(forKey: legacy),
                  let old = try? JSONDecoder().decode([FeiniuConnectionV2].self, from: data) else { continue }
            connections = old.map { item in
                var value = FeiniuConnection()
                value.id = item.id ?? UUID()
                value.name = item.name ?? "飞牛 NAS"
                let host = item.host ?? ""
                value.smbHost = host
                value.webdavHost = host
                value.username = item.username ?? ""
                value.password = item.password ?? ""
                value.share = item.share ?? ""
                value.webdavScheme = item.scheme ?? "http"
                value.webdavPort = item.proto == "smb" ? 5005 : (item.port ?? 5005)
                value.webdavRootPath = item.rootPath ?? "/"
                value.createdAt = item.createdAt ?? Date()
                return value
            }
            persist()
            return
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
        UserDefaults.standard.removeObject(forKey: FeiniuNASService.cacheKey(connection.id))
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
    case noLink(smbHost: String, smbError: String, webdavHost: String, webdavError: String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "地址或端口无效：内网填局域网 IP、外网填域名（均不含协议和端口）"
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
        case .noLink(let smbHost, let smbError, let webdavHost, let webdavError):
            "两条链路都不可用。内网 SMB（\(smbHost)）：\(smbError)；外网 WebDAV（\(webdavHost)）：\(webdavError)。请分别检查内网 IP 与外网域名，及飞牛「文件服务」中 SMB / WebDAV 是否已启用。"
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

/// 网络环境探测：判断设备当前是否具备访问内网 SMB 的条件。
/// 用 NWPathMonitor 读取系统网络路径，比"IP 是不是私有段"更可靠：
/// - Wi-Fi / 以太网且已连通：尝试内网 SMB；
/// - 蜂窝 / 未连通：跳过 SMB，直接走外网 WebDAV，避免拿内网 IP 空等超时。
private enum NASNetwork {
    /// 逃逸闭包里的一次性标志，避免重复 resume continuation。
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }

    /// 旧判断：只看"有没有 Wi-Fi/以太网"，无法区分家里的 WiFi 和外面的 WiFi，已不再作为链路依据。
    /// 保留仅为诊断参考，实际选路一律以 canReachSMB 的 TCP 预检结果为准。
    static func hasLocalInterface() async -> Bool {
        await withCheckedContinuation { continuation in
            let once = Once()
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "nas.network.probe")
            monitor.pathUpdateHandler = { path in
                guard once.claim() else { return }
                let usable = path.status == .satisfied &&
                    (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
                continuation.resume(returning: usable)
                monitor.cancel()
            }
            monitor.start(queue: queue)
        }
    }

    /// 方案1：对 smbHost:smbPort 做一次带硬超时的 TCP 连接预检。
    /// 只有 445 端口真的能握手，才判定"当前可达 NAS 内网"，进而允许尝试 SMB。
    /// - 外面 WiFi / 蜂窝：445 不通 → 1.5s 内失败，直接跳过 SMB，绝不进入 AMSMB2 的不可取消 connect。
    /// - 人在内网：445 通 → 强制 SMB 优先，即使上次缓存的是 WebDAV 也不会继续走外网。
    /// NWConnection 的 connect 可被 cancel，配合 DispatchSourceTimer 实现真正的硬超时。
    /// 承载不可 Sendable 的 NWConnection / Timer，供 @Sendable 回调安全捕获。
    /// finish 做成方法而非闭包，避免"非 Sendable 闭包被 @Sendable 回调捕获"的编译错误。
    private final class TCPProbeBox: @unchecked Sendable {
        let once = Once()
        var connection: NWConnection?
        var timer: DispatchSourceTimer?
        var continuation: CheckedContinuation<Bool, Never>?

        func finish(_ reachable: Bool) {
            guard once.claim() else { return }
            timer?.cancel()
            connection?.cancel()
            continuation?.resume(returning: reachable)
        }
    }

    static func canReachSMB(host: String, port: Int, timeout: TimeInterval = 1.5) async -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, (1...65535).contains(port),
              let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(trimmed), port: nwPort)
        return await withCheckedContinuation { continuation in
            let box = TCPProbeBox()
            box.continuation = continuation
            let queue = DispatchQueue(label: "nas.smb.tcp.probe")
            let connection = NWConnection(to: endpoint, using: .tcp)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            box.connection = connection
            box.timer = timer
            // 回调只捕获 box（@unchecked Sendable），并通过它的方法收尾，
            // 不捕获任何非 Sendable 闭包或对象，满足 Swift 6 严格并发检查。
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: box.finish(true)
                case .failed, .cancelled: box.finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler { box.finish(false) }
            timer.resume()
        }
    }
}

/// SMB2/3 客户端（内网直连）：基于 AMSMB2/libsmb2。
/// 每条连接独立创建 SMB2Manager，Swift 对象释放时库会自动断开共享。
private enum FeiniuSMB {
    /// 探测用短超时，避免公网环境连 445 端口长时间阻塞。
    static func probe(_ connection: FeiniuConnection, timeout: TimeInterval = 4) async throws {
        let manager = try makeManager(connection, timeout: timeout)
        try await connect(manager, connection)
    }

    static func list(_ connection: FeiniuConnection, path: String) async throws -> [NASEntry] {
        let manager = try makeManager(connection, timeout: 8)
        try await connect(manager, connection)
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
        let manager = try makeManager(connection, timeout: 20)
        try await connect(manager, connection)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("feiniu-smb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = entry.name.isEmpty ? "download" : entry.name
        let target = folder.appendingPathComponent(filename)
        try await manager.downloadItem(atPath: entry.path, to: target, progress: nil)
        return target
    }

    private static func makeManager(_ connection: FeiniuConnection, timeout: TimeInterval) throws -> SMB2Manager {
        guard !connection.smbHost.isEmpty, (1...65535).contains(connection.smbPort),
              let url = URL(string: "smb://\(connection.smbHost):\(connection.smbPort)") else {
            throw FeiniuError.invalidAddress
        }
        guard !connection.share.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FeiniuError.missingShare
        }
        let credential = URLCredential(user: connection.username, password: connection.password, persistence: .forSession)
        guard let manager = SMB2Manager(url: url, domain: "", credential: credential) else {
            throw FeiniuError.smb("无法初始化 SMB 客户端")
        }
        manager.timeout = timeout
        return manager
    }

    /// 底层 connectShare 是同步阻塞调用且不响应 Swift 取消，无法在 Swift 层硬超时。
    /// 真正的防护在上层 NASNetwork：无内网接口时根本不会调用到这里。
    private static func connect(_ manager: SMB2Manager, _ connection: FeiniuConnection) async throws {
        try await manager.connectShare(name: connection.share)
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
    static func probe(_ connection: FeiniuConnection, timeout: TimeInterval = 8) async throws {
        let (_, response) = try await request(connection, method: "PROPFIND", path: connection.webdavRootPath,
                                              depth: "0", timeout: timeout)
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

    private static func request(_ connection: FeiniuConnection, method: String, path: String, depth: String?, timeout: TimeInterval = 25) async throws -> (Data, HTTPURLResponse) {
        var urlRequest = try makeRequest(connection, method: method, path: path, timeout: timeout)
        if let depth { urlRequest.setValue(depth, forHTTPHeaderField: "Depth") }
        if method == "PROPFIND" { urlRequest.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        let session = makeSession()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw FeiniuError.nonHTTP }
        return (data, http)
    }

    private static func makeRequest(_ connection: FeiniuConnection, method: String, path: String, timeout: TimeInterval = 25) throws -> URLRequest {
        guard !connection.webdavHost.isEmpty, (1...65535).contains(connection.webdavPort) else { throw FeiniuError.invalidAddress }
        var components = URLComponents()
        components.scheme = connection.webdavScheme
        components.host = connection.webdavHost
        components.port = connection.webdavPort
        let target = path.isEmpty ? "/" : path
        components.path = target.hasPrefix("/") ? target : "/" + target
        guard let url = components.url else { throw FeiniuError.invalidAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        let basic = Data("\(connection.effectiveWebDAVUsername):\(connection.effectiveWebDAVPassword)".utf8).base64EncodedString()
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

/// 自动探测结果缓存：key 为连接 id，value 为上次成功的协议。
/// 网络切换后缓存可能失效，list 失败时会自动重新探测并切换。
private enum FeiniuNASService {
    private static let cachePrefix = "nas.feiniu.link."

    static func cacheKey(_ id: UUID) -> String { cachePrefix + id.uuidString }

    private static func cached(_ connection: FeiniuConnection) -> NASProtocol? {
        guard let raw = UserDefaults.standard.string(forKey: cacheKey(connection.id)) else { return nil }
        return NASProtocol(rawValue: raw)
    }

    private static func store(_ proto: NASProtocol, for connection: FeiniuConnection) {
        UserDefaults.standard.set(proto.rawValue, forKey: cacheKey(connection.id))
    }

    /// 网络变化后清掉旧链路缓存，避免"人在内网却沿用上次 WebDAV 缓存"。
    static func clearCache(for connection: FeiniuConnection) {
        UserDefaults.standard.removeObject(forKey: cacheKey(connection.id))
    }

    /// 上次探测到的链路，仅用于 UI 展示；nil 表示还没探测过。
    static func activeProtocol(_ connection: FeiniuConnection) -> NASProtocol? {
        cached(connection)
    }

    /// 当前网络下这条链路是否"可用到值得尝试"。
    /// smbReachable 来自 canReachSMB 的真实 TCP 探测（445 握手成功），不是"是否连着 WiFi"。
    /// - WiFi 但不在 NAS 内网（外面 WiFi）：445 不通 → 排除 SMB，直接走 WebDAV，不卡死。
    /// - 在内网：445 通 → SMB 可用。
    private static func isViable(_ proto: NASProtocol, _ connection: FeiniuConnection, smbReachable: Bool) -> Bool {
        let configured = proto == .smb
            ? !connection.smbHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : !connection.webdavHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !configured { return false }
        if proto == .smb && !smbReachable { return false }
        return true
    }

    /// 探测两条链路：smbHost 是内网 IP、webdavHost 是外网域名，各走各的地址。
    /// 先用 TCP 预检判定内网是否真的可达：
    /// - 445 通 → SMB 强制排第一（忽略旧缓存，修复"在内网却因缓存走外网"）。
    /// - 445 不通 → 只走 WebDAV，绝不调用 AMSMB2 那个不可取消的 connect。
    @discardableResult
    static func resolve(_ connection: FeiniuConnection) async throws -> NASProtocol {
        let smbReachable = await NASNetwork.canReachSMB(host: connection.smbHost, port: connection.smbPort)
        let preferred: NASProtocol = smbReachable ? .smb : .webdav
        let order: [NASProtocol] = smbReachable ? [.smb, .webdav] : [.webdav]
        var failures: [NASProtocol: String] = [:]
        for proto in order {
            guard isViable(proto, connection, smbReachable: smbReachable) else {
                failures[proto] = proto == .smb
                    ? (connection.smbHost.isEmpty ? "未配置内网 IP" : "当前网络无法连接内网 445，已跳过 SMB")
                    : "未配置外网域名"
                continue
            }
            do {
                switch proto {
                case .smb: try await FeiniuSMB.probe(connection)
                case .webdav: try await FeiniuWebDAV.probe(connection)
                }
                store(proto, for: connection)
                return proto
            } catch {
                failures[proto] = error.localizedDescription
            }
        }
        throw FeiniuError.noLink(
            smbHost: connection.smbHost.isEmpty ? "未配置" : connection.smbHost,
            smbError: failures[.smb] ?? "未测试",
            webdavHost: connection.webdavHost.isEmpty ? "未配置" : connection.webdavHost,
            webdavError: failures[.webdav] ?? "未测试"
        )
    }

    static func probe(_ connection: FeiniuConnection) async throws -> NASProtocol {
        try await resolve(connection)
    }

    /// 列目录：先用 TCP 预检判定当前网络期望的链路（445 通=内网 SMB，否则外网 WebDAV）。
    /// 缓存链路与期望一致才直接用；不一致（如人在内网但缓存是 WebDAV）则重新探测，避免继续走外网。
    /// 这样断开 WiFi / 换到外面 WiFi 后，即便缓存是 SMB，也不会拿内网 IP 去连导致卡死。
    static func list(_ connection: FeiniuConnection, path: String) async throws -> [NASEntry] {
        let smbReachable = await NASNetwork.canReachSMB(host: connection.smbHost, port: connection.smbPort)
        let expected: NASProtocol = smbReachable ? .smb : .webdav
        if let proto = cached(connection), proto == expected, isViable(proto, connection, smbReachable: smbReachable) {
            do { return try await fetch(connection, proto: proto, path: path) }
            catch {
                let refreshed = try await resolve(connection)
                if refreshed == proto { throw error }
                return try await fetch(connection, proto: refreshed, path: path)
            }
        }
        let proto = try await resolve(connection)
        return try await fetch(connection, proto: proto, path: path)
    }

    static func download(_ connection: FeiniuConnection, entry: NASEntry) async throws -> URL {
        let smbReachable = await NASNetwork.canReachSMB(host: connection.smbHost, port: connection.smbPort)
        let expected: NASProtocol = smbReachable ? .smb : .webdav
        let proto: NASProtocol
        if let cachedProto = cached(connection), cachedProto == expected,
           isViable(cachedProto, connection, smbReachable: smbReachable) {
            proto = cachedProto
        } else {
            proto = try await resolve(connection)
        }
        switch proto {
        case .smb: return try await FeiniuSMB.download(connection, entry: entry)
        case .webdav: return try await FeiniuWebDAV.download(connection, entry: entry)
        }
    }

    private static func fetch(_ connection: FeiniuConnection, proto: NASProtocol, path: String) async throws -> [NASEntry] {
        switch proto {
        case .smb: return try await FeiniuSMB.list(connection, path: path)
        case .webdav: return try await FeiniuWebDAV.list(connection, path: path)
        }
    }

    static func initialPath(_ connection: FeiniuConnection) -> String {
        cached(connection) == .smb ? "/" : connection.webdavRootPath
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
    /// 当前网络下每条连接实际可用的链路（实时 TCP 预检得出），不用旧缓存误导用户。
    @State private var liveLinks: [UUID: NASProtocol] = [:]

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
        .task(id: store.connections.map(\.id)) {
            await refreshLinks()
        }
        .sheet(isPresented: $showingAdd) {
            FeiniuConnectionFormView(store: store)
        }
        .sheet(item: $editing) { connection in
            FeiniuConnectionFormView(store: store, connection: connection)
        }
        .accessibilityIdentifier("nas.scroll")
    }

    /// 进入页面 / 连接变化时，对每条连接做一次真实 TCP 预检，更新"当前链路"标签。
    /// 只判 445 是否可达，不建立 SMB 会话，开销很小；不依赖上次缓存。
    private func refreshLinks() async {
        var result: [UUID: NASProtocol] = [:]
        for connection in store.connections {
            let reachable = await NASNetwork.canReachSMB(host: connection.smbHost, port: connection.smbPort)
            result[connection.id] = reachable ? .smb : .webdav
            if reachable { FeiniuNASService.clearCache(for: connection) }
        }
        liveLinks = result
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("NAS")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(ReadingTheme.ink.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(ReadingTheme.groupedCanvas.opacity(0.75))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nas.add.connection")
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
            Text("填内网 IP 与外网域名，App 自动识别网络：内网走 SMB、外网走 WebDAV，直接导入书架阅读。")
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
                        Image(systemName: "externaldrive.connected.to.line.below")
                            .font(.system(size: 22))
                            .foregroundStyle(ReadingTheme.accent)
                            .frame(width: 42, height: 42)
                            .background(ReadingTheme.groupedCanvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connection.name).font(.headline).foregroundStyle(ReadingTheme.ink)
                            Text(connection.lanAddressText)
                                .font(.caption)
                                .foregroundStyle(ReadingTheme.ink.opacity(0.5))
                                .lineLimit(1)
                            Text(connection.wanAddressText)
                                .font(.caption)
                                .foregroundStyle(ReadingTheme.ink.opacity(0.5))
                                .lineLimit(1)
                            if let active = liveLinks[connection.id] ?? FeiniuNASService.activeProtocol(connection) {
                                Label(active == .smb ? "当前：内网 SMB" : "当前：外网 WebDAV",
                                      systemImage: active == .smb ? "wifi" : "globe")
                                    .font(.caption2)
                                    .foregroundStyle(ReadingTheme.accent)
                            }
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
    @State private var smbHost: String
    @State private var webdavHost: String
    @State private var username: String
    @State private var password: String
    @State private var share: String
    @State private var smbPort: String
    @State private var webdavScheme: String
    @State private var webdavPort: String
    @State private var webdavRootPath: String
    @State private var webdavUsername: String
    @State private var webdavPassword: String
    @State private var testing = false
    @State private var testResult: String?
    @State private var errorMessage: String?

    init(store: FeiniuConnectionStore, connection: FeiniuConnection? = nil) {
        self.store = store
        self.connection = connection
        _name = State(initialValue: connection?.name ?? "飞牛 NAS")
        _smbHost = State(initialValue: connection?.smbHost ?? "")
        _webdavHost = State(initialValue: connection?.webdavHost ?? "")
        _username = State(initialValue: connection?.username ?? "")
        _password = State(initialValue: connection?.password ?? "")
        _share = State(initialValue: connection?.share ?? "")
        _smbPort = State(initialValue: String(connection?.smbPort ?? 445))
        _webdavScheme = State(initialValue: connection?.webdavScheme ?? "http")
        _webdavPort = State(initialValue: String(connection?.webdavPort ?? 5005))
        _webdavRootPath = State(initialValue: connection?.webdavRootPath ?? "/")
        _webdavUsername = State(initialValue: connection?.webdavUsername ?? "")
        _webdavPassword = State(initialValue: connection?.webdavPassword ?? "")
    }

    private var draft: FeiniuConnection {
        var value = connection ?? FeiniuConnection()
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "飞牛 NAS" : name
        value.smbHost = FeiniuConnection.cleanedHost(smbHost)
        value.webdavHost = FeiniuConnection.cleanedHost(webdavHost)
        value.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        value.password = password
        value.share = share.trimmingCharacters(in: .whitespacesAndNewlines)
        value.smbPort = Int(smbPort) ?? 445
        value.webdavScheme = webdavScheme
        value.webdavPort = Int(webdavPort) ?? (webdavScheme == "https" ? 5006 : 5005)
        let path = webdavRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        value.webdavRootPath = path.isEmpty ? "/" : (path.hasPrefix("/") ? path : "/" + path)
        value.webdavUsername = webdavUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        value.webdavPassword = webdavPassword
        return value
    }

    /// 至少要配置一条链路：内网 IP + 共享名，或外网域名 + 账号。
    private var canSave: Bool {
        let hasSMB = !draft.smbHost.isEmpty && !draft.share.isEmpty && !draft.username.isEmpty && !draft.password.isEmpty
        let hasWebDAV = !draft.webdavHost.isEmpty && !draft.username.isEmpty && !draft.password.isEmpty
        return hasSMB || hasWebDAV
    }

    var body: some View {
        ReadingNavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name)
                } header: {
                    Text("服务器")
                }

                Section {
                    TextField("局域网 IP（如 192.168.1.10）", text: $smbHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("nas.form.smbHost")
                    TextField("共享名", text: $share)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("nas.form.share")
                    TextField("端口（默认 445）", text: $smbPort)
                        .keyboardType(.numberPad)
                } header: {
                    Text("内网 SMB 地址")
                } footer: {
                    Text("填飞牛在局域网里的 IP，以及「文件服务 → SMB」启用的共享文件夹名；仅在家/Wi-Fi 下可达。")
                }

                Section {
                    TextField("外网域名（如 nas.example.com）", text: $webdavHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("nas.form.webdavHost")
                    Picker("协议", selection: $webdavScheme) {
                        Text("HTTP（默认 5005）").tag("http")
                        Text("HTTPS（默认 5006）").tag("https")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: webdavScheme) { newValue in
                        webdavPort = newValue == "https" ? "5006" : "5005"
                    }
                    TextField("端口", text: $webdavPort)
                        .keyboardType(.numberPad)
                    TextField("初始路径（默认 /）", text: $webdavRootPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("外网 WebDAV 地址")
                } footer: {
                    Text("填外网可访问的域名；需在飞牛「文件服务 → WebDAV」启用，并配置端口转发或反代。")
                }

                Section("账号") {
                    TextField("用户名（SMB）", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码（SMB）", text: $password)
                    TextField("WebDAV 账号（可选，留空复用上方）", text: $webdavUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("WebDAV 密码（可选）", text: $webdavPassword)
                    Text("飞牛 WebDAV 通常需要独立账号；若与 SMB 不同请单独填写。密码仅保存在本机。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Label("测试连接（自动探测）", systemImage: "waveform.path.ecg")
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
                    Text("会依次测试内网 SMB 与外网 WebDAV，显示当前可用的链路。连接参数仅保存在本机。")
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
            let proto = try await FeiniuNASService.probe(draft)
            testResult = proto == .smb
                ? "内网 SMB 可用，当前设备走内网链路"
                : "外网 WebDAV 可用，当前设备走外网链路"
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
    @State private var linkLabel: String?
    @State private var isRoot = false

    init(connection: FeiniuConnection, path: String? = nil) {
        self.connection = connection
        let root = path == nil
        _isRoot = State(initialValue: root)
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
                            HStack {
                                Text("\(entries.count) 项 · 点击文件导入书架")
                                Spacer()
                                if let linkLabel { Text(linkLabel).font(.caption2) }
                            }
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
            // 每次进入都走 resolve：它按系统网络判断可用性，断开 Wi-Fi 时会跳过 SMB、选 WebDAV。
            // 缓存链路仍可用时这里会快速探测成功，开销很小。
            let proto = try await FeiniuNASService.probe(connection)
            linkLabel = proto == .smb ? "内网 SMB" : "外网 WebDAV"
            // 根目录首次探测后按实际链路重设初始路径：SMB 从 share 根 "/" 开始，
            // WebDAV 用配置的初始路径。子目录（path 非 nil 进入）不受影响。
            if isRoot {
                let wanted = FeiniuNASService.initialPath(connection)
                if path != wanted {
                    path = wanted
                    return  // .task(id: path) 会用新路径重新加载
                }
            }
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
