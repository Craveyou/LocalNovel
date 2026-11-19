import Foundation

/// Version 1 document coordinates shared with Android and the HTTP contract.
public enum DocumentLocator: Hashable, Sendable, Codable {
    case pdf(page: Int, pageCount: Int, y: Double)
    case epub(resource: String, spineIndex: Int, spineCount: Int, textOffset: Int, textLength: Int)
    case comic(format: String, manifestHash: String, pageKey: String, page: Int, pageCount: Int, y: Double)
    case kindle(textHash: String, textOffset: Int, textLength: Int)

    public var format: String { switch self { case .pdf: "pdf"; case .epub: "epub"; case .comic(let f, _, _, _, _, _): f; case .kindle: "kindle" } }
    /// Kindle units are resolved by the publication, never inferred from a screen page.
    public var unit: Int { switch self { case .pdf(let p, _, _): p; case .epub(_, let p, _, _, _): p; case .comic(_, _, _, let p, _, _): p; case .kindle: 0 } }
    public var progress: Double {
        switch self {
        case .pdf(let p, let n, let y): (Double(p) + y) / Double(n)
        case .epub(_, let i, let n, let o, let l): (Double(i) + (l == 0 ? 0 : Double(o) / Double(l))) / Double(n)
        case .comic(_, _, _, let p, let n, _): (Double(p) + 1) / Double(n)
        case .kindle(_, let o, let l): Double(o) / Double(l)
        }
    }
    public var positionKey: String {
        switch self {
        case .pdf(let p, _, let y): "pdf:1:\(p):" + String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), y)
        case .epub(let r, _, _, let o, _): "epub:1:\(r):\(o)"
        case .kindle(let h, let o, _): "kindle:1:kindle-text-v1:\(h):\(o)"
        case .comic(let f, let h, let k, _, _, let y): "\(f):1:comic-order-v1:\(h):\(k):" + String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), Self.roundedComicY(y))
        }
    }
    public func validated() throws -> Self {
        switch self {
        case .pdf(let p, let n, let y):
            guard (1...100_000).contains(n), (0..<n).contains(p), y.isFinite, (0...1).contains(y) else { throw DocumentError.invalidPosition }
            return .pdf(page: p, pageCount: n, y: floor(y * 1_000_000 + 0.5) / 1_000_000)
        case .epub(let r, let i, let n, let o, let l):
            guard Self.safeResource(r), (1...10_000).contains(n), (0..<n).contains(i), (0...2_147_483_647).contains(l), (0...l).contains(o) else { throw DocumentError.invalidPosition }
            return self
        case .kindle(let h, let o, let l):
            guard Self.validHash(h), (1...2_147_483_647).contains(l), (0...l).contains(o) else { throw DocumentError.invalidPosition }
            return self
        case .comic(let f, let h, let k, let p, let n, let y):
            guard ["cbz", "cbr"].contains(f), Self.validHash(h), Self.validHash(k),
                  (1...10_000).contains(n), (0..<n).contains(p), y.isFinite, (0...1).contains(y) else { throw DocumentError.invalidPosition }
            return .comic(format: f, manifestHash: h, pageKey: k, page: p, pageCount: n, y: Self.roundedComicY(y))
        }
    }
    private static func roundedComicY(_ y: Double) -> Double {
        let rounded = floor(y * 1_000_000 + 0.5) / 1_000_000
        return rounded == 0 ? 0 : rounded
    }
    private static func validHash(_ hash: String) -> Bool {
        hash.utf8.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    public static func safeResource(_ path: String) -> Bool {
        !path.isEmpty && path.utf16.count <= 1024 && !path.contains(where: { "/\\:%#?".contains($0) && $0 != "/" })
        && !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
        && !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }
    private struct Key: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func int(_ k: String) throws -> Int { try c.decode(Int.self, forKey: Key(k)) }
        guard try int("version") == 1 else { throw DocumentError.invalidPosition }
        let format = try c.decode(String.self, forKey: Key("format"))
        let keys: Set<String>
        switch format {
        case "pdf":
            keys = ["format", "version", "page", "pageCount", "y"]
            self = .pdf(page: try int("page"), pageCount: try int("pageCount"), y: try c.decode(Double.self, forKey: Key("y")))
        case "epub":
            keys = ["format", "version", "resource", "spineIndex", "spineCount", "textOffset", "textLength"]
            self = .epub(resource: try c.decode(String.self, forKey: Key("resource")), spineIndex: try int("spineIndex"), spineCount: try int("spineCount"), textOffset: try int("textOffset"), textLength: try int("textLength"))
        case "cbz", "cbr":
            keys = ["format", "version", "profile", "manifestHash", "pageKey", "page", "pageCount", "y"]
            guard try c.decode(String.self, forKey: Key("profile")) == "comic-order-v1" else { throw DocumentError.invalidPosition }
            self = .comic(format: format, manifestHash: try c.decode(String.self, forKey: Key("manifestHash")), pageKey: try c.decode(String.self, forKey: Key("pageKey")), page: try int("page"), pageCount: try int("pageCount"), y: try c.decode(Double.self, forKey: Key("y")))
        case "kindle":
            keys = ["format", "version", "profile", "textHash", "textOffset", "textLength"]
            guard try c.decode(String.self, forKey: Key("profile")) == "kindle-text-v1" else { throw DocumentError.invalidPosition }
            self = .kindle(textHash: try c.decode(String.self, forKey: Key("textHash")), textOffset: try int("textOffset"), textLength: try int("textLength"))
        default: throw DocumentError.invalidPosition
        }
        guard Set(c.allKeys.map(\.stringValue)) == keys else { throw DocumentError.invalidPosition }
        self = try validated()
    }
    public func encode(to encoder: Encoder) throws {
        let value = try validated()
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(format, forKey: Key("format")); try c.encode(1, forKey: Key("version"))
        switch value {
        case .pdf(let p, let n, let y):
            try c.encode(p, forKey: Key("page")); try c.encode(n, forKey: Key("pageCount")); try c.encode(y, forKey: Key("y"))
        case .epub(let r, let i, let n, let o, let l):
            try c.encode(r, forKey: Key("resource")); try c.encode(i, forKey: Key("spineIndex")); try c.encode(n, forKey: Key("spineCount")); try c.encode(o, forKey: Key("textOffset")); try c.encode(l, forKey: Key("textLength"))
        case .kindle(let h, let o, let l):
            try c.encode("kindle-text-v1", forKey: Key("profile")); try c.encode(h, forKey: Key("textHash"))
            try c.encode(o, forKey: Key("textOffset")); try c.encode(l, forKey: Key("textLength"))
        case .comic(_, let h, let k, let p, let n, let y):
            try c.encode("comic-order-v1", forKey: Key("profile"))
            try c.encode(h, forKey: Key("manifestHash")); try c.encode(k, forKey: Key("pageKey"))
            try c.encode(p, forKey: Key("page")); try c.encode(n, forKey: Key("pageCount")); try c.encode(y, forKey: Key("y"))
        }
    }
}

