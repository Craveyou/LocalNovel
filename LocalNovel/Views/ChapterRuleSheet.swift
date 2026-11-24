import SwiftUI

// MARK: - 重新分章（目录面板底部入口）
//
// 一本书一条正则：只影响分章，不动源文件。写规则时用正文前 2000 行做样本预览，
// 先看到「能切出多少章 / 前几条标题」再落库，避免规则写错把目录切成几百条垃圾。
//
// 兜底在 ChapterSplitter：规则切不出多章时退回内置正则，最差整本一章，不会变空书。

struct ChapterRuleSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialRule: String
    /// 整本文件 URL（分章样本从这里取）
    let bookURL: URL?
    /// 这本书的正文编码：必须和阅读器一致，否则 GB18030 的书会解出乱码、规则静默失效
    let preferred: TextEncodingOption
    let onApply: (String?) -> Void

    @State private var rule: String
    @State private var sample: String?
    @State private var loadingSample = true
    @State private var preview: ChapterSplitter.Preview?
    @State private var computing = false

    init(initialRule: String,
         bookURL: URL?,
         preferred: TextEncodingOption = .auto,
         onApply: @escaping (String?) -> Void) {
        self.initialRule = initialRule
        self.bookURL = bookURL
        self.preferred = preferred
        self.onApply = onApply
        _rule = State(initialValue: initialRule)
    }

    /// 只有样本里真能切出两章以上才允许应用（否则等于什么都没改）
    private var canApply: Bool {
        guard let preview else { return false }
        return !preview.usesFallback && preview.count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("正则表达式，例如 ^第\\d+章", text: $rule, axis: .vertical)
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(2...4)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("分章规则")
                } footer: {
                    Text("按行匹配：一行里命中就算标题行。留空 = 用自动分章（第X章 / Chapter N / 序章 / 番外）。")
                }

                Section("常用写法（点一下填入，可再改）") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ChapterSplitter.presets) { preset in
                                Button {
                                    rule = preset.pattern
                                } label: {
                                    Text(preset.label)
                                        .font(.system(size: 12))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.quaternary.opacity(0.5), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("样本预览") {
                    if loadingSample {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在读取正文样本…").font(.footnote).foregroundStyle(.secondary)
                        }
                    } else if sample == nil {
                        Label("读不到这本书的正文，无法预览（可以先手动填规则再应用）",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else if rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("当前用自动分章。填一条规则即可预览能切出多少章。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if let preview {
                        Text(preview.usesFallback
                             ? "样本（前 \(preview.sampleLines) 行）：切不出多章"
                             : "样本（前 \(preview.sampleLines) 行）：能切出 \(preview.count) 章")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(preview.usesFallback ? Color.orange : Color.green)
                        if let message = preview.message {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        ForEach(preview.titles.indices, id: \.self) { index in
                            Text("\(index + 1). \(preview.titles[index])")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在预览…").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        onApply(rule)
                        dismiss()
                    } label: {
                        Text("应用并重新分章").frame(maxWidth: .infinity)
                    }
                    .disabled(!canApply || computing)

                    Button("恢复自动分章") {
                        onApply(nil)
                        dismiss()
                    }
                    .foregroundStyle(.red)
                } footer: {
                    Text("重切后章节列表与阅读进度会全部重建，每章从开头开始读；已有书签和笔记会标为「章节已失效」，可在目录面板里清理。")
                }
            }
            .navigationTitle("重新分章")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .task { await loadSample() }
        .onChange(of: rule) { _, _ in refreshPreview() }
    }

    @MainActor
    private func loadSample() async {
        guard let url = bookURL else {
            loadingSample = false
            return
        }
        let value = await Task.detached(priority: .userInitiated) {
            ChapterSplitter.sample(from: url, maxLines: 2000, preferred: preferred)
        }.value
        sample = value
        loadingSample = false
        refreshPreview()
    }

    @MainActor
    private func refreshPreview() {
        guard let sample, !sample.isEmpty else {
            preview = nil
            return
        }
        let pattern = rule
        guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            preview = nil
            return
        }
        computing = true
        Task.detached(priority: .userInitiated) {
            let result = ChapterSplitter.preview(sample, pattern: pattern)
            await MainActor.run {
                // 规则又改了：丢掉过期结果，避免预览和输入框对不上
                guard pattern == rule else { return }
                preview = result
                computing = false
            }
        }
    }
}
