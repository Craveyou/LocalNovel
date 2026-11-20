import Foundation

// MARK: - 书籍导入：把选中的内容复制进 App 文档目录的对应分区
//
// 为什么不直接读外部目录：iOS 文件选择器返回的是 security-scoped URL，
//   * 「选中文件夹」需要用户点进去后再点右上角「打开」才会回调（点文件夹只是导航）；
//   * 「选中文件」不保证能列出它的父目录；
//   * 跨启动的 bookmark 在部分文件提供者上会失效。
// 这几条叠加，就是前几版「点了没反应 / 重启就没书」的来源。
//
// 现在：在系统给授权作用域内复制进 小说 / 漫画 / 整理 之一，之后与用户手动放书
// 走完全相同的零权限扫描路径。复制完成后就是 App 自己的文件，重启仍在。

enum BookImportError: LocalizedError {
    case inaccessible(String)
    case nothingToImport
    case documentsUnavailable(String)
    /// 覆盖同名书失败，且旧副本没能自动挪回原位（备份路径一并带出，别静默丢书）
    case rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .inaccessible(let s): return "无法读取所选内容：\(s)"
        case .nothingToImport: return "所选位置没有找到可导入的书"
        case .documentsUnavailable(let s): return "无法准备 App 文档目录：\(s)"
        case .rollbackFailed(let backup):
            return "覆盖导入失败，且原书没能自动还原。原书备份仍在：\(backup)"
        }
    }
}

enum BookImporter {
    struct Report {
        var imported: [String] = []
        var skipped: [String] = []
        /// 因本批内重名而自动改名的条目（原名 → 新名）
        var renamed: [String] = []
        var fileCount = 0
        var target: BookCategory?
        var error: String?

        var isEmpty: Bool { imported.isEmpty }

        var summary: String {
            if let error { return error }
            var s = "已复制 \(imported.count) 项 / \(fileCount) 个文件到「\(target?.label ?? "书库")」："
                + imported.prefix(3).joined(separator: "、")
            if !skipped.isEmpty { s += "；跳过 \(skipped.count) 项" }
            if !renamed.isEmpty { s += "；\(renamed.count) 项重名已自动改名" }
            return s
        }
    }

    /// 把选中的内容复制进 App 文档目录。调用方应在后台线程执行。
    /// - Parameters:
    ///   - preferred: 用户当前所在分区；nil 时按内容自动判断。
    ///   - preferredSeries: 用户当前所在系列；复制进「分区/系列/」而不是分区根目录。
    static func importIntoDocuments(
        from source: URL,
        documents: URL,
        preferred: BookCategory? = nil,
        preferredSeries: String? = nil,
        fileManager: FileManager = .default
    ) -> Report {
        var report = Report()
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let isDir = isDirectory(source, fm: fileManager)
        let category = preferred ?? suggestedSection(for: source, isDirectory: isDir, fm: fileManager)
        report.target = category

        let items: [URL]
        do {
            items = try importItems(at: source, category: category,
                                    isDirectory: isDir, fm: fileManager)
        } catch {
            report.error = "\(error.localizedDescription)。"
                + "请改用「导入书籍文件夹」选中文件夹后点右上角「打开」，"
                + "或把书直接放进「文件」App → 我的 iPhone → 本地小说 的对应分区。"
            return report
        }
        guard !items.isEmpty else {
            report.error = BookImportError.nothingToImport.localizedDescription
                + "（「\(category.label)」分区需要\(category == .novel ? " txt / md / epub / pdf 文件" : "对应的文件夹结构")）"
            return report
        }

        var targetDir = documents.appendingPathComponent(category.folderName)
        if let series = preferredSeries, !series.isEmpty {
            for part in series.components(separatedBy: " · ") where !part.isEmpty {
                targetDir.appendPathComponent(part)
            }
        }
        do {
            try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
        } catch {
            report.error = BookImportError
                .documentsUnavailable(error.localizedDescription).localizedDescription
            return report
        }

        // 小说文件夹是「递归拍平」导入的：多级目录里的同名文件（上册/第1章.txt、
        // 下册/第1章.txt）会撞到同一个目标名。原来后一个直接覆盖前一个，
        // 盘上只剩一本但提示「已复制 N 项」—— 等于静默丢书。这里在本批内自动改名。
        var usedNames: Set<String> = []
        for item in items {
            var name = item.lastPathComponent
            if usedNames.contains(name) {
                let renamed = uniqueName(for: name, used: usedNames, in: targetDir, fm: fileManager)
                report.renamed.append("\(name) → \(renamed)")
                name = renamed
            }
            usedNames.insert(name)
            let dest = targetDir.appendingPathComponent(name)
            do {
                try replaceCopy(from: item, to: dest, in: targetDir, fm: fileManager)
                report.imported.append(name)
                report.fileCount += isDirectory(item, fm: fileManager)
                    ? countFiles(at: dest, fm: fileManager) : 1
            } catch {
                report.skipped.append("\(name)（\(error.localizedDescription)）")
            }
        }
        return report
    }

