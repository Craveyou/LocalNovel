import SwiftUI
import AVKit
import AVFoundation

/// 章末视频 / 短剧单集：点击播放、不自动播放；支持全屏、长按倍速、旋转。
///
/// 重要：内嵌播放器与全屏播放器**必须共用同一个 AVPlayer 实例**。
/// 之前两处各自 `AVPlayer(url:)`，全屏时两个播放器同时在播 → 双音轨。
///
/// 实现要点（b47）：
/// - 加载后**不设 rate**：AVPlayer 对未播放的实例直接设 `rate = 1.0` 会立刻开播，
///   这就是「没点播放自己响」的根因；倍速只在正在播放时套用。
/// - 长按手势不能挂在 SwiftUI 层（会被 AVPlayerViewController 的系统手势吞掉），
///   改为在自定义 UIViewRepresentable 里给播放器视图挂 UIGestureRecognizer 并行识别。
struct LNVideoView: View {
    let item: LNMediaItem
    let source: any LNLibrarySource

    @State private var player: AVPlayer?
    @State private var duration: Double?
    @State private var failed = false
    @State private var fullscreen = false

    /// 倍速：长按内嵌画面循环切换；全屏里也有按钮
    @State private var speed: Float = 1.0
    @State private var speedHint: String?

    private let speeds: [Float] = [1.0, 1.25, 1.5, 2.0, 0.75]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if failed {
                Label("无法播放：\(item.fileName)", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let player {
                ZStack {
                    LNPlayerSurface(player: player, onLongPress: cycleSpeed)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        // 全屏时内嵌画面仍然渲染同一 player，视觉上没问题（只有一个音轨）
                        .overlay(alignment: .topTrailing) {
                            HStack(spacing: 6) {
                                Button {
                                    fullscreen = true
                                } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(Color.black.opacity(0.45), in: Circle())
                                }
                                .accessibilityLabel("全屏播放")
                            }
                            .padding(8)
                        }
                        .overlay(alignment: .bottomLeading) {
                            if speed != 1.0 {
                                Text("\(speed, specifier: "%.2g")×")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.black.opacity(0.55), in: Capsule())
                                    .padding(8)
                            }
                        }
                }
                .overlay(alignment: .center) {
                    if let speedHint {
                        Text(speedHint)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.black.opacity(0.7), in: Capsule())
                            .transition(.opacity)
                    }
                }
                // 播放/暂停由系统控制条接管；用户点播放时把记住的倍速套回去
                // （VideoPlayer 的 play 固定以 1.0 开播）
                .onReceive(player.publisher(for: \.timeControlStatus)) { status in
                    guard status == .playing, player.rate != speed else { return }
                    player.rate = speed
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.06))
                    ProgressView()
                }
                .frame(height: 200)
            }
            HStack(spacing: 8) {
                Text(item.fileName)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                if let duration, duration > 0 {
                    Text(timeText(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    fullscreen = true
                } label: {
                    Image(systemName: "rectangle.expand.vertical")
                        .font(.caption)
                        .foregroundStyle(ReadingTheme.accent)
                }
                .accessibilityLabel("旋转全屏播放")
            }
        }
        .task(id: item.path) { await load() }
        .fullScreenCover(isPresented: $fullscreen) {
            LNVideoFullscreen(item: item, source: source, player: player,
                              speed: $speed, onSpeedChange: applySpeed)
        }
    }

    private func load() async {
        guard player == nil, !failed else { return }
        guard let url = try? await source.localURL(for: item.path) else {
            failed = true
            return
        }
        let p = AVPlayer(url: url)
        // 注意：这里绝不能 p.rate = speed —— 未播放的 player 直接设 rate 会立刻开播
        player = p
        let asset = AVURLAsset(url: url)
        if let cm = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cm)
            if seconds.isFinite, seconds > 0 { duration = seconds }
        }
    }

    private func applySpeed(_ value: Float) {
        speed = value
        // 暂停状态下直接设 rate 会把视频启动起来；只在正在播放时改 rate，
        // 暂停时先记住，等用户点播放后由 timeControlStatus 监听套用。
        if let player, player.timeControlStatus == .playing {
            player.rate = value
        }
    }

    private func cycleSpeed() {
        guard let index = speeds.firstIndex(of: speed) else { return }
        let next = speeds[(index + 1) % speeds.count]
        applySpeed(next)
        speedHint = "播放速度 \(formatSpeed(next))×"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            speedHint = nil
        }
    }

    private func formatSpeed(_ value: Float) -> String {
        value == 1 ? "1.0" : String(format: "%.2g", value)
    }

    private func timeText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60, s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// 全屏播放器：复用内嵌传进来的同一个 AVPlayer，绝不自己新建，避免双音轨。
private struct LNVideoFullscreen: View {
    let item: LNMediaItem
    let source: any LNLibrarySource
    let player: AVPlayer?
    @Binding var speed: Float
    let onSpeedChange: (Float) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var speedMenu = false

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ReadingNavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                        .onTapGesture {
                            // 点击空白处不做处理，交给系统 VideoPlayer 控件
                        }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("退出全屏")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(speeds, id: \.self) { value in
                                Button {
                                    onSpeedChange(value)
                                } label: {
                                    HStack {
                                        Text("\(formatSpeed(value))×")
                                        if abs(speed - value) < 0.01 {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text("\(formatSpeed(speed))×")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.white.opacity(0.18), in: Capsule())
                        }
                        .accessibilityLabel("播放倍速")
                        Button {
                            requestLandscape()
                        } label: {
                            Image(systemName: "rotate.3deg")
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel("旋转屏幕")
                        Button("完成") { dismiss() }
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .onAppear { onSpeedChange(speed) }
    }

    private func formatSpeed(_ value: Float) -> String {
        value == 1 ? "1.0" : String(format: "%.2g", value)
    }

    /// 请求横屏：优先用项目的 ReaderScreenOrientation，它封装了 iOS 16 的 requestGeometryUpdate
    private func requestLandscape() {
        ReaderScreenOrientation.apply("5")  // landscapeLeft
    }
}

/// AVPlayerViewController 的 SwiftUI 包装：
/// 系统播放控制条照常可用，同时给画面挂一个与系统手势**并行识别**的长按手势。
///
/// 为什么不用 SwiftUI 的 `.onLongPressGesture`：VideoPlayer / AVPlayerViewController
/// 内部的 UIKit 手势（点按呼出控制条等）优先级更高，SwiftUI 层的长按收不到任何事件。
private struct LNPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let onLongPress: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLongPress: onLongPress) }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black

        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        let surface = controller.view ?? UIView()
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        surface.frame = container.bounds
        container.addSubview(surface)
        // 必须持有 controller，否则控制条会被释放
        context.coordinator.controller = controller

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        longPress.minimumPressDuration = 0.4
        longPress.cancelsTouchesInView = false
        longPress.delegate = context.coordinator
        container.addGestureRecognizer(longPress)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onLongPress = onLongPress
        if context.coordinator.controller?.player !== player {
            context.coordinator.controller?.player = player
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onLongPress: () -> Void
        weak var controller: AVPlayerViewController?

        init(onLongPress: @escaping () -> Void) {
            self.onLongPress = onLongPress
        }

        @objc func handle(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            onLongPress()
        }

        // 与系统播放控件的手势并行识别，互不阻断
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
