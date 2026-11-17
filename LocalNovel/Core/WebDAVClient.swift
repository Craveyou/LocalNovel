import Foundation

// MARK: - WebDAV 客户端（协议：WebDAV over HTTP/HTTPS）
//
// 只依赖 URLSession + XMLParser，不引第三方库：
//   PROPFIND Depth:1  列目录（名称 / 是否目录 / 大小）
//   PROPFIND Depth:0  探活（判断内网 / 外网哪条路通）
//   GET               取文件（图片等，视频不在这里走）
//
// 飞牛：控制面板 → 文件共享 → WebDAV 开启，端口默认 5005（http）/ 5006（https），
// 账号用飞牛的用户名密码，路径一般就是共享目录名。

struct RemoteEntry: Identifiable, Hashable {
    let name: String
    let url: URL
    let isDirectory: Bool
    let byteCount: Int64?

    var id: String { url.absoluteString }
}

struct WebDAVAccount {
    var username: String
    var password: String
}

enum WebDAVError: LocalizedError {
    case invalidAddress
    case unauthorized
    case notWebDAV
    case badStatus(Int)
    case unreachable

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "地址格式不对，示例：http://192.168.1.10:5005"
        case .unauthorized:
            return "账号或密码不对（飞牛的用户名 / 密码）"
        case .notWebDAV:
            return "这个地址不是 WebDAV 服务，检查飞牛是否已开启 WebDAV、端口是否正确"
        case .badStatus(let code):
            return "服务器返回 \(code)"
        case .unreachable:
            return "连不上，检查地址、端口、是否在同一网络"
        }
    }
}

