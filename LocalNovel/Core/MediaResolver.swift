import Foundation

// MARK: - 媒体识别与章节内容装配
// 约定：章节文件夹内 = 1 个 txt + N 张按序号命名的图片（含动图）+ 0/1 个音视频文件。
// 渲染顺序固定：正文 → 图片（序号）→ 章末音视频。

enum MediaResolver {

    static let textExtensions: Set<String>   = ["txt", "text", "md"]
    static let imageExtensions: Set<String>  = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif", "apng"]
    static let videoExtensions: Set<String>  = ["mp4", "mov", "m4v"]
    static let audioExtensions: Set<String>  = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf"]
    static let animatedExtensions: Set<String> = ["gif", "apng"]

    static func fileExtension(_ name: String) -> String {
        (name as NSString).pathExtension.lowercased()
    }

    static func stem(_ name: String) -> String {
        (name as NSString).deletingPathExtension
    }

    static func isHidden(_ name: String) -> Bool {
        if name.hasPrefix(".") || name == "Thumbs.db" || name == "desktop.ini" { return true }
        // App 启动写入的说明文件：只用于让「文件」App 显示文档目录，不属于书库内容
        return name == DocumentsBootstrap.guideFileName
    }

    /// 按扩展名分类；返回 nil 表示不认识的文件
    static func classify(_ name: String) -> MediaKind? {
        let e = fileExtension(name)
        if textExtensions.contains(e)  { return .text }
        if imageExtensions.contains(e)  { return .image }
        if videoExtensions.contains(e)  { return .video }
        if audioExtensions.contains(e)  { return .audio }
        return nil
    }

    /// 解析「1.jpg」「02.png」「３.gif」这类序号；非纯数字文件名返回 nil
    static func imageSequence(_ name: String) -> Int? {
        let s = NaturalSort.normalize(stem(name))
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(s)
    }

    /// 默认动图判定：按扩展名。Media 层会注入基于 ImageIO 帧数的精确判定。
    static func defaultAnimatedDetector(_ url: URL) -> Bool {
        animatedExtensions.contains(fileExtension(url.lastPathComponent))
    }

    /// 装配一章内容
    /// - Parameters:
    ///   - chapter: 章节（文件夹）
    ///   - animatedDetector: 动图判定闭包（可注入，便于测试）
    static func resolveChapter(
        _ chapter: Chapter,
        animatedDetector: (URL) -> Bool = defaultAnimatedDetector,
        fileManager: FileManager = .default
    ) -> ChapterContent {
        let folder = chapter.folderURL
        let names: [String]
        if let list = try? fileManager.contentsOfDirectory(atPath: folder.path) {
            names = list
        } else {
            names = []
        }

        var texts: [URL] = []
        var images: [MediaItem] = []
        var av: [MediaItem] = []
        var ignored: [String] = []

        for name in names where !isHidden(name) {
            let url = folder.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue } // 忽略子文件夹

            guard let kind = classify(name) else {
                ignored.append(name)
                continue
            }

            switch kind {
            case .text:
                texts.append(url)
            case .image:
                let animated = animatedDetector(url)
                let itemKind: MediaKind = animated ? .animatedImage : .image
                images.append(MediaItem(url: url, kind: itemKind,
                                        sequence: imageSequence(name), isAnimated: animated))
            case .video, .audio:
                av.append(MediaItem(url: url, kind: kind, sequence: nil))
            case .animatedImage:
                images.append(MediaItem(url: url, kind: .animatedImage,
                                        sequence: imageSequence(name), isAnimated: true))
            }
        }

        // 正文：每章约定只有一个；多出时取自然序第一个，其余忽略并提示
        let sortedTexts = texts.sorted { NaturalSort.less($0.lastPathComponent, $1.lastPathComponent) }
        let textURL = sortedTexts.first
        if sortedTexts.count > 1 {
            ignored.append(contentsOf: sortedTexts.dropFirst().map { $0.lastPathComponent })
        }

        // 图片：有序号的按数值升序；无序号的排在其后按文件名排序
        let withSeq = images.filter { $0.sequence != nil }
        let withoutSeq = images.filter { $0.sequence == nil }
        let sortedWithSeq = withSeq.sorted {
            if $0.sequence! != $1.sequence! { return $0.sequence! < $1.sequence! }
            return NaturalSort.less($0.fileName, $1.fileName)
        }
        let sortedWithoutSeq = withoutSeq.sorted { NaturalSort.less($0.fileName, $1.fileName) }

        return ChapterContent(
            chapter: chapter,
            textURL: textURL,
            images: sortedWithSeq + sortedWithoutSeq,
            avMedia: av.sorted { NaturalSort.less($0.fileName, $1.fileName) },
            ignoredFiles: ignored
        )
    }
}
