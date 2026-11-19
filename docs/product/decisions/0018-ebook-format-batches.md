# Decision 0018：0.14 电子书格式分批交付

状态：版本目标、格式与批次顺序 accepted（用户明确指定）；功能子集和技术方案为本次设计基线，尚无实现/验收证据。

适用性：本文件保留原 0.14.0 设计背景；当前目标为 0.14.1，双端执行顺序、TXT 界面基线和公共部分归属以 [Decision 0019](0019-parallel-clients-txt-ui-baseline.md)为准。下面原 Android → iOS 安排不再指导当前版本实施。

## Context

现有 TXT/PDF/EPUB 阅读已具备格式化位置、SQLite 持久化和可选同步。用户要求 0.14 第一批 CBZ/CBR、第二批无 DRM MOBI/AZW/AZW3，并计划由 Android/iOS agent 分别实现。仅增加后缀会导致 ZIP 类型误判、默认 PDF 分支错误和位置契约不兼容。

## Decision

- 新建 active 的 CAP-COMIC-READING 与 CAP-KINDLE-READING，双端实现状态为 planned，不按每个文件后缀建重复能力。
- 按 CBZ/CBR → 无 DRM Kindle 家族推进。沿用 Android 业务先行验证、iOS 独立实现的渐进模型；每批双端验收后进入下一批。
- 搜索、书签、复制和同步使用已有能力；漫画没有正文文本层，不因其他格式具备文字功能就承诺 OCR。
- 本次设计采用本地解析、漫画页面阅读与 Kindle 正文重排两条内容管线。SQLite、原文件、安全存储边界保持；Backend 继续 PostgreSQL，只提供进度服务。
- 新格式定位独立定义并先验证互操作，不借用 PDF/EPUB 的格式身份。具体字段是设计草案，实施时与正式机器契约及后端/双端一起落地。

## Reason

漫画与文字电子书的用户行为和定位语义不同，分别定义能力有明确业务意义；CBZ/CBR 共用页面模型、MOBI/AZW/AZW3 共用内容模型，可以减少重复实现。跨端共享的是可验证的排序/正文/定位契约，平台控件与渲染不自动传播。

## Consequences

0.14 新增范围尚未实现；0.13 的验收、版本和历史决定不被覆盖。依赖选型、许可、RAR 子集、正文规范与性能需要先做技术验证；不能将候选库的格式声明当作完整支持证明。需协同扩展 API 与存储，但本次只写文档，不修改业务代码、Schema、OpenAPI 或发布清单。具体需求、排除项和交接分别见 [0.14 需求](../plans/0.14.1.md)及[技术设计](../../architecture/0.14.1-ebook-formats.md)。
