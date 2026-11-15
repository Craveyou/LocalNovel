import Foundation
import CryptoKit

// MARK: - NAS 上的「书库结构」
//
// 书库本地的三层是：分区 → 书 → 章节 → 内容（正文 + 插图 + 章末音视频）。
// NAS 这里完全对齐，只是每一层都改成按需 PROPFIND（不预扫整棵树）：
//
//   NAS 分类根  →  书名列表        （organize: 每个子目录一本书）
//   书目录      →  章节列表        （organize: 每个子目录一章）
//   章节目录    →  正文 / 图片 / 音视频（与本地「整理」一样的排布）
//
// 漫画与短剧复用同一套层级，章节的识别规则分别对齐 ComicScanner / ShortDramaScanner，
// 这样同一个目录在本地和 NAS 上看到的层级与标题是一致的。

enum NASChapterKind: String, Hashable {
    /// 图片目录（漫画一话 / 短剧剧照包）
    case images
    /// 单个 pdf（漫画一话）
    case pdf
    /// 单个视频（短剧一集）
    case video
    case audio
    /// 普通章节目录（整理：正文 + 插图 + 章末音视频）
    case folder
    /// 单个文本文件
    case text

    var symbol: String {
        switch self {
        case .images: return "photo.on.rectangle.angled"
        case .pdf:    return "doc.richtext"
        case .video:  return "play.rectangle"
        case .audio:  return "waveform"
        case .folder: return "folder"
        case .text:   return "doc.text"
        }
    }

    var label: String {
        switch self {
        case .images: return "图片"
        case .pdf:    return "PDF"
        case .video:  return "视频"
        case .audio:  return "音频"
        case .folder: return "章节"
        case .text:   return "正文"
        }
    }
}

struct NASChapterRef: Identifiable, Hashable {
    let name: String
    let url: URL
    let kind: NASChapterKind
    /// 包名 / 卷名（短剧的「剧照」「视频」，漫画的「第1部」）
    let group: String?

    var id: String { url.absoluteString }

    var displayName: String {
        guard let group, !group.isEmpty, group != name else { return name }
        return "\(group) · \(name)"
    }
}

// MARK: - 目录探测

enum NASPlanner {
    /// 书籍列表：分类根下的子目录。根下直接放文件（结构不规范）时返回空，
    /// 由界面把根目录自己当成唯一一本，避免「明明有文件却显示空」。
    static func books(at root: URL,
                      category: BookCategory,
                      account: WebDAVAccount) async throws -> [RemoteEntry] {
        let entries = try await WebDAVClient.list(dir: root, account: account)
        return entries.filter { $0.isDirectory }
    }

    /// 书籍行上的数量：只探一层，不为了一个数字递归整本书。
    /// 整理 / 漫画 / 短剧的书目录下一层正好是「章 / 话 / 包」。
    static func itemCount(bookURL: URL,
                          category: BookCategory,
                          account: WebDAVAccount) async -> Int? {
        guard let entries = try? await WebDAVClient.list(dir: bookURL, account: account) else {
            return nil
        }
        let dirs = entries.filter { $0.isDirectory }.count
        if dirs > 0 { return dirs }
        if category == .organized || category == .novel {
            // 书目录里直接放文件：这本书只有一章
            let hasMedia = entries.contains {
                !$0.isDirectory && MediaResolver.classify($0.name) != nil
            }
            return hasMedia ? 1 : nil
        }
        return dirs
    }

    /// 一本书的章节列表
    static func chapters(bookURL: URL,
                         category: BookCategory,
                         account: WebDAVAccount) async throws -> [NASChapterRef] {
        switch category {
        case .organized, .novel:
            return try await organizedChapters(bookURL: bookURL, account: account)
        case .comic:
            return try await comicChapters(dir: bookURL, root: bookURL,
                                           depth: 0, group: [], account: account)
        case .shortDrama:
            return try await dramaChapters(dir: bookURL, root: bookURL,
                                           depth: 0, group: [], account: account)
        }
    }

