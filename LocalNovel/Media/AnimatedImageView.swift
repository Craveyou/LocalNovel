import SwiftUI
import UIKit
import QuartzCore

// MARK: - 动图视图：CADisplayLink 逐帧播放，支持每帧不同延时、离屏暂停

final class AnimatedFrameView: UIView {
    private let imageView = UIImageView()
    private var link: CADisplayLink?
    private var currentURL: URL?
    private var frames: [AnimatedFrame] = []
    private var cumulative: [TimeInterval] = []
    private var total: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var lastTimestamp: TimeInterval = 0
    private var currentIndex = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        addSubview(imageView)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
    }

    func configure(url: URL, frames: [AnimatedFrame]) {
        guard currentURL != url, !frames.isEmpty else { return }
        currentURL = url
        self.frames = frames
        cumulative = []
        var acc: TimeInterval = 0
        for f in frames {
            acc += f.duration
            cumulative.append(acc)
        }
        total = max(acc, 0.02)
        elapsed = 0
        currentIndex = -1
        showFrame(at: 0)
    }

    func start() {
        guard link == nil, total > 0 else { return }
        lastTimestamp = 0
        let displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    func releaseFrames() {
        stop()
        frames = []
        cumulative = []
        imageView.image = nil
        currentURL = nil
        currentIndex = -1
    }

    @objc private func tick(_ link: CADisplayLink) {
        if lastTimestamp == 0 { lastTimestamp = link.timestamp }
        let delta = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        elapsed = (elapsed + delta).truncatingRemainder(dividingBy: total)

        var index = 0
        while index < cumulative.count - 1, cumulative[index] < elapsed { index += 1 }
        showFrame(at: index)
    }

    private func showFrame(at index: Int) {
        guard index != currentIndex, frames.indices.contains(index) else { return }
        currentIndex = index
        imageView.image = frames[index].image
    }
}

/// SwiftUI 包装：isVisible 由外层 LazyVStack 的 onAppear/onDisappear 驱动，离屏即暂停
struct AnimatedImageView: UIViewRepresentable {
    let url: URL
    let isVisible: Bool

    func makeUIView(context: Context) -> AnimatedFrameView {
        AnimatedFrameView(frame: .zero)
    }

    func updateUIView(_ uiView: AnimatedFrameView, context: Context) {
        uiView.configure(url: url, frames: AnimatedFrameCache.shared.frames(for: url))
        if isVisible { uiView.start() } else { uiView.stop() }
    }

    static func dismantleUIView(_ uiView: AnimatedFrameView, coordinator: ()) {
        uiView.releaseFrames()
    }
}
