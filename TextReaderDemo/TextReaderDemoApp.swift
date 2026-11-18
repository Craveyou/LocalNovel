import SwiftUI
import TextReaderKit

@main
struct TextReaderDemoApp: App {
    var body: some Scene {
        WindowGroup {
            TextReaderRootView(bundledBooks: Self.sampleBooks())
        }
    }

    private static func sampleBooks() -> [TextBook] {
        guard let url = Bundle.main.url(forResource: "样例小说", withExtension: "txt") else {
            return []
        }
        return [TextBook(title: "样例小说", url: url)]
    }
}
