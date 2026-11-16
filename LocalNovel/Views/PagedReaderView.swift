import SwiftUI
import UIKit
import Foundation
import CoreText

// MARK: - 分页阅读器（仿真卷曲 / 滑动翻页）
//
// 结构：
//   PagedReaderView（SwiftUI 入口）
//     └ PagedBaseController（公共：分页、定位、页码、点击翻页）
//         ├ CurlPageController   —— UIPageViewController.pageCurl，纸张卷起
//         └ SlidePageController  —— UIScrollView 分页，整页跟手横移 + 页边阴影
//
// 两套引擎共用同一份排版与页面构建，切换只换「怎么呈现」：
//   · 分页仍然用 CoreText 测量，绘制与测量同一个 rect，不会出现末行被切；
//   · 阅读记忆沿用段落锚点 blk-pN，与滚动模式互通；
//   · 整章只保留一份 attributed，页面控制器按窗口装载，大文件不会把内存吃满。
//
// 定位规则（两处「跳到最后一页」的历史坑都在这）：
// 1) 只有在用户真正翻过页之后，才用「当前页」反推段落保持位置；
//    在这之前一直用传入的记忆段落。首帧尺寸不稳定时反复 rebuild 也不会把位置挤走。
// 2) 记忆段落在偏移前先按本章段落数收敛，越界值不再落到「最后一个「起始段落 ≤ 目标」的页」。

enum PageFlipStyle: Equatable {
    case curl
    case slide
}

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
    let style: PageFlipStyle

    /// 只有影响排版的参数变化才重建；restoreParagraph 故意不参与。
    /// 用 O(1) 的指纹（段数 + 首末段长度），不再遍历全部段落算总长：
    /// 几十万段的书每次 body 重算都做一次 NSString 桥接，主线程会被拖住。
    var signature: String {
        let head = paragraphs.first?.utf16.count ?? 0
        let tail = paragraphs.last?.utf16.count ?? 0
        return "\(chapterId)|\(paragraphs.count)|\(head)|\(tail)|\(fontSize)|\(lineSpacing)"
            + "|\(images.count)|\(avMedia.count)|\(hasNextChapter)|\(style == .curl ? "curl" : "slide")"
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
    /// 点屏幕中间 28%~72% 区域：弹出 / 收起阅读控制菜单
    let onTapCenter: () -> Void

    func makeUIViewController(context: Context) -> PagedBaseController {
        // 两种引擎都继承 PagedBaseController，SwiftUI 侧不必感知差异。
        // 切换阅读方式时 ReaderView 用 .id(pageTurn) 强制重建，所以这里不会中途换类型。
        let controller: PagedBaseController = input.style == .curl
            ? CurlPageController()
            : SlidePageController()
        wire(controller)
        controller.apply(input)
        return controller
    }

    func updateUIViewController(_ controller: PagedBaseController, context: Context) {
        wire(controller)
        controller.apply(input)
    }

    private func wire(_ controller: PagedBaseController) {
        controller.onProgress = onProgress
        controller.onTapMedia = onTapMedia
        controller.onOpenNext = onOpenNext
        controller.onTapCenter = onTapCenter
    }
}

// MARK: - 公共容器

class PagedBaseController: UIViewController {
    var onProgress: ((Int) -> Void)?
    var onTapMedia: ((MediaItem) -> Void)?
    var onOpenNext: (() -> Void)?
    var onTapCenter: (() -> Void)?

    private(set) var input: PagedReaderInput?
    private(set) var pages: [ReaderPage] = []
    private(set) var slices: [ReaderPageSlice] = []
    private(set) var currentIndex = 0
    /// 整章唯一的排版文本：所有文字页共用这一份，不再每页各建一份全文
    private(set) var measureAttributed: NSAttributedString?

    private var signature = ""
    private var contentSize: CGSize = .zero
    private var needsRebuild = true
    /// 记忆段落：用户翻页之前，每次 rebuild 都用它定位
    private var restoreParagraph = 0
    /// 用户是否已在本章内主动翻页（翻过之后才改为「保持当前页」）
    private var didNavigate = false
    private let pageLabel = UILabel()

    // MARK: 子类扩展点

