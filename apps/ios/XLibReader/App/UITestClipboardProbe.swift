#if DEBUG
import SwiftUI
import UIKit

/// The physical-device UI runner is a background process and cannot query the
/// general pasteboard. Observe its generation in the foreground app instead;
/// never read or expose clipboard contents. Present only for an isolated UI run.
struct UITestClipboardProbe: View {
    @State private var generation = UIPasteboard.general.changeCount

    var body: some View {
        Text(String(generation))
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .clipped()
            .accessibilityIdentifier("testing.clipboardGeneration")
            .allowsHitTesting(false)
            .task {
                while !Task.isCancelled {
                    let current = UIPasteboard.general.changeCount
                    if current != generation { generation = current }
                    do { try await Task.sleep(for: .milliseconds(150)) }
                    catch { return }
                }
            }
    }
}
#endif
