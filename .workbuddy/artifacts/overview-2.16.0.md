# 2.16.0-b20 — 把千阅的「页码即状态」翻页模型搬过来

## 一、千阅（FLReader 2.8.6）的章节跳转是怎么做的

反编译 IPA 主二进制 `FLReader.bin`（arm64 + ObjC 运行时元数据），直接读到调用链：

**1）点目录选章 = 章节 index + 页 index = 0**

`-[ReaderViewController catalogueViewController:selectChapterIndex:]` @0x100186990 的汇编只有三条有效指令：

```
mov x2, x3        ; chapterIndex = 目录传进来的 index
mov w3, #0        ; pageIndex   = 0
b   stub(goChapterWithIndex:withPageIndex:)
```

**2）跳章只认这两个整数**

- `-[ReaderViewController goChapterWithIndex:withPageIndex:]` @0x10017ed48
  = `mov x4, #0` + 尾调 `goChapterWithIndex:withPageIndex:whenLoadChapterFinish:`（block 传 nil）
- 该方法把 (chapterIndex, pageIndex) 捕获进闭包，再调
  `-[ReaderService goChapterWithChapterIndex:pageIndex:httpRequestStart:complete:]`
- `ReaderService` 的实例变量就是 `currentChapterIndex` / `currentPageIndex` 两个 int，
  另有 `PageViewsCache` 按章缓存已排版页面

**3）呈现层只负责「把第 N 页装上去」**

`PageViewController`（`pageVC` = `MyPageViewController` : UIPageViewController，
`scrollPageVC` = `ScrollPageViewController` 自绘跟手滚动）对外暴露的是
`setViewControllers:direction:animated:completion:`、`manualTurnToNextPage/PrePage`、
`leftTapRect / centerTapRect / rightTapRect`（三分区点击）与 `panLockMode`（方向锁）。

**关键结论：千阅全程没有「读 contentOffset 反推第几页」这条路。**
页码是状态，偏移只是渲染结果，所以结构上不可能出现「跳章落到末页」。

## 二、我们为什么会跳到最后一页

旧实现（b19 及以前）的「平移 / 上下」是自己拿 `UIScrollView + isPagingEnabled` 做的：

- 页码靠 `contentOffset.x / pageWidth` 反推；
- 切章那一刻控制器刚建好，`bounds` / `contentSize` 还在变，UIKit 会把
  `contentOffset` 夹到 **contentSize 末尾**（这是 UIScrollView 的既定行为）；
- 任何一次「按偏移反推」都会得到**最后一页**，再被 `adopt()` 写进阅读记忆，
  于是下次进来还是末页 —— 这就是「点目录 → 落在章节最后一页」的完整闭环。

b19 加的「恢复期」标记只是把这窗口挡一挡，属于补丁，不可能根治。

顺带发现第二个真 bug：`pageContainer`（全屏透明容器）盖在分页引擎之上且可交互，
把系统分页器的 pan 全部吃掉 —— 这就是「滑动翻页怎么划都不动」的来源。

## 三、本轮改了什么（`LocalNovel/Views/PagedReaderView.swift`）

| 项 | 改动 |
|---|---|
| 引擎 | 平移 / 上下改成 `UIPageViewController(transitionStyle: .scroll)`，跟手横移、松手吸附、页间过渡全由系统给 |
| 页码 | 只由两处产生：① 上层给的起始段落（点目录 / 书签 / 进度条）② `didFinishAnimating` 里用户真翻过去。**全篇删掉 `indexFromOffset` / `settle` / `scrollViewDidScroll`** |
| 跳章 / 跳段 | `show(index:animated:)` → `setViewControllers([target], direction:, animated:)`，绝对定位，落哪页是哪页 |
| 手势 | 保留三分区点击（左 28% / 中 / 右 72%）；末页继续划由补的边缘 `UISwipeGestureRecognizer` 接下一章（中间页不抢） |
| 层级 | 新增 `installEngineView(_:)`：引擎容器插在**背景图之上**（原来 `insertSubview(at: 0)` 会被主题背景图盖住）；`pageContainer.isUserInteractionEnabled = false`，只有「覆盖 / 无动画」两个引擎自己打开 |
| 脏数据 | `clampedParagraph` 越界一律**回章首**，不再夹到 `count-1`（脏锚点＝打开就末页） |
| 页边阴影 | `PageHost` 换成轻量的 `PageEdgeShadowView`（纯装饰、不吃触摸） |

## 四、验证与交付

- `python Tools/static_check.py` → **420 通过 / 0 失败**（新增 X6 段 5 条：索引模型、容器层级、脏锚点、末页判定）
- `python Tools/check_ipa_readiness.py` → **49 通过 / 0 失败**
- 版本四处同步：`2.16.0` / build `20`（Info.plist、pbxproj、check_ipa_readiness、static_check）
- CI run **44086786261** 编译通过（一次过）
- 产物：`build/LocalNovel-2.16.0-b20-unsigned.ipa`
  - 3561407 字节（3478 KB），主二进制 2692 KB
  - sha256 前 16：`44f8a51fdb80288a`
  - 包内版本 2.16.0 / 20，bundle id `com.localnovel.reader`，zip 校验 OK

## 五、装完建议这样验

1. 小说 → 目录 → 连点几章：每次都应是**该章第一页**
2. 平移模式下左右划：整页跟手移动、松手吸附；点左右 28% 也能翻
3. 拖进度条跨章：应落在拖动位置对应的段落
4. 书签 / 笔记跳转：应落在当时那一段
5. 末页再划一次：进下一章第一页（只划一次，不会连跳）