    /// 把第 index 页显示出来
    func presentPage(at index: Int, animated: Bool) { _ = animated }
    /// 页面数组重建完成（子类在这里重排自己的容器）
    func didRebuildPages() {}

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

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
        view.addGestureRecognizer(tap)
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
        if chapterChanged {
            restoreParagraph = max(0, new.restoreParagraph)
            didNavigate = false
        }
        input = new
        if new.signature != signature {
            signature = new.signature
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
        guard needsRebuild, input != nil else { return }
        let rect = contentRect
        guard rect.width > 40, rect.height > 60 else { return }
        needsRebuild = false
        rebuild(rect)
    }

    private func rebuild(_ rect: CGRect) {
        guard let input else { return }

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

        // 定位：用户没翻过页 → 永远用记忆段落（尺寸变化不会把位置挤走）；
        // 翻过页 → 用当前页所在段落，字号 / 行距变化时原地不动。
        let anchor = didNavigate ? nearestParagraph(at: currentIndex) : restoreParagraph
        let target = TextPaginator.pageIndex(forParagraph: clampedParagraph(anchor), in: slices)
        currentIndex = min(max(target, 0), max(pages.count - 1, 0))

        didRebuildPages()
        updateLabel()
    }

    private func clampedParagraph(_ value: Int) -> Int {
        let count = input?.paragraphs.count ?? 0
        guard count > 0 else { return 0 }
        return min(max(value, 0), count - 1)
    }

    // MARK: 翻页

    /// 子类翻页后回调：把当前页同步到基类
    func adopt(_ index: Int) {
        guard index >= 0, index < pages.count else { return }
        currentIndex = index
        didNavigate = true
        afterPageChange()
    }

    func move(by delta: Int) {
        let target = min(max(currentIndex + delta, 0), max(pages.count - 1, 0))
        guard target != currentIndex else { return }
        currentIndex = target
        didNavigate = true
        presentPage(at: target, animated: true)
        afterPageChange()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)
        let width = max(view.bounds.width, 1)
        let x = point.x
        if x < width * 0.28 {
            move(by: -1)
        } else if x > width * 0.72 {
            move(by: 1)
        } else {
            // 中间区域：弹出 / 收起控制菜单（字号、行距、翻页、外观、目录）
            onTapCenter?()
        }
    }

    private func afterPageChange() {
        updateLabel()
        // 非文字页（插图 / 音视频 / 章末）不写锚点，避免把进度污染成「最后一段」
        if let paragraph = currentParagraph { onProgress?(paragraph) }
    }

    func updateLabel() {
        guard !pages.isEmpty else {
            pageLabel.text = ""
            return
        }
        pageLabel.text = TextPaginator.progressText(page: currentIndex, total: pages.count)
    }

    /// 拖动过程中按滚动偏移实时显示页码（松手后再校准）
    func previewLabel(page: Int) {
        guard !pages.isEmpty else { return }
        pageLabel.text = TextPaginator.progressText(page: page, total: pages.count)
    }

    /// 当前页对应的段落；插图 / 音视频 / 章末页不产生段落锚点。
    ///
    /// 必须按 `pages` 取，不能拿 `currentIndex` 去索引 `slices`：`pages` 比 `slices`
    /// 多出插图、音视频和章末页，两者下标并不对应。
    private var currentParagraph: Int? {
        guard currentIndex >= 0, currentIndex < pages.count else { return nil }
        if case .text(let slice) = pages[currentIndex] { return slice.paragraph }
        return nil
    }

    /// 从指定页往前找最近一个文字页的段落；用于换字号 / 换行距时保持位置
    func nearestParagraph(at index: Int) -> Int {
        guard !pages.isEmpty else { return restoreParagraph }
        var i = min(max(index, 0), pages.count - 1)
        while i >= 0 {
            if case .text(let slice) = pages[i] { return slice.paragraph }
            i -= 1
        }
        return 0
    }

    // MARK: 页面构建

    /// 按页码新建页面控制器（不缓存：由子类按自己的窗口策略决定生命周期）
    func makeController(at index: Int) -> UIViewController {
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
        // 用 tag 记住页码：容器淘汰页面后仍要能认出它是第几页
        vc.view.tag = index + 1
        return vc
    }

    private func hosting<V: View>(_ content: V) -> UIViewController {
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .systemBackground
        return controller
    }
}

// MARK: - 点击手势

