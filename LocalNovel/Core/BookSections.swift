import Foundation

// MARK: - 三分区扫描
//
// 小说/ 每个电子书文件 = 一本书；章节在首次打开时从正文里切（见 BookScanner.makeSliceChapters）
// 漫画/ 每个文件夹 = 一部漫画；「部 → 话」任意层，图片目录与 pdf 单话混排
// 整理/ 原有格式：作者文件夹 → 章节文件夹 → 正文 + 插图 + 音视频

enum LibrarySection: String, CaseIterable, Identifiable {
    case novel
    case comic
    case organized

    var id: String { rawValue }

    var category: BookCategory {
        switch self {
        case .novel: return .novel
        case .comic: return .comic
        case .organized: return .organized
        }
    }

    /// 文档目录下的文件夹名，与 BookCategory.label 保持一致
    var folderName: String { category.folderName }

    init?(folderName: String) {
        guard let match = LibrarySection.allCases.first(where: { $0.folderName == folderName })
        else { return nil }
        self = match
    }

    func scan(rootURL: URL, cleanTitles: Bool, fileManager: FileManager) -> [Book] {
        switch self {
        case .novel:     return NovelScanner.scan(rootURL: rootURL, cleanTitles: cleanTitles,
                                                  fileManager: fileManager)
        case .comic:     return ComicScanner.scan(rootURL: rootURL, cleanTitles: cleanTitles,
                                                  fileManager: fileManager)
        case .organized: return OrganizedScanner.scan(rootURL: rootURL, cleanTitles: cleanTitles,
                                                      fileManager: fileManager)
        }
    }

    var emptyHint: String {
        switch self {
        case .novel:
            return "「小说」里还没有书。每个 txt / md / epub / pdf 文件就是一本，直接放进来即可。"
        case .comic:
            return "「漫画」里还没有书。每部漫画一个文件夹：漫画名 → 第几部 → 第几话 → 图片，"
                + "或 漫画名 → 第几话.pdf。"
        case .organized:
            return "「整理」里还没有书。结构：作者名 → 章节名 → 正文.txt / 按序号命名的图片 / 音视频。"
        }
    }
}

// MARK: - 小说：每个电子书文件 = 一本书

enum NovelScanner {
    /// 小说区支持的电子书格式
    static let bookExtensions: Set<String> = ["txt", "text", "md", "markdown", "epub", "pdf"]

    static func isNovelFile(_ url: URL) -> Bool {
        bookExtensions.contains(MediaResolver.fileExtension(url.lastPathComponent))
    }

    static func scan(rootURL: URL, cleanTitles: Bool,
                     fileManager: FileManager = .default) -> [Book] {
        var books: [Book] = []
        collect(in: rootURL, depth: 0, series: [], into: &books,
                cleanTitles: cleanTitles, fileManager: fileManager)
        return NaturalSort.sorted(books) { $0.title }
    }

    /// 递归最多 3 层。
    /// · 根目录里的电子书文件 = 独立的一本书（不属于任何系列）
    /// · 根目录下的子文件夹 = 一个系列，往里多一层就是「系列 · 子系列」
    private static func collect(in dir: URL, depth: Int, series: [String], into books: inout [Book],
                                cleanTitles: Bool, fileManager: FileManager) {
        let files = BookScanner.files(in: dir, fileManager: fileManager)
            .filter { isNovelFile($0) }
        let seriesName = series.isEmpty ? nil : series.joined(separator: " · ")
        for file in files {
            let raw = file.deletingPathExtension().lastPathComponent
            let title = cleanTitles ? ChapterTitleCleaner.clean(raw) : raw
            let book = Book(folderURL: file,
                            title: title,
                            category: .novel,
                            chapters: placeholderChapter(for: file, title: title),
                            chaptersDeferred: true,
                            series: seriesName)
            books.append(book)
        }
        guard depth < 3 else { return }
        for sub in BookScanner.subdirectories(at: dir, fileManager: fileManager) {
            collect(in: sub, depth: depth + 1,
                    series: series + [sub.lastPathComponent], into: &books,
                    cleanTitles: cleanTitles, fileManager: fileManager)
        }
    }

