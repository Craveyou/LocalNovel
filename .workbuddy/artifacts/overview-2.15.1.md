# LocalNovel 2.15.1（build 19）交付说明

本轮修两个问题：

1. 点「整理」大类里的书 → 侧栏跳回书库首页
2. 点阅读器目录里的某一章 → 落到这一章最后几页

---

## 一、整理分类点书跳回首页

**根因**（两层，叠在一起）：

- 为让小说只有两栏、漫画 / 整理 / 短剧保持三栏，`RootView` 在 `if/else` 里放了两个不同的
  `NavigationSplitView`。这两个分支的类型不同，SwiftUI 会**销毁整棵子树再重建**，
  于是 `LibrarySidebar` 的 `@State openedSection / openedSeries`（当前进了哪个分区、
  哪一层系列）被清空 → 侧栏回到「书库」三张卡片那页。
- 重建出来的三栏分栏视图在手机上（紧凑宽度）用默认的「显示哪一栏」= 正文栏，
  不会自己按当前选中书补一次推入 → 看起来就像「点了书结果跳走」。

**修法**：

- `openedSection / openedSeries` 改成 `@Binding`，状态提升到 `RootView`
  （`sidebarSection / sidebarSeries`），两栏 / 三栏共用同一个 `sidebar`。
  布局切换时层级不再丢，从阅读页退回也还停在原来那一层。
- 新增 `@State compactColumn`，显式驱动手机上显示哪一栏：
  选书（漫画 / 整理 / 短剧）→ `.content`（章节列表）、选章 → `.detail`（正文）、
  回首页 → `.sidebar`。

## 二、目录点章落到章末

**根因**：起始位置一直是「先把段落锚点写进 ProgressStore，阅读器再去读」的副作用链：
谁后写谁赢。旧锚点、残留的跳转标记都能在阅读器读之前把它顶掉，
于是明明点的是第 20 章，落点却是第 20 章上次读到的最后几页。

**修法**：把位置改成**明确参数**，不再靠猜。

| 入口 | 起始段落 |
|---|---|
| 目录里点某一章 | 第 0 段（章首） |
| 书签 / 笔记 / 正文搜索结果 | 记录的那一段 |
| 拖进度条跨章 | 「章索引 + 章内比例」换算出的段 |
| 点书 / 退出再进 / 章末续章 | 这一章上次读到的位置 |

- `RootView` 新增 `ChapterStart{chapterId, paragraph}` + `@State startIntent`，
  `ReaderView` 新增 `startParagraph: Int?`，`restoreParagraph` / `restoreAnchor`
  优先用它，任何存量状态都顶不掉。
- `onSelectChapter` 签名改成 `(Chapter, Int?) -> Void`：`nil` = 从章首，
  非 `nil` = 书签 / 搜索带来的精确段。删掉 `AnnotationStore.pendingJump` 这条旧通道。
- 分页引擎加「恢复期」保护 `isRestoring`：刚切章那一两帧里，系统会把
  `contentOffset` 夹到内容末尾，这时按偏移反推页码会得到「末页」，
  以前会把它当成用户翻页写进阅读记忆。现在恢复期内不认这个反推，
  用户一旦开始拖动 / 手势翻页就立刻解除。

## 三、顺手修掉的两处回归

- 漫画 / 整理 / 短剧「自动续读上次那一话」时，位置不再被重置成章首
  （目录页自动恢复时回调 `onAutoRestore` 告知上层）。
- 在目录里点「当前正在读的这一章」不再把这一章的阅读记忆重置成章首
  （以前点了没反应，现在也还是收面板，但不会污染进度）。

---

## 交付物

- 包：`build/LocalNovel-2.15.1-b19-unsigned.ipa`（3480 KB，sha256 前 16 `8b4de1c0eaf16f4b`）
  - 包内 `2.15.1` / `19`、`com.localnovel.reader`，主二进制 2692 KB，zip 校验通过
  - 固定名副本：`build/LocalNovel-unsigned.ipa`
- CI：run 44080668616（success）
- 自检：`python Tools/static_check.py` 415 通过 / 0 失败；
  `python Tools/check_ipa_readiness.py` 49 通过 / 0 失败
- 版本号四处同步：`Info.plist`、`project.pbxproj`、`Tools/check_ipa_readiness.py`、
  `Tools/static_check.py`

## 安装

把 ipa 拖进 Sideloadly / AltStore，用你的 Apple ID 重签安装。

## 验证清单（装完建议这样试）

1. 进「整理」→ 点作者文件夹 → 应停在章节列表，侧栏不跳回书库首页；
   点某一章 → 进正文；退回 → 还在该作者的章节列表。
2. 小说 → 目录 → 点任意一章 → 应停在这一章**第一页**（再点别的章重复几次）。
3. 小说 → 目录 → 点书签 → 应落到书签那一段。
4. 拖进度条到某章中间 → 应落在该章中间，松手后进度条不弹回。
5. 读到某章末尾退出 → 再点这本书 → 回到刚才那一章那一页。
