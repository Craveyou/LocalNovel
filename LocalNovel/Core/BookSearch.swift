import Foundation
import SwiftUI

// MARK: - 全书正文搜索
//
// 只在后台队列里读正文，不碰 LibraryStore 的缓存字典（那些缓存只允许主线程写）。
// 正文读取全部走 TextLoader / MediaResolver 的纯函数入口，二者都用 NSCache 或只有常量，
// 后台调用安全。命中结果按批回主线程追加，长书也不会把主线程卡死。

/// 一条正文命中
struct SearchHit: Identifiable, Hashable {
    /// 章节在目录里的下标（用于显示「第 N 章」并回查 Chapter）
    let chapterIndex: Int
    let chapterId: String
    let chapterTitle: String
    /// 段落下标（0 起，与阅读器 blk-p 编号一致）
    let paragraph: Int
    /// 命中位置前后截的一段原文
    let snippet: String

    var id: String { "\(chapterId)#\(paragraph)" }
}

final class BookSearchModel: ObservableObject {
    /// 单次搜索最多收多少条命中，防止「的」这类词把内存吃光
    static let maxHits = 500
    /// 少打两个字就搜，命中会爆炸
    static let minKeywordLength = 2

    @Published private(set) var hits: [SearchHit] = []
    /// 已扫完的章节数 / 总章节数
    @Published private(set) var scanned = 0
    @Published private(set) var total = 0
    @Published private(set) var isSearching = false
    /// 命中达到上限，后面没再继续扫
    @Published private(set) var limitReached = false
    /// 给界面的提示（关键词太短、没有正文等）
    @Published private(set) var hint: String?

    /// 当前搜索的世代号：开新搜索就 +1，旧任务每章自查一次后自行退出
    private var generation = 0
    private let stateQueue = DispatchQueue(label: "LocalNovel.booksearch.state")

    // MARK: 对外

    /// rules 传 nil 时取当前生效的净化规则。必须在主线程调用（读 Preferences / 生成规则快照）。
    func start(query rawQuery: String, chapters: [Chapter], rules: [PurifyRule]? = nil) {
        let keyword = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchRules = rules ?? Preferences.shared.activePurifyRules
        cancel()

        guard keyword.count >= Self.minKeywordLength else {
            hits = []
            scanned = 0
            total = 0
            limitReached = false
            hint = keyword.isEmpty ? nil : "正文搜索至少输入 \(Self.minKeywordLength) 个字"
            return
        }
        guard !chapters.isEmpty else {
            hits = []
            scanned = 0
            total = 0
            hint = "这本书没有章节可搜"
            return
        }

        let myGeneration = nextGeneration()
        hits = []
        scanned = 0
        total = chapters.count
        limitReached = false
        isSearching = true
        hint = nil

        let snapshot = chapters
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var buffer: [SearchHit] = []
            // 上限必须用独立累加器算：buffer 每批都会清空，拿它计数等于没有上限
            var totalHits = 0
            var stopped = false
            /// 触到上限时停在第几章（进度显示要准，别拿「全扫完」冒充）
            var stoppedAtChapter = 0

            for (index, chapter) in snapshot.enumerated() {
                guard self.isAlive(myGeneration) else { return }

                let preferred = TextEncodingStore.option(for: TextEncodingStore.bookKey(for: chapter))
                let body = Self.bodyText(of: chapter, preferred: preferred)
                if !body.isEmpty {
                    let raw = TextLoader.paragraphs(body)
                    // 与阅读器共用同一套净化 / 去空段变换：段号就是 blk-pN 的 N，
                    // 否则净化开启后搜索命中下标和屏幕段落属于两个空间，点了跳错。
                    let displayed = ReaderTextPipeline.displayPairs(raw: raw, rules: searchRules)
                    let title = chapter.displayTitle
                    for pair in displayed {
                        guard let snippet = Self.snippet(in: pair.text, keyword: keyword) else { continue }
                        buffer.append(SearchHit(chapterIndex: index,
                                                chapterId: chapter.id,
                                                chapterTitle: title,
                                                paragraph: pair.index,
                                                snippet: snippet))
                        totalHits += 1
                        if totalHits >= Self.maxHits { stopped = true; break }
                    }
                }

                // 每章或每累积 20 条回一次主线程，避免几百次刷新
                let reachedEnd = index + 1 == snapshot.count
                if reachedEnd || buffer.count >= 20 || (index + 1) % 5 == 0 {
                    let chunk = buffer
                    let done = index + 1
                    buffer.removeAll(keepingCapacity: true)
                    DispatchQueue.main.async {
                        guard self.isAlive(myGeneration) else { return }
                        self.hits.append(contentsOf: chunk)
                        self.scanned = done
                    }
                }
                if stopped {
                    stoppedAtChapter = index + 1
                    break
                }
            }

            DispatchQueue.main.async {
                guard self.isAlive(myGeneration) else { return }
                if !buffer.isEmpty { self.hits.append(contentsOf: buffer) }
                if stopped {
                    self.limitReached = true
                    self.scanned = stoppedAtChapter
                } else {
                    self.scanned = snapshot.count
                }
                self.isSearching = false
            }
        }
    }

    /// 关闭面板 / 关键词清空时调用
    func cancel() {
        stateQueue.sync { generation += 1 }
        if isSearching { isSearching = false }
        hits = []
        scanned = 0
        total = 0
        limitReached = false
        hint = nil
    }

    // MARK: 世代号（跨线程判活）

    private func nextGeneration() -> Int {
        stateQueue.sync {
            generation += 1
            return generation
        }
    }

    private func isAlive(_ token: Int) -> Bool {
        stateQueue.sync { generation == token }
    }

    // MARK: 取正文（后台安全，不写任何共享缓存）

    private static func bodyText(of chapter: Chapter, preferred: TextEncodingOption) -> String {
        switch chapter.kind {
        case .slice:
            guard let range = chapter.range,
                  let full = try? TextLoader.loadDocument(chapter.folderURL, preferred: preferred) else {
                return ""
            }
            return TextLoader.substring(full, range: range)
        case .file:
            return (try? TextLoader.loadDocument(chapter.folderURL, preferred: preferred)) ?? ""
        case .folder:
            // 章节目录：正文文件名不固定，交给 MediaResolver 认一次（纯文件系统，无状态）
            guard let url = MediaResolver.resolveChapter(chapter).textURL else { return "" }
            return (try? TextLoader.load(url, preferred: preferred)) ?? ""
        }
    }

    /// 在这一段里找关键词，命中则返回带前后文的片段（找不到返回 nil）
    private static func snippet(in paragraph: String, keyword: String) -> String? {
        guard !paragraph.isEmpty else { return nil }
        let text = paragraph as NSString
        let found = text.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive])
        guard found.location != NSNotFound else { return nil }

        let padding = 12
        let start = max(0, found.location - padding)
        let end = min(text.length, found.location + found.length + padding)
        // 命中点可能落在表情 / 代理对中间，向外扩到完整字符边界
        let window = text.rangeOfComposedCharacterSequences(
            for: NSRange(location: start, length: end - start))
        var piece = text.substring(with: window)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if window.location > 0 { piece = "…" + piece }
        if window.location + window.length < text.length { piece += "…" }
        return piece
    }
}
