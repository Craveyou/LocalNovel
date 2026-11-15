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

    /// 点第几张进全屏；nil = 没在看大图
    @State private var galleryIndex: Int?

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries.indices, id: \.self) { index in
                        RemoteImage(url: entries[index].url, account: account)
                            .frame(width: geo.size.width)
                            // 滑到这张就顺手把前后各两张拉进缓存（共 4 个并发，见 RemoteImageCache）
                            .onAppear { prefetch(around: index) }
                            // 点图看大图：可捏合放大、左右翻、上滑关闭
                            .contentShape(Rectangle())
                            .onTapGesture { galleryIndex = index }
                    }
                    Text("共 \(entries.count) 张 · 点图看大图")
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
        .fullScreenCover(item: Binding(
            get: { galleryIndex.map(RemoteGalleryTarget.init(index:)) },
            set: { galleryIndex = $0?.index }
        )) { target in
            RemoteGalleryView(entries: entries,
                              startIndex: target.index,
                              account: account,
                              title: title)
        }
    }

    /// 预取前后各两张：往前翻、往后翻都不用等
    private func prefetch(around index: Int) {
        guard !entries.isEmpty else { return }
        var urls: [URL] = []
        for offset in [-2, -1, 1, 2] {
            let target = index + offset
            if target >= 0, target < entries.count, target != index {
                urls.append(entries[target].url)
            }
        }
        guard !urls.isEmpty else { return }
        RemoteImageCache.shared.prefetch(urls, account: account)
    }
}

// MARK: - 远端图片全屏画廊
//
// 与本地 MediaGalleryView 同一套交互：左右整页吸附、双击放大、单击显隐遮罩、上滑关闭。
// 区别只在图片来源：这里带认证头走 RemoteImageCache，拿到 UIImage 后复用 ZoomableImageView。

struct RemoteGalleryTarget: Identifiable {
    let index: Int
    var id: Int { index }
}

struct RemoteGalleryView: View {
    let entries: [RemoteEntry]
    let startIndex: Int
    let account: WebDAVAccount
    var title: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var chromeVisible = true
    @State private var verticalDrag: CGFloat = 0

    init(entries: [RemoteEntry], startIndex: Int,
         account: WebDAVAccount, title: String = "") {
        self.entries = entries
        self.startIndex = startIndex
        self.account = account
        self.title = title
        let safe = entries.indices.contains(startIndex) ? startIndex : 0
        _selection = State(initialValue: entries.indices.contains(safe) ? entries[safe].id : nil)
    }

    private var currentIndex: Int {
        guard let selection,
              let index = entries.firstIndex(where: { $0.id == selection }) else { return startIndex }
        return index
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(entries) { entry in
                        RemoteGalleryPage(entry: entry,
                                          account: account,
                                          onSingleTap: { toggleChrome() })
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(entry.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selection)
            .ignoresSafeArea()
            .offset(y: verticalDrag)
            .scaleEffect(verticalDrag < 0 ? max(0.86, 1 + verticalDrag / 1200) : 1)
        }
        .simultaneousGesture(closeGesture)
        .overlay(alignment: .top) { if chromeVisible { topBar } }
        .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        .statusBarHidden(!chromeVisible)
        .persistentSystemOverlays(chromeVisible ? .visible : .hidden)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭大图")

            Spacer()

            VStack(spacing: 1) {
                Text("\(max(1, currentIndex + 1)) / \(entries.count)")
                    .font(.subheadline.weight(.semibold))
                if entries.indices.contains(currentIndex) {
                    Text(entries[currentIndex].name)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)

            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color.black.opacity(0.55))
    }

    private var closeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let dy = value.translation.height
                let dx = value.translation.width
                guard abs(dy) >= abs(dx) else { return }
                verticalDrag = dy < 0 ? max(dy * 0.9, -260) : 0
            }
            .onEnded { value in
                let dy = value.translation.height
                let dx = value.translation.width
                if dy < -90, abs(dy) > abs(dx) {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        verticalDrag = 0
                    }
                }
            }
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() }
    }
}

private struct RemoteGalleryPage: View {
    let entry: RemoteEntry
    let account: WebDAVAccount
    let onSingleTap: () -> Void

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black
            if let image {
                ZoomableImageView(image: image, onSingleTap: onSingleTap)
            } else if failed {
                Button {
                    Task { await load(force: true) }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark").font(.title2)
                        Text("加载失败，点此重试").font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: entry.id) { await load(force: false) }
    }

    private func load(force: Bool) async {
        failed = false
        if !force, let hit = RemoteImageCache.shared.cachedImage(for: entry.url) {
            image = hit
            return
        }
        let value = await RemoteImageCache.shared.image(for: entry.url, account: account)
        image = value
        failed = value == nil
    }
}

// MARK: - 远端视频（带认证头，Range 流式播放，不下载整部）
//
// 直接复用本地「整理 / 短剧」那套 MediaAttachmentView：
// 内联画面 → 全屏（可旋转）→ 长按倍速，三处入口的能力完全一致，
// 不再用系统 VideoPlayer（那个只有全屏，没有旋转与长按倍速）。

struct RemoteVideoView: View {
    let entry: RemoteEntry
    let account: WebDAVAccount

    @EnvironmentObject private var prefs: Preferences
    @ObservedObject private var videoMeta = VideoMetaStore.shared

    private var metaLine: String? {
        let info = videoMeta.info(for: entry.url)
        let size = VideoMetaFormat.size(entry.byteCount ?? info?.byteCount)
        let duration = VideoMetaFormat.duration(info?.seconds)
        let parts = [size, duration].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MediaAttachmentView(item: MediaItem(url: entry.url, kind: .video, sequence: nil),
                                    chapterId: "nas:\(entry.url.absoluteString)",
                                    boostRate: prefs.longPressRate,
                                    headers: WebDAVClient.headers(account: account))

                if let metaLine {
                    Text(metaLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Text("播放与「整理」里的视频一致：右上角全屏，全屏里可旋转画面，长按画面临时倍速。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { ReadingChrome.shared.enter() }
        .onDisappear { ReadingChrome.shared.leave() }
        .task {
            await VideoMetaStore.shared.load(entry.url,
                                             headers: WebDAVClient.headers(account: account),
                                             knownSize: entry.byteCount)
        }
    }
}
