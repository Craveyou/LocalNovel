import SwiftUI

// MARK: - 净化规则管理（顶部右侧「净化」打开）
//
// 每条规则 = 一个正则 + 替换文本；留空 = 把匹配到的内容删掉。
// 改完立刻生效（ReaderTextPipeline 的缓存按规则指纹失效），不用重进章节。

struct PurifyManagerView: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.dismiss) private var dismiss

    @State private var editing: PurifyRule?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("启用净化", isOn: Binding(
                        get: { prefs.purifyEnabled },
                        set: { prefs.purifyEnabled = $0 }))
                } footer: {
                    Text("净化只作用于「小说」的正文，插图、音视频、漫画不受影响。规则按顺序执行。")
                }

                Section {
                    ForEach(prefs.purifyRules) { rule in
                        Button {
                            editing = rule
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.pattern.isEmpty ? "（空规则）" : rule.pattern)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(rule.replacement.isEmpty
                                     ? "删除匹配内容"
                                     : "替换为：\(rule.replacement)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                prefs.purifyRules.removeAll { $0.id == rule.id }
                            }
                        }
                    }
                    Button {
                        editing = PurifyRule.newRule()
                    } label: {
                        Label("新增规则", systemImage: "plus.circle")
                    }
                } header: {
                    Text("规则（\(prefs.purifyRules.count) 条）")
                } footer: {
                    Text(#"举例：^\s*（本章完）\s*$ 删掉每行只有「（本章完）」的行；www\.[a-z0-9]+\.(com|net) 删掉站名。写错的正则会自动跳过，不会吃掉正文。"#)
                }
            }
            .navigationTitle("净化")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $editing) { rule in
                PurifyRuleEditor(rule: rule) { saved in
                    if let index = prefs.purifyRules.firstIndex(where: { $0.id == saved.id }) {
                        prefs.purifyRules[index] = saved
                    } else {
                        prefs.purifyRules.append(saved)
                    }
                }
            }
        }
    }
}

private struct PurifyRuleEditor: View {
    @Environment(\.dismiss) private var dismiss

    let rule: PurifyRule
    let onSave: (PurifyRule) -> Void

    @State private var draft: PurifyRule
    @State private var sample = "（本章完）\n正文第一段。\nwww.example.com"

    init(rule: PurifyRule, onSave: @escaping (PurifyRule) -> Void) {
        self.rule = rule
        self.onSave = onSave
        _draft = State(initialValue: rule)
    }

    private var preview: String {
        PurifyEngine.apply([draft], to: sample)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("匹配") {
                    TextField("正则表达式", text: $draft.pattern, axis: .vertical)
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(1...3)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Toggle("按正则匹配", isOn: $draft.isRegex)
                }
                Section("替换为（留空 = 删除）") {
                    TextField("替换文本", text: $draft.replacement)
                        .font(.system(size: 13, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("样例预览") {
                    TextField("样例文本", text: $sample, axis: .vertical)
                        .font(.system(size: 12))
                        .lineLimit(3...6)
                    Text(preview.isEmpty ? "（全部被删除）" : preview)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("启用这条规则", isOn: $draft.isEnabled)
                }
            }
            .navigationTitle("编辑规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.pattern.isEmpty)
                }
            }
        }
    }
}
