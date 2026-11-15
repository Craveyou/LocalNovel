import SwiftUI

// MARK: - 目录结构说明（App 内可查，不用去猜「为什么这部漫画扫不出来」）
// 规则与 ComicScanner / NovelScanner / OrganizedScanner 一一对应，
// 改扫描逻辑时必须同步这里的表格，否则说明会骗人。

struct StructureGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    intro
                    comicSection
                    shortDramaSection
                    novelSection
                    organizedSection
                    ignoredSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("目录结构说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("书放在「文件」App → 我的 iPhone → 本地小说 里")
                .font(.headline)
            Text("四个文件夹就是四个分区，放哪个文件夹就归哪一类，App 不再按内容猜。"
                 + "下面的规则是实时的：你在文件 App 里改名、挪位置，回到 App 就按新结构重新识别。"
                 + "NAS 上的目录用同一套规则，只是分类少一个「小说」。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 漫画

    private var comicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            blockTitle("漫画", systemImage: "photo.on.rectangle.angled")

            Text("第一部：文件夹名就是漫画名，可以只有一层「话」，也可以中间夹「部 / 单行本」这类卷。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            tree("""
            漫画/
            ├─ 星海旅人/                 ← 文件夹名 = 漫画名（列表里的一本）
            │  ├─ 第1部/                 ← 中间层 = 卷名
            │  │  ├─ 第1话/              ← 放图片的文件夹 = 一话
            │  │  │    001.jpg 002.jpg …
            │  │  └─ 第2话/
            │  └─ 第3部/第1话/…
            ├─ 深海食堂/                 ← 没有「部」也支持
            │  ├─ 第01话/001.jpg
            │  └─ 第02话.pdf             ← 一个 pdf = 一话
            ├─ 夜行列车/                 ← 同一部书按格式分成两个包
            │  ├─ PDF包/                 ← 包里只放 pdf：整包一话一个文件
            │  │  ├─ 第01话.pdf
            │  │  └─ 第02话.pdf
            │  └─ 图片包/                ← 包里只放图片话
            │     ├─ 第01话/001.jpg
            │     └─ 第02话/001.jpg
            └─ 短篇合集/单行本/第3话/…    ← 更深的中间层并进卷名
            """)

            Text("第二部：也支持 pdf 单话、图片话和 pdf 话混在同一部里，列表统一按名称自然排序。"
                 + "同一部书按格式分成两个包时，章节列表会把「PDF包」「图片包」各列一段，"
                 + "包下面再列该包的章节，两种格式都保留、互相不覆盖。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ruleTable([
                ("漫画名文件夹", "一部漫画，书库列表里的一本"),
                ("中间文件夹", "卷名；多层用「 · 」连接，如「第1部 · 第2话」"),
                ("直接有图片的文件夹", "一话（只看该层自己的图片，不含子文件夹里的）"),
                ("目录下的每个 pdf", "一话；按页渲染，滑到哪页生成哪页"),
                ("格式包（PDF / 图片）", "包名原样作为分组，章节列表按包分段显示，两包各自列出"),
                ("漫画名层里的散图", "整部只有一话，标题用漫画名"),
                ("根目录直接放图片", "整个「漫画」分区当作一部（没有漫画名文件夹时）"),
                ("排序", "先按分组、再按话名自然排序：第2话 排在第10话 前面")
            ])

            Tip(text: "每话的图片按文件名排序：纯数字名（1.jpg / 002.png）按数值，其余按自然字符序。"
                 + "jpg / jpeg / png / webp / heic / heif / bmp / tiff / gif / apng 都支持。")
        }
    }

    // MARK: 短剧

    private var shortDramaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            blockTitle("短剧", systemImage: "play.rectangle.on.rectangle")

            Text("一部剧一个文件夹：剧照一个包、视频一个包；两个包都进了章节列表，"
                 + "剧照包点进去按漫画方式连排，视频包点进去是每集一行。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            tree("""
            短剧/
            ├─ 逆光而行/                 ← 文件夹名 = 剧名（列表里的一部）
            │  ├─ 剧照/                  ← 剧照包：图片
            │  │     001.jpg 002.jpg …
            │  └─ 视频/                  ← 视频包：每集一个文件
            │        第01集.mp4
            │        第02集.mp4
            ├─ 只有视频的一部/           ← 没有剧照也能识别
            │  └─ 全集.mp4
            └─ 散装短片.mp4              ← 根目录单个视频 = 一部单片
            """)

            ruleTable([
                ("剧名文件夹", "一部短剧，书库列表里的一部"),
                ("剧照包（放图片的文件夹）", "一个「剧照」条目；打开按漫画方式满宽连排，点图看大图"),
                ("视频包 / 剧名层的视频", "每个视频一集；目录上显示 大小 · 时长"),
                ("只有视频", "没有剧照也能识别，列表用视频首帧当封面"),
                ("根目录散装视频", "每个视频单独成一部（单片）"),
                ("播放", "与「整理」里的视频完全一致：内联播放、可全屏、长按倍速"),
                ("阅读方式", "始终上下滚动，不受翻页设置影响")
            ])
        }
    }

    // MARK: 小说

    private var novelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            blockTitle("小说", systemImage: "text.book.closed")

            tree("""
            小说/
            ├─ 风起长安.txt              ← 一个文件 = 一本
            ├─ 短篇.md
            ├─ 某书.epub
            ├─ 某书.pdf
            └─ 银河旧事/                 ← 文件夹 = 一个系列
               ├─ 第一部 启程.txt
               ├─ 第二部 归途.txt
               └─ 前传/前传.txt          ← 显示为「银河旧事 · 前传」
            """)

            ruleTable([
                ("支持格式", "txt / md / epub / pdf（mobi、azw3 不支持）"),
                ("分章", "打开时按「第X章 / Chapter N / 序章 / 番外」自动切；切不出来就整本一章"),
                ("系列", "小说目录下的子文件夹；再多一层是「系列 · 子系列」"),
                ("阅读方式", "只有小说用左右翻页；「设置 → 阅读方式」可改成上下滚动"),
                ("epub", "只取文字，不含样式与内嵌插图"),
                ("pdf", "抽取文字层；扫描版没有文字时会提示改放「漫画」按页看")
            ])
        }
    }

    // MARK: 整理

    private var organizedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            blockTitle("整理", systemImage: "folder")

            tree("""
            整理/
            └─ 作者名/                    ← 文件夹名 = 书名
               ├─ 第01章/
               │  ├─ 正文.txt
               │  ├─ 1.jpg 2.png 3.gif
               │  └─ 片尾.mp4
               └─ 第02章/
            """)

            ruleTable([
                ("章节文件夹", "每章一个文件夹，按名称自然排序"),
                ("正文", "每章一个 txt / md，按序号图片跟在正文后面"),
                ("音视频", "每章可带 mp4 / mov / mp3 / m4a，显示在正文与插图之后"),
                ("阅读方式", "始终上下滚动，图文混排；翻页设置不影响这里"),
                ("单章书", "目录里直接是正文 + 图片、没有子文件夹时，整体当作一章")
            ])
        }
    }

    private var ignoredSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            blockTitle("不会被识别的文件", systemImage: "eye.slash")
            Text("· 隐藏文件（以 . 开头）、Thumbs.db、desktop.ini\n"
                 + "· 根目录的「放书说明.txt」（App 自动生成，用于让「文件」App 显示本目录）\n"
                 + "· 不认识的扩展名，会在阅读页底部提示「已忽略 N 个未识别文件」")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 组件

    private func blockTitle(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
    }

    private func tree(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10))
    }

    private func ruleTable(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    Text(rows[index].0)
                        .font(.caption.weight(.semibold))
                        .frame(width: 104, alignment: .leading)
                    Text(rows[index].1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(index.isMultiple(of: 2)
                            ? Color.clear
                            : Color.secondary.opacity(0.06))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
        )
    }

    private struct Tip: View {
        let text: String
        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