extension PagedBaseController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        // 只在文字页接收点击翻页；图片页要留给「点开全屏」，章末页要留给按钮
        guard currentIndex >= 0, currentIndex < pages.count else { return false }
        if case .text = pages[currentIndex] { return true }
        return false
    }
}

// MARK: - 仿真卷曲

final class CurlPageController: PagedBaseController {
    private let pager = UIPageViewController(transitionStyle: .pageCurl,
                                             navigationOrientation: .horizontal,
                                             options: nil)
    /// 卷曲引擎需要数据源随时取相邻页，这里保留一个小窗口的缓存
    private var cache: [Int: UIViewController] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        pager.isDoubleSided = false
        pager.dataSource = self
        pager.delegate = self
        pager.view.backgroundColor = .systemBackground
        pager.view.clipsToBounds = true

        addChild(pager)
        pager.view.frame = view.bounds
        pager.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // 页码在最上层：插到 index 0，别盖住 label
        view.insertSubview(pager.view, at: 0)
        pager.didMove(toParent: self)
    }

    override func didRebuildPages() {
        cache.removeAll()
        show(index: currentIndex, animated: false)
    }

    override func presentPage(at index: Int, animated: Bool) {
        show(index: index, animated: animated)
    }

    private func show(index: Int, animated: Bool) {
        guard index >= 0, index < pages.count else { return }
        pager.setViewControllers([controller(at: index)],
                                 direction: .forward,
                                 animated: animated)
        trimCache(around: index)
    }

    private func controller(at index: Int) -> UIViewController {
        if let cached = cache[index] { return cached }
        let vc = makeController(at: index)
        cache[index] = vc
        return vc
    }

    /// 只保留当前页前后各两页：卷曲动画需要相邻页，但不必常驻整章
    private func trimCache(around index: Int) {
        for key in cache.keys where abs(key - index) > 2 {
            cache[key] = nil
        }
    }

    private func index(of controller: UIViewController) -> Int? {
        if let hit = cache.first(where: { $0.value === controller }) { return hit.key }
        let index = controller.view.tag - 1
        guard index >= 0, index < pages.count else { return nil }
        return index
    }
}

extension CurlPageController: UIPageViewControllerDataSource {
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

extension CurlPageController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController,
                            didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        guard completed,
              let current = pageViewController.viewControllers?.first,
              let position = index(of: current) else { return }
        adopt(position)
    }
}

// MARK: - 滑动翻页

