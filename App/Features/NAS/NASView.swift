import SwiftUI

/// NAS 页占位骨架。底层已有 Server / WebDAV 数据模型，连接与浏览界面尚未实现。
/// 后续可直接在此文件中替换为完整功能页面，tab 与基础版式保持不变。
struct NASView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                placeholder
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(ReadingTheme.canvas.ignoresSafeArea())
        .navigationBarHidden(true)
        .accessibilityIdentifier("nas.scroll")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("NAS")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Image(systemName: "network")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(ReadingTheme.ink.opacity(0.6))
                    .frame(width: 44, height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(ReadingTheme.groupedCanvas.opacity(0.75))
                    }
                    .accessibilityHidden(true)
            }
            Text("网络存储，随处阅读")
                .font(.subheadline)
                .foregroundStyle(ReadingTheme.ink.opacity(0.55))
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
        .padding(.bottom, 26)
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(ReadingTheme.ink.opacity(0.35))
                .accessibilityHidden(true)
            Text("敬请期待")
                .font(.headline)
                .foregroundStyle(ReadingTheme.ink.opacity(0.75))
            Text("这里即将呈现网络存储的接入与浏览")
                .font(.subheadline)
                .foregroundStyle(ReadingTheme.ink.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
        .accessibilityElement(children: .combine)
    }
}
