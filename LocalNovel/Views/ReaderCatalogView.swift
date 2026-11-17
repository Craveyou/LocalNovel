import SwiftUI

// MARK: - 目录面板（从下方浮出，版式对齐千阅）
//
// 结构：
//   拖拽手柄
//   标题 + 章节数 ......... 正序/倒序 · 关闭
//   搜索框（输入即过滤）
//   章节列表（当前章高亮 + 圆点，打开时自动定位到当前章）
//   底部「定位到当前章」
//
// 只给「小说」用；漫画 / 整理 / 短剧仍走它们原来的章节列表。

struct ReaderCatalogView: View {
    let chapters: [Chapter]
    let currentId: String
    let theme: ReaderTheme
    let onSelect: (Chapter) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var descending = false
    @FocusState private var searchFocused: Bool

    private var sorted: [Chapter] {
        descending ? Array(chapters.reversed()) : chapters
    }

    private var filtered: [Chapter] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return sorted }
        return sorted.filter { $0.displayTitle.localizedCaseInsensitiveContains(keyword) }
    }

    private func indexLabel(_ chapter: Chapter) -> String {
        guard let index = chapters.firstIndex(where: { $0.id == chapter.id }) else { return "" }
        return "\(index + 1)"
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.22))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                VStack(spacing: 0) {
                    handle
                    header
                    searchBar
                    Divider().overlay(theme.uiSeparator)
                    list
                    footer
                }
                .frame(height: geo.size.height * 0.72)
                .background(theme.uiBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, y: -2)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: 局部

    private var handle: some View {
        Capsule()
            .fill(theme.uiSeparator)
            .frame(width: 36, height: 4)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("目录")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.uiText)
            Text("共 \(chapters.count) 章")
                .font(.system(size: 12))
                .foregroundStyle(theme.uiHeaderFooter)

            Spacer(minLength: 8)

            Button {
                descending.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: descending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                    Text(descending ? "倒序" : "正序")
                        .font(.system(size: 12))
                }
                .foregroundStyle(theme.uiText)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(theme.uiSeparator.opacity(0.35),
                            in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.uiHeaderFooter)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(theme.uiHeaderFooter)
            TextField("搜索章节", text: $query)
                .font(.system(size: 14))
                .foregroundStyle(theme.uiText)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.uiHeaderFooter)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(theme.uiSeparator.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { _, chapter in
                        row(chapter)
                            .id(chapter.id)
                    }
                    if filtered.isEmpty {
                        Text("没有匹配的章节")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.uiHeaderFooter)
                            .padding(.top, 40)
                    }
                }
                .padding(.bottom, 8)
            }
            .onAppear {
                // 打开即定位到当前章（列表可能上千条，滚到当前章才有意义）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    proxy.scrollTo(currentId, anchor: .center)
                }
            }
        }
    }

    private func row(_ chapter: Chapter) -> some View {
        let isCurrent = chapter.id == currentId
        return Button {
            onSelect(chapter)
        } label: {
            HStack(spacing: 8) {
                Text(indexLabel(chapter))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(isCurrent ? Color.accentColor : theme.uiHeaderFooter)
                    .frame(width: 34, alignment: .trailing)
                Text(chapter.displayTitle)
                    .font(.system(size: 14, weight: isCurrent ? .medium : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : theme.uiText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                if isCurrent {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(theme.uiSeparator)
            Button {
                onSelect(chapters.first { $0.id == currentId } ?? chapters.first ?? chapters[0])
            } label: {
                Text("定位到当前章")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.uiText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(chapters.isEmpty)
        }
    }
}
