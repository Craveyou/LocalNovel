import SwiftUI
import UIKit

// MARK: - 沉浸式全屏插图浏览
// 交互（本版）：
//   * 单击：切换顶部遮罩（关闭按钮 / 页码 / 文件名）显隐，底部不再常驻操作提示
//   * 上滑：关闭大图（跟手位移，松手判定）
//   * 最后一张继续右滑：关闭大图
//   * 关闭时把当前图片回传给阅读器，由阅读器滚动定位回这张图
//   * 左右整页吸附翻页、双击放大保持不变
//
// 兼容性要点：
//   * 分页仍用 iOS 17+ 原生 scrollTargetBehavior(.paging) + containerRelativeFrame，
//     保证「不会停在两张图中间」。
//   * 关闭手势用 simultaneousGesture，避免抢走 ScrollView 的横向翻页。
//   * 图片一旦放大（zoomedId != nil），关闭手势全部让位给图片自身的平移，
//     否则放大后上滑看局部会被误判为关闭。

struct MediaGalleryView: View {
    let items: [MediaItem]
    let onClose: (MediaItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selection: String?
    @State private var chromeVisible = true
    /// 上滑跟手位移（负值 = 向上）
    @State private var verticalDrag: CGFloat = 0
    /// 最后一页右滑跟手位移
    @State private var edgePull: CGFloat = 0
    /// 当前被放大的图片 id；非 nil 时禁用关闭手势
    @State private var zoomedId: String?

    init(items: [MediaItem], initial: MediaItem, onClose: @escaping (MediaItem) -> Void) {
        self.items = items
        self.onClose = onClose
        _selection = State(initialValue: initial.id)
    }

    private var currentIndex: Int {
        guard let selection,
              let index = items.firstIndex(where: { $0.id == selection }) else { return -1 }
        return index
    }

    private var currentItem: MediaItem? {
        let index = currentIndex
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    private var isLastPage: Bool {
        let index = currentIndex
        return index >= 0 && index == items.count - 1
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { item in
                        GalleryPage(
                            item: item,
                            onSingleTap: { toggleChrome() },
                            onZoomChanged: { zoomed in
                                if zoomed {
                                    zoomedId = item.id
                                } else if zoomedId == item.id {
                                    zoomedId = nil
                                }
                            }
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selection)
            .ignoresSafeArea()
            .offset(y: verticalDrag)
            .offset(x: edgePull)
            .scaleEffect(verticalDrag < 0 ? max(0.86, 1 + verticalDrag / 1200) : 1)
        }
        // 关闭手势与外层横向翻页同时识别，互不抢占
        .simultaneousGesture(closeGesture)
        .overlay(alignment: .top) {
            if chromeVisible {
                topBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: 顶部遮罩（单击显隐）

    private var topBar: some View {
        HStack {
            Button { close() } label: {
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
                Text("\(max(1, currentIndex + 1)) / \(items.count)")
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

    // MARK: 手势：上滑关闭 / 末页右滑关闭

    private var closeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard zoomedId == nil else { return }
                let dx = value.translation.width
                let dy = value.translation.height

                if abs(dy) >= abs(dx) {
                    // 只跟随上滑；下滑不动，避免与翻页/回弹打架
                    verticalDrag = dy < 0 ? max(dy * 0.9, -260) : 0
                    edgePull = 0
                } else {
                    verticalDrag = 0
                    // 只有最后一页的右滑才跟手，作为「关闭」的预备动作
                    edgePull = (isLastPage && dx > 0) ? min(dx * 0.3, 130) : 0
                }
            }
            .onEnded { value in
                guard zoomedId == nil else {
                    settleBack()
                    return
                }
                let dx = value.translation.width
                let dy = value.translation.height
                let swipedUp = dy < -90 && abs(dy) > abs(dx)
                let pulledAtLastPage = isLastPage && dx > 90 && abs(dx) > abs(dy)

                if swipedUp || pulledAtLastPage {
                    close()
                } else {
                    settleBack()
                }
            }
    }

    private func settleBack() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            verticalDrag = 0
            edgePull = 0
        }
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() }
    }

    private func close() {
        // 先回传当前图片：阅读器据此在关闭后滚动定位回这张
        if let item = currentItem { onClose(item) }
        dismiss()
    }
}

// MARK: - 单页

private struct GalleryPage: View {
    let item: MediaItem
    let onSingleTap: () -> Void
    let onZoomChanged: (Bool) -> Void

    @State private var staticImage: UIImage?
    @State private var zoomed = false

    var body: some View {
        Group {
            if item.kind == .animatedImage {
                AnimatedImageView(url: item.url, isVisible: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(zoomed ? 2.0 : 1.0)
                    // 双击优先：exclusively 保证双击放大时不会误触发单击
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded {
                                withAnimation(.easeInOut(duration: 0.2)) { zoomed.toggle() }
                                onZoomChanged(zoomed)
                            }
                            .exclusively(before: TapGesture(count: 1).onEnded { onSingleTap() })
                    )
            } else if let image = staticImage {
                ZoomableImageView(image: image,
                                  onSingleTap: onSingleTap,
                                  onZoomChanged: onZoomChanged)
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
