# CAP-TEXT-COPY

Status: active
Type: Shared Optional Capability
Introduced From: Android 正文复制及双端页内拖动实现；用户明确将 PDF/EPUB 复制纳入 0.13.0 后确认正式可选能力，见 Decision 0017。

## Purpose

让用户提取正在阅读的部分原文，用于粘贴到其他位置。

## Business Behavior

用户选择原文范围并主动执行复制，获得对应文本。复制不改变正式阅读位置或阅读时间。

## Rules

0.14.1 扩展：无 DRM Kindle 的可提取正文沿用选取、主动复制及进度隔离；图片漫画不提供正文复制且不包含 OCR，见 [需求分析](../plans/0.14.1.md)。iOS Kindle 已复用可提取正文的选区/复制，删除内部图像占位符且不改变正式位置或时间；Android 接入及专项 UI/跨端验收另记。

当前实现覆盖 TXT 与支持子集内的 PDF/EPUB 正文选取复制。普通文本 PDF 及支持的 EPUB 提供可用复制；无文本层、权限禁止或不可提取内容明确提示，不自动 OCR、复制图片或绕过保护，见 [多格式阅读需求](../multi-format-reading.md)。

复制范围保留选中文本及换行，不附加书名、页码或位置信息，不向 XLib 后端上传正文。跨页选取和其他导出形式未纳入范围。

## Data

临时选区及其原文内容；不是持久化阅读进度或同步数据。

## API / Contract

无 HTTP 接口，不改变进度同步契约。

## Edge Cases

空正文、字符边界、取消选择、页面变化；选区不得混淆为持久化字节进度。

## Scope Decision

[Decision 0017](../decisions/0017-multi-format-release-scope.md) 基于用户明确的多格式交付要求提升为 active，而非因为已有双端代码自动升格。Android/iOS 在本版本范围内交付，其他端仍未评估；选文手势和 UI 不传播。

## Client Implementations

| Client | Status | Notes |
|---|---|---|
| Android | implemented | TXT 与受支持 PDF/EPUB 已实现；模拟器、会话和跨端验证见开发记录 |
| iOS | implemented | TXT 与受支持 PDF/EPUB 已实现；模拟器、会话和跨端验证见开发记录 |
| Backend | unsupported | 本地文本操作，不承担正文复制职责 |

其他客户端尚未评估，见矩阵。iOS 核验清单见 [交互需求](../clients/ios-interaction-requirements.md)，本次真机证据见 [真机验证](../plans/0.13.0-ios-device-validation.md)。

## Source

- 用户确认先 PDF，密码输入及 PDF/EPUB 搜索/书签/复制/同步纳入 0.13.0；见 [Decision 0017](../decisions/0017-multi-format-release-scope.md)。

- [Android 阅读交互](../../../apps/android/README.md)
- [ReaderPageTextView](../../../apps/android/app/src/main/java/com/xlib/txtreader/ReaderPageTextView.java)
- [ReaderTextSelection](../../../apps/android/app/src/main/java/com/xlib/txtreader/ReaderTextSelection.java)
- [iOS ReaderTextSelection](../../../apps/ios/XLibReader/Reader/ReaderTextSelection.swift)
- [iOS ReaderView](../../../apps/ios/XLibReader/Reader/ReaderView.swift)

## Related Capabilities

[CAP-READING](reading.md)、[CAP-AUTO-PAGING](auto-paging.md)。

2026-10-21 开发实现及验证证据：[0.13 开发验证记录](../plans/0.13.0-validation.md)。实现状态不表示发布或真机性能验收。
