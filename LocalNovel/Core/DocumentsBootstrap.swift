import Foundation

// MARK: - 让 App 文档目录在「文件」App 里真正可见
//
// Apple DTS 明确给出三个必要条件（见 developer.apple.com/forums/thread/765329）：
//   1) LSSupportsOpeningDocumentsInPlace = true
//   2) UIFileSharingEnabled = true
//   3) Documents 目录里【至少有一个文件】
// 启动时会写一份说明文件（幂等），并把文件名登记进 MediaResolver.isHidden，
// 保证它不会被扫描器误当成一章正文。
//
// 同时建好 小说 / 漫画 / 整理 三个文件夹：用户打开「文件」App 就能直接往里放书，
// 不必自己猜目录名。全程本地、无联网、无权限申请。

enum DocumentsBootstrap {
    /// 说明文件名。改名时需同步更新校验脚本里的检查项。
    static let guideFileName = "放书说明.txt"

    static let guideText = """
    把书放进三个文件夹，回到「本地小说」就会自动出现。

    小说/    每个文件就是一本
             书名.txt / 书名.md / 书名.epub / 书名.pdf
             文件夹 = 一个系列：系列名/第1部.txt 第2部.txt
             打开时按「第X章 / Chapter N / 序章 / 番外」自动分章。

    漫画/    每部漫画一个文件夹，文件夹名就是漫画名
             漫画名/第1部/第1话/001.jpg 002.jpg …
             漫画名/第2话/001.jpg …          （没有「部」也可以）
             漫画名/第5话.pdf                （一个 pdf = 一话）
             漫画名/单行本/第3话/…            （中间层显示为卷名）
             漫画名/PDF包/第01话.pdf …        （同一部书按格式分成两个包）
             漫画名/图片包/第01话/001.jpg …

             识别规则：
               · 漫画名文件夹 = 一部，列表里的一本
               · 中间文件夹 = 卷名，多层用「 · 」连接
               · 直接放着图片的文件夹 = 一话
               · 目录下的每个 pdf = 一话，按页渲染
               · 格式包（PDF包 / 图片包）= 章节列表里的一段，包下再列该包的章节
               · 漫画名层直接放散图 = 整部一话
               · 图片支持 jpg / png / webp / heic / bmp / tiff / gif
               · 排序按自然序：第2话 在第10话 前面

    整理/    原来那种图文混排结构
             作者名/章节名/正文.txt + 1.jpg 2.png … + 视频或音频

    说明：
      · 分类只看文件夹：放在哪个文件夹就是哪一类，不用在 App 里再改。
      · 小说区的子文件夹会显示为「系列」，点进去看该系列的书。
      · 漫画满宽连排、支持超长条漫，点一下可全屏；pdf 单话按页显示。
      · 小说默认左右翻页（设置里可改成上下滚动）；「整理」和「漫画」始终上下滚动。
      · 小说支持 txt / md / epub / pdf；epub 只取文字（不含内嵌样式与插图）。
      · 「设置 → 结构说明」里有同样的规则，图文对照更清楚。

    如果「文件」App 的「我的 iPhone」里看不到本目录：
      · 在「文件」App 顶部搜索框输入「本地小说」即可搜到；
      · 或直接用本 App 的「＋ → 导入书籍文件 / 文件夹」。

    本文件可以删除，App 下次启动会重新生成。
    """

    /// 创建 Documents 与三个分区目录，并写入说明文件；任何失败都不阻断 App 启动。
    @discardableResult
    static func ensureVisibleInFilesApp(fileManager: FileManager = .default) -> URL? {
        guard let docs = try? fileManager.url(for: .documentDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: nil,
                                              create: true) else { return nil }
        try? fileManager.createDirectory(at: docs, withIntermediateDirectories: true)

        for section in LibrarySection.allCases {
            let dir = docs.appendingPathComponent(section.folderName)
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }

        let guide = docs.appendingPathComponent(guideFileName)
        if !fileManager.fileExists(atPath: guide.path) {
            try? guideText.write(to: guide, atomically: true, encoding: .utf8)
        }
        return docs
    }
}
