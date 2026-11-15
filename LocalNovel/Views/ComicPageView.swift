import SwiftUI
import UIKit

// MARK: - 漫画页（满宽、无圆角、无间距）
//
// 与上一版的区别：
// · 页高按图片真实宽高比算出来（读文件头，很快且带缓存），
//   LazyVStack 不再「先猜一个高度、图片到了再变」，滚动不会再抖。
// · 图片用 TiledImage（CATiledLayer 分块绘制）而不是 maxPixel 降采样，
//   条漫不会被缩成 120 像素宽再拉伸，1:1 像素显示。
// · 解码不在主线程 onAppear 里同步做，滚动不卡。
// 点一下进全屏画廊（沿用同一套手势与遮罩）。

struct ComicPageView: View {
    let item: MediaItem
    /// 由阅读器传入的可用宽度；满宽绘制，不做左右留白
    let width: CGFloat
    let onTap: () -> Void

    @State private var aspect: CGFloat
    @State private var onScreen = false

    init(item: MediaItem, width: CGFloat, onTap: @escaping () -> Void) {
        self.item = item
        self.width = width
        self.onTap = onTap
        // 同步读文件头拿宽高比：只解析 header，不加载像素，且带缓存
        let pixel = ComicImageStore.shared.pixelSize(of: item.url)
        let ratio = pixel.map { $0.height / max($0.width, 1) } ?? 1.45
        _aspect = State(initialValue: ratio)
    }

    private var pageWidth: CGFloat { max(width, 1) }
    private var pageHeight: CGFloat { max(pageWidth * aspect, 40) }

    var body: some View {
        Group {
            if item.kind == .animatedImage {
                AnimatedImageView(url: item.url, isVisible: onScreen)
                    .frame(width: pageWidth, height: pageHeight)
            } else {
                TiledImage(url: item.url)
                    .frame(width: pageWidth, height: pageHeight)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onAppear {
            onScreen = true
            // 高度算错过（读不到 header）时，进入屏幕后再纠正一次
            if let pixel = ComicImageStore.shared.pixelSize(of: item.url), pixel.width > 0 {
                let ratio = pixel.height / pixel.width
                if abs(ratio - aspect) > 0.001 { aspect = ratio }
            }
        }
        .onDisappear { onScreen = false }
    }
}
