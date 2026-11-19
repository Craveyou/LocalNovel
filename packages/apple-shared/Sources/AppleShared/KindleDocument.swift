import CryptoKit
import Foundation
import JavaScriptCore
import ImageIO

/// UI-independent, offline output from the shared, pinned Kindle engine.
/// Each parse owns a VM on its calling thread; neither the VM nor file handle escapes.
public struct KindleDocument: Sendable {
    public struct SourceMap: Codable, Sendable {
        public let textStart: Int
        public let textEnd: Int
        public let sourceStart: Int
        public let sourceEnd: Int
        public let kind: String
    }
    public struct Chapter: Codable, Sendable {
        public let resource: String
        public let html: String
        public let text: String
        public let textStart: Int
        public let sourceHTML: String
        public let anchors: [String: Int]
        public let maps: [SourceMap]
    }
    public struct Toc: Codable, Sendable { public let title: String; public let unit: Int; public let offset: Int }
    private struct Resource: Codable, Sendable { let offset: Int; let size: Int }
    private struct Output: Decodable {
        let coreVersion: Int
        let profile: String
        let mode: String
        let canonicalText: String
        let chapters: [Chapter]
        let toc: [Toc]
        let resources: [String: Resource]
        let coverResource:String?
    }
    private let url: URL
    private let resources: [String: Resource]
    private let sourceSize:Int
    private let sourceModified:Date
    public let mode: String
    public let canonicalText: String
    public let textHash: String
    public let chapters: [Chapter]
    public let toc: [Toc]
    public let coverResource:String?
    public static let profile = "kindle-text-v1"

    public init(url: URL) throws {
        try Task.checkCancellation()
        let before = try Self.sourceStamp(url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let context = JSContext() else { throw DocumentError.unsupported("Kindle 解析器无法初始化") }
        var failure: String?
        context.exceptionHandler = { _, exception in failure = exception?.toString() ?? "Kindle 解析失败" }
        let read: @convention(block) (Int, Int) -> JSValue? = { start, count in
            do {
                try Task.checkCancellation()
                guard start >= 0, count >= 0, count <= 16 * 1024 * 1024,
                      start <= before.size, count <= before.size - start else { throw DocumentError.invalidPosition }
                try handle.seek(toOffset: UInt64(start))
                let bytes = try handle.read(upToCount: count) ?? Data()
                guard bytes.count == count,
                      let array = JSObjectMakeTypedArray(context.jsGlobalContextRef, kJSTypedArrayTypeUint8Array, count, nil),
                      let pointer = JSObjectGetTypedArrayBytesPtr(context.jsGlobalContextRef, array, nil) else { throw DocumentError.invalidPosition }
                bytes.copyBytes(to: pointer.assumingMemoryBound(to: UInt8.self), count: bytes.count)
                return JSValue(jsValueRef: array, in: context)
            } catch { failure = Task.isCancelled ? "CANCELLED" : error.localizedDescription; return nil }
        }
        let decode: @convention(block) (JSValue, String, Bool) -> String? = { value, encoding, fatal in
            guard let object = JSValueToObject(context.jsGlobalContextRef, value.jsValueRef, nil) else { return nil }
            let count = JSObjectGetTypedArrayByteLength(context.jsGlobalContextRef, object, nil)
            if count == 0 { return "" }
            let offset = JSObjectGetTypedArrayByteOffset(context.jsGlobalContextRef, object, nil)
            guard count <= 32 * 1024 * 1024 else { return nil }
            guard let pointer = JSObjectGetTypedArrayBytesPtr(context.jsGlobalContextRef, object, nil) else { return nil }
            let data = Data(bytes: pointer.advanced(by: offset), count: count)
            if encoding == "windows-1252" {
                let specials: [UInt32] = [0x20ac,0x81,0x201a,0x192,0x201e,0x2026,0x2020,0x2021,0x2c6,0x2030,0x160,0x2039,0x152,0x8d,0x17d,0x8f,0x90,0x2018,0x2019,0x201c,0x201d,0x2022,0x2013,0x2014,0x2dc,0x2122,0x161,0x203a,0x153,0x9d,0x17e,0x178]
                return String(String.UnicodeScalarView(data.map { UnicodeScalar((0x80...0x9f).contains($0) ? specials[Int($0)-0x80] : UInt32($0))! }))
            }
            let decoded = fatal ? String(data: data, encoding: .utf8) : String(decoding: data, as: UTF8.self)
            return decoded?.hasPrefix("\u{feff}") == true ? String(decoded!.dropFirst()) : decoded
        }
        let cancelled: @convention(block) () -> Bool = { Task.isCancelled }
        context.setObject(read, forKeyedSubscript: "xlibRead" as NSString)
        context.setObject(decode, forKeyedSubscript: "xlibDecode" as NSString)
        context.setObject(cancelled, forKeyedSubscript: "xlibCancelled" as NSString)
        defer {
            // Break the VM -> host callback -> VM ownership cycle.
            for key in ["xlibRead", "xlibDecode", "xlibCancelled"] { context.setObject(nil, forKeyedSubscript: key as NSString) }
            context.exceptionHandler = nil
        }
        context.evaluateScript(Self.bootstrap)
        guard let scriptURL = Bundle.module.url(forResource: "kindle-core", withExtension: "js") else { throw DocumentError.unsupported("Kindle 公共解析资源缺失") }
        context.evaluateScript(try String(contentsOf: scriptURL, encoding: .utf8))
        context.setObject(before.size, forKeyedSubscript: "xlibSize" as NSString)
        let value = context.evaluateScript("JSON.stringify(XLibKindle.parse({size:xlibSize,read:xlibRead},xlibCancelled))")?.toString()
        try Task.checkCancellation()
        if let failure { throw DocumentError.unsupported("Kindle：\(failure)") }
        guard let value, let bytes = value.data(using: .utf8) else { throw DocumentError.unsupported("Kindle 解析结果无效") }
        let output = try JSONDecoder().decode(Output.self, from: bytes)
        guard output.coreVersion == 1, output.profile == Self.profile,
              !output.canonicalText.isEmpty, output.chapters.map(\.text).joined(separator: "\n") == output.canonicalText else { throw DocumentError.unsupported("Kindle 规范正文校验失败") }
        let after = try Self.sourceStamp(url)
        guard before.size == after.size, before.modified == after.modified else { throw DocumentError.unsupported("Kindle 解析期间原文件已改变") }
        self.url = url; resources = output.resources; mode = output.mode
        sourceSize = before.size;sourceModified = before.modified
        canonicalText = output.canonicalText; chapters = output.chapters; toc = output.toc
        coverResource = output.coverResource
        textHash = SHA256.hash(data: Data(output.canonicalText.utf8)).map { String(format: "%02x", $0) }.joined()
        // Validate metadata without decoding full-size bitmaps during import/open.
        for path in resources.keys {
            try Task.checkCancellation()
            let bytes = try self.read(path)
            guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache:false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 100_000_000 / height else {
                throw DocumentError.unsupported("Kindle 图片无效或超过一亿像素安全限制")
            }
            guard CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) != nil else {
                throw DocumentError.unsupported("Kindle 图片无法解码")
            }
        }
    }

