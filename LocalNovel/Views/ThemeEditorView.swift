import SwiftUI
import PhotosUI

// MARK: - 自定义主题管理 / 编辑（F2 / F3 / F4 / F5）
//
// 列表：内置主题（只读，可「以此为底稿新建」）+ 自定义主题（可编辑 / 删除 / 设为夜间）。
// 编辑：名字、6 个颜色、背景图（相册选图，存进沙盒）、是否夜间主题，顶部有实时预览。
//
// 只作用于「小说」分区的阅读页；书库、设置等界面仍走系统的浅色 / 深色外观。

struct ThemeManagerView: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(prefs.customThemes) { theme in
                        NavigationLink {
                            ThemeEditorView(theme: theme)
                        } label: {
                            row(theme)
                        }
                    }
                    .onDelete { indexSet in
                        let ids = indexSet.map { prefs.customThemes[$0].id }
                        prefs.customThemes.removeAll { ids.contains($0.id) }
                        if ids.contains(prefs.themeId) {
                            prefs.themeId = ReaderTheme.builtIns[0].id
                        }
                    }
                } header: {
                    Text("自定义主题")
                } footer: {
                    Text("左滑删除。删除后正在用它的书会自动回到「纸白」。")
                }

                Section("内置主题（只读，可复制一份来改）") {
                    ForEach(ReaderTheme.builtIns) { theme in
                        HStack {
                            row(theme)
                            Spacer()
                            Button("复制") {
                                duplicate(theme)
                            }
                            .font(.footnote)
                        }
                    }
                }

                Section {
                    Button {
                        duplicate(prefs.theme)
                    } label: {
                        Label("以当前主题为底稿新建", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("主题管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func row(_ theme: ReaderTheme) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.uiBackground)
                .frame(width: 34, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(theme.uiText.opacity(0.3), lineWidth: 1)
                }
                .overlay {
                    Text("文").font(.system(size: 13)).foregroundStyle(theme.uiText)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name).font(.system(size: 15))
                HStack(spacing: 6) {
                    if theme.isNight {
                        Text("夜间").font(.system(size: 10))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                    if theme.backgroundImage != nil {
                        Text("背景图").font(.system(size: 10))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                    if theme.id == prefs.themeId {
                        Text("使用中").font(.system(size: 10)).foregroundStyle(.tint)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func duplicate(_ base: ReaderTheme) {
        let name = base.name + " 副本"
        let theme = ReaderTheme.newCustom(from: base, name: name)
        prefs.customThemes.append(theme)
    }
}

// MARK: - 单个主题编辑

struct ThemeEditorView: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss

    let theme: ReaderTheme

    @State private var draft: ReaderTheme
    @State private var pickerItem: PhotosPickerItem?

    init(theme: ReaderTheme) {
        self.theme = theme
        _draft = State(initialValue: theme)
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ReaderTheme, String>) -> Binding<Color> {
        Binding(get: { Color(hex: draft[keyPath: keyPath]) },
                set: { draft[keyPath: keyPath] = $0.hexRGB })
    }

    var body: some View {
        Form {
            Section("预览") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("第一章 夜行")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(draft.uiTitle)
                    Text("风从窗缝里挤进来，把纸页掀得哗啦作响。")
                        .font(.system(size: 15))
                        .foregroundStyle(draft.uiText)
                    HStack {
                        Text("1 / 12")
                        Spacer()
                        Text("第 1 章")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(draft.uiHeaderFooter)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(draft.uiBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(draft.uiSeparator, lineWidth: 1)
                }
            }

            Section("名称") {
                TextField("主题名字", text: $draft.name)
                Toggle("作为夜间主题", isOn: $draft.isNight)
            }

            Section("颜色") {
                ColorPicker("正文", selection: colorBinding(\.textColor), supportsOpacity: false)
                ColorPicker("背景", selection: colorBinding(\.backgroundColor), supportsOpacity: false)
                ColorPicker("章节标题", selection: colorBinding(\.titleColor), supportsOpacity: false)
                ColorPicker("页码", selection: colorBinding(\.pageIndexColor), supportsOpacity: false)
                ColorPicker("页眉页脚", selection: colorBinding(\.headerFooterColor), supportsOpacity: false)
                ColorPicker("分隔线", selection: colorBinding(\.separatorColor), supportsOpacity: false)
            }

            Section("背景图") {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(draft.backgroundImage == nil ? "从相册选择背景图" : "更换背景图",
                          systemImage: "photo")
                }
                if draft.backgroundImage != nil {
                    Picker("铺法", selection: $draft.backgroundImageMode) {
                        Text("填充裁切").tag(0)
                        Text("完整显示").tag(1)
                        Text("拉伸铺满").tag(2)
                    }
                    Button("移除背景图", role: .destructive) {
                        draft.backgroundImage = nil
                    }
                }
            }

            Section {
                Button("保存并应用") { save(apply: true) }
                Button("仅保存") { save(apply: false) }
            }
        }
        .navigationTitle("编辑主题")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let name = ReaderBackgroundImage.save(imageData: data, ext: "jpg") {
                    await MainActor.run { draft.backgroundImage = name }
                }
            }
        }
    }

    private func save(apply: Bool) {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.name = trimmed.isEmpty ? "未命名主题" : trimmed
        if let index = prefs.customThemes.firstIndex(where: { $0.id == draft.id }) {
            prefs.customThemes[index] = draft
        } else {
            prefs.customThemes.append(draft)
        }
        if apply { prefs.themeId = draft.id }
        dismiss()
    }
}
