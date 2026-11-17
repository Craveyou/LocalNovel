import SwiftUI

// MARK: - 阅读控制菜单（点屏幕中间弹出，只作用于「小说」）
//
// 覆盖在阅读层之上，半透明背景点一下即收起。集中放「格式效果」与常用入口：
//   · 排版：字号 / 字体 / 字重 / 行距 / 段距 / 字距 / 左右边距 / 对齐 / 首行缩进 / 繁简
//   · 标题样式：字号比例或固定值、字重、斜体、上下间距、下划线、分两行
//   · 页眉页脚：内容与显示开关
//   · 主题：内置配色 + 阅读亮度 + 常亮
//   · 翻页方式 / 外观 / 文本编码 / 目录 / 全部设置 / 退出阅读
//
// 全部改动即时写进 Preferences，分页引擎靠 signature 变化重建排版，不需要点保存。
// 漫画 / 整理 / 短剧不走这个面板的逻辑（它们固定滚动、不吃这些设置）。

struct ReaderControlsPanel: View {
    @EnvironmentObject private var prefs: Preferences

    let chapterTitle: String
    let showsEncoding: Bool
    let encodingMenu: AnyView
    let onTOC: () -> Void
    let onSettings: () -> Void
    let onExit: () -> Void
    let onDismiss: () -> Void

