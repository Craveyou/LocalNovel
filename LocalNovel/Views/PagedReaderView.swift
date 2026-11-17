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
// 章末续章：本章最后一页再往后翻 = 下一章（章末没有「下一章」按钮，也不再有章末空白页）。
//   滑动：末页继续右拖过阈值；卷曲：末页左滑；点击：末页点右侧。
//   三个入口都收在 PagedBaseController.advanceToNextChapter，一次翻页只切一次。
//
// 定位规则（两处「跳到最后一页」的历史坑都在这）：
// 1) 只有在用户真正翻过页之后，才用「当前页」反推段落保持位置；
//    在这之前一直用传入的记忆段落。首帧尺寸不稳定时反复 rebuild 也不会把位置挤走。
// 2) 记忆段落在偏移前先按本章段落数收敛，越界值不再落到「最后一个「起始段落 ≤ 目标」的页」。

enum PageFlipStyle: Equatable {
    case curl      // 仿真卷曲
    case slide     // 整页跟手横移
    case cover     // 覆盖：新页从右侧压上来，旧页不动
    case vertical  // 整页纵向吸附
    case none      // 无动画：直接换页

    /// 存进阅读指纹 / 用于 SwiftUI 侧 .id 重建
    var key: String {
        switch self {
        case .curl:     return "curl"
        case .slide:    return "slide"
        case .cover:    return "cover"
        case .vertical: return "vertical"
        case .none:     return "none"
        }
    }
}

struct PagedReaderInput {
    let chapterId: String
    let paragraphs: [String]
    let images: [MediaItem]
    let avMedia: [MediaItem]
    /// 一次排版的全套参数（字号 / 字体 / 字重 / 各种间距 / 对齐 / 缩进 / 标题样式）
    let typography: ReaderTypography
    /// 当前主题（正文色 / 背景色 / 页码色 / 背景图）
    let theme: ReaderTheme
    /// 本章标题（作为正文前的标题块参与排版）
    let title: String
    /// 书名（页眉可选展示）
    let bookTitle: String
    let restoreParagraph: Int
    /// 本章后面还有没有章：决定「末页继续翻」是切下一章还是停住
    let hasNextChapter: Bool
    let isComic: Bool
    let boostRate: Double
    let style: PageFlipStyle
    let headerMode: ReaderHeaderMode
    let footerMode: ReaderFooterMode
    let headerTopPadding: CGFloat
    let footerBottomPadding: CGFloat
    /// 覆盖翻页的动画时长（秒）；0 = 不动画
    let flipDuration: Double

    /// 只有影响排版的参数变化才重建；restoreParagraph 故意不参与。
    /// 用 O(1) 的指纹（段数 + 首末段长度），不再遍历全部段落算总长：
    /// 几十万段的书每次 body 重算都做一次 NSString 桥接，主线程会被拖住。
    var signature: String {
        let head = paragraphs.first?.utf16.count ?? 0
        let tail = paragraphs.last?.utf16.count ?? 0
        return "\(chapterId)|\(paragraphs.count)|\(head)|\(tail)|\(typography.identity)"
            + "|\(theme.hashValue)|\(title)|\(bookTitle)"
            + "|\(headerMode.rawValue)|\(footerMode.rawValue)|\(headerTopPadding)|\(footerBottomPadding)"
            + "|\(images.count)|\(avMedia.count)|\(hasNextChapter)|\(style.key)"
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
        let controller: PagedBaseController
        switch input.style {
        case .curl:     controller = CurlPageController()
        case .slide:    controller = SlidePageController()
        case .cover:    controller = CoverPageController()
        case .vertical: controller = VerticalPageController()
        case .none:     controller = InstantPageController()
        }
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
    /// 主题底色：子类容器与每个页面都用它，避免分页容器露出系统白/黑底
    var themeBackgroundColor: UIColor {
        input?.theme.uiBackgroundColor ?? .systemBackground
    }
    /// 整章唯一的排版文本：所有文字页共用这一份，不再每页各建一份全文
    private(set) var measureAttributed: NSAttributedString?

    private var signature = ""
    private var contentSize: CGSize = .zero
    private var needsRebuild = true
    /// 记忆段落：用户翻页之前，每次 rebuild 都用它定位
    private var restoreParagraph = 0
    /// 用户是否已在本章内主动翻页（翻过之后才改为「保持当前页」）
    private var didNavigate = false
    /// 是否已经把「翻到底」换成切章：一次翻页只切一次，等上层重建本控制器
    private var nextTriggered = false
    /// 页脚：页码 / 百分比
    private let pageLabel = UILabel()
    /// 页眉：章节名 / 书名
    private let headerLabel = UILabel()
    /// 主题背景图（只有主题配了图才加）
    private let backgroundImageView = UIImageView()
    /// 页面容器：夹在背景图与页眉页脚之间，方便「覆盖 / 无动画」这类引擎自己管理层级
    let pageContainer = UIView()

    // MARK: 子类扩展点

    /// 把第 index 页显示出来
    func presentPage(at index: Int, animated: Bool) { _ = animated }
    /// 页面数组重建完成（子类在这里重排自己的容器）
    func didRebuildPages() {}
    /// 主题换色（子类把容器底色也一起刷掉，否则换主题时容器会闪一下系统色）
    func themeDidChange() {}

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.isHidden = true
        view.addSubview(backgroundImageView)

        pageContainer.frame = view.bounds
        pageContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pageContainer.backgroundColor = .clear
        view.addSubview(pageContainer)

        for label in [headerLabel, pageLabel] {
            label.font = .systemFont(ofSize: 12, weight: .regular)
            label.textAlignment = .center
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            view.addSubview(label)
        }
        pageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutChrome()
        if contentRect.size != contentSize {
            contentSize = contentRect.size
            needsRebuild = true
        }
        rebuildIfNeeded()
    }

