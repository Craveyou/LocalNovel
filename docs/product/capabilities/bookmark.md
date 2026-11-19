# CAP-BOOKMARK

Status: active
Type: Product Capability
Introduced From: 既有产品愿景/功能文档及当前实现，初始抽象于 2026-09-14；见 Source。

## Purpose

保存并重新访问用户标记的阅读位置。

## Business Behavior

添加、列出、跳转和单独删除本地书签；删除书籍时清理其关联书签。

## Rules

0.14.1 扩展：漫画页面/页内书签及无 DRM Kindle 内容书签复用本能力，定位绑定相同原文件和规范内容版本，见 [需求分析](../plans/0.14.1.md)。iOS 两类新格式已接入 typed 存储、同位置提示、保留原记录、预览返回及单条删除；Android Kindle 接入和专项验收状态见能力矩阵。不增加云端书签同步。

既有实现覆盖 TXT 与支持子集内的 PDF/EPUB 本地书签，新增格式分别使用漫画自然图片锚点和 Kindle 规范正文锚点，不改变旧格式的稳定定位与跳转，见 [多格式阅读需求](../multi-format-reading.md)。

书签归属具体本地书籍，TXT 使用原始字节 offset，PDF 使用页面及必要页内锚点，EPUB 使用正文资源及内容锚点。同一本书、同一规范化位置只保留一个书签；重复添加提示“当前位置已有书签”，不新建或替换原记录。不以显示百分比、客户端排版页码或摘要判重；PDF 的文档页面属于其定位的一部分，定位规范化须跨端一致，见 [Decision 0008](../decisions/0008-bookmark-position-uniqueness.md)。支持单独删除选中的书签，不影响书籍、其他书签、本地或云端阅读进度及阅读时间；具体交互由各端决定，见 [Decision 0009](../decisions/0009-delete-individual-bookmark.md)。

## Data

书签标识、书籍标识、格式及定位版本、对应格式的位置、创建时间；摘要是可选展示数据。重排和缓存清除不改变位置，失效定位提示不可跳转而非定位到书首。

## API / Contract

无书签同步 API。

HTTP 字段以 [OpenAPI](../../../contracts/openapi.yaml) 为准；能力描述不复制 Schema。

## Edge Cases

重复添加同一位置、单条删除、删除最后一条后的空列表、书籍删除；同位置唯一与单条删除规则均已确认，当前实现缺口见客户端说明。

## Client Implementations

| Client | Status | Notes |
|---|---|---|
| Android | implemented | TXT 与受支持 PDF/EPUB 已实现；模拟器、会话和跨端验证见开发记录 |
| iOS | implemented | TXT 与受支持 PDF/EPUB 已实现；模拟器、会话和跨端验证见开发记录 |
| Backend | unsupported | 服务端职责，不是阅读客户端 |

未评估端见 [矩阵](../matrix/capability-matrix.md)；partial 表示存在范围缺口或未决业务差异，不等于整个功能不可用。

## Source

- 用户确认先 PDF，密码输入及 PDF/EPUB 搜索/书签/复制/同步纳入 0.13.0；见 [Decision 0017](../decisions/0017-multi-format-release-scope.md)。

- [apps/android/app/src/main/java/com/xlib/txtreader/BookmarkStore.java](../../../apps/android/app/src/main/java/com/xlib/txtreader/BookmarkStore.java)
- [apps/ios/XLibReader/Persistence/LibraryStore.swift](../../../apps/ios/XLibReader/Persistence/LibraryStore.swift)
- [apps/ios/XLibReader/Catalog/CatalogView.swift](../../../apps/ios/XLibReader/Catalog/CatalogView.swift)

## Related Capabilities

CAP-LIBRARY、CAP-READING，参见 [能力索引](README.md)；未决差异见 [初始化决策](../decisions/0001-capability-baseline-and-open-questions.md)。

2026-10-21 开发实现及验证证据：[0.13 开发验证记录](../plans/0.13.0-validation.md)。实现状态不表示发布或真机性能验收。
