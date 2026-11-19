# iOS Client

## Role

已有 Swift 原生 TXT/PDF/EPUB 阅读客户端，自行定义界面和平台集成，不继承 Android 布局与交互。

## Implemented Capabilities

CAP-LIBRARY、CAP-READING、CAP-TOC、CAP-READING-PREFERENCES、CAP-SYNC-IDENTITY 的 TXT 基线已实现。CAP-SEARCH、CAP-BOOKMARK、CAP-TEXT-COPY、CAP-PROGRESS-SYNC、CAP-CLOUD-DATA-CONTROL 的 TXT 基线有实现，新格式已有独立阅读器和类型化同步实现；candidate CAP-AUTO-PAGING 有实现。正文复制含页内长按持续拖动、端点微调及主动复制/取消，临时选区不写正式进度。见 [矩阵](../matrix/capability-matrix.md)。

### Product Capability 实现

搜索与书签属于 A. Existing Product Capability；没有新增正式能力。

| Capability | iOS 设计与实现 | 验收重点 |
|---|---|---|
| CAP-SEARCH | 当前页作为固定原起点；每批最多 200 条，按钮继续加载；书末提供用户主动“从开头继续”，到原起点结束；新查询取消旧任务，失败可重试；结果进入临时阅读，隔离正式保存和同步事件 | 大小写、不重叠、跨段/跨批、200 条后的结束判定、手动回绕范围、UTF-16 字节游标、组合字符 2–32 计数 |
| CAP-BOOKMARK | 存储层按本地书籍 ID + 字节 offset 原子判重；重复提示“当前位置已有书签”；保留原记录；继续支持单条删除 | 重复位置、相邻位置、不同书同位置、持久化重开、单条删除和空列表 |

这些属于已有 Product Capability 的业务补齐。续查按钮、原生导航及异步任务取消属于 iOS 实现细节，不成为跨端 Feature。历史重复书签保持原样，不自动清理。

### Shared Optional Capability 实现（分类 D）

| Capability | iOS 设计与实现 | 验收重点 |
|---|---|---|
| CAP-SYNC-IDENTITY | 配置代际隔离旧登录、拉取、上传与设备响应；凭据清除/写入串行，配置修改立即使旧会话失效 | 延迟登录/拉取不能覆盖新配置，配置离线持久化 |
| CAP-PROGRESS-SYNC | 阅读前比较、选择和定位门控；提示本地与云端百分比；阅读内实际位移更新时间，接受远端保留远端时间；只上传活动正式阅读书籍；新导入/未知时间不上传 | 恢复/原地停留不改时间，准备期不上传，离线恢复先比较，拉取失败只本地阅读，无会话不补传 |
| CAP-CLOUD-DATA-CONTROL | 目录/书签页提供本书云端删除与原生确认；上传/删除串行；成功后暂停本次阅读上传，真正关闭重开才恢复 | 在途上传排序、同会话刷新/配置重建不解除暂停、失败不暂停、本地数据保留 |

书签重复错误传递至页面；导航中断加载后返回可恢复加载，离开阅读停止自动翻页。任务取消、凭据串行写入、隔离 UI 测试入口属于 F. Implementation Detail。既有自动化结果及真实服务验收边界见 [CURRENT](../../CURRENT.md)，不以隔离服务测试代替真实云端验收。

## 搜索边界补齐

CAP-SEARCH：2026-10-23 按既有规则补齐 I01/I02。PDF 将原始页内视觉位置映射为文本起点，支持旋转、裁边与缩放；查询开始后固定起点，预览不改变回绕边界。仅原起点非书首、后半段已搜完且未回绕时提供回绕；书首起搜完成直接显示结束，200 条仍是批大小而非上限。实现与验证见 [搜索补齐记录](../plans/0.13.0-ios-search-completion.md)。TXT 搜索器未修改。

## 多格式实现与验证

PDF/EPUB 已实现本地导入、阅读恢复、搜索、本地书签、主动复制、v2 进度同步及单书云端删除。SQLite v3 保留 TXT 数据与字节语义，旧 v1 传输保持隔离。2026-10-22 补齐打开失败重试、后台/快速导航隔离、搜索取消、EPUB 字体与宽度重排恢复、两章缓存，以及书签错误不关闭面板。真实界面覆盖密码重试/取消/重开、搜索预览返回、书签判重/删除及双格式长按拖动。见 [iOS 完成记录](../plans/0.13.0-ios-validation.md) 与 [0.13 开发验证记录](../plans/0.13.0-validation.md)。模拟及大文档真机测量已有证据，复杂真实文件、低端设备、完整内存/性能预算和最终版本验收仍有边界，当前源码版本与清单状态见 [CURRENT](../../CURRENT.md)，不以改号代替验收。

