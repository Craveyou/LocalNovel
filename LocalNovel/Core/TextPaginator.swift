import Foundation
import CoreText
import UIKit

// MARK: - 文本分页（翻页模式）
//
// 为什么不用 SwiftUI 的 Text 逐页显示：分页必须「排版与测量是同一套引擎」，
// 否则会出现文字溢出页底或半行被截断。这里统一用 CoreText：
//   测量（CTFramesetterCreateFrame + CTFramesetterGetVisibleStringRange）→ 得到每页字符区间
//   绘制（CTFrameDraw 同一个 attributed string 的同一段区间）→ 视觉与测量完全一致
//
// 段落切分沿用 TextLoader.paragraphs，与滚动模式共用一份文本，
// 因此两种模式的阅读记忆都是「第几段」（锚点 blk-pN），可以互相切换而不丢位置。
//
// 排版参数全部来自 ReaderTypography（字号 / 字体 / 字重 / 行距 / 段距 / 字距 / 对齐 / 缩进），
// 颜色来自 ReaderTheme，所以换主题、换字号都只需要重建这一份 attributed。

/// 一页：字符区间 + 该页起始字符所属的段落下标
struct ReaderPageSlice: Equatable {
    let location: Int
    let length: Int
    let paragraph: Int

    var range: NSRange { NSRange(location: location, length: length) }
}

enum TextPaginator {

    /// 每段起始的 UTF-16 偏移（段落之间用一个 \n 连接，与 joined(separator:) 一致）
    static func paragraphStarts(_ paragraphs: [String]) -> [Int] {
        var starts: [Int] = []
        starts.reserveCapacity(paragraphs.count)
        var offset = 0
        for p in paragraphs {
            starts.append(offset)
            offset += (p as NSString).length + 1
        }
        return starts
    }

    static func joinedText(_ paragraphs: [String]) -> String {
        paragraphs.joined(separator: "\n")
    }

