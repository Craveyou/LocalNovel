import SwiftUI

// MARK: - 阅读控制菜单（点屏幕中间弹出）
//
// 覆盖在阅读层之上，半透明背景点一下即收起。集中放「格式效果」与常用入口：
//   · 字号 / 行距：即时改写 Preferences，正文与分页引擎都会重建
//   · 翻页方式 / 外观：与「设置」同源，改完立即生效
//   · 文本编码：正文章才有（同一份编码菜单，按书记忆）
//   · 目录：弹出本书章节，点章跳转
//   · 退出阅读、字号重置
// 只依赖 Preferences / library 环境对象，不持有章节内容，切章时不重建。

struct ReaderControlsPanel: View {
    @EnvironmentObject private var prefs: Preferences

    let chapterTitle: String
    let showsEncoding: Bool
    let encodingMenu: AnyView
    let onTOC: () -> Void
    let onSettings: () -> Void
    let onExit: () -> Void
    let onDismiss: () -> Void

    private func binding<T>(for keyPath: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { prefs[keyPath: keyPath] },
                set: { prefs[keyPath: keyPath] = $0 })
    }

    var body: some View {
        ZStack {
            // 点面板外任意处收起
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                // 顶部：章节名 + 关闭
                HStack {
                    Text(chapterTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider()

                ScrollView {
                    VStack(spacing: 18) {
                        // 字号
                        stepperRow(
                            title: "字号",
                            value: "\(Int(prefs.fontSize))",
                            canMinus: prefs.fontSize > 14,
                            canPlus: prefs.fontSize < 30,
                            minus: { prefs.fontSize = max(14, prefs.fontSize - 1) },
                            plus: { prefs.fontSize = min(30, prefs.fontSize + 1) }
                        )

                        // 行距
                        stepperRow(
                            title: "行距",
                            value: "\(Int(prefs.lineSpacing))",
                            canMinus: prefs.lineSpacing > 4,
                            canPlus: prefs.lineSpacing < 24,
                            minus: { prefs.lineSpacing = max(4, prefs.lineSpacing - 1) },
                            plus: { prefs.lineSpacing = min(24, prefs.lineSpacing + 1) }
                        )

                        Divider()

                        // 翻页方式（小说用；另两类固定滚动，仍显示但不影响它们）
                        VStack(alignment: .leading, spacing: 8) {
                            Text("翻页方式").font(.subheadline.weight(.semibold))
                            Picker("翻页", selection: binding(for: \.pageTurn)) {
                                ForEach(PageTurnMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // 外观
                        VStack(alignment: .leading, spacing: 8) {
                            Text("外观").font(.subheadline.weight(.semibold))
                            Picker("外观", selection: binding(for: \.appearance)) {
                                ForEach(AppearanceMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // 文本编码（仅正文章）
                        if showsEncoding {
                            VStack(alignment: .leading, spacing: 4) {
                                encodingMenu
                                Text("乱码时手动切换编码，按书记忆。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        // 目录入口
                        Button(action: onTOC) {
                            HStack {
                                Label("目录", systemImage: "list.bullet")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.body)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)

                        // 全部设置
                        Button(action: onSettings) {
                            HStack {
                                Label("全部设置", systemImage: "gearshape")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.body)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)

                        // 退出阅读
                        Button(action: onExit) {
                            HStack {
                                Label("退出阅读", systemImage: "books.vertical")
                                Spacer()
                            }
                            .font(.body)
                            .foregroundStyle(.red)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            }
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func stepperRow(title: String,
                            value: String,
                            canMinus: Bool,
                            canPlus: Bool,
                            minus: @escaping () -> Void,
                            plus: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Button(action: minus) {
                Image(systemName: "minus.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(!canMinus)
            Text(value)
                .font(.body.monospacedDigit())
                .frame(minWidth: 28)
            Button(action: plus) {
                Image(systemName: "plus.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(!canPlus)
        }
    }
}

// MARK: - 目录弹层（本书全部章节，当前章高亮，点击跳转）

struct ReaderTOCView: View {
    let chapters: [Chapter]
    let currentId: String
    let onSelect: (Chapter) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if chapters.isEmpty {
                    ContentUnavailableView(
                        "这一本还没有目录",
                        systemImage: "list.bullet",
                        description: Text("单文件小说首次打开会在后台自动切章，稍等片刻再打开目录。")
                    )
                } else {
                    List(chapters) { chapter in
                        Button {
                            onSelect(chapter)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Text(chapter.displayTitle)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Spacer(minLength: 8)
                                if chapter.id == currentId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