    /// 页眉 / 页脚 / 背景图的位置（跟 safeArea 与用户设的间距走）
    private func layoutChrome() {
        backgroundImageView.frame = view.bounds
        pageContainer.frame = view.bounds
        let safe = view.safeAreaInsets
        let side = max(input?.typography.horizontalPadding ?? 20, 8)
        let width = max(view.bounds.width - side * 2, 10)
        let headerTop = max(safe.top, 0) + (input?.headerTopPadding ?? 8)
        let footerBottom = max(safe.bottom, 0) + (input?.footerBottomPadding ?? 6)
        headerLabel.frame = CGRect(x: side, y: headerTop, width: width, height: 16)
        pageLabel.frame = CGRect(x: side,
                                 y: view.bounds.height - footerBottom - 16,
                                 width: width,
                                 height: 16)
    }

    /// 主题换色：容器底色 / 页眉页脚色 / 背景图
    private func applyThemeChrome() {
        guard let theme = input?.theme else { return }
        view.backgroundColor = theme.uiBackgroundColor
        headerLabel.textColor = theme.uiHeaderFooterColor
        pageLabel.textColor = theme.uiPageIndexColor

        if let name = theme.backgroundImage,
           let image = ReaderBackgroundImage.load(name) {
            backgroundImageView.image = image
            backgroundImageView.isHidden = false
            switch theme.backgroundImageMode {
            case 1: backgroundImageView.contentMode = .scaleAspectFit
            case 2: backgroundImageView.contentMode = .scaleToFill
            default: backgroundImageView.contentMode = .scaleAspectFill
            }
            view.sendSubviewToBack(backgroundImageView)
        } else {
            backgroundImageView.image = nil
            backgroundImageView.isHidden = true
        }
        themeDidChange()
    }

    // MARK: 输入

    func apply(_ new: PagedReaderInput) {
        let chapterChanged = input?.chapterId != new.chapterId
        if chapterChanged {
            restoreParagraph = max(0, new.restoreParagraph)
            didNavigate = false
            nextTriggered = false
        }
        input = new
        applyThemeChrome()
        if new.signature != signature {
            signature = new.signature
            needsRebuild = true
            rebuildIfNeeded()
        }
        updateLabel()
    }

