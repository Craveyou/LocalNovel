# Android Client

## Role

已有 Java 原生 TXT 阅读客户端，是已验证行为参考，不是其他客户端的完整需求源。

## Implemented Capabilities

CAP-LIBRARY、CAP-READING、CAP-TOC、CAP-READING-PREFERENCES、CAP-SYNC-IDENTITY 的 TXT 基线已实现；CAP-SEARCH、CAP-BOOKMARK、CAP-TEXT-COPY、CAP-PROGRESS-SYNC、CAP-CLOUD-DATA-CONTROL 的 TXT 基线有实现，新格式扩展已实现并完成模拟器与隔离服务验证。candidate CAP-AUTO-PAGING 有实现但无正式跨端交付承诺。见 [矩阵](../matrix/capability-matrix.md)。done 表示代码及自动化覆盖，不等于真机或发布验收通过。

本轮已完成、待优化、待验收及尚未承诺范围集中见 [Android / iOS 功能补齐清单](../plans/0.13.0-client-completion-review.md)，其中 Android 为 A01–A04；iOS 裁边不自动作为 Android 的必修需求。

## 多格式实现与验证

PDF/EPUB 已实现本地导入、阅读恢复、搜索、本地书签、主动复制、v2 进度同步及单书云端删除。SQLite v3 保留 TXT 数据与字节语义，旧 v1 传输保持隔离。支持范围与设备测试见 [0.13 开发验证记录](../plans/0.13.0-validation.md)。模拟大文档已有测量；2026-10-23 补齐新格式搜索停止/后台取消/书首范围、常亮设置和 EPUB 主题持久化，并优化 PDF 全书扫描重复遍历页树，见 [Android 后续完成记录](../plans/0.13.0-android-followup.md)。代表性真机性能与最终验收待完成，开发版本保持 0.12.0。

## 能力实现与验证范围

| Capability | Android 实现 | 回归测试 |
|---|---|---|
| CAP-SEARCH | ICU 扩展字素簇计数；原文大小写不敏感、不重叠匹配，保留字节定位；200 条分批续查及用户手动回绕 | SearchTextRulesTest、ReaderTextSearchTest |
| CAP-BOOKMARK | 书签列表提供单条删除确认；按具体记录删除，不触碰阅读位置/时间 | BookmarkStoreTest |
| CAP-SYNC-IDENTITY | 首次手动开启；后续有效配置自动重建，排队时读取最新配置，旧凭据/缓存/提示失效 | ProgressSyncCoordinatorTest |
| CAP-PROGRESS-SYNC | 定位与比较完成后进入正式阅读；仅实际位移生成时间；远端跳转保留远端时间；离线恢复先比较最新本地状态 | FormalReadingProgressTest、ReadingSyncPhaseTest、SyncRulesTest、ProgressSyncCoordinatorTest |
| CAP-CLOUD-DATA-CONTROL | 书籍编辑和当前书同步设置提供单书删除；上传/删除串行；本次阅读会话持续暂停上传，关闭重开才解除 | SyncApiClientTest、ReadingSyncPhaseTest、ProgressSyncCoordinatorTest |

阅读同步仅针对当前前台、活动、非临时搜索的正式阅读书籍；后台和退出后不补传。配置重建、刷新、网络恢复都不能解除单书删除后的上传暂停。未开启同步不依赖后端即可阅读。

## 阅读时间与同步边界

以下属于已有能力的实现约束：

- 导入不生成阅读时间；无阅读时间使用 0 表示未知/未读，不上传。存在云端进度时仍先比较并提示；首次实际位移才生成本地阅读时间。旧记录缺失时间不以当前时刻补齐，已有有效时间保留，不推测或批量清零历史数据。
- `DEVICE_FORBIDDEN` 进入需手动重新开启状态，用户点击同步刷新重新登记；前台恢复不自动重新登记。身份级 `SYNC_UNAVAILABLE` 不按设备撤销处理。
- 单书同步校验失败后，即使该书本次应用会话已停止上传，重新打开仍允许本地阅读，不停在比较准备阶段。
- 每次打开（包括关闭后重开同一本书）建立独立阅读会话标识；旧拉取不得触发已退出书籍的新上传/跳转提示。已经发出的上传不承诺撤回，云端删除的串行顺序保持不变。
- 回归测试覆盖导入/未知阅读时间持久化、无云端未读书籍、手动设备恢复、单书异常重开、切书与同书重开期间的在途拉取。指定双端真机流程的用户确认、Android 真机性能豁免及未提供的运行日志见 [P8 验收记录](../../architecture/p8-system-validation.md)。

## 客户端扩展与分类

| 用户行为 | Classification | 当前范围 |
|---|---|---|
| 书架横滑、纵滑与长按删除 | A. Existing Product Capability：CAP-LIBRARY；具体手势属 F. Implementation Detail | 横滑展开/收起操作；纵滑不打开书籍或触发长按；长按显示删除按钮，松手不打开；点击删除仍须确认，取消保留数据；导入占位不参与，管理模式保留多选 |
| 阅读进度条反馈与可见性 | A. Existing Product Capability：CAP-READING；控件样式属 F. Implementation Detail | 左侧从固定 0% 改为当前滑块值，显示一位小数，拖动立即更新，翻页/程序定位同步；明暗主题均提供完整轨道及已读段反差，轨道 6dp、滑块 20dp |
| 批量导入与重复内容跳过 | A. Existing Product Capability：CAP-LIBRARY | 单次去重 URI 后最多 20 本，超限整批拒绝；逐本完成，单项失败不阻断后续；完整字节相同则跳过，不覆盖旧数据。跨端批量上限、重复策略尚未确认 |
| 搜索前选择从书首开始 | A. Existing Product Capability：CAP-SEARCH 的候选扩展 | 默认仍从当前页起搜；主动选书首则只搜一遍全书；切换范围清空结果、保留输入，不改正式进度。尚未成为其他客户端要求 |
| 选取并复制正文 | D. Shared Optional Capability：CAP-TEXT-COPY | 当前页内原文复制；长按后持续按住可双向扩选，回到原词恢复初始选区，松手显示复制/取消，再用端点微调；不改正式进度，不上传正文 |
| 阶段门控、配置隔离、单书云端删除 | D. Shared Optional Capability 的已有实现 | 分别归入 CAP-PROGRESS-SYNC、CAP-SYNC-IDENTITY、CAP-CLOUD-DATA-CONTROL，不新增能力 |
| 占位卡片、系统多选、选区拖动锚点与应用内复制浮层 | F. Implementation Detail | 分别服务于导入或复制；正文不启动系统 ActionMode/context 菜单，拖动时隐藏浮层、松手重定位，返回先取消选区。进入选区停止自动翻页，取消不自动恢复。不是独立平台 Feature |

