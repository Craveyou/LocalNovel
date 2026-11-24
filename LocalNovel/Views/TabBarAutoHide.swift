import SwiftUI
import UIKit

// MARK: - 阅读时收起底部标签栏（UIKit 兜底）
//
// SwiftUI 的 `.toolbar(.hidden, for: .tabBar)` 在 NavigationSplitView 的 detail 列里
// 并不总是生效：iPad 分栏下 tabBar 由外层 UITabBarController 持有，detail 的
// 导航栏更新会把隐藏请求覆盖掉（表现就是「读书时底部三个标签还在」）。
//
// 这里直接找到宿主 UITabBarController，在每次布局时把 tabBar 收起，
// 视图消失时恢复。写成 representable 是为了能跟着阅读页的生命周期走，
// 不需要全局单例，也不会影响书库 / NAS / 设置三个根页面。

enum TabBarVisibility {
    static func setHidden(_ hidden: Bool, animated: Bool) {
        guard let tab = resolve() else { return }

        // iOS 18 起有官方的收起接口；没有就退回 isHidden。
        // 两条路都试过：isHidden 会被 SwiftUI 的导航栏更新复位，
        // 所以调用方还需要在布局阶段重复设置。
        let selector = NSSelectorFromString("setTabBarHidden:animated:")
        if tab.responds(to: selector) {
            _ = tab.perform(selector, with: hidden, with: animated)
        } else {
            tab.tabBar.isHidden = hidden
        }
    }

    static func resolve() -> UITabBarController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if let found = findTabBar(in: window.rootViewController) {
                    return found
                }
            }
        }
        return nil
    }

    private static func findTabBar(in controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tab = controller as? UITabBarController { return tab }
        for child in controller.children {
            if let found = findTabBar(in: child) { return found }
        }
        return findTabBar(in: controller.presentedViewController)
    }
}

struct TabBarAutoHide: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TabBarHiderController {
        TabBarHiderController()
    }

    func updateUIViewController(_ uiViewController: TabBarHiderController, context: Context) {}
}

final class TabBarHiderController: UIViewController {
    /// 进入阅读前 tabBar 是否本来就是隐藏的：只在第一次记录，避免把「已隐藏」当成原状
    private var recorded = false
    private var wasHidden = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        rememberOriginalState()
        TabBarVisibility.setHidden(true, animated: true)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        rememberOriginalState()
        // SwiftUI 每次更新都可能把 tabBar 复原，布局阶段再压一次，保证稳定隐藏
        TabBarVisibility.setHidden(true, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        TabBarVisibility.setHidden(wasHidden, animated: false)
        recorded = false
    }

    private func rememberOriginalState() {
        guard !recorded, let tab = TabBarVisibility.resolve() else { return }
        wasHidden = tab.tabBar.isHidden
        recorded = true
    }
}
