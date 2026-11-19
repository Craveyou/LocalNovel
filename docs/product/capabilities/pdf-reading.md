# CAP-PDF-READING

Status: active
Type: Product Capability
Introduced From: 用户提出新增 PDF 文档阅读需求，并确认先 Android、验证后 iOS。

当前双端已有支持子集实现及自动化验证，见 [验证记录](../plans/0.13.0-validation.md)。iOS 已完成六类大文档真机 Release 测量和连续切书测试，复杂真实文件、低端设备及完整内存/数值预算验收仍未完成，见 [真机记录](../plans/0.13.0-ios-device-validation.md)。需求范围为 [多格式阅读方案](../multi-format-reading.md) 中的已确认范围。

## Purpose

让用户在本地书库中离线阅读 PDF 文档，保持文档原有版面并恢复阅读位置。

## Business Behavior

通过 CAP-LIBRARY 导入 PDF，浏览文档页面、前后导航、定位目标页、放大查看内容，关闭后重新打开恢复到已记录位置。文档有文本或仅含扫描图片均可作为页面阅读，不以文字识别作为打开前提。需要打开密码时先提示输入，正确后继续阅读前准备，错误可重试，取消返回原入口。0.13.0 同时交付搜索、用户书签、正文复制与可选的阅读进度同步，分别遵守关联能力定义。

## Rules

- 页面顺序和版面以原文档为准，不将 PDF 转成 TXT 后冒充原版阅读。
- 位置由具体文档、页面及必要的页内位置表达；显示页码、文档自带页标签与内部定位值需区分。百分比不是精确位置真值。
- 单纯缩放、打开、恢复和原地停留不生成新的正式阅读位移；翻页或主动导航实际改变位置时沿用正式阅读时间语义。
- 导入和阅读不要求同步登录；不能上传文档、标题或本地路径来完成渲染。
- 失败应保留已有文档与进度；密码错误不等同损坏，不清空位置或重复导入。取消、重试与重开均有确定结果，具体密码状态见多格式需求。
- 密码默认仅用于当前打开会话内存，不自动记住，不进入普通数据库、缓存、日志或同步；关闭/取消后释放。不持久化解密正文或不受保护的敏感派生内容。
- 未解锁不能比较/应用云端定位、更新阅读时间或上传；可定位后先恢复及比较，用户选择并完成定位后才正式阅读。
- 支持常见打开密码 PDF；具体加密兼容样本在实现前明确，不承诺破解密码或绕过文档权限。格式/加密不支持应区别于错误密码。
- 扫描件无文本层或提取受限时明确搜索/复制不可用，阅读、书签和位置同步仍可用；不隐含 OCR。

## Data

本地文档身份、格式、标题/作者等展示信息、文件大小、总页数、页面定位、可选页内位置与真实阅读时间。缺失的作者或页标签不影响基本阅读。需要密码、校验失败、可阅读等打开状态属于会话状态；密码不是书库、进度或同步数据。

## API / Contract

本地阅读与解锁不需要 HTTP。双端与 Backend 已实现 v2 类型化进度协议，使用版本化 PDF 页索引和页内纵向位置，百分比由定位派生；旧 TXT v1 保持隔离，不能上传伪字节 offset。契约见 [OpenAPI](../../../contracts/openapi.yaml)，互操作证据见 [开发验证记录](../plans/0.13.0-validation.md)。密码和正文不进入进度契约，见 CAP-PROGRESS-SYNC。

## Edge Cases

单页文档、第一页/末页、无页面、扫描件、不同页面尺寸/旋转、无文本层、文件缺失/替换、密码保护、损坏页面、加载中离开、空间不足。无文本层不等于不能阅读；搜索/复制仅针对允许提取的文本，OCR、批注未因本轮决定自动纳入。

## Client Implementations

| Client | Status | Notes |
|---|---|---|
| Android | partial | 已接入格式阅读及关联能力，支持子集和大文档/真机验收边界见开发验证记录 |
| iOS | partial | 已接入格式阅读及关联能力，支持子集和大文档/真机验收边界见开发验证记录 |
| Backend | unsupported | 当前职责为进度服务，不导入或渲染文档；多格式进度协议支持归 CAP-PROGRESS-SYNC，已纳入 0.13.0 |

macOS、Web、Windows 未评估，见 [矩阵](../matrix/capability-matrix.md)。

## Source

- 用户新增 PDF 阅读需求及“先 Android，验证后再做 iOS”的确认。
- [多格式阅读方案](../multi-format-reading.md)、[Decision 0016](../decisions/0016-multi-format-reading-scope.md)。

## Related Capabilities

iOS 另有全局生效、不持久化、仅影响显示的手动左右裁边，见 [iOS 裁边交互](../clients/ios-interaction-requirements.md#pdf-阅读显示裁边2026-10-23-新增)。不改原文件或 typed 位置契约，不要求其他客户端采用相同交互。

[CAP-LIBRARY](library.md)、[CAP-READING](reading.md)、[CAP-EPUB-READING](epub-reading.md)、[CAP-PROGRESS-SYNC](progress-sync.md)、[CAP-SEARCH](search.md)、[CAP-BOOKMARK](bookmark.md)、[CAP-TEXT-COPY](text-copy.md)。

2026-10-21 开发实现及验证证据：[0.13 开发验证记录](../plans/0.13.0-validation.md)。实现状态不表示发布或真机性能验收。
