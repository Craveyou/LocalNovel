# iOS 阅读交互需求与验收

本文件定义 iOS 对已有能力的交互完善范围。业务定义以 [CAP-LIBRARY](../capabilities/library.md)、[CAP-READING](../capabilities/reading.md)、[CAP-TEXT-COPY](../capabilities/text-copy.md) 为准。Android 实现用作行为参考，iOS 保留原生布局、控件和导航。

交付归入 [0.13.0 计划 R013-06](../plans/0.13.0.md)，开发与验收期间保持 0.12.0。提交 91009df 已包含书架原生长按删除、双滚轮反馈及选区清理实现；2026-10-22 已逐项运行模拟器界面回归，结果见 [iOS 完成记录](../plans/0.13.0-ios-validation.md)。真机体验和性能验收另行完成。

## 范围与分类

实现证据包含 Android 提交 `17276cd`、`610ec0d`、`8bab636` 与 iOS 提交 `91009df`，不以单个最后提交判断范围。

| 需求 | Capability Classification | Android 当前实现 | iOS 当前状态与下一步 |
|---|---|---|---|
| 书架手势区分及长按删除入口 | A. Existing Product Capability：CAP-LIBRARY；手势与按钮组织属 F. Implementation Detail | 左滑编辑/删除，右滑或点击展开卡片收起；纵滑不触发点击或长按；长按显示删除按钮，再确认删除 | 原生侧滑、长按删除、取消/确认、管理模式及手势互斥的 UI 回归通过 |
| 阅读位置调整反馈 | A. Existing Product Capability：CAP-READING；百分比精度与控件属 F. Implementation Detail | 0–100% 进度条；当前选择值一位小数，随拖动即时更新，程序更新同步；浅深主题均可辨识 | 保留两位小数双滚轮及“前往”；实时预览、确认保存、重开恢复和既有设置 UI 回归通过 |
| 页内持续拖动选文 | D. Shared Optional Capability：CAP-TEXT-COPY；长按、锚点和浮层属 F. Implementation Detail | 长按词语后不松手可双向扩选，回到原词恢复初始选区，松手后显示操作浮层 | 持续拖动、主动复制/取消、剪贴板及正式进度隔离的单元和 UI 回归通过 |
| 构建号递增 | F. Implementation Detail | 客户端构建时递增，版本名称仅显式 VERSION 改变 | 构建脚本已有相同策略，不属于本次 iOS 产品交互待办 |
| PDF 左右裁边 | A. Existing Product Capability：CAP-PDF-READING；裁边控件属 F. Implementation Detail | 不继承或要求其他端的专属控件 | 全局内存状态，独立左右滑块、即时适配、恢复原页；不改文件或同步坐标 |

不新增 Product Capability，不将通用触摸操作虚构为平台专属 Feature。正文复制已根据用户明确的 0.13.0 多格式交付承诺升为 active Shared Optional，见 [Decision 0017](../decisions/0017-multi-format-release-scope.md)，并非由双端代码自动升格。本文件的页内交互验收仍为 TXT 基线，新格式需求见多格式阅读文档。

## 书架操作

### 预期行为

- 正常点击书籍打开阅读；纵向滚动仅滚动，不打开书籍、不误触长按。
- 侧滑保留已有编辑和删除入口；操作区域展开后，点击卡片正文先收起操作，不误打开书籍。右滑可收起已展开操作。
- 单书长按入口提供明确的删除操作。长按结束不打开书籍，也不直接删除。
- 选择删除后确认目标书和本地删除范围；取消保留 TXT、书库记录、阅读位置、目录及书签。确认后沿用现有本地删除链路，不调用云端进度删除接口。
- 取消或离开书架不遗留待执行手势。管理模式保留原有勾选/批量删除；若界面呈现导入中项目，该项目不提供打开、编辑、删除或管理勾选。

### 验收条件

分别覆盖轻点、长按后松手、横滑带少量纵向偏移、连续纵滑、手势取消、删除确认与取消；确认不会一次手势既打开书籍又显示删除入口。删除后验证目标本地数据清理及其他书籍保留。

Android 的半菜单宽度吸附、右侧 48dp 按钮和动画时长仅是端内实现参考；iOS 可采用原生长按操作菜单，无须复制卡片位移和尺寸。iOS 已有“目录管理”入口继续保留。

## 阅读位置调整

### 预期行为

- 打开位置调整入口时反映当前阅读位置；调整目标值时立即给出百分比反馈，不能等待异步正文定位结束才更新数值。
- 完成翻页、目录/书签跳转、手动定位或接受同步跳转后，再打开位置调整入口应反映新位置，不保留过期值。
- 目标限制为 0–100%，展示值与可操作值一致；最终位置仍按原始文件字节 offset 和合法字符边界定位，百分比不替代位置真值。
- 浅色与深色主题下，双滚轮的数值、选中项及禁用状态均清晰；保留“百分比整数”和“百分比小数”的可访问名称。
- 沿用现有阅读时间和同步规则：打开面板或只改变待选择数值不生成阅读事件；真正发生正式位置变化时按既有规则提交。Android 拖动会触发延迟正文定位，不能据此认定所有拖动过程均不改变正式进度。

### 验收条件

