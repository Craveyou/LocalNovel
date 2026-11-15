import SwiftUI

// MARK: - 设置（书架首页 / 阅读器均可进入，所有偏好集中在这里）

struct SettingsView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var showGuide = false

    /// 用显式 Binding 包装，避免依赖环境对象的 $ 投影（不同 SwiftUI 版本行为有差异）
    private func binding<T>(for keyPath: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { prefs[keyPath: keyPath] },
            set: { prefs[keyPath: keyPath] = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("阅读方式") {
                    Picker("翻页", selection: binding(for: \.pageTurn)) {
                        ForEach(PageTurnMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(prefs.pageTurn == .page
                         ? "左右翻页：仿真翻页动画，点屏幕左 / 右侧翻页，底部显示页码。含插图的章节里，插图与音视频各占一页。"
                         : "上下滚动：传统连续滚动，段落流畅衔接。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("排版") {
                    HStack {
                        Text("字号")
                        Slider(value: binding(for: \.fontSize), in: 14...30, step: 1)
                        Text("\(Int(prefs.fontSize))")
                            .monospacedDigit()
                            .frame(width: 28)
                    }
                    HStack {
                        Text("行距")
                        Slider(value: binding(for: \.lineSpacing), in: 4...24, step: 1)
                        Text("\(Int(prefs.lineSpacing))")
                            .monospacedDigit()
                            .frame(width: 28)
                    }
                }

                Section("外观") {
                    Picker("外观", selection: binding(for: \.appearance)) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    Text("默认「跟随系统」，会随设备的浅色 / 深色外观自动切换；也可手动固定为浅色或深色。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("播放") {
                    Picker("长按倍速", selection: binding(for: \.longPressRate)) {
                        Text("1.5×").tag(1.5)
                        Text("2×").tag(2.0)
                        Text("3×").tag(3.0)
                    }
                    Text("按住视频画面临时倍速播放，松手还原；全屏播放、音频面板同样有效。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("章节目录") {
                    Toggle("去掉章节名的序号前缀", isOn: binding(for: \.cleanTitles))
                    Text("章节默认按文件夹原名展示与排序；开启后需在下方重新扫描才会生效。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("按当前设置重新扫描") {
                        library.reload()
                        dismiss()
                    }
                }

                Section("书库") {
                    Button("导入书籍（复制到「本地小说」）") {
                        library.importTargetSection = nil
                        library.importTargetSeries = nil
                        library.noteImportStarted(ImportMode.file.label)
                        library.activeImport = .file
                        dismiss()
                    }
                    if library.hiddenChapterCount > 0 {
                        Button("恢复已隐藏的 \(library.hiddenChapterCount) 个章节") {
                            library.restoreHiddenChapters()
                        }
                        Text("外部只读目录里删不掉的章节会被隐藏，点这里可让它们重新出现在书库。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("结构说明") {
                    Button {
                        showGuide = true
                    } label: {
                        Label("漫画 / 小说 / 整理 的目录结构", systemImage: "questionmark.folder")
                    }
                    Text("说明每层文件夹会被识别成什么：漫画名、卷、话，以及哪些文件会被忽略。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("所有内容仅在本机读取，不联网、不上传、不修改原始文件。阅读进度与偏好保存在本机。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showGuide) { StructureGuideView() }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
