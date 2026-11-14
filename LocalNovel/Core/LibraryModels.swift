import Foundation

// MARK: - 数据模型（纯值类型，不依赖任何 UI 框架）

enum MediaKind: String, Codable {
    case text
    case image
    case animatedImage
    case video
    case audio
}

/// 章节内的一个媒体文件
struct MediaItem: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let fileName: String
    let kind: MediaKind
    /// 图片序号（从 1 开始）；无序号命名的文件为 nil
    let sequence: Int?
    /// 是否为动图（GIF / APNG 多帧）
    let isAnimated: Bool

    init(url: URL, kind: MediaKind, sequence: Int?, isAnimated: Bool = false) {
        self.url = url
        self.fileName = url.lastPathComponent
        self.kind = kind
        self.sequence = sequence
        self.isAnimated = isAnimated
    }
}

/// 章节 = 章节名文件夹
struct Chapter: Identifiable, Hashable {
    var id: String { folderURL.path }
    let folderURL: URL
    /// 文件夹原名，用于排序
    let rawName: String
    /// 展示标题（可选去掉序号前缀）
    let title: String
}

/// 一章解析后的内容：正文 → 图片（序号）→ 章末音视频
struct ChapterContent {
    let chapter: Chapter
    /// 每章只有一个 txt；nil 表示该章缺正文
    let textURL: URL?
    /// 按序号自然排序后的图片（含动图）
    let images: [MediaItem]
    /// 视频 / 音频，最多一个，也可能为空；按数组渲染以兼容更多情况
    let avMedia: [MediaItem]
    /// 扫描时被忽略的文件（用于调试提示，不参与渲染）
    let ignoredFiles: [String]

    var hasAVMedia: Bool { !avMedia.isEmpty }
}

/// 书 = 作者名文件夹
struct Book: Identifiable, Hashable {
    var id: String { folderURL.path }
    let folderURL: URL
    /// 作者名即书名
    let title: String
    let chapters: [Chapter]
}

/// 扫描结果
struct Library {
    let rootURL: URL
    let books: [Book]
}
