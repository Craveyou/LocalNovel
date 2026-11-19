# CAP-EPUB-READING

Status: active
Type: Product Capability
Introduced From: 用户提出新增 EPUB 文档阅读需求，并确认先 Android、验证后 iOS。

当前双端已有支持子集实现及自动化验证，见 [验证记录](../plans/0.13.0-validation.md)。iOS 已完成六类大文档真机 Release 测量和连续切书测试，复杂真实文件、低端设备及完整内存/数值预算验收仍未完成，见 [真机记录](../plans/0.13.0-ios-device-validation.md)。需求范围为 [多格式阅读方案](../multi-format-reading.md) 中的已确认范围。

## Purpose

让用户在本地书库中离线阅读 EPUB 电子书，并在文字重新排版后恢复到相同内容位置。

## Business Behavior

通过 CAP-LIBRARY 导入 EPUB，按出版物规定的阅读顺序浏览内容、跨章节导航、使用书内有效目录定位，并调整可重排正文的可读性。退出后重新打开恢复到原内容附近。0.13.0 同时交付正文搜索、用户书签、正文复制与可选阅读进度同步；采用内容定位，不依赖屏幕分页。

## Rules

- 阅读顺序遵循出版物定义，不按压缩包文件名排序，也不以目录条目作为唯一正文清单。
- 可重排内容改变字号、显示面积或排版后，应保留原内容位置；屏幕分页号不能作为持久化位置真值。
- 阅读位置需能识别正文资源与资源内内容锚点，绑定同一源文档；压缩文件字节位置不能表示正文阅读位置。
- 优先使用有效的内置目录；无目录时仍可按阅读顺序浏览，不强制套用 TXT 章节识别规则。
- 内置文本与图片等可支持资源应可离线使用；不为展示内容自动上传文件、加载远端资源或执行外部交互。
- 打开、恢复、重新排版和原地停留不生成新的阅读时间；正式内容位置实际改变才按既有语义记录。

## Data

本地文档身份、格式、展示 metadata、阅读顺序、目录结构、正文资源标识、资源内锚点、真实阅读时间。进度百分比为派生展示值，计算方法须在实现前确定，不作为同步或去重真值。

## API / Contract

本地阅读不需要 HTTP。TXT v1 的 offset/fileSize 比值不代表 EPUB 内容位置。双端与 Backend 已实现 v2 类型化进度协议，以版本化正文资源和 UTF-16 内容坐标表达 EPUB 位置，并与旧 TXT v1 隔离；不得用伪字节位置上传。定位、派生百分比及有效性校验以 [OpenAPI](../../../contracts/openapi.yaml) 和 [本地存储 Contract](../../architecture/local-storage-contract.md) 为准；互操作证据见 [开发验证记录](../plans/0.13.0-validation.md)。搜索/书签/复制复用关联能力，不增加书签或正文同步。

## Edge Cases

缺失或损坏的包结构、正文/图片缺失、无目录、重复目录目标、跨章链接、字体不可用、组合字符、章节末尾、变更排版、源文件替换。当前支持无 DRM、可重排的 EPUB 2/3 子集；加密/DRM、固定版式及媒体交互不在本版本承诺范围，详见 [支持边界](../multi-format-reading.md#支持边界与后续验收)。

## Client Implementations

| Client | Status | Notes |
|---|---|---|
| Android | partial | 已接入格式阅读及关联能力，支持子集和大文档/真机验收边界见开发验证记录 |
| iOS | partial | 已接入格式阅读及关联能力，支持子集和大文档/真机验收边界见开发验证记录 |
| Backend | unsupported | 当前职责为进度服务，不解析或提供 EPUB 正文；多格式进度协议归 CAP-PROGRESS-SYNC，已纳入 0.13.0 |

macOS、Web、Windows 未评估，见 [矩阵](../matrix/capability-matrix.md)。

## Source

- 用户新增 EPUB 阅读需求及“先 Android，验证后再做 iOS”的确认。
- [多格式阅读方案](../multi-format-reading.md)、[Decision 0016](../decisions/0016-multi-format-reading-scope.md)。
- [W3C EPUB Reading Systems 3.3（2024-10-17）](https://www.w3.org/TR/2024/REC-epub-rs-33-20241017/)：阅读顺序、导航、可重排/固定版式的参考，不代表本产品承诺完整标准符合性。

## Related Capabilities

[CAP-LIBRARY](library.md)、[CAP-READING](reading.md)、[CAP-PDF-READING](pdf-reading.md)、[CAP-READING-PREFERENCES](reading-preferences.md)、[CAP-PROGRESS-SYNC](progress-sync.md)、[CAP-SEARCH](search.md)、[CAP-BOOKMARK](bookmark.md)、[CAP-TEXT-COPY](text-copy.md)。

2026-10-21 开发实现及验证证据：[0.13 开发验证记录](../plans/0.13.0-validation.md)。实现状态不表示发布或真机性能验收。
