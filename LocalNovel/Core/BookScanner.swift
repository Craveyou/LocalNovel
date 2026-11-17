import Foundation

// MARK: - 书库入口：三个固定分区，目录即分类
//
// 本地小说/
//   小说/    每个电子书文件 = 一本书（txt / md / epub / pdf）
//   漫画/    每个文件夹 = 一部漫画，部 → 话 多层，图片目录或 pdf 单话
//   整理/    原有格式：作者文件夹 → 章节文件夹 → 正文 + 插图 + 音视频
//
// 分类不再靠内容猜测：书在哪个分区就是哪一类，用户在「文件」App 里怎么放就怎么显示。
// 缺少某个分区时按空处理，不报错、不猜。

/// 识别出的目录层级
enum LibraryLayout: String {
    /// 三分区书库根（小说 / 漫画 / 整理）
    case sections
    /// 用户直接选中了某一个分区目录（其下即书）
    case singleSection
    /// 兼容旧版：根目录下直接是作者文件夹（全部归入「整理」）
    case legacyRoot
    /// 目录可读，但没有可识别内容
    case empty
    /// 目录读取失败（权限失效 / 不存在 / iCloud 未下载）
    case unreadable
}

/// 扫描诊断：把「为什么没出现书」明确告诉用户
struct ScanDiagnostics {
    let library: Library
    let layout: LibraryLayout
    /// 根目录读到的可见条目数；-1 表示读取失败
    let topLevelItemCount: Int
    let readError: String?
    /// 成功时的摘要（如「小说 3 · 漫画 5 · 整理 2」）
    let summary: String
    /// 未得到书时的具体原因与建议
    let failureHint: String?
}

enum BookScanner {

    /// 兼容原接口（单元测试与既有调用点使用）
    static func scan(rootURL: URL, cleanTitles: Bool = false,
                     fileManager: FileManager = .default) -> Library {
        scanWithDiagnostics(rootURL: rootURL, cleanTitles: cleanTitles,
                            fileManager: fileManager).library
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
            let hint = "无法读取该目录（\(error.localizedDescription)）。"
                + "常见原因：目录访问权限已失效、文件夹被移动或删除、或文件在 iCloud 上尚未下载。"
                + "请重新点「选择书库目录」再选一次。"
            return ScanDiagnostics(library: Library(rootURL: rootURL, books: []),
                                   layout: .unreadable, topLevelItemCount: -1,
                                   readError: error.localizedDescription,
                                   summary: "目录读取失败", failureHint: hint)
        }

        let total = listed.all.count

        // 情形 1：直接选中了某一个分区（小说 / 漫画 / 整理）
        // 仅当目录名是分区名、且内部没有再嵌分区目录时才这样判定，
        // 避免书库根恰好叫「小说」时被误当成单个分区。
        if let section = LibrarySection(folderName: rootURL.lastPathComponent),
           !looksLikeLibraryRoot(listed, fileManager: fileManager) {
            let books = section.scan(rootURL: rootURL, cleanTitles: cleanTitles,
                                     fileManager: fileManager)
            let lib = Library(rootURL: rootURL, books: books)
            return ScanDiagnostics(library: lib, layout: .singleSection,
                                   topLevelItemCount: total, readError: nil,
                                   summary: "「\(section.category.label)」分区：\(books.count) 本",
                                   failureHint: books.isEmpty ? section.emptyHint : nil)
        }

        // 情形 2：三分区书库根
        let presentSections = LibrarySection.allCases.filter { section in
            var isDir: ObjCBool = false
            let url = rootURL.appendingPathComponent(section.folderName)
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
        if !presentSections.isEmpty {
            var books: [Book] = []
            var parts: [String] = []
            for section in presentSections {
                let dir = rootURL.appendingPathComponent(section.folderName)
                let found = section.scan(rootURL: dir, cleanTitles: cleanTitles,
                                         fileManager: fileManager)
                books.append(contentsOf: found)
                parts.append("\(section.category.label) \(found.count)")
            }

            // 升级前放的书：根目录里还有非分区文件夹 → 按「整理」规则扫出来，不丢书
            let looseDirs = listed.dirs.filter {
                LibrarySection(folderName: $0.lastPathComponent) == nil
            }
            if !looseDirs.isEmpty {
                var legacyCount = 0
                for dir in looseDirs {
                    let found = OrganizedScanner.scan(rootURL: dir, cleanTitles: cleanTitles,
                                                      fileManager: fileManager)
                    legacyCount += found.count
                    books.append(contentsOf: found)
                }
                if legacyCount > 0 { parts.append("根目录旧结构 \(legacyCount)（归入整理）") }
            }

            let lib = Library(rootURL: rootURL, books: NaturalSort.sorted(books) { $0.title })
            let hint = lib.books.isEmpty
                ? "「\(presentSections.map { $0.folderName }.joined(separator: " / "))」里还没有可识别的书。"
                    + "小说分区放 txt / epub / pdf 文件；漫画分区每部一个文件夹，里面按「部 → 话」放图片或 pdf。"
                : nil
            return ScanDiagnostics(library: lib, layout: .sections,
                                   topLevelItemCount: total, readError: nil,
                                   summary: parts.joined(separator: " · "),
                                   failureHint: hint)
        }

        // 情形 3：兼容旧书库（根下直接是作者文件夹）→ 全部按「整理」规则扫描
        let legacy = OrganizedScanner.scan(rootURL: rootURL, cleanTitles: cleanTitles,
                                           fileManager: fileManager)
        if !legacy.isEmpty {
            let lib = Library(rootURL: rootURL, books: legacy)
            return ScanDiagnostics(library: lib, layout: .legacyRoot,
                                   topLevelItemCount: total, readError: nil,
                                   summary: "旧版书库结构：\(legacy.count) 本（已归入「整理」）",
                                   failureHint: nil)
        }

        let hint = total == 0
            ? "这个目录是空的。请在「本地小说」里建三个文件夹：小说 / 漫画 / 整理。"
            : "这个目录里有 \(total) 个条目，但没有识别到书。"
                + "请确认选择的是「本地小说」这一层，里面包含 小说 / 漫画 / 整理 三个文件夹。"
        return ScanDiagnostics(library: Library(rootURL: rootURL, books: []),
                               layout: .empty, topLevelItemCount: total,
                               readError: nil, summary: "未发现可识别内容",
                               failureHint: hint)
    }

