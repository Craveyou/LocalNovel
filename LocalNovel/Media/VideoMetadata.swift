import Foundation
import SwiftUI
import AVFoundation

// MARK: - 视频元信息（大小 / 时长）
//
// 短剧的每一集在目录里要显示「128.4 MB · 12:36」。
// 读时长要解析文件头（AVAsset），远端文件还会发一次 Range 请求，所以：
//   · 只在行滚动到可见时按需加载（.task），不做整目录预扫；
//   · 结果按路径缓存，翻回去不再重复读；
//   · 读不到就只显示大小，不阻塞列表。

struct VideoInfo: Equatable {
    var byteCount: Int64?
    var seconds: Double?
}

final class VideoMetaStore: ObservableObject {
    static let shared = VideoMetaStore()

    @Published private(set) var infos: [String: VideoInfo] = [:]
    private var loading: Set<String> = []

    func info(for url: URL) -> VideoInfo? { infos[url.absoluteString] }

    func load(_ url: URL) async {
        await load(url, headers: [:], knownSize: nil)
    }

    /// 远端视频：带认证头读时长；大小由 PROPFIND 给，不必再问一次
    func load(_ url: URL, headers: [String: String], knownSize: Int64?) async {
        let key = url.absoluteString
        guard infos[key] == nil, !loading.contains(key) else { return }
        loading.insert(key)
        defer { loading.remove(key) }

        let bytes = knownSize ?? (try? url.resourceValues(forKeys: [.fileSizeKey]))
            .flatMap { $0.fileSize }
            .map { Int64($0) }

        var seconds: Double?
        let asset = headers.isEmpty
            ? AVURLAsset(url: url)
            : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        if let duration = try? await asset.load(.duration) {
            let value = CMTimeGetSeconds(duration)
            if value.isFinite, value > 0 { seconds = value }
        }
        let info = VideoInfo(byteCount: bytes, seconds: seconds)
        await MainActor.run { self.infos[key] = info }
    }
}

// MARK: - 文案格式化

enum VideoMetaFormat {
    /// 128.4 MB / 1.2 GB
    static func size(_ bytes: Int64?) -> String? {
        guard let bytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 12:36 / 1:02:03
    static func duration(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// 「128.4 MB · 12:36」；只有大小就只显示大小，都没有返回 nil
    static func line(_ info: VideoInfo?) -> String? {
        guard let info else { return nil }
        let parts = [size(info.byteCount), duration(info.seconds)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
