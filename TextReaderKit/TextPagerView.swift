import SwiftUI
import UIKit

/// UIKit 分页器宿主：对齐主 App「页码即状态」模型。
/// 翻页模式映射：
///   仿真 = pageCurl / 平移·覆盖 = scroll（系统无覆盖过渡，近似）/
///   上下 = 竖向 scroll / 无 = 仅点击翻页不播动画。
/// 点击区域手势直接挂在宿主视图上，不遮挡 UIPageViewController 的滑动手势。
struct TextPagerView: UIViewControllerRepresentable {
    @EnvironmentObject private var session: TextReaderSession
    let theme: TextTheme
    let onTapMenu: () -> Void

    func makeUIViewController(context: Context) -> TextPagerHost {
        let host = TextPagerHost()
        host.onTapMenu = onTapMenu
        return host
    }

    func updateUIViewController(_ host: TextPagerHost, context: Context) {
        host.onTapMenu = onTapMenu
        host.sync(session: session, theme: theme)
        // 章节切换 / 重排后内容变了：即使页码相同也要重铺。
        if host.contentStamp != host.stamp(of: session.pages) || host.currentIndex != session.pageIndex {
            host.display(index: session.pageIndex, animated: session.settings.transition != .none)
        }
    }
}

/// 持有 UIPageViewController 并充当 dataSource / delegate。
final class TextPagerHost: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private(set) weak var session: TextReaderSession?
    private var theme: TextTheme = .dark
    private(set) var currentIndex = 0
    private(set) var contentStamp: String = ""
    var onTapMenu: (() -> Void)?

    private var pageController: UIPageViewController?
    private var suppressDelegate = false
    private var lastFont: UIFont?
    private var lastIndent: Bool?

    override func viewDidLoad() {
        super.viewDidLoad()
        rebuildPageController()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
    }

    /// 翻页模式变化时整体重建（navigationOrientation 不支持原地切换）。
    private func rebuildPageController() {
        pageController?.view.removeFromSuperview()
        pageController?.removeFromParent()
        let transition: UIPageViewController.TransitionStyle = (session?.settings.transition == .curl) ? .pageCurl : .scroll
        let orientation: UIPageViewController.NavigationOrientation =
            (session?.settings.transition == .vertical) ? .vertical : .horizontal
        let controller = UIPageViewController(transitionStyle: transition,
                                              navigationOrientation: orientation,
                                              options: [UIPageViewController.OptionsKey.interPageSpacing: 24])
        controller.dataSource = self
        controller.delegate = self
        controller.view.backgroundColor = .clear
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.didMove(toParent: self)
        pageController = controller
    }

    func sync(session: TextReaderSession, theme: TextTheme) {
        let firstSync = self.session == nil
        let transitionChanged = self.session?.settings.transition != session.settings.transition
        let themeChanged = self.theme != theme
        let fontChanged = self.lastFont != session.readingFont
            || self.lastIndent != session.settings.indentParagraphs
        self.session = session
        self.theme = theme
        self.lastFont = session.readingFont
        self.lastIndent = session.settings.indentParagraphs
        if transitionChanged || firstSync {
            // viewDidLoad 时 session 还没同步进来，首帧必须按真实设置重建一次。
            rebuildPageController()
            if !firstSync { contentStamp = "" }
        }
        // 主题 / 字体 / 缩进变化：页码和切片边界可能完全没变，
        // 但页内容必须用新样式重铺，所以强制 display。
        if (themeChanged || fontChanged) && !firstSync {
            contentStamp = ""
        }
    }

    func stamp(of pages: [TextPageSlice]) -> String {
        guard !pages.isEmpty else { return "empty" }
        return "\(pages.count)#\(pages[0].location)#\(pages[pages.count - 1].location)"
    }

    func display(index: Int, animated: Bool) {
        guard let session, let pageController else { return }
        let direction: UIPageViewController.NavigationDirection = index >= currentIndex ? .forward : .reverse
        currentIndex = index
        contentStamp = stamp(of: session.pages)
        guard session.pages.indices.contains(index) else { return }
        suppressDelegate = true
        pageController.setViewControllers([makePage(at: index)],
                                          direction: direction,
                                          animated: animated) { [weak self] _ in
            self?.suppressDelegate = false
        }
    }

    private func makePage(at index: Int) -> UIViewController {
        let controller = UIViewController()
        let page = TextPageUIView()
        page.backgroundColor = .clear
        if let session, session.pages.indices.contains(index) {
            page.configure(slice: session.pages[index],
                           font: session.readingFont,
                           lineSpacing: 6,
                           indent: session.settings.indentParagraphs,
                           textColor: theme.text.uiColor)
        }
        controller.view.addSubview(page)
        page.frame = controller.view.bounds
        page.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.backgroundColor = .clear
        return controller
    }

    // MARK: 点击区域（3×3 九宫格，动作可在编辑器里改）

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let session else { return }
        let point = gesture.location(in: view)
        let action = session.settings.tapAction(at: point, in: view.bounds.size)
        switch action {
        case .menu:
            onTapMenu?()
        case .prev:
            session.movePage(-1)
        case .next:
            session.movePage(1)
        }
    }

    // MARK: UIPageViewControllerDataSource

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let session, currentIndex > 0 else { return nil }
        return makePage(at: currentIndex - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let session, currentIndex + 1 < session.pages.count else { return nil }
        return makePage(at: currentIndex + 1)
    }

    // MARK: UIPageViewControllerDelegate

    func pageViewController(_ pageViewController: UIPageViewController,
                            didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        guard completed, !suppressDelegate, let session else { return }
        guard let visible = pageViewController.viewControllers?.first,
              let index = session.pages.firstIndex(where: { slice in
                  (visible.view.subviews.compactMap { $0 as? TextPageUIView }.first?.sliceID) == slice.location
              }) else { return }
        currentIndex = index
        session.pageIndex = index
        contentStamp = stamp(of: session.pages)
    }
}

/// 单页正文：UITextView 直渲染分页切片，样式与分页度量完全一致。
final class TextPageUIView: UITextView {
    private(set) var sliceID: Int = -1

    func configure(slice: TextPageSlice,
                   font: UIFont,
                   lineSpacing: CGFloat,
                   indent: Bool,
                   textColor: UIColor) {
        sliceID = slice.location
        isEditable = false
        isScrollEnabled = false
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0 // UITextView 默认 5pt 内边距会让渲染与分页度量错位
        backgroundColor = .clear
        self.textColor = textColor
        attributedText = TextPaginator.sliceAttributed(slice.text,
                                                       font: font,
                                                       lineSpacing: lineSpacing,
                                                       indent: indent)
    }
}

extension Color {
    var uiColor: UIColor {
        UIColor(self)
    }
}