    /// 正文区域：左右留白 / 页眉页脚高度都跟设置走
    private var contentRect: CGRect {
        let safe = view.safeAreaInsets
        let side = max(input?.typography.horizontalPadding ?? 20, 4)
        let headerExtra: CGFloat = (input?.headerMode ?? .none) == .none
            ? 0 : 16 + (input?.headerTopPadding ?? 8) + 4
        let footerExtra: CGFloat = (input?.footerMode ?? .page) == .none
            ? 0 : 16 + (input?.footerBottomPadding ?? 6) + 4
        return view.bounds.inset(by: UIEdgeInsets(top: max(safe.top, 0) + 12 + headerExtra,
                                                  left: side,
                                                  bottom: max(safe.bottom, 0) + 8 + footerExtra,
                                                  right: side))
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

        // 整章只建一份 attributed：分页测量与逐页绘制共用，内存从「页数 × 全文」降到「1 × 全文」。
        // 章节标题作为正文前的标题块拼进来（有自己的字号 / 颜色 / 上下间距），
        // 这样标题会自然出现在第一页顶部，而不是另起一页或干脆不显示。
        let body = TextPaginator.attributed(paragraphs: input.paragraphs,
                                            typography: input.typography,
                                            theme: input.theme)
        let combined = NSMutableAttributedString()
        var titleOffset = 0
        if let titleAttr = TextPaginator.titleAttributed(title: input.title,
                                                         typography: input.typography,
                                                         theme: input.theme) {
            combined.append(titleAttr)
            combined.append(NSAttributedString(string: "\n"))
            titleOffset = combined.length
        }
        combined.append(body)
        measureAttributed = combined

        slices = TextPaginator.paginate(attributed: combined,
                                        paragraphs: input.paragraphs,
                                        size: rect.size,
                                        titleOffset: titleOffset)

        var list: [ReaderPage] = slices.map { .text($0) }
        // 保持与滚动模式完全一致的内容顺序：正文 → 插图（含动图）→ 音视频
        for item in input.images { list.append(.image(item)) }
        for item in input.avMedia { list.append(.av(item)) }
        // 有下一章时不再插「章末页」：本章最后一页再往后翻就直接进下一章
        // （以前这里会多出一页，上面挂着「下一章」按钮，翻到底要先过一页空页）
        if !input.hasNextChapter { list.append(.footer) }
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
        // 章尾继续往后翻：不留在本页，直接进下一章（点右侧翻页也走这里）
        if delta > 0, advanceToNextChapter() { return }
        let target = min(max(currentIndex + delta, 0), max(pages.count - 1, 0))
        guard target != currentIndex else { return }
        currentIndex = target
        didNavigate = true
        presentPage(at: target, animated: true)
        afterPageChange()
    }

    /// 本章已经翻到最后一页、还要继续往后翻：交给上层切到下一章。
    ///
    /// 返回 true 表示这一次翻页已被「下一章」接管，子类不要再做本地翻页
    /// （否则会先在本章内弹回末页，再被切章覆盖，看起来像卡了一下）。
    /// 章末已经没有「下一章」按钮，翻到底就是续章，这里是唯一的入口。
    @discardableResult
    func advanceToNextChapter(at position: Int? = nil) -> Bool {
        let index = position ?? currentIndex
        guard !pages.isEmpty,
              index >= pages.count - 1,
              input?.hasNextChapter == true,
              !nextTriggered else { return false }
        nextTriggered = true
        onOpenNext?()
        return true
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
        headerLabel.text = headerText
        pageLabel.text = pages.isEmpty ? "" : footerText(page: currentIndex)
    }

    /// 拖动过程中按滚动偏移实时显示页码（松手后再校准）
    func previewLabel(page: Int) {
        guard !pages.isEmpty else { return }
        pageLabel.text = footerText(page: page)
    }

    private var headerText: String {
        guard let mode = input?.headerMode else { return "" }
        switch mode {
        case .chapter: return input?.title ?? ""
        case .book:    return input?.bookTitle ?? ""
        case .none:    return ""
        }
    }

