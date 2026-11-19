# CAP-SEARCH

Status: active
Type: Product Capability
Introduced From: 既有产品愿景/功能文档及当前实现，初始抽象于 2026-09-14；见 Source。

## Purpose

在当前书籍内定位文字而不丢失正式阅读位置。

## Business Behavior

从当前阅读位置向后查找文本，展示结果并允许进入临时阅读。到书末后由用户选择是否从书首继续，继续时搜到本次原起点即结束，不自动循环。

## Rules

0.14.1 扩展：无 DRM Kindle 在规范正文上复用以下搜索规则，并映射回原内容位置，见 [需求分析](../plans/0.14.1.md)。图片漫画无正文搜索，明确说明原因；本版本不引入 OCR，不把页码导航算作文本搜索。iOS Kindle 已实现规范正文搜索、200 条续查和显式回绕、预览返回及 Unicode 锚点映射；Android 接入与专项验收见矩阵，不从通用 implemented 推断双端通过。

当前实现覆盖 TXT 与支持子集内的 PDF/EPUB。下述共同搜索规则继续适用，命中使用格式原生定位：TXT 为原文字节位置、PDF 为页面及文本位置、EPUB 为正文资源及内容锚点。按正文阅读顺序检索，不以渲染屏幕页号排序；跨格式提取/断行到原文定位映射须通过样本验证。无文本层或文本提取受限时明确说明，不自动执行 OCR 或绕过保护。

临时阅读不覆盖正式进度、不作为正式进度上传。

书内搜索统一不区分大小写，例如 hello 匹配 Hello 和 HELLO；命中仍定位到对应格式原文位置并保留原文，见 [Decision 0006](../decisions/0006-search-case-insensitive.md)。

搜索不重叠命中：每次从上一命中的结束位置继续查找，相邻但不重叠的命中正常保留；分段和分批不改变此语义，见 [Decision 0007](../decisions/0007-search-non-overlapping-matches.md)。

每批最多 200 条，允许继续加载直到当前搜索范围结束，200 条不是总结果上限；必须区分已加载数量与全部结果，分批不重复或遗漏命中，见 [Decision 0012](../decisions/0012-search-results-in-batches.md)。

到达书末后，若本次搜索并非从书首开始，提供从开头继续的选择；确认后搜索书首至本次固定原起点的部分，不自动回绕或重复后半部分，见 [Decision 0013](../decisions/0013-search-wrap-with-user-choice.md)。

关键词去除首尾空白后按用户感知字符（Unicode 扩展字素簇）计数，允许 2–32 个，包含上下界；内部空格保留。无效长度提示要求、不执行查询，不静默截断，见 [Decision 0014](../decisions/0014-search-query-character-count.md)。

## Data

查询文本、本次搜索固定原起点、当前搜索范围与续查位置、命中的格式定位（TXT 字节 offset / PDF 页面文本位置 / EPUB 内容锚点）、上下文、临时阅读位置。

## API / Contract

本地能力，无搜索 API。

HTTP 字段以 [OpenAPI](../../../contracts/openapi.yaml) 为准；能力描述不复制 Schema。

## Edge Cases

跨读取边界命中、无结果、Unicode、重复查询及加载失败；既有匹配/分批/回绕差异已补齐，自动化不代替完整字符集与真机验收。

## Client Implementations

| Client | Status | Notes |
|---|---|---|
| Android | implemented | TXT 与受支持 PDF/EPUB 已实现；模拟器、会话和跨端验证见开发记录 |
| iOS | implemented | 已补齐 PDF 页内起点、固定原起点和书首起搜不回绕；旋转/裁边/缩放及 200 条续查边界见 [搜索补齐记录](../plans/0.13.0-ios-search-completion.md)；TXT 搜索器未修改 |
| Backend | unsupported | 服务端职责，不是阅读客户端 |

未评估端见 [矩阵](../matrix/capability-matrix.md)；partial 表示存在范围缺口或未决业务差异，不等于整个功能不可用。

## Source

- 用户确认先 PDF，密码输入及 PDF/EPUB 搜索/书签/复制/同步纳入 0.13.0；见 [Decision 0017](../decisions/0017-multi-format-release-scope.md)。

- [apps/ios/XLibReader/Search/SearchService.swift](../../../apps/ios/XLibReader/Search/SearchService.swift)
- [apps/ios/XLibReader/Search/SearchView.swift](../../../apps/ios/XLibReader/Search/SearchView.swift)
- [apps/ios/XLibReader/Documents/DocumentReaderModel.swift](../../../apps/ios/XLibReader/Documents/DocumentReaderModel.swift)
- [apps/ios/XLibReader/Documents/DocumentReaderView.swift](../../../apps/ios/XLibReader/Documents/DocumentReaderView.swift)
- [apps/ios/XLibReaderTests/DocumentReaderTests.swift](../../../apps/ios/XLibReaderTests/DocumentReaderTests.swift)
- [apps/android/app/src/main/java/com/xlib/txtreader/ReaderTextSearch.java](../../../apps/android/app/src/main/java/com/xlib/txtreader/ReaderTextSearch.java)

## Related Capabilities

CAP-READING，参见 [能力索引](README.md)；未决差异见 [初始化决策](../decisions/0001-capability-baseline-and-open-questions.md)。

2026-10-21 开发实现及验证证据：[0.13 开发验证记录](../plans/0.13.0-validation.md)。实现状态不表示发布或真机性能验收。