    public func read(_ path: String) throws -> Data {
        try Task.checkCancellation()
        let current = try Self.sourceStamp(url)
        guard current.size == sourceSize,current.modified == sourceModified else {throw DocumentError.unsupported("Kindle 原文件已改变，原位置已保留")}
        guard let resource = resources[path], DocumentLocator.safeResource(path) else { throw DocumentError.unsupported("Kindle 本地资源不存在") }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(resource.offset))
        let bytes = try handle.read(upToCount: resource.size) ?? Data()
        guard bytes.count == resource.size else { throw DocumentError.unsupported("Kindle 图片资源已改变或被截断") }
        return bytes
    }

    public func locator(chapter: Int, offset: Int) -> DocumentLocator {
        let chapter = chapters[min(chapters.count - 1, max(0, chapter))]
        let text = chapter.text as NSString
        let raw = min(text.length, max(0, offset))
        let local = raw == text.length ? raw : text.rangeOfComposedCharacterSequence(at: raw).location
        return .kindle(textHash: textHash, textOffset: chapter.textStart + local, textLength: canonicalText.utf16.count)
    }
    public func chapterIndex(for value: DocumentLocator) -> Int? {
        guard case .kindle(let hash, let offset, let length) = value,
              hash == textHash, length == canonicalText.utf16.count,
              (try? value.validated()) != nil else { return nil }
        return chapters.lastIndex(where: { $0.textStart <= offset })
    }
    public func localOffset(for value: DocumentLocator) -> Int? {
        guard let i = chapterIndex(for: value), case .kindle(_, let offset, _) = value else { return nil }
        return min(chapters[i].text.utf16.count, offset - chapters[i].textStart)
    }
    public func valid(_ value: DocumentLocator) -> Bool {
        guard let i = chapterIndex(for: value), let offset = localOffset(for: value) else { return false }
        return locator(chapter: i, offset: offset) == value
    }

    /// Ranges, rather than guessed points, make lossy entity/whitespace mappings explicit.
    /// Offsets are chapter-local UTF-16 in the selected reconstructed source HTML.
    public func sourceRange(forCanonicalOffset offset:Int, chapter:Int) -> NSRange? {
        guard chapters.indices.contains(chapter),let span = chapters[chapter].maps.first(where:{$0.textStart <= offset && offset < $0.textEnd}),span.sourceStart >= 0 else {return nil}
        if span.kind == "text",span.sourceEnd-span.sourceStart == span.textEnd-span.textStart {
            return NSRange(location:span.sourceStart+offset-span.textStart,length:1)
        }
        return NSRange(location:span.sourceStart,length:span.sourceEnd-span.sourceStart)
    }
    public func canonicalRange(forSourceOffset offset:Int, chapter:Int) -> NSRange? {
        guard chapters.indices.contains(chapter),let span = chapters[chapter].maps.first(where:{$0.sourceStart >= 0 && $0.sourceStart <= offset && offset < $0.sourceEnd}) else {return nil}
        if span.kind == "text",span.sourceEnd-span.sourceStart == span.textEnd-span.textStart {
            return NSRange(location:span.textStart+offset-span.sourceStart,length:1)
        }
        return NSRange(location:span.textStart,length:span.textEnd-span.textStart)
    }

    private static func sourceStamp(_ url:URL) throws -> (size:Int,modified:Date) {
        // URL resourceValues may retain a cached size/mtime from an earlier read.
        let attributes = try FileManager.default.attributesOfItem(atPath:url.path)
        guard let size = attributes[.size] as? NSNumber,let modified = attributes[.modificationDate] as? Date else {throw DocumentError.invalidPosition}
        return (size.intValue,modified)
    }
    private static let bootstrap = """
    globalThis.TextDecoder=class {
      constructor(encoding,options){this.encoding=encoding||'utf-8';this.fatal=options?.fatal||false;}
      decode(value){const bytes=value instanceof ArrayBuffer?new Uint8Array(value):value;const result=xlibDecode(bytes,this.encoding,this.fatal);if(result===null||result===undefined)throw new Error('正文编码无效');return result;}
    };
    globalThis.TextEncoder=class {
      encode(value){const bytes=unescape(encodeURIComponent(value));return Uint8Array.from(bytes,c=>c.charCodeAt(0));}
    };
    """
}
