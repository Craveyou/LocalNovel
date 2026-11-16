import SwiftUI

// MARK: - 设置（书架首页 / 阅读器均可进入，所有偏好集中在这里）

struct SettingsView: View {
    /// 作为底部 Tab 时不需要「完成」按钮；从阅读器弹出时保留
    var showsDoneButton: Bool = true

    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var showGuide = false
    /// NAS 图片缓存占用（进入设置时扫一次，改上限 / 清理后刷新）
    @State private var cacheUsage = RemoteImageCache.Usage()
    @State private var showCacheConfirm = false

    init(showsDoneButton: Bool = true) {
        self.showsDoneButton = showsDoneButton
    }

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
                Section("阅读方式（仅小说）") {
                    Picker("翻页", selection: binding(for: \.pageTurn)) {
                        ForEach(PageTurnMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(prefs.pageTurn.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("这一项只影响「小说」分区。「整理」是图文混排、「漫画」是满宽连排，两者始终上下滚动。")
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

                Section("NAS 图片缓存") {
                    Picker("上限", selection: binding(for: \.networkImageCacheMB)) {
                        ForEach(Preferences.imageCacheOptions, id: \.self) { mb in
                            Text(mb == 0 ? "不限制" : "\(mb) MB").tag(mb)
                        }
                    }
                    LabeledContent("已占用") {
                        Text(cacheUsageText)
                            .monospacedDigit()
                    }
                    Button(role: .destructive) {
                        showCacheConfirm = true
                    } label: {
                        Label("清理图片缓存", systemImage: "trash")
                    }
                    .disabled(cacheUsage.isEmpty)
                    Text("NAS 上的漫画、剧照与插图会先下载到本机再显示；超出上限时按「最久未修改」自动淘汰。"
                         + "清理只删本机缓存，NAS 原图不受影响，下次浏览会重新下载。")
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
                        Label("小说 / 漫画 / 整理 / 短剧 的目录结构", systemImage: "questionmark.folder")
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
            .task { await refreshCacheUsage() }
            .onChange(of: prefs.networkImageCacheMB) { _, _ in
                // 改小上限后立刻裁一次，占用数字同步刷新
                Task {
                    await RemoteImageCache.shared.enforceLimit()
                    await refreshCacheUsage()
                }
            }
            .confirmationDialog("清空 NAS 图片缓存？",
                                isPresented: $showCacheConfirm,
                                titleVisibility: .visible) {
                Button("清理 \(cacheUsageText)", role: .destructive) {
                    Task {
                        await RemoteImageCache.shared.clear()
                        await refreshCacheUsage()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只删除本机缓存文件，NAS 上的原图不受影响；下次浏览会重新下载。")
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
            }
        }
    }

    private var cacheUsageText: String {
        guard !cacheUsage.isEmpty else { return "0 KB" }
        let size = Self.sizeFormatter.string(fromByteCount: cacheUsage.bytes)
        return "\(size) · \(cacheUsage.files) 个文件"
    }

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    @MainActor
    private func refreshCacheUsage() async {
        cacheUsage = await RemoteImageCache.shared.usage()
    }
}
