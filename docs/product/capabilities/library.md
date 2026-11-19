# CAP-LIBRARY

Status: active
Type: Product Capability
Introduced From: 既有产品愿景/功能文档及当前实现，初始抽象于 2026-09-14；见 Source。

## Purpose

管理可离线访问的个人书库。现有支持格式为 TXT，以及对应格式能力限定的 PDF/EPUB 子集。

## Business Behavior

导入支持格式的文件到本地书库，查看书籍、修改书名/作者并删除本地书籍。新增格式范围见 [PDF / EPUB 阅读需求](../multi-format-reading.md)。

## Rules

0.14.1 扩展：支持子集内的 CBZ/CBR、无 DRM MOBI/AZW/AZW3 原文件导入及混合书库，见 [需求分析](../plans/0.14.1.md)。原文件保留、失败不发布半本书、删除本地不等于删除云端的规则保持。两端已实现漫画和 Kindle 原包识别/验证后原子入库，六 Kindle 原包同源输出与实际双端接续已通过；设备/复杂样本和整版验收仍独立保留，证据见 [实施记录](../plans/0.14.1-kindle-implementation.md)。

书库是本地数据；删除本地书籍不等于删除云端进度。重复导入的合并策略尚未统一。

## Data

书籍标识、格式、书名、来源文件名、作者、文件大小、按格式定义的阅读位置与最后阅读时间；编码适用于 TXT，不强制套用到所有格式。双端 SQLite 当前为 v5：v3 引入 PDF/EPUB 类型化位置，v4/v5 分别扩展漫画/Kindle；旧 TXT 数据与字节语义由迁移保留，见 [本地存储 Contract](../../architecture/local-storage-contract.md)。

## API / Contract

无书库同步 API；不可借进度 API 上传书名或文件。

HTTP 字段以 [OpenAPI](../../../contracts/openapi.yaml) 为准；能力描述不复制 Schema。

## Edge Cases

文件不可读、导入中断、空文件、重复导入、删除关联目录与书签。空文件阅读体验未形成统一验收。

## Client Implementations

| Client | Status | Notes |
|---|---|---|
| Android | implemented | 批量导入与完整字节去重；书架区分横滑、纵向滚动、点击及长按，长按显示删除入口，仍需确认；20 本上限及重复策略仅为该端扩展 |
| iOS | implemented | 已有侧滑、原生长按删除、删除确认和管理模式；交互的本版本验收见 [iOS 交互需求](../clients/ios-interaction-requirements.md) |
| macOS | planned | 仅有基础阅读/书库方向，尚无 target |
| Backend | unsupported | 服务端职责，不是阅读客户端 |

未评估端见 [矩阵](../matrix/capability-matrix.md)；partial 表示存在范围缺口或未决业务差异，不等于整个功能不可用。

本表 implemented 对应已交付的 TXT 书库；PDF/EPUB 混合书架与导入已有实现，格式限制和验收由两项格式能力及 0.13 开发验证记录追踪。

## Source

- [apps/ios/XLibReader/Persistence/LibraryStore.swift](../../../apps/ios/XLibReader/Persistence/LibraryStore.swift)
- [apps/android/app/src/main/java/com/xlib/txtreader/BookStore.java](../../../apps/android/app/src/main/java/com/xlib/txtreader/BookStore.java)
- [docs/features/reader.md](../../../docs/features/reader.md)

## Related Capabilities

CAP-READING，参见 [能力索引](README.md)；未决差异见 [初始化决策](../decisions/0001-capability-baseline-and-open-questions.md)。