    private func footerText(page: Int) -> String {
        guard let mode = input?.footerMode else { return "" }
        switch mode {
        case .percent: return TextPaginator.percentText(page: page, total: pages.count)
        case .none:    return ""
        case .page:    return TextPaginator.progressText(page: page, total: pages.count)
        }
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
                                            typography: input?.typography ?? ReaderTypography.fallback,
                                            theme: input?.theme ?? ReaderTheme.fallback)
            vc = TextPageController(attributed: attributed,
                                    slice: slice,
                                    textFrame: contentRect,
                                    background: themeBackgroundColor)
        case .image(let item):
            vc = hosting(ImagePageView(item: item) { [weak self] in
                self?.onTapMedia?(item)
            })
        case .av(let item):
            vc = hosting(MediaPageView(item: item,
                                       chapterId: input?.chapterId ?? "",
                                       boostRate: input?.boostRate ?? 2.0))
        case .footer:
            vc = hosting(FooterPageView(isComic: input?.isComic ?? false))
        }
        vc.view.backgroundColor = input?.theme.uiBackgroundColor ?? .systemBackground
        // 用 tag 记住页码：容器淘汰页面后仍要能认出它是第几页
        vc.view.tag = index + 1
        return vc
    }

    private func hosting<V: View>(_ content: V) -> UIViewController {
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = input?.theme.uiBackgroundColor ?? .systemBackground
        return controller
    }
}

// MARK: - 点击手势

