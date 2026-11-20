import SwiftUI
import UIKit

// MARK: - 沉浸式全屏插图浏览
// 交互（本版）：
//   * 单击：切换顶部遮罩（关闭按钮 / 页码 / 文件名）显隐，底部不再常驻操作提示
//     遮罩隐藏时连系统状态栏、Home 指示条一起隐藏，真正全屏看图
//   * 下滑：关闭大图（向下拖跟手、图片略微缩小，松手过阈就退出）
//   * 最后一张从右边缘继续左滑：关闭大图（左滑本就是「下一张」，到底了顺势退出；
//     只在右边缘起手才认，中间左滑只回弹，不会误关）
//   * 关闭时把当前图片回传给阅读器，由阅读器滚动定位回这张图
//   * 左右整页吸附翻页、双击放大保持不变
//
// 兼容性要点：
//   * 分页仍用 iOS 17+ 原生 scrollTargetBehavior(.paging) + containerRelativeFrame，
//     保证「不会停在两张图中间」。
//   * 关闭手势用 simultaneousGesture，避免抢走 ScrollView 的横向翻页。
//   * 图片一旦放大（zoomedId != nil），关闭手势全部让位给图片自身的平移，
//     否则放大后下滑看局部会被误判为关闭。

struct MediaGalleryView: View {
    let items: [MediaItem]
    let onClose: (MediaItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selection: String?
    @State private var chromeVisible = true
    /// 下滑跟手位移（正值 = 向下）
    @State private var verticalDrag: CGFloat = 0
    /// 最后一页从右边缘左滑的跟手位移（负值 = 向左）
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
        // 手势要判「是否从右边缘起手」，需要当前视图宽度
        GeometryReader { geo in
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
                .scaleEffect(1 - min(verticalDrag, 300) / 1600)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 关闭手势与外层横向翻页同时识别，互不抢占
            .simultaneousGesture(closeGesture(width: geo.size.width))
        }
        .overlay(alignment: .top) {
            if chromeVisible {
                topBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        // 遮罩隐藏时状态栏、Home 指示条一起让位；单击唤回遮罩时同步恢复
        .statusBarHidden(!chromeVisible)
        .persistentSystemOverlays(chromeVisible ? .visible : .hidden)
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

    // MARK: 手势：下滑关闭 / 末页右边缘左滑关闭

    private func closeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard zoomedId == nil else { return }
                let dx = value.translation.width
                let dy = value.translation.height

                if abs(dy) >= abs(dx) {
                    // 只跟随下滑；上滑不动，避免与翻页/回弹打架
                    verticalDrag = dy > 0 ? min(dy * 0.9, 300) : 0
                    edgePull = 0
                } else {
                    verticalDrag = 0
                    // 只有最后一页、且从右边缘起手的「继续左滑」才跟手，作为关闭的预备动作
                    edgePull = (isLastPage && dx < 0 && fromRightEdge(value, width: width))
                        ? max(dx * 0.3, -130) : 0
                }
            }
            .onEnded { value in
                guard zoomedId == nil else {
                    settleBack()
                    return
                }
                let dx = value.translation.width
                let dy = value.translation.height
                let swipedDown = dy > 110 && abs(dy) > abs(dx)
                let swipedPastEnd = isLastPage
                    && dx < -90 && abs(dx) > abs(dy)
                    && fromRightEdge(value, width: width)

                if swipedDown || swipedPastEnd {
                    close()
                } else {
                    settleBack()
                }
            }
    }

    /// 起手点落在右侧边缘 44pt 内：只有这里才当作「想继续往后翻，但已经到底」
    private func fromRightEdge(_ value: DragGesture.Value, width: CGFloat) -> Bool {
        width > 0 && value.startLocation.x >= width - 44
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
