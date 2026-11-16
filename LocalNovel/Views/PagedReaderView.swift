import SwiftUI
import UIKit
import Foundation
import CoreText

// MARK: - 翻页阅读器（左右翻页 / 仿真翻页）
//
// 结构：
//   PagedReaderView（SwiftUI 入口）
//     └ PageTurnController（容器：UIPageViewController.pageCurl + 底部页码）
//         ├ TextPageController（CoreText 绘制一页文字，与分页测量同一套引擎）
//         ├ ImagePageView / MediaPageView（插图、音视频各占一页）
//         └ FooterPageView（章末：下一章 / 已是最后一章）
//
// 三条约束：
// 1) 分页在「容器拿到真实尺寸后」做，尺寸与绘制区域是同一个 rect，
//    否则会出现文字超出页底、末行被切。
// 2) 阅读记忆沿用段落锚点 blk-pN，与滚动模式共用，切换模式不丢位置。
// 3) 翻页回调不写 UserDefaults（走 ProgressStore.noteAnchor 去抖），
//    也不改任何 SwiftUI @State，避免翻页时整页重算。

struct PagedReaderInput {
    let chapterId: String
    let paragraphs: [String]
    let images: [MediaItem]
    let avMedia: [MediaItem]
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let restoreParagraph: Int
    let hasNextChapter: Bool
    let nextTitle: String
    let isComic: Bool
    let boostRate: Double

    /// 只有影响排版的参数变化才重建；restoreParagraph 故意不参与。
    /// 用 O(1) 的指纹（段数 + 首末段长度），不再遍历全部段落算总长：
    /// 几十万段的书每次 body 重算都做一次 NSString 桥接，主线程会被拖住。
    var signature: String {
        let head = paragraphs.first?.utf16.count ?? 0
        let tail = paragraphs.last?.utf16.count ?? 0
        return "\(chapterId)|\(paragraphs.count)|\(head)|\(tail)|\(fontSize)|\(lineSpacing)"
            + "|\(images.count)|\(avMedia.count)|\(hasNextChapter)"
    }
}

enum ReaderPage {
    case text(ReaderPageSlice)
    case image(MediaItem)
    case av(MediaItem)
    case footer
}

struct PagedReaderView: UIViewControllerRepresentable {
    let input: PagedReaderInput
    let onProgress: (Int) -> Void
    let onTapMedia: (MediaItem) -> Void
    let onOpenNext: () -> Void

    func makeUIViewController(context: Context) -> PageTurnController {
        let controller = PageTurnController()
        wire(controller)
        controller.apply(input)
        return controller
    }

    func updateUIViewController(_ controller: PageTurnController, context: Context) {
        wire(controller)
        controller.apply(input)
    }

    private func wire(_ controller: PageTurnController) {
        controller.onProgress = onProgress
        controller.onTapMedia = onTapMedia
        controller.onOpenNext = onOpenNext
    }
}

// MARK: - 容器

final class PageTurnController: UIViewController {
    var onProgress: ((Int) -> Void)?
    var onTapMedia: ((MediaItem) -> Void)?
    var onOpenNext: (() -> Void)?

    private let pager = UIPageViewController(transitionStyle: .pageCurl,
                                             navigationOrientation: .horizontal,
                                             options: nil)
    private let pageLabel = UILabel()

    private var input: PagedReaderInput?
    private var pages: [ReaderPage] = []
    private var slices: [ReaderPageSlice] = []
    private var built: [UIViewController?] = []
    /// 全章唯一的排版文本：所有文字页共用这一份，不再每页各建一份全文
    private var measureAttributed: NSAttributedString?
    private var currentIndex = 0
    private var didRestore = false
    private var needsRebuild = true
    private var signature = ""
    private var contentSize: CGSize = .zero

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        pager.isDoubleSided = false
        pager.dataSource = self
        pager.delegate = self
        pager.view.backgroundColor = .systemBackground
        pager.view.clipsToBounds = true

