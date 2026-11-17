import Foundation
import AVFoundation
import MediaPlayer
import UIKit

// MARK: - 音量键翻页
//
// iOS 没有公开的「音量键按下」事件，通用做法是：
//   1. 激活一个 ambient + mixWithOthers 的音频会话（不抢占别人的音频）；
//   2. KVO 监听 AVAudioSession.outputVolume；
//   3. 把 MPVolumeView 塞进窗口（1×1、移到屏幕外），把系统音量 HUD 藏起来；
//   4. 每次翻页后把音量拨回基准值，否则读一章下来音量会被拉到 0 或 1。
//
// 默认关闭：开启后音量键就不再调音量了。

final class VolumeKeyPager {
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?

    private let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
    private var observation: NSKeyValueObservation?
    private var baseline: Float = 0.5
    private var restoring = false
    private var active = false

    func start() {
        guard !active else { return }
        active = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        baseline = min(max(session.outputVolume, 0.05), 0.95)

        attachVolumeView()
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self, let value = change.newValue, !self.restoring else { return }
            let delta = value - self.baseline
            guard abs(delta) > 0.002 else { return }
            self.baseline = value
            DispatchQueue.main.async {
                if delta > 0 { self.onUp?() } else { self.onDown?() }
                self.restoreBaseline()
            }
        }
    }

    func stop() {
        guard active else { return }
        active = false
        observation = nil
        volumeView.removeFromSuperview()
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func attachVolumeView() {
        guard volumeView.superview == nil else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        window?.addSubview(volumeView)
    }

    /// 把音量拨回基准值：只为了「下一次按键还能被识别成变化」，不改变用户听感太多
    private func restoreBaseline() {
        guard !restoring else { return }
        restoring = true
        let target = baseline
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            if let slider = self.volumeView.subviews.compactMap({ $0 as? UISlider }).first {
                slider.value = target
            }
            self.restoring = false
        }
    }
}
