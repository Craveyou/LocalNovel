import Foundation
import Observation

/// Shared for this app run, never serialized into book metadata or settings.
@MainActor @Observable
final class PDFCropState {
    var settings = PDFCropSettings()
}

/// Display-only margins. Locators always use the original crop box.
struct PDFCropSettings: Equatable, Sendable {
    var enabled = false
    var left = 0.10
    var right = 0.10

    func normalized() -> Self {
        var value = self
        value.left = left.isFinite ? min(0.30, max(0, left)) : 0.10
        value.right = right.isFinite ? min(0.30, max(0, right)) : 0.10
        return value
    }

    func bounds(original: CGRect, rotation: Int) -> CGRect {
        let value = normalized()
        guard value.enabled, original.width > 0, original.height > 0 else { return original }
        // PDF coordinates are bottom-up; margins describe the displayed page.
        switch (rotation % 360 + 360) % 360 {
        case 90:
            return CGRect(x: original.minX, y: original.minY + original.height * value.left,
                          width: original.width, height: original.height * (1 - value.left - value.right))
        case 180:
            return CGRect(x: original.minX + original.width * value.right, y: original.minY,
                          width: original.width * (1 - value.left - value.right), height: original.height)
        case 270:
            return CGRect(x: original.minX, y: original.minY + original.height * value.right,
                          width: original.width, height: original.height * (1 - value.left - value.right))
        default:
            return CGRect(x: original.minX + original.width * value.left, y: original.minY,
                          width: original.width * (1 - value.left - value.right), height: original.height)
        }
    }
}