    // MARK: - 内部工具（三个分区扫描器共用）

    struct DirectoryListing {
        let all: [URL]
        let dirs: [URL]
    }

    /// 读取目录；失败时抛出，交由上层形成诊断，不再静默返回空数组
    static func listDirectory(at url: URL, fileManager: FileManager) throws -> DirectoryListing {
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

    static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) {
            return values.isDirectory ?? false
        }
        var flag: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

    /// 列出目录下的子文件夹；读取失败返回空
    static func subdirectories(at url: URL, fileManager: FileManager) -> [URL] {
        (try? listDirectory(at: url, fileManager: fileManager))?.dirs ?? []
    }

    static func files(in url: URL, fileManager: FileManager) -> [URL] {
        guard let listing = try? listDirectory(at: url, fileManager: fileManager) else { return [] }
        return listing.all.filter { !isDirectory($0, fileManager: fileManager) }
    }

    /// 目录名是不是三分区之一（用于判断用户选中的是分区本身还是书库根）
    private static func looksLikeLibraryRoot(_ listing: DirectoryListing,
                                             fileManager: FileManager) -> Bool {
        listing.dirs.contains { LibrarySection(folderName: $0.lastPathComponent) != nil }
    }

    /// 从整本正文里按「第X章」切章（epub 优先用 spine 自带的分章；无匹配则整本一章）
    ///
    /// customPattern 是用户给这本书写的「重新分章」规则（由 LibraryStore 从 Preferences 取后透传）。
    /// 规则优先：切出两章以上就用它；规则写错 / 切不出多章时 ChapterSplitter 会退回内置正则，
    /// 所以这里有规则也不会把一本书切成空。
    static func makeSliceChapters(fileURL: URL, cleanTitles: Bool,
                                  customPattern: String? = nil) -> [Chapter] {
        let bookTitle = fileURL.deletingPathExtension().lastPathComponent
        var slices: [ChapterSplitter.Slice] = []
        let rule = (customPattern ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !rule.isEmpty,
           let regex = ChapterSplitter.makePattern(rule),
           let text = try? TextLoader.loadDocument(fileURL) {
            let custom = ChapterSplitter.split(text, customPattern: regex)
            if custom.count >= 2 { slices = custom }
        }
        if slices.isEmpty, MediaResolver.isEpub(fileURL) {
            slices = EpubParser.slices(url: fileURL)
        }
        if slices.isEmpty, let text = try? TextLoader.loadDocument(fileURL) {
            slices = ChapterSplitter.split(text)
        }
        guard !slices.isEmpty else {
            let title = cleanTitles ? ChapterTitleCleaner.clean(bookTitle) : bookTitle
            return [Chapter(folderURL: fileURL,
                            rawName: fileURL.lastPathComponent,
                            title: title,
                            kind: .slice)]
        }
        if slices.count == 1 {
            let chapterTitle = cleanTitles
                ? ChapterTitleCleaner.clean(bookTitle)
                : bookTitle
            return [Chapter(folderURL: fileURL,
                            rawName: fileURL.lastPathComponent,
                            title: chapterTitle,
                            kind: .slice,
                            range: slices[0].range)]
        }
        return slices.map { slice in
            Chapter(folderURL: fileURL,
                    rawName: slice.title,
                    title: cleanTitles ? ChapterTitleCleaner.clean(slice.title) : slice.title,
                    kind: .slice,
                    range: slice.range)
        }
    }
}
