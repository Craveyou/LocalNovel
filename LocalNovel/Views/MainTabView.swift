import SwiftUI

// MARK: - 底部三页：书库 · NAS · 设置
//
// 软件打开默认停在「书库」；设置固定在最右。
// iPhone 上是底部标签栏，iPad 上按系统规范显示在顶部（同一顺序）。

struct MainTabView: View {
    enum Tab: String, Hashable {
        case library
        case nas
        case settings
    }

    @State private var selection: Tab = .library

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
    }
}
