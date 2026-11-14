import Foundation

// MARK: - 书籍导入：把选中的内容复制进 App 文档目录
//
// 为什么不直接读外部目录：iOS 文件选择器返回的是 security-scoped URL，
//   * 「选中文件夹」需要用户点进去后再点右上角「打开」才会回调（点文件夹只是导航）；
//   * 「选中文件」不保证能列出它的父目录，bestRoot 反推后扫描常直接失败；
//   * 跨启动的 bookmark 在部分文件提供者上会失效，重启就没书。
// 这几条叠加，就是前几版「点了没反应 / 重启就没书」的来源。
//
// 现在：在系统给授权作用域内，把书【复制】进 App 自己的 Documents（本地小说），
// 之后与用户手动放书走完全相同的零权限扫描路径 —— 这是已验证稳定可用的路径。
// 复制完成后就是 App 自己的文件，重启仍在、不需要任何授权。

enum BookImportError: LocalizedError {
    case inaccessible(String)
    case noBookFolder
    case documentsUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .inaccessible(let s): return "无法读取所选内容：\(s)"
        case .noBookFolder: return "所选位置没有找到可导入的作者文件夹"
        case .documentsUnavailable(let s): return "无法准备 App 文档目录：\(s)"
        }
    }
}

enum BookImporter {
    struct Report {
        var imported: [String] = []
        var skipped: [String] = []
        var fileCount = 0
        var error: String?

        var isEmpty: Bool { imported.isEmpty }

        var summary: String {
            if let error { return error }
            var s = "已复制 \(imported.count) 个文件夹 / \(fileCount) 个文件："
                + imported.prefix(3).joined(separator: "、")
            if !skipped.isEmpty { s += "；跳过 \(skipped.count) 项" }
            return s
        }
    }

    /// 把选中的文件夹复制进 App 文档目录。调用方应在后台线程执行，
    /// 完成后重新扫描文档目录。不修改、不移动任何用户原始文件。
    static func importIntoDocuments(
        from source: URL,
        documents: URL,
        fileManager: FileManager = .default
    ) -> Report {
        var report = Report()
        // 授权只在复制期间需要；复制完成即为 App 自有文件
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let folders: [URL]
        do {
            folders = try bookFolders(at: source, fm: fileManager)
        } catch {
            report.error = "\(error.localizedDescription)。"
                + "请改用「选择书库目录」选中文件夹后点右上角「打开」，"
                + "或把【作者文件夹】直接放进「文件」App → 我的 iPhone → 本地小说。"
            return report
        }

        do {
            try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        } catch {
            report.error = BookImportError
                .documentsUnavailable(error.localizedDescription).localizedDescription
            return report
        }

        for folder in folders {
            let name = folder.lastPathComponent
            let dest = documents.appendingPathComponent(name)
            do {
                try replaceCopy(from: folder, to: dest, in: documents, fm: fileManager)
                report.imported.append(name)
                report.fileCount += countFiles(at: dest, fm: fileManager)
            } catch {
                report.skipped.append("\(name)（\(error.localizedDescription)）")
            }
        }
        return report
    }

    /// 决定要复制到 Documents 顶层的文件夹：
    /// · 书库根（作者文件夹 → 章节文件夹）→ 复制每个作者文件夹（不多包一层，避免章节错乱）
    /// · 单个作者文件夹 / 章节文件夹 → 整体复制
    private static func bookFolders(at url: URL, fm: FileManager) throws -> [URL] {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw BookImportError.inaccessible("项目不存在或已被移动")
        }
        guard isDir.boolValue else { throw BookImportError.noBookFolder }

        let children = try visibleItems(at: url, fm: fm)
        let dirs = children.filter { isDirectory($0, fm: fm) }
        if dirs.isEmpty {
            // 章节文件夹（里面直接是 txt / 图片 / 音视频）：整体作为一本单章书
            return [url]
        }
        let nested = (try? visibleItems(at: dirs[0], fm: fm)) ?? []
        let nestedHasDirs = nested.contains { isDirectory($0, fm: fm) }
        if nestedHasDirs {
            return dirs  // 标准书库根
        }
        return [url]      // 单个作者文件夹
    }

    /// 同名目标整体替换；先移走旧副本，复制成功再删，失败回滚，绝不留下半本书
    private static func replaceCopy(from src: URL, to dest: URL, in docs: URL,
                                    fm: FileManager) throws {
        if !fm.fileExists(atPath: dest.path) {
            try fm.copyItem(at: src, to: dest)
            return
        }
        let backup = docs.appendingPathComponent(".ln-backup-\(UUID().uuidString)")
        try fm.moveItem(at: dest, to: backup)
        do {
            try fm.copyItem(at: src, to: dest)
            try? fm.removeItem(at: backup)
        } catch {
            try? fm.removeItem(at: dest)
            try? fm.moveItem(at: backup, to: dest)
            throw error
        }
    }

    private static func visibleItems(at url: URL, fm: FileManager) throws -> [URL] {
        let items = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return items.filter { !MediaResolver.isHidden($0.lastPathComponent) }
    }

    private static func isDirectory(_ url: URL, fm: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    private static func countFiles(at url: URL, fm: FileManager) -> Int {
        guard let e = fm.enumerator(at: url,
                                    includingPropertiesForKeys: [.isRegularFileKey],
                                    options: [.skipsHiddenFiles]) else { return 0 }
        var n = 0
        while let u = e.nextObject() as? URL {
            if (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                n += 1
            }
        }
        return n
    }
}
