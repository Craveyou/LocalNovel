# Decision 0016：多格式阅读与渐进式交付

状态：PDF/EPUB 产品方向与 Android → iOS 顺序 accepted；PDF 优先及 0.13.0 密码/搜索/书签/复制/同步范围已由 [Decision 0017](0017-multi-format-release-scope.md) 明确；其余格式子集仍待验证，见 [多格式阅读需求](../multi-format-reading.md)。

## Context

现有客户端及持久化、目录、书签和进度同步实现围绕 TXT 原始字节 offset。用户明确提出 PDF 和 EPUB 阅读，并确认先实现 Android、验证后再实施 iOS。仅放宽文件选择后缀不能满足该需求。

## Decision

- 建立 active 的 CAP-PDF-READING 与 CAP-EPUB-READING，记录明确的产品级阅读需求；实现状态均为 planned。
- 复用 CAP-LIBRARY 与 CAP-READING 的共同业务语义，各格式保留自己的定位语义。PDF 的页面位置和 EPUB 的内容位置不能被解释为 TXT 字节 offset。
- Android 为先行端；iOS 在 Android 验证后实施。macOS、Web、Windows 不自动继承实施计划。
- 保留 TXT v1 同步契约；多格式同步已在 Decision 0017 确认纳入 0.13.0，须先定义定位协议和兼容性，不通过伪造 offset 适配现有 API。

## Reason

两种格式是明确提出的产品需求，具备跨客户端业务意义，因此不列为仅从实现发现的 candidate。它们的版面、导航和位置语义不同，分别定义有利于验收；页面缓存、渲染引擎、解包及控件仍是 Implementation Detail，不另立能力。

## Consequences

当前代码仍只实现 TXT，本轮不修改代码、数据库 Schema、HTTP 契约或发布清单。两项新格式为 planned；已有能力扩展为 partial，明确 TXT 已实现与新格式缺口，避免把产品计划写成已交付。实施前需确认首期范围并扩展共享本地位置契约与幂等迁移，已有 TXT 进度不得重算或清零。PDF/EPUB 的搜索、用户书签、复制、同步已由用户明确承诺，详见 Decision 0017；批注、DRM、固定版式 EPUB 等不从 TXT 或其他客户端自动传播。
