import Foundation
import SwiftUI
import UIKit
import QuartzCore

// MARK: - 自动阅读的底层设施（千阅 I 组）
//
// 两套引擎的「自动」含义不同：
//   · 翻页：定时给分页器下一条翻页指令（走 pageCommand 通道，和手势翻页同一条路）
//   · 滚动：匀速推进 contentOffset
//
// 滚动为什么不能纯 SwiftUI：ScrollView 没有「按像素前进」的接口，scrollTo 只能按锚点跳，
// 按段落跳一下一大截，做不出千阅那种匀速。这里把底下的 UIScrollView 找出来按帧推，
// 只用到最老的公开 API（superview 链 / setContentOffset / CADisplayLink）。

/// 自动滚动驱动器（单例：ReaderView 会按章重建，驱动不能跟着重置）
final class AutoScrollDriver: NSObject {
    static let shared = AutoScrollDriver()

    private weak var scrollView: UIScrollView?
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    /// 触底只报一次，回卷后重新武装
    private var bottomReported = false

    /// 每秒推进多少点
    var speed: CGFloat = 40
    /// 滚到底（后续由上层决定「进下一章」还是「停止」）
    var onReachBottom: (() -> Void)?

    var isRunning: Bool { link != nil }

    private override init() { super.init() }

    func attach(_ view: UIScrollView) {
        scrollView = view
    }

    func start() {
        guard link == nil else { return }
        bottomReported = false
        lastTime = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)   // common：手指按住 / 惯性中也不停
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTime = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let scroll = scrollView else { return }
        // 用户上手了就让位：拖动 / 惯性期间不推，松手后自己接着走
        if scroll.isTracking || scroll.isDecelerating { lastTime = link.timestamp; return }

        let now = link.timestamp
        let dt = lastTime == 0 ? 0 : min(now - lastTime, 0.1)  // 后台回来那一帧别一次跳一大截
        lastTime = now
        guard dt > 0 else { return }

        let maxY = scroll.contentSize.height - scroll.bounds.height + scroll.contentInset.bottom
        let next = scroll.contentOffset.y + speed * CGFloat(dt)
        if next >= maxY - 0.5 {
            if !bottomReported {
                bottomReported = true
                onReachBottom?()
            }
            if contentFits(scroll) { return }   // 短章一屏都不到：等上层切章
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: maxY), animated: false)
            return
        }
        bottomReported = false
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: next), animated: false)
    }

    /// 正文连一屏都填不满（极短章 / 图片未加载完）
    private func contentFits(_ scroll: UIScrollView) -> Bool {
        scroll.contentSize.height <= scroll.bounds.height + 1
    }
}

/// 0 高度的探针，挂在滚动正文里，把宿主 UIScrollView 交给 driver
struct AutoScrollProbe: UIViewRepresentable {
    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var node = superview
            while let view = node {
                if let scroll = view as? UIScrollView {
                    AutoScrollDriver.shared.attach(scroll)
                    return
                }
                node = view.superview
            }
        }
    }

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}
}

/// 自动阅读是否开着。
/// ReaderView 切章时整棵重建（RootView 用 .id(chapter.id)），@State 活不过去，
/// 而自动阅读必须跨章连续，所以开关放进程级静态位：新章 onAppear 时接着跑。
/// 退出阅读 / 换书时由 RootView 清掉，避免下次进书莫名其妙自己翻页。
enum AutoReadFlag {
    static var isOn = false
}
