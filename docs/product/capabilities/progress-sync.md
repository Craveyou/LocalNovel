# CAP-PROGRESS-SYNC

Status: active
Type: Shared Optional Capability
Introduced From: 既有产品愿景/功能文档及当前实现，初始抽象于 2026-09-14；见 Source。

## Purpose

在拥有同一源文档的设备间继续阅读，仅交换进度；当前实现覆盖 TXT 与支持子集内的 PDF/EPUB。

## Business Behavior

打开书籍先进入阅读前准备：保留原有本地位置与时间，取得并比较云端状态，完成必要的提示、用户选择和定位后，才进入正式阅读。准备期间不更新时间、不上传本书进度。远端响应不能未经用户确认改变当前阅读页。详见 [Decision 0003](../decisions/0003-pre-reading-progress-comparison.md)。

## Rules

0.14.1 扩展：CBZ/CBR 和无 DRM Kindle 复用阅读阶段、时间裁决、双方百分比、活动书上传和单书删除暂停规则。现行 OpenAPI/Backend 已支持漫画与 Kindle locator，新增 PG004/005，旧 TXT/PDF/EPUB 语义不变。漫画四原包已做双端模拟器接续；Kindle 目前是 iOS→真实 HTTPS/PG17 验证，不代签 Android。详见 [Kindle 实施记录](../plans/0.14.1-kindle-implementation.md)。

v1 定位契约与实现为 TXT；PDF/EPUB 使用双端与 Backend 已实现的独立 v2 类型化定位协议，包含格式、定位版本及进度展示语义，并与旧客户端隔离，见 [多格式阅读需求](../multi-format-reading.md)。页面/内容位置不可伪装成 byte offset。密码文档各端分别解锁，可定位后才开始阅读前比较；密码不参与同步。

文件身份为完整文件 SHA-256 + fileSize。按用户确认的 [Decision 0002](../decisions/0002-latest-reading-time-wins.md)，readAtMs 更新的状态优先，即使阅读位置更靠前；TXT offset、PDF 页面/页内锚点、EPUB 正文资源/内容锚点分别是位置真值，不以百分比比较新旧。时间相同沿用现有确定性裁决。

每次跳转提示必须同时展示本地“当前阅读进度 xx%”和远端目标进度，当前值取提示时保留的本地阅读位置；用户确认后才能跳转。TXT 百分比由 offset / fileSize 派生；PDF/EPUB 根据共享格式定位规范派生，不按二进制文件大小换算，与阅读界面精度一致；平台自行选择布局。实现缺口见 Client Implementations。

正式阅读后，实际改变位置的翻页或主动跳转才更新 readAtMs；仅打开、拉取、周期上传、原地停留和搜索临时阅读不更新。接受远端跳转保留远端时间；选择不跳转保留本地原时间，阶段切换不刷新时间。

只上传当前活动正式阅读会话的书籍，不在书架或其他无阅读会话场景上传保存的书库进度。离线阅读结束后不补传；若恢复网络时仍在阅读，先比较再恢复本书上传。重新打开书籍须重新完成阅读前流程。见 [Decision 0005](../decisions/0005-sync-only-current-reading-book.md)。

单书云端进度删除成功后，该客户端本次阅读会话暂停该书上传，本地阅读与时间记录继续；退出并重新打开、完成阅读前比较后才恢复同步。手动刷新、网络恢复或同步会话重建不得绕过暂停，见 [Decision 0010](../decisions/0010-delete-cloud-progress-per-book.md)。

## Data

文件哈希、大小、格式与定位版本、对应格式位置、readAtMs、云端版本和来源设备；当前 TXT wire 仍只有 offset 等现行字段。百分比为定位的派生展示。不得上传正文、书名、路径、目录、书签、搜索结果、选区、密码或偏好。

## API / Contract