实现细节及边界见 [Android 阅读交互](../../../apps/android/README.md)。批量导入、去重和搜索范围选择均有跨端意义，不能仅因 Android 先实现就归为平台专属，也不能据此修改其他端范围。

书架手势和长按确认的测试源码为 `BookRowGesturesTest`、`BookLongPressDeleteTest`；进度反馈/拖动及明暗对比为 `ReaderProgressControlTest`；持续拖动扩选为 `ReaderLongPressDragTest`、`ReaderTextSelectionTest`。这些测试不等同新增真机验收。本轮审查覆盖 `17276cd`、`610ec0d`、`8bab636`；构建号策略属 F，不新增产品能力。iOS 后续范围及已有复制实现见 [iOS 交互需求](ios-interaction-requirements.md)。

## 0.14.1 新增能力与验收状态

0.14.1 的 CAP-COMIC-READING（CBZ/CBR）与 CAP-KINDLE-READING（无 DRM MOBI/AZW/AZW3）已接入正式链路，复用书库、书签、偏好和同步；Kindle 支持适用的搜索/复制，漫画不做 OCR。Android owner 已交付同源 Kindle 宿主、六原包向量、SQLite v5、293项单元、lint 与模拟器流程，见[本端记录](../../../apps/android/docs/0.14.1-kindle-delivery.md)；六原包真正双端五阶段接续已[通过](../plans/0.14.1-kindle-cross-client-validation.md)。格式能力保留 partial，真机性能/压力/样本及整版出口待验，不再表示尚未实施。新增界面遵循 Android TXT 阅读器的布局、操作逻辑、菜单/弹窗、按钮样式和主题（R014-15）。Android agent 负责本端代码、桥接/构建、迁移/测试与说明，消费并复验 iOS agent 负责的公共契约/Backend/共享夹具。详见 [需求与验收](../plans/0.14.1.md)及 [agent 交接](../plans/0.14.1-agent-handoff.md)。

CAP-PDF-READING、CAP-EPUB-READING：已按 Android PDF → EPUB → iOS 顺序接入，格式阅读实现与跨端定位测试已完成；后续版本验收见 [0.13 记录](../plans/0.13.0-validation.md)。不改变 TXT 的平台交互。

## Unsupported Capabilities

暂无明确排除的正式能力；缺失不等于 unsupported。身份删除已从产品范围排除，不另建客户端能力。

## Client-specific Features

本次盘点未确认独立的平台专属产品功能。系统文件选择、安全凭据存储及渲染技术属于能力实现，不单独创建 Feature。

## Implementation Notes

P2 将导入、书库、搜索、目录/书签、偏好与阅读任务生命周期提取为用例及适配器，分类为 Implementation Detail，不新增 Capability 或平台 Feature。从书首搜索的临时返回位置仍保留搜索前正式位置，修复原实现误用起搜位置的缺陷；能力定义不变。P3 将同步比较状态、配置会话、网络执行与正式进度提交分离，时钟/传输可替换；属于 Implementation Detail，API 和已确认业务语义不变。

P6 将书库、进度、书签、目录、非敏感设置与同步状态迁入 `xlib.db`；`ReadingPreferences` 等 typed Store 通过 `LocalDatabase` 访问。TXT 仍在应用文件目录，Token 仍使用 Android Keystore 保护的现有密文。迁移失败回退 legacy，成功后不双写；legacy 清理由 P7 独立执行。这是 Implementation Detail，不改变 Capability 或同步契约。

P7.1–P7.3 已在 0.11.0 draft 完成：业务 Store 只访问 SQLite；Schema v2 只在检测到 0.10.0 migration ledger 且校验通过后清理 allowlist；旧格式 parser 已删除。Token 密文/IV、Keystore alias、TXT 和 SQLite 保留。用户已确认 0.10.0 完成 Android 真机测试和发布；未提供的设备明细不补写。当前升级与清理边界见 [Legacy Persistence Cleanup](../../architecture/legacy-persistence-cleanup.md)。

StaticLayout、连续缓存与分页窗口均属技术实现。具体原生交互见 [reader](../../features/reader.md)，存储约束见 [Local Storage Contract](../../architecture/local-storage-contract.md)，实现边界见 [architecture](../../architecture.md)。源码位于 [apps/android](../../../apps/android/)。

搜索使用固定版本 ICU4J，以兼容 min SDK 23 的用户感知字符计数；需在发布验收关注包体及低端设备开销。详细检查结果统一见 [CURRENT](../../CURRENT.md)。不自动继承其他客户端的平台专属 Feature。

来源设备名称响应校验已与契约对齐为最多 80 个字符；新增互通测试覆盖超过 20 字符的合法名称。
