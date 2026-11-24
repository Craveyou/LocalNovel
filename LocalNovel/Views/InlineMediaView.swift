import SwiftUI
import UIKit

// MARK: - 章节内插图（静态图降采样 / 动图逐帧播放 / 点击放大）
// 可见性放在【本视图自己】的 @State 里：滚动时只重绘这一张图，
// 不再让父级 ReaderView 整页重算（此前是滑动卡顿的主要来源之一）。

struct InlineMediaView: View {
    let item: MediaItem
    let onTap: () -> Void

    @State private var staticImage: UIImage?
    @State private var onScreen = false

    // 显式 init：避免编译器合成的 memberwise init 把带默认值的 @State
    // 参数排到 onTap 后面，导致尾随闭包匹配错参数。
    init(item: MediaItem, onTap: @escaping () -> Void) {
        self.item = item
        self.onTap = onTap
    }

    var body: some View {
        Group {
            if item.kind == .animatedImage {
                AnimatedImageView(url: item.url, isVisible: onScreen)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(Color.black.opacity(0.04))
            } else if let image = staticImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.08))
                    ProgressView()
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(6)
                .background(Color.black.opacity(0.45), in: Circle())
                .padding(8)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onAppear {
            onScreen = true
            if item.kind != .animatedImage, staticImage == nil {
                staticImage = ImageLoader.load(url: item.url)
            }
        }
        .onDisappear { onScreen = false }
    }
}
