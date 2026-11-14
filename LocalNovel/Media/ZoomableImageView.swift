import Foundation
import SwiftUI
import UIKit

// MARK: - 全屏静态插图缩放容器（UIScrollView 原生捏合 + 双击放大 + 单击关闭）
// 未放大时禁用自身滚动，让横向滑动完整交给外层分页容器——这是「滑到两张图中间」
// 的直接原因（内层 UIScrollView 抢走了分页手势）。放大后才允许平移看局部。

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let onSingleTap: () -> Void
    /// 缩放状态上报：放大时上层需让出「上滑 / 右滑关闭」手势，避免误关
    var onZoomChanged: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap, onZoomChanged: onZoomChanged)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.backgroundColor = .black
        scroll.minimumZoomScale = 1.0
        scroll.maximumZoomScale = 4.0
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.isScrollEnabled = false // 未放大：不抢外层横向翻页手势
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

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap) // 双击不会误触发单击关闭
        scroll.addGestureRecognizer(singleTap)
        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onZoomChanged = onZoomChanged
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var onSingleTap: () -> Void
        var onZoomChanged: ((Bool) -> Void)?
        private var lastReportedZoom = false

        init(onSingleTap: @escaping () -> Void,
             onZoomChanged: ((Bool) -> Void)? = nil) {
            self.onSingleTap = onSingleTap
            self.onZoomChanged = onZoomChanged
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // 放大后才允许内部平移看局部；还原到 1× 立刻把横向手势还给分页
            scrollView.isScrollEnabled = scrollView.zoomScale > 1.01
            reportZoom(scrollView.zoomScale > 1.01)
        }

        /// 只在状态真正变化时上报，避免缩放过程中高频回调触发上层重绘
        private func reportZoom(_ zoomed: Bool) {
            guard zoomed != lastReportedZoom else { return }
            lastReportedZoom = zoomed
            onZoomChanged?(zoomed)
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            onSingleTap()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1.0, animated: true)
                scroll.isScrollEnabled = false
                reportZoom(false)
                return
            }
            // 放大后允许内部平移看局部；scrollViewDidZoom 也会同步这一状态
            scroll.isScrollEnabled = true
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
