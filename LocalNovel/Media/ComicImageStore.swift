import Foundation
import ImageIO
import UIKit
import SwiftUI

// MARK: - 漫画原图读取（长图专用）
//
// 旧实现是 ImageLoader(maxPixel: 1800)：这是「最长边」限制，
// 800×12000 的条漫会被缩到 120×1800，再被拉伸到满屏宽 → 看起来糊成一片；
// 而且解码写在 onAppear 里、跑在主线程 → 滑动一顿一顿。
//
// 现在：
// · 只解析文件头取像素尺寸（不加载像素），用来算精确页高，LazyVStack 不再抖动
// · 原图交给 CATiledLayer 分块绘制，只画可见 tile，1:1 像素不放大、不整图驻留
// · 像素数过大时才降采样兜底，避免一次吃掉几百 MB

final class CGImageBox: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

final class ComicImageStore {
    static let shared = ComicImageStore()

    private let lock = NSLock()
    private var sizeCache: [String: CGSize] = [:]
    private let imageCache = NSCache<NSURL, CGImageBox>()

    /// 超过这个像素数（约 40MP / RGBA 约 160MB）才降采样
    private let maxPixels = 40_000_000
    private let maxPixelSide = 4096

    private init() {
        imageCache.countLimit = 6
        imageCache.totalCostLimit = 180 * 1024 * 1024
    }

    /// 像素尺寸（不是 points）。只解析文件头，不解码像素。
    func pixelSize(of url: URL) -> CGSize? {
        let key = url.path
        lock.lock()
        if let cached = sizeCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue,
              let height = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }

        let size = CGSize(width: width, height: height)
        lock.lock()
        sizeCache[key] = size
        lock.unlock()
        return size
    }

    func image(for url: URL) -> CGImage? {
        if let box = imageCache.object(forKey: url as NSURL) { return box.image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let size = pixelSize(of: url) ?? .zero
        let cgImage: CGImage?
        if size.width * size.height > CGFloat(maxPixels) {
            let options: [String: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways as String: true,
                kCGImageSourceThumbnailMaxPixelSize as String: maxPixelSide,
                kCGImageSourceShouldCacheImmediately as String: true
            ]
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            let options: [String: Any] = [
                kCGImageSourceShouldCache as String: false
            ]
            cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        }
        guard let cgImage else { return nil }

        let cost = cgImage.width * cgImage.height * 4
        imageCache.setObject(CGImageBox(cgImage), forKey: url as NSURL, cost: cost)
        return cgImage
    }

    func clear() {
        imageCache.removeAllObjects()
    }
}

// MARK: - 分块绘制视图

/// 用 CATiledLayer 画整张原图：系统只回调当前可见 tile 的 draw，
/// 因此长图既不会超过 GPU 纹理上限，也不会把几百 MB 一次性钉在内存里。
final class TiledImageView: UIView {
    private var imageURL: URL?
    private var image: CGImage?
    private var appliedScale: CGFloat = 0

    override class var layerClass: AnyClass { CATiledLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        if let tiled = layer as? CATiledLayer {
            tiled.tileSize = CGSize(width: 1024, height: 1024)
            tiled.levelsOfDetail = 1
            tiled.levelsOfDetailBias = 0
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ url: URL) {
        guard imageURL != url else { return }
        imageURL = url
        image = ComicImageStore.shared.image(for: url)
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        let scale = window?.screen.scale ?? UITraitCollection.current.displayScale
        guard scale > 0, scale != appliedScale else { return }
        appliedScale = scale
        // contentsScale 决定 tile 的像素密度：不设就会按 1x 绘制，等于主动糊掉
        (layer as? CATiledLayer)?.contentsScale = scale
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let image, let context = UIGraphicsGetCurrentContext() else { return }
        context.interpolationQuality = .high
        context.saveGState()
        // 图片坐标原点在左下，UIKit 在左上
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: bounds)
        context.restoreGState()
    }
}

struct TiledImage: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> TiledImageView {
        let view = TiledImageView(frame: .zero)
        view.show(url)
        return view
    }

    func updateUIView(_ view: TiledImageView, context: Context) {
        view.show(url)
    }
}
