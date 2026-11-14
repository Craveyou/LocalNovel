import SwiftUI
import UIKit

// MARK: - 沉浸式全屏插图浏览
// 从阅读器点击任意插图进入：纯黑铺满、左右翻页、静态图捏合/双击缩放、
// 动图全屏逐帧播放并支持双击放大。顶部工具条为悬浮层，不占阅读区域。

struct MediaGalleryView: View {
    let items: [MediaItem]
    let initial: MediaItem

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String

    init(items: [MediaItem], initial: MediaItem) {
        self.items = items
        self.initial = initial
        _selection = State(initialValue: initial.id)
    }

    private var currentIndex: Int {
        (items.firstIndex(where: { $0.id == selection }) ?? 0) + 1
    }

    private var currentItem: MediaItem? {
        items.first(where: { $0.id == selection })
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(items) { item in
                    GalleryPage(item: item)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { bottomHint }
        .persistentSystemOverlays(.hidden)
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
            .accessibilityLabel("关闭全屏")

            Spacer()

            VStack(spacing: 1) {
                Text("\(currentIndex) / \(items.count)")
                    .font(.subheadline.weight(.semibold))
                if let item = currentItem {
                    Text(item.fileName)
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

    private var bottomHint: some View {
        Text((currentItem?.kind == MediaKind.animatedImage ? "动图自动播放 · " : "")
             + "左右滑动翻页 · 双击或捏合放大")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.45), in: Capsule())
            .padding(.bottom, 18)
            .allowsHitTesting(false)
    }
}

// MARK: - 单页

private struct GalleryPage: View {
    let item: MediaItem
    @State private var staticImage: UIImage?
    @State private var zoomed = false

    var body: some View {
        Group {
            if item.kind == .animatedImage {
                AnimatedImageView(url: item.url, isVisible: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(zoomed ? 2.0 : 1.0)
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) { zoomed.toggle() }
                    }
            } else if let image = staticImage {
                ZoomableImageView(image: image)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            if item.kind != .animatedImage, staticImage == nil {
                staticImage = ImageLoader.load(url: item.url, maxPixel: 2400)
            }
        }
    }
}
