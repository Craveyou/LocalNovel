import Foundation
import AVFoundation
import UIKit
import SwiftUI

// MARK: - 章末音视频播放控制
// 要求：点击才播放、不自动播放、不后台播放、按需加载、记住播放进度。
// 未声明 UIBackgroundModes，且 scenePhase 进入 background 时主动 pause。

final class LocalMediaPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isBoosting = false

    let player: AVPlayer
    private let chapterId: String
    private var timeObserver: Any?
    /// 长按开始前是否在播放，用于松手后精确还原状态
    private var resumeAfterBoost = false

    init(url: URL, chapterId: String) {
        self.chapterId = chapterId
        let item = AVPlayerItem(url: url) // 本地 file://，按需加载，不预缓冲整章
        let p = AVPlayer(playerItem: item)
        p.actionAtItemEnd = .pause
        self.player = p

        let assetDuration = CMTimeGetSeconds(item.asset.duration)
        if assetDuration.isFinite, assetDuration > 0 { duration = assetDuration }

        let saved = ProgressStore.shared.mediaTime(for: chapterId)
        if saved > 0, assetDuration.isFinite, saved < assetDuration - 1 {
            p.seek(to: CMTime(seconds: saved, preferredTimescale: 600))
            currentTime = saved
        }

        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let t = CMTimeGetSeconds(time)
            if t.isFinite { self.currentTime = t }
            if let item = self.player.currentItem {
                let d = CMTimeGetSeconds(item.duration)
                if d.isFinite, d > 0 { self.duration = d }
            }
        }
    }

    deinit {
        player.pause()
        if let observer = timeObserver { player.removeTimeObserver(observer) }
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        do {
            // .playback 保证有声；未声明后台模式，App 挂起即停
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // 音频会话失败不阻断画面播放
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
        isBoosting = false
        ProgressStore.shared.setMediaTime(currentTime, for: chapterId)
    }

    /// 长按临时倍速：按住以目标倍速播放，松手还原长按前的播放状态。
    /// 若长按前是暂停态，松手会回到暂停（相当于「按住快进」）；
    /// 若长按前正在播放，松手恢复 1 倍速继续播放。
    func setBoost(_ active: Bool, rate: Double) {
        let target = Float(max(1.0, min(4.0, rate)))
        if active {
            guard !isBoosting else { return }
            isBoosting = true
            resumeAfterBoost = isPlaying
            if !isPlaying { play() }
            player.rate = target
        } else {
            guard isBoosting else { return }
            isBoosting = false
            // 若长按期间用户（或全屏系统控件）已经暂停，rate≈0，此时不能强行
            // 设回 1.0 —— 那会让已暂停的视频意外重新播放。
            if player.rate > 0.01 { player.rate = 1.0 }
            if !resumeAfterBoost || player.rate < 0.01 { pause() }
        }
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { self?.currentTime = seconds }
        }
    }

    static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - AVPlayerLayer 画面容器（视频用；音频不显示画面）

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    /// 长按倍速回调：true = 按住开始，false = 松手恢复
    let onBoost: (Bool) -> Void

    func makeCoordinator() -> RateBoostCoordinator {
        RateBoostCoordinator(onChange: onBoost)
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        RateBoostGesture.attach(to: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }
}