## 阅读时间与数据兼容

新导入书籍使用现有 Date 格式中的 Unix 时间 0 表示未知/未读，书架显示“暂无阅读记录”；未知时间不上传。打开后仍先比较云端，拒绝跳转继续保留未知时间，接受跳转保留云端真实时间，正式实际位移才生成本地阅读时间。导入伪阅读时间的实现冲突已修复，能力定义不变。

TXT 历史时间保持原样；对早期版本产生的错误时间不做推测清零。数据基线覆盖未读值持久化/重开、元数据编辑不改时间、真实时间保存和重开。同步回归覆盖准备期、原地停留、首次位移以及较早的真实云端进度。验收记录见 [CURRENT](../../CURRENT.md)。

## 交付状态与剩余验收

CAP-PDF-READING、CAP-EPUB-READING：已按 Android PDF → EPUB → iOS 顺序接入，支持子集内的功能开发、模拟器界面及跨端定位测试已完成。2026-10-23 在 iPhone 15 Pro Max/iOS 26.5.2 完成 102 项普通单元、22 项不同 UI 用例分批回归、六类大文档三轮 Release 测量及 30 次连续切书，修复真机动态框架加载路径；本次失败/复核记录、内存口径与最终验收边界见 [真机验证记录](../plans/0.13.0-ios-device-validation.md)。既有模拟器证据见 [iOS 完成记录](../plans/0.13.0-ios-validation.md)。不改变 TXT 的平台交互。

既有交互需求归入 [0.13.0 计划 R013-06](../plans/0.13.0.md)，已执行本版本模拟器回归。详细范围与验收条件见 [iOS 阅读交互需求](ios-interaction-requirements.md)：

- CAP-LIBRARY：原生长按删除入口、侧滑收起、手势互斥、确认/取消及管理模式回归通过。
- CAP-READING：保留两位小数双滚轮与“前往”；实时选择预览、确认定位及重开恢复回归通过。
- CAP-TEXT-COPY（active Shared Optional）：页内持续拖动、主动复制/取消、剪贴板与进度隔离回归通过。

这些沿用已有能力定义，具体字体、尺寸和布局由 iOS 独立实现。

## 0.14.1 新能力与验收状态

2026-10-25 另行执行直接访问已部署 HTTPS Backend 的功能验收，覆盖真实20秒调度、配置自动保存/重登记、多格式原生阅读模型及真实 TXT/Kindle UI；发现并获批修复限流错误码和撤销设备列表展示问题。服务器修复未重新部署，不能把本地回归当线上全绿，具体通过、失败和清理边界见[线上验证记录](../plans/0.14.1-live-backend-validation.md)。

执行顺序更新（2026-10-25）：按用户 [0020 决定](../decisions/0020-defer-device-validation.md)，现在优先补齐漫画及 Kindle 的功能、界面和非设备回归；需要连接 iPhone 的性能/压力/样本集中到全格式功能后联合验收，不再阻塞 Kindle 开发。Kindle 功能已接入，状态为 partial；完整 G1/G2/G3 仍未通过。

0.14.1 第一批 CAP-COMIC-READING（CBZ/CBR）为 partial：已实现内容识别与验证后入库、自然页序、原生图片缩放/适宽/整页/纵向导航、书签预览/恢复、SQLite v5（含无损保留漫画 v4）与漫画定位同步集成。复用 TXT 的 35/20/45 点击区、上下玻璃工具栏、主题/锁屏控件及双滚轮“前往”；图片不反色，不提供 OCR/正文搜索/复制。采样每图最多约八百万像素，串行解码、当前图片显示，原始页临时磁盘 LRU 每会话 512 MiB、全局 1 GiB，退出清除，崩溃残留下次首次使用清理。正式锚点为自然图片位置，不受缓存/缩放影响。

模拟器普通单元、全量常规 UI 与真实 HTTPS/PostgreSQL 漫画同步已有通过证据；用户授权后补齐四原包 Android↔iOS 同服务五阶段接续（iOS build123/124），见[漫画联调](../plans/0.14.1-comic-cross-client-validation.md)。Kindle 正文、离线图片、目录/链接、搜索/复制/书签、临时预览、重排/重开恢复和类型化同步已实现；同源 MIT 核心与六原包、SQLite v5、OpenAPI/Backend/PG005 及单元/UI 证据见 [Kindle 实施记录](../plans/0.14.1-kindle-implementation.md)，六原包真正双端五阶段也已[通过](../plans/0.14.1-kindle-cross-client-validation.md)。最终 iOS 单元 135 通过/12 条件跳过/0失败、Kindle UI2/2、Backend88/88、共享32项、普通 make check 均通过。需要 iPhone 的性能/压力/样本仍按0020后置，不把这些功能证据当整版发布验收。新增界面遵循 iOS TXT 规范（R014-15），基线提交为 `09d399035692a6f69dbc35ef652a4a4475d8b79b`。iOS agent 负责公共契约、Backend、共享依赖/夹具、根检查及共同文档；Android 本端由其任务交付。详见 [需求](../plans/0.14.1.md)与[agent 清单](../plans/0.14.1-agent-handoff.md)。既有 PDF/EPUB 状态不因此重置。

