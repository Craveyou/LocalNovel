import SwiftUI

@main
struct LocalNovelApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var preferences = Preferences.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(preferences)
        }
    }
}