**当前已实现的 TXT v1**：GET /v1/progress 为 pull-only；POST /v1/progress/sync 为 1–100 条且 bookKey 不重复。0 <= offset <= fileSize，fileSize > 0；结果返回 accepted/server_kept/unchanged 和最终状态。

**已实现的文档 v2**：支持格式、定位版本及可跨客户端解释的位置，明确百分比派生语义；保留 TXT v1 读写兼容和身份隔离，旧客户端不能接收不可解释的新格式定位。未知版本、格式不匹配、越界或无法应用的位置保留本地状态并明确失败，不能回落为 0% 或 TXT offset。单书云端删除继续按同一源文件身份隔离，暂停/重开规则不变。

该扩展已协同更新 OpenAPI、API 文档、Backend PostgreSQL Schema/校验/裁决、双端缓存/实现及兼容测试，证据见 [开发验证记录](../plans/0.13.0-validation.md)。后续修改仍须保持契约一致；HTTP 当前字段以 [OpenAPI](../../../contracts/openapi.yaml) 为准。实现与隔离服务测试不代表生产部署。

## Edge Cases

离线、并发、回读、未来时间、首次比较、批量上限；超前超过五分钟的时间由服务端调整。时间更新及阅读前比较边界已由 Decision 0003 确认；离线或服务不可用时从本地位置正式阅读，实际改变位置正常记录时间；恢复后先拉取并比较最新双方状态，完成必要提示与用户选择后才恢复本书上传，不自动跳页、不因恢复或上传刷新阅读时间。拉取失败继续本地阅读但不恢复上传。无会话不上传，离线阅读结束后不补传；上述恢复上传仅适用于仍在阅读的书籍，见 Decision 0005；时间优先已由 Decision 0002 确认。

## Client Implementations

| Client | Status | Notes |
|---|---|---|
| Android | implemented | TXT 与受支持 PDF/EPUB 已实现；模拟器、会话和跨端验证见开发记录 |
| iOS | implemented | TXT 与受支持 PDF/EPUB 已实现；模拟器、会话和跨端验证见开发记录 |
| Backend | implemented | TXT v1 隔离；v2 类型化定位、PostgreSQL 003 迁移、时间裁决和身份级删除；真实隔离 PostgreSQL 及 HTTPS 客户端互通通过，未部署 |

未评估端见 [矩阵](../matrix/capability-matrix.md)；partial 表示存在范围缺口或未决业务差异，不等于整个功能不可用。

Android/iOS 均已补齐双进度提示；0.11.0 指定双端真机跨设备接续流程由用户确认通过，未提供逐项脱敏运行日志，见 [P8 验收记录](../../architecture/p8-system-validation.md)。

## Source

- 用户确认先 PDF，密码输入及 PDF/EPUB 搜索/书签/复制/同步纳入 0.13.0；见 [Decision 0017](../decisions/0017-multi-format-release-scope.md)。

- [docs/DECISIONS.md](../../../docs/DECISIONS.md)
- [contracts/openapi.yaml](../../../contracts/openapi.yaml)
- [services/backend/src/arbitration.ts](../../../services/backend/src/arbitration.ts)
- [services/backend/src/progress-service.ts](../../../services/backend/src/progress-service.ts)
- [apps/android/app/src/main/java/com/xlib/txtreader/SyncRules.java](../../../apps/android/app/src/main/java/com/xlib/txtreader/SyncRules.java)
- [apps/ios/XLibReader/Sync/ProgressSyncCoordinator.swift](../../../apps/ios/XLibReader/Sync/ProgressSyncCoordinator.swift)

## Related Capabilities

CAP-READING、CAP-SYNC-IDENTITY，参见 [能力索引](README.md)；未决差异见 [初始化决策](../decisions/0001-capability-baseline-and-open-questions.md)。

2026-10-21 开发实现及验证证据：[0.13 开发验证记录](../plans/0.13.0-validation.md)。实现状态不表示发布或真机性能验收。
