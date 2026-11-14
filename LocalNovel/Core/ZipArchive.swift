import Foundation
import Compression

// MARK: - 最小 ZIP 读取器（只读，够解析 epub 用）
//
// epub 就是一个 zip：META-INF/container.xml + OPF + 一堆 xhtml。
// 不引第三方库，只支持 zip 规范里最常见的 stored(0) / deflate(8) 两种压缩方式。
// 解析失败一律返回 nil，由上层给出「文件可能损坏」的明确提示。

struct ZipArchive {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    private(set) var entries: [String: Entry] = [:]

    init?(url: URL) {
        guard let raw = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        self.init(data: raw)
    }

    init?(data: Data) {
        self.data = data
        guard let eocd = Self.findEndOfCentralDirectory(in: data) else { return nil }
        let total = Self.u16(data, eocd + 10)
        var offset = Int(Self.u32(data, eocd + 16))
        guard offset > 0, offset < data.count else { return nil }

        for _ in 0..<max(total, 1) {
            guard offset + 46 <= data.count, Self.u32(data, offset) == 0x0201_4b50 else { break }
            let method = Self.u16(data, offset + 10)
            let compressed = Int(Self.u32(data, offset + 20))
            let uncompressed = Int(Self.u32(data, offset + 24))
            let nameLength = Self.u16(data, offset + 28)
            let extraLength = Self.u16(data, offset + 30)
            let commentLength = Self.u16(data, offset + 32)
            let localOffset = Int(Self.u32(data, offset + 42))
            guard offset + 46 + nameLength <= data.count else { break }
            let nameData = data.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
            let name = String(data: nameData, encoding: .utf8)
                ?? String(decoding: nameData, as: UTF8.self)
            entries[name] = Entry(name: name,
                                  method: method,
                                  compressedSize: compressed,
                                  uncompressedSize: uncompressed,
                                  localHeaderOffset: localOffset)
            offset += 46 + nameLength + extraLength + commentLength
        }
        if entries.isEmpty { return nil }
    }

    /// 按条目名取解压后的数据；找不到或解压失败返回 nil
    func data(for name: String) -> Data? {
        guard let entry = entries[name] else { return nil }
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, Self.u32(data, header) == 0x0403_4b50 else { return nil }
        let nameLength = Self.u16(data, header + 26)
        let extraLength = Self.u16(data, header + 28)
        let start = header + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= data.count, start <= end else { return nil }
        let payload = data.subdata(in: start..<end)

        switch entry.method {
        case 0:
            return payload
        case 8:
            return Self.inflate(payload, expectedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }

    /// 按条目名取 UTF-8 文本（epub 内部文件都是 UTF-8）
    func text(for name: String) -> String? {
        guard let raw = data(for: name) else { return nil }
        if let s = String(data: raw, encoding: .utf8) { return s }
        return String(data: raw, encoding: .isoLatin1)
    }

    /// 名字后缀匹配（epub 里路径大小写混乱时兜底）
    func entryName(endingWith suffix: String) -> String? {
        if entries[suffix] != nil { return suffix }
        let lower = suffix.lowercased()
        return entries.keys.first { $0.lowercased().hasSuffix(lower) }
    }

    // MARK: - 字节读取

    private static func u16(_ data: Data, _ offset: Int) -> Int {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
        return Int(UInt16(littleEndian: value))
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        return UInt32(littleEndian: value)
    }

    /// 从尾部往前找 EOCD（0x06054b50），注释最长 64K
    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        let count = data.count
        guard count >= 22 else { return nil }
        let lowerBound = max(0, count - 65_557)
        var index = count - 22
        while index >= lowerBound {
            if u32(data, index) == 0x0605_4b50 { return index }
            index -= 1
        }
        return nil
    }

    /// raw deflate 解压（COMPRESSION_ZLIB 在 Apple 平台上就是 raw DEFLATE，无 zlib 头）
    private static func inflate(_ source: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return nil }
        var output = Data(count: expectedSize)
        let written = source.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let srcBase = src.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
                guard let dstBase = dst.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(dstBase, expectedSize,
                                                 srcBase, source.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }
}
