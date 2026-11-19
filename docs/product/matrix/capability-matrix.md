# Capability Matrix

基于代码与文档，非发布验收。业务定义以能力文件为准。Backend 列表示服务端支持职责，不表示终端功能；API 不是独立客户端，apple-shared 是共享实现包。

执行顺序于 2026-10-25 按用户 [0020 决定](../decisions/0020-defer-device-validation.md) 修订：需要 iPhone 的性能/压力/样本验收集中后置，不再阻塞 Kindle 开发；功能、界面及非设备安全回归继续。表中的 partial/planned 仍表示真实实现与验收状态，不因调整计划改成 done。

- done：当前代码覆盖已定义范围，不代表所有未知产品规则已解决。
- partial：已实现一部分，或存在已知语义冲突/入口缺口。
- planned：有明确计划；不因 macOS 整体 planned 就把所有能力列为 planned。
- unsupported：当前组件职责明确不提供该能力，不代表永久不可变。
- not-evaluated：无明确范围判断；不能等同于不支持或计划实现。

| Capability | Status | Android | iOS | macOS | Web | Windows | Backend |
|---|---|---|---|---|---|---|---|
| [CAP-LIBRARY](../capabilities/library.md) | active | done | done | planned | not-evaluated | not-evaluated | unsupported |
| [CAP-READING](../capabilities/reading.md) | active | done | done | planned | not-evaluated | not-evaluated | unsupported |
| [CAP-PDF-READING](../capabilities/pdf-reading.md) | active | partial | partial | not-evaluated | not-evaluated | not-evaluated | unsupported |
| [CAP-EPUB-READING](../capabilities/epub-reading.md) | active | partial | partial | not-evaluated | not-evaluated | not-evaluated | unsupported |
| [CAP-COMIC-READING](../capabilities/comic-reading.md) | active | partial | partial | not-evaluated | not-evaluated | not-evaluated | unsupported |
| [CAP-KINDLE-READING](../capabilities/kindle-reading.md) | active | partial | partial | not-evaluated | not-evaluated | not-evaluated | unsupported |
| [CAP-SEARCH](../capabilities/search.md) | active | done | done | not-evaluated | not-evaluated | not-evaluated | unsupported |
| [CAP-TOC](../capabilities/toc.md) | active | done | done | not-evaluated | not-evaluated | not-evaluated | unsupported |
| [CAP-BOOKMARK](../capabilities/bookmark.md) | active | done | done | not-evaluated | not-evaluated | not-evaluated | unsupported |
| [CAP-READING-PREFERENCES](../capabilities/reading-preferences.md) | active | done | done | not-evaluated | not-evaluated | not-evaluated | unsupported |
| [CAP-SYNC-IDENTITY](../capabilities/sync-identity.md) | active | done | done | not-evaluated | not-evaluated | not-evaluated | done |
| [CAP-PROGRESS-SYNC](../capabilities/progress-sync.md) | active | done | done | not-evaluated | not-evaluated | not-evaluated | done |
| [CAP-AUTO-PAGING](../capabilities/auto-paging.md) | candidate | done | done | not-evaluated | not-evaluated | not-evaluated | unsupported |
| [CAP-CLOUD-DATA-CONTROL](../capabilities/cloud-data-control.md) | active | done | done | not-evaluated | not-evaluated | not-evaluated | done |
| [CAP-TEXT-COPY](../capabilities/text-copy.md) | active | done | done | not-evaluated | not-evaluated | not-evaluated | unsupported |

0.14.1 新范围见 [需求分析](../plans/0.14.1.md)：CBZ/CBR → 无 DRM MOBI/AZW/AZW3，同批双端并行、公共部分由 iOS agent 负责、界面遵循本端 TXT 基线（R014-15）。两端漫画已实现正式导入/阅读/书签/恢复及 v2 同步，Backend v2/004 和真实 PG 已验证；[漫画五阶段联调](../plans/0.14.1-comic-cross-client-validation.md)补齐四原包 Android↔iOS 模拟器实际接续。Kindle 两端同源正文、交互、v5 存储、Backend/PG005、六原包坐标及[真实五阶段接续](../plans/0.14.1-kindle-cross-client-validation.md)均已有通过证据，见 [Kindle 实施记录](../plans/0.14.1-kindle-implementation.md)。格式能力保留 partial，表示物理设备性能/压力/样本与整版出口未关闭，不表示仍缺解析器或双向接续。既有通用能力行的 done 不代替新增格式专项验收，也不代表 0.14.1 已发布。两项阅读能力的 Backend unsupported 仅表示不承担正文阅读；漫画无 OCR/正文搜索/复制。更多语料和支持子集限制见 [漫画记录](../plans/0.14.1-comic-implementation.md)。

2026-10-23 静态核对发现的 iOS PDF 页内搜索起点和书首搜索回绕入口缺口（I01/I02）已按共同规则修复，CAP-SEARCH 的 iOS 状态恢复 done；见 [搜索补齐记录](../plans/0.13.0-ios-search-completion.md)。两端完成与剩余工作的统一入口见 [功能补齐清单](../plans/0.13.0-client-completion-review.md)。done 不表示复杂文件、性能预算及发布验收已完成。

候选能力的 done 仅表示已存在实现，不表示正式产品承诺。Web / Windows 未立项，无对应空客户端文件。Shared Optional 的选择由客户端范围决定。所有 partial 的具体原因见能力及客户端文档。iOS 新导入时间充当阅读时间的问题已修复，历史记录保持原样；0.11.0 双端真机跨设备接续已由用户确认通过，证据范围见 [P8 验收记录](../../architecture/p8-system-validation.md)。Android 批量导入和搜索起点选择属于已有能力扩展，不据此给其他端新增计划。

PDF/EPUB 的导入、阅读、密码、搜索、书签、复制和 v2 同步已有双端实现及自动化证据；Backend 已有类型化协议与 PostgreSQL 迁移。Android 长设备名称响应兼容问题已修复。iOS 已追加 iPhone 15 Pro Max 的六类大文档 Release 测量及 30 次交替切书，见 [真机验证](../plans/0.13.0-ios-device-validation.md)。格式阅读保留 partial，表示复杂真实样本、低端设备、完整内存口径与最终性能验收仍有边界，不表示缺少本地入口或完全未做真机测量。支持子集、限制、测试和跨端接续结果见 [0.13 开发验证记录](../plans/0.13.0-validation.md)。当前版本与清单状态以 [CURRENT](../../CURRENT.md) 为准；源码改号不等于已发布或部署。

Android 书架手势、进度条反馈及页内拖动选文的实现分类见 [Android 客户端](../clients/android.md)；下一步 iOS 工作见 [iOS 交互需求](../clients/ios-interaction-requirements.md)。CAP-LIBRARY / CAP-READING 的既有业务范围已实现，后续交互完善不将它们改为 planned 或 unsupported。CAP-TEXT-COPY 已因明确交付承诺升为 active，实现状态不表示本版本真机或发布验收完成。
