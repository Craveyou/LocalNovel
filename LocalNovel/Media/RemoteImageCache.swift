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

    /// 同时下载的张数上限：预取与可见图共用这一个池子，避免把连接数打满
    private static let maxConcurrentDownloads = 4
    private let limiter = AsyncLimiter(limit: RemoteImageCache.maxConcurrentDownloads)
    /// 同一张图正在下载时，后来的请求直接等它的结果，不重复走一遍网络
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func image(for url: URL, account: WebDAVAccount) async -> UIImage? {
        if let hit = cachedImage(for: url) { return hit }

        let token = key(url)
        lock.lock()
        if let running = inFlight[token] {
            lock.unlock()
            return await running.value
        }
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.load(url, account: account)
        }
        inFlight[token] = task
        lock.unlock()

        let image = await task.value

        lock.lock()
        inFlight[token] = nil
        lock.unlock()
        return image
    }

    /// 预取一组图片：已在内存里的直接跳过；其余进下载池排队（低优先级）。
    /// 用于剧照 / 漫画往后翻的时候提前拉好，滑到下一张不用等。
    func prefetch(_ urls: [URL], account: WebDAVAccount) {
        for url in urls {
            if memory.object(forKey: key(url) as NSString) != nil { continue }
            Task(priority: .utility) { [weak self] in
                _ = await self?.image(for: url, account: account)
            }
        }
    }

    private func load(_ url: URL, account: WebDAVAccount) async -> UIImage? {
        let file = folder.appendingPathComponent(digest(url.absoluteString))
        if let data = await readFile(file), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key(url) as NSString)
            return image
        }

        await limiter.acquire()
        let data = try? await download(url, account: account)
        await limiter.release()

        guard let data, let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key(url) as NSString)
        // 落盘与淘汰都放后台队列：翻页时不要让写盘卡住主线程
        let limit = configuredLimit
        let target = file          // 一图一文件；写成目录会让 write 必然失败（原来是 folder）
        let cacheFolder = folder
        let payload = data
        queue.async {
            try? payload.write(to: target, options: .atomic)
            _ = Self.trim(folder: cacheFolder, limit: limit)
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


// MARK: - 并发闸门
//
// 一次预取会同时发起好几个请求；没有闸门的话会把 URLSession 的连接池占满，
// 反而让屏幕上正在等的那张图排到最后。这里限制同时最多 4 个下载在飞。
actor AsyncLimiter {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        available = max(1, limit)
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
