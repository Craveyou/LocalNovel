# CAP-KINDLE-READING

Status: active
Type: Product Capability
Introduced From: 用户明确要求 0.14.1 第二批支持无 DRM 的 MOBI / AZW / AZW3。

## Purpose

让用户离线阅读自己导入、没有 DRM 限制的 Kindle 格式电子书，并在重排后恢复相同内容位置。

## Business Behavior

识别支持的实际内容格式，按出版物顺序阅读文字和图片，使用有效内置目录和内容导航，调整可重排正文的可读性。复用正文搜索、选取复制、本地书签和可选阅读进度同步。

## Rules

- 格式按内容识别；AZW 是输入后缀之一，不能据后缀断言内部格式或 DRM 状态。同一原始字节仅改名不改变文档身份或定位语义。
- 仅支持无 DRM 的已定义子集；受 DRM 保护、非支持的内容变体明确提示，不提供账号绑定或 DRM 解锁流程。
- 相同源文件在不同客户端使用一致的正文选择、阅读顺序和规范内容锚点；混合文件不能在两端静默选择不同的正文版本。
- 字号、字体和显示面积改变不使内容位置失效；屏幕页号和转换缓存文件字节位置不能作为同步真值。
- 搜索、选区、复制和临时预览沿用已有能力规则；恢复、重排、原地操作不刷新阅读时间。
- 原始文件保持不变，内置资源可离线使用，不自动加载远端资源或执行活动内容。

## Data

原文档身份、识别出的内容类型、出版物阅读顺序、有效目录、规范正文与版本化内容锚点、正式阅读时间。百分比由规范位置派生；显示分页随设备变化。

## API / Contract

本地阅读不需要服务。现行 OpenAPI/Backend 已接受严格 `kindle-text-v1` 定位，参考规范和共用原包见 [正文规范](../../architecture/kindle-text-v1.md)。两端已接入同源核心及 typed 本地持久化，六原包正文/坐标和真实双向接续通过，见[联合记录](../plans/0.14.1-kindle-cross-client-validation.md)，不假冒 EPUB 定位或 TXT offset。只同步进度，不上传正文、文件或书签；功能证据不代表设备预算达标或服务部署。

## Edge Cases

MOBI6/KF8/混合文件、错误后缀、未知编码、缺失目录/图片、DRM、固定版式和非支持变体、长正文、组合字符、内部链接、源文件替换、规范正文版本不一致。无法解释锚点时保留本地进度，不按百分比猜位置或静默切换解析模式。

## Client Implementations

| Client | Status | Notes |
|---|---|---|
| Android | partial | 已接入同源核心、正文/图片/搜索复制/书签/恢复及 v5 定位；六原包同源、模拟器/旧格式与双端接续通过；设备/整版出口未关闭 |
| iOS | partial | 正文、离线图片、导航/搜索/复制/书签、重排恢复及 v2 同步已实现；单元/UI、实际 HTTPS/PG17 与双端接续通过，后置设备验收见实施记录 |
| Backend | unsupported | 不转换或渲染正文；已实现的类型化进度支持归 CAP-PROGRESS-SYNC |

其他客户端未评估，见矩阵。

Android 接入证据见[本端交付记录](../../../apps/android/docs/0.14.1-kindle-delivery.md)，实际接续另见联合记录；不能从单端解析/界面通过推断 G2/G3 已完成。

## Source

用户确认“第二批是无 DRM 的 MOBI／AZW／AZW3”；[0.14.1 需求](../plans/0.14.1.md)、[Decision 0018](../decisions/0018-ebook-format-batches.md)。active 来自明确产品需求，非从某一解析库自动推导范围。

用户最新确认的需求版本、双端并行与公共归属见 [Decision 0019](../decisions/0019-parallel-clients-txt-ui-baseline.md)；平台界面规范留在客户端和交付计划。

2026-10-25 用户调整执行顺序，见 [Decision 0020](../decisions/0020-defer-device-validation.md)：需要 iPhone 的验收后置，不是缩减本能力范围或允许写入未冻结坐标。

## Related Capabilities

[CAP-LIBRARY](library.md)、[CAP-READING](reading.md)、[CAP-TOC](toc.md)、[CAP-SEARCH](search.md)、[CAP-BOOKMARK](bookmark.md)、[CAP-TEXT-COPY](text-copy.md)、[CAP-READING-PREFERENCES](reading-preferences.md)、[CAP-PROGRESS-SYNC](progress-sync.md)。
