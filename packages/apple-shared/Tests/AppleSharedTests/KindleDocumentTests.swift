import Foundation
import XCTest
@testable import AppleShared

final class KindleDocumentTests: XCTestCase {
    private var root:URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    func testKindleCoordinatesUnicodeBoundariesAndBidirectionalSourceSpans() throws {
        let document = try KindleDocument(url:root.appending(path:"contracts/fixtures/documents/kindle-mobi6.mobi"))
        for (index,chapter) in document.chapters.enumerated() {
            let text = chapter.text as NSString,source = chapter.sourceHTML as NSString
            for offset in 0...text.length {
                let value = document.locator(chapter:index,offset:offset)
                XCTAssertTrue(document.valid(value));XCTAssertEqual(try JSONDecoder().decode(DocumentLocator.self,from:JSONEncoder().encode(value)),value)
                if offset < text.length,text.rangeOfComposedCharacterSequence(at:offset).location != offset {
                    XCTAssertFalse(document.valid(.kindle(textHash:document.textHash,textOffset:chapter.textStart+offset,textLength:document.canonicalText.utf16.count)))
                }
            }
            for map in chapter.maps {
                guard map.sourceStart >= 0 else {XCTAssertNil(document.sourceRange(forCanonicalOffset:map.textStart,chapter:index));continue}
                let sourceRange = try XCTUnwrap(document.sourceRange(forCanonicalOffset:map.textStart,chapter:index))
                let back = try XCTUnwrap(document.canonicalRange(forSourceOffset:sourceRange.location,chapter:index))
                XCTAssertTrue(NSLocationInRange(map.textStart,back))
                if map.kind == "text" {
                    XCTAssertEqual(text.substring(with:NSRange(location:map.textStart,length:map.textEnd-map.textStart)),source.substring(with:NSRange(location:map.sourceStart,length:map.sourceEnd-map.sourceStart)))
                }
            }
        }
        XCTAssertFalse(document.valid(.kindle(textHash:String(repeating:"b",count:64),textOffset:0,textLength:document.canonicalText.utf16.count)))
    }
    func testKindleSharedLocatorVectorsRejectUnknownAndForeignFields() throws {
        let vectors = try JSONSerialization.jsonObject(with:Data(contentsOf:root.appending(path:"contracts/fixtures/kindle-locators.json"))) as! [String:Any]
        let base = vectors["base"] as! [String:Any]
        for item in vectors["validOverrides"] as! [[String:Any]] {
            let value = base.merging(item["overrides"] as! [String:Any]){_,new in new}
            let locator = try JSONDecoder().decode(DocumentLocator.self,from:JSONSerialization.data(withJSONObject:value))
            XCTAssertEqual(locator.progress,item["progress"] as! Double,accuracy:1e-12)
        }
        for item in vectors["invalidOverrides"] as! [[String:Any]] {
            let value = base.merging(item["overrides"] as! [String:Any]){_,new in new}
            XCTAssertThrowsError(try JSONDecoder().decode(DocumentLocator.self,from:JSONSerialization.data(withJSONObject:value)),item["id"] as! String)
        }
        for key in base.keys {
            var value = base;value.removeValue(forKey:key)
            XCTAssertThrowsError(try JSONDecoder().decode(DocumentLocator.self,from:JSONSerialization.data(withJSONObject:value)))
        }
    }
    func testSharedCanonicalPublicationsAgreeWithNodeReferenceAndKeepOriginal() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in ["kindle-mobi6.mobi", "kindle-palmdoc.azw", "kindle-huff.mobi", "kindle-kf8.azw3", "kindle-mixed.mobi", "kindle-long.mobi"] {
            let url = root.appending(path: "contracts/fixtures/documents/" + name)
            let before = try Data(contentsOf: url)
            let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: url.appendingPathExtension("json"))) as! [String: Any]
            let book = try KindleDocument(url: url)
            XCTAssertEqual(book.canonicalText, expected["canonicalText"] as? String, name)
            XCTAssertEqual(book.textHash, expected["textHash"] as? String, name)
            XCTAssertEqual(book.mode, expected["mode"] as? String, name)
            XCTAssertEqual(book.coverResource,expected["coverResource"] as? String,name)
            XCTAssertFalse(book.toc.isEmpty, name)
            XCTAssertTrue(try book.read("resources/0.png").starts(with: [0x89,0x50,0x4e,0x47]), name)
            XCTAssertEqual(try Data(contentsOf: url), before, name)
        }
    }
    func testResourceReadRejectsChangedOrMissingOriginalWithoutChangingCoordinates() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path:"KindleChanged-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let url = directory.appending(path:"book.mobi")
        var bytes = try Data(contentsOf:root.appending(path:"contracts/fixtures/documents/kindle-mobi6.mobi"))
        try bytes.write(to:url)
        let document = try KindleDocument(url:url),position = document.locator(chapter:1,offset:5)
        bytes.append(0);try bytes.write(to:url)
        XCTAssertThrowsError(try document.read("resources/0.png"))
        XCTAssertTrue(document.valid(position))
        try FileManager.default.removeItem(at:url)
        XCTAssertThrowsError(try document.read("resources/0.png"))
        XCTAssertEqual(document.locator(chapter:1,offset:5),position)
    }
}
