# XLib 产品能力

## Product Overview

XLib 帮助用户管理本地书籍与文档、离线阅读和恢复阅读位置。当前已实现 TXT 阅读及可选的跨设备进度同步；Android/iOS 已按先 PDF 后 EPUB 的顺序实现支持子集内的多格式导入、阅读、搜索、书签、复制与类型化进度同步，真机性能及最终版本验收仍在推进，见 [0.13.0 计划](plans/0.13.0.md)。正文、书名和本地路径不上传。当前有 Android、iOS 和 Backend；macOS 已规划但无构建目标，Web、Windows 尚未立项。

已确认先 PDF 后 EPUB，密码 PDF 提示输入；PDF/EPUB 的搜索、书签、复制与阅读进度同步均纳入 0.13.0。格式定位、受限文本、密码流程、验收及其余待决项见 [PDF / EPUB 阅读需求](multi-format-reading.md)。这些范围来自明确产品决定，不由某客户端实现自动传播。

PDF/EPUB 及本轮既有交互需求归入 [0.13.0 开发目标](plans/0.13.0.md)，其中记录该版本原开发/升级规则；当前源码版本和清单状态以 [CURRENT](../CURRENT.md)及版本源为准。未决细化项在计划内跟踪，不自动视为已确认范围。

当前双端已完成和需补齐的工作见 [0.13 功能完成清单](plans/0.13.0-client-completion-review.md)，区分实际业务缺口、验收缺口与未承诺增强。

下一版本目标为 [0.14.1 电子书格式扩展](plans/0.14.1.md)：第一批 CBZ/CBR，第二批无 DRM 的 MOBI/AZW/AZW3。新增 [CAP-COMIC-READING](capabilities/comic-reading.md) 和 [CAP-KINDLE-READING](capabilities/kindle-reading.md)；双端正式链路、公共核心/契约、Backend/PG004/005 与非真机回归已有实现和证据。四漫画原包及六 Kindle 原包均完成真实 Android↔iOS 五阶段接续，见 [Kindle 实施记录](plans/0.14.1-kindle-implementation.md)及[联合记录](plans/0.14.1-kindle-cross-client-validation.md)。需要设备的性能/压力/样本及完整版本出口仍未关闭，不替代 0.13 收口，也不表示已发布。用户要求每批双端并行，全部界面/操作遵循本端 TXT 阅读器，所有公共新增/修改由 iOS agent 负责；详见 [Decision 0019](decisions/0019-parallel-clients-txt-ui-baseline.md)。

## Development Model

本项目采用渐进式多客户端开发：先完成一个客户端，再从已验证行为中提炼产品能力，逐步开发其他客户端。已实现客户端只能作为业务理解、已验证行为和 UI/交互参考，不能自动成为其他客户端的完整需求。

0.14.1 按用户明确指令采用同批双端并行，替代一般模型的客户端串行顺序；跨客户端需求仍来自共同 Capability/Contract，不来自另一端 UI。各端新格式界面必须沿用本端 TXT 规范，公共部分统一归 iOS。2026-10-25 用户进一步通过 [0020](decisions/0020-defer-device-validation.md) 要求功能/界面优先、需要 iPhone 的性能/压力/样本集中后置，不再以第一批完整设备验收阻塞第二批开发；不取消最终验收。该例外不追溯修改 0.13 的交付记录。

需求来源优先级：

1. [Product Capability](capabilities/README.md)：业务语义。
2. [Capability Matrix](matrix/capability-matrix.md)：客户端承诺与覆盖。
3. [Client-specific 文档](clients/README.md)：平台差异。
4. [API / 数据契约](../../contracts/openapi.yaml)：协议约束。
5. 已实现客户端代码：最后的实现参考，不自动传播 UI、快捷方式或系统集成。

发现文档与代码冲突时记录证据，不以优先级掩盖实现缺陷，也不擅自把现状改写成新需求。

## 分类与维护

- **Product Capability**：跨客户端成立的业务能力，不包含平台专属 UI。
- **Shared Optional Capability**：多端可用但并非每端必须交付；active 不等于全端必做。
- **Client-specific Feature**：平台或客户端形态专属的用户功能，仅在客户端文档维护。
- **Client Implementation / Implementation Detail**：能力的客户端实现、存储、渲染、缓存、调度等，不单独制造业务能力。
- **candidate** 是定义成熟度，不是第五种功能类型；功能存在也不意味着已确认为跨端要求。

新增功能先分类；正式业务变更同时更新能力、矩阵、相关客户端和必要的契约。重要升格、拆分、差异取舍写入 [decisions](decisions/README.md)。实际发布后才写入 [releases](releases/README.md)。ID 保持稳定，废弃使用 deprecated 而非删除历史定义。

## 实现与文档边界

初始盘点于 2026-09-14。实现与验证状态集中在 [CURRENT](../CURRENT.md)，不代表已发布版本。Android 阅读交互变化及下一步 iOS 实现范围见 [iOS 交互需求](clients/ios-interaction-requirements.md)。重要规则与来源可从 [决策索引](decisions/README.md) 追溯；初始化错误和后续确认结果已在 [0001](decisions/0001-capability-baseline-and-open-questions.md) 纠正。

[愿景](../VISION.md) 提供方向；docs/features 只保留平台交互或实现索引；[API](../API.md) 集中维护现行接口。发布清单保留历史，当前 draft 不能描述为已发布。
