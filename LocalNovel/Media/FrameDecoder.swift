import Foundation
import ImageIO
import UIKit

// MARK: - 动图解码（ImageIO，零第三方依赖）
// SwiftUI 的 Image 对 GIF/APNG 只显示第一帧，这里逐帧解码并读取每帧延时。
// 内存保护：限制帧数与单边像素，并用 NSCache 控制同时驻留的动图数量。

struct AnimatedFrame {
    let image: UIImage
    let duration: TimeInterval
}

private final class FrameBox: NSObject {
    let frames: [AnimatedFrame]
    init(_ frames: [AnimatedFrame]) { self.frames = frames }
}

final class AnimatedFrameCache {
    static let shared = AnimatedFrameCache()
    private let cache = NSCache<NSURL, FrameBox>()

    private init() {
        cache.countLimit = 12 // 最多驻留 12 张动图的帧数据
    }

    func frames(for url: URL) -> [AnimatedFrame] {
        let key = url as NSURL
        if let box = cache.object(forKey: key) { return box.frames }
        let decoded = FrameDetector.decode(url: url)
        cache.setObject(FrameBox(decoded), forKey: key)
        return decoded
    }
}

enum FrameDetector {
    /// 精确动图判定：ImageIO 帧数 > 1（比按扩展名更可靠）
    static func isAnimated(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    static func frameCount(_ url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return CGImageSourceGetCount(source)
    }

    /// 解码动图为帧序列；帧数过多时等间隔抽样，避免内存暴涨
    static func decode(url: URL, maxFrames: Int = 90, maxDimension: Int = 1200) -> [AnimatedFrame] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            if let image = ImageLoader.load(url: url, maxPixel: maxDimension) {
                return [AnimatedFrame(image: image, duration: 0)]
            }
            return []
        }

        let step = max(1, count / maxFrames)
        var indices: [Int] = []
        var i = 0
        while i < count {
            indices.append(i)
            i += step
        }

        let thumbnailOptions: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: maxDimension,
            kCGImageSourceShouldCacheImmediately as String: true
        ]

        var frames: [AnimatedFrame] = []
        frames.reserveCapacity(indices.count)
        for index in indices {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions as CFDictionary) else { continue }
            let image = UIImage(cgImage: cg)
            // 抽样时把被跳过帧的时长累加，保持总节奏不变
            var duration: TimeInterval = 0
            for k in index..<min(index + step, count) {
                duration += delay(at: k, in: source)
            }
            frames.append(AnimatedFrame(image: image, duration: max(0.02, duration)))
        }
        return frames
    }

    /// GIF / APNG 每帧延时；取不到时用 0.1s 兜底
    private static func delay(at index: Int, in source: CGImageSource) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] else {
            return 0.1
        }
        if let gif = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
            let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double ?? 0
            let clamped = gif[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0
            let d = unclamped > 0 ? unclamped : clamped
            return d >= 0.02 ? d : 0.1
        }
        if let png = props[kCGImagePropertyPNGDictionary as String] as? [String: Any],
           let d = png["DelayTime"] as? Double, d >= 0.02 {
            return d
        }
        return 0.1
    }
}

// MARK: - 静态图降采样加载（避免大图直接进内存）

enum ImageLoader {
    static func load(url: URL, maxPixel: Int = 1600) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: maxPixel,
            kCGImageSourceShouldCacheImmediately as String: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}
