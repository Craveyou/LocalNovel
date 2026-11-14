import Foundation
import SwiftUI
import UIKit

// MARK: - 全屏静态插图缩放容器（UIScrollView 原生捏合 + 双击放大）
// 用 UIScrollView 而不是 SwiftUI MagnificationGesture：缩放、惯性、边界回弹
// 都由系统处理，且在 TabView 分页容器里更不容易和横向翻页手势打架。

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.backgroundColor = .black
        scroll.minimumZoomScale = 1.0
        scroll.maximumZoomScale = 4.0
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.frame = scroll.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1.0, animated: true)
                return
            }
            // 显式标注为 UIView，避免 ?? 两侧（UIImageView? / UIScrollView）泛型推断不一致
            let target: UIView = imageView ?? scroll
            let center = gesture.location(in: target)
            let width = scroll.bounds.width / 2.0
            let height = scroll.bounds.height / 2.0
            let origin = CGPoint(x: max(0, center.x - width / 2.0),
                                 y: max(0, center.y - height / 2.0))
            scroll.zoom(to: CGRect(origin: origin, size: CGSize(width: width, height: height)),
                        animated: true)
        }
    }
}
