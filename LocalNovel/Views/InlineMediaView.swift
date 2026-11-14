import SwiftUI
import UIKit

// MARK: - 章节内插图（静态图降采样 / 动图逐帧播放 / 点击放大）

struct InlineMediaView: View {
    let item: MediaItem
    let isVisible: Bool
    let onTap: () -> Void

    @State private var staticImage: UIImage?

    var body: some View {
        Group {
            if item.kind == .animatedImage {
                AnimatedImageView(url: item.url, isVisible: isVisible)
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
            // 明确提示：点击可进入沉浸式全屏
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
            if item.kind != .animatedImage, staticImage == nil {
                staticImage = ImageLoader.load(url: item.url)
            }
        }
    }
}
