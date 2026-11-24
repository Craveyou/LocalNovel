import Foundation
import SwiftUI
import AVFoundation

// MARK: - 章末音视频附件
// 点击才播放 / 不自动播放 / 不后台播放；视频可全屏；三处（内联视频、全屏视频、音频面板）
// 共用一套长按倍速手势，按住临时倍速、松手还原。

struct MediaAttachmentView: View {
    let item: MediaItem
    let chapterId: String
    let boostRate: Double
    /// NAS 远端视频的认证头；本地文件为空
    let headers: [String: String]

    @StateObject private var controller: LocalMediaPlayer
    @State private var isFullscreen = false
    @Environment(\.scenePhase) private var scenePhase

    init(item: MediaItem, chapterId: String, boostRate: Double,
         headers: [String: String] = [:]) {
        self.item = item
        self.chapterId = chapterId
        self.boostRate = boostRate
        self.headers = headers
        _controller = StateObject(wrappedValue: LocalMediaPlayer(url: item.url,
                                                                 chapterId: chapterId,
                                                                 headers: headers,
                                                                 progressKey: "\(chapterId)#\(item.id)"))
    }

    private func boost(_ active: Bool) {
        controller.setBoost(active, rate: boostRate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if item.kind == .video { videoBlock }
            if item.kind == .audio { audioBlock }
            controls
        }
        .padding(14)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: scenePhase) { _, newPhase in
            // 明确要求：不后台播放；同时收掉可能正在进行的倍速
            if newPhase == .background {
                boost(false)
                controller.pause()
            }
        }
        .onDisappear {
            boost(false)
            controller.pause()
        }
        .fullScreenCover(isPresented: $isFullscreen, onDismiss: {
            boost(false)
        }) {
            FullscreenVideoView(controller: controller, boostRate: boostRate)
        }
    }

    // MARK: 视频画面（内联 / 全屏共用同一 AVPlayer）

    private var videoBlock: some View {
        ZStack(alignment: .topTrailing) {
            if isFullscreen {
                // 全屏期间卸载内联 AVPlayerLayer：同一个 AVPlayer 被两个 layer
                // 同时绑定会互相抢渲染，退出全屏后这里重建并重新绑定即可续播。
                Rectangle().fill(Color.black)
            } else {
                PlayerLayerView(player: controller.player) { active in boost(active) }
            }

            Button { isFullscreen = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("全屏播放")
        }
        // 跟随视频真实比例：竖屏短剧按 9:16 竖着显示，不再被压成 16:9
        .aspectRatio(controller.videoAspect ?? 16.0 / 9.0, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottomLeading) { boostTag }
    }

    // MARK: 音频面板（没有画面，但同样可长按倍速）

    private var audioBlock: some View {
        AudioSurfaceView(onBoost: { active in boost(active) })
            .frame(height: 116)
            .overlay(alignment: .center) {
                VStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.title2)
                    Text("音频 · 长按此处倍速播放")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) { boostTag }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var boostTag: some View {
        Group {
            if controller.isBoosting {
                Text(String(format: "%.1f× 快进中", boostRate))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: 播放控件

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    controller.toggle()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(controller.isPlaying ? "暂停" : "播放")

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(item.kind == .video ? "视频" : "音频")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(LocalMediaPlayer.timeString(controller.currentTime)) / \(LocalMediaPlayer.timeString(controller.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { controller.currentTime },
                    set: { controller.seek(to: $0) }
                ),
                in: 0...max(1, controller.duration)
            )
            .disabled(controller.duration <= 0)

            Text(item.kind == .video
                 ? "点右上角按钮全屏 · 长按画面临时倍速，松手还原"
                 : "长按上方音轨面板临时倍速，松手还原")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
