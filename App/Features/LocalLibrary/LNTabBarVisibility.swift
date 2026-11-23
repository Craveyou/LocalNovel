import SwiftUI
import UIKit

/// 阅读页隐藏底部 Tab 栏。
///
/// iOS 16+ 直接用原生 `.toolbar(.hidden, for: .tabBar)`；
/// iOS 15 没有这个 API，退化为找到宿主 UITabBarController 手动设置 tabBar 可见性
/// （工程部署目标是 15.0，必须留这条兜底）。
struct LNHidesTabBarModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.toolbar(.hidden, for: .tabBar)
        } else {
            content
                .onAppear { LNTabBarController.setHidden(true) }
                .onDisappear { LNTabBarController.setHidden(false) }
        }
    }
}

/// 列表页显式恢复 tab 栏，避免 iOS 16 上从阅读页返回后偶发残留隐藏。
struct LNShowsTabBarModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.toolbar(.visible, for: .tabBar)
        } else {
            content.onAppear { LNTabBarController.setHidden(false) }
        }
    }
}

extension View {
    /// 当前页面隐藏底部 tab 栏（阅读页）
    func lnHidesTabBar() -> some View { modifier(LNHidesTabBarModifier()) }
    /// 明确恢复底部 tab 栏（列表页）
    func lnShowsTabBar() -> some View { modifier(LNShowsTabBarModifier()) }
}

enum LNTabBarController {
    static func setHidden(_ hidden: Bool) {
        DispatchQueue.main.async {
            guard let controller = find() else { return }
            guard controller.tabBar.isHidden != hidden else { return }
            UIView.performWithoutAnimation {
                controller.tabBar.isHidden = hidden
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
            }
        }
    }

    private static func find() -> UITabBarController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        let root = windows.first(where: \.isKeyWindow)?.rootViewController
            ?? windows.first?.rootViewController
        return find(in: root)
    }

    private static func find(in controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tab = controller as? UITabBarController { return tab }
        for child in controller.children {
            if let found = find(in: child) { return found }
        }
        if let presented = controller.presentedViewController {
            return find(in: presented)
        }
        return nil
    }
}
