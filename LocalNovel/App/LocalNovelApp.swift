import SwiftUI

@main
struct LocalNovelApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var preferences = Preferences.shared

    init() {
        // Apple 要求 Documents 目录里至少有一个文件，它才会出现在「文件」App 的
        // 「我的 iPhone」里。启动即写说明文件（幂等，不联网、不申请权限）。
        DocumentsBootstrap.ensureVisibleInFilesApp()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(preferences)
        }
    }
}
