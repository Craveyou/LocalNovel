import Foundation

// MARK: - 让 App 文档目录在「文件」App 里真正可见
//
// Apple DTS 明确给出三个必要条件（见 developer.apple.com/forums/thread/765329）：
//   1) LSSupportsOpeningDocumentsInPlace = true
//   2) UIFileSharingEnabled = true
//   3) Documents 目录里【至少有一个文件】
// 之前只创建了空目录，缺第 3 条，所以「我的 iPhone」里找不到「本地小说」。
// 这里在启动时写一份说明文件（幂等），并把文件名登记进 MediaResolver.isHidden，
// 保证它不会被扫描器误当成一章正文。全程本地、无联网、无权限申请。

enum DocumentsBootstrap {
    /// 说明文件名。改名时需同步更新校验脚本里的检查项。
    static let guideFileName = "放书说明.txt"

    static let guideText = """
    把书放进这个文件夹，回到「本地小说」就会自动出现。

    目录结构：
      作者名文件夹（= 一本书）
        └─ 章节名文件夹（= 一章）
             ├─ 正文.txt
             ├─ 1.jpg / 2.png / 3.gif …（按序号命名的图片，含动图）
             └─ 视频或音频（可选，每章最多一个）

    注意：放进来的是【作者文件夹】本身，不要再多包一层文件夹。

    如果「文件」App 的「我的 iPhone」里看不到本目录：
      · 在「文件」App 顶部搜索框输入「本地小说」即可搜到；
      · 或直接用本 App 的「＋ → 选择书库目录 / 选择书库内任意文件」导入。

    本文件可以删除，App 下次启动会重新生成。
    """

    /// 创建 Documents 目录并写入说明文件；任何失败都不阻断 App 启动。
    @discardableResult
    static func ensureVisibleInFilesApp(fileManager: FileManager = .default) -> URL? {
        guard let docs = try? fileManager.url(for: .documentDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: nil,
                                              create: true) else { return nil }
        try? fileManager.createDirectory(at: docs, withIntermediateDirectories: true)
        let guide = docs.appendingPathComponent(guideFileName)
        if !fileManager.fileExists(atPath: guide.path) {
            try? guideText.write(to: guide, atomically: true, encoding: .utf8)
        }
        return docs
    }
}