enum WebDAVClient {
    /// 补全协议、去掉结尾斜杠：「192.168.1.10:5005」→「http://192.168.1.10:5005」
    static func baseURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "http://" + text
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// 探活：Depth 0 的 PROPFIND，只要回 207 / 200 且带 DAV 头就认为是 WebDAV
    static func probe(base: URL, account: WebDAVAccount, timeout: TimeInterval = 2.5) async throws {
        var request = URLRequest(url: base, timeoutInterval: timeout)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.propfindBody
        authorize(&request, account: account)

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.unreachable }
        switch http.statusCode {
        case 200, 207:
            return
        case 401, 403:
            throw WebDAVError.unauthorized
        case 405, 501:
            throw WebDAVError.notWebDAV
        default:
            throw WebDAVError.badStatus(http.statusCode)
        }
    }

    /// 列一层目录（Depth 1），结果按自然序：目录在前，再按名称
    static func list(dir: URL, account: WebDAVAccount,
                     timeout: TimeInterval = 12) async throws -> [RemoteEntry] {
        var request = URLRequest(url: dir, timeoutInterval: timeout)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.propfindBody
        authorize(&request, account: account)

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.unreachable }
        switch http.statusCode {
        case 207, 200: break
        case 401, 403: throw WebDAVError.unauthorized
        case 404: throw WebDAVError.badStatus(404)
        case 405, 501: throw WebDAVError.notWebDAV
        default: throw WebDAVError.badStatus(http.statusCode)
        }

        let parser = PropfindParser()
        guard parser.parse(data) else { throw WebDAVError.notWebDAV }

        let selfPath = normalizedPath(dir)
        var entries: [RemoteEntry] = []
        for raw in parser.items {
            guard let href = raw.href,
                  let resolved = URL(string: href, relativeTo: dir)?.absoluteURL else { continue }
            if normalizedPath(resolved) == selfPath { continue }
            let name = resolved.lastPathComponent.removingPercentEncoding ?? resolved.lastPathComponent
            if name.isEmpty { continue }
            if name.hasPrefix(".") { continue }
            entries.append(RemoteEntry(name: name, url: resolved,
                                       isDirectory: raw.isCollection,
                                       byteCount: raw.byteCount))
        }
        let dirs = NaturalSort.sorted(entries.filter { $0.isDirectory }) { $0.name }
        let files = NaturalSort.sorted(entries.filter { !$0.isDirectory }) { $0.name }
        return dirs + files
    }

    /// 取整个文件（图片、剧照用；视频走 AVPlayer 流式播放）
    static func data(_ url: URL, account: WebDAVAccount,
                     timeout: TimeInterval = 30) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        authorize(&request, account: account)
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.unreachable }
        switch http.statusCode {
        case 200: return data
        case 401, 403: throw WebDAVError.unauthorized
        default: throw WebDAVError.badStatus(http.statusCode)
        }
    }

    /// 视频播放用的请求头（AVPlayer 不会走我们上面的 URLSession）
    static func headers(account: WebDAVAccount) -> [String: String] {
        guard !account.username.isEmpty else { return [:] }
        let token = Data("\(account.username):\(account.password)".utf8).base64EncodedString()
        return ["Authorization": "Basic \(token)"]
    }

    // MARK: - 内部

    private static let propfindBody = Data("""
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:">
      <d:prop>
        <d:resourcetype/>
        <d:getcontentlength/>
      </d:prop>
    </d:propfind>
    """.utf8)

    private static func authorize(_ request: inout URLRequest, account: WebDAVAccount) {
        guard !account.username.isEmpty else { return }
        let token = Data("\(account.username):\(account.password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
    }

    /// 全工程共用一条会话：https 时由系统按 ALPN 自动协商 HTTP/2（单连接多路复用），
    /// http 时退回 HTTP/1.1 keep-alive + 最多 4 条并发连接。
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        // 单次传输上限要留够：PDF / 大图走的是请求级 120s，
        // 会话级 60s 会先到点，把「网络慢」误报成「连不上」
        config.timeoutIntervalForResource = 180
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config,
                          delegate: ProtocolProbe.shared,
                          delegateQueue: nil)
    }()

    /// 上一次请求实际用的协议：h2 / h3 表示多路复用已生效
    static var lastProtocolName: String? { ProtocolProbe.shared.lastProtocol }

    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            // 主动取消（快速返回列表 / 关掉章节页）不是「连不上」。
            // 原来一律映射成 unreachable，会顺手作废已探测好的连接，
            // 下次进列表又要重新探内网 + 外网各 2.5 秒。
            throw CancellationError()
        } catch {
            throw WebDAVError.unreachable
        }
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = url.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path.removingPercentEncoding ?? path
    }
}

// MARK: - 协议探测（判断 https 下有没有真的走 HTTP/2）

final class ProtocolProbe: NSObject, URLSessionTaskDelegate {
    static let shared = ProtocolProbe()

    private let lock = NSLock()
    private var value: String?

    var lastProtocol: String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    /// 「h2」→「HTTP/2（多路复用）」；没有协议名（缓存命中 / 失败）时保持原值
    var displayName: String? {
        guard let value else { return nil }
        switch value {
        case "h2", "h2c": return "HTTP/2（多路复用）"
        case "h3", "h3-29": return "HTTP/3（多路复用）"
        case "http/1.1": return "HTTP/1.1"
        default: return value
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let name = metrics.transactionMetrics.last?.networkProtocolName,
              !name.isEmpty else { return }
        lock.lock()
        value = name
        lock.unlock()
    }
}

// MARK: - PROPFIND 响应解析

private final class PropfindParser: NSObject, XMLParserDelegate {
    struct Item {
        var href: String?
        var isCollection = false
        var byteCount: Int64?
    }

    private(set) var items: [Item] = []
    private var current: Item?
    private var text = ""

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = self
        return parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String]) {
        text = ""
        switch elementName {
        case "response":
            current = Item()
        case "collection":
            current?.isCollection = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard var item = current else { return }
        switch elementName {
        case "href":
            item.href = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "getcontentlength":
            item.byteCount = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case "response":
            items.append(item)
            current = nil
            return
        default:
            break
        }
        current = item
    }
}