    // MARK: 整理：书 → 子目录 = 章节

    private static func organizedChapters(bookURL: URL,
                                          account: WebDAVAccount) async throws -> [NASChapterRef] {
        let entries = try await WebDAVClient.list(dir: bookURL, account: account)
        let dirs = entries.filter { $0.isDirectory }
        if dirs.isEmpty {
            // 书目录里直接就是 txt / 图片 / 音视频 → 这本书只有一章（就是它自己）
            let hasMedia = entries.contains { !$0.isDirectory && MediaResolver.classify($0.name) != nil }
            guard hasMedia else { return [] }
            return [NASChapterRef(name: bookURL.lastPathComponent,
                                  url: bookURL,
                                  kind: .folder,
                                  group: nil)]
        }
        return NaturalSort.sorted(dirs) { $0.name }.map {
            NASChapterRef(name: $0.name, url: $0.url, kind: .folder, group: nil)
        }
    }

    // MARK: 漫画：目录里有图片 = 一话；有 pdf = 每个 pdf 一话；否则下钻

    private static func comicChapters(dir: URL, root: URL, depth: Int,
                                      group: [String],
                                      account: WebDAVAccount) async throws -> [NASChapterRef] {
        guard depth <= 4 else { return [] }
        let entries = try await WebDAVClient.list(dir: dir, account: account)
        let files = entries.filter { !$0.isDirectory }
        let images = files.filter { MediaResolver.imageExtensions.contains(ext($0.name)) }
        let pdfs = files.filter { MediaResolver.isPDF($0.url) }
        let isRoot = dir.path == root.path

        var result: [NASChapterRef] = []
        let ownGroup = group.joined(separator: " · ")

        if !images.isEmpty {
            result.append(NASChapterRef(name: dir.lastPathComponent,
                                        url: dir,
                                        kind: .images,
                                        group: ownGroup.isEmpty ? nil : ownGroup))
        }

        let pdfGroup = (isRoot ? [] : group + [dir.lastPathComponent]).joined(separator: " · ")
        for pdf in pdfs {
            result.append(NASChapterRef(name: (pdf.name as NSString).deletingPathExtension,
                                        url: pdf.url,
                                        kind: .pdf,
                                        group: pdfGroup.isEmpty ? nil : pdfGroup))
        }

        guard depth < 4 else { return sortForComic(result) }
        let nextGroup = isRoot ? group : group + [dir.lastPathComponent]
        for sub in entries.filter({ $0.isDirectory }) {
            result += try await comicChapters(dir: sub.url, root: root, depth: depth + 1,
                                              group: nextGroup, account: account)
        }
        return sortForComic(result)
    }

    // MARK: 短剧：剧名 → 包 → 集；图片目录 = 剧照包，视频 = 每集

    private static func dramaChapters(dir: URL, root: URL, depth: Int,
                                      group: [String],
                                      account: WebDAVAccount) async throws -> [NASChapterRef] {
        guard depth <= 3 else { return [] }
        let entries = try await WebDAVClient.list(dir: dir, account: account)
        let files = entries.filter { !$0.isDirectory }
        let images = files.filter { MediaResolver.imageExtensions.contains(ext($0.name)) }
        let videos = files.filter { MediaResolver.isVideoFile($0.url) }
        let isRoot = dir.path == root.path
        let ownGroup = isRoot ? [] : group + [dir.lastPathComponent]

        var result: [NASChapterRef] = []

        if !images.isEmpty {
            let name = dir.lastPathComponent
            result.append(NASChapterRef(name: isRoot ? "剧照" : name,
                                        url: dir,
                                        kind: .images,
                                        group: nil))
        }

        let videoGroup = ownGroup.joined(separator: " · ")
        for video in videos {
            result.append(NASChapterRef(name: (video.name as NSString).deletingPathExtension,
                                        url: video.url,
                                        kind: .video,
                                        group: videoGroup.isEmpty ? nil : videoGroup))
        }

        guard depth < 3 else { return sortForDrama(result) }
        for sub in entries.filter({ $0.isDirectory }) {
            result += try await dramaChapters(dir: sub.url, root: root, depth: depth + 1,
                                              group: ownGroup, account: account)
        }
        return sortForDrama(result)
    }