extension PagedBaseController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        // 「末页左滑进下一章」「覆盖翻页的跟手拖拽」不受下面这条限制：
        // 末页可能是插图 / 音视频页，也照样要能翻
        if gestureRecognizer is UISwipeGestureRecognizer { return true }
        if gestureRecognizer is UIPanGestureRecognizer { return true }
        // 只在文字页接收点击翻页；图片页要留给「点开全屏」，章末页要留给按钮
        guard currentIndex >= 0, currentIndex < pages.count else { return false }
        if case .text = pages[currentIndex] { return true }
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // 卷曲引擎的翻页由 UIPageViewController 内部的 pan 处理，
        // 末页左滑必须能和它共存，否则两个手势互相打断
        true
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
        pager.view.backgroundColor = themeBackgroundColor
        pager.view.clipsToBounds = true

        addChild(pager)
        pager.view.frame = view.bounds
        pager.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // 页码在最上层：插到 index 0，别盖住 label
        view.insertSubview(pager.view, at: 0)
        pager.didMove(toParent: self)

        // 翻到末页后数据源不再给「下一页」，UIPageViewController 到这里手感就是顶住。
        // 补一个左滑识别补上这段路：只在末页生效，用来进下一章。
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeLeft))
        swipe.direction = .left
        swipe.delegate = self
        // 不吞触摸，卷曲自己的 pan 照常工作
        swipe.cancelsTouchesInView = false
        view.addGestureRecognizer(swipe)
    }

    /// 末页左滑 = 下一章
    @objc private func handleSwipeLeft() {
        _ = advanceToNextChapter()
    }

    override func didRebuildPages() {
        cache.removeAll()
        show(index: currentIndex, animated: false)
    }

    override func themeDidChange() {
        pager.view.backgroundColor = themeBackgroundColor
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
class SlidePageController: PagedBaseController {
    private let scroller = UIScrollView()
    private var hosts: [Int: PageHost] = [:]
    /// 一页在滚动方向上的长度（横向 = 宽，纵向 = 高）
    private var pageExtent: CGFloat = 0
    /// 上下翻页：同一个引擎换成纵轴吸附，分页 / 锚点 / 页码全部复用
    var isVertical: Bool { false }
    /// 末页继续往外拖出去的最大距离（松手才判定，避免手势中途反复触发）
    private var overflow: CGFloat = 0
    /// 本次拖动是从第几页开始的：只认「本来就在末页又继续往外拉」，
    /// 快速连翻甩到末页那一下不算（那种情况用户还在找页，不是要换章）
    private var dragStartIndex = 0
    /// 末页再拖出去这么多就切下一章：小了不起作用，易误触；太大拉不出来
    private let nextChapterThreshold: CGFloat = 72

    override func viewDidLoad() {
        super.viewDidLoad()
        scroller.isPagingEnabled = true
        scroller.alwaysBounceHorizontal = !isVertical
        scroller.alwaysBounceVertical = isVertical
        scroller.showsHorizontalScrollIndicator = false
        scroller.showsVerticalScrollIndicator = false
        scroller.contentInsetAdjustmentBehavior = .never
        scroller.delegate = self
        scroller.backgroundColor = themeBackgroundColor
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
        let extent = isVertical ? height : width
        let extentChanged = abs(extent - pageExtent) > 0.5
        pageExtent = extent

        guard !pages.isEmpty else {
            scroller.contentSize = view.bounds.size
            return
        }
        scroller.contentSize = isVertical
            ? CGSize(width: width, height: height * CGFloat(pages.count))
            : CGSize(width: width * CGFloat(pages.count), height: height)
        for (index, host) in hosts {
            host.frame = isVertical
                ? CGRect(x: 0, y: CGFloat(index) * height, width: width, height: height)
                : CGRect(x: CGFloat(index) * width, y: 0, width: width, height: height)
        }
        if extentChanged {
            jump(to: currentIndex)
            load(around: currentIndex)
        }
    }

    override func didRebuildPages() {
        hosts.values.forEach { detach($0) }
        hosts.removeAll()
        let width = max(view.bounds.width, 1)
        let height = max(view.bounds.height, 1)
        pageExtent = isVertical ? height : width
        scroller.contentSize = isVertical
            ? CGSize(width: width, height: height * CGFloat(max(pages.count, 1)))
            : CGSize(width: width * CGFloat(max(pages.count, 1)), height: height)
        jump(to: currentIndex)
        load(around: currentIndex)
        updateLabel()
    }

    override func themeDidChange() {
        scroller.backgroundColor = themeBackgroundColor
        for host in hosts.values { host.backgroundColor = themeBackgroundColor }
    }

    override func presentPage(at index: Int, animated: Bool) {
        guard index >= 0, index < pages.count else { return }
        load(around: index)
        scroller.setContentOffset(offset(for: index), animated: animated)
        if !animated { updateLabel() }
    }

    private func jump(to index: Int) {
        guard index >= 0, index < pages.count, pageExtent > 0 else { return }
        scroller.setContentOffset(offset(for: index), animated: false)
    }

    private func offset(for index: Int) -> CGPoint {
        isVertical
            ? CGPoint(x: 0, y: CGFloat(index) * pageExtent)
            : CGPoint(x: CGFloat(index) * pageExtent, y: 0)
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
        let height = max(view.bounds.height, 1)
        let width = max(view.bounds.width, 1)
        host.frame = isVertical
            ? CGRect(x: 0, y: CGFloat(index) * pageExtent, width: width, height: height)
            : CGRect(x: CGFloat(index) * pageExtent, y: 0, width: width, height: height)
        host.backgroundColor = themeBackgroundColor

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
        guard pageExtent > 0 else { return 0 }
        let value = isVertical ? scroller.contentOffset.y : scroller.contentOffset.x
        let raw = (value / pageExtent).rounded()
        return min(max(Int(raw), 0), max(pages.count - 1, 0))
    }
}

extension SlidePageController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        overflow = 0
        dragStartIndex = indexFromOffset()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard pageExtent > 0, !pages.isEmpty else { return }
        // 贴在末页还继续往外拖：记下最大越界距离。
        // 只有内容的右边缘会越界，所以拖到中间页时这里恒为 0，不会误判。
        // 上下翻页不做「拖到底换章」（纵向到底本来就是滚到章末，容易误触）。
        if !isVertical {
            let maxOffset = max(scroller.contentSize.width - scroller.bounds.width, 0)
            overflow = max(overflow, scroller.contentOffset.x - maxOffset)
        }

        let index = indexFromOffset()
        load(around: index)
        // 拖动 / 减速中实时显示页码，松手后 settle 再校准
        if scrollView.isDragging || scrollView.isDecelerating {
            previewLabel(page: index)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // 回弹本身就是一次减速动画：等它走完再判定，不然拿到的是越界中的偏移
        if !decelerate { _ = finishDrag() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if !finishDrag() { settle() }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        settle()
    }

    /// 松手后判定：从末页继续往外拉过阈值 → 进下一章。返回 true 表示已切章
    private func finishDrag() -> Bool {
        let dragged = overflow
        let startedAtEnd = dragStartIndex >= pages.count - 1
        overflow = 0
        guard dragged >= nextChapterThreshold, startedAtEnd else { return false }
        return advanceToNextChapter(at: indexFromOffset())
    }

    private func settle() {
        guard pageExtent > 0, !pages.isEmpty else { return }
        let index = indexFromOffset()
        if index != currentIndex {
            adopt(index)
        } else {
            updateLabel()
        }
    }
}

/// 上下翻页：与滑动翻页同一个引擎，只把轴换成纵向。
/// 千阅的「上下」是整页吸附（不是连续滚动），所以复用分页切片而不是滚动视图。
final class VerticalPageController: SlidePageController {
    override var isVertical: Bool { true }
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

// MARK: - 覆盖翻页

/// 覆盖翻页：新页从右侧压上来，旧页不动；往回翻则旧页滑走、露出上一页。
/// 手势自己接管（UIPanGestureRecognizer），松手按位移 / 速度决定翻页还是回弹。
/// 分页、锚点、页码、章末续章全部复用基类，只换「怎么呈现」。
final class CoverPageController: PagedBaseController {
    private var currentVC: UIViewController?
    private var incomingVC: UIViewController?
    private var incomingIndex: Int?
    private var direction = 0
    private var prepared = false

    private var duration: Double { max(0, input?.flipDuration ?? 0.28) }

    override func viewDidLoad() {
        super.viewDidLoad()
        pageContainer.clipsToBounds = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
    }

    override func didRebuildPages() {
        removeCurrent()
        install(index: currentIndex)
    }

    override func presentPage(at index: Int, animated: Bool) {
        guard index >= 0, index < pages.count, index != currentIndex else { return }
        if animated && duration > 0 {
            slide(to: index)
        } else {
            removeCurrent()
            install(index: index)
            updateLabel()
        }
    }

    // MARK: 页面装载

    private func install(index: Int) {
        guard index >= 0, index < pages.count else { return }
        let vc = makeController(at: index)
        addChild(vc)
        vc.view.frame = pageContainer.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pageContainer.addSubview(vc.view)
        vc.didMove(toParent: self)
        currentVC = vc
    }

    private func removeCurrent() {
        guard let vc = currentVC else { return }
        vc.willMove(toParent: nil)
        vc.view.removeFromSuperview()
        vc.removeFromParent()
        currentVC = nil
    }

    private func dropIncoming() {
        guard let vc = incomingVC else { return }
        vc.willMove(toParent: nil)
        vc.view.removeFromSuperview()
        vc.removeFromParent()
        incomingVC = nil
        incomingIndex = nil
        prepared = false
        direction = 0
    }

    /// 收尾：把新页扶正、旧页移除、同步页码
    private func commit() {
        guard let incoming = incomingVC, let index = incomingIndex else { return }
        removeCurrent()
        incoming.view.frame = pageContainer.bounds
        incoming.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        currentVC = incoming
        incomingVC = nil
        incomingIndex = nil
        prepared = false
        direction = 0
        adopt(index)
    }

    /// 点击翻页的动效（没有跟手过程，直接一段动画）
    private func slide(to index: Int) {
        let forward = index > currentIndex
        let width = max(pageContainer.bounds.width, 1)
        let vc = makeController(at: index)
        addChild(vc)
        vc.view.frame = forward
            ? pageContainer.bounds.offsetBy(dx: width, dy: 0)
            : pageContainer.bounds
        vc.view.autoresizingMask = []
        if forward {
            pageContainer.addSubview(vc.view)
        } else {
            pageContainer.insertSubview(vc.view, at: 0)
        }
        vc.didMove(toParent: self)
        incomingVC = vc
        incomingIndex = index
        prepared = true
        direction = forward ? 1 : -1

        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut]) {
            if forward {
                vc.view.frame = self.pageContainer.bounds
            } else {
                self.currentVC?.view.frame = self.pageContainer.bounds.offsetBy(dx: width, dy: 0)
            }
        } completion: { _ in
            self.commit()
        }
    }

    // MARK: 手势

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let dx = gesture.translation(in: view).x
        switch gesture.state {
        case .began:
            direction = 0
            prepared = false
        case .changed:
            if !prepared {
                guard abs(dx) > 6 else { return }
                prepare(direction: dx < 0 ? 1 : -1)
            }
            guard prepared else { return }
            apply(dx: dx)
        case .ended, .cancelled, .failed:
            finish(dx: dx, velocity: gesture.velocity(in: view).x)
        default:
            break
        }
    }

    private func prepare(direction dir: Int) {
        let target = currentIndex + dir
        guard dir != 0, target >= 0, target < pages.count else {
            direction = 0
            prepared = false
            return
        }
        direction = dir
        let width = max(pageContainer.bounds.width, 1)
        let vc = makeController(at: target)
        addChild(vc)
        vc.view.frame = dir > 0
            ? pageContainer.bounds.offsetBy(dx: width, dy: 0)
            : pageContainer.bounds
        vc.view.autoresizingMask = []
        if dir > 0 {
            pageContainer.addSubview(vc.view)
        } else {
            pageContainer.insertSubview(vc.view, at: 0)
        }
        vc.didMove(toParent: self)
        incomingVC = vc
        incomingIndex = target
        prepared = true
    }

    private func apply(dx: CGFloat) {
        guard let incoming = incomingVC else { return }
        let width = max(pageContainer.bounds.width, 1)
        if direction > 0 {
            // 新页跟手从右侧压进来
            let offset = min(max(dx, -width), 0)
            incoming.view.frame = pageContainer.bounds.offsetBy(dx: width + offset, dy: 0)
        } else {
            // 旧页跟手往右滑走，露出上一页
            let offset = max(min(dx, width), 0)
            currentVC?.view.frame = pageContainer.bounds.offsetBy(dx: offset, dy: 0)
        }
    }

    private func finish(dx: CGFloat, velocity: CGFloat) {
        guard prepared, let incoming = incomingVC else {
            dropIncoming()
            return
        }
        let width = max(pageContainer.bounds.width, 1)
        let passed = direction > 0
            ? (dx < -width * 0.28 || velocity < -700)
            : (dx > width * 0.28 || velocity > 700)
        let duration = self.duration
        UIView.animate(withDuration: passed ? duration : duration * 0.7,
                       delay: 0,
                       options: [.curveEaseOut]) {
            if passed {
                if self.direction > 0 {
                    incoming.view.frame = self.pageContainer.bounds
                } else {
                    self.currentVC?.view.frame = self.pageContainer.bounds.offsetBy(dx: width, dy: 0)
                }
            } else {
                if self.direction > 0 {
                    incoming.view.frame = self.pageContainer.bounds.offsetBy(dx: width, dy: 0)
                } else {
                    self.currentVC?.view.frame = self.pageContainer.bounds
                }
            }
        } completion: { _ in
            if passed {
                self.commit()
            } else {
                self.dropIncoming()
            }
        }
    }
}

