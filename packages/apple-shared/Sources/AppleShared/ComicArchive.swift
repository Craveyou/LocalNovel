import Foundation
import CComicArchive

/// Fixed-version, read-only ZIP/RAR reader. Does not classify the publication,
/// extract entry paths to disk, or own page ordering / image decoding.
public struct ComicArchive: Sendable {
    public struct Entry: Sendable, Equatable {
        public let path: String
        public let size: Int64
        public let isDirectory: Bool
        public let isLink: Bool
    }
    public enum ArchiveError: Error, Sendable, LocalizedError {
        case invalid(String)
        public var errorDescription: String? {
            switch self { case .invalid(let reason): return reason }
        }
    }
    public let entries: [Entry]
    public let format: String
    private let url: URL
    private let fileSize: Int64

    public init(url: URL) throws {
        try Task.checkCancellation()
        guard url.isFileURL else { throw ArchiveError.invalid("漫画必须为本地文件") }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let length = (attributes[.size] as? NSNumber)?.int64Value,
              length > 0, length <= 1 << 30 else {
            throw ArchiveError.invalid("漫画原文件超过 1 GiB 或不是普通文件")
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let signature = try file.read(upToCount: 8) ?? Data()
        if signature.starts(with: [0x50, 0x4b, 0x03, 0x04]) || signature.starts(with: [0x50, 0x4b, 0x05, 0x06]) {
            format = "cbz"
        } else if signature.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x00]) || signature.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x01, 0x00]) {
            format = "cbr"
        } else { throw ArchiveError.invalid("不支持的漫画容器或自解压文件") }
        self.url = url
        fileSize = length
        let reader = try Reader(url: url)
        var result: [Entry] = []
        var paths = Set<String>()
        var declared: Int64 = 0
        var expanded: Int64 = 0
        while let entry = try reader.next() {
            guard result.count < 20_000, entry.size >= 0, entry.size <= 128 << 20,
                  !entry.isLink, paths.insert(entry.path).inserted else {
                throw ArchiveError.invalid("漫画条目过多、过大、路径重复或包含链接")
            }
            declared += entry.size
            guard declared <= 4 << 30 else { throw ArchiveError.invalid("漫画累计解压超过 4 GiB") }
            try reader.consume(expected: entry.size, total: &expanded, output: nil)
            result.append(entry)
        }
        entries = result
    }

    /// Reopens and sequentially decodes predecessors (including solid RAR4/5).
    /// Call off the main actor; a higher layer may maintain a bounded page cache.
    public func read(_ path: String) throws -> Data {
        try Task.checkCancellation()
        guard let target = entries.firstIndex(where: { $0.path == path }), !entries[target].isDirectory else {
            throw ArchiveError.invalid("漫画资源不存在")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == fileSize else {
            throw ArchiveError.invalid("漫画原文件已改变")
        }
        let reader = try Reader(url: url)
        var expanded: Int64 = 0
        var output = Data()
        for index in 0...target {
            guard let entry = try reader.next(), entry == entries[index] else {
                throw ArchiveError.invalid("漫画条目在读取期间改变")
            }
            if index == target {
                try reader.consume(expected: entry.size, total: &expanded, output: &output)
            } else {
                try reader.consume(expected: entry.size, total: &expanded, output: nil)
            }
        }
        return output
    }

    /// Single sequential validation pass; caller may validate images without
    /// repeated solid-archive decompression. Does not retain callback data.
    public func visitFiles(_ body: (Entry, Data) throws -> Void) throws {
        let reader = try Reader(url: url)
        var total: Int64 = 0
        for expected in entries {
            guard let entry = try reader.next(), entry == expected else {
                throw ArchiveError.invalid("漫画条目在读取期间改变")
            }
            if entry.isDirectory {
                try reader.consume(expected: entry.size, total: &total, output: nil)
            } else {
                var data = Data()
                try reader.consume(expected: entry.size, total: &total, output: &data)
                try Task.checkCancellation()
                try body(entry, data)
            }
        }
        guard try reader.next() == nil else { throw ArchiveError.invalid("漫画条目数量改变") }
    }

    private final class Reader {
        let handle: OpaquePointer
        init(url: URL) throws {
            guard let handle = url.withUnsafeFileSystemRepresentation({ $0.flatMap { xca_open($0) } }) else {
                throw ArchiveError.invalid("无法创建漫画解压器")
            }
            self.handle = handle
        }
        deinit { xca_close(handle) }
        func failure() -> ArchiveError { .invalid(String(cString: xca_error(handle))) }
        func next() throws -> Entry? {
            try Task.checkCancellation()
            var path: UnsafePointer<CChar>?
            var size: Int64 = 0
            var directory: Int32 = 0, link: Int32 = 0
            let status = xca_next(handle, &path, &size, &directory, &link)
            if status == 1 { return nil }
            guard status == 0, let path, let raw = String(validatingCString: path) else { throw failure() }
            let normalized = raw.precomposedStringWithCanonicalMapping
            let name = directory != 0 && normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized
            let components = name.split(separator: "/", omittingEmptySubsequences: false)
            guard !name.isEmpty, !name.contains("\\"), !name.contains(":"),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw ArchiveError.invalid("漫画条目路径不安全")
            }
            return Entry(path: name, size: size, isDirectory: directory != 0, isLink: link != 0)
        }
        func consume(expected: Int64, total: inout Int64, output: UnsafeMutablePointer<Data>?) throws {
            try Task.checkCancellation()
            if xca_uses_sink(handle) != 0 {
                let state = ChunkSink(expected: expected, total: total, data: output?.pointee)
                let status = xca_process(handle, { context, bytes, count in
                    guard let context, let bytes else { return -1 }
                    let sink = Unmanaged<ChunkSink>.fromOpaque(context).takeUnretainedValue()
                    do {
                        try sink.accept(bytes, count: count)
                        return 0
                    } catch {
                        sink.error = error
                        return -1
                    }
                }, Unmanaged.passUnretained(state).toOpaque())
                total = state.total
                if let error = state.error { throw error }
                guard status == 0, state.count == expected else { throw failure() }
                if let output, let data = state.data { output.pointee = data }
                return
            }
            var count: Int64 = 0
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                try Task.checkCancellation()
                let n = buffer.withUnsafeMutableBytes { xca_read(handle, $0.baseAddress, $0.count) }
                guard n >= 0 else { throw failure() }
                if n == 0 { break }
                count += n
                total += n
                guard count <= expected, count <= 128 << 20, total <= 4 << 30 else {
                    throw ArchiveError.invalid("漫画实际解压超出声明或资源限额")
                }
                if let output { output.pointee.append(contentsOf: buffer.prefix(Int(n))) }
            }
            guard count == expected else { throw ArchiveError.invalid("漫画条目大小不符") }
        }
    }

    /// Lifetime is confined to a synchronous native call. No callback or bytes
    /// escape; cancellation and size checks run before retaining every chunk.
    private final class ChunkSink {
        let expected: Int64
        var total: Int64
        var count: Int64 = 0
        var data: Data?
        var error: Error?
        init(expected: Int64, total: Int64, data: Data?) {
            self.expected = expected; self.total = total; self.data = data
        }
        func accept(_ bytes: UnsafeRawPointer, count size: Int) throws {
            try Task.checkCancellation()
            count += Int64(size); total += Int64(size)
            guard count <= expected, count <= 128 << 20, total <= 4 << 30 else {
                throw ArchiveError.invalid("漫画实际解压超出声明或资源限额")
            }
            if data != nil { data?.append(bytes.assumingMemoryBound(to: UInt8.self), count: size) }
        }
    }
}
