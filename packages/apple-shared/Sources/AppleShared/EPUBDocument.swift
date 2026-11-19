import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct EPUBDocument: Sendable {
    public struct Chapter: Sendable {
        public let resource: String
        public let html: String
        public let text: String
        public let anchors: [String: Int]
    }
    public struct Toc: Sendable { public let title: String; public let chapter: Int; public let offset: Int }
    private let archive: EPUBArchive
    public let chapters: [Chapter]
    public let toc: [Toc]
    public init(url: URL) throws {
        let archive = try EPUBArchive(url: url)
        self.archive = archive
        guard String(data: try archive.read("mimetype"), encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) == "application/epub+zip" else { throw DocumentError.unsupported("不是 EPUB 包") }
        if archive.entries["META-INF/encryption.xml"] != nil, !(try XMLTree.read(archive.read("META-INF/encryption.xml"))).elements("EncryptedData").isEmpty { throw DocumentError.unsupported("暂不支持 DRM 或加密 EPUB 资源") }
        let container = try XMLTree.read(archive.read("META-INF/container.xml"))
        guard let root = container.elements("rootfile").first else { throw DocumentError.unsupported("缺少 EPUB 包入口") }
        let opf = try Self.resolve(base: "", href: root.attrs["full-path"] ?? "")
        let package = try XMLTree.read(archive.read(opf))
        for meta in package.elements("meta") {
            if ((meta.attrs["property"] ?? "").contains("rendition:layout") && meta.text.contains("pre-paginated")) || (meta.attrs["name"] == "fixed-layout" && meta.attrs["content"] == "true") { throw DocumentError.unsupported("暂不支持固定版式 EPUB") }
        }
        var manifest: [String: XMLNode] = [:]
        var nav: String?, ncx: String?
        for item in package.elements("item") {
            guard let id = item.attrs["id"], manifest[id] == nil else { throw DocumentError.unsupported("EPUB 资源清单重复或缺少标识") }
            manifest[id] = item
            if (item.attrs["properties"] ?? "").split(separator: " ").contains("nav") { nav = try Self.resolve(base: opf, href: item.attrs["href"] ?? "") }
            if item.attrs["media-type"] == "application/x-dtbncx+xml" { ncx = try Self.resolve(base: opf, href: item.attrs["href"] ?? "") }
        }
        var chapters: [Chapter] = []; var decodedBytes = 0
        for ref in package.elements("itemref") where ref.attrs["linear"] != "no" {
            guard let item = manifest[ref.attrs["idref"] ?? ""], item.attrs["media-type"] == "application/xhtml+xml" else { throw DocumentError.unsupported("正文资源不支持或缺失") }
            let path = try Self.resolve(base: opf, href: item.attrs["href"] ?? "")
            guard !chapters.contains(where: { $0.resource == path }), chapters.count < 10_000 else { throw DocumentError.unsupported("正文资源重复或过多") }
            let tree = try XMLTree.read(archive.read(path))
            guard let body = tree.elements("body").first else { throw DocumentError.unsupported("正文缺少 body") }
            body.sanitize()
            for image in body.elements("img") {
                let src = image.attrs["src"] ?? ""
                if !src.hasPrefix("data:") {
                    let imagePath = try Self.resolve(base: path, href: src)
                    guard archive.entries[imagePath] != nil else { throw DocumentError.unsupported("EPUB 图片资源缺失") }
                }
            }
            var text = ""; var anchors: [String: Int] = [:]; var textOffset = 0
            body.collect(text: &text, anchors: &anchors, offset: &textOffset)
            var styles = ""
            for link in tree.elements("link") where link.attrs["rel"] == "stylesheet" {
                let css = try Self.resolve(base: path, href: link.attrs["href"] ?? "")
                _ = try archive.read(css)
                styles += "<link rel=\"stylesheet\" href=\"/\(Self.escape(css, attribute: true))\">"
            }
            for style in tree.elements("style") { styles += "<style>\(style.text.replacingOccurrences(of: "</style", with: "", options: .caseInsensitive))</style>" }
            let html = styles + body.html
            decodedBytes += text.utf8.count + html.utf8.count
            guard decodedBytes <= 64 * 1024 * 1024 else { throw DocumentError.unsupported("EPUB 正文超过 64 MiB 内存限额") }
            chapters.append(Chapter(resource: path, html: html, text: text, anchors: anchors))
        }
        guard !chapters.isEmpty else { throw DocumentError.unsupported("EPUB 没有可阅读正文") }
        self.chapters = chapters
        var toc: [Toc] = []
        func add(_ label: String, base: String, href: String) {
            guard let path = try? Self.resolve(base: base, href: href), let i = chapters.firstIndex(where: { $0.resource == path }) else { return }
            let fragment = URLComponents(string: href)?.fragment
            if let fragment, chapters[i].anchors[fragment] == nil { return }
            toc.append(Toc(title: label.trimmingCharacters(in: .whitespacesAndNewlines), chapter: i, offset: fragment.flatMap { chapters[i].anchors[$0] } ?? 0))
        }
        if let nav {
            let tree = try XMLTree.read(archive.read(nav))
            if let section = tree.elements("nav").first(where: { ($0.attrs["epub:type"] ?? $0.attrs["type"] ?? "").split(separator: " ").contains("toc") }) {
                for link in section.elements("a") { add(link.text, base: nav, href: link.attrs["href"] ?? "") }
            }
        } else if let ncx {
            for point in try XMLTree.read(archive.read(ncx)).elements("navPoint") {
                if let target = point.elements("content").first?.attrs["src"], let label = point.elements("text").first { add(label.text, base: ncx, href: target) }
            }
        }
        self.toc = toc
    }
    public func read(_ path: String) throws -> Data { try archive.read(path) }
    public func locator(chapter: Int, offset: Int) -> DocumentLocator {
        let c = chapters[chapter]; let text = c.text as NSString
        let raw = min(text.length, max(0, offset))
        let boundary = raw == text.length ? raw : text.rangeOfComposedCharacterSequence(at: raw).location
        return .epub(resource: c.resource, spineIndex: chapter, spineCount: chapters.count, textOffset: boundary, textLength: text.length)
    }
    public func valid(_ value: DocumentLocator) -> Bool {
        guard case .epub(let r, let i, let n, let o, let l) = value, n == chapters.count, chapters.indices.contains(i), chapters[i].resource == r, chapters[i].text.utf16.count == l else { return false }
        return locator(chapter: i, offset: o) == value && (try? value.validated()) != nil
    }
    public static func resolve(base: String, href: String) throws -> String {
        guard let origin = URL(string: "https://book.xlib.invalid/" + base), let target = URL(string: href, relativeTo: origin)?.absoluteURL.standardized,
              target.scheme == "https", target.host == "book.xlib.invalid", target.query == nil else { throw DocumentError.unsupported("不支持外部资源") }
        let path = String(target.path.dropFirst())
        guard DocumentLocator.safeResource(path) else { throw DocumentError.unsupported("资源路径越界") }
        return path
    }
    fileprivate static func escape(_ value: String, attribute: Bool = false) -> String {
        var result = value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        if attribute { result = result.replacingOccurrences(of: "\"", with: "&quot;") }
        return result
    }
}

