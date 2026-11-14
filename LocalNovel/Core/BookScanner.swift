import Foundation

// MARK: - 书库扫描：目录即结构
// <书库根>/<作者名(一本书)>/<章节名(一章)>/<文件>
// 不依赖任何清单文件，不写回用户目录，不联网。

/// 识别出的目录层级
enum LibraryLayout: String {
    /// 标准书库根：作者文件夹 → 章节文件夹 → 文件（两层）
    case libraryRoot
    /// 用户直接选中了某个作者文件夹：其下即章节文件夹
    case singleBook
    /// 用户直接选中了某个章节文件夹：其下即 txt / 图片 / 音视频
    case chapterFolder
    /// 目录可读，但没有可识别内容
    case empty
    /// 目录读取失败（权限失效 / 不存在 / iCloud 未下载）
    case unreadable
}

/// 扫描诊断：把「为什么没出现书」明确告诉用户，而不是一律显示「没找到结构」
struct ScanDiagnostics {
    let library: Library
    let layout: LibraryLayout
    /// 根目录读到的可见条目数；-1 表示读取失败
    let topLevelItemCount: Int
    let readError: String?
    /// 成功时的摘要（如「已载入 2 本书 / 12 章」）
    let summary: String
    /// 未得到书时的具体原因与建议
    let failureHint: String?
}

enum BookScanner {

    /// 兼容原接口（单元测试与既有调用点使用）
    static func scan(rootURL: URL, cleanTitles: Bool = false, fileManager: FileManager = .default) -> Library {
        scanWithDiagnostics(rootURL: rootURL, cleanTitles: cleanTitles, fileManager: fileManager).library
    }

    /// 带诊断的扫描：自动识别用户选中的层级，并显式上报读取错误
    static func scanWithDiagnostics(
        rootURL: URL,
        cleanTitles: Bool = false,
        fileManager: FileManager = .default
    ) -> ScanDiagnostics {
        let listed: DirectoryListing
        do {
            listed = try listDirectory(at: rootURL, fileManager: fileManager)
        } catch {
            // 不再吞掉错误：权限失效 / iCloud 文件未下载 / 目录被删，都能看到真实原因
            let hint = "无法读取该目录（\(error.localizedDescription)）。"
                + "常见原因：目录访问权限已失效、文件夹被移动或删除、或文件在 iCloud 上尚未下载。"
                + "请重新点「选择书库目录」再选一次。"
            return ScanDiagnostics(library: Library(rootURL: rootURL, books: []),
                                   layout: .unreadable, topLevelItemCount: -1,
                                   readError: error.localizedDescription,
                                   summary: "目录读取失败", failureHint: hint)
        }

        let all = listed.all
        let folders = listed.dirs
        let mediaFiles = all.filter {
            !isDirectory($0, fileManager: fileManager)
                && MediaResolver.classify($0.lastPathComponent) != nil
        }
        let total = all.count

        // 情形 A：没有子文件夹，但根目录里直接是 txt / 图片 / 音视频
        // → 用户选中的是「章节文件夹」本身，包装成一本单章书
        if folders.isEmpty {
            if !mediaFiles.isEmpty {
                let chapter = makeChapter(rootURL, cleanTitles: cleanTitles)
                let book = Book(folderURL: rootURL,
                                title: rootURL.lastPathComponent,
                                chapters: [chapter])
                let lib = Library(rootURL: rootURL, books: [book])
                return ScanDiagnostics(library: lib, layout: .chapterFolder,
                                       topLevelItemCount: total, readError: nil,
                                       summary: "识别为单个章节文件夹：1 本书 / 1 章（\(mediaFiles.count) 个媒体文件）",
                                       failureHint: nil)
            }
            let hint = total == 0
                ? "这个目录是空的。请选择包含「作者文件夹」的那一层书库根目录。"
                : "这个目录里有 \(total) 个条目，但没有子文件夹，也没有 txt / 图片 / 视频。"
                    + "请确认选择的是包含作者文件夹的书库根目录，而不是某个文件所在的位置。"
            return ScanDiagnostics(library: Library(rootURL: rootURL, books: []),
                                   layout: .empty, topLevelItemCount: total,
                                   readError: nil, summary: "未发现可识别内容", failureHint: hint)
        }

        // 情形 B：有子文件夹。探测第一个子文件夹，判断它是「作者」还是「章节」
        let probe = folders[0]
        let nested = (try? listDirectory(at: probe, fileManager: fileManager))?.dirs ?? []

        if !nested.isEmpty {
            // B1 标准书库根：子文件夹 = 作者（一本书），其下的子文件夹 = 章节
            let books: [Book] = folders.map { bookFolder in
                let chapterFolders = subdirectories(at: bookFolder, fileManager: fileManager)
                let chapters: [Chapter] = chapterFolders.map {
                    makeChapter($0, cleanTitles: cleanTitles)
                }
                return Book(folderURL: bookFolder,
                            title: bookFolder.lastPathComponent,
                            chapters: NaturalSort.sorted(chapters) { $0.rawName })
            }
            let lib = Library(rootURL: rootURL, books: NaturalSort.sorted(books) { $0.title })
            let chapterCount = lib.books.reduce(0) { $0 + $1.chapters.count }
            let summary = "书库根目录：\(total) 个顶层条目 → \(lib.books.count) 本书 / \(chapterCount) 章"
            let hint = lib.books.isEmpty
                ? "没有找到作者文件夹，请确认选择的是包含作者文件夹的那一层。"
                : nil
            return ScanDiagnostics(library: lib, layout: .libraryRoot,
                                   topLevelItemCount: total, readError: nil,
                                   summary: summary, failureHint: hint)
        }

        // B2 子文件夹里没有更深的子文件夹 → 用户选中的是「单个作者文件夹」
        // 把 root 当作一本书，其下的文件夹当作章节
        let chapters: [Chapter] = folders.map { makeChapter($0, cleanTitles: cleanTitles) }
        let book = Book(folderURL: rootURL,
                        title: rootURL.lastPathComponent,
                        chapters: NaturalSort.sorted(chapters) { $0.rawName })
        let lib = Library(rootURL: rootURL, books: [book])
        return ScanDiagnostics(library: lib, layout: .singleBook,
                               topLevelItemCount: total, readError: nil,
                               summary: "识别为单本书（作者文件夹）：1 本书 / \(chapters.count) 章",
                               failureHint: nil)
    }

    // MARK: - 内部工具

    private struct DirectoryListing {
        let all: [URL]
        let dirs: [URL]
    }

    /// 读取目录；失败时抛出，交由上层形成诊断，不再静默返回空数组
    private static func listDirectory(at url: URL, fileManager: FileManager) throws -> DirectoryListing {
        let items = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let visible = items.filter { !MediaResolver.isHidden($0.lastPathComponent) }
        let dirs = visible.filter { isDirectory($0, fileManager: fileManager) }
        return DirectoryListing(all: visible,
                                dirs: NaturalSort.sorted(dirs) { $0.lastPathComponent })
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) {
            return values.isDirectory ?? false
        }
        var flag: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

    /// 列出目录下的子文件夹；读取失败返回空（用于章节层，主目录错误已在上层捕获）
    private static func subdirectories(at url: URL, fileManager: FileManager) -> [URL] {
        (try? listDirectory(at: url, fileManager: fileManager))?.dirs ?? []
    }

    private static func makeChapter(_ folder: URL, cleanTitles: Bool) -> Chapter {
        let raw = folder.lastPathComponent
        return Chapter(folderURL: folder,
                       rawName: raw,
                       title: cleanTitles ? ChapterTitleCleaner.clean(raw) : raw)
    }
}
