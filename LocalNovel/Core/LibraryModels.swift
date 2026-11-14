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
    /// 内容构成画像（只采样前几章），用于自动判定分类
    let profile: BookProfile

    init(folderURL: URL, title: String, chapters: [Chapter],
         profile: BookProfile = .empty) {
        self.folderURL = folderURL
        self.title = title
        self.chapters = chapters
        self.profile = profile
    }
}

/// 书库分类：小说 / 漫画 / 整理
/// 「整理」= 原有那种图文混排的作者文件夹（正文 + 按序号插图 + 章末媒体）。
enum BookCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case novel
    case comic
    case organized

    var id: String { rawValue }

    var label: String {
        switch self {
        case .novel: return "小说"
        case .comic: return "漫画"
        case .organized: return "整理"
        }
    }

    var symbol: String {
        switch self {
        case .novel: return "text.book.closed"
        case .comic: return "photo.on.rectangle.angled"
        case .organized: return "folder"
        }
    }

    var hint: String {
        switch self {
        case .novel: return "以文字为主，几乎没有插图"
        case .comic: return "以图片为主，正文很少或没有"
        case .organized: return "图文混排：正文 + 序号插图 + 章末音视频"
        }
    }
}

/// 一本书的内容构成画像（只统计采样章节，扫描时顺带算出，不读文件内容）
struct BookProfile: Hashable {
    /// 实际探测的章节数
    let sampledChapters: Int
    /// 其中有 txt 正文的章节数
    let textChapters: Int
    /// 采样章节里的图片总数（含动图）
    let images: Int
    /// 采样章节里的视频 / 音频总数
    let videos: Int

    static let empty = BookProfile(sampledChapters: 0, textChapters: 0,
                                   images: 0, videos: 0)

    var imagesPerChapter: Double {
        guard sampledChapters > 0 else { return 0 }
        return Double(images) / Double(sampledChapters)
    }

    var textRatio: Double {
        guard sampledChapters > 0 else { return 0 }
        return Double(textChapters) / Double(sampledChapters)
    }
}

/// 自动分类规则（与 Validation/validate_core.py 里的等价实现保持一致）
enum BookCategoryRule {
    static func auto(_ profile: BookProfile) -> BookCategory {
        // 没有采到章节：不猜，归到「整理」
        guard profile.sampledChapters > 0 else { return .organized }

        // 完全没有正文：有图就是漫画，没图也归整理
        if profile.textChapters == 0 {
            return profile.images > 0 ? .comic : .organized
        }

        // 有正文但基本没图：小说
        if profile.imagesPerChapter < 1.5 { return .novel }

        // 有正文、但绝大多数章节没正文且图很多：按漫画算（图解类）
        if profile.imagesPerChapter >= 4 && profile.textRatio < 0.5 { return .comic }

        // 正文 + 插图并存：就是原来的「整理」类型
        return .organized
    }
}

/// 扫描结果
struct Library {
    let rootURL: URL
    let books: [Book]
}
