import Foundation

/// 三类书库的分层扫描：输入 LNNode 树，输出 LNBook/LNChapter。
/// 本地与 NAS 共用同一套规则，因此两边列表显示完全一致。
/// 参照 LocalNovel BookSections.swift 的 ComicScanner / OrganizedScanner / ShortDramaScanner。
enum LNScanner {

    // MARK: - 文件类型（参照 MediaResolver）

    static func ext(_ name: String) -> String {
        (name as NSString).pathExtension.lowercased()
    }

    static let textExts: Set<String> = ["txt", "text", "md", "markdown"]
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif", "apng"]
    static let pdfExt = "pdf"
    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "ts", "rmvb", "rm", "3gp", "mpg", "mpeg"]
    static let audioExts: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf", "ogg", "opus"]
    static let animatedExts: Set<String> = ["gif", "apng"]

    static func isText(_ n: LNNode) -> Bool { !n.isDirectory && textExts.contains(ext(n.name)) }
    static func isImage(_ n: LNNode) -> Bool { !n.isDirectory && imageExts.contains(ext(n.name)) }
    static func isPDF(_ n: LNNode) -> Bool { !n.isDirectory && ext(n.name) == pdfExt }
    static func isVideo(_ n: LNNode) -> Bool { !n.isDirectory && videoExts.contains(ext(n.name)) }
    static func isAudio(_ n: LNNode) -> Bool { !n.isDirectory && audioExts.contains(ext(n.name)) }

    /// 图片序号（1.jpg / 02.png / ３.gif），非纯数字返回 nil
    static func sequence(_ name: String) -> Int? {
        var stem = (name as NSString).deletingPathExtension
        // 全角数字 → 半角（CFStringTransform 的 Swift 6 安全写法）
        let cf = NSMutableString(string: stem)
        CFStringTransform(cf, nil, kCFStringTransformFullwidthHalfwidth, false)
        stem = cf as String
        guard !stem.isEmpty, stem.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(stem)
    }

    // MARK: - 扫书：根目录下每个子目录 = 一本书

    static func books(in nodes: [LNNode], category: LNCategory,
                      loadChildren: @Sendable (LNNode) async throws -> [LNNode]) async throws -> [LNBook] {
        var result: [LNBook] = []
        for folder in nodes.filter({ $0.isDirectory }) {
            let children = try await loadChildren(folder)
            let chapters: [LNChapter]
            switch category {
            case .comic:
                chapters = try await comicChapters(in: folder, nodes: children,
                                                   loadChildren: loadChildren)
            case .organized:
                chapters = try await organizedChapters(in: folder, nodes: children,
                                                       loadChildren: loadChildren)
            case .shortDrama:
                chapters = try await dramaChapters(in: folder, nodes: children,
                                                   loadChildren: loadChildren)
            }
            guard !chapters.isEmpty else { continue }
            result.append(LNBook(path: folder.path, title: folder.name,
                                  category: category, chapters: chapters))
        }
        return result
    }

    // MARK: 整理：书 → 子目录 = 章；平铺文件 = 单章

    private static func organizedChapters(in folder: LNNode, nodes: [LNNode],
                                          loadChildren: @Sendable (LNNode) async throws -> [LNNode]) async throws -> [LNChapter] {
        let dirs = nodes.filter { $0.isDirectory }
        if !dirs.isEmpty {
            return dirs.map { LNChapter(path: $0.path, name: $0.name, kind: .folder, groupName: nil) }
        }
        // 目录里平铺了多个电子书文件：每本一章
        let texts = nodes.filter { isText($0) }
        if texts.count > 1 {
            return LNNaturalSort.sorted(texts) { $0.name }.map {
                LNChapter(path: $0.path,
                          name: ($0.name as NSString).deletingPathExtension,
                          kind: .text, groupName: nil)
            }
        }
        let hasMedia = nodes.contains { isText($0) || isImage($0) || isVideo($0) || isAudio($0) || isPDF($0) }
        guard hasMedia else { return [] }
        return [LNChapter(path: folder.path, name: folder.name, kind: .folder, groupName: nil)]
    }

    // MARK: 漫画：有图片=一话；有 pdf=每 pdf 一话；否则下钻，depth<=4

    private static func comicChapters(in folder: LNNode, nodes: [LNNode],
                                      loadChildren: @Sendable (LNNode) async throws -> [LNNode]) async throws -> [LNChapter] {
        try await mediaChapters(in: folder, nodes: nodes, loadChildren: loadChildren,
                                 maxDepth: 4, pdfEnabled: true, videoEnabled: false,
                                 imageLabel: nil)
    }

    // MARK: 短剧：图片包=剧照；视频=每集；depth<=3

    private static func dramaChapters(in folder: LNNode, nodes: [LNNode],
                                      loadChildren: @Sendable (LNNode) async throws -> [LNNode]) async throws -> [LNChapter] {
        try await mediaChapters(in: folder, nodes: nodes, loadChildren: loadChildren,
                                 maxDepth: 3, pdfEnabled: false, videoEnabled: true,
                                 imageLabel: "剧照")
    }

    private static func mediaChapters(in folder: LNNode, nodes: [LNNode],
                                      loadChildren: @Sendable (LNNode) async throws -> [LNNode],
                                      maxDepth: Int, pdfEnabled: Bool, videoEnabled: Bool,
                                      imageLabel: String?) async throws -> [LNChapter] {
        var result: [LNChapter] = []
        let files = nodes.filter { !$0.isDirectory }
        let images = files.filter { isImage($0) }
        if !images.isEmpty {
            result.append(LNChapter(path: folder.path,
                                    name: imageLabel ?? folder.name,
                                    kind: .images, groupName: nil))
        }
        if pdfEnabled {
            for pdf in files.filter({ isPDF($0) }) {
                result.append(LNChapter(path: pdf.path,
                                        name: (pdf.name as NSString).deletingPathExtension,
                                        kind: .pdf, groupName: nil))
            }
        }
        if videoEnabled {
            for video in files.filter({ isVideo($0) }) {
                result.append(LNChapter(path: video.path,
                                        name: (video.name as NSString).deletingPathExtension,
                                        kind: .video, groupName: nil))
            }
            for audio in files.filter({ isAudio($0) }) {
                result.append(LNChapter(path: audio.path,
                                        name: (audio.name as NSString).deletingPathExtension,
                                        kind: .audio, groupName: nil))
            }
        }
        let depth = folder.path.split(separator: "/").count
        guard depth < maxDepth else { return sortChapters(result) }
        for sub in nodes.filter({ $0.isDirectory }) {
            let children = try await loadChildren(sub)
            result += try await mediaChapters(in: sub, nodes: children,
                                              loadChildren: loadChildren,
                                              maxDepth: maxDepth, pdfEnabled: pdfEnabled,
                                              videoEnabled: videoEnabled,
                                              imageLabel: imageLabel)
        }
        return sortChapters(result)
    }

    private static func sortChapters(_ chapters: [LNChapter]) -> [LNChapter] {
        LNNaturalSort.sorted(chapters) { $0.displayName }
    }
}
