import Foundation

// MARK: - 书库扫描：目录即结构
// <书库根>/<作者名(一本书)>/<章节名(一章)>/<文件>
// 不依赖任何清单文件，不写回用户目录，不联网。

enum BookScanner {

    /// 扫描书库根目录
    /// - Parameters:
    ///   - cleanTitles: 是否启用章节标题前缀清洗（默认关闭，原样展示文件夹名）
    static func scan(rootURL: URL, cleanTitles: Bool = false, fileManager: FileManager = .default) -> Library {
        let bookFolders = subdirectories(at: rootURL, fileManager: fileManager)
        let books: [Book] = bookFolders.map { bookFolder in
            let chapterFolders = subdirectories(at: bookFolder, fileManager: fileManager)
            let chapters: [Chapter] = chapterFolders.map { folder in
                let raw = folder.lastPathComponent
                return Chapter(folderURL: folder,
                               rawName: raw,
                               title: cleanTitles ? ChapterTitleCleaner.clean(raw) : raw)
            }
            return Book(folderURL: bookFolder,
                        title: bookFolder.lastPathComponent,
                        chapters: NaturalSort.sorted(chapters) { $0.rawName })
        }
        return Library(rootURL: rootURL,
                       books: NaturalSort.sorted(books) { $0.title })
    }

    /// 列出目录下的子文件夹（忽略隐藏项与文件），按自然序排列
    private static func subdirectories(at url: URL, fileManager: FileManager) -> [URL] {
        guard let items = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let dirs = items.filter { item in
            guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey]) else {
                return false
            }
            return values.isDirectory ?? false
        }
        return NaturalSort.sorted(dirs) { $0.lastPathComponent }
    }
}
