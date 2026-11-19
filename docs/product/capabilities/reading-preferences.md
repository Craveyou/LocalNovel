# CAP-READING-PREFERENCES

Status: active
Type: Product Capability
Introduced From: 既有产品愿景/功能文档及当前实现，初始抽象于 2026-09-14；见 Source。

## Purpose

让用户调整阅读可读性与外观。

## Business Behavior

本地保存字体、字号、行距和明暗外观偏好，并在阅读中应用。

## Rules

0.14.1 扩展（iOS 已接入，双端专项验收另记）：无 DRM Kindle 支持可重排正文可读性设置；漫画支持本地阅读方向选择且保持页面逻辑顺序、原图颜色和内容位置不变。格式范围见 [0.14.1 需求](../plans/0.14.1.md)，具体 UI 由各端独立设计，偏好仍不跨设备同步。

TXT 支持阅读偏好；可重排 EPUB 已接入字体、字号、行距及明暗主题，并在重排后恢复正文锚点。EPUB 支持子集与验收边界见 CAP-EPUB-READING 及各客户端说明。PDF 保持原版面，不自动继承字体/字号/行距调整。

偏好改变不改变原始位置意义；不要求各客户端拥有相同字体清单、范围、默认值或控件。

## Data

阅读外观偏好及其当前值。

## API / Contract

本地能力；不在进度同步协议中传输。

HTTP 字段以 [OpenAPI](../../../contracts/openapi.yaml) 为准；能力描述不复制 Schema。

## Edge Cases

字体不可用、历史设置迁移、排版重建；具体取值在客户端实现中维护。

## Client Implementations

| Client | Status | Notes |
|---|---|---|
| Android | implemented | 以客户端文档及已知差异为准 |
| iOS | implemented | 以客户端文档及已知差异为准 |
| Backend | unsupported | 服务端职责，不是阅读客户端 |

未评估端见 [矩阵](../matrix/capability-matrix.md)；partial 表示存在范围缺口或未决业务差异，不等于整个功能不可用。

## Source

- [apps/ios/XLibReader/Settings/SettingsStore.swift](../../../apps/ios/XLibReader/Settings/SettingsStore.swift)
- [apps/android/app/src/main/java/com/xlib/txtreader/ReaderSettingsOptions.java](../../../apps/android/app/src/main/java/com/xlib/txtreader/ReaderSettingsOptions.java)

## Related Capabilities

CAP-READING，参见 [能力索引](README.md)；未决差异见 [初始化决策](../decisions/0001-capability-baseline-and-open-questions.md)。