    @State private var showTitleStyle = false

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
                header
                Divider()
                ScrollView {
                    VStack(spacing: 14) {
                        typographySection
                        Divider()
                        titleSection
                        Divider()
                        headerFooterSection
                        Divider()
                        themeSection
                        Divider()
                        behaviorSection
                        Divider()
                        entries
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            }
            .frame(maxWidth: 460)
            .frame(maxHeight: 620)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: 顶部

    private var header: some View {
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
    }

    // MARK: 排版

    private var typographySection: some View {
        VStack(spacing: 12) {
            sectionTitle("排版")

            sliderRow("字号", value: binding(for: \.fontSize), range: 14...34, step: 1,
                      format: { "\(Int($0))" })

            // 字体
            HStack {
                Text("字体").font(.subheadline)
                Spacer(minLength: 8)
                Menu {
                    ForEach(prefs.fontOptions) { option in
                        Button {
                            prefs.fontFamily = option.id
                        } label: {
                            if option.id == prefs.fontFamily {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentFontLabel).font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .foregroundStyle(.tint)
                }
            }

            // 字重
            HStack {
                Text("字重").font(.subheadline)
                Spacer(minLength: 8)
                Picker("字重", selection: binding(for: \.fontWeight)) {
                    ForEach(ReaderFontWeight.allCases) { weight in
                        Text(weight.label).tag(weight)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            sliderRow("行距", value: binding(for: \.lineSpacing), range: 4...24, step: 1,
                      format: { "\(Int($0))" })
            sliderRow("段距", value: binding(for: \.paragraphSpacing), range: 0...24, step: 1,
                      format: { "\(Int($0))" })
            sliderRow("字距", value: binding(for: \.wordSpacing), range: 0...6, step: 0.5,
                      format: { String(format: "%.1f", $0) })
            sliderRow("边距", value: binding(for: \.horizontalPadding), range: 12...40, step: 2,
                      format: { "\(Int($0))" })

            HStack(spacing: 12) {
                Text("对齐").font(.subheadline)
                Picker("对齐", selection: binding(for: \.textAlign)) {
                    ForEach(ReaderTextAlign.allCases) { align in
                        Text(align.label).tag(align)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                Spacer(minLength: 0)
            }

            HStack(spacing: 16) {
                Toggle("首行缩进", isOn: binding(for: \.firstLineIndent))
                    .font(.subheadline)
                Toggle("繁体", isOn: binding(for: \.isTraditional))
                    .font(.subheadline)
            }
        }
    }

    private var currentFontLabel: String {
        prefs.fontOptions.first { $0.id == prefs.fontFamily }?.label ?? "系统默认"
    }

    // MARK: 标题样式

    private var titleSection: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showTitleStyle.toggle() }
            } label: {
                HStack {
                    Text("章节标题样式").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: showTitleStyle ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showTitleStyle {
                VStack(spacing: 12) {
                    HStack {
                        Text("固定字号").font(.subheadline)
                        Spacer()
                        Toggle("", isOn: binding(for: \.titleFixedSize))
                            .labelsHidden()
                    }
                    if prefs.titleFixedSize {
                        sliderRow("标题字号", value: binding(for: \.titleFixedValue),
                                  range: 12...40, step: 1, format: { "\(Int($0))" })
                    } else {
                        sliderRow("字号比例", value: Binding(
                            get: { CGFloat(prefs.titleScale) },
                            set: { prefs.titleScale = Double($0) }
                        ), range: 0.8...2.4, step: 0.1, format: { String(format: "%.1f×", $0) })
                    }
                    HStack {
                        Text("字重").font(.subheadline)
                        Spacer()
                        Picker("标题字重", selection: binding(for: \.titleWeight)) {
                            ForEach(ReaderFontWeight.allCases) { weight in
                                Text(weight.label).tag(weight)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                    }
                    sliderRow("上间距", value: binding(for: \.titleTopPadding),
                              range: 0...60, step: 2, format: { "\(Int($0))" })
                    sliderRow("下间距", value: binding(for: \.titleBottomPadding),
                              range: 0...60, step: 2, format: { "\(Int($0))" })
                    HStack(spacing: 16) {
                        Toggle("斜体", isOn: binding(for: \.titleItalic)).font(.subheadline)
                        Toggle("下方细线", isOn: binding(for: \.titleShowBottomLine)).font(.subheadline)
                    }
                    HStack(spacing: 16) {
                        Toggle("分两行显示", isOn: binding(for: \.titleSplitTwoLines)).font(.subheadline)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: 页眉页脚

    private var headerFooterSection: some View {
        VStack(spacing: 10) {
            sectionTitle("页眉页脚")
            HStack {
                Text("页眉").font(.subheadline)
                Spacer()
                Picker("页眉", selection: binding(for: \.headerMode)) {
                    ForEach(ReaderHeaderMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            HStack {
                Text("页脚").font(.subheadline)
                Spacer()
                Picker("页脚", selection: binding(for: \.footerMode)) {
                    ForEach(ReaderFooterMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            if prefs.headerMode != .none {
                sliderRow("页眉间距", value: binding(for: \.headerTopPadding),
                          range: 0...40, step: 2, format: { "\(Int($0))" })
            }
            if prefs.footerMode != .none {
                sliderRow("页脚间距", value: binding(for: \.footerBottomPadding),
                          range: 0...40, step: 2, format: { "\(Int($0))" })
            }
        }
    }

    // MARK: 主题与亮度

    private var themeSection: some View {
        VStack(spacing: 12) {
            HStack {
                sectionTitle("主题")
                Spacer()
                Button("自定义") { onSettings() }
                    .font(.caption)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ReaderTheme.builtIns) { theme in
                        themeSwatch(theme)
                    }
                    ForEach(prefs.customThemes) { theme in
                        themeSwatch(theme)
                    }
                }
                .padding(.vertical, 2)
            }
            sliderRow("亮度", value: Binding(
                get: { CGFloat(prefs.readerBrightness) },
                set: { prefs.readerBrightness = Double($0) }
            ), range: 0.25...1.0, step: 0.05, format: { "\(Int($0 * 100))%" })

            Toggle("阅读时常亮（不自动锁屏）", isOn: binding(for: \.keepScreenOn))
                .font(.subheadline)
        }
    }

    private func themeSwatch(_ theme: ReaderTheme) -> some View {
        Button {
            prefs.themeId = theme.id
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(theme.uiBackground)
                    .frame(width: 42, height: 42)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(theme.uiText.opacity(0.35), lineWidth: 1)
                    }
                    .overlay {
                        if theme.id == prefs.themeId {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .overlay {
                        Text("文").font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.uiText)
                    }
                Text(theme.name)
                    .font(.caption2)
                    .foregroundStyle(theme.id == prefs.themeId ? Color.accentColor : .secondary)
            }
            .frame(width: 52)
        }
        .buttonStyle(.plain)
    }

    // MARK: 翻页 / 外观

    private var behaviorSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("翻页方式").font(.subheadline)
                Spacer()
                Picker("翻页", selection: binding(for: \.pageTurn)) {
                    ForEach(PageTurnMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
            Text(prefs.pageTurn.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if prefs.pageTurn == .cover {
                sliderRow("翻页动画", value: Binding(
                    get: { CGFloat(prefs.flipDuration) },
                    set: { prefs.flipDuration = Double($0) }
                ), range: 0.05...0.8, step: 0.05, format: { String(format: "%.2fs", $0) })
            }
            HStack {
                Text("外观").font(.subheadline)
                Spacer()
                Picker("外观", selection: binding(for: \.appearance)) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            if showsEncoding {
                HStack {
                    encodingMenu
                    Spacer()
                }
                Text("乱码时手动切换编码，按书记忆。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 入口

    private var entries: some View {
        VStack(spacing: 12) {
            entryButton("目录", systemImage: "list.bullet", action: onTOC)
            entryButton("全部设置", systemImage: "gearshape", action: onSettings)
            Button(action: onExit) {
                HStack {
                    Label("退出阅读", systemImage: "books.vertical")
                    Spacer()
                }
                .font(.body)
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    private func entryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .font(.body)
        }
        .buttonStyle(.plain)
    }

    // MARK: 小组件

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sliderRow(_ title: String,
                           value: Binding<CGFloat>,
                           range: ClosedRange<CGFloat>,
                           step: CGFloat,
                           format: (CGFloat) -> String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .frame(width: 52, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(format(value.wrappedValue))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
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
