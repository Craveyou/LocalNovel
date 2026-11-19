import Foundation
import Testing
@testable import AppleShared

private struct ComicOrderVector: Decodable {
    struct Entry: Decodable {
        let path: String
        let kind: String
        var value: ComicManifest.Entry {
            let type: ComicManifest.Entry.Kind = switch kind {
            case "directory": .directory
            case "symbolicLink": .symbolicLink
            case "hardLink": .hardLink
            default: .file
            }
            return .init(path: path, kind: type)
        }
    }
    struct Page: Decodable { let canonicalPath: String; let pageKey: String }
    struct Position: Decodable { let locator: DocumentLocator; let progress: Double; let positionKey: String }
    struct Invalid: Decodable { let entries: [Entry]; let error: String }
    let profile: String
    let entries: [Entry]
    let canonicalPaths: [String]
    let pages: [Page]
    let manifestHash: String
    let locators: [Position]
    let invalidCases: [Invalid]
}

private func comicVector() throws -> ComicOrderVector {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return try JSONDecoder().decode(ComicOrderVector.self, from: Data(contentsOf: root.appending(path: "contracts/fixtures/documents/comic-order-v1.json")))
}

@Test func comicSharedOrderHashesAndCoordinates() throws {
    let vector = try comicVector()
    let entries = vector.entries.map(\.value)
    let manifest = try ComicManifest(entries: entries)
    #expect(vector.profile == ComicManifest.profile)
    #expect(try entries.map { try ComicManifest.canonicalPath($0.path, directory: $0.kind == .directory) } == vector.canonicalPaths)
    #expect(manifest.paths == vector.pages.map(\.canonicalPath))
    #expect(manifest.pageKeys == vector.pages.map(\.pageKey))
    #expect(manifest.hash == vector.manifestHash)
    #expect(try ComicManifest(entries: entries.reversed()) == manifest)
    #expect(try ComicManifest(paths: entries.map(\.path)) == manifest)
    for position in vector.locators {
        let value = position.locator
        #expect(abs(value.progress - position.progress) < 1e-12)
        #expect(value.positionKey == position.positionKey)
        #expect(manifest.valid(value, format: value.format))
        #expect(try manifest.validated(value, format: value.format) == value)
        #expect(try JSONDecoder().decode(DocumentLocator.self, from: JSONEncoder().encode(value)) == value)
        guard case .comic(let format, _, _, let page, _, let y) = value else { Issue.record("Not a comic coordinate"); continue }
        #expect(try manifest.locator(format: format, page: page, y: y) == value)
    }
}

@Test func comicSharedAttackAndDuplicateVectors() throws {
    for vector in try comicVector().invalidCases {
        do {
            _ = try ComicManifest(entries: vector.entries.map(\.value))
            Issue.record("Accepted invalid entries: \(vector.entries.map(\.path))")
        } catch let error as ComicManifest.Failure {
            let tag: String = switch error {
            case .unsafePath: "unsafePath"
            case .link: "link"
            case .duplicatePath: "duplicatePath"
            case .unsupportedImage: "unsupportedImage"
            case .invalidImage: "invalidImage"
            case .empty: "empty"
            case .limitExceeded: "limitExceeded"
            }
            #expect(tag == vector.error)
        }
    }
    for path in ["//host/x.png", "https://host/x.png", "/", "./x.png", "a\r.png", "a\u{7f}.png", "a//"] {
        #expect(throws: (any Error).self) { try ComicManifest.canonicalPath(path) }
    }
    #expect(throws: ComicManifest.Failure.duplicatePath("readme.txt")) {
        try ComicManifest(paths: ["1.jpg", "readme.txt", "readme.txt"])
    }
    #expect(throws: ComicManifest.Failure.unsafePath(".hidden/../x.png")) {
        try ComicManifest(paths: ["1.jpg", ".hidden/../x.png"])
    }
    #expect(try ComicManifest.canonicalPath("e\u{301}/page.png") == "é/page.png")
    // Do not URL-decode or case-fold local resource identity.
    #expect(try ComicManifest.canonicalPath("a%2fb#?.png") == "a%2fb#?.png")
    #expect(try ComicManifest(paths: ["A.jpg", "a.jpg"]).pages.count == 2)
}