private final class XMLNode {
    let name: String
    var attrs: [String: String]
    var children: [XMLNode] = []
    var value = ""
    init(_ name: String, attrs: [String: String] = [:]) { self.name = name; self.attrs = attrs }
    var text: String { name == "#text" ? value : children.map(\.text).joined() }
    func elements(_ tag: String) -> [XMLNode] { (name == tag ? [self] : []) + children.flatMap { $0.elements(tag) } }
    func sanitize() {
        attrs = attrs.filter { !$0.key.lowercased().hasPrefix("on") && !["srcdoc", "formaction", "xmlns"].contains($0.key.lowercased()) }
        children.removeAll { ["script", "iframe", "object", "embed", "form", "input", "button", "audio", "video", "base", "meta"].contains($0.name.lowercased()) }
        for child in children { child.sanitize() }
    }
    func collect(text: inout String, anchors: inout [String: Int], offset: inout Int) {
        guard name.lowercased() != "style" else { return }
        if let id = attrs["id"], anchors[id] == nil { anchors[id] = offset }
        if name == "#text" { text += value; offset += value.utf16.count }
        for child in children { child.collect(text: &text, anchors: &anchors, offset: &offset) }
    }
    var html: String {
        if name == "#text" { return EPUBDocument.escape(value) }
        let attrs = attrs.filter { !$0.key.hasPrefix("xmlns") }.sorted { $0.key < $1.key }.map { " \($0.key)=\"\(EPUBDocument.escape($0.value, attribute: true))\"" }.joined()
        let content = name.lowercased() == "style" ? text.replacingOccurrences(of: "</style", with: "", options: .caseInsensitive) : children.map(\.html).joined()
        let close = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"].contains(name.lowercased()) ? "" : "</\(name)>"
        return "<\(name)\(attrs)>\(content)\(close)"
    }
}
private final class XMLTree: NSObject, XMLParserDelegate {
    let root = XMLNode("#document")
    var stack: [XMLNode] = []
    var count = 0
    var exceeded = false
    static func read(_ bytes: Data) throws -> XMLNode {
        guard var source = String(data: bytes, encoding: .utf8), source.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { throw DocumentError.unsupported("EPUB 不允许自定义实体，正文须为 UTF-8") }
        if let declaration = source.range(of: "<\\?xml[^>]*encoding\\s*=\\s*[\"']([^\"']+)", options: [.regularExpression, .caseInsensitive]), !source[declaration].lowercased().hasSuffix("utf-8") { throw DocumentError.unsupported("暂只支持 UTF-8 EPUB 正文") }
        source = source.replacingOccurrences(of: "<!DOCTYPE[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        source = XHTMLNamedEntities.normalize(source)
        let tree = XMLTree(); tree.stack = [tree.root]
        let parser = XMLParser(data: Data(source.utf8)); parser.delegate = tree; parser.shouldResolveExternalEntities = false
        guard parser.parse(), !tree.exceeded else { throw DocumentError.unsupported("EPUB XML 结构损坏或超过支持限额") }
        return tree.root
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        count += 1
        guard stack.count <= 128, count <= 200_000 else { exceeded = true; parser.abortParsing(); return }
        let node = XMLNode(elementName.split(separator: ":").last.map(String.init) ?? elementName, attrs: attributeDict)
        stack.last?.children.append(node); stack.append(node)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if stack.count > 1 { stack.removeLast() } }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if let last = stack.last?.children.last, last.name == "#text" { last.value += string }
        else { let node = XMLNode("#text"); node.value = string; stack.last?.children.append(node); count += 1 }
        if count > 200_000 { exceeded = true; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self)) }
}

