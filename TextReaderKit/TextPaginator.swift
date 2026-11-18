import Foundation
import CoreText
import UIKit

public struct TextPageSlice: Hashable {
    public let location: Int
    public let length: Int
    public let paragraph: Int
    public let text: String

    public init(location: Int, length: Int, paragraph: Int, text: String) {
        self.location = location
        self.length = length
        self.paragraph = paragraph
        self.text = text
    }
}

public enum TextPaginator {
    public static func paragraphs(in text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    public static func paragraphStarts(_ paragraphs: [String]) -> [Int] {
        var starts: [Int] = []
        starts.reserveCapacity(paragraphs.count)
        var offset = 0
        for paragraph in paragraphs {
            starts.append(offset)
            offset += (paragraph as NSString).length + 1
        }
        return starts
    }

    public static func attributed(paragraphs: [String],
                                  fontSize: CGFloat,
                                  lineSpacing: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = 6
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: paragraphs.joined(separator: "\n"),
                                  attributes: [
                                      .font: UIFont.systemFont(ofSize: fontSize),
                                      .foregroundColor: UIColor.label,
                                      .paragraphStyle: style
                                  ])
    }

    public static func paginate(paragraphs: [String],
                                size: CGSize,
                                fontSize: CGFloat,
                                lineSpacing: CGFloat) -> [TextPageSlice] {
        guard !paragraphs.isEmpty, size.width > 40, size.height > 60 else { return [] }
        let attributed = self.attributed(paragraphs: paragraphs,
                                         fontSize: fontSize,
                                         lineSpacing: lineSpacing)
        let starts = paragraphStarts(paragraphs)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        let full = attributed.string as NSString

        var slices: [TextPageSlice] = []
        var location = 0
        while location < attributed.length {
            let advance = autoreleasepool { () -> Int in
                let frame = CTFramesetterCreateFrame(framesetter,
                                                     CFRange(location: location, length: 0),
                                                     path, nil)
                return CTFrameGetVisibleStringRange(frame).length
            }
            guard advance > 0 else { break }
            let text = full.substring(with: NSRange(location: location, length: advance))
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                slices.append(TextPageSlice(location: location,
                                            length: advance,
                                            paragraph: paragraphIndex(of: location, starts: starts),
                                            text: text))
            }
            location += advance
        }
        return slices
    }

    public static func paragraphIndex(of location: Int, starts: [Int]) -> Int {
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

    /// 段号 → 该段第一次出现的页；目标段跨多页时也落在段首。
    public static func pageIndex(forParagraph paragraph: Int, in slices: [TextPageSlice]) -> Int {
        guard !slices.isEmpty else { return 0 }
        if let index = slices.firstIndex(where: { $0.paragraph == paragraph }) { return index }
        if let index = slices.firstIndex(where: { $0.paragraph > paragraph }) {
            return max(0, index - 1)
        }
        return slices.count - 1
    }
}
