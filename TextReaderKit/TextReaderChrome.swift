import SwiftUI
import UIKit

// MARK: - 页眉 / 页脚（对齐截图 5215：章节标题·章节序号 / 电量时间·页码）

struct ReaderHeader: View {
    @EnvironmentObject private var session: TextReaderSession
    let theme: TextTheme

    var body: some View {
        HStack(spacing: 12) {
            if session.settings.showChapterTitle {
                Text(session.currentChapter?.title ?? "")
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if session.settings.showChapterIndex {
                Text("第\(session.chapterIndex + 1)/\(max(session.chapters.count, 1))章")
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前章：\(session.currentChapter?.title ?? "")，第 \(session.chapterIndex + 1) 章，共 \(session.chapters.count) 章")
    }
}

struct ReaderFooter: View {
    @EnvironmentObject private var session: TextReaderSession
    let theme: TextTheme

    var body: some View {
        HStack(spacing: 12) {
            if session.settings.showBatteryTime {
                BatteryTimeView(theme: theme)
            }
            Spacer(minLength: 8)
            if session.settings.showPageNumber {
                Text("第\(session.pageIndex + 1)/\(max(session.pages.count, 1))页")
                    .font(.footnote)
                    .foregroundStyle(theme.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(session.pageIndex + 1) 页，共 \(max(session.pages.count, 1)) 页")
    }
}

/// 电量 + 时间：30 秒随 TimelineView 刷新一次。
struct BatteryTimeView: View {
    let theme: TextTheme
    @State private var batteryLevel: Float = -1
    @State private var charging = false

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private var batterySymbol: String {
        let level = Int((batteryLevel >= 0 ? batteryLevel : 1) * 100)
        if charging { return "battery.100.bolt" }
        switch level {
        case ..<25: return "battery.25percent"
        case ..<50: return "battery.50percent"
        case ..<75: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 4) {
                Image(systemName: batterySymbol)
                    .font(.footnote)
                Text(timeText)
                    .font(.footnote)
                    .monospacedDigit()
            }
            .foregroundStyle(theme.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("时间 \(timeText)，电量 \(batteryLevel >= 0 ? Int(batteryLevel * 100) : 0)%")
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            batteryLevel = UIDevice.current.batteryLevel
            charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        }
    }
}

// MARK: - 阅读菜单浮层（对齐截图 5216）

struct ReaderMenuOverlay: View {
    @EnvironmentObject private var session: TextReaderSession
    @Binding var isPresented: Bool
    let theme: TextTheme

    @Binding var showSettingsPanel: Bool
    @Binding var showThemePanel: Bool
    let onCatalog: () -> Void
    let onSearch: () -> Void
    let onBack: () -> Void
    let onMoreSettings: () -> Void
    let onTapZoneEditor: () -> Void

    @State private var chapterDraft: Double = 0

    private var isBookmarked: Bool {
        guard let book = session.book else { return false }
        return store.bookmark(in: book.id,
                              chapterIndex: session.chapterIndex,
                              paragraph: session.currentParagraph) != nil
    }

    private var store: TextReaderStore { session.store }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack {
                Spacer()
                floatingButtons
                    .padding(.top, 12)
                    .padding(.trailing, 14)
            }
            Spacer()
            if showSettingsPanel {
                ReaderSettingsPanel(theme: theme,
                                    onTapZoneEditor: onTapZoneEditor,
                                    onMoreSettings: onMoreSettings)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if showThemePanel {
                ReaderThemePanel(theme: theme)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            sliderRow
            toolRow
        }
        .background(theme.menuBackground.ignoresSafeArea())
        .onAppear { chapterDraft = Double(session.chapterIndex) }
        .onChange(of: session.chapterIndex) { _, newValue in
            chapterDraft = Double(newValue)
        }
        .animation(.easeOut(duration: 0.2), value: showSettingsPanel)
        .animation(.easeOut(duration: 0.2), value: showThemePanel)
    }

    // MARK: 顶栏：返回 / 书名 / 净化

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                isPresented = false
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("返回书架")
            Spacer(minLength: 4)
            Text(session.book?.title ?? "阅读")
                .font(.headline)
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Button {
                session.setPurified(!session.settings.purified)
            } label: {
                Text("净化")
                    .font(.subheadline.weight(session.settings.purified ? .semibold : .regular))
                    .foregroundStyle(session.settings.purified ? theme.accent : theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(session.settings.purified ? "关闭净化" : "开启净化，过滤广告行")
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    // MARK: 右侧悬浮按钮：书签 / 搜索 / 目录

    private var floatingButtons: some View {
        VStack(spacing: 16) {
            menuCircle(systemName: isBookmarked ? "bookmark.fill" : "bookmark",
                       tint: isBookmarked ? theme.accent : theme.text) {
                session.toggleBookmark()
            }
            .accessibilityLabel(isBookmarked ? "取消书签" : "加书签")
            menuCircle(systemName: "magnifyingglass", tint: theme.text, action: {
                isPresented = false
                onSearch()
            })
            .accessibilityLabel("搜索全书")
            menuCircle(systemName: "list.bullet.rectangle", tint: theme.text, action: {
                isPresented = false
                onCatalog()
            })
            .accessibilityLabel("打开目录")
        }
    }

    private func menuCircle(systemName: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(theme.isDark ? Color(white: 0.18) : Color(white: 0.92)))
        }
        .buttonStyle(.plain)
    }

    // MARK: 章节滑杆：上一章 ←—●—→ 下一章

    private var sliderRow: some View {
        HStack(spacing: 12) {
            Button("上一章") {
                if session.chapterIndex > 0 { session.goChapter(session.chapterIndex - 1, paragraph: 0) }
            }
            .font(.subheadline)
            .foregroundStyle(theme.text)
            .disabled(session.chapterIndex == 0)
            Slider(value: $chapterDraft, in: 0...Double(max(session.chapters.count - 1, 0))) { editing in
                if !editing {
                    session.goChapter(Int(chapterDraft),
                                      paragraph: Int(chapterDraft) == session.chapterIndex ? nil : 0)
                }
            }
            .tint(theme.accent)
            .accessibilityLabel("章节滑杆")
            Button("下一章") {
                if session.chapterIndex + 1 < session.chapters.count {
                    session.goChapter(session.chapterIndex + 1, paragraph: 0)
                }
            }
            .font(.subheadline)
            .foregroundStyle(theme.text)
            .disabled(session.chapterIndex + 1 >= session.chapters.count)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 底部工具栏：目录 / 夜晚 / 主题 / 设置 / 搜索

    private var toolRow: some View {
        HStack(spacing: 0) {
            toolItem(systemName: "list.bullet", label: "目录") {
                isPresented = false
                onCatalog()
            }
            toolItem(systemName: theme.isDark ? "sun.max" : "moon",
                     label: theme.isDark ? "白天" : "夜晚") {
                session.settings.theme = theme.isDark ? .white : .dark
            }
            toolItem(systemName: "paintpalette", label: "主题") {
                showSettingsPanel = false
                showThemePanel.toggle()
            }
            toolItem(systemName: "gearshape", label: "设置") {
                showThemePanel = false
                showSettingsPanel.toggle()
            }
            toolItem(systemName: "magnifyingglass", label: "搜索") {
                isPresented = false
                onSearch()
            }
        }
        .padding(.vertical, 8)
    }

    private func toolItem(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.title3)
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - 设置面板（对齐截图 5217：亮度 / 字体 / 翻页 / 其他）

struct ReaderSettingsPanel: View {
    @EnvironmentObject private var session: TextReaderSession
    let theme: TextTheme
    let onTapZoneEditor: () -> Void
    let onMoreSettings: () -> Void

    private var accent: Color { theme.accent }
    private var chipIdle: Color { theme.isDark ? Color(white: 0.16) : Color(white: 0.88) }

    var body: some View {
        VStack(spacing: 14) {
            brightnessRow
            fontRow
            transitionRow
            miscRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var brightnessRow: some View {
        HStack(spacing: 12) {
            panelLabel("亮度")
            Slider(value: Binding(get: { UIScreen.main.brightness },
                                  set: { UIScreen.main.brightness = $0 }),
                   in: 0.05...1)
                .tint(accent)
                .accessibilityLabel("亮度")
            chip("常亮", active: session.settings.keepAwake) {
                session.settings.keepAwake.toggle()
                UIApplication.shared.isIdleTimerDisabled = session.settings.keepAwake
            }
        }
    }

    private var fontRow: some View {
        HStack(spacing: 12) {
            panelLabel("字体")
            chip("A-") {
                session.settings.fontSize = max(14, session.settings.fontSize - 1)
            }
            Text("\(Int(session.settings.fontSize))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.text)
                .frame(minWidth: 28)
            chip("A+") {
                session.settings.fontSize = min(34, session.settings.fontSize + 1)
            }
            chip(session.settings.fontDesign.label) {
                session.settings.fontDesign = nextFontDesign(from: session.settings.fontDesign)
            }
        }
    }

    private var transitionRow: some View {
        HStack(spacing: 12) {
            panelLabel("翻页")
            ForEach(TextPageTransition.allCases) { transition in
                chip(transition.label,
                     active: session.settings.transition == transition) {
                    session.settings.transition = transition
                }
            }
        }
    }

    private var miscRow: some View {
        HStack(spacing: 12) {
            panelLabel("其他")
            chip("点击") { onTapZoneEditor() }
            chip(session.settings.indentParagraphs ? "缩进" : "齐头") {
                session.settings.indentParagraphs.toggle()
            }
            chip("滚动", active: session.mode == .scroll) {
                session.mode = session.mode == .paged ? .scroll : .paged
            }
            chip("更多") { onMoreSettings() }
        }
    }

    private func panelLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(theme.secondary)
            .frame(width: 36, alignment: .leading)
    }

    private func chip(_ text: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(active ? accent : theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(chipIdle))
                .overlay(Capsule().stroke(active ? accent : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
    }

    private func nextFontDesign(from current: TextFontDesign) -> TextFontDesign {
        let all = TextFontDesign.allCases
        guard let index = all.firstIndex(of: current) else { return current }
        return all[(index + 1) % all.count]
    }
}

// MARK: - 主题面板

struct ReaderThemePanel: View {
    @EnvironmentObject private var session: TextReaderSession
    let theme: TextTheme

    var body: some View {
        HStack(spacing: 20) {
            ForEach(TextTheme.allCases) { candidate in
                Button {
                    session.settings.theme = candidate
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(candidate.background)
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(
                                session.settings.theme == candidate ? theme.accent : Color.clear,
                                lineWidth: 2))
                            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        Text(candidate.label)
                            .font(.caption)
                            .foregroundStyle(session.settings.theme == candidate ? theme.accent : theme.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("主题：\(candidate.label)")
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - 更多设置（对齐截图 5218）

struct MoreSettingsSheet: View {
    @EnvironmentObject private var session: TextReaderSession
    @Environment(\.dismiss) private var dismiss
    let theme: TextTheme

    var body: some View {
        NavigationStack {
            Form {
                Section("页眉页脚") {
                    toggleRow("章节标题", hint: "左上（显示）",
                              value: session.settings.showChapterTitle) {
                        session.settings.showChapterTitle.toggle()
                    }
                    toggleRow("章节序号", hint: "右上（显示）",
                              value: session.settings.showChapterIndex) {
                        session.settings.showChapterIndex.toggle()
                    }
                    toggleRow("电量时间", hint: "左下（显示）",
                              value: session.settings.showBatteryTime) {
                        session.settings.showBatteryTime.toggle()
                    }
                    toggleRow("页码", hint: "右下（显示）",
                              value: session.settings.showPageNumber) {
                        session.settings.showPageNumber.toggle()
                    }
                }
                Section("阅读方式") {
                    Picker("翻页方式", selection: $session.mode) {
                        ForEach(TextReaderMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    toggleRow("首行缩进", hint: "段落缩进两字符",
                              value: session.settings.indentParagraphs) {
                        session.settings.indentParagraphs.toggle()
                    }
                }
                Section("亮度") {
                    toggleRow("常亮", hint: "阅读时屏幕不息屏",
                              value: session.settings.keepAwake) {
                        session.settings.keepAwake.toggle()
                        UIApplication.shared.isIdleTimerDisabled = session.settings.keepAwake
                    }
                }
            }
            .scrollContentBackground(theme.isDark ? .hidden : .visible)
            .background(theme.chrome.ignoresSafeArea())
            .navigationTitle("更多设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.secondary)
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .preferredColorScheme(theme.isDark ? .dark : .light)
        }
    }

    private func toggleRow(_ title: String, hint: String, value: Bool, action: @escaping () -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: { _ in action() })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(.green)
    }
}

// MARK: - 点击区域编辑器（对齐截图 5219）

struct TapZoneEditorOverlay: View {
    @EnvironmentObject private var session: TextReaderSession
    @Binding var isPresented: Bool
    let theme: TextTheme

    var body: some View {
        VStack(spacing: 16) {
            Text("点击格子改动作：上一页 → 下一页 → 菜单 循环切换")
                .font(.footnote)
                .foregroundStyle(theme.secondary)
                .padding(.top, 16)
            GeometryReader { geo in
                let columns = 3
                let rows = 3
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<columns, id: \.self) { col in
                                let cell = row * columns + col
                                let action = session.settings.action(forCell: cell)
                                Button {
                                    cycle(cell: cell, current: action)
                                } label: {
                                    Text(action.label)
                                        .font(.subheadline)
                                        .foregroundStyle(theme.text)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("区域 \(row + 1) 行 \(col + 1) 列：\(action.label)")
                                if col < columns - 1 {
                                    Rectangle().fill(Color.gray.opacity(0.35)).frame(width: 1)
                                }
                            }
                        }
                        if row < rows - 1 {
                            Rectangle().fill(Color.gray.opacity(0.35)).frame(height: 1)
                        }
                    }
                }
                .background(Color.gray.opacity(0.08))
            }
            .frame(maxHeight: .infinity)
            Button {
                isPresented = false
            } label: {
                Text("关闭")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(theme.accent))
            }
            .accessibilityLabel("关闭点击区域编辑")
            Button("恢复默认") {
                session.settings.tapZones = TextReaderSettings.standardTapZones()
            }
            .font(.footnote)
            .foregroundStyle(theme.secondary)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .background(theme.menuBackground.ignoresSafeArea())
    }

    private func cycle(cell: Int, current: TextTapAction) {
        let all = TextTapAction.allCases
        guard let index = all.firstIndex(where: { current == $0 }) else { return }
        session.settings.tapZones[cell] = all[(index + 1) % all.count]
    }
}

// MARK: - 全书搜索面板

struct ReaderSearchSheet: View {
    @EnvironmentObject private var session: TextReaderSession
    @Environment(\.dismiss) private var dismiss
    let theme: TextTheme
    let onJump: () -> Void

    @State private var query = ""

    private var hits: [TextSearchHit] {
        TextSearchEngine.search(query: query, chapters: session.chapters)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("至少输入 2 个字，搜全书正文", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                }
                if query.count >= 2 {
                    Section("命中 \(hits.count) 处") {
                        ForEach(hits.prefix(80)) { hit in
                            Button {
                                session.goChapter(hit.chapterIndex, paragraph: hit.paragraph)
                                dismiss()
                                onJump()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(hit.chapterTitle)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(hit.snippet)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        if hits.count > 80 {
                            Text("命中过多，只显示前 80 条")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .preferredColorScheme(theme.isDark ? .dark : .light)
        }
    }
}
