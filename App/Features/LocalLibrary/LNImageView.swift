import SwiftUI
import UIKit

/// 章节插图：静态图降采样 + 动图逐帧播放 + 点击放大。
/// 动图离屏暂停由子视图自己管理，避免滚动时整页重绘。
struct LNImageView: View {
    let item: LNMediaItem
    let source: any LNLibrarySource
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var url: URL?
    @State private var onScreen = false

    var body: some View {
        Group {
            if item.kind == .animatedImage, let url {
                LNAnimatedImageView(url: url, isVisible: onScreen)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(Color.black.opacity(0.04))
            } else if let image {
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
                .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .task {
            guard url == nil else { return }
            guard let resolved = try? await source.localURL(for: item.path) else { return }
            url = resolved
            guard item.kind != .animatedImage else { return }
            if let data = try? Data(contentsOf: resolved, options: .mappedIfSafe),
               let ui = UIImage(data: data) {
                image = downsample(ui)
            }
        }
    }

    /// 大图降采样到屏幕宽度级别，避免一张 4000px 图占满内存
    private func downsample(_ image: UIImage) -> UIImage {
        let maxSide: CGFloat = 1600
        let w = image.size.width, h = image.size.height
        let scale = min(1, maxSide / max(w, h))
        guard scale < 1 else { return image }
        let size = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
