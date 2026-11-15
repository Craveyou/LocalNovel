import Foundation
import UIKit
import CryptoKit

// MARK: - 远端图片缓存（WebDAV 图片 → 本地缓存 → UIImage）
//
// NAS 上的剧照 / 插图必须带认证头下载，UIImage 不能直接吃 URL。
// 策略：内存 NSCache + 磁盘 Caches/RemoteImages，键是 URL 的 SHA256。
// 视频不走这里：AVPlayer 自己按 Range 流式播放，不落地整个文件。

final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    private let session: URLSession

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

    func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: key(url) as NSString)
    }

    func image(for url: URL, account: WebDAVAccount) async -> UIImage? {
        if let hit = cachedImage(for: url) { return hit }

        let file = folder.appendingPathComponent(digest(url.absoluteString))
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key(url) as NSString)
            return image
        }

        guard let data = try? await download(url, account: account),
              let image = UIImage(data: data) else { return nil }
        try? data.write(to: file, options: .atomic)
        memory.setObject(image, forKey: key(url) as NSString)
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

    private func key(_ url: URL) -> String { url.absoluteString }

    private func digest(_ text: String) -> String {
        let hash = SHA256.hash(data: Data(text.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
