# CAP-COMIC-READING

Status: active
Type: Product Capability
Introduced From: 用户明确要求 0.14.1 第一批支持 CBZ / CBR。

## Purpose

让用户从本地漫画包离线阅读按序组织的图片页面，并恢复到此前阅读的位置。

## Business Behavior

导入支持的漫画包，按确定的页面顺序阅读、翻页、跳页、缩放和适配页面，查看页码及进度，退出后恢复同一页面及必要的页内位置。通过已有能力提供本地书签和可选阅读进度同步。

## Rules

- 相同源文件在不同客户端产生相同的页面集合与顺序；不得因压缩条目顺序、平台排序或不可显示页面被静默跳过而改变页码。
- 进度绑定源文档中的页面与内容位置，缩放比例和屏幕分页不是权威位置。应用主题不改变原图颜色。
- 翻页、跳页和实际页内内容位移才产生正式阅读事件；导入、打开、恢复、缩放及缓存准备不生成阅读时间。
- 图片没有正文文本层时，搜索/复制明确说明不可用，不将页码查找或文件名查找冒充正文搜索；本版本不包含 OCR。
- 0.14.1 支持子集、失败提示和验收以 [需求分析](../plans/0.14.1.md) 为准；加密/分卷不隐式成为必做范围。

## Data

原文档身份、页面集合与确定顺序、页面标识、页面内锚点、正式阅读时间。页数和百分比是位置相关展示；封面/缩略图可以重建，不替代原文件或正式位置。

## API / Contract

本地阅读不需要服务。现行开发中的 OpenAPI / Backend v2 已接受 comic-order-v1 漫画定位，使用原始文件身份和独立清单/页面哈希；PostgreSQL 004、真实数据库及四原包 Android↔iOS 模拟器五阶段接续已有证据，尚未部署或完成含物理设备预算的完整联合出口。见 [实施记录](../plans/0.14.1-comic-implementation.md)及[跨端证据](../plans/0.14.1-comic-cross-client-validation.md)。不能将漫画位置伪装成 PDF 或 TXT。同步继续只传本书进度，遵循 CAP-PROGRESS-SYNC。

## Edge Cases

无图片、图片损坏、单页/长图、子目录和非 ASCII 文件名、相同排序值、路径冲突、加密/分卷、固实压缩、大图内存、磁盘满、取消/中断、源文件替换、页序不一致。失败保留旧位置及时间，不自动回到第一页并覆盖记录。

## Client Implementations

| Client | Status | Notes |
|---|---|---|
| Android | partial | 已接入正式漫画导入/阅读/书签/恢复及共同 v2 契约，依据[本端记录](../../../apps/android/docs/0.14.1-comic-delivery.md)；真机预算与双端联合出口未完成 |
| iOS | partial | 0.14.1 第一批已接入导入/原生阅读/书签/恢复及共享定位；RAR 方法覆盖、真机与联合验收仍待完成，见实施记录 |
| Backend | unsupported | 不解包或渲染漫画；已实现的漫画进度支持归 CAP-PROGRESS-SYNC |

其他客户端未评估，见矩阵。

## Source

用户原确认“新版本 0.14，第一批 CBZ/CBR”，最新要求将需求目标修订为 0.14.1；[当前需求](../plans/0.14.1.md)、[原格式决定](../decisions/0018-ebook-format-batches.md)。active 表示产品方向已明确，不表示代码已有实现。

用户最新确认的需求版本、双端并行与公共归属见 [Decision 0019](../decisions/0019-parallel-clients-txt-ui-baseline.md)；平台界面规范留在客户端和交付计划，不写入跨端业务定义。

## Related Capabilities

[CAP-LIBRARY](library.md)、[CAP-READING](reading.md)、[CAP-BOOKMARK](bookmark.md)、[CAP-PROGRESS-SYNC](progress-sync.md)、[CAP-CLOUD-DATA-CONTROL](cloud-data-control.md)。
