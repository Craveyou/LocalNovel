import XCTest
import Foundation
import CZlib
import CComicArchive
import CryptoKit
@testable import AppleShared

final class ComicArchiveTests: XCTestCase {
    private func solidComicURL() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("contracts/fixtures/documents/comic-basic-rar4-solid.cbr")
    }

    func testRAR4SolidImagesMatchOriginalZIPInReverseAndAfterReopen() throws {
        let source = solidComicURL()
        let originalBytes = try Data(contentsOf: source)
        XCTAssertEqual(originalBytes.count, 19_059)
        XCTAssertEqual(SHA256.hash(data: originalBytes).map { String(format: "%02x", $0) }.joined(),
                       "3d12d67d112b8bdaf98eb1e144011e34e59ccd3ba4143c936897e07424a79adb")
        let original = try ComicArchive(url: source.deletingLastPathComponent().appendingPathComponent("comic-basic.cbz"))
        let solid = try ComicArchive(url: source)
        let pages = solid.entries.filter { $0.path.hasSuffix(".png") }
        XCTAssertEqual(pages.count, 24)
        for page in pages.reversed() {
            XCTAssertEqual(try solid.read(page.path), try original.read(page.path))
        }
        var visited = 0
        try solid.visitFiles { entry, bytes in
            XCTAssertEqual(bytes, try original.read(entry.path)); visited += 1
        }
        XCTAssertEqual(visited, solid.entries.filter { !$0.isDirectory }.count)
        let reopened = try ComicArchive(url: source)
        XCTAssertEqual(reopened.entries, solid.entries)
        XCTAssertEqual(try reopened.read(pages.last!.path), try original.read(pages.last!.path))
    }

    func testRAR4SolidChunkCancellationAndCorruptionDoNotPoisonNextOpen() throws {
        let source = solidComicURL()
        let handle = try XCTUnwrap(source.withUnsafeFileSystemRepresentation { $0.flatMap { xca_open($0) } })
        defer { xca_close(handle) }
        var path: UnsafePointer<CChar>?, size: Int64 = 0
        var directory: Int32 = 0, link: Int32 = 0
        XCTAssertEqual(xca_next(handle, &path, &size, &directory, &link), 0)
        XCTAssertEqual(xca_uses_sink(handle), 1)
        XCTAssertEqual(xca_process(handle, { _, _, count in
            XCTAssertGreaterThan(count, 0); XCTAssertLessThanOrEqual(count, 65_536)
            return -1
        }, nil), -1)
        XCTAssertEqual(xca_next(handle, &path, &size, &directory, &link), -1)
        var corrupt = try Data(contentsOf: source)
        func u16(_ offset: Int) -> Int { Int(corrupt[offset]) | Int(corrupt[offset + 1]) << 8 }
        let firstHeader = 7 + u16(12)
        let firstBody = firstHeader + u16(firstHeader + 5)
        corrupt[firstBody + 20] ^= 0x40
        try temporary(corrupt) { XCTAssertThrowsError(try ComicArchive(url: $0)) }
        try temporary(Data(corrupt.dropLast(10))) { XCTAssertThrowsError(try ComicArchive(url: $0)) }
        XCTAssertEqual(try ComicArchive(url: source).entries.filter { $0.path.hasSuffix(".png") }.count, 24)
    }

    func testConcurrentRAR4ReadersKeepIndependentSolidState() async throws {
        let source = solidComicURL()
        let reference = try ComicArchive(url: source)
        let page = try XCTUnwrap(reference.entries.last { $0.path.hasSuffix(".png") })
        let expected = try reference.read(page.path)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    let archive = try ComicArchive(url: source)
                    XCTAssertEqual(try archive.read(page.path), expected)
                }
            }
            try await group.waitForAll()
        }
    }

    func testRAR4DeclaredEntryBudgetIsRejectedBeforeDecompression() throws {
        var bytes = try Data(contentsOf: solidComicURL())
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        let header = 7 + u16(12)
        let length = u16(header + 5)
        XCTAssertEqual(bytes[header + 2], 0x74)
        // First entry declares 128 MiB + 1; body itself remains tiny/unchanged.
        let oversized = UInt32(128 << 20) + 1
        for index in 0..<4 { bytes[header + 11 + index] = UInt8(truncatingIfNeeded: oversized >> (index * 8)) }
        let checksum = crc(bytes.subdata(in: header + 2..<header + length))
        bytes[header] = UInt8(truncatingIfNeeded: checksum)
        bytes[header + 1] = UInt8(truncatingIfNeeded: checksum >> 8)
        try temporary(bytes) { url in
            XCTAssertThrowsError(try ComicArchive(url: url)) { error in
                XCTAssertTrue(error.localizedDescription.contains("resource limit"))
            }
        }
    }
    private struct ZIPItem {
        var name: Data
        var bytes: Data = Data([1, 2, 3])
        var flags: UInt16 = 0x800
        var method: UInt16 = 0
        var extra = Data()
        var mode: UInt32 = 0o100644
        var size: UInt32?
        var badCRC = false
        var centralName: Data?
    }
    private func temporary(_ data: Data, _ test: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("book.cbr")
        try data.write(to: url)
        try test(url)
    }
    private func crc(_ bytes: Data) -> UInt32 {
        bytes.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, UInt32($0.count))) }
    }
    private func unicodeField(_ raw: Data, _ name: String) -> Data {
        var payload = Data([1])
        payload.le(crc(raw))
        payload.append(Data(name.utf8))
        var extra = Data()
        extra.le(UInt16(0x7075)); extra.le(UInt16(payload.count)); extra.append(payload)
        return extra
    }
    private func zip(_ items: [ZIPItem]) -> Data {
        var result = Data(), central = Data()
        for item in items {
            let offset = UInt32(result.count)
            var compressed = item.bytes
            if item.method == 8 {
                // A valid raw DEFLATE stream with a final stored block.
                compressed = Data([1])
                compressed.le(UInt16(item.bytes.count))
                compressed.le(~UInt16(item.bytes.count))
                compressed.append(item.bytes)
            }
            let size = item.size ?? UInt32(item.bytes.count)
            let checksum = item.badCRC ? crc(item.bytes) ^ 1 : crc(item.bytes)
            result.le(UInt32(0x04034b50)); result.le(UInt16(20))
            result.le(item.flags); result.le(item.method); result.le(UInt32(0))
            result.le(checksum); result.le(UInt32(compressed.count)); result.le(size)
            result.le(UInt16(item.name.count)); result.le(UInt16(item.extra.count))
            result.append(item.name); result.append(item.extra); result.append(compressed)
            let name = item.centralName ?? item.name
            central.le(UInt32(0x02014b50)); central.le(UInt16(0x0314)); central.le(UInt16(20))
            central.le(item.flags); central.le(item.method); central.le(UInt32(0))
            central.le(checksum); central.le(UInt32(compressed.count)); central.le(size)
            central.le(UInt16(name.count)); central.le(UInt16(item.extra.count)); central.le(UInt16(0))
            central.le(UInt16(0)); central.le(UInt16(0)); central.le(item.mode << 16); central.le(offset)
            central.append(name); central.append(item.extra)
        }
        let offset = UInt32(result.count)
        result.append(central)
        result.le(UInt32(0x06054b50)); result.le(UInt16(0)); result.le(UInt16(0))
        result.le(UInt16(items.count)); result.le(UInt16(items.count))
        result.le(UInt32(central.count)); result.le(offset); result.le(UInt16(0))
        return result
    }
    private func fixture(_ name: String) throws -> Data {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("native-archive/fixtures")
        let encoded = try String(contentsOf: directory.appendingPathComponent(name + ".rar.uu"), encoding: .utf8)
        var data = Data(), started = false
        for line in encoded.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("begin ") { started = true; continue }
            if !started { continue }
            if line == "end" { break }
            let values = Array(line.utf8)
            guard let first = values.first else { continue }
            let count = Int((first &- 32) & 63)
            if count == 0 { continue }
            var block = Data()
            var i = 1
            while i + 3 < values.count {
                let a = (values[i] &- 32) & 63, b = (values[i + 1] &- 32) & 63
                let c = (values[i + 2] &- 32) & 63, d = (values[i + 3] &- 32) & 63
                block.append((a << 2) | (b >> 4)); block.append((b << 4) | (c >> 2)); block.append((c << 6) | d)
                i += 4
            }
            data.append(block.prefix(count))
        }
        return data
    }

    // Mutate only a filename/header CRC in the genuine upstream RAR4 fixture;
    // the original compressed bodies and their CRCs remain byte-identical.
    private func rar4Renamed(_ source: Data, name: Data, unicode: Bool) throws -> Data {
        func u16(_ offset: Int) -> Int { Int(source[offset]) | Int(source[offset + 1]) << 8 }
        let header = 7 + u16(12)
        XCTAssertEqual(source[header + 2], 0x74)
        let flags = u16(header + 3), oldSize = u16(header + 26)
        XCTAssertEqual(flags & 0x100, 0)
        XCTAssertEqual(source.subdata(in: header + 32..<header + 32 + oldSize), Data("random_data.bin".utf8))
        let size = u16(header + 5) - oldSize + name.count
        var result = Data(source.prefix(header + 32))
        result.append(name)
        result.append(source.dropFirst(header + 32 + oldSize))
        func put16(_ offset: Int, _ value: Int) {
            result[offset] = UInt8(truncatingIfNeeded: value)
            result[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        }
        put16(header + 3, unicode ? flags | 0x200 : flags & ~0x200)
        put16(header + 5, size)
        put16(header + 26, name.count)
        put16(header, Int(crc(result.subdata(in: header + 2..<header + size)) & 0xffff))
        return result
    }

    private func rar4UnicodeName(_ units: [UInt16]) -> Data {
        var result = Data([0x78, 0, 0]) // fallback + NUL, then high byte
        for offset in stride(from: 0, to: units.count, by: 4) {
            let group = units[offset..<min(offset + 4, units.count)]
            let flags = group.indices.reduce(UInt8(0)) { $0 | (2 << (6 - 2 * ($1 - offset))) }
            result.append(flags)
            for unit in group { result.le(unit) }
        }
        return result
    }

    func testCBZStoreDeflateNFCAndSequentialVisit() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aDc0AAAAASUVORK5CYII=")!
        let data = zip([ZIPItem(name: Data("e\u{301}.png".utf8), bytes: png),
                        ZIPItem(name: Data("2.png".utf8), bytes: png, method: 8)])
        try temporary(data) { url in
            let archive = try ComicArchive(url: url)
            XCTAssertEqual(archive.format, "cbz")
            XCTAssertEqual(archive.entries.map(\.path), ["é.png", "2.png"])
            XCTAssertEqual(try archive.read("é.png"), png)
            XCTAssertEqual(try archive.read("2.png"), png)
            var visited: [String] = []
            try archive.visitFiles { entry, bytes in
                XCTAssertEqual(bytes, png); visited.append(entry.path)
            }
            XCTAssertEqual(visited, archive.entries.map(\.path))
        }
    }
    func testImageLessZIPAndDirectoriesRemainAvailableForEPUBDetection() throws {
        try temporary(zip([])) { XCTAssertTrue(try ComicArchive(url: $0).entries.isEmpty) }
        let data = zip([ZIPItem(name: Data("META-INF/".utf8), bytes: Data(), mode: 0o040755),
                        ZIPItem(name: Data("mimetype".utf8), bytes: Data("application/epub+zip".utf8)),
                        ZIPItem(name: Data("META-INF/container.xml".utf8))])
        try temporary(data) { url in
            let archive = try ComicArchive(url: url)
            XCTAssertEqual(archive.entries.count, 3)
            XCTAssertTrue(archive.entries[0].isDirectory)
            XCTAssertEqual(try archive.read("mimetype"), Data("application/epub+zip".utf8))
        }
    }
    func testCP437AndUnicodePathFields() throws {
        let raw = Data([0x82]) + Data(".png".utf8)
        try temporary(zip([ZIPItem(name: raw, flags: 0)])) { url in
            XCTAssertEqual(try ComicArchive(url: url).entries.first?.path, "é.png")
        }
        try temporary(zip([ZIPItem(name: raw, flags: 0, extra: unicodeField(raw, "漫画.png"))])) { url in
            let archive = try ComicArchive(url: url)
            XCTAssertEqual(archive.entries.first?.path, "漫画.png")
            XCTAssertEqual(try archive.read("漫画.png"), Data([1, 2, 3]))
        }
    }
    func testRejectsMaliciousNamesDuplicatesLinksAndEncodingConflict() throws {
        for name in ["/1.png", "../1.png", "a//1.png", "a/./1.png", "a\\1.png", "C:1.png", "a/\u{1}.png"] {
            try temporary(zip([ZIPItem(name: Data(name.utf8))])) {
                XCTAssertThrowsError(try ComicArchive(url: $0), name)
            }
        }
        let invalid: [[ZIPItem]] = [
            [ZIPItem(name: Data("é.png".utf8)), ZIPItem(name: Data("e\u{301}.png".utf8))],
            [ZIPItem(name: Data("link.png".utf8), mode: 0o120777)],
            [ZIPItem(name: Data([0xc0, 0xaf]))],
            [ZIPItem(name: Data("a.png".utf8), extra: unicodeField(Data("a.png".utf8), "b.png"))],
            [ZIPItem(name: Data("a.png".utf8), centralName: Data("b.png".utf8))],
            [ZIPItem(name: Data("a.png".utf8), extra: unicodeField(Data("wrong.png".utf8), "a.png"))],
        ]
        for items in invalid {
            try temporary(zip(items)) { XCTAssertThrowsError(try ComicArchive(url: $0)) }
        }
    }
    func testRejectsCRCEncryptionUnsupportedCompressionTruncationAndLimits() throws {
        for item in [
            ZIPItem(name: Data("1.png".utf8), badCRC: true),
            ZIPItem(name: Data("1.png".utf8), flags: 1),
            ZIPItem(name: Data("1.png".utf8), method: 12),
            ZIPItem(name: Data("1.png".utf8), size: 128 * 1024 * 1024 + 1),
            ZIPItem(name: Data("1.png".utf8), size: 1),
        ] {
            try temporary(zip([item])) { XCTAssertThrowsError(try ComicArchive(url: $0)) }
        }
        try temporary(Data(zip([ZIPItem(name: Data("1.png".utf8))]).dropLast(5))) {
            XCTAssertThrowsError(try ComicArchive(url: $0))
        }
        let many = (0..<20_001).map { ZIPItem(name: Data("\($0).txt".utf8), bytes: Data()) }
        try temporary(zip(many)) { XCTAssertThrowsError(try ComicArchive(url: $0)) }
    }
    func testRealUpstreamRAR4NonSolidAndRAR5StoredCompressedSolid() throws {
        for name in ["test_read_format_rar_binary_data", "test_read_format_rar5_stored",
                     "test_read_format_rar5_compressed", "test_read_format_rar5_multiple_files_solid",
                     "test_read_format_rar5_solid"] {
            try temporary(fixture(name)) { url in
                let archive = try ComicArchive(url: url)
                XCTAssertEqual(archive.format, "cbr")
                XCTAssertFalse(archive.entries.isEmpty)
                let files = archive.entries.filter { !$0.isDirectory }
                for entry in files.reversed() {
                    XCTAssertEqual(Int64(try archive.read(entry.path).count), entry.size)
                }
                var visited = 0
                try archive.visitFiles { entry, bytes in
                    XCTAssertEqual(Int64(bytes.count), entry.size); visited += 1
                }
                XCTAssertEqual(visited, files.count)
                if name == "test_read_format_rar5_stored" {
                    XCTAssertEqual(try archive.read("helloworld.txt"), Data("hello libarchive test suite!\n".utf8))
                }
                if name == "test_read_format_rar5_multiple_files_solid" {
                    XCTAssertEqual(files.map(\.path), ["test1.bin", "test2.bin", "test3.bin", "test4.bin"])
                    for (index, entry) in files.enumerated() {
                        let bytes = try archive.read(entry.path)
                        for word in 0..<1024 {
                            let offset = word * 4
                            let value = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
                                UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
                            let k = word + 1
                            XCTAssertEqual(value, UInt32(max(0, k * k - 3 * k + 2 + index)))
                        }
                    }
                }
            }
        }
    }
    func testRealUpstreamEncryptedMultivolumeAndLinksRejected() throws {
        for name in ["test_read_format_rar4_encrypted", "test_read_format_rar5_encrypted",
                     "test_read_format_rar5_multiarchive.part01", "test_read_format_rar_multivolume.part0001",
                     "test_read_format_rar5_hardlink", "test_read_format_rar"] {
            try temporary(fixture(name)) { XCTAssertThrowsError(try ComicArchive(url: $0), name) }
        }
    }
    func testRAR4RawUTF8AndEncodedUnicodeNamesPreserveSafety() throws {
        let source = try fixture("test_read_format_rar_binary_data")
        var original = Data()
        try temporary(source) { url in
            let archive = try ComicArchive(url: url)
            XCTAssertEqual(archive.entries.map(\.path), ["random_data.bin", "LibarchiveAddingTest.odt"])
            original = try archive.read("random_data.bin")
        }
        var cases: [(String, Data, Bool)] = []
        for unicode in [false, true] {
            for path in ["ascii-name.bin", "café.png", "e\u{301}.png"] {
                cases.append((path.precomposedStringWithCanonicalMapping, Data(path.utf8), unicode))
            }
        }
        for path in ["é.png", "🦊.png"] {
            cases.append((path, rar4UnicodeName(Array(path.utf16)), true))
        }
        for (expected, name, unicode) in cases {
            try temporary(rar4Renamed(source, name: name, unicode: unicode)) { url in
                let archive = try ComicArchive(url: url)
                XCTAssertEqual(archive.entries.map(\.path), [expected, "LibarchiveAddingTest.odt"])
                XCTAssertEqual(try archive.read(expected), original)
            }
        }
        let invalid: [(Data, Bool)] = [
            (Data([0xc0, 0xaf]), false), (Data([0x82]), false),
            (Data([0x61, 0, 0x62]), false), (Data("a\\b.png".utf8), false),
            (Data("a\\b.png".utf8), true),
            (rar4UnicodeName(Array("a\\b.png".utf16)), true),
            (rar4UnicodeName([0xd800, 0x62]), true),
        ]
        for (name, unicode) in invalid {
            try temporary(rar4Renamed(source, name: name, unicode: unicode)) {
                XCTAssertThrowsError(try ComicArchive(url: $0))
            }
        }
    }
    func testRealRARBodyCRCFailureAndOversizedInput() throws {
        var rar = try fixture("test_read_format_rar5_stored")
        let range = try XCTUnwrap(rar.range(of: Data("hello libarchive test suite!".utf8)))
        rar[range.lowerBound] ^= 1
        try temporary(rar) { XCTAssertThrowsError(try ComicArchive(url: $0)) }
        try temporary(Data([1])) { url in
            let file = try FileHandle(forWritingTo: url)
            try file.truncate(atOffset: (1 << 30) + 1)
            try file.close()
            XCTAssertThrowsError(try ComicArchive(url: url))
        }
    }
    func testCancelledOpen() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ComicArchive(url: URL(fileURLWithPath: "/no-file-needed"))
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }
}

private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
