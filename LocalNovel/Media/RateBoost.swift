import Foundation
import UIKit
import SwiftUI

// MARK: - 长按倍速手势（内联视频 / 全屏视频 / 音频面板共用）
// 必须用 UIKit 的 UILongPressGestureRecognizer：SwiftUI 的 onLongPressGesture
// 只在达到阈值时回调一次，拿不到「松手」事件，无法实现「按住快进、松开还原」。

enum RateBoostGesture {
    /// 长按判定阈值（秒）
    static let minimumPressDuration: TimeInterval = 0.35

    static func attach(to view: UIView, coordinator: RateBoostCoordinator) {
        let press = UILongPressGestureRecognizer(
            target: coordinator,
            action: #selector(RateBoostCoordinator.handlePress(_:))
        )
        press.minimumPressDuration = minimumPressDuration
        press.allowableMovement = 24
        // 不吞掉触摸：播放按钮、进度条、系统播放控件仍可正常响应
        press.cancelsTouchesInView = false
        press.delegate = coordinator
        view.addGestureRecognizer(press)
    }
}

final class RateBoostCoordinator: NSObject, UIGestureRecognizerDelegate {
    private let onChange: (Bool) -> Void
    private var isActive = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init()
    }

    @objc func handlePress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            isActive = true
            onChange(true)
        case .ended, .cancelled, .failed:
            guard isActive else { return }
            isActive = false
            onChange(false)
        default:
            break
        }
    }

    /// 与系统播放控件 / SwiftUI 手势同时识别，避免长按阻断点击
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - 音频面板：没有画面，但同样支持长按倍速

struct AudioSurfaceView: UIViewRepresentable {
    let onBoost: (Bool) -> Void

    func makeCoordinator() -> RateBoostCoordinator {
        RateBoostCoordinator(onChange: onBoost)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.secondarySystemFill
        RateBoostGesture.attach(to: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
