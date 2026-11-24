# TextReaderKit 接入说明

## 现在有什么

本仓库新增了一个**独立、不触碰主 App 小说大类**的纯文本阅读器：

- `TextReaderKit/`：framework 源码，纯文本小说专用
- `TextReaderDemo/`：Demo App 源码 + 样例小说
- `TextReaderKitDemo.xcodeproj`：独立工程，含两个 target
  - `TextReaderKit`（framework）
  - `TextReaderDemo`（App，依赖并嵌入 framework）
- `Tools/make_textreader_demo_proj.py`：确定性重建上述 Xcode 工程

打开 `TextReaderKitDemo.xcodeproj`，选 `TextReaderDemo` scheme 即可运行。要求 Xcode 27 / iOS 27 SDK。

## v1 范围

包含：

- txt / md 文件读取与简单编码探测（UTF-8 / GB18030 / Big5 / UTF-16）
- 自动分章（第X章 / Chapter N / 序章 / 番外），切不出就整本一章
- CoreText 分页 + 翻页 / 滚动两种模式
- 书签、笔记，精确到段落
- 全文搜索，点结果跳段
- 唯一状态源 `TextReaderSession`：章节号 + 页码，所有导航都从这里走

不包含：

- epub / pdf / 图片 / 音视频 / 漫画 / 短剧 / NAS
- 媒体锚点（全书只有 `blk-pN` 一种锚点）
- 旧版 LocalNovel 的进度 / 书签 / 笔记迁移（按你的选择，v1 不迁移）
- 自定义分章规则 UI、排版主题面板、净化规则（按你的选择，v1 不做）

## 关键设计约束

1. **一个锚点空间**：只有 `blk-pN`（段落下标）。没有 `blk-iN` / `blk-a-*`，所以不会出现旧版那种媒体锚点解析失败导致书签记成第 1 段的问题。
2. **一个状态源**：`TextReaderSession` 持有 `chapterIndex` / `pageIndex` / `pages`；视图不各自记位置，不从 `contentOffset` 反推页码。
3. **点当前章不重置**：目录里点当前章传 `paragraph: nil`，其他章传 0，语义与旧版修复后的行为一致。
4. **段落 → 页取首次出现**：`TextPaginator.pageIndex(forParagraph:)` 返回目标段第一次出现的页，跨页长段落不会跳到段尾。
5. **滚动只记位置不改页码**：`noteParagraph(_:)` 只写锚点，翻页页码与滚动偏移彻底分离。

## 接入主 App 的步骤（建议）

1. 先把 `TextReaderKit/` 整个目录复制到主工程，或把它作为本地 Swift Package / framework target 加进 `LocalNovel.xcodeproj`。
2. 在主 App 的 `RootView` 小说分支加一个 feature flag：
   ```swift
   if useNewTextReader {
       TextReaderRootView(books: TextFileLoader.books(in: novelRootURL))
   } else {
       // 现有小说大类
   }
   ```
3. 先只对内测/自己开启，真机回归：分章、翻页、滚动、书签、笔记、搜索、跨章跳转。
4. 稳定后把 flag 默认打开，再逐步删除旧小说大类的重复代码。
5. 如需旧数据迁移，再单独写 adapter；v1 明确不做。

## 已知限制 / 下一步

- 当前 Windows 环境没有 Xcode，**Demo 工程只做了 pbxproj / scheme / 括号静态校验，没有实际编译**。第一次在 Mac 打开若报编译错误，把日志给我，我直接修。
- 分页测量走 CoreText，页面显示用 SwiftUI `Text`；两者字体渲染细节可能有极小差异。若真机发现末行被切，下一步把页面渲染换成 UIKit `CoreTextPageView`。
- 搜索目前是同步扫描，大书可能卡；下一步可以搬到后台队列 + 进度 + 取消。
- 自定义分章规则 UI、主题 / 字号面板、净化规则都还没做，按你的选择留给 v2。

## 重新生成工程

```bash
python Tools/make_textreader_demo_proj.py
```

脚本会覆盖 `TextReaderKitDemo.xcodeproj`，源码目录不受影响。
