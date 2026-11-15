import SwiftUI
import UIKit
import AVKit
import AVFoundation

// MARK: - 远端图片（NAS 上的剧照 / 插图）
//
// 带认证头下载 → 内存 + 磁盘缓存；失败给可重试的占位，不阻塞整页。

struct RemoteImage: View {
    let url: URL
    let account: WebDAVAccount
    var cornerRadius: CGFloat = 0

    @State private var image: UIImage?
    @State private var failed = false
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    Rectangle().fill(Color.secondary.opacity(0.08))
                    if isLoading {
                        ProgressView()
                    } else if failed {
                        VStack(spacing: 8) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.title3)
                            Text("加载失败，点击重试")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .onTapGesture { Task { await load() } }
                    }
                }
                .frame(minHeight: 200)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: url) { await load() }
    }

    private func load() async {
        if let cached = RemoteImageCache.shared.cachedImage(for: url) {
            image = cached
            isLoading = false
            return
        }
        isLoading = true
        failed = false
        let value = await RemoteImageCache.shared.image(for: url, account: account)
        image = value
        failed = value == nil
        isLoading = false
    }
}

// MARK: - 远端剧照连排（与漫画同一形式：满宽、无间距、无圆角）

struct RemoteImageSequenceView: View {
    let title: String
    let entries: [RemoteEntry]
    let account: WebDAVAccount

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        RemoteImage(url: entry.url, account: account)
                            .frame(width: geo.size.width)
                    }
                    Text("共 \(entries.count) 张")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                }
            }
            .frame(width: geo.size.width)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.black.opacity(0.02))
        .onAppear { ReadingChrome.shared.enter() }
        .onDisappear { ReadingChrome.shared.leave() }
    }
}

// MARK: - 远端视频（带认证头，Range 流式播放，不下载整部）

struct RemoteVideoView: View {
    let entry: RemoteEntry
    let account: WebDAVAccount

    @ObservedObject private var videoMeta = VideoMetaStore.shared
    @State private var player: AVPlayer?
    @State private var failed = false

    private var metaLine: String? {
        let info = videoMeta.info(for: entry.url)
        let size = VideoMetaFormat.size(entry.byteCount ?? info?.byteCount)
        let duration = VideoMetaFormat.duration(info?.seconds)
        let parts = [size, duration].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let player {
                    VideoPlayer(player: player)
                } else if failed {
                    ContentUnavailableView("无法播放", systemImage: "exclamationmark.triangle",
                                           description: Text("检查 NAS 是否还在线、文件是否完整"))
                        .foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.name)
                    .font(.headline)
                if let metaLine {
                    Text(metaLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text("播放与「整理」里的视频一致：可全屏、可长按倍速。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Spacer(minLength: 0)
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ReadingChrome.shared.enter()
            prepare()
        }
        .onDisappear {
            ReadingChrome.shared.leave()
            player?.pause()
        }
        .task {
            await VideoMetaStore.shared.load(entry.url,
                                             headers: WebDAVClient.headers(account: account),
                                             knownSize: entry.byteCount)
        }
    }

    private func prepare() {
        guard player == nil else { player?.play(); return }
        let headers = WebDAVClient.headers(account: account)
        let asset = headers.isEmpty
            ? AVURLAsset(url: entry.url)
            : AVURLAsset(url: entry.url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let created = AVPlayer(playerItem: item)
        player = created
        created.play()
    }
}