        addChild(pager)
        pager.view.frame = view.bounds
        pager.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pager.view)
        pager.didMove(toParent: self)

        pageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        pageLabel.textColor = .secondaryLabel
        pageLabel.textAlignment = .center
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageLabel)
        NSLayoutConstraint.activate([
            pageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                              constant: -8)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        pager.view.addGestureRecognizer(tap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if contentRect.size != contentSize {
            contentSize = contentRect.size
            needsRebuild = true
        }
        rebuildIfNeeded()
    }

    // MARK: 输入

    func apply(_ new: PagedReaderInput) {
        let chapterChanged = input?.chapterId != new.chapterId
        input = new
        if new.signature != signature {
            signature = new.signature
            // 换章：按这本书的进度锚点定位；同章内改字号 / 行距：留在当前这段
            didRestore = !chapterChanged && !pages.isEmpty
            needsRebuild = true
            rebuildIfNeeded()
        }
    }

    /// 正文区域：与滚动模式同样的留白（左右 20），底部给页码让位
    private var contentRect: CGRect {
        let safe = view.safeAreaInsets
        return view.bounds.inset(by: UIEdgeInsets(top: max(safe.top, 0) + 12,
                                                  left: 20,
                                                  bottom: max(safe.bottom, 0) + 34,
                                                  right: 20))
    }

    private func rebuildIfNeeded() {
        guard needsRebuild else { return }
        guard input != nil else { return }
        let rect = contentRect
        guard rect.width > 40, rect.height > 60 else { return }
        needsRebuild = false
        rebuild(rect)
    }

    private func rebuild(_ rect: CGRect) {
        guard let input else { return }
        let keepParagraph = nearestParagraph(at: currentIndex)

        // 整章只建一份 attributed：分页测量与逐页绘制共用，内存从「页数 × 全文」降到「1 × 全文」
        let attributed = TextPaginator.attributed(paragraphs: input.paragraphs,
                                                  fontSize: input.fontSize,
                                                  lineSpacing: input.lineSpacing)
        measureAttributed = attributed

        slices = TextPaginator.paginate(attributed: attributed,
                                        paragraphs: input.paragraphs,
                                        size: rect.size)

        var list: [ReaderPage] = slices.map { .text($0) }
        // 保持与滚动模式完全一致的内容顺序：正文 → 插图（含动图）→ 音视频
        for item in input.images { list.append(.image(item)) }
        for item in input.avMedia { list.append(.av(item)) }
        list.append(.footer)

        pages = list
        built = Array<UIViewController?>(repeating: nil, count: list.count)

        let target: Int
        if didRestore {
            target = TextPaginator.pageIndex(forParagraph: keepParagraph, in: slices)
        } else {
            target = TextPaginator.pageIndex(forParagraph: input.restoreParagraph, in: slices)
            didRestore = true
        }
        currentIndex = min(max(target, 0), max(pages.count - 1, 0))
        showCurrent(animated: false)
        updateLabel()
    }

    private func showCurrent(animated: Bool) {
        guard currentIndex >= 0, currentIndex < pages.count else { return }
        pager.setViewControllers([controller(at: currentIndex)],
                                 direction: .forward,
                                 animated: animated)
        trimBuilt(around: currentIndex)
    }

    /// 只保留当前页前后各 2 页的控制器：页越多常驻的视图越多，大文件会把内存吃满。
    /// 被释放的页需要时由 `controller(at:)` 重建，正文页共用同一份 attributed，重建很轻。
    private func trimBuilt(around index: Int) {
        guard !built.isEmpty else { return }
        for i in built.indices where abs(i - index) > 2 {
            built[i] = nil
        }
    }

    /// 当前页对应的段落；插图 / 音视频 / 章末页不产生段落锚点。
    ///
    /// 必须按 `pages` 取，不能拿 `currentIndex` 去索引 `slices`：`pages` 比 `slices`
    /// 多出插图、音视频和章末页，两者下标并不对应。此前用 `min(currentIndex, count-1)`
    /// 收敛，翻到正文之后的任意一页都会把锚点记成「最后一段」，
    /// 下次进这一章就定位到最后一页（问题就出在这里）。
    private var currentParagraph: Int? {
        guard currentIndex >= 0, currentIndex < pages.count else { return nil }
        if case .text(let slice) = pages[currentIndex] { return slice.paragraph }
        return nil
    }

    /// 从指定页往前找最近一个文字页的段落；用于换字号 / 换行距时保持位置
    private func nearestParagraph(at index: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        var i = min(max(index, 0), pages.count - 1)
        while i >= 0 {
            if case .text(let slice) = pages[i] { return slice.paragraph }
            i -= 1
        }
        return 0
    }

    // MARK: 页面构建

    private func controller(at index: Int) -> UIViewController {
        if index >= 0, index < built.count, let cached = built[index] { return cached }
        guard index >= 0, index < pages.count else { return UIViewController() }

        let vc: UIViewController
        switch pages[index] {
        case .text(let slice):
            // 共用 rebuild 时建好的那一份全文；缺失才兜底重建（正常不会走到）
            let attributed = measureAttributed
                ?? TextPaginator.attributed(paragraphs: input?.paragraphs ?? [],
                                            fontSize: input?.fontSize ?? 18,
                                            lineSpacing: input?.lineSpacing ?? 10)
            vc = TextPageController(attributed: attributed,
                                    slice: slice,
                                    textFrame: contentRect)
        case .image(let item):
            vc = hosting(ImagePageView(item: item) { [weak self] in
                self?.onTapMedia?(item)
            })
        case .av(let item):
            vc = hosting(MediaPageView(item: item,
                                       chapterId: input?.chapterId ?? "",
                                       boostRate: input?.boostRate ?? 2.0))
        case .footer:
            vc = hosting(FooterPageView(hasNext: input?.hasNextChapter ?? false,
                                        nextTitle: input?.nextTitle ?? "",
                                        isComic: input?.isComic ?? false,
                                        onOpenNext: { [weak self] in self?.onOpenNext?() }))
        }
        vc.view.backgroundColor = .systemBackground
        // 用 tag 记住页码：页缓存会被淘汰，翻页数据源仍要能认出这一页是第几页
        vc.view.tag = index + 1
        if index < built.count { built[index] = vc }
        return vc
    }

    private func hosting<V: View>(_ content: V) -> UIViewController {
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .systemBackground
        return controller
    }

    private func index(of controller: UIViewController) -> Int? {
        if let cached = built.firstIndex(where: { $0 === controller }) { return cached }
        // 缓存淘汰后靠 tag 反查（设置时是 index + 1，用 0 表示「未登记」）
        let index = controller.view.tag - 1
        guard index >= 0, index < pages.count else { return nil }
        return index
    }

    // MARK: 翻页

    private func goForward() {
        guard currentIndex + 1 < pages.count else { return }
        currentIndex += 1
        showCurrent(animated: true)
        afterPageChange()
    }

    private func goBackward() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        showCurrent(animated: true)
        afterPageChange()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: view).x
        let width = max(view.bounds.width, 1)
        if x < width * 0.28 {
            goBackward()
        } else if x > width * 0.72 {
            goForward()
        }
    }

    private func afterPageChange() {
        updateLabel()
        // 非文字页（插图 / 音视频 / 章末）不写锚点，避免把进度污染成「最后一段」
        if let paragraph = currentParagraph { onProgress?(paragraph) }
    }

    private func updateLabel() {
        guard !pages.isEmpty else {
            pageLabel.text = ""
            return
        }
        pageLabel.text = TextPaginator.progressText(page: currentIndex, total: pages.count)
    }
}