// MARK: - 无动画翻页

/// 无动画：左右滑 / 点左右边缘直接换页，中间不跟手、不加过渡。
/// 适合「只想快速看字」的人，也顺手把章末续章保留下来。
final class InstantPageController: PagedBaseController {
    private var currentVC: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        pageContainer.clipsToBounds = true
        for dir in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = dir
            swipe.delegate = self
            swipe.cancelsTouchesInView = false
            view.addGestureRecognizer(swipe)
        }
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        move(by: gesture.direction == .left ? 1 : -1)
    }

    override func didRebuildPages() {
        install(index: currentIndex)
    }

    override func presentPage(at index: Int, animated: Bool) {
        install(index: index)
        updateLabel()
    }

    private func install(index: Int) {
        guard index >= 0, index < pages.count else { return }
        currentVC?.willMove(toParent: nil)
        currentVC?.view.removeFromSuperview()
        currentVC?.removeFromParent()

        let vc = makeController(at: index)
        addChild(vc)
        vc.view.frame = pageContainer.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pageContainer.addSubview(vc.view)
        vc.didMove(toParent: self)
        currentVC = vc
    }
}

// MARK: - 文字页（CoreText 绘制）

final class TextPageController: UIViewController {
    private let attributed: NSAttributedString
    private let slice: ReaderPageSlice
    private let textFrame: CGRect
    private let background: UIColor
    private let pageView = CoreTextPageView(frame: .zero)

    init(attributed: NSAttributedString, slice: ReaderPageSlice, textFrame: CGRect,
         background: UIColor = .systemBackground) {
        self.attributed = attributed
        self.slice = slice
        self.textFrame = textFrame
        self.background = background
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 底色跟主题走：主题底色 + 主题正文色，不再依赖系统的动态色
        view.backgroundColor = background
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

/// 整本最后一章的收尾页。
/// 有下一章时不再生成这一页：本章最后一页再往后翻就直接进下一章。
private struct FooterPageView: View {
    let isComic: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.title3)
            Text(isComic ? "已是最后一话" : "已是最后一章")
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
