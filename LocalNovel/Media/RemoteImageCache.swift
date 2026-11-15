import Foundation
import UIKit
import CryptoKit

// MARK: - 远端图片缓存（WebDAV 图片 → 本地缓存 → UIImage）
//
// NAS 上的剧照 / 插图必须带认证头下载，UIImage 不能直接吃 URL。
// 策略：内存 NSCache + 磁盘 Caches/RemoteImages，键是 URL 的 SHA256。
// 视频不走这里：AVPlayer 自己按 Range 流式播放，不落地整个文件。
//
// 磁盘有上限（设置页可调，默认 512 MB）：每次落盘后按「最久未修改」淘汰，
// 直到总量不超过上限；上限 0 表示不限制。

final class RemoteImageCache {
    static let shared = RemoteImageCache()

    /// 缓存占用快照（设置页展示用）
    struct Usage: Equatable {
        var bytes: Int64 = 0
        var files: Int = 0

        var isEmpty: Bool { bytes == 0 }
    }

    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    private let session: URLSession
    /// 串行队列：目录读写、统计、淘汰都排队，避免边写边删打架
    private let queue = DispatchQueue(label: "LocalNovel.remoteImageCache", qos: .utility)

    private init() {
        memory.countLimit = 40
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        folder = caches.appendingPathComponent("RemoteImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    /// 当前设置的上限（字节）；0 = 不限制
    private var configuredLimit: Int64 {
        Int64(Preferences.shared.networkImageCacheMB) * 1024 * 1024
    }

    // MARK: 读取

    func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: key(url) as NSString)
    }

    func image(for url: URL, account: WebDAVAccount) async -> UIImage? {
        if let hit = cachedImage(for: url) { return hit }

        let file = folder.appendingPathComponent(digest(url.absoluteString))
        if let data = await readFile(file), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key(url) as NSString)
            return image
        }

        guard let data = try? await download(url, account: account),
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key(url) as NSString)
        // 落盘与淘汰都放后台队列：翻页时不要让写盘卡住主线程
        let limit = configuredLimit
        let target = folder
        let payload = data
        queue.async {
            try? payload.write(to: target, options: .atomic)
            _ = Self.trim(folder: target, limit: limit)
        }
        return image
    }

    private func download(_ url: URL, account: WebDAVAccount) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        if !account.username.isEmpty {
            let token = Data("\(account.username):\(account.password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WebDAVError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    // MARK: 统计 / 清理（设置页）

    /// 统计磁盘占用（后台扫描，目录里通常几百个文件，毫秒级）
    func usage() async -> Usage {
        await withCheckedContinuation { (continuation: CheckedContinuation<Usage, Never>) in
            queue.async { continuation.resume(returning: Self.measure(folder: self.folder)) }
        }
    }

    /// 清空磁盘缓存，返回释放的字节数；内存缓存一并清掉
    @discardableResult
    func clear() async -> Int64 {
        memory.removeAllObjects()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int64, Never>) in
            queue.async {
                let before = Self.measure(folder: self.folder).bytes
                let fm = FileManager.default
                let files = (try? fm.contentsOfDirectory(at: self.folder,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles])) ?? []
                for file in files { try? fm.removeItem(at: file) }
                continuation.resume(returning: before)
            }
        }
    }

    /// 设置里改完上限后立刻按新上限裁一次
    func enforceLimit() async {
        let limit = configuredLimit
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                _ = Self.trim(folder: self.folder, limit: limit)
                continuation.resume()
            }
        }
    }

    // MARK: 目录操作

    private func readFile(_ file: URL) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            queue.async { continuation.resume(returning: try? Data(contentsOf: file)) }
        }
    }

    static func measure(folder: URL) -> Usage {
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                includingPropertiesForKeys: Array(keys),
                                                                options: [.skipsHiddenFiles])) ?? []
        var usage = Usage()
        for file in files {
            let size = (try? file.resourceValues(forKeys: keys))?.fileSize ?? 0
            usage.bytes += Int64(size)
            usage.files += 1
        }
        return usage
    }

    /// 按「最久未修改」从旧到新删，直到总量 <= limit。limit <= 0 时不删。
    @discardableResult
    static func trim(folder: URL, limit: Int64) -> Usage {
        guard limit > 0 else { return measure(folder: folder) }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                includingPropertiesForKeys: Array(keys),
                                                                options: [.skipsHiddenFiles])) ?? []
        var entries: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0
        for file in files {
            let values = try? file.resourceValues(forKeys: keys)
            let size = Int64(values?.fileSize ?? 0)
            total += size
            entries.append((file, size, values?.contentModificationDate ?? .distantPast))
        }
        guard total > limit else { return Usage(bytes: total, files: entries.count) }

        entries.sort { $0.date < $1.date }
        var remaining = entries.count
        for entry in entries {
            if total <= limit { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
            remaining -= 1
        }
        return Usage(bytes: max(0, total), files: max(0, remaining))
    }

    // MARK: 键

    private func key(_ url: URL) -> String { url.absoluteString }

    private func digest(_ text: String) -> String {
        let hash = SHA256.hash(data: Data(text.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