    /// 排版属性：字号 + 字体 + 字重 + 行距 + 段距 + 字距 + 对齐 + 首行缩进，颜色取主题正文色。
    ///
    /// 颜色写成具体的 UIColor（主题固定色）：不再依赖 UIColor.label 的动态解析——
    /// 主题背景可能是米黄 / 护眼绿，label 的自动反色反而会看不清。
    static func attributes(_ type: ReaderTypography, _ theme: ReaderTheme) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = type.lineSpacing
        style.paragraphSpacing = type.paragraphSpacing
        style.alignment = type.alignment.nsAlignment
        style.lineBreakMode = .byWordWrapping
        if type.firstLineIndent {
            // 中文习惯缩进两个字
            style.firstLineHeadIndent = type.fontSize * 2
            style.headIndent = 0
        }
        var attrs: [NSAttributedString.Key: Any] = [
            .font: ReaderFonts.font(size: type.fontSize,
                                    weight: type.weight),
            .paragraphStyle: style,
            .foregroundColor: theme.uiTextColor
        ]
        if type.wordSpacing > 0 {
            attrs[.kern] = type.wordSpacing
        }
        return attrs
    }

    static func attributed(paragraphs: [String],
                           typography: ReaderTypography,
                           theme: ReaderTheme) -> NSAttributedString {
        NSAttributedString(string: joinedText(paragraphs),
                           attributes: attributes(typography, theme))
    }

    /// 章节标题块：渲染成正文前面的一段，带自己的字号 / 字重 / 颜色 / 上下间距。
    /// 返回的字符串已带结尾换行，直接拼在正文前面即可。
    static func titleAttributed(title: String,
                                typography: ReaderTypography,
                                theme: ReaderTheme) -> NSAttributedString? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let style = typography.title
        let size = style.fontSize(bodySize: typography.fontSize)
        let color = style.colorMode == 1 ? UIColor(hex: style.colorHex) : theme.uiTitleColor

        let para = NSMutableParagraphStyle()
        para.alignment = typography.alignment.nsAlignment
        para.lineSpacing = max(2, typography.lineSpacing * 0.4)
        para.paragraphSpacingBefore = style.topPadding
        para.paragraphSpacing = style.bottomPadding
        para.lineBreakMode = .byWordWrapping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: ReaderFonts.font(size: size,
                                    weight: style.weight,
                                    italic: style.isItalic),
            .foregroundColor: color,
            .paragraphStyle: para
        ]

        if style.splitTwoLines, let split = splitTitle(trimmed) {
            // 「第10章 夜行」→ 第一行标题字号，第二行缩到 0.72 倍并弱化
            let first = NSMutableAttributedString(string: split.0 + "\n", attributes: attrs)
            var secondAttrs = attrs
            let small = NSMutableParagraphStyle()
            small.alignment = typography.alignment.nsAlignment
            small.lineSpacing = max(2, typography.lineSpacing * 0.4)
            small.paragraphSpacing = style.bottomPadding
            small.paragraphSpacingBefore = 2
            secondAttrs[.font] = ReaderFonts.font(size: max(12, size * 0.72),
                                                  weight: .regular,
                                                  italic: style.isItalic)
            secondAttrs[.paragraphStyle] = small
            first.append(NSAttributedString(string: split.1, attributes: secondAttrs))
            return first
        }

        let result = NSMutableAttributedString(string: trimmed, attributes: attrs)
        if style.showBottomLine {
            // 用下划线模拟标题下方细线，不额外插图形页
            result.addAttribute(.underlineStyle,
                                value: NSUnderlineStyle.single.rawValue,
                                range: NSRange(location: 0, length: result.length))
            result.addAttribute(.underlineColor, value: theme.uiSeparatorColor,
                                range: NSRange(location: 0, length: result.length))
        }
        return result
    }

    /// 把「第10章 夜行」拆成两段；拆不出来（没有空白）就返回 nil。
    /// 滚动模式与分页模式共用同一套拆分规则，保证两种阅读方式标题排法一致。
    static func splitTitle(_ title: String) -> (String, String)? {
        guard let space = title.firstIndex(where: { $0 == " " || $0 == "\u{3000}" }) else { return nil }
        let head = String(title[title.startIndex..<space]).trimmingCharacters(in: .whitespaces)
        let tail = String(title[title.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty, !tail.isEmpty else { return nil }
        return (head, tail)
    }

    /// 按容器尺寸分页
    static func paginate(paragraphs: [String],
                         typography: ReaderTypography,
                         theme: ReaderTheme,
                         size: CGSize) -> [ReaderPageSlice] {
        guard !paragraphs.isEmpty, size.width > 40, size.height > 60 else { return [] }
        let attr = attributed(paragraphs: paragraphs, typography: typography, theme: theme)
        return paginate(attributed: attr, paragraphs: paragraphs, size: size)
    }

    /// 分页（复用外部建好的 attributed）：翻页阅读器整章只建一份排版文本，
    /// 测量与逐页绘制共用，避免「每页一份全文」把内存放大几十倍。
    ///
    /// `titleOffset` = 拼在正文前面的标题块长度：段落起始偏移整体后移，
    /// 落在标题区的页仍然算第 0 段（阅读锚点不受影响）。
    static func paginate(attributed attr: NSAttributedString,
                         paragraphs: [String],
                         size: CGSize,
                         titleOffset: Int = 0) -> [ReaderPageSlice] {
        guard !paragraphs.isEmpty, size.width > 40, size.height > 60 else { return [] }
        let length = attr.length
        guard length > 0 else { return [] }

        let starts = paragraphStarts(paragraphs).map { $0 + titleOffset }
        let framesetter = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        let text = attr.string as NSString

        var slices: [ReaderPageSlice] = []
        var location = 0
        while location < length {
            // 每次试排都会产生 CTFrame 与一页字符串：用 autoreleasepool 及时回收，
            // 否则一次分页几千页会把中间对象全压在内存里（大文件闪退的原因之一）。
            let step = autoreleasepool { () -> (advance: Int, paragraph: Int?) in
                let frame = CTFramesetterCreateFrame(framesetter,
                                                     CFRange(location: location, length: 0),
                                                     path, nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                // 容器连一行都放不下时必须退出，否则会死循环
                guard visible.length > 0 else { return (0, nil) }
                let chunk = text.substring(with: NSRange(location: location, length: visible.length))
                // 只剩换行 / 空白的「页」不单独成页（分页处正好落在段落结尾时会出现）
                if chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (visible.length, nil)
                }
                return (visible.length, paragraphIndex(of: location, starts: starts))
            }
            guard step.advance > 0 else { break }
            if let paragraph = step.paragraph {
                slices.append(ReaderPageSlice(location: location,
                                              length: step.advance,
                                              paragraph: paragraph))
            }
            location += step.advance
        }
        return slices
    }

    /// 字符偏移 → 段落下标（二分，越界收敛到最后一页）
    static func paragraphIndex(of location: Int, starts: [Int]) -> Int {
        guard !starts.isEmpty else { return 0 }
        var low = 0
        var high = starts.count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if starts[mid] <= location {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    /// 段落下标 → 页码：定位到「这一段第一次出现的页」。
    ///
    /// 以前取最后一个 slice.paragraph <= 目标 的页：目标段跨 3 页时三页都满足，
    /// 结果落在段尾。书签 / 续读记的是段首语义，必须取第一次出现。
    /// 目标段本身没有独立起始页（被净化删空）时，退回它前面那一页。
    static func pageIndex(forParagraph paragraph: Int, in slices: [ReaderPageSlice]) -> Int {
        guard !slices.isEmpty else { return 0 }
        if let index = slices.firstIndex(where: { $0.paragraph == paragraph }) { return index }
        if let index = slices.firstIndex(where: { $0.paragraph > paragraph }) {
            return max(0, index - 1)
        }
        return slices.count - 1
    }

    /// 当前页的进度文案：「3 / 128」
    static func progressText(page: Int, total: Int) -> String {
        guard total > 0 else { return "" }
        return "\(min(max(page, 0) + 1, total)) / \(total)"
    }

    /// 百分比文案：页脚选「百分比」时用
    static func percentText(page: Int, total: Int) -> String {
        guard total > 0 else { return "" }
        let value = Double(min(max(page, 0) + 1, total)) / Double(total) * 100
        return String(format: "%.0f%%", value)
    }
}
