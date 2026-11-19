import Foundation
import CZlib

/// No extraction to disk. Central-directory limits are checked before allocating output.
struct EPUBArchive: Sendable {
    struct Entry: Sendable { let offset: Int; let compressed: Int; let size: Int; let method: Int; let crc: UInt32 }
    let data: Data
    let entries: [String: Entry]
    init(url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 256 * 1024 * 1024 else { throw DocumentError.unsupported("EPUB 超过 256 MiB") }
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 22 else { throw DocumentError.unsupported("EPUB ZIP 结构损坏") }
        var eocd: Int?
        for i in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
            if data.u32(i) == 0x06054b50, i + 22 + data.u16(i + 20) == data.count { eocd = i; break }
        }
        guard let end = eocd, data.u16(end + 4) == 0, data.u16(end + 6) == 0,
              data.u16(end + 8) == data.u16(end + 10), (1...10_000).contains(data.u16(end + 10)) else { throw DocumentError.unsupported("不支持分卷、ZIP64 或过多 EPUB 资源") }
        var cursor = Int(data.u32(end + 16)); var total = 0; var result: [String: Entry] = [:]
        for _ in 0..<data.u16(end + 10) {
            guard cursor >= 0, cursor + 46 <= end, data.u32(cursor) == 0x02014b50 else { throw DocumentError.unsupported("EPUB 资源目录损坏") }
            let flags = data.u16(cursor + 8), method = data.u16(cursor + 10)
            let compressed = Int(data.u32(cursor + 20)), size = Int(data.u32(cursor + 24))
            let nameLength = data.u16(cursor + 28), extra = data.u16(cursor + 30), comment = data.u16(cursor + 32)
            guard cursor + 46 + nameLength + extra + comment <= end,
                  let name = String(data: data.subdata(in: cursor + 46..<cursor + 46 + nameLength), encoding: .utf8),
                  flags & 1 == 0, method == 0 || method == 8, size <= 16 * 1024 * 1024,
                  compressed == 0 ? size == 0 : size / compressed <= 1000 else { throw DocumentError.unsupported("EPUB 加密、压缩或资源大小不受支持") }
            total += size
            guard total <= 256 * 1024 * 1024 else { throw DocumentError.unsupported("EPUB 解包资源超过支持限额") }
            if !name.hasSuffix("/") {
                guard DocumentLocator.safeResource(name), result[name] == nil else { throw DocumentError.unsupported("EPUB 资源路径无效或重复") }
                result[name] = Entry(offset: Int(data.u32(cursor + 42)), compressed: compressed, size: size, method: method, crc: data.u32(cursor + 16))
            }
            cursor += 46 + nameLength + extra + comment
        }
        guard cursor == Int(data.u32(end + 16)) + Int(data.u32(end + 12)) else { throw DocumentError.unsupported("EPUB 资源目录长度不符") }
        entries = result
    }
    func read(_ path: String) throws -> Data {
        guard let entry = entries[path], entry.offset >= 0, entry.offset + 30 <= data.count,
              data.u32(entry.offset) == 0x04034b50 else { throw DocumentError.unsupported("EPUB 缺少资源") }
        let start = entry.offset + 30 + data.u16(entry.offset + 26) + data.u16(entry.offset + 28)
        guard start <= data.count, entry.compressed <= data.count - start else { throw DocumentError.unsupported("EPUB 资源截断") }
        let input = data.subdata(in: start..<start + entry.compressed)
        var output: Data
        if entry.method == 0 { output = input }
        else {
            output = Data(count: max(1, entry.size))
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw DocumentError.unsupported("无法解压 EPUB") }
            defer { inflateEnd(&stream) }
            let status: Int32 = input.withUnsafeBytes { src in
                output.withUnsafeMutableBytes { dst in
                    stream.next_in = UnsafeMutablePointer(mutating: src.bindMemory(to: Bytef.self).baseAddress)
                    stream.avail_in = uInt(input.count)
                    stream.next_out = dst.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(dst.count)
                    return inflate(&stream, Z_FINISH)
                }
            }
            guard status == Z_STREAM_END, stream.total_out == entry.size, stream.total_in == entry.compressed else { throw DocumentError.unsupported("EPUB 资源解压失败") }
            output.count = entry.size
        }
        let crc = output.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) }
        guard output.count == entry.size, UInt32(crc) == entry.crc else { throw DocumentError.unsupported("EPUB 资源校验失败") }
        return output
    }
}
private extension Data {
    func u16(_ index: Int) -> Int { Int(self[index]) | Int(self[index + 1]) << 8 }
    func u32(_ index: Int) -> UInt32 { UInt32(u16(index)) | UInt32(u16(index + 2)) << 16 }
}
