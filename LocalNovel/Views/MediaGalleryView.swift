import SwiftUI
import UIKit

// MARK: - 沉浸式全屏插图浏览
// 从阅读器点击任意插图进入：纯黑铺满、整页吸附翻页、单击关闭、双击放大。
//
// 本版修复「左右滑动停在两张图中间」：
// 旧实现用 TabView(.page) 且页内嵌 UIScrollView，横向手势被内层吃掉、
// 分页吸附按错误宽度计算，就会停在半页。现改用 iOS 17+ 原生分页：
//   * 每页 .containerRelativeFrame([.horizontal, .vertical]) 精确等于视口
//   * .scrollTargetLayout() + .scrollTargetBehavior(.paging) 按整页吸附
//   * .scrollPosition(id:) 记录当前页，首次布局即定位到点击的那张
//   * ZoomableImageView 未放大时禁用自身滚动，把横向滑动完整交给外层

struct MediaGalleryView: View {
    let items: [MediaItem]

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?

    init(items: [MediaItem], initial: MediaItem) {
        self.items = items
        _selection = State(initialValue: initial.id)
    }

    private var currentIndex: Int {
        guard let selection else { return 1 }
        return (items.firstIndex(where: { $0.id == selection }) ?? 0) + 1
    }

    private var currentItem: MediaItem? {
        guard let selection else { return nil }
        return items.first(where: { $0.id == selection })
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { item in
                        GalleryPage(item: item, onSingleTap: { dismiss() })
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selection)
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
             + "单击关闭 · 左右滑动翻页 · 双击放大")
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
    let onSingleTap: () -> Void

    @State private var staticImage: UIImage?
    @State private var zoomed = false

    var body: some View {
        Group {
            if item.kind == .animatedImage {
                AnimatedImageView(url: item.url, isVisible: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(zoomed ? 2.0 : 1.0)
                    // 双击优先：exclusively 保证双击放大时不会误触发单击关闭
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded { withAnimation(.easeInOut(duration: 0.2)) { zoomed.toggle() } }
                            .exclusively(before: TapGesture(count: 1).onEnded { onSingleTap() })
                    )
            } else if let image = staticImage {
                ZoomableImageView(image: image, onSingleTap: onSingleTap)
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