// MARK: - 翻页手势 / 数据源

extension PageTurnController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        // 只在文字页接收点击翻页；图片页要留给「点开全屏」，章末页要留给按钮
        guard currentIndex >= 0, currentIndex < pages.count else { return false }
        if case .text = pages[currentIndex] { return true }
        return false
    }
}

extension PageTurnController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let position = index(of: viewController), position > 0 else { return nil }
        return controller(at: position - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let position = index(of: viewController), position + 1 < pages.count else { return nil }
        return controller(at: position + 1)
    }
}

extension PageTurnController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController,
                            didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        guard completed,
              let current = pageViewController.viewControllers?.first,
              let position = index(of: current) else { return }
        currentIndex = position
        afterPageChange()
    }
}

// MARK: - 文字页（CoreText 绘制）

final class TextPageController: UIViewController {
    private let attributed: NSAttributedString
    private let slice: ReaderPageSlice
    private let textFrame: CGRect
    private let pageView = CoreTextPageView(frame: .zero)

    init(attributed: NSAttributedString, slice: ReaderPageSlice, textFrame: CGRect) {
        self.attributed = attributed
        self.slice = slice
        self.textFrame = textFrame
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        pageView.backgroundColor = .clear
        pageView.isOpaque = false
        pageView.attributed = attributed
        pageView.textRange = slice.range
        view.addSubview(pageView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pageView.frame = textFrame
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            pageView.setNeedsDisplay()
        }
    }
}

/// 只画 attributed string 里的一个字符区间；与分页时的测量尺寸完全一致
final class CoreTextPageView: UIView {
    var attributed: NSAttributedString?
    var textRange: NSRange?

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let attributed,
              let textRange,
              attributed.length > 0,
              bounds.width > 1, bounds.height > 1 else { return }

        let full = NSRange(location: 0, length: attributed.length)
        let visible = NSIntersectionRange(textRange, full)
        guard visible.length > 0 else { return }

        // 颜色已经在 TextPaginator.attributes 里写成 UIColor.label（动态色，按当前 trait 解析）。
        // 之前为「上色」在这里把整章文本复制一份 mutable，正文一长就是成倍的内存与 CPU，
        // 大文件进入阅读几秒内就被系统杀掉。现在直接画共享的那一份。
        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let path = CGPath(rect: CGRect(origin: .zero, size: bounds.size), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter,
                                             CFRange(location: visible.location,
                                                     length: visible.length),
                                             path, nil)

        context.saveGState()
        context.textMatrix = .identity
        // CoreText 原点在左下，UIKit 在左上
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}

// MARK: - 插图 / 音视频 / 章末页

private struct ImagePageView: View {
    let item: MediaItem
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            InlineMediaView(item: item, onTap: onTap)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MediaPageView: View {
    let item: MediaItem
    let chapterId: String
    let boostRate: Double

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            MediaAttachmentView(item: item, chapterId: chapterId, boostRate: boostRate)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FooterPageView: View {
    let hasNext: Bool
    let nextTitle: String
    let isComic: Bool
    let onOpenNext: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            if hasNext {
                Button(action: onOpenNext) {
                    VStack(spacing: 8) {
                        Text("下一章")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(nextTitle)
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.center)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                    Text(isComic ? "已是最后一话" : "已是最后一章")
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