public enum DocumentError: LocalizedError, Sendable {
    case invalidPosition
    case unsupported(String)
    public var errorDescription: String? {
        switch self { case .invalidPosition: "文档位置无效或版本不支持，原位置已保留"; case .unsupported(let message): message }
    }
}

public struct DocumentSearchHit: Hashable, Sendable {
    public let unit: Int
    public let offset: Int
    public let length: Int
    public let excerpt: String
}

public struct DocumentTextSearch: Sendable {
    public private(set) var cursorUnit: Int
    public private(set) var cursorOffset: Int
    public private(set) var exhausted = false
    private let originUnit: Int
    private let originOffset: Int
    private var wrapping = false
    public init(unit: Int, offset: Int) { cursorUnit = unit; cursorOffset = offset; originUnit = unit; originOffset = offset }
    public static func validQuery(_ text: String) -> Bool { (2...32).contains(text.count) }
    public mutating func wrap() { cursorUnit = 0; cursorOffset = 0; exhausted = false; wrapping = true }
    public mutating func next(query: String, count: Int, limit: Int = 200, unitBudget: Int = .max, text: (Int) throws -> String) throws -> [DocumentSearchHit] {
        guard Self.validQuery(query), !exhausted else { return [] }
        var hits: [DocumentSearchHit] = []
        var scanned = 0
        while cursorUnit < count {
            try Task.checkCancellation()
            let source = try text(cursorUnit) as NSString
            let end = wrapping && cursorUnit == originUnit ? min(source.length, originOffset) : source.length
            if wrapping && cursorUnit > originUnit { break }
            while cursorOffset < end {
                let range = source.range(of: query, options: [.caseInsensitive], range: NSRange(location: cursorOffset, length: end - cursorOffset))
                guard range.location != NSNotFound else { break }
                cursorOffset = NSMaxRange(range)
                let snippet = source.substring(with: source.rangeOfComposedCharacterSequences(for: NSRange(location: max(0, range.location - 24), length: min(source.length, NSMaxRange(range) + 40) - max(0, range.location - 24))))
                hits.append(DocumentSearchHit(unit: cursorUnit, offset: range.location, length: range.length, excerpt: snippet))
                if hits.count == max(1,min(200,limit)) { return hits }
            }
            cursorUnit += 1; cursorOffset = 0; scanned += 1
            if scanned >= unitBudget, cursorUnit < count { return hits }
        }
        exhausted = true
        return hits
    }
}
