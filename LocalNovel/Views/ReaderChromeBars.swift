import SwiftUI

// MARK: - 阅读菜单：顶部条 / 底部条（只作用于「小说」）
//
// 版式对齐千阅：
//   顶部：‹ 返回 | 书名（或章节名） ....... 右侧文字动作（文本编码）
//   底部：上一章 | 全书进度滑杆 | 下一章
//         ──────  工具行：目录 / 白天 / 主题 / 排版 / 设置  ──────
//
// 两条都贴在安全区上，中间区域留给正文；单击正文中间收起 / 弹出。
// 颜色全部取当前主题，深色主题下不会出现白底条。

struct ReaderTopBar: View {
    let title: String
    let subtitle: String?
    /// 右侧文字动作（如「文本编码」）；nil 时不显示
    let trailing: String?
    let theme: ReaderTheme
    let onBack: () -> Void
    let onTrailing: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.uiText)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.uiText)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.uiHeaderFooter)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let trailing {
                Button(action: onTrailing) {
                    Text(trailing)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.uiText)
                        .padding(.horizontal, 6)
                        .frame(height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .background(theme.uiBackground.opacity(0.97))
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.uiSeparator).frame(height: 0.5)
        }
    }
}

struct ReaderBottomBar: View {
    let theme: ReaderTheme
    /// 全书进度（0...1）
    let progress: Double
    /// 拖动过程中的目标章节名，用于浮动提示
    let draggingTitle: String?
    let hasPrevious: Bool
    let hasNext: Bool
    let isNight: Bool
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onScrub: (Double) -> Void
    let onScrubEnd: (Double) -> Void
    let onCatalog: () -> Void
    let onDayNight: () -> Void
    let onTheme: () -> Void
    let onTypography: () -> Void
    let onSettings: () -> Void

    @State private var dragValue: Double?

    private var shownValue: Double { dragValue ?? progress }

    var body: some View {
        VStack(spacing: 0) {
            // 上一章 / 进度 / 下一章
            HStack(spacing: 10) {
                Button(action: onPreviousChapter) {
                    Text("上一章")
                        .font(.system(size: 13))
                        .foregroundStyle(hasPrevious ? theme.uiText : theme.uiHeaderFooter.opacity(0.5))
                        .frame(height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasPrevious)

                ZStack(alignment: .top) {
                    Slider(value: Binding(get: { shownValue },
                                          set: { value in
                                              dragValue = value
                                              onScrub(value)
                                          }),
                           in: 0...1,
                           onEditingChanged: { editing in
                               if editing {
                                   dragValue = progress
                               } else {
                                   let value = dragValue ?? progress
                                   onScrubEnd(value)
                                   dragValue = nil
                               }
                           })
                        .tint(Color.accentColor)
                        .controlSize(.small)

                    if let draggingTitle, dragValue != nil {
                        Text(draggingTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.uiText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(theme.uiBackground.opacity(0.96),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(theme.uiSeparator, lineWidth: 0.5)
                            }
                            .offset(y: -26)
                            .allowsHitTesting(false)
                    }
                }

                Button(action: onNextChapter) {
                    Text("下一章")
                        .font(.system(size: 13))
                        .foregroundStyle(hasNext ? theme.uiText : theme.uiHeaderFooter.opacity(0.5))
                        .frame(height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasNext)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            // 工具行
            HStack(alignment: .top, spacing: 0) {
                tool("目录", systemImage: "list.bullet", action: onCatalog)
                tool(isNight ? "白天" : "夜间",
                     systemImage: isNight ? "sun.max" : "moon",
                     action: onDayNight)
                tool("主题", systemImage: "paintpalette", action: onTheme)
                tool("排版", systemImage: "textformat.size", action: onTypography)
                tool("设置", systemImage: "gearshape", action: onSettings)
            }
            .padding(.top, 8)
            .padding(.bottom, 6)
            .padding(.horizontal, 6)
        }
        .background(theme.uiBackground.opacity(0.97))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.uiSeparator).frame(height: 0.5)
        }
    }

    private func tool(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .regular))
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundStyle(theme.uiText)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 右侧浮动圆钮（对齐千阅：书签 / 目录 / 主题）
//
// 只在菜单栏展开时出现，贴在右边、底部工具行之上；不挡正文时完全不可见，
// 也不吃点击（外层 allowsHitTesting 由调用方控制）。

struct ReaderFloatingActions: View {
    let theme: ReaderTheme
    let isBookmarked: Bool
    let onBookmark: () -> Void
    let onCatalog: () -> Void
    let onTheme: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            circle(isBookmarked ? "bookmark.fill" : "bookmark",
                   tint: isBookmarked ? Color.accentColor : theme.uiText,
                   action: onBookmark)
            circle("list.bullet", tint: theme.uiText, action: onCatalog)
            circle("paintpalette", tint: theme.uiText, action: onTheme)
        }
        .padding(.trailing, 10)
    }

    private func circle(_ systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(theme.uiBackground.opacity(0.92), in: Circle())
                .overlay {
                    Circle().strokeBorder(theme.uiSeparator, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
    }
}
