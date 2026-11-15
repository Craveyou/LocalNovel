import SwiftUI
import Combine

// MARK: - 阅读沉浸状态（阅读时自动收起底部标签栏）
//
// 用计数而不是布尔：切章时 ReaderView 会 .id(chapter.id) 重建，
// 新旧视图的 appear / disappear 先后不保证，计数能避免「一瞬间闪回标签栏」。
// 只在主线程读写（onAppear / onDisappear 本身就在主线程）。

final class ReadingChrome: ObservableObject {
    static let shared = ReadingChrome()

    /// 当前是否有阅读界面在前台（文字 / 漫画 / 剧照 / 视频）
    @Published private(set) var isImmersive = false

    private var depth = 0

    private init() {}

    func enter() {
        depth += 1
        if !isImmersive { isImmersive = true }
    }

    func leave() {
        depth = max(0, depth - 1)
        if depth == 0, isImmersive { isImmersive = false }
    }

    /// 兜底：视图层级异常时（例如整页被替换）强制复位
    func reset() {
        depth = 0
        isImmersive = false
    }
}