    /// 扫描阶段不解析正文（epub 解包、pdf 抽文本都很贵），
    /// 先给一章占位；进入这本书时再后台切章。大书库启动不被拖慢。
    private static func placeholderChapter(for file: URL, title: String) -> [Chapter] {
        [Chapter(folderURL: file,
                 rawName: file.lastPathComponent,
                 title: title,
                 kind: .slice)]
    }
}

// MARK: - 漫画：每个文件夹 = 一部漫画

enum ComicScanner {
    /// 嵌套上限：漫画名/部/话/图 一般为 3 层，留两层的余量
    private static let maxDepth = 5

    static func scan(rootURL: URL, cleanTitles: Bool,
                     fileManager: FileManager = .default) -> [Book] {
        var books: [Book] = []
        for folder in BookScanner.subdirectories(at: rootURL, fileManager: fileManager) {
            let chapters = collect(in: folder, bookRoot: folder, depth: 0,
                                   group: [], cleanTitles: cleanTitles,
                                   fileManager: fileManager)
            guard !chapters.isEmpty else { continue }
            let raw = folder.lastPathComponent
            books.append(Book(folderURL: folder,
                              title: cleanTitles ? ChapterTitleCleaner.clean(raw) : raw,
                              category: .comic,
                              chapters: sortChapters(chapters)))
        }
        // 漫画区根目录里直接放图片（没有书名文件夹）时，整体当作一部
        let rootFiles = BookScanner.files(in: rootURL, fileManager: fileManager)
        if books.isEmpty,
           rootFiles.contains(where: { MediaResolver.isImageFile($0) || MediaResolver.isPDF($0) }) {
            let chapters = collect(in: rootURL, bookRoot: rootURL, depth: 0,
                                   group: [], cleanTitles: cleanTitles,
                                   fileManager: fileManager)
            if !chapters.isEmpty {
                let raw = rootURL.lastPathComponent
                books.append(Book(folderURL: rootURL,
                                  title: cleanTitles ? ChapterTitleCleaner.clean(raw) : raw,
                                  category: .comic,
                                  chapters: sortChapters(chapters)))
            }
        }
        return books
    }

    /// 同一部漫画里「图片话」和「pdf 话」是混着扫出来的，统一按展示名自然排序，
    /// 保证 第1部 第1话 → 第1部 第2话 → 第5话 的顺序。
    private static func sortChapters(_ chapters: [Chapter]) -> [Chapter] {
        NaturalSort.sorted(chapters) { $0.displayTitle }
    }

    /// 递归收集「话」：
    /// · 目录里直接有图片 → 这个目录就是一话
    /// · 目录里有 pdf → 每个 pdf 是一话
    /// · 其余子目录继续下钻，路径上的中间层记为卷名（第几部 / 单行本 …）
    private static func collect(in dir: URL, bookRoot: URL, depth: Int,
                                group: [String], cleanTitles: Bool,
                                fileManager: FileManager) -> [Chapter] {
        guard depth <= maxDepth else { return [] }
        let listing = (try? BookScanner.listDirectory(at: dir, fileManager: fileManager))
            ?? BookScanner.DirectoryListing(all: [], dirs: [])
        let files = listing.all.filter { !BookScanner.isDirectory($0, fileManager: fileManager) }
        let images = files.filter { MediaResolver.isImageFile($0) }
        let pdfs = files.filter { MediaResolver.isPDF($0) }
        let isBookRoot = dir.path == bookRoot.path

        var chapters: [Chapter] = []

        // 1. 当前目录本身就是一话（图片章节）
        if !images.isEmpty {
            let raw = dir.lastPathComponent
            chapters.append(Chapter(folderURL: dir,
                                    rawName: raw,
                                    title: cleanTitles ? ChapterTitleCleaner.clean(raw) : raw,
                                    kind: .folder,
                                    groupName: group.joined(separator: " · ")))
        }

        // 2. pdf 单话
        let pdfGroup = isBookRoot ? "" : (group + [dir.lastPathComponent]).joined(separator: " · ")
        for pdf in pdfs {
            let raw = pdf.deletingPathExtension().lastPathComponent
            chapters.append(Chapter(folderURL: pdf,
                                    rawName: pdf.lastPathComponent,
                                    title: cleanTitles ? ChapterTitleCleaner.clean(raw) : raw,
                                    kind: .file,
                                    groupName: pdfGroup))
        }

        // 3. 下钻
        guard depth < maxDepth else { return chapters }
        let nextGroup = isBookRoot ? group : group + [dir.lastPathComponent]
        for sub in listing.dirs {
            chapters += collect(in: sub, bookRoot: bookRoot, depth: depth + 1,
                                group: nextGroup, cleanTitles: cleanTitles,
                                fileManager: fileManager)
        }
        return chapters
    }
}

