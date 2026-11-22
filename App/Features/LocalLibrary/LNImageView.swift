import SwiftUI
import UIKit

/// 章节插图：静态图降采样 + 点击放大占位。
/// 动图在阶段 5 接入 AnimatedImageView；这里先按静态首帧显示。
struct LNImageView: View {
    let item: LNMediaItem
    let source: any LNLibrarySource
    let onTap: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
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
        .task {
            guard image == nil else { return }
            if let url = try? await source.localURL(for: item.path),
               let data = try? Data(contentsOf: url, options: .mappedIfSafe),
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
