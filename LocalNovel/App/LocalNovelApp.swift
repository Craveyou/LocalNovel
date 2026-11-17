import SwiftUI

@main
struct LocalNovelApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var preferences = Preferences.shared

    init() {
        // Apple 要求 Documents 目录里至少有一个文件，它才会出现在「文件」App 的
        // 「我的 iPhone」里。启动即写说明文件（幂等，不联网、不申请权限）。
        DocumentsBootstrap.ensureVisibleInFilesApp()
        // 导入的自定义字体在这里注册一次（幂等）；字体列表以沙盒里的文件为准
        let families = ReaderFontLibrary.registerInstalled()
        if !families.isEmpty {
            Preferences.shared.customFontFamilies = families
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(library)
                .environmentObject(preferences)
        }
    }
}
