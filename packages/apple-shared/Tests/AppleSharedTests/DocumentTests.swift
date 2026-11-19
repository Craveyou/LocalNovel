import Foundation
import Testing
@testable import AppleShared

private func documentFixture(_ name:String) -> URL {
    var root = URL(fileURLWithPath:#filePath)
    for _ in 0..<5 {root.deleteLastPathComponent()}
    return root.appending(path:"contracts/fixtures/documents/"+name)
}
private struct Vector:Decodable {let locator:DocumentLocator;let progress:Double}
@Test func namedEntitiesPreserveEscapingAndUnicodeInSinglePass() {
    let source = "中文👩‍💻é &nbsp; &copy; &amp;copy; &#160; &#x1f600; &notKnown;"
    #expect(XHTMLNamedEntities.normalize(source) == "中文👩‍💻é &#160; &#169; &#38;copy; &#160; &#x1f600; &notKnown;")
    #expect(XHTMLNamedEntities.normalize(String(repeating:source,count:5000)).hasSuffix("&notKnown;"))
}
@Test func sharedDocumentCoordinatesAndCanonicalEPUB() throws {
    let vectors = try JSONDecoder().decode([Vector].self,from:Data(contentsOf:documentFixture("coordinates.json")))
    let epub = try EPUBDocument(url:documentFixture("reflow.epub"))
    let texts = try JSONDecoder().decode([String].self,from:Data(contentsOf:documentFixture("canonical-text.json")))
    #expect(epub.chapters.map(\.resource) == ["OPS/z.xhtml","OPS/a.xhtml"])
    #expect(epub.chapters.map(\.text) == texts)
    #expect(epub.toc.count == 2)
    #expect(!epub.chapters[0].html.contains("authoredScriptExecuted"))
    #expect(try epub.read("OPS/dot.png").count > 0)
    for vector in vectors {
        #expect(abs(vector.locator.progress-vector.progress)<0.000000001)
        #expect(try JSONDecoder().decode(DocumentLocator.self,from:JSONEncoder().encode(vector.locator)) == vector.locator)
        if vector.locator.format == "epub" {#expect(epub.valid(vector.locator))}
    }
    #expect(epub.locator(chapter:0,offset:5) == epub.locator(chapter:0,offset:4))
    #expect(!epub.valid(.epub(resource:"OPS/z.xhtml",spineIndex:0,spineCount:2,textOffset:5,textLength:texts[0].utf16.count)))
}
@Test func rejectsUnknownCoordinatesAndUnsafeResources() throws {
    for json in [#"{"format":"pdf","version":2,"page":0,"pageCount":2,"y":0}"#,
                 #"{"format":"pdf","version":1,"page":0.5,"pageCount":2,"y":0}"#,
                 #"{"format":"pdf","version":1,"page":0,"pageCount":2,"y":0,"offset":1}"#,
                 #"{"format":"epub","version":1,"resource":"../x","spineIndex":0,"spineCount":1,"textOffset":0,"textLength":1}"#] {
        #expect(throws:(any Error).self) {try JSONDecoder().decode(DocumentLocator.self,from:Data(json.utf8))}
    }
    #expect(try DocumentLocator.pdf(page:0,pageCount:2,y:0.1234565).validated() == .pdf(page:0,pageCount:2,y:0.123457))
    #expect(try EPUBDocument.resolve(base:"OPS/z.xhtml",href:"../OPS/a.xhtml#next") == "OPS/a.xhtml")
    for path in ["/a","a//b","../a","a\\b","a%2fb","https:a","a?x"] {#expect(!DocumentLocator.safeResource(path))}
    #expect(throws:(any Error).self) {try EPUBDocument.resolve(base:"OPS/z.xhtml",href:"https://example.com/a")}
}
@Test func documentSearchBatchesAndExplicitWrapPreserveOrigin() throws {
    let text = String(repeating:"Needle ",count:450)
    var search = DocumentTextSearch(unit:0,offset:7)
    #expect(try search.next(query:"needle",count:1,text:{_ in text}).count == 200)
    #expect(try search.next(query:"needle",count:1,text:{_ in text}).count == 200)
    #expect(try search.next(query:"needle",count:1,text:{_ in text}).count == 49)
    #expect(search.exhausted)
    search.wrap()
    let first = try search.next(query:"needle",count:1,text:{_ in text})
    #expect(first.count == 1);#expect(first.first?.offset == 0)
    #expect(!DocumentTextSearch.validQuery("👨‍👩‍👧‍👦"));#expect(DocumentTextSearch.validQuery("👨‍👩‍👧‍👦中"))
}
