import Foundation
import SwiftUI

// MARK: - NAS 连接模型与状态
//
// 只支持 WebDAV（系统不向 App 开放 SMB 客户端；SMB 共享请在「文件」App 里连接，
// 再用「导入书籍文件夹」加进本地书库）。
//
// 每个连接填两个地址：内网（如 http://192.168.1.10:5005）与外网（DDNS / 公网 IP:端口）。
// 连接时先探内网、失败再探外网，结果缓存 5 分钟；切网或请求失败立刻作废重探。

struct NASConnection: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var lanAddress: String
    var wanAddress: String
    var username: String
    /// 分类 → 该分类在 NAS 上的目录（相对 WebDAV 根）。默认三名，可改。
    var categoryPaths: [String: String]

    init(id: UUID = UUID(), name: String, lanAddress: String, wanAddress: String,
         username: String, categoryPaths: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.lanAddress = lanAddress
        self.wanAddress = wanAddress
        self.username = username
        self.categoryPaths = categoryPaths
    }

    static let defaultCategoryPaths: [String: String] = [
        BookCategory.comic.rawValue: BookCategory.comic.folderName,
        BookCategory.organized.rawValue: BookCategory.organized.folderName,
        BookCategory.shortDrama.rawValue: BookCategory.shortDrama.folderName,
    ]

    func path(for category: BookCategory) -> String {
        let value = categoryPaths[category.rawValue] ?? ""
        return value.isEmpty ? category.folderName : value
    }

    /// NAS 页只放这三类（不含小说）
    static let categories: [BookCategory] = [.comic, .organized, .shortDrama]
}

/// 一条连接的连通状态
enum NASStatus: Equatable {
    case idle
    case connecting
    case connected(isLAN: Bool)
    case failed(String)

    var text: String {
        switch self {
        case .idle: return "未连接"
        case .connecting: return "正在连接…"
        case .connected(true): return "内网直连"
        case .connected(false): return "外网连接"
        case .failed(let message): return "连接失败：\(message)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - 连接存储

final class NASStore: ObservableObject {
    static let shared = NASStore()

    struct Endpoint {
        let base: URL
        let isLAN: Bool
        let resolvedAt: Date
    }

    @Published private(set) var connections: [NASConnection] = []
    @Published private(set) var status: [UUID: NASStatus] = [:]
    @Published var lastError: String?

    private let defaults = UserDefaults.standard
    private let storageKey = "LocalNovel.nas.connections"
    private var endpoints: [UUID: Endpoint] = [:]
    /// 探测结果的有效期：切网 / 失败会立刻作废，正常情况 5 分钟够用
    private let endpointTTL: TimeInterval = 300

    init() {
        load()
    }

    // MARK: 增删改

    func save(_ connection: NASConnection, password: String?) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        if let password, !password.isEmpty {
            Keychain.setPassword(password, for: connection.id.uuidString)
        }
        endpoints[connection.id] = nil
        status[connection.id] = .idle
        persist()
    }

    func delete(_ connection: NASConnection) {
        connections.removeAll { $0.id == connection.id }
        Keychain.removePassword(for: connection.id.uuidString)
        endpoints[connection.id] = nil
        status[connection.id] = nil
        persist()
    }

    func password(for connection: NASConnection) -> String {
        Keychain.password(for: connection.id.uuidString) ?? ""
    }

    func account(for connection: NASConnection) -> WebDAVAccount {
        WebDAVAccount(username: connection.username, password: password(for: connection))
    }

    // MARK: 内外网判定

    /// 先内网、后外网；都失败把原因带回来。结果缓存，失败立即可重试。
    @discardableResult
    func resolve(_ connection: NASConnection, force: Bool = false) async -> Endpoint? {
        if !force, let cached = endpoints[connection.id],
           Date().timeIntervalSince(cached.resolvedAt) < endpointTTL {
            await MainActor.run { self.status[connection.id] = .connected(isLAN: cached.isLAN) }
            return cached
        }

        await MainActor.run { self.status[connection.id] = .connecting }
        let account = account(for: connection)
        var lastMessage = "内网、外网地址都连不上"

        for (raw, isLAN) in [(connection.lanAddress, true), (connection.wanAddress, false)] {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let base = WebDAVClient.baseURL(from: text) else { continue }
            do {
                try await WebDAVClient.probe(base: base, account: account)
                let endpoint = Endpoint(base: base, isLAN: isLAN, resolvedAt: Date())
                await MainActor.run {
                    self.endpoints[connection.id] = endpoint
                    self.status[connection.id] = .connected(isLAN: isLAN)
                    self.lastError = nil
                }
                return endpoint
            } catch {
                lastMessage = (isLAN ? "内网：" : "外网：") + error.localizedDescription
            }
        }

        await MainActor.run {
            self.status[connection.id] = .failed(lastMessage)
            self.lastError = lastMessage
        }
        return nil
    }

    /// 请求失败时调用：下次进入重新探测（可能换了网络）
    func invalidate(_ connection: NASConnection) {
        endpoints[connection.id] = nil
        status[connection.id] = .idle
    }

    func status(for connection: NASConnection) -> NASStatus {
        status[connection.id] ?? .idle
    }

    // MARK: 目录访问

    func categoryURL(_ category: BookCategory,
                     connection: NASConnection,
                     endpoint: Endpoint) -> URL {
        let path = connection.path(for: category)
        var url = endpoint.base
        for segment in path.split(separator: "/") {
            url.appendPathComponent(String(segment))
        }
        return url
    }

    func list(_ url: URL, connection: NASConnection) async throws -> [RemoteEntry] {
        do {
            return try await WebDAVClient.list(dir: url, account: account(for: connection))
        } catch {
            // 连接层面的错误（掉线 / 换了网络）→ 作废探测结果，下次重探
            if let dav = error as? WebDAVError, case .unreachable = dav {
                invalidate(connection)
            }
            throw error
        }
    }

    // MARK: 持久化（不含密码，密码在钥匙串）

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([NASConnection].self, from: data) else { return }
        connections = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
