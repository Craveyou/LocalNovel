import PDFKit

/// Refit cropped pages when iPad rotation or a window resize changes the width.
final class PDFCropView: PDFView {
    var onWidthChange: (() -> Void)?
    private var lastWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, abs(bounds.width - lastWidth) > 0.5 else { return }
        lastWidth = bounds.width
        DispatchQueue.main.async { [weak self] in self?.onWidthChange?() }
    }
}
