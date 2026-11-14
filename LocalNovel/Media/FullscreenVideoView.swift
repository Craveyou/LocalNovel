import Foundation
import SwiftUI
import AVFoundation
import AVKit
import UIKit

// MARK: - 全屏视频播放
// 关键点：与内联播放器共享同一个 AVPlayer 实例，进入/退出全屏不中断播放、不丢进度。
// 系统 AVPlayerViewController 自带播放/暂停、进度拖动、字幕与音量控件，无需自己重写一套。
// 明确关闭画中画：用户要求不后台播放，且画中画会在 App 退出后继续出画。

struct FullscreenVideoView: View {
    @ObservedObject var controller: LocalMediaPlayer
    let boostRate: Double

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            FullscreenPlayerHost(player: controller.player) { active in
                controller.setBoost(active, rate: boostRate)
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .center) { boostBadge }
        .overlay(alignment: .bottom) { hint }
        .persistentSystemOverlays(.hidden)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("退出全屏")

            Spacer()
            Text("全屏播放")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color.black.opacity(0.55))
    }

    private var boostBadge: some View {
        Group {
            if controller.isBoosting {
                Text(String(format: "%.1f× 快进中", boostRate))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .allowsHitTesting(false)
            }
        }
    }

    private var hint: some View {
        Text("长按画面临时倍速，松手恢复原速")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.4), in: Capsule())
            .padding(.bottom, 22)
            .allowsHitTesting(false)
    }
}

// MARK: - AVPlayerViewController 宿主（长按照样挂上）

struct FullscreenPlayerHost: UIViewControllerRepresentable {
    let player: AVPlayer
    let onBoost: (Bool) -> Void

    func makeCoordinator() -> RateBoostCoordinator {
        RateBoostCoordinator(onChange: onBoost)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        RateBoostGesture.attach(to: controller.view, coordinator: context.coordinator)
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
