import SwiftUI
import AVKit
import AVFoundation

/// 章末视频 / 短剧单集：点击播放、不自动播放；支持全屏。
/// 参照 LocalNovel LocalMediaPlayer 的核心能力，精简为 AVKit VideoPlayer。
struct LNVideoView: View {
    let item: LNMediaItem
    let source: any LNLibrarySource

    @State private var player: AVPlayer?
    @State private var duration: Double?
    @State private var failed = false
    @State private var fullscreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if failed {
                Label("无法播放：\(item.fileName)", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let player {
                VideoPlayer(player: player)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            fullscreen = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.45), in: Circle())
                                .padding(8)
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
            }
        }
        .task(id: item.path) { await load() }
        .fullScreenCover(isPresented: $fullscreen) {
            LNVideoFullscreen(item: item, source: source)
        }
    }

    private func load() async {
        guard player == nil, !failed else { return }
        guard let url = try? await source.localURL(for: item.path) else {
            failed = true
            return
        }
        let p = AVPlayer(url: url)
        player = p
        let asset = AVURLAsset(url: url)
        if let cm = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(cm)
            if seconds.isFinite, seconds > 0 { duration = seconds }
        }
    }

    private func timeText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60, s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct LNVideoFullscreen: View {
    let item: LNMediaItem
    let source: any LNLibrarySource
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ReadingNavigationStack {
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView()
                }
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task {
            if let url = try? await source.localURL(for: item.path) {
                player = AVPlayer(url: url)
            }
        }
    }
}
