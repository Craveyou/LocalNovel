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

    /// 正文内容的决定性因素（净化规则 + 繁简）的指纹。
    /// 分页重建判断要用它：只看「段数 + 首末段长度」的话，
    /// 改了一条只影响中间段落的净化规则，段数和首末段都没变 → 不重建，
    /// 屏幕上还是没净化的旧正文，直到切章或改字号才刷新。
    static func stamp(rules: [PurifyRule], traditional: Bool) -> String {
        let active = rules.filter { $0.isEnabled && !$0.pattern.isEmpty }
        guard !active.isEmpty || traditional else { return "raw" }
        return "\(traditional ? 1 : 0)|\(PurifyEngine.fingerprint(active))"
    }

    /// 全书可能几千段，这里只在「章节 + 规则 + 繁简」变化时重算
    static func paragraphs(chapterId: String,
                           raw: [String],
                           rules: [PurifyRule],
                           traditional: Bool) -> [String] {
        let active = rules.filter { $0.isEnabled && !$0.pattern.isEmpty }
        guard !active.isEmpty || traditional else { return raw }

        let key = "\(chapterId)|\(traditional ? 1 : 0)|\(PurifyEngine.fingerprint(active))"
        if let hit = cache[key] { return hit }

        var result = raw
        if !active.isEmpty {
            result = result.map { PurifyEngine.apply(active, to: $0) }
            result = result.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        if traditional {
            result = result.map { ChineseScript.toTraditional($0) }
        }

        cache[key] = result
        order.append(key)
        if order.count > 3 {
            cache[order.removeFirst()] = nil
        }
        return result
    }

    /// 后台预计算某一章的净化 / 繁简结果，算完在主线程写缓存再回调。
    ///
    /// 净化是逐段跑正则、繁简是逐段跑 ICU 转换，几千段放主线程会明显卡顿。
    /// 阅读器在「点书 → 进章」之间先调它，首帧就只剩分页排版。
    /// 没启用任何规则时零成本：不复制数组，直接回调。
    static func precompute(chapterId: String,
                           raw: [String],
                           rules: [PurifyRule],
                           traditional: Bool,
                           completion: @escaping () -> Void) {
        let active = rules.filter { $0.isEnabled && !$0.pattern.isEmpty }
        guard !active.isEmpty || traditional else {
            completion()
            return
        }
        let key = "\(chapterId)|\(traditional ? 1 : 0)|\(PurifyEngine.fingerprint(active))"
        if cache[key] != nil {
            completion()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var result = raw
            if !active.isEmpty {
                result = result.map { PurifyEngine.apply(active, to: $0) }
                result = result.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            if traditional {
                result = result.map { ChineseScript.toTraditional($0) }
            }
            let value = result
            DispatchQueue.main.async {
                store(key: key, value: value)
                completion()
            }
        }
    }

    /// 缓存只允许主线程写（读者可能在另一章取用）
    private static func store(key: String, value: [String]) {
        cache[key] = value
        order.append(key)
        if order.count > 3 {
            cache[order.removeFirst()] = nil
        }
    }

    static func reset() {
        cache.removeAll()
        order.removeAll()
    }
}