// MARK: - 整理：原有格式（作者 → 章节 → 文件）

enum OrganizedScanner {
    static func scan(rootURL: URL, cleanTitles: Bool,
                     fileManager: FileManager = .default) -> [Book] {
        let listed: BookScanner.DirectoryListing
        do {
            listed = try BookScanner.listDirectory(at: rootURL, fileManager: fileManager)
        } catch {
            return []
        }

        let mediaFiles = listed.all.filter {
            !BookScanner.isDirectory($0, fileManager: fileManager)
                && MediaResolver.classify($0.lastPathComponent) != nil
        }

        // A. 没有子文件夹，但根目录里直接是 txt / 图片 / 音视频 → 章节文件夹本身
        if listed.dirs.isEmpty {
            guard !mediaFiles.isEmpty else { return [] }
            let chapter = makeChapter(rootURL, cleanTitles: cleanTitles)
            let raw = rootURL.lastPathComponent
            return [Book(folderURL: rootURL,
                         title: cleanTitles ? ChapterTitleCleaner.clean(raw) : raw,
                         category: .organized,
                         chapters: [chapter])]
        }

        // B. 探测第一个子文件夹：里面有子文件夹 = 书库根（每个子文件夹一本书）
        let probe = listed.dirs[0]
        let nested = BookScanner.subdirectories(at: probe, fileManager: fileManager)

        if !nested.isEmpty {
            let books: [Book] = listed.dirs.map { bookFolder in
                let chapterFolders = BookScanner.subdirectories(at: bookFolder, fileManager: fileManager)
                let chapters = NaturalSort.sorted(chapterFolders.map {
                    makeChapter($0, cleanTitles: cleanTitles)
                }) { $0.rawName }
                let raw = bookFolder.lastPathComponent
                return Book(folderURL: bookFolder,
                            title: cleanTitles ? ChapterTitleCleaner.clean(raw) : raw,
                            category: .organized,
                            chapters: chapters)
            }
            return NaturalSort.sorted(books) { $0.title }
        }

        // C. 只有一层子文件夹 → 用户选中的是单个作者文件夹，其下即章节
        let chapters = NaturalSort.sorted(listed.dirs.map {
            makeChapter($0, cleanTitles: cleanTitles)
        }) { $0.rawName }
        let raw = rootURL.lastPathComponent
        return [Book(folderURL: rootURL,
                     title: cleanTitles ? ChapterTitleCleaner.clean(raw) : raw,
                     category: .organized,
                     chapters: chapters)]
    }

    private static func makeChapter(_ folder: URL, cleanTitles: Bool) -> Chapter {
        let raw = folder.lastPathComponent
        return Chapter(folderURL: folder,
                       rawName: raw,
                       title: cleanTitles ? ChapterTitleCleaner.clean(raw) : raw)
    }
}
