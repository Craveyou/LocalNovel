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

    /// 排版属性：字号 + 行距 + 段间距。段间距取 lineSpacing，
    /// 与滚动模式里 LazyVStack(spacing: lineSpacing) 的视觉一致。
    static func attributes(fontSize: CGFloat, lineSpacing: CGFloat) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = lineSpacing
        style.lineBreakMode = .byWordWrapping
        return [
            .font: UIFont.systemFont(ofSize: fontSize),
            .paragraphStyle: style
        ]
    }

    /// 注意：这里刻意不写 .foregroundColor。
    /// 颜色要在绘制时按当前 trait（浅色 / 深色）决定，不能在分页阶段固化。
    static func attributed(paragraphs: [String],
                           fontSize: CGFloat,
                           lineSpacing: CGFloat) -> NSAttributedString {
        NSAttributedString(string: joinedText(paragraphs),
                           attributes: attributes(fontSize: fontSize, lineSpacing: lineSpacing))
    }

    /// 按容器尺寸分页
    static func paginate(paragraphs: [String],
                         fontSize: CGFloat,
                         lineSpacing: CGFloat,
                         size: CGSize) -> [ReaderPageSlice] {
        guard !paragraphs.isEmpty, size.width > 40, size.height > 60 else { return [] }
        let attr = attributed(paragraphs: paragraphs, fontSize: fontSize, lineSpacing: lineSpacing)
        let length = attr.length
        guard length > 0 else { return [] }

        let starts = paragraphStarts(paragraphs)
        let framesetter = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        let text = attr.string as NSString

        var slices: [ReaderPageSlice] = []
        var location = 0
        while location < length {
            let frame = CTFramesetterCreateFrame(framesetter,
                                                 CFRange(location: location, length: 0),
                                                 path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            // 容器连一行都放不下时必须退出，否则会死循环
            guard visible.length > 0 else { break }
            let chunk = text.substring(with: NSRange(location: location, length: visible.length))
            // 只剩换行 / 空白的「页」不单独成页（分页处正好落在段落结尾时会出现）
            if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                slices.append(ReaderPageSlice(location: location,
                                              length: visible.length,
                                              paragraph: paragraphIndex(of: location, starts: starts)))
            }
            location += visible.length
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

    /// 段落下标 → 页码（取最后一个「起始段落 ≤ 目标」的页）
    static func pageIndex(forParagraph paragraph: Int, in slices: [ReaderPageSlice]) -> Int {
        guard !slices.isEmpty else { return 0 }
        var result = 0
        for (index, slice) in slices.enumerated() {
            if slice.paragraph <= paragraph { result = index } else { break }
        }
        return min(result, slices.count - 1)
    }

    /// 当前页的进度文案：「3 / 128」
    static func progressText(page: Int, total: Int) -> String {
        guard total > 0 else { return "" }
        return "\(min(max(page, 0) + 1, total)) / \(total)"
    }
}
