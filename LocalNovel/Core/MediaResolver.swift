import Foundation

// MARK: - 媒体识别与章节内容装配
// 整理 / 漫画的图片章节：1 个 txt + N 张按序号命名的图片（含动图）+ 0/1 个音视频
// 渲染顺序固定：正文 → 图片（序号）→ 章末音视频。
// 小说单文件：整本一节，正文由 LibraryStore 按区间切（见 ChapterKind.slice）。

enum MediaResolver {

    static let textExtensions: Set<String>   = ["txt", "text", "md", "markdown"]
    static let imageExtensions: Set<String>  = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif", "apng"]
    /// AVPlayer 能直接解码的容器
    static let videoExtensions: Set<String>  = ["mp4", "mov", "m4v"]
    /// 识别用宽集合：短剧 / 整理里常见的其它容器也算「视频集」，
    /// 不再被当成正文去读（此前 mp4 以外的文件会显示「不支持的格式」）。
    /// 播放不了时由播放器给出「建议转成 mp4」的提示，而不是伪装成文本错误。
    static let looseVideoExtensions: Set<String> = videoExtensions.union([
        "avi", "mkv", "wmv", "flv", "webm", "ts", "m2ts", "mts",
        "rmvb", "rm", "3gp", "mpg", "mpeg", "vob", "ogv", "asf", "divx",
    ])
    static let audioExtensions: Set<String>  = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf", "ogg", "opus"]

    /// 宽松判定：短剧的「一集」、整理的章末视频都按这个识别
    static func isVideoFile(_ url: URL) -> Bool {
        looseVideoExtensions.contains(fileExtension(url.lastPathComponent))
    }

    static func isAudioFile(_ url: URL) -> Bool {
        audioExtensions.contains(fileExtension(url.lastPathComponent))
    }
    static let animatedExtensions: Set<String> = ["gif", "apng"]

    /// 漫画单话 / 小说整本都可能是 pdf
    static let pdfExtension = "pdf"
    static let epubExtension = "epub"

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
        if looseVideoExtensions.contains(e) { return .video }
        if audioExtensions.contains(e)  { return .audio }
        return nil
    }

    static func isImageFile(_ url: URL) -> Bool {
        imageExtensions.contains(fileExtension(url.lastPathComponent))
    }

    static func isPDF(_ url: URL) -> Bool {
        fileExtension(url.lastPathComponent) == pdfExtension
    }

    static func isEpub(_ url: URL) -> Bool {
        fileExtension(url.lastPathComponent) == epubExtension
    }

    static func isPlainText(_ url: URL) -> Bool {
        textExtensions.contains(fileExtension(url.lastPathComponent))
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

    /// 单文件章节按扩展名分流。
    ///
    /// 这里曾是「短剧显示不支持的格式」的根因：所有非 pdf 的单文件都被当成正文，
    /// 于是 mp4 被交给 TextLoader，最终抛出 unsupported("mp4") 显示成一行红字。
    /// 现在图片 / 视频 / 音频各自归位，只有真正的文档才走文本读取。
    private static func resolveSingleFile(
        _ chapter: Chapter,
        animatedDetector: (URL) -> Bool
    ) -> ChapterContent {
        let url = chapter.folderURL
        let ext = fileExtension(url.lastPathComponent)

        if ext == pdfExtension {
            return ChapterContent(chapter: chapter, textURL: nil, images: [], avMedia: [],
                                  ignoredFiles: [], pdfURL: url)
        }
        if imageExtensions.contains(ext) {
            let animated = animatedDetector(url)
            let item = MediaItem(url: url,
                                 kind: animated ? .animatedImage : .image,
                                 sequence: imageSequence(url.lastPathComponent),
                                 isAnimated: animated)
            return ChapterContent(chapter: chapter, textURL: nil, images: [item], avMedia: [],
                                  ignoredFiles: [], pdfURL: nil)
        }
        if looseVideoExtensions.contains(ext) {
            return ChapterContent(chapter: chapter, textURL: nil, images: [],
                                  avMedia: [MediaItem(url: url, kind: .video, sequence: nil)],
                                  ignoredFiles: [], pdfURL: nil)
        }
        if audioExtensions.contains(ext) {
            return ChapterContent(chapter: chapter, textURL: nil, images: [],
                                  avMedia: [MediaItem(url: url, kind: .audio, sequence: nil)],
                                  ignoredFiles: [], pdfURL: nil)
        }
        // txt / md / epub 以及其它未知文档类型：交给 TextLoader 报明确错误
        return ChapterContent(chapter: chapter, textURL: url, images: [], avMedia: [],
                              ignoredFiles: [], pdfURL: nil)
    }

    /// 装配一章内容
    /// - Parameters:
    ///   - chapter: 章节（文件夹 / 单文件 / 小说整本切片）
    ///   - animatedDetector: 动图判定闭包（可注入，便于测试）
    static func resolveChapter(
        _ chapter: Chapter,
        animatedDetector: (URL) -> Bool = defaultAnimatedDetector,
        fileManager: FileManager = .default
    ) -> ChapterContent {
        let folder = chapter.folderURL

        // 单文件章节 / 小说切片：不再列目录
        if chapter.kind != .folder {
            return resolveSingleFile(chapter, animatedDetector: animatedDetector)
        }

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
        var pdfURL: URL?

        for name in names where !isHidden(name) {
            let url = folder.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue } // 忽略子文件夹

            // 章节目录里混入 pdf：当作该章的整章文档
            if isPDF(url) {
                if pdfURL == nil { pdfURL = url } else { ignored.append(name) }
                continue
            }

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
            ignoredFiles: ignored,
            pdfURL: pdfURL
        )
    }
}