/// Normalize named HTML entities in one pass, preserving XML parsing and UTF-16 text semantics.
enum XHTMLNamedEntities {
    private static let values: [String:String] = {
        guard let url = Bundle.module.url(forResource:"xhtml-entities",withExtension:"tsv"),
              let map = try? String(contentsOf:url,encoding:.utf8) else { return [:] }
        return Dictionary(uniqueKeysWithValues:map.split(separator:"\n").compactMap {
            let parts = $0.split(separator:"\t")
            return parts.count == 2 ? (String(parts[0]),String(parts[1])) : nil
        })
    }()
    private static let pattern = try! NSRegularExpression(pattern:"&([A-Za-z][A-Za-z0-9]*);")
    static func normalize(_ source: String) -> String {
        guard source.utf8.contains(38) else { return source }
        let input = source as NSString
        let output = NSMutableString(capacity:input.length)
        var offset = 0
        pattern.enumerateMatches(in:source,range:NSRange(location:0,length:input.length)) { match,_,_ in
            guard let match else { return }
            output.append(input.substring(with:NSRange(location:offset,length:match.range.location-offset)))
            if let number = values[input.substring(with:match.range(at:1))] { output.append("&#\(number);") }
            else { output.append(input.substring(with:match.range)) }
            offset = NSMaxRange(match.range)
        }
        output.append(input.substring(from:offset))
        return output as String
    }
}