覆盖 0%、100%、中间值、快速连续调整、程序定位后的重新进入、浅深主题及异步任务返回顺序。确认显示值对应最新选择，不由旧任务覆盖；实际定位遵守字符边界，原地操作不刷新阅读时间。

### 已确认的 iOS 呈现

用户于 2026-10-21 确认 iOS 进度选择保留双滚轮。沿用整数与小数两个滚轮、两位小数精度及“前往”确认；调整滚轮只修改待选择值，点击“前往”后才执行定位。整数为 100 时小数归零并禁用，目标最大为 100.00%。本轮完善集中于反馈、主题可见性和既有行为验收，不增加或替换为滑块。Android 的一位小数、6dp 轨道和 20dp 滑块继续仅属于 Android 实现。

## 页内选文与复制

### 已有行为及核验目标

- 长按选中词语，保持按下并向前或向后拖动可扩选；移回初始词范围时恢复初始选区。
- 松手后提供复制和取消；两个端点可继续在当前页内微调，不交叉、不形成空选区，不切断组合字符或 emoji。
- 仅用户主动复制时写入剪贴板，保持原文及换行，不附加书名、页码或 offset；取消不写剪贴板。
- 选区不跨页、不自动翻页；选择期间屏蔽阅读翻页操作，开始选择停止自动翻页，取消不自动恢复。页面失效或退出时清理临时选区。
- 选文不改变正式阅读位置、阅读时间或同步状态，不上传正文，不新增持久化数据。

### 验收条件

核验中文、英文、跨行、emoji/组合字符、双向拖动、回到初始词、端点交叉保护、复制后粘贴原文一致、取消和退出。验证选择期间不翻页、不产生正式进度事件，取消后恢复正常操作。`testCopySelectionExtendsBothDirectionsWithoutSplittingEmoji`、`testLongPressDragCopySelectionAndCancel` 及相关回归已在本次运行通过；模拟器结果不等于真机验收。

## PDF 阅读显示裁边（2026-10-23 新增）

此项归 CAP-PDF-READING 的 iOS 阅读呈现扩展，不要求 Android 或其他平台继承同一控件。

- 阅读界面的“文档菜单”增加“PDF 裁边”，仅 PDF 显示，解锁并完成正文恢复后可用。
- 原生配置面板提供启用开关、左右独立滑块和“恢复原页”。左右各默认 10%，各可在 0–30% 之间以 1% 调整；首次使用默认关闭，避免直接遮挡正文。开启后按裁边后的页宽适配屏幕，可继续使用 PDFKit 缩放和滚动。
- 手动调整全局即时生效，同一次应用运行中的所有 PDF 共用，切换或重开书籍不重置。不按书保存、不写 SQLite/文件、不上传；应用重新启动后恢复默认关闭状态。
- 只修改当前阅读会话的显示裁框，不写回原 PDF，不改变原文件哈希、加密和复制权限。恢复原页关闭裁边并恢复默认滑块数值。
- 书签、正式进度和同步继续采用原始页面坐标；调整裁边本身不生成阅读时间、不提交新进度。旋转页面按显示后的左右方向裁剪。只为可见页及邻页准备显示裁框，不为裁边一次性加载全书页面。
- 裁边为手动显示调整，不承诺自动识别正文或 OCR；若裁到正文，可减小左右数值或恢复原页。

验证覆盖几何范围/旋转页、全局跨书共用与不持久化、原文件/正式进度不变、宽度变化重新适配，以及实际菜单调整、切书和恢复；结果追加至 [真机验证记录](../plans/0.13.0-ios-device-validation.md)。

## 影响与契约

书架、进度控件和选文需求未新增权限、业务持久化模型、API、认证或同步协议变化。临时选区和手势状态均不持久化；剪贴板只承接用户主动复制的原文。书架长按不是云端删除功能，进度控件不是新的同步策略。PDF 裁边为全局内存显示状态，不改变文档位置、同步契约或数据库 schema 版本。

当前两端差异是交互实现差异，未发现这三项变化引入新的 implementation vs capability conflict。既有 Android 来源设备长名称兼容缺陷仍按客户端文档追踪。本文件不修改 Backend、其他客户端代码或发布状态。

## Source

- [Android 交互说明](../../../apps/android/README.md)，提交 `17276cd`、`610ec0d`、`8bab636`。
- [BookRowGestures](../../../apps/android/app/src/main/java/com/xlib/txtreader/BookRowGestures.java)、[ReaderProgressControlTest](../../../apps/android/app/src/test/java/com/xlib/txtreader/ReaderProgressControlTest.java)、[ReaderLongPressDragTest](../../../apps/android/app/src/test/java/com/xlib/txtreader/ReaderLongPressDragTest.java)。
- [iOS LibraryView](../../../apps/ios/XLibReader/Library/LibraryView.swift)、[ReaderView](../../../apps/ios/XLibReader/Reader/ReaderView.swift)、[ReaderTextSelection](../../../apps/ios/XLibReader/Reader/ReaderTextSelection.swift)。
- [iOS ReaderCoreTests](../../../apps/ios/XLibReaderTests/ReaderCoreTests.swift)、[XLibReaderUITests](../../../apps/ios/XLibReaderUITests/XLibReaderUITests.swift)。
