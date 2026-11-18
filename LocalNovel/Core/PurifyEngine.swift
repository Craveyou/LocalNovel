import Foundation
import SwiftUI

// MARK: - 净化（正文正则替换）
//
// 千阅的「净化」是把正文里混进来的广告行、盗版站标、字数统计之类按规则删掉 / 换掉。
// 这里做成「规则列表 + 全局开关」：每条规则一个正则 + 替换文本（留空 = 删除）。
//
// 性能：正文可能有上千段，逐段跑正则在翻页时会被反复调用，所以按
// 「章节 id + 规则指纹 + 繁简」做一层小缓存（最多 3 章），与繁简转换合并成一条流水线。

struct PurifyRule: Codable, Identifiable, Equatable {
    var id: String
    var pattern: String
    /// 留空表示删除匹配内容
    var replacement: String
    var isEnabled: Bool
    /// 关掉后按纯文本匹配（正则元字符会被转义）
    var isRegex: Bool

    static func newRule() -> PurifyRule {
        PurifyRule(id: UUID().uuidString, pattern: "", replacement: "",
                   isEnabled: true, isRegex: true)
    }

    /// 编译好的正则（失败则为 nil，调用方按纯文本处理）
    var regex: NSRegularExpression? {
        isRegex ? try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) : nil
    }
}

enum PurifyEngine {
    /// 规则指纹：任何一条改动都要让缓存失效
    static func fingerprint(_ rules: [PurifyRule]) -> String {
        rules.map { "\($0.isEnabled ? 1 : 0)\($0.isRegex ? 1 : 0)|\($0.pattern)|\($0.replacement)" }
            .joined(separator: "\u{1F}")
    }

    static func apply(_ rules: [PurifyRule], to text: String) -> String {
        var result = text
        for rule in rules where rule.isEnabled && !rule.pattern.isEmpty {
            if let regex = rule.regex {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result,
                                                        options: [],
                                                        range: range,
                                                        withTemplate: rule.replacement)
            } else if rule.isRegex {
                continue   // 正则写错了，跳过这条，别把正文吃掉
            } else {
                result = result.replacingOccurrences(of: rule.pattern, with: rule.replacement)
            }
        }
        return result
    }
}

// MARK: - 正文流水线（净化 → 繁简），带小缓存

enum ReaderTextPipeline {
    private static var cache: [String: [String]] = [:]
    private static var order: [String] = []
    /// 每次 reset（净化规则变 / 切编码 / 重分章）都+1。
    /// 后台预计算拿的是进入时的 raw 副本，回来时若世代号已变，结果必须丢弃，
    /// 否则旧编码的乱码会盖掉刚解出来的新正文。
    private static var generation = 0

    /// 正文内容的决定性因素（净化规则）的指纹。
    /// 分页重建判断要用它：只看「段数 + 首末段长度」的话，
    /// 改了一条只影响中间段落的净化规则，段数和首末段都没变 → 不重建，
    /// 屏幕上还是没净化的旧正文，直到切章或改字号才刷新。
    static func stamp(rules: [PurifyRule]) -> String {
        let active = rules.filter { $0.isEnabled && !$0.pattern.isEmpty }
        guard !active.isEmpty else { return "raw" }
        return PurifyEngine.fingerprint(active)
    }

    /// 唯一一段「净化 → 去空段」的变换，阅读器/搜索/预计算必须共用。
    /// 返回的 index 是净化后的段号（与 blk-pN 一致）；没启用规则时直接沿用原文段号。
    private static func transformed(raw: [String],
                                    active: [PurifyRule]) -> [(index: Int, text: String)] {
        guard !active.isEmpty else {
            return raw.enumerated().map { (index: $0.offset, text: $0.element) }
        }
        var result: [(index: Int, text: String)] = []
        result.reserveCapacity(raw.count)
        var index = 0
        for item in raw {
            let text = PurifyEngine.apply(active, to: item)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            result.append((index: index, text: text))
            index += 1
        }
        return result
    }

    /// 搜索用：拿到与阅读器完全同口径的「段号 + 文本」对。
    /// 只在后台读 raw，不碰任何共享缓存。
    static func displayPairs(raw: [String],
                             rules: [PurifyRule]) -> [(index: Int, text: String)] {
        let active = rules.filter { $0.isEnabled && !$0.pattern.isEmpty }
        return transformed(raw: raw, active: active)
    }

    /// 全书可能几千段，这里只在「章节 + 规则」变化时重算
    static func paragraphs(chapterId: String,
                           raw: [String],
                           rules: [PurifyRule]) -> [String] {
        let active = rules.filter { $0.isEnabled && !$0.pattern.isEmpty }
        guard !active.isEmpty else { return raw }

        let key = "\(chapterId)|\(PurifyEngine.fingerprint(active))"
        if let hit = cache[key] { return hit }

        let value = transformed(raw: raw, active: active).map { $0.text }
        store(key: key, value: value)
        return value
    }

    /// 进度条 / 跨章跳转必须按「阅读器实际显示的段数」换算，不能拿原文段数。
    static func displayCount(chapterId: String,
                             raw: [String],
                             rules: [PurifyRule]) -> Int {
        paragraphs(chapterId: chapterId, raw: raw, rules: rules).count
    }

    /// 后台预计算某一章的净化结果，算完在主线程写缓存再回调。
    /// 净化是逐段跑正则，几千段放主线程会明显卡顿；
    /// 阅读器在「点书 → 进章」之间先调它，首帧就只剩分页排版。
    /// 没启用任何规则时零成本：不复制数组，直接回调。
    static func precompute(chapterId: String,
                           raw: [String],
                           rules: [PurifyRule],
                           completion: @escaping () -> Void) {
        let active = rules.filter { $0.isEnabled && !$0.pattern.isEmpty }
        guard !active.isEmpty else {
            completion()
            return
        }
        let key = "\(chapterId)|\(PurifyEngine.fingerprint(active))"
        if cache[key] != nil {
            completion()
            return
        }
        let token = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let value = transformed(raw: raw, active: active).map { $0.text }
            DispatchQueue.main.async {
                guard token == generation else { completion(); return }
                store(key: key, value: value)
                completion()
            }
        }
    }

    /// 缓存只允许主线程写（读者可能在另一章取用）
    private static func store(key: String, value: [String]) {
        if let position = order.firstIndex(of: key) { order.remove(at: position) }
        cache[key] = value
        order.append(key)
        while order.count > 3 {
            cache[order.removeFirst()] = nil
        }
    }

    static func reset() {
        generation &+= 1
        cache.removeAll()
        order.removeAll()
    }
}