    /// 本批导入内的重名：追加「(2)」「(3)」…，同时避开书库里已存在的名字
    private static func uniqueName(for name: String, used: Set<String>,
                                   in dir: URL, fm: FileManager) -> String {
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var index = 2
        while index <= 999 {
            let candidate = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            if !used.contains(candidate),
               !fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
                return candidate
            }
            index += 1
        }
        let suffix = UUID().uuidString.prefix(4)
        return ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
    }

    // MARK: - 要复制哪些项目

    private static func importItems(at source: URL, category: BookCategory,
                                    isDirectory: Bool, fm: FileManager) throws -> [URL] {
        guard fm.fileExists(atPath: source.path) else {
            throw BookImportError.inaccessible("项目不存在或已被移动")
        }
        // 选的是单个文件：直接复制
        if !isDirectory { return [source] }

        // 选的就是分区目录本身：复制其子项
        if LibrarySection(folderName: source.lastPathComponent) != nil {
            return try visibleItems(at: source, fm: fm)
        }

        switch category {
        case .novel:
            // 文件夹里可能有多本书：把所有电子书文件逐个复制进「小说」
            var found: [URL] = []
            collectNovelFiles(in: source, depth: 0, into: &found, fm: fm)
            return found
        case .comic, .shortDrama:
            // 整个文件夹就是一部（漫画 / 短剧），保持层级原样
            return [source]
        case .organized:
            return try organizedItems(at: source, fm: fm)
        }
    }

    private static func collectNovelFiles(in dir: URL, depth: Int,
                                          into found: inout [URL], fm: FileManager) {
        guard let items = try? visibleItems(at: dir, fm: fm) else { return }
        for item in items {
            if isDirectory(item, fm: fm) {
                if depth < 3 { collectNovelFiles(in: item, depth: depth + 1, into: &found, fm: fm) }
            } else if NovelScanner.isNovelFile(item) {
                found.append(item)
            }
        }
    }

    /// 整理分区沿用旧规则：
    /// · 书库根（作者文件夹 → 章节文件夹）→ 复制每个作者文件夹
    /// · 单个作者文件夹 / 章节文件夹 → 整体复制
    private static func organizedItems(at source: URL, fm: FileManager) throws -> [URL] {
        let children = try visibleItems(at: source, fm: fm)
        let dirs = children.filter { isDirectory($0, fm: fm) }
        if dirs.isEmpty { return [source] }
        let probe = dirs[0]
        let nested = (try? visibleItems(at: probe, fm: fm)) ?? []
        if nested.contains(where: { isDirectory($0, fm: fm) }) {
            return dirs
        }
        return [source]
    }

    // MARK: - 自动判断分区

    static func suggestedSection(for url: URL, isDirectory: Bool,
                                 fm: FileManager = .default) -> BookCategory {
        guard isDirectory else {
            return NovelScanner.isNovelFile(url) ? .novel : .organized
        }
        var hasText = false
        var hasImageOrPDF = false
        scanKind(url, depth: 0, hasText: &hasText, hasImage: &hasImageOrPDF, fm: fm)
        if hasText { return .organized }
        if hasImageOrPDF { return .comic }
        return .organized
    }

    private static func scanKind(_ dir: URL, depth: Int,
                                 hasText: inout Bool, hasImage: inout Bool, fm: FileManager) {
        guard depth <= 3, let items = try? visibleItems(at: dir, fm: fm) else { return }
        for item in items {
            if isDirectory(item, fm: fm) {
                scanKind(item, depth: depth + 1, hasText: &hasText, hasImage: &hasImage, fm: fm)
                continue
            }
            let ext = MediaResolver.fileExtension(item.lastPathComponent)
            if ["txt", "text", "md", "markdown", "epub"].contains(ext) { hasText = true }
            if MediaResolver.imageExtensions.contains(ext) || ext == "pdf" { hasImage = true }
        }
    }

    // MARK: - 复制

    /// 同名目标整体替换；先移走旧副本，复制成功再删，失败回滚，绝不留下半本书。
    ///
    /// 回滚的坑：原来先 `removeItem(dest)` 再 `moveItem(backup → dest)`，
    /// 一旦 dest 删不干净（受保护路径 / 半成品里有只读文件），move 也会失败，
    /// 用户原书就只剩一个隐藏的 `.ln-backup-*`，等于凭空消失。
    /// 现在的顺序是「半成品先挪开 → 旧副本移回 → 才清半成品」，
    /// 任一步失败都保留旧副本，并把备份路径写进错误里。
    private static func replaceCopy(from src: URL, to dest: URL, in docs: URL,
                                    fm: FileManager) throws {
        if !fm.fileExists(atPath: dest.path) {
            try fm.copyItem(at: src, to: dest)
            return
        }
        // 备份名带上原文件名，进程被杀时下次启动能认出来还原（见 recoverInterruptedReplacements）
        let backup = docs.appendingPathComponent(
            ".ln-backup-\(UUID().uuidString)-\(dest.lastPathComponent)")
        try fm.moveItem(at: dest, to: backup)
        do {
            try fm.copyItem(at: src, to: dest)
            try? fm.removeItem(at: backup)
        } catch {
            let partial = docs.appendingPathComponent(".ln-partial-\(UUID().uuidString)")
            if fm.fileExists(atPath: dest.path) {
                do {
                    try fm.moveItem(at: dest, to: partial)
                } catch {
                    // 半成品挪不动：不动旧副本，把它留在原处，交给恢复流程
                    throw BookImportError.rollbackFailed(backup.path)
                }
            }
            do {
                try fm.moveItem(at: backup, to: dest)
                try? fm.removeItem(at: partial)
            } catch {
                throw BookImportError.rollbackFailed(backup.path)
            }
            throw error
        }
    }

    /// 启动时补救「覆盖导入中途被杀」留下的隐藏备份：
    /// 备份名形如 `.ln-backup-<uuid>-<原名>`，若原位置为空就把旧书挪回去。
    /// 备份散落在各分区 / 系列目录里，所以按目录递归（限深 3 层）。
    /// 返回还原的条目数。
    @discardableResult
    static func recoverInterruptedReplacements(in root: URL,
                                               depth: Int = 0,
                                               fileManager fm: FileManager = .default) -> Int {
        guard depth <= 3 else { return 0 }
        guard let items = try? fm.contentsOfDirectory(at: root,
                                                      includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: []) else { return 0 }
        var restored = 0
        for item in items {
            let name = item.lastPathComponent
            if name.hasPrefix(".ln-backup-") {
                // 去掉 `.ln-backup-<uuid>-` 前缀，剩下的才是原文件名（可能含连字符）
                let rest = name.dropFirst(".ln-backup-".count)
                guard let dash = rest.firstIndex(of: "-") else { continue }
                let original = String(rest[rest.index(after: dash)...])
                guard !original.isEmpty else { continue }
                let dest = root.appendingPathComponent(original)
                guard !fm.fileExists(atPath: dest.path) else { continue }
                if (try? fm.moveItem(at: item, to: dest)) != nil { restored += 1 }
                continue
            }
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir, !MediaResolver.isHidden(name) {
                restored += recoverInterruptedReplacements(in: item,
                                                           depth: depth + 1,
                                                           fileManager: fm)
            }
        }
        return restored
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