漫画 RAR4 已按用户批准接入官方 UnRAR 7.23 正式版内存解码，libarchive 3.8.9 继续负责严格元数据/文件名校验及 ZIP/RAR5。新增 24 张原创 PNG 的真实 RAR4 固实样本，扩展逆序读取、取消/损坏/并发、导入/书签/重开与前后各 20 页 UI 回归；实际运行结果见实施记录第 15–16 节。许可全文随 AppleShared 和应用根资源分发，不包含 RAR 压缩器或外部命令运行路径。此项不等于完整 RAR 方法、真机性能或 Android/iOS 联合验收。

最新补齐：书架封面取确定页序的第一页（最长边 192 像素，内存缓存 8 MiB / 64 项，可重建，不改阅读时间）；JPEG EXIF 方向/颜色与坏末页拒绝回归；导入期间显示进度和“取消导入”，后台执行验证并在发布前检查取消。TXT 从原先仅检查开头改为完整流式编码/控制字节验证，保留原始字节及多字节边界；BOOKMOBI 或晚出现的二进制不再误入 TXT。预检与分块复制保留 16 MiB 空间余量，失败/取消保留旧书、进度和书签并清理本次副本，最终仍以文件写入结果为准。

真实模拟器手势回归覆盖右向左阅读、反向翻页、放大后拖图不翻页、适宽/整页、明暗主题、长图拖动、旋转及同页重开。UIScrollView 在未放大时让翻页手势优先，放大后交回原生图片平移；开关测试点击实际控件并断言值，避免只点标签造成假失败。SwiftUI 状态/异步任务按本端组件模式收敛，封面取消后不发布旧任务结果。最新完整测试与物理设备边界见实施记录第 16 节。

## Unsupported Capabilities

暂无明确排除的正式能力；缺失不等于 unsupported。身份删除已从产品范围排除，不另建客户端能力。

## Client-specific Features

本次盘点未确认独立的平台专属产品功能。系统文件选择、安全凭据存储及渲染技术属于能力实现，不单独创建 Feature。

## Implementation Notes

P4 将阅读同步会话、身份配置、串行副作用与正式进度时间规则提取为独立内部组件，属于 F. Implementation Detail。沿用同一能力及 API，不新增平台 Feature。临时页面离开只暂停，返回同一阅读会话仍保留云端删除后的上传暂停；旧页面回调不能修改同书的新会话。书籍边界裁剪后没有实际位移时不生成时间。旧服务器凭据清理与新登录保存按顺序执行。验证与未验收边界见 CURRENT。

P6 将书库、进度、书签、目录、非敏感设置与同步状态迁入 `xlib.db`；`LibraryStore`、`SettingsStore`、`SyncStateStore` 和 `SyncConfigurationSession` 通过 `LocalDatabase` 访问。原文档仍在 Application Support，Credential 仍保留原 Keychain service/account。P7 已删除 legacy 回退，数据库或迁移失败保留数据并显示不可用状态；当前 iOS 开发 SQLite v5 在 v4 漫画坐标基础上增加 Kindle typed 定位，原子保留旧 TXT/PDF/EPUB/漫画数据；Android schema 版本以其本端为准。迁移属于 Implementation Detail，不改变既有坐标语义。

P7.1–P7.3 已在 0.11.0 draft 完成：业务 Store 只访问 SQLite；Schema v2 只在检测到 0.10.0 migration ledger 且校验通过后清理 allowlist；旧 Codable/JSON/UserDefaults parser 已删除。Keychain、TXT 和 SQLite 保留。用户明确 iOS 不影响本阶段继续；Simulator、构建和单元测试结果不等同真机分发证据。当前升级与清理边界见 [Legacy Persistence Cleanup](../../architecture/legacy-persistence-cleanup.md)。

SwiftUI / UIKit / Core Text 与 Keychain 是平台实现；AppleShared 只容纳 UI 无关代码。当前前台单一 20 秒调度，后台仅尽力执行，不承诺持续运行。存储约束见 [Local Storage Contract](../../architecture/local-storage-contract.md)，细节见 [iOS 实现说明](../../features/ios.md)。

无阅读会话的全书库上传路径已移除，不建立离线退出后的补传队列。完整验证边界见 [CURRENT](../../CURRENT.md)。
