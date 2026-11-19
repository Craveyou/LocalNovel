import AppleShared
import Foundation
import ImageIO
import CoreGraphics

/// Original archive identity and natural-image coordinates never depend on display sampling.
struct ComicDocument: Sendable {
    let archive: ComicArchive
    let manifest: ComicManifest
    let format: String
    private let cache: ComicPageCache

    init(url: URL, validatePages: Bool = false) throws {
        archive = try ComicArchive(url: url)
        cache = ComicPageCache()
        format = archive.format
        guard ["cbz", "cbr"].contains(format) else { throw DocumentError.unsupported("不支持的漫画容器") }
        manifest = try ComicManifest(entries: archive.entries.map {
            .init(path: $0.path, kind: $0.isLink ? .symbolicLink : ($0.isDirectory ? .directory : .file))
        })
        if validatePages {
            let pages = Set(manifest.paths)
            try archive.visitFiles { entry, data in
                let path = entry.path
                guard pages.contains(path) else { return }
                try Task.checkCancellation()
                _ = try Self.source(data, path: path)
                // Decode a tiny sample to catch corrupt content without allocating the original bitmap.
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 32, kCGImageSourceShouldCacheImmediately: true]
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil else {
                    throw DocumentError.unsupported("漫画图片损坏：\(path)")
                }
            }
        }
    }

    struct Bitmap: @unchecked Sendable {
        let image: CGImage
        let naturalSize: CGSize
    }

    /// Rebuildable first-page cover; never creates a reader or a reading event.
    static func cover(url: URL, kindle:Bool = false) throws -> Bitmap {
        if kindle {
            let document = try KindleDocument(url:url)
            guard let path = document.coverResource else {throw DocumentError.unsupported("此书没有可用封面")}
            let bytes = try document.read(path)
            let options:[CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:192,
                kCGImageSourceShouldCacheImmediately:true]
            guard let source = CGImageSourceCreateWithData(bytes as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else {throw DocumentError.unsupported("Kindle 封面无法解码")}
            try Task.checkCancellation()
            return Bitmap(image:image,naturalSize:CGSize(width:image.width,height:image.height))
        }
        let archive = try ComicArchive(url: url)
        let manifest = try ComicManifest(entries: archive.entries.map {
            .init(path: $0.path, kind: $0.isLink ? .symbolicLink : ($0.isDirectory ? .directory : .file))
        })
        let path = manifest.pages[0].canonicalPath
        return try sampledBitmap(archive.read(path), path: path, maximumDimension: 192)
    }

    func bitmap(page: Int) throws -> Bitmap {
        try cache.decode { try decodeBitmap(page: page) }
    }

    private func decodeBitmap(page: Int) throws -> Bitmap {
        guard manifest.pages.indices.contains(page) else { throw DocumentError.invalidPosition }
        try Task.checkCancellation()
        let path = manifest.pages[page].canonicalPath
        let data = try cache.read(key: manifest.pages[page].pageKey) { try archive.read(path) }
        return try Self.sampledBitmap(data, path: path)
    }

    private static func sampledBitmap(_ data: Data, path: String, maximumDimension: Int? = nil) throws -> Bitmap {
        let (source, natural) = try Self.source(data, path: path)
        // At most eight million sampled pixels (~32 MiB); only one displayed bitmap is retained.
        let scale = min(1, sqrt(8_000_000 / (natural.width * natural.height)))
        let maximum = min(maximumDimension ?? Int.max, max(1, Int(max(natural.width, natural.height) * scale)))
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maximum,
            kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw DocumentError.unsupported("漫画图片解码失败：\(path)")
        }
        try Task.checkCancellation()
        return Bitmap(image: image, naturalSize: natural)
    }

    private static func source(_ data: Data, path: String) throws -> (CGImageSource, CGSize) {
        try ComicManifest.validateImageHeader(data, canonicalPath: path)
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              Self.validPixelDimensions(width: width, height: height) else {
            throw DocumentError.unsupported("漫画图片损坏、为动画或超过一亿像素：\(path)")
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = (5...8).contains(orientation)
        return (source, CGSize(width: rotated ? height : width, height: rotated ? width : height))
    }

    static func validPixelDimensions(width: Int, height: Int) -> Bool {
        // Divide before multiplying: malicious declared dimensions must not overflow.
        width > 0 && height > 0 && width <= 100_000_000 / height
    }
}