@Test func comicNaturalSortUsesRunsComponentsAndFinalRawScalarTieBreak() throws {
    let cases: [[String]] = [
        ["1.png", "2.png", "10.png"],
        ["a2.png", "a0002z.png", "a2z.png", "a10.png", "a-1.png"],
        ["A/2.png", "a/10.png"], // Must not raw-tie-break the directory component early.
        ["dir2/page3.png", "dir02/page10.png"],
        ["0.png", "00.png"], // Equal numeric values: full raw-scalar order decides.
        ["A.png", "a.PNG"],
        ["a.png", "Ä.png", "ä.png", "é.png", "中.png", "😀.png"],
        ["x9.png", "x٩.png", "x９.png"], // Non-ASCII digits are non-digit runs.
        ["x" + String(repeating: "9", count: 200) + ".png", "x1" + String(repeating: "0", count: 200) + ".png"],
    ]
    for expected in cases {
        #expect(expected.reversed().sorted(by: ComicManifest.pathLessThan) == expected)
    }
    let paths = try comicVector().pages.map(\.canonicalPath)
    for a in paths {
        #expect(!ComicManifest.pathLessThan(a, a))
        for b in paths where ComicManifest.pathLessThan(a, b) {
            #expect(!ComicManifest.pathLessThan(b, a))
            for c in paths where ComicManifest.pathLessThan(b, c) { #expect(ComicManifest.pathLessThan(a, c)) }
        }
    }
}

@Test func comicHiddenTypesImageSignaturesAndLimits() throws {
    let png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0xff])
    let jpeg = Data([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0])
    try ComicManifest.validateImageHeader(png, canonicalPath: "2.PNG")
    try ComicManifest.validateImageHeader(jpeg, canonicalPath: "1.JPEG")
    for (header, path) in [(png, "1.jpg"), (jpeg, "2.png"), (Data(), "1.jpg"), (png.prefix(7), "1.png")] {
        #expect(throws: ComicManifest.Failure.invalidImage(path)) { try ComicManifest.validateImageHeader(header, canonicalPath: path) }
    }
    for ext in ["GIF", "webp", "bmp", "TIFF", "heic", "avif", "jxl", "jp2", "svg", "ico", "apng", "psd", "tga"] {
        #expect(throws: ComicManifest.Failure.unsupportedImage("2." + ext)) { try ComicManifest(paths: ["1.jpg", "2." + ext]) }
    }
    #expect(throws: ComicManifest.Failure.unsupportedImage("1.gif")) { try ComicManifest.validateImageHeader(jpeg, canonicalPath: "1.gif") }
    #expect(try ComicManifest(paths: ["1.jpg", ".hidden/a.gif", "__MACOSX/a.gif", "a/.cover.png", "ComicInfo.xml", "nested.zip"]).paths == ["1.jpg"])
    #expect(try ComicManifest(paths: ["1.jpg", "__macosx/2.png"]).pages.count == 2)
    #expect(throws: ComicManifest.Failure.empty) { try ComicManifest(paths: ["dir/", "readme.txt"]) }
    #expect(throws: ComicManifest.Failure.limitExceeded) { try ComicManifest(paths: (0...10_000).map { "\($0).png" }) }
    #expect(throws: ComicManifest.Failure.limitExceeded) { try ComicManifest(entries: Array(repeating: .init(path: "x"), count: 20_001)) }
}

@Test func comicLocatorRejectsInvalidWireFields() throws {
    let manifest = try ComicManifest(paths: ["1.jpg", "2.png"])
    let locator = try manifest.locator(format: "cbz", page: 0)
    let base = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(locator)) as? [String: Any])
    let invalid: [(String, Any)] = [
        ("version", 2), ("version", true), ("profile", "comic-order-v2"), ("profile", NSNull()),
        ("format", "CBZ"), ("format", "kindle"), ("format", "pdf"),
        ("manifestHash", String(repeating: "A", count: 64)), ("manifestHash", String(repeating: "a", count: 63)),
        ("pageKey", String(repeating: "g", count: 64)), ("pageKey", "../1.jpg"), ("pageKey", true),
        ("page", -1), ("page", 2), ("page", 0.5), ("page", true), ("page", "0"),
        ("pageCount", 0), ("pageCount", 10_001), ("pageCount", 2.5),
        ("y", -0.000001), ("y", 1.000001), ("y", "NaN"), ("y", true),
        ("resource", "local/page.jpg"), ("offset", 1),
    ]
    for (key, value) in invalid {
        var json = base; json[key] = value
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(DocumentLocator.self, from: data) }
    }
    for key in base.keys {
        var json = base; json.removeValue(forKey: key)
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(DocumentLocator.self, from: data) }
    }
    for y in [Double.nan, .infinity, -.infinity, -1, 1.1] {
        #expect(throws: (any Error).self) { try manifest.locator(format: "cbz", page: 0, y: y) }
    }
    #expect(throws: (any Error).self) { try manifest.locator(format: "pdf", page: 0) }
    #expect(throws: (any Error).self) { try manifest.locator(format: "cbz", page: -1) }
    #expect(throws: (any Error).self) { try manifest.locator(format: "cbz", page: 2) }
}

