import AppleShared
import SwiftUI
import UIKit
import OSLog

/// UIKit owns zoom/pan; the model receives only completed, intentional reading moves.
struct ComicReadingSurface: UIViewRepresentable {
    let document: ComicDocument
    let model: DocumentReaderModel
    let fitWidth: Bool
    let theme: AppTheme
    var interactionEnabled = true
    let tapped: (ReaderTapAction) -> Void
    let swiped: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> Canvas {
        let canvas = Canvas()
        canvas.delegate = context.coordinator
        canvas.minimumZoomScale = 1; canvas.maximumZoomScale = 5
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.addSubview(canvas.image)
        canvas.image.contentMode = .scaleToFill
        canvas.accessibilityIdentifier = "comic.canvas"
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        canvas.addGestureRecognizer(tap)
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipe(_:)))
            swipe.direction = direction; swipe.delegate = context.coordinator
            canvas.addGestureRecognizer(swipe)
            // UIScrollView's pan otherwise wins even at zoom=1, swallowing
            // horizontal page swipes. Vertical drags still proceed after the
            // direction-specific swipe fails; at zoom>1 the delegate rejects
            // swipes immediately so native image panning remains available.
            canvas.panGestureRecognizer.require(toFail: swipe)
        }
        canvas.resized = { [weak coordinator = context.coordinator, weak canvas] in
            guard let canvas else { return }; coordinator?.layout(canvas, preservingY: true)
        }
        return canvas
    }
    func updateUIView(_ canvas: Canvas, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        canvas.backgroundColor = theme.uiBackground
        canvas.isScrollEnabled = interactionEnabled && model.canNavigate && !model.rendering
        guard let command = model.command, case .comic(_, _, _, let page, _, let y) = command.locator else { return }
        guard coordinator.command != command.id else {
            if canvas.fitWidth != fitWidth { coordinator.layout(canvas, preservingY: true) }
            return
        }
        coordinator.command = command.id
        coordinator.loading?.cancel()
        coordinator.loading = Task { @MainActor [weak canvas, weak coordinator] in
            model.rendererStarted(command.id)
            let work = Task.detached(priority: .userInitiated) { try document.bitmap(page: page) }
            let result = await withTaskCancellationHandler {
                await work.result
            } onCancel: { work.cancel() }
            guard let canvas, let coordinator, !Task.isCancelled, coordinator.command == command.id else { return }
            switch result {
            case .success(let bitmap):
                coordinator.restoring = true
                canvas.zoomScale = 1
                canvas.image.image = UIImage(cgImage: bitmap.image)
                canvas.naturalSize = bitmap.naturalSize
                canvas.anchorY = y
                coordinator.displayedCommand = command.id
                coordinator.displayedPage = page
                canvas.accessibilityValue = "第 \(page + 1) 页"
                coordinator.layout(canvas, preservingY: false)
                coordinator.restoring = false
                model.rendererCompleted(command.id, success: true)
            case .failure(let error):
                if !(error is CancellationError) { model.rendererCompleted(command.id, success: false) }
            }
        }
    }
    static func dismantleUIView(_ canvas: Canvas, coordinator: Coordinator) {
        coordinator.loading?.cancel(); canvas.resized = nil; canvas.delegate = nil; canvas.image.image = nil
    }

    final class Canvas: UIScrollView {
        let image = UIImageView()
        var naturalSize = CGSize.zero
        var fitWidth = true
        var anchorY = 0.0
        var resized: (() -> Void)?
        private var previousSize = CGSize.zero
        override func layoutSubviews() {
            super.layoutSubviews()
            if previousSize != bounds.size, bounds.width > 0, bounds.height > 0 {
                previousSize = bounds.size; resized?()
            }
        }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ComicReadingSurface
        var command: UUID?
        var displayedCommand: UUID?
        var displayedPage: Int?
        var loading: Task<Void, Never>?
        var restoring = false
        private var readingPan = false
        private var dragStartY: CGFloat = 0
        init(_ parent: ComicReadingSurface) { self.parent = parent }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? Canvas)?.image }
        func layout(_ canvas: Canvas, preservingY: Bool) {
            guard canvas.naturalSize.width > 0, canvas.bounds.width > 0, canvas.bounds.height > 0 else { return }
            let y = preservingY ? canvas.anchorY : canvas.anchorY
            restoring = true
            canvas.setZoomScale(1, animated: false)
            canvas.fitWidth = parent.fitWidth
            var scale = canvas.bounds.width / canvas.naturalSize.width
            if !canvas.fitWidth { scale = min(scale, canvas.bounds.height / canvas.naturalSize.height) }
            let size = CGSize(width: canvas.naturalSize.width * scale, height: canvas.naturalSize.height * scale)
            canvas.image.frame = CGRect(origin: .zero, size: size)
            canvas.contentSize = size
            center(canvas)
            let target = min(max(-canvas.contentInset.top, CGFloat(y) * size.height - canvas.contentInset.top),
                             max(-canvas.contentInset.top, size.height - canvas.bounds.height + canvas.contentInset.bottom))
            canvas.contentOffset = CGPoint(x: -canvas.contentInset.left, y: target)
            restoring = false
        }
        func center(_ canvas: Canvas) {
            let horizontal = max(0, (canvas.bounds.width - canvas.contentSize.width) / 2)
            let vertical = max(0, (canvas.bounds.height - canvas.contentSize.height) / 2)
            canvas.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { if let canvas = scrollView as? Canvas { center(canvas) } }
        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { readingPan = false }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            readingPan = parent.interactionEnabled && !restoring && !scrollView.isZooming && scrollView.panGestureRecognizer.numberOfTouches == 1
            dragStartY = scrollView.contentOffset.y
        }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { commit(scrollView) } }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { commit(scrollView) }
        private func commit(_ scrollView: UIScrollView) {
            defer { readingPan = false }
            guard readingPan, parent.interactionEnabled, !restoring, !parent.model.rendering,
                  displayedCommand == command, displayedCommand == parent.model.command?.id,
                  let page = displayedPage, let canvas = scrollView as? Canvas, canvas.contentSize.height > 0,
                  abs(canvas.contentOffset.y - dragStartY) > 0.5,
                  let locator = try? parent.document.manifest.locator(format: parent.document.format, page: page,
                    y: min(1, max(0, Double((canvas.contentOffset.y + canvas.contentInset.top) / canvas.contentSize.height)))) else { return }
            if case .comic(_, _, _, _, _, let y) = locator { canvas.anchorY = y }
            parent.model.userScrolled(locator)
        }
        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            guard let canvas = recognizer.view as? Canvas else { return }
            trace("tap interaction=\(parent.interactionEnabled) page=\(displayedPage ?? -1)")
            parent.tapped(ReaderPageInteraction.tapAction(x: recognizer.location(in: canvas).x - canvas.bounds.minX, width: canvas.bounds.width))
        }
        @objc func swipe(_ recognizer: UISwipeGestureRecognizer) {
            trace("swipe left=\(recognizer.direction == .left) enabled=\(parent.interactionEnabled) canNavigate=\(parent.model.canNavigate) page=\(displayedPage ?? -1)")
            parent.swiped(recognizer.direction == .left ? 1 : -1)
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let canvas = gestureRecognizer.view as? Canvas else { return false }
            let x = gestureRecognizer.location(in: canvas).x - canvas.bounds.minX
            trace("begin zoom=\(canvas.zoomScale) x=\(x) enabled=\(parent.interactionEnabled)")
            return canvas.zoomScale == 1 && x > ReaderPageInteraction.navigationEdgeWidth
        }
        private func trace(_ message: String) {
#if DEBUG
            Logger(subsystem: "com.xlib.reader", category: "ComicGesture").notice("\(message, privacy: .public)")
#endif
        }
    }
}