/// Serial background decoding, bounded memory only. Purging this cache cannot
/// affect originals, formal positions, bookmarks or book metadata.
actor ComicCoverCache {
    static let shared = ComicCoverCache()
    private final class Value {
        let bitmap: ComicDocument.Bitmap
        init(_ bitmap: ComicDocument.Bitmap) { self.bitmap = bitmap }
    }
    private let values = NSCache<NSString, Value>()
    init() {
        values.totalCostLimit = 8 * 1024 * 1024
        values.countLimit = 64
    }
    func cover(url: URL,kindle:Bool = false) throws -> ComicDocument.Bitmap {
        try Task.checkCancellation()
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let key = "\(url.path)|\(attributes.fileSize ?? 0)|\(attributes.contentModificationDate?.timeIntervalSince1970 ?? 0)" as NSString
        if let value = values.object(forKey: key) { return value.bitmap }
        let bitmap = try ComicDocument.cover(url: url,kindle:kindle)
        try Task.checkCancellation()
        values.setObject(Value(bitmap), forKey: key, cost: bitmap.image.bytesPerRow * bitmap.image.height)
        return bitmap
    }
    func removeAll() { values.removeAllObjects() }
}

/// Disposable session cache, never a source of book identity or formal position.
/// Opaque keys prevent archive-controlled extraction paths. A single global budget
/// also covers briefly overlapping sessions while canceled background reads finish.
private final class ComicPageCache: @unchecked Sendable {
    private struct Record { let url: URL; let bytes: Int; var used: UInt64; let owner: UUID }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var records: [String: Record] = [:]
    nonisolated(unsafe) private static var clock: UInt64 = 0
    nonisolated(unsafe) private static var cleaned = false
    private let decoding = NSLock()
    private let owner = UUID()
    private let root: URL
    init() {
        root = FileManager.default.temporaryDirectory.appending(path: "XLibComicCache-" + owner.uuidString)
        Self.lock.withLock {
            if !Self.cleaned {
                // Only generated cache folders, once before this process owns any session.
                for url in (try? FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: nil)) ?? [] {
                    let prefix = "XLibComicCache-"
                    if url.lastPathComponent.hasPrefix(prefix), UUID(uuidString: String(url.lastPathComponent.dropFirst(prefix.count))) != nil {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
                Self.cleaned = true
            }
        }
    }
    func decode<T>(_ body: () throws -> T) throws -> T {
        try decoding.withLock { try Task.checkCancellation(); return try body() }
    }
    deinit {
        Self.lock.withLock {
            Self.records = Self.records.filter { $0.value.owner != owner }
            try? FileManager.default.removeItem(at: root)
        }
    }
    func read(key: String, load: () throws -> Data) throws -> Data {
        let cacheKey = owner.uuidString + key
        if let data = Self.lock.withLock({ () -> Data? in
            guard var record = Self.records[cacheKey], let data = try? Data(contentsOf: record.url) else { return nil }
            Self.clock += 1; record.used = Self.clock; Self.records[cacheKey] = record
            return data
        }) { return data }
        let data = try load()
        try Task.checkCancellation()
        Self.lock.withLock {
            let bookBudget = 512 * 1024 * 1024, totalBudget = 1024 * 1024 * 1024
            while Self.records.values.reduce(0, { $0 + ($1.owner == owner ? $1.bytes : 0) }) + data.count > bookBudget ||
                    Self.records.values.reduce(0, { $0 + $1.bytes }) + data.count > totalBudget {
                let ownLimit = Self.records.values.reduce(0, { $0 + ($1.owner == owner ? $1.bytes : 0) }) + data.count > bookBudget
                guard let oldest = Self.records.filter({ !ownLimit || $0.value.owner == owner }).min(by: { $0.value.used < $1.value.used }) else { break }
                try? FileManager.default.removeItem(at: oldest.value.url)
                Self.records.removeValue(forKey: oldest.key)
            }
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let destination = root.appending(path: key)
                try data.write(to: destination, options: .atomic)
                Self.clock += 1; Self.records[cacheKey] = Record(url: destination, bytes: data.count, used: Self.clock, owner: owner)
            } catch { /* Cache exhaustion must not invalidate a readable original. */ }
        }
        return data
    }
}