/// 整页跟手横移：UIScrollView 分页 + 页边阴影。
///
/// 与卷曲引擎的区别只在呈现层，分页 / 定位 / 锚点全部复用基类，
/// 所以两种模式之间切换不会丢阅读位置。
final class SlidePageController: PagedBaseController {
    private let scroller = UIScrollView()
    private var hosts: [Int: PageHost] = [:]
    private var pageWidth: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        scroller.isPagingEnabled = true
        scroller.alwaysBounceHorizontal = true
        scroller.showsHorizontalScrollIndicator = false
        scroller.contentInsetAdjustmentBehavior = .never
        scroller.delegate = self
        scroller.backgroundColor = .systemBackground
        scroller.frame = view.bounds
        scroller.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(scroller, at: 0)
    }

    override func viewDidLayoutSubviews() {
        // 基类在这里触发分页（首次拿到真实尺寸后才算）
        super.viewDidLayoutSubviews()

        scroller.frame = view.bounds
        let width = max(view.bounds.width, 1)
        let height = max(view.bounds.height, 1)
        let widthChanged = abs(width - pageWidth) > 0.5
        pageWidth = width

        guard !pages.isEmpty else {
            scroller.contentSize = view.bounds.size
            return
        }
        scroller.contentSize = CGSize(width: width * CGFloat(pages.count), height: height)
        for (index, host) in hosts {
            host.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: height)
        }
        if widthChanged {
            jump(to: currentIndex)
            load(around: currentIndex)
        }
    }

    override func didRebuildPages() {
        hosts.values.forEach { detach($0) }
        hosts.removeAll()
        let width = max(view.bounds.width, 1)
        let height = max(view.bounds.height, 1)
        pageWidth = width
        scroller.contentSize = CGSize(width: width * CGFloat(max(pages.count, 1)), height: height)
        jump(to: currentIndex)
        load(around: currentIndex)
        updateLabel()
    }

    override func presentPage(at index: Int, animated: Bool) {
        guard index >= 0, index < pages.count else { return }
        load(around: index)
        scroller.setContentOffset(CGPoint(x: CGFloat(index) * pageWidth, y: 0),
                                  animated: animated)
        if !animated { updateLabel() }
    }

    private func jump(to index: Int) {
        guard index >= 0, index < pages.count, pageWidth > 0 else { return }
        scroller.setContentOffset(CGPoint(x: CGFloat(index) * pageWidth, y: 0), animated: false)
    }

    // MARK: 页面窗口化

    /// 只装载当前页前后各一页：整章几百页全建出来会直接吃掉几百 MB
    private func load(around index: Int) {
        guard !pages.isEmpty else { return }
        let center = min(max(index, 0), pages.count - 1)
        let lower = max(0, center - 1)
        let upper = min(pages.count - 1, center + 1)
        guard lower <= upper else { return }
        for i in lower...upper { ensureHost(i) }
        evict(except: lower...upper)
    }

    private func ensureHost(_ index: Int) {
        guard index >= 0, index < pages.count, hosts[index] == nil else { return }
        let host = PageHost(index: index)
        host.frame = CGRect(x: CGFloat(index) * pageWidth,
                            y: 0,
                            width: pageWidth,
                            height: max(view.bounds.height, 1))
        host.backgroundColor = .systemBackground

        let vc = makeController(at: index)
        addChild(vc)
        vc.view.frame = host.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(vc.view)
        vc.didMove(toParent: self)
        host.child = vc
        host.installEdgeShadows()

        scroller.addSubview(host)
        hosts[index] = host
    }

    private func evict(except range: ClosedRange<Int>) {
        for (index, host) in hosts where !range.contains(index) {
            detach(host)
            hosts[index] = nil
        }
    }

    private func detach(_ host: PageHost) {
        if let child = host.child {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
            host.child = nil
        }
        host.removeFromSuperview()
    }

    private func indexFromOffset() -> Int {
        guard pageWidth > 0 else { return 0 }
        let raw = (scroller.contentOffset.x / pageWidth).rounded()
        return min(max(Int(raw), 0), max(pages.count - 1, 0))
    }
}

extension SlidePageController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard pageWidth > 0, !pages.isEmpty else { return }
        let index = indexFromOffset()
        load(around: index)
        // 拖动 / 减速中实时显示页码，松手后 settle 再校准
        if scrollView.isDragging || scrollView.isDecelerating {
            previewLabel(page: index)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settle()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        settle()
    }

    private func settle() {
        guard pageWidth > 0, !pages.isEmpty else { return }
        let index = indexFromOffset()
        if index != currentIndex {
            adopt(index)
        } else {
            updateLabel()
        }
    }
}

/// 滑动翻页里的一页：承载子控制器的视图 + 左右页边阴影
private final class PageHost: UIView {
    let index: Int
    var child: UIViewController?

    private let shadowWidth: CGFloat = 12
    private let leftEdge = CAGradientLayer()
    private let rightEdge = CAGradientLayer()

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func installEdgeShadows() {
        leftEdge.name = "edge.left"
        leftEdge.colors = [UIColor.black.withAlphaComponent(0.16).cgColor,
                           UIColor.clear.cgColor]
        leftEdge.startPoint = CGPoint(x: 0, y: 0.5)
        leftEdge.endPoint = CGPoint(x: 1, y: 0.5)

        rightEdge.name = "edge.right"
        rightEdge.colors = [UIColor.clear.cgColor,
                            UIColor.black.withAlphaComponent(0.16).cgColor]
        rightEdge.startPoint = CGPoint(x: 0, y: 0.5)
        rightEdge.endPoint = CGPoint(x: 1, y: 0.5)

        layer.addSublayer(leftEdge)
        layer.addSublayer(rightEdge)
        layoutShadows()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutShadows()
    }

    private func layoutShadows() {
        leftEdge.frame = CGRect(x: 0, y: 0, width: shadowWidth, height: bounds.height)
        rightEdge.frame = CGRect(x: max(bounds.width - shadowWidth, 0),
                                 y: 0,
                                 width: shadowWidth,
                                 height: bounds.height)
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
