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

    /// 旧版书库（根下直接是作者文件夹）仍能被识别，全部归入「整理」
    func testLegacyLayoutAutoDetection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalNovelLayout-" + UUID().uuidString)
        let author = root.appendingPathComponent("作者甲")
        let chapter1 = author.appendingPathComponent("01_序章")
        try FileManager.default.createDirectory(at: chapter1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: author.appendingPathComponent("02_第二章"),
                                                withIntermediateDirectories: true)
        try Data("x".utf8).write(to: chapter1.appendingPathComponent("正文.txt"))
        defer { try? FileManager.default.removeItem(at: root) }

        let report = BookScanner.scanWithDiagnostics(rootURL: root)
        XCTAssertEqual(report.layout, .legacyRoot)
        XCTAssertEqual(report.library.books.count, 1)
        XCTAssertEqual(report.library.books.first?.chapters.count, 2)
        XCTAssertEqual(report.library.books.first?.category, .organized)
        XCTAssertNil(report.failureHint)

        // 空目录：明确给出失败提示，而不是笼统一句「没找到结构」
        let empty = root.appendingPathComponent("空目录")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let r2 = BookScanner.scanWithDiagnostics(rootURL: empty)
        XCTAssertEqual(r2.layout, .empty)
        XCTAssertNotNil(r2.failureHint)
    }

    /// 三分区书库：目录即分类，小说 / 漫画 / 整理各归各位
    func testThreeSectionsScan() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalNovelSections-" + UUID().uuidString)
        let fm = FileManager.default

        // 小说：一个 txt 就是一本
        let novelDir = root.appendingPathComponent("小说")
        try fm.createDirectory(at: novelDir, withIntermediateDirectories: true)
        try Data("第一章 起风\n内容\n第二章 落雨\n内容".utf8)
            .write(to: novelDir.appendingPathComponent("斗破.txt"))

        // 漫画：漫画名 → 第1部 → 第1话 → 图片；另有 第5话.pdf
        let comic = root.appendingPathComponent("漫画").appendingPathComponent("某漫画")
        let part1 = comic.appendingPathComponent("第1部").appendingPathComponent("第1话")
        try fm.createDirectory(at: part1, withIntermediateDirectories: true)
        for name in ["1.jpg", "2.jpg"] {
            try Data("x".utf8).write(to: part1.appendingPathComponent(name))
        }
        try Data("x".utf8).write(to: comic.appendingPathComponent("第5话.pdf"))

        // 整理：作者 → 章节 → 正文
        let organized = root.appendingPathComponent("整理")
            .appendingPathComponent("作者乙")
            .appendingPathComponent("第01章")
        try fm.createDirectory(at: organized, withIntermediateDirectories: true)
        try Data("正文".utf8).write(to: organized.appendingPathComponent("正文.txt"))

        defer { try? fm.removeItem(at: root) }

        let report = BookScanner.scanWithDiagnostics(rootURL: root)
        XCTAssertEqual(report.layout, .sections)
        XCTAssertEqual(report.library.count(in: .novel), 1)
        XCTAssertEqual(report.library.count(in: .comic), 1)
        XCTAssertEqual(report.library.count(in: .organized), 1)

        let comicBook = try XCTUnwrap(report.library.books(in: .comic).first)
        XCTAssertEqual(comicBook.title, "某漫画")
        // 一话图片目录 + 一个 pdf 单话
        XCTAssertEqual(comicBook.chapters.count, 2)
        XCTAssertEqual(comicBook.chapters[0].groupName, "第1部")
        XCTAssertEqual(comicBook.chapters[0].title, "第1话")
        XCTAssertTrue(comicBook.chapters[0].canDeleteFromDisk)
        XCTAssertEqual(comicBook.chapters[1].kind, .file)

        let organizedBook = try XCTUnwrap(report.library.books(in: .organized).first)
        XCTAssertEqual(organizedBook.chapters.count, 1)
    }

    /// 单独选中某个分区也能扫（导入后直接验证）
    func testSingleSectionScan() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalNovelOneSection-" + UUID().uuidString)
        let novelDir = root.appendingPathComponent("小说")
        try FileManager.default.createDirectory(at: novelDir, withIntermediateDirectories: true)
        try Data("第一章 a\nb".utf8).write(to: novelDir.appendingPathComponent("书一.txt"))
        try Data("x".utf8).write(to: novelDir.appendingPathComponent("封面.jpg"))
        defer { try? FileManager.default.removeItem(at: root) }

        let report = BookScanner.scanWithDiagnostics(rootURL: novelDir)
        XCTAssertEqual(report.layout, .singleSection)
        XCTAssertEqual(report.library.books.count, 1)
        XCTAssertEqual(report.library.books.first?.category, .novel)
    }

    /// 单文件小说按「第X章」切分，切不出来就整本一章
    func testNovelChapterSplit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalNovelSplit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let multi = root.appendingPathComponent("多章.txt")
        try Data("第一章 起风\n甲\n第二章 落雨\n乙\n第三章 天晴\n丙".utf8).write(to: multi)
        let chapters = BookScanner.makeSliceChapters(fileURL: multi, cleanTitles: false)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0].title, "第一章 起风")
        XCTAssertEqual(chapters[0].kind, .slice)
        XCTAssertNotNil(chapters[0].range)

        let single = root.appendingPathComponent("无章节名.txt")
        try Data("整本都是正文，没有任何章节标题。".utf8).write(to: single)
        let one = BookScanner.makeSliceChapters(fileURL: single, cleanTitles: false)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one[0].title, "无章节名")
    }

    /// 切片正文按区间取，不会串到下一章
    func testSliceTextIsolation() throws {
        let text = "第一章 甲\nAAA\n第二章 乙\nBBB"
        let slices = ChapterSplitter.split(text)
        XCTAssertEqual(slices.count, 2)
        let first = TextLoader.substring(text, range: slices[0].range)
        XCTAssertTrue(first.contains("AAA"))
        XCTAssertFalse(first.contains("BBB"))
    }

    /// 漫画 pdf 单话：装配成 pdf 章节而不是空章节
    func testPdfChapterResolve() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalNovelPDF-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pdf = root.appendingPathComponent("第1话.pdf")
        try Data("%PDF-1.4".utf8).write(to: pdf)
        defer { try? FileManager.default.removeItem(at: root) }

        let chapter = Chapter(folderURL: pdf, rawName: "第1话.pdf", title: "第1话", kind: .file)
        let content = MediaResolver.resolveChapter(chapter)
        XCTAssertEqual(content.pdfURL?.lastPathComponent, "第1话.pdf")
        XCTAssertTrue(content.isPdfChapter)
        XCTAssertNil(content.textURL)
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
