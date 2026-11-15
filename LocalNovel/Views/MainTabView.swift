import SwiftUI

// MARK: - 底部三页：书库 · NAS · 设置
//
// 软件打开默认停在「书库」；设置固定在最右。阅读时标签栏自动收起（见 ReadingChrome）。
// iPhone 上是底部标签栏，iPad 上按系统规范显示在顶部（同一顺序）。

struct MainTabView: View {
    enum Tab: String, Hashable {
        case library
        case nas
        case settings
    }

    @State private var selection: Tab = .library
    /// 阅读界面出现时收起标签栏，让正文占满整屏
    @ObservedObject private var chrome = ReadingChrome.shared

    var body: some View {
        TabView(selection: $selection) {
            RootView()
                .tabItem { Label("书库", systemImage: "books.vertical") }
                .tag(Tab.library)

            NASRootView()
                .tabItem { Label("NAS", systemImage: "externaldrive.connected.to.line.below") }
                .tag(Tab.nas)

            SettingsView(showsDoneButton: false)
                .tabItem { Label("设置", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
        // 阅读（文字 / 漫画 / 剧照 / 视频）时自动隐藏标签栏，退出阅读立即恢复。
        // 书库根视图（NavigationSplitView）内部再声明一次，覆盖 iPad 分栏的情形。
        .toolbar(chrome.isImmersive ? .hidden : .visible, for: .tabBar)
        .animation(.easeInOut(duration: 0.22), value: chrome.isImmersive)
    }
}
