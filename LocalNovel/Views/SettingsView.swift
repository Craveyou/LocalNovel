import SwiftUI

// MARK: - 阅读设置

struct SettingsView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

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
                    Toggle("夜间模式", isOn: binding(for: \.isDarkMode))
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

                Section {
                    Text("所有内容仅在本机读取，不联网、不上传、不修改原始文件。阅读进度与偏好保存在本机。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
