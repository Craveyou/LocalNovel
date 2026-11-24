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

/// 章节的三种来源
enum ChapterKind: String, Codable {
    /// 章节目录：正文.txt + 按序号图片 + 章末音视频（整理 / 漫画）
    case folder
    /// 单文件章节：一章就是一个 pdf / txt / epub（漫画单话、小说整本）
    case file
    /// 单文件小说里切出来的一段（虚拟章节，不占磁盘）
    case slice
}

/// 章节
struct Chapter: Identifiable, Hashable {
    /// 章节目录 / 单文件 / 小说源文件（slice 时指向整本文件）
    let folderURL: URL
    /// 原名，用于排序
    let rawName: String
    /// 展示标题
    let title: String
    let kind: ChapterKind
    /// 卷名（漫画的「第1部」这类中间层），无则为 nil
    let groupName: String?
    /// slice 章节在整本正文里的区间（UTF-16 偏移，与 NSString 一致）
    let range: NSRange?

    init(folderURL: URL,
         rawName: String,
         title: String,
         kind: ChapterKind = .folder,
         groupName: String? = nil,
         range: NSRange? = nil) {
        self.folderURL = folderURL
        self.rawName = rawName
        self.title = title
        self.kind = kind
        self.groupName = groupName
        self.range = range
    }

    /// 同一个整本文件会切出多个 slice，必须带区间偏移才能唯一
    var id: String {
        if let range { return "\(folderURL.path)#\(range.location)" }
        return folderURL.path
    }

    /// 列表里的完整标题：有卷名时显示「卷名 · 章名」
    var displayTitle: String {
        guard let groupName, !groupName.isEmpty, groupName != title else { return title }
        return "\(groupName) · \(title)"
    }

    /// 能否删除源文件：slice 属于整本文件，只能隐藏，不能单独删
    var canDeleteFromDisk: Bool { kind != .slice }

    /// 切章前的占位章：整本小说只挂一个 slice，range 为 nil。
    /// 目录弹层里要过滤掉它（否则会看到一条和书名重复的「章」），
    /// 切章完成后它会被一系列带 range 的真实 slice 替换。
    var isPlaceholder: Bool { kind == .slice && range == nil }
}

/// 一章解析后的内容：正文 → 图片（序号）→ 章末音视频
struct ChapterContent {
    let chapter: Chapter
    /// 每章只有一个正文文件；nil 表示该章缺正文
    let textURL: URL?
    /// 按序号自然排序后的图片（含动图）
    let images: [MediaItem]
    /// 视频 / 音频，最多一个，也可能为空；按数组渲染以兼容更多情况
    let avMedia: [MediaItem]
    /// 扫描时被忽略的文件（用于调试提示，不参与渲染）
    let ignoredFiles: [String]
    /// 漫画 pdf 章节：按页渲染，不抽文本
    let pdfURL: URL?

    var hasAVMedia: Bool { !avMedia.isEmpty }
    var isPdfChapter: Bool { pdfURL != nil }
}

/// 书库分区：目录名就是唯一依据，不再靠内容猜
enum BookCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case novel
    case comic
    case organized
    case shortDrama

    var id: String { rawValue }

    var label: String {
        switch self {
        case .novel: return "小说"
        case .comic: return "漫画"
        case .organized: return "整理"
        case .shortDrama: return "短剧"
        }
    }

    /// 该分类在文档目录下的文件夹名
    var folderName: String { label }

    var symbol: String {
        switch self {
        case .novel: return "text.book.closed"
        case .comic: return "photo.on.rectangle.angled"
        case .organized: return "folder"
        case .shortDrama: return "play.rectangle.on.rectangle"
        }
    }

    var hint: String {
        switch self {
        case .novel: return "每本一个文件；一个文件夹 = 一个系列"
        case .comic: return "每部一个文件夹，按「部 → 话」分层，图片或 pdf；也能按格式包分（PDF 包 / 图片包）"
        case .organized: return "作者文件夹 → 章节文件夹 → 正文 + 插图 + 音视频"
        case .shortDrama: return "剧名文件夹：一个剧照包 + 一个视频包（也可只有视频）"
        }
    }

    /// 目录结构示例（用于空态与说明文件）
    var structureExample: String {
        switch self {
        case .novel:
            return "小说/书名.txt（也支持 .md / .epub / .pdf）\n小说/系列名/第1部.txt（文件夹 = 系列）"
        case .comic:
            return "漫画/漫画名/第1部/第1话/001.jpg\n漫画/漫画名/第5话.pdf\n漫画/漫画名/PDF包/第01话.pdf + 图片包/第01话/001.jpg"
        case .organized:
            return "整理/作者名/第01章/正文.txt + 1.jpg"
        case .shortDrama:
            return "短剧/剧名/剧照/001.jpg\n短剧/剧名/视频/第01集.mp4"
        }
    }
}

/// 一本书
struct Book: Identifiable, Hashable {
    var id: String { folderURL.path }
    /// 书目录；单文件小说时为该文件本身
    let folderURL: URL
    let title: String
    /// 由所在分区决定，不再推断
    let category: BookCategory
    let chapters: [Chapter]
    /// 小说单文件：章节还没切（首次打开时才解析正文），先给一章占位
    let chaptersDeferred: Bool
    /// 所属系列（小说分区里的中间文件夹），nil = 直接放在分区根目录。
    /// 「系列 / 子系列」用 " · " 连接，列表里显示成一行。
    let series: String?

    init(folderURL: URL, title: String,
         category: BookCategory = .organized,
         chapters: [Chapter],
         chaptersDeferred: Bool = false,
         series: String? = nil) {
        self.folderURL = folderURL
        self.title = title
        self.category = category
        self.chapters = chapters
        self.chaptersDeferred = chaptersDeferred
        self.series = series
    }
}

/// 扫描结果
struct Library {
    let rootURL: URL
    let books: [Book]

    func books(in category: BookCategory) -> [Book] {
        books.filter { $0.category == category }
    }

    func count(in category: BookCategory) -> Int {
        books.lazy.filter { $0.category == category }.count
    }

    /// 该分区下出现过的系列名（自然排序）；没有系列时为空
    func seriesNames(in category: BookCategory) -> [String] {
        let names = Set(books.filter { $0.category == category }.compactMap { $0.series })
        return NaturalSort.sorted(Array(names)) { $0 }
    }

    /// series == nil 时取「直接放在分区根目录」的书
    func books(in category: BookCategory, series: String?) -> [Book] {
        books.filter { $0.category == category && $0.series == series }
    }

    func count(in category: BookCategory, series: String?) -> Int {
        books.lazy.filter { $0.category == category && $0.series == series }.count
    }
}
