import CryptoKit
import Foundation

/// Local-only, immutable page order. Names must already be losslessly decoded by the archive reader.
/// The archive reader must reject conflicting encodings and verify each page with validateImageHeader.
/// Never use canonical paths as extraction destinations; use generated opaque resource IDs instead.
public struct ComicManifest: Sendable, Hashable {
    public static let profile = "comic-order-v1"

    public struct Entry: Sendable, Hashable {
        public enum Kind: Sendable, Hashable { case file, directory, symbolicLink, hardLink }
        public let path: String
        public let kind: Kind
        public init(path: String, kind: Kind = .file) { self.path = path; self.kind = kind }
    }

    public struct Page: Sendable, Hashable {
        public let canonicalPath: String
        public let pageKey: String
    }

    public enum Failure: Error, Sendable, Equatable {
        case unsafePath(String)
        case link(String)
        case duplicatePath(String)
        case unsupportedImage(String)
        case invalidImage(String)
        case empty
        case limitExceeded
    }

    public let pages: [Page]
    public let manifestHash: String
    public var paths: [String] { pages.map(\.canonicalPath) }
    public var pageKeys: [String] { pages.map(\.pageKey) }
    public var hash: String { manifestHash }

    /// Convenience for archive readers that have already rejected links and decoded names losslessly.
    /// One terminal slash identifies a directory entry. Image bytes must be checked separately.
    public init(paths: [String]) throws {
        try self.init(entries: paths.map { Entry(path: $0, kind: $0.hasSuffix("/") ? .directory : .file) })
    }

    /// Checks every entry (including hidden and non-page entries) before selecting pages.
    public init(entries: [Entry]) throws {
        guard entries.count <= 20_000 else { throw Failure.limitExceeded }
        var seen = Set<String>()
        var paths: [String] = []
        for entry in entries {
            try Task.checkCancellation()
            guard entry.kind == .file || entry.kind == .directory else { throw Failure.link(entry.path) }
            let path = try Self.canonicalPath(entry.path, directory: entry.kind == .directory)
            guard seen.insert(path).inserted else { throw Failure.duplicatePath(path) }
            guard entry.kind == .file, !Self.isHidden(path) else { continue }
            let ext = Self.imageExtension(path)
            if Self.unsupportedExtensions.contains(ext) { throw Failure.unsupportedImage(path) }
            if Self.pageExtensions.contains(ext) { paths.append(path) }
        }
        guard !paths.isEmpty else { throw Failure.empty }
        guard paths.count <= 10_000 else { throw Failure.limitExceeded }
        pages = paths.sorted(by: Self.pathLessThan).map { Page(canonicalPath: $0, pageKey: Self.sha256($0)) }
        manifestHash = Self.sha256("xlib-comic-order-v1\n" + pages.map { $0.pageKey + "\n" }.joined())
    }