    // MARK: 排序（与本地扫描器同一规则）

    private static func sortForComic(_ chapters: [NASChapterRef]) -> [NASChapterRef] {
        chapters.sorted { a, b in
            let ga = a.group ?? "", gb = b.group ?? ""
            if ga.isEmpty != gb.isEmpty { return !ga.isEmpty }
            if NaturalSort.less(ga, gb) { return true }
            if NaturalSort.less(gb, ga) { return false }
            if NaturalSort.less(a.name, b.name) { return true }
            if NaturalSort.less(b.name, a.name) { return false }
            return a.id < b.id
        }
    }

    private static func sortForDrama(_ chapters: [NASChapterRef]) -> [NASChapterRef] {
        chapters.sorted { a, b in
            let aImages = a.kind == .images, bImages = b.kind == .images
            if aImages != bImages { return aImages }
            let ga = a.group ?? "", gb = b.group ?? ""
            if ga.isEmpty != gb.isEmpty { return !ga.isEmpty }
            if NaturalSort.less(ga, gb) { return true }
            if NaturalSort.less(gb, ga) { return false }
            if NaturalSort.less(a.name, b.name) { return true }
            if NaturalSort.less(b.name, a.name) { return false }
            return a.id < b.id
        }
    }

    private static func ext(_ name: String) -> String {
        MediaResolver.fileExtension(name)
    }
}

// MARK: - 远端正文 / 远端文件
//
// 文本：整份下载后按编码解码，结果进 NSCache（同一章反复进出不重复下载）。
// PDF：下载到 Caches/RemoteFiles，交给 PdfChapterView 按页渲染。
// 二者都只在进入章节时触发，不做目录预扫。

final class RemoteTextCache {
    static let shared = RemoteTextCache()

    private let cache = NSCache<NSString, NSString>()
    private var inFlight: [String: Task<String?, Never>] = [:]
    private let lock = NSLock()

    private init() { cache.countLimit = 12 }

    func text(for url: URL, account: WebDAVAccount) async -> String? {
        // 编码按文件记忆：用户手动指定过就照那个解，否则自动识别
        let preferred = TextEncodingStore.option(for: TextEncodingStore.bookKey(forURL: url))
        let key = url.absoluteString + "|" + preferred.rawValue
        if let hit = cache.object(forKey: key as NSString) { return hit as String }

        lock.lock()
        if let running = inFlight[key] {
            lock.unlock()
            return await running.value
        }
        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            guard let data = try? await WebDAVClient.data(url, account: account, timeout: 30),
                  let text = TextLoader.text(from: data, preferred: preferred) else { return nil }
            self.cache.setObject(text as NSString, forKey: key as NSString)
            return text
        }
        inFlight[key] = task
        lock.unlock()

        let value = await task.value
        lock.lock(); inFlight[key] = nil; lock.unlock()
        return value
    }

    /// 改了编码要把这份缓存清掉，否则重新打开还是旧结果
    func invalidate() {
        cache.removeAllObjects()
    }
}

enum RemoteFileStore {
    /// 远端文件落到本地缓存的副本（pdf 用）；同一地址第二次直接命中
    static func localCopy(of url: URL, account: WebDAVAccount) async throws -> URL {
        let folder = try cacheFolder()
        let ext = MediaResolver.fileExtension(url.lastPathComponent)
        let name = digest(url.absoluteString) + (ext.isEmpty ? "" : "." + ext)
        let target = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) { return target }
        let data = try await WebDAVClient.data(url, account: account, timeout: 120)
        try data.write(to: target, options: .atomic)
        return target
    }

    private static func cacheFolder() throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = caches.appendingPathComponent("RemoteFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func digest(_ text: String) -> String {
        let hash = SHA256.hash(data: Data(text.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
