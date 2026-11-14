import SwiftUI
import UIKit

// MARK: - 漫画页（满宽、无圆角、无间距）
// 与小说插图不同：漫画整页就是内容，不需要圆角卡片与「可放大」角标，
// 直接铺满宽度纵向连排；点一下进全屏画廊（沿用同一套手势与遮罩）。

struct ComicPageView: View {
    let item: MediaItem
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var onScreen = false

    init(item: MediaItem, onTap: @escaping () -> Void) {
        self.item = item
        self.onTap = onTap
    }

    var body: some View {
        Group {
            if item.kind == .animatedImage {
                AnimatedImageView(url: item.url, isVisible: onScreen)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            } else {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: 320)
                    .overlay(ProgressView())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onAppear {
            onScreen = true
            if item.kind != .animatedImage, image == nil {
                image = ImageLoader.load(url: item.url, maxPixel: 1800)
            }
        }
        .onDisappear { onScreen = false }
    }
}
