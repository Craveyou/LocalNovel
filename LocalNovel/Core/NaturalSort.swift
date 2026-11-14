import Foundation

// MARK: - 自然排序
// 目标：1, 2, 3 ... 10 按数值排列，而不是字典序把 10 排在 2 前面。
// 规则：先做 NFKC 归一化（全角数字/全角字母 → 半角），再按「数字串 / 非数字串」切分比较。
// 数字串去前导零后按「长度 + 字典序」比较，避免超大数字溢出；非数字串按 Unicode 标量比较。
// 该实现与 Validation/validate_core.py 中的等价实现保持一致，便于双端验证。

enum NaturalSort {
    /// 归一化：NFC 合成 + 全角转半角（覆盖 NFKC 中影响文件名的部分）
    static func normalize(_ s: String) -> String {
        let composed = (s as NSString).precomposedStringWithCanonicalMapping
        return normalizeWidth(composed)
    }

    /// 全角 ASCII 与全角空格转半角
    private static func normalizeWidth(_ s: String) -> String {
        var out = String()
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if v == 0x3000 { // 全角空格
                out.unicodeScalars.append(Unicode.Scalar(0x20)!)
            } else if (0xFF01...0xFF5E).contains(v), let half = Unicode.Scalar(v - 0xFEE0) {
                out.unicodeScalars.append(half) // ！～ -> !~
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private enum Token {
        case number(String)
        case text(String)
    }

    private static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = String()
        var currentIsDigit: Bool?

        func flush() {
            guard !buffer.isEmpty, let isDigit = currentIsDigit else { return }
            tokens.append(isDigit ? .number(buffer) : .text(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        for ch in s {
            let isDigit = ch.isASCII && ch.isNumber
            if let cur = currentIsDigit, cur != isDigit {
                flush()
            }
            currentIsDigit = isDigit
            buffer.append(ch)
        }
        flush()
        return tokens
    }

    private static func trimmedNumber(_ s: String) -> String {
        let t = s.drop(while: { $0 == "0" })
        return t.isEmpty ? "0" : String(t)
    }

    private static func compareNumbers(_ a: String, _ b: String) -> ComparisonResult {
        let x = trimmedNumber(a), y = trimmedNumber(b)
        if x.count != y.count { return x.count < y.count ? .orderedAscending : .orderedDescending }
        if x == y { return .orderedSame }
        return x < y ? .orderedAscending : .orderedDescending
    }

    private static func compareText(_ a: String, _ b: String) -> ComparisonResult {
        if a == b { return .orderedSame }
        return a < b ? .orderedAscending : .orderedDescending
    }

    /// 返回 true 表示 a 应排在 b 之前
    static func less(_ aRaw: String, _ bRaw: String) -> Bool {
        let a = normalize(aRaw), b = normalize(bRaw)
        if a == b { return aRaw < bRaw } // 稳定：完全相同时按原名定序
        let ta = tokenize(a), tb = tokenize(b)
        let n = min(ta.count, tb.count)
        for i in 0..<n {
            let r: ComparisonResult
            switch (ta[i], tb[i]) {
            case (.number(let x), .number(let y)): r = compareNumbers(x, y)
            case (.text(let x), .text(let y)):     r = compareText(x, y)
            case (.number(let x), .text(let y)):   r = compareText(x, y)
            case (.text(let x), .number(let y)):   r = compareText(x, y)
            }
            if r != .orderedSame { return r == .orderedAscending }
        }
        return ta.count < tb.count
    }

    static func sorted<T>(_ items: [T], by name: (T) -> String) -> [T] {
        items.sorted { less(name($0), name($1)) }
    }
}
