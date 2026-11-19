# CAP-READING

Status: active
Type: Product Capability
Introduced From: 既有产品愿景/功能文档及当前实现，初始抽象于 2026-09-14；见 Source。

## Purpose

无需网络即可阅读已支持格式的书籍和文档，并可靠恢复阅读位置。当前实现基线为 TXT；PDF/EPUB 扩展分别由对应格式能力定义。

## Business Behavior

分页阅读、前后翻页、按位置跳转、保存并恢复正式阅读进度。

## Rules

0.14.1 扩展：漫画使用页面/页内位置，无 DRM Kindle 使用规范正文位置，分别见 [CAP-COMIC-READING](comic-reading.md)和 [CAP-KINDLE-READING](kindle-reading.md)。现有 TXT/PDF/EPUB 定位含义不变。iOS 已接入漫画与 Kindle，Android 漫画已接入、Kindle 待其本端验证；专项跨端及后置设备验收不由通用 implemented 状态推断完成。

位置真值按格式定义，百分比只用于展示和粗跳转。TXT 沿用原始文件绝对字节 offset；PDF 使用页面定位，EPUB 使用正文内容定位，分别见 [CAP-PDF-READING](pdf-reading.md) 和 [CAP-EPUB-READING](epub-reading.md)。同步不可成为本地阅读前提；排版变化不能让内容位置失效，不得把文件字节、字符索引或动态页号混为同一种定位。

## Data

文档格式、正式位置与真实阅读时间；TXT 包含文件大小、编码和 offset，百分比由 offset/fileSize 派生。新格式的定位与派生展示见各格式能力，不把显示百分比作为唯一持久化位置。

## API / Contract

本地阅读不需要 HTTP。CAP-PROGRESS-SYNC v1 仅承接 TXT 位置意义，新格式位置不能直接装入 offset。PDF/EPUB 已使用独立 v2 类型化进度协议，定位版本、有效性校验及旧 TXT 隔离已由双端与 Backend 实现，见 CAP-PROGRESS-SYNC 和 [开发验证记录](../plans/0.13.0-validation.md)。

HTTP 字段以 [OpenAPI](../../../contracts/openapi.yaml) 为准；能力描述不复制 Schema。

## Edge Cases

多字节字符边界、文件首尾、排版变化、文件损坏或替换；大文件应避免整体载入，具体性能指标尚未统一。

## Client Implementations

| Client | Status | Notes |
|---|---|---|
| Android | implemented | 进度条显示当前选择的百分比，拖动立即更新，翻页和程序定位后同步；精度、控件和主题规范见客户端文档 |
| iOS | implemented | 用户确认保留两位小数双滚轮与“前往”定位；后续反馈和主题验收见 [iOS 交互需求](../clients/ios-interaction-requirements.md) |
| macOS | planned | 仅有基础阅读/书库方向，尚无 target |
| Backend | unsupported | 服务端职责，不是阅读客户端 |

未评估端见 [矩阵](../matrix/capability-matrix.md)；partial 表示存在范围缺口或未决业务差异，不等于整个功能不可用。

## Source

- [docs/VISION.md](../../../docs/VISION.md)
- [docs/DECISIONS.md](../../../docs/DECISIONS.md)
- [apps/ios/XLibReader/Reader/ReaderEngine.swift](../../../apps/ios/XLibReader/Reader/ReaderEngine.swift)
- [apps/android/app/src/main/java/com/xlib/txtreader/ReaderPosition.java](../../../apps/android/app/src/main/java/com/xlib/txtreader/ReaderPosition.java)

## Related Capabilities

CAP-LIBRARY、CAP-PDF-READING、CAP-EPUB-READING、CAP-PROGRESS-SYNC，参见 [能力索引](README.md)；未决差异见 [初始化决策](../decisions/0001-capability-baseline-and-open-questions.md)。本表 implemented 表示共同阅读行为的现有 TXT 基线，新格式覆盖单独列在矩阵。