@Test func comicLocalManifestRejectsForeignCoordinatesAndKeepsPageProgress() throws {
    let manifest = try ComicManifest(paths: ["1.jpg", "2.png"])
    let start = try manifest.locator(format: "cbz", page: 0, y: -0.0)
    let end = try manifest.locator(format: "cbz", page: 0, y: 1)
    #expect(start.progress == 0.5 && end.progress == 0.5)
    #expect(start.positionKey.hasSuffix(":0.000000"))
    #expect(start.positionKey != end.positionKey)
    #expect(try manifest.locator(format: "cbz", page: 1).progress == 1)
    #expect(try ComicManifest(paths: ["1.jpg"]).locator(format: "cbr", page: 0).progress == 1)
    let rounded = try manifest.locator(format: "cbz", page: 0, y: 0.1234565)
    #expect(rounded.positionKey.hasSuffix(":0.123457"))
    let samePosition = DocumentLocator.comic(format: "cbz", manifestHash: manifest.hash, pageKey: manifest.pageKeys[0], page: 0, pageCount: 2, y: 0.1234565)
    #expect(try manifest.validated(samePosition, format: "cbz") == rounded)
    #expect(samePosition.positionKey == rounded.positionKey)
    let foreign: [DocumentLocator] = [
        .comic(format: "cbr", manifestHash: manifest.hash, pageKey: manifest.pageKeys[0], page: 0, pageCount: 2, y: 0),
        .comic(format: "cbz", manifestHash: String(repeating: "0", count: 64), pageKey: manifest.pageKeys[0], page: 0, pageCount: 2, y: 0),
        .comic(format: "cbz", manifestHash: manifest.hash, pageKey: manifest.pageKeys[1], page: 0, pageCount: 2, y: 0),
        .comic(format: "cbz", manifestHash: manifest.hash, pageKey: manifest.pageKeys[0], page: 0, pageCount: 3, y: 0),
        .pdf(page: 0, pageCount: 2, y: 0),
        .epub(resource: "a.xhtml", spineIndex: 0, spineCount: 1, textOffset: 0, textLength: 0),
    ]
    for value in foreign { #expect(!manifest.valid(value, format: "cbz")) }
    #expect(try ComicManifest(paths: ["renamed.jpg", "2.png"]).hash != manifest.hash)
    #expect(try ComicManifest(paths: ["1.jpg", "2.png", ".ignored.png"]).hash == manifest.hash)
}

@Test func comicAdditionPreservesOldPDFAndEPUBSemantics() throws {
    let pdf = try DocumentLocator.pdf(page: 1, pageCount: 2, y: 0.1234565).validated()
    #expect(pdf.progress == 0.5617285)
    #expect(pdf.positionKey == "pdf:1:1:0.123457")
    #expect(try JSONDecoder().decode(DocumentLocator.self, from: JSONEncoder().encode(pdf)) == pdf)
    let epub = try DocumentLocator.epub(resource: "OPS/a.xhtml", spineIndex: 1, spineCount: 2, textOffset: 3, textLength: 18).validated()
    #expect(epub.progress == (1.0 + 3.0 / 18.0) / 2.0)
    #expect(epub.positionKey == "epub:1:OPS/a.xhtml:3")
    let data = try JSONEncoder().encode(epub)
    #expect(try JSONDecoder().decode(DocumentLocator.self, from: data) == epub)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["profile"] == nil && json["manifestHash"] == nil && json["pageKey"] == nil)
    #expect(try DocumentLocator.epub(resource: "a.xhtml", spineIndex: 0, spineCount: 1, textOffset: 0, textLength: 0).validated().progress == 0)
}
