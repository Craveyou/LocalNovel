import SwiftUI

/// NAS 连接下的三类入口（漫画 / 整理 / 短剧），显示与本地 tab 完全一致。
/// 数据源走 LNNASSource → FeiniuNASService（双地址 + TCP 预检逻辑不动）。
struct LNNASCategoryView: View {
    let connection: FeiniuConnection

    var body: some View {
        LNCategoryView(source: LNNASSource(connection: connection, rootPath: "/"),
                       title: connection.name,
                       subtitle: "漫画 · 整理 · 短剧 — 飞牛上的三个分类目录",
                       showsCounts: false)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        FeiniuBrowserView(connection: connection)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel("浏览全部文件")
                }
            }
    }
}