    /// Directory entries may carry one terminal slash; it is not part of their canonical identity.
    public static func canonicalPath(_ name: String, directory: Bool = false) throws -> String {
        var path = name.precomposedStringWithCanonicalMapping
        if directory, path.hasSuffix("/") { path.removeLast() }
        guard !path.isEmpty, !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw Failure.unsafePath(name)
        }
        return path
    }

    public static func isHidden(_ canonicalPath: String) -> Bool {
        canonicalPath.split(separator: "/").contains { $0.hasPrefix(".") || $0 == "__MACOSX" }
    }

    /// JPEG/PNG signature check only; the platform decoder must still validate dimensions and content.
    /// Supply at least the first eight bytes (or the complete, shorter file).
    public static func validateImageHeader(_ header: Data, canonicalPath: String) throws {
        let ext = imageExtension(canonicalPath)
        let bytes = Array(header.prefix(8))
        if ["jpg", "jpeg"].contains(ext), bytes.starts(with: [0xff, 0xd8, 0xff]) { return }
        if ext == "png", bytes == [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] { return }
        if !pageExtensions.contains(ext) { throw Failure.unsupportedImage(canonicalPath) }
        throw Failure.invalidImage(canonicalPath)
    }

    public func locator(format: String, page: Int, y: Double = 0) throws -> DocumentLocator {
        guard pages.indices.contains(page) else { throw DocumentError.invalidPosition }
        return try DocumentLocator.comic(format: format, manifestHash: manifestHash, pageKey: pages[page].pageKey,
                                         page: page, pageCount: pages.count, y: y).validated()
    }

    /// Call only after checking original-file SHA-256 + size; this checks the local manifest, not file identity.
    public func validated(_ locator: DocumentLocator, format: String) throws -> DocumentLocator {
        let value = try locator.validated()
        guard case .comic(let f, let h, let k, let p, let n, _) = value,
              f == format, h == manifestHash, n == pages.count, pages.indices.contains(p), pages[p].pageKey == k else {
            throw DocumentError.invalidPosition
        }
        return value
    }

    public func valid(_ locator: DocumentLocator, format: String) -> Bool {
        (try? validated(locator, format: format)) != nil
    }

    /// Only ASCII case folding, never locale-sensitive or Unicode case folding.
    private static func folded(_ scalar: UInt32) -> UInt32 { (65...90).contains(scalar) ? scalar + 32 : scalar }
    private static func digit(_ scalar: UInt32) -> Bool { (48...57).contains(scalar) }

    private static func compareComponent(_ a: Substring, _ b: Substring) -> Int {
        let left = a.unicodeScalars.map(\.value), right = b.unicodeScalars.map(\.value)
        var i = 0, j = 0
        while i < left.count, j < right.count {
            var ie = i + 1, je = j + 1
            while ie < left.count, digit(left[ie]) == digit(left[i]) { ie += 1 }
            while je < right.count, digit(right[je]) == digit(right[j]) { je += 1 }
            if digit(left[i]), digit(right[j]) {
                var iz = i, jz = j
                while iz < ie, left[iz] == 48 { iz += 1 }
                while jz < je, right[jz] == 48 { jz += 1 }
                if ie - iz != je - jz { return ie - iz < je - jz ? -1 : 1 }
                while iz < ie {
                    if left[iz] != right[jz] { return left[iz] < right[jz] ? -1 : 1 }
                    iz += 1; jz += 1
                }
            } else {
                var li = i, rj = j
                while li < ie, rj < je {
                    let l = folded(left[li]), r = folded(right[rj])
                    if l != r { return l < r ? -1 : 1 }
                    li += 1; rj += 1
                }
                if ie - i != je - j { return ie - i < je - j ? -1 : 1 }
            }
            i = ie; j = je
        }
        if i == left.count, j == right.count { return 0 }
        return i == left.count ? -1 : 1
    }

    /// Both arguments must be canonical paths. Tie-break only after ALL components compare equal.
    public static func pathLessThan(_ left: String, _ right: String) -> Bool {
        let a = left.split(separator: "/"), b = right.split(separator: "/")
        for (l, r) in zip(a, b) {
            let comparison = compareComponent(l, r)
            if comparison != 0 { return comparison < 0 }
        }
        if a.count != b.count { return a.count < b.count }
        return left.unicodeScalars.lexicographicallyPrecedes(right.unicodeScalars, by: { $0.value < $1.value })
    }

    private static let pageExtensions: Set<String> = ["jpg", "jpeg", "png"]
    private static let unsupportedExtensions: Set<String> = [
        "gif", "webp", "bmp", "dib", "tif", "tiff", "heic", "heif", "avif", "jxl", "jp2", "j2k", "jpf", "jpx", "jpm", "mj2",
        "svg", "svgz", "ico", "cur", "apng", "psd", "psb", "tga", "dds", "pnm", "pbm", "pgm", "ppm", "pam", "pcx", "qoi", "jpe", "jfif",
    ]
    private static func imageExtension(_ path: String) -> String {
        let name = path.split(separator: "/").last ?? ""
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return String(String.UnicodeScalarView(name[name.index(after: dot)...].unicodeScalars.map { Unicode.Scalar(folded($0.value))! }))
    }
    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
