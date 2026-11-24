import SwiftUI
import AVKit
import AVFoundation

/// 章末视频 / 短剧单集：点击播放、不自动播放；支持全屏、长按倍速、旋转。
///
/// 重要：内嵌播放器与全屏播放器**必须共用同一个 AVPlayer 实例**。
/// 之前两处各自 `AVPlayer(url:)`，全屏时两个播放器同时在播 → 双音轨。
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
                    VideoPlayer(player: player)
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
                // 长按循环倍速
                .onLongPressGesture(minimumDuration: 0.5) {
                    cycleSpeed()
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
        p.rate = speed
        player = p
        let asset = AVURLAsset(url: url)
        if let cm = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cm)
            if seconds.isFinite, seconds > 0 { duration = seconds }
        }
    }

    private func applySpeed(_ value: Float) {
        speed = value
        player?.rate = value
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
