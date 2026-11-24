import SwiftUI
import AVKit
import AVFoundation

/// 章末视频 / 短剧单集：点击播放、不自动播放；支持全屏、长按倍速、旋转画面。
///
/// 重要：内嵌播放器与全屏播放器**必须共用同一个 AVPlayer 实例**。
/// 之前两处各自 `AVPlayer(url:)`，全屏时两个播放器同时在播 → 双音轨。
///
/// 实现要点：
/// - 加载后**不设 rate**：AVPlayer 对未播放的实例直接设 `rate = 1.0` 会立刻开播，
///   这就是「没点播放自己响」的根因；倍速只在正在播放时套用。
/// - 长按手势不能挂在 SwiftUI 层（会被 AVPlayerViewController 的系统手势吞掉），
///   用 LNPlayerSurface 在播放器视图上挂 UIGestureRecognizer 并行识别。
/// - 播放器必须以 childViewController 方式装配（addChild/didMove），
///   只 addSubview 不 addChild 在新系统上会黑屏（b47 的教训）。
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
                // （系统控件的 play 固定以 1.0 开播）
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
                .accessibilityLabel("全屏播放")
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
/// 长按画面也能循环倍速；「旋转」是画面旋转（转 90° 后握持手机方向即可），退出自动复原。
private struct LNVideoFullscreen: View {
    let item: LNMediaItem
    let source: any LNLibrarySource
    let player: AVPlayer?
    @Binding var speed: Float
    let onSpeedChange: (Float) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rotated = false

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ReadingNavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black
                    if let player {
                        LNPlayerSurface(player: player, onLongPress: cycleSpeed)
                            .frame(width: rotated ? geo.size.height : geo.size.width,
                                   height: rotated ? geo.size.width : geo.size.height)
                            .rotationEffect(.degrees(rotated ? 90 : 0))
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
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
                            rotated.toggle()
                        } label: {
                            Image(systemName: rotated ? "arrow.counterclockwise" : "rotate.3deg")
                                .foregroundStyle(rotated ? ReadingTheme.accent : .white)
                        }
                        .accessibilityLabel(rotated ? "恢复画面方向" : "旋转画面")
                        Button("完成") { dismiss() }
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .onAppear { onSpeedChange(speed) }
    }

    private func cycleSpeed() {
        guard let index = speeds.firstIndex(of: speed) else { return }
        let next = speeds[(index + 1) % speeds.count]
        onSpeedChange(next)
    }

    private func formatSpeed(_ value: Float) -> String {
        value == 1 ? "1.0" : String(format: "%.2g", value)
    }
}

/// AVPlayerViewController 的 SwiftUI 包装：
/// - 以 childViewController 方式正式装配（黑屏修复的关键，只 addSubview 不够）；
/// - 系统播放控制条照常可用；
/// - 挂一个与系统手势**并行识别**的长按手势用于循环切换倍速。
///
/// 为什么不用 SwiftUI 的 `.onLongPressGesture`：AVPlayerViewController
/// 内部的 UIKit 手势（点按呼出控制条等）优先级更高，SwiftUI 层的长按收不到任何事件。
private struct LNPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let onLongPress: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLongPress: onLongPress) }

    func makeUIView(context: Context) -> AttachContainerView {
        let container = AttachContainerView()
        container.backgroundColor = .black

        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        context.coordinator.controller = controller
        container.coordinator = context.coordinator

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

    func updateUIView(_ uiView: AttachContainerView, context: Context) {
        context.coordinator.onLongPress = onLongPress
        if context.coordinator.controller?.player !== player {
            context.coordinator.controller?.player = player
        }
        // 首次 updateUIView 时可能还没进视图层级，didMoveToWindow 回调会兜底再试
        context.coordinator.attachIfNeeded()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onLongPress: () -> Void
        var controller: AVPlayerViewController?
        weak var container: AttachContainerView?
        private var attached = false

        init(onLongPress: @escaping () -> Void) {
            self.onLongPress = onLongPress
        }

        /// 正式装配：找到宿主 VC → addChild → 加视图 + 四边约束 → didMove。
        /// 只 addSubview 不 addChild 时，新系统上渲染层/控制条会失效（黑屏）。
        func attachIfNeeded() {
            guard let controller, let container, !attached else { return }
            guard controller.view.superview == nil else {
                attached = true
                return
            }
            if let parent = parentViewController(of: container) {
                parent.addChild(controller)
                let surface = controller.view
                surface.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(surface)
                NSLayoutConstraint.activate([
                    surface.topAnchor.constraint(equalTo: container.topAnchor),
                    surface.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    surface.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    surface.trailingAnchor.constraint(equalTo: container.trailingAnchor)
                ])
                controller.didMove(toParent: parent)
                attached = true
            }
        }

        /// 视图离开窗口（被滚动回收/销毁）时摘除 child 关系，避免父 VC 持续持有泄漏
        func detachIfNeeded() {
            guard attached, let controller, controller.parent != nil else { return }
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            attached = false
        }

        private func parentViewController(of view: UIView) -> UIViewController? {
            var responder: UIResponder? = view.next
            while let r = responder {
                if let vc = r as? UIViewController { return vc }
                responder = r.next
            }
            return nil
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

/// 容器视图：进窗口时触发装配、离窗口时触发摘除。
final class AttachContainerView: UIView {
    var coordinator: LNPlayerSurface.Coordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { coordinator?.attachIfNeeded() }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { coordinator?.detachIfNeeded() }
    }
}
