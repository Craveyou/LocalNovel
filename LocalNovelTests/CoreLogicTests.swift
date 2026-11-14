import Foundation
import XCTest
@testable import LocalNovel

// MARK: - Core 层单元测试（与 Validation/validate_core.py 用例对齐）

final class CoreLogicTests: XCTestCase {

    func testNaturalSortNumeric() {
        let input = ["10", "2", "1"]
        let result = NaturalSort.sorted(input) { $0 }
        XCTAssertEqual(result, ["1", "2", "10"])
    }

    func testNaturalSortFullWidthAndLeadingZeros() {
        let input = ["１０.png", "2.png", "1.png"]
        let result = NaturalSort.sorted(input) { $0 }
        XCTAssertEqual(result, ["1.png", "2.png", "１０.png"])
    }

    func testNaturalSortChapterPrefix() {
        let input = ["第10章", "第2章", "第1章"]
        XCTAssertEqual(NaturalSort.sorted(input) { $0 }, ["第1章", "第2章", "第10章"])
    }

    func testImageSequence() {
        XCTAssertEqual(MediaResolver.imageSequence("12.png"), 12)
        XCTAssertEqual(MediaResolver.imageSequence("003.jpg"), 3)
        XCTAssertEqual(MediaResolver.imageSequence("２.gif"), 2)
        XCTAssertNil(MediaResolver.imageSequence("无序号插图.jpg"))
        XCTAssertNil(MediaResolver.imageSequence("封面.png"))
    }

    func testClassification() {
        XCTAssertEqual(MediaResolver.classify("正文.txt"), .text)
        XCTAssertEqual(MediaResolver.classify("2.gif"), .image)
        XCTAssertEqual(MediaResolver.classify("clip.mp4"), .video)
        XCTAssertEqual(MediaResolver.classify("audio.m4a"), .audio)
        XCTAssertNil(MediaResolver.classify("notes.docx"))
        XCTAssertTrue(MediaResolver.isHidden(".DS_Store"))
    }

    func testTitleCleaner() {
        XCTAssertEqual(ChapterTitleCleaner.clean("01_序章"), "序章")
        XCTAssertEqual(ChapterTitleCleaner.clean("第01章 起风了"), "起风了")
        XCTAssertEqual(ChapterTitleCleaner.clean("纯标题"), "纯标题")
    }

    func testParagraphs() {
        let text = "第一段第一行\n第一段第二行\n\n第二段\n\n\n第三段"
        let result = TextLoader.paragraphs(text)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result[0].contains("第一段第二行"))
        XCTAssertEqual(result[2], "第三段")
    }

    /// 章节装配：正文 → 图片（序号）→ 章末音视频，且异常文件不崩溃
    func testResolveChapterOrderAndEdgeCases() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalNovelTests-" + UUID().uuidString)
        let chapterFolder = root.appendingPathComponent("01_测试章")
        try FileManager.default.createDirectory(at: chapterFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for name in ["正文.txt", "1.png", "2.gif", "10.png", "无序号.jpg", "clip.mp4", "notes.docx", ".DS_Store"] {
            let url = chapterFolder.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
        }

        let chapter = Chapter(folderURL: chapterFolder, rawName: "01_测试章", title: "01_测试章")
        let content = MediaResolver.resolveChapter(chapter)

        XCTAssertEqual(content.textURL?.lastPathComponent, "正文.txt")
        XCTAssertEqual(content.images.map { $0.fileName }, ["1.png", "2.gif", "10.png", "无序号.jpg"])
        XCTAssertTrue(content.images[1].isAnimated)
        XCTAssertEqual(content.avMedia.map { $0.fileName }, ["clip.mp4"])
        XCTAssertTrue(content.ignoredFiles.contains("notes.docx"))
    }

    /// 两层目录结构：作者文件夹 = 一本书，章节文件夹 = 一章
    func testLibraryStructure() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalNovelTests-" + UUID().uuidString)
        let book = root.appendingPathComponent("作者甲")
        try FileManager.default.createDirectory(at: book.appendingPathComponent("02_第二章"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: book.appendingPathComponent("01_第一章"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let library = BookScanner.scan(rootURL: root)
        XCTAssertEqual(library.books.count, 1)
        XCTAssertEqual(library.books.first?.title, "作者甲")
        XCTAssertEqual(library.books.first?.chapters.map { $0.rawName }, ["01_第一章", "02_第二章"])
    }

    /// 空章节 / 缺正文不崩溃
    func testEmptyChapterIsSafe() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalNovelTests-" + UUID().uuidString)
        let folder = root.appendingPathComponent("空章")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let chapter = Chapter(folderURL: folder, rawName: "空章", title: "空章")
        let content = MediaResolver.resolveChapter(chapter)
        XCTAssertNil(content.textURL)
        XCTAssertTrue(content.images.isEmpty)
        XCTAssertTrue(content.avMedia.isEmpty)
    }
}
