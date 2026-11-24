import SwiftUI

// MARK: - 分类卡片（书库首页 与 NAS 页共用）
//
// 两处的「大类入口」必须是同一套视觉：图标圆角底 + 标题 + 一行说明 + 右侧数量 + chevron。
// 抽成一个视图，避免以后只改了一边、两边长得不一样。

struct CategoryCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    /// 右侧数量文案；nil 表示还在统计（不占位）
    var countText: String?
    /// 未就绪（如 NAS 还在连接）时整体置灰
    var isDimmed: Bool = false

    private var accent: Color { isDimmed ? .secondary : .accentColor }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(accent)
                .frame(width: 46, height: 46)
                .background(accent.opacity(isDimmed ? 0.08 : 0.12),
                            in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isDimmed ? Color.secondary : Color.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let countText {
                Text(countText)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(isDimmed || countText == "0" ? Color.secondary : Color.primary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
