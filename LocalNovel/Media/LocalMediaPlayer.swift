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
    /// 画面宽高比（竖屏短剧 ≈ 0.56，横屏 ≈ 1.78）；读不到时按 16:9 兜底
    @Published private(set) var videoAspect: CGFloat?

    let player: AVPlayer
    /// 进度按「章 + 媒体」存储：同一章里可能挂多个视频/音频，只按章存会互相串台
    private let progressKey: String
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    /// 长按开始前是否在播放，用于松手后精确还原状态
    private var resumeAfterBoost = false

    init(url: URL, chapterId: String, headers: [String: String] = [:],
         progressKey: String? = nil) {
        self.progressKey = progressKey ?? chapterId
        // 远端（NAS / WebDAV）视频要带认证头；本地 file:// 时 headers 为空
        let asset = headers.isEmpty
            ? AVURLAsset(url: url)
            : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset) // 按需加载，不预缓冲整章
        let p = AVPlayer(playerItem: item)
        p.actionAtItemEnd = .pause
        self.player = p

        // 远端 asset 的 duration 要等网络，不能在主线程同步读；先给 0，
        // 由下面的时间观察器在元数据到位后回填。
        let assetDuration = headers.isEmpty ? CMTimeGetSeconds(item.asset.duration) : 0
        if assetDuration.isFinite, assetDuration > 0 { duration = assetDuration }

        // 恢复进度：不能拿 assetDuration 当门槛 —— 远端视频这里恒为 0，
        // 原来那个 `saved < assetDuration - 1` 永远不成立，NAS 视频永远从头播。
        // 兼容旧数据：以前按 chapterId 存，单媒体章节的进度能直接接上。
        var saved = ProgressStore.shared.mediaTime(for: self.progressKey)
        if saved <= 1, self.progressKey != chapterId {
            saved = ProgressStore.shared.mediaTime(for: chapterId)
        }
        if saved > 1 {
            let reachedEnd = assetDuration.isFinite && assetDuration > 0
                && saved >= assetDuration - 1
            if !reachedEnd {
                p.seek(to: CMTime(seconds: saved, preferredTimescale: 600))
                currentTime = saved
            }
        }

        // 播完必须自己收状态：否则 isPlaying 还是 true，按钮显示「暂停」，
        // 点一下执行的是 pause()，播放器停在末尾再也起不来。
        endObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isPlaying = false
            self.isBoosting = false
            self.player.rate = 1.0
            // 清掉记忆：下次点播放从头开始，而不是又停在结尾一动不动
            ProgressStore.shared.setMediaTime(0, for: self.progressKey)
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

        // 画面比例：竖屏短剧不能被硬压成 16:9（那样上下大片黑边、人像被缩小）
        Task { [weak self] in
            guard let self else { return }
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            guard let track = tracks.first,
                  let size = try? await track.load(.naturalSize),
                  let transform = try? await track.load(.preferredTransform) else { return }
            let applied = size.applying(transform)
            let width = abs(applied.width), height = abs(applied.height)
            guard width > 1, height > 1 else { return }
            let aspect = width / height
            await MainActor.run { self.videoAspect = aspect }
        }
    }

    deinit {
        player.pause()
        if let observer = timeObserver { player.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        // 已经播到结尾：先回到开头。否则 play() 之后停在最后一帧，看起来毫无反应。
        if duration > 1, currentTime >= duration - 0.5 {
            seek(to: 0)
        }
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
        ProgressStore.shared.setMediaTime(currentTime, for: progressKey)
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
