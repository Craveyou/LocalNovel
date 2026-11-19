# 当前实现与验收状态

当前开发版本与需求计划更新：2026-10-25；下文 P5–P8 验收证据保留原范围。本文记录当前工作树和已核实发布状态；产品规则以 [docs/product](product/README.md) 为准。

最新线上验证：用户确认 Backend 已部署，本轮直接访问已部署 HTTPS 服务，不使用本地服务代替。12个文档样本、身份/TXT仲裁、真实20秒自动同步及3项真实UI均通过；iOS重进设备管理显示撤销历史的问题已修复并线上复验。Backend限流误返回500已在源码修复，90项测试（含18项专用PG17）通过，但按用户要求未部署，线上该项仍失败，不能宣称全绿。修复后iOS单元136通过/12条件跳过、真实UI3/3通过；修复前普通UI基线32通过/18物理性能跳过，最终make check通过。分轮结果与清理限制见[线上验证记录](product/plans/0.14.1-live-backend-validation.md)。

0.14.1 的 CBZ/CBR 与无 DRM MOBI/AZW/AZW3 双端功能、公共核心/契约、SQLite v5、Backend/PG004/005 和非真机回归已完成本轮交付。官方 UnRAR 固定 7.23 正式版支持 RAR4 固实解码，原严格路径校验和 ZIP/RAR5 不变；Kindle 使用同源 MIT 核心，六原包在 Node/JSC/Android 的正文、坐标及实际五阶段接续均有通过证据，见 [Kindle 实施记录](product/plans/0.14.1-kindle-implementation.md)。两项格式能力保留 partial，表示真机性能/压力/样本和整版出口尚未关闭，不表示仍缺宿主或双端接续。需要 iPhone 的验收按 0020 后置。所有公共新增/修改归 iOS agent，全部界面/操作遵循本端 TXT 规范（R014-15）；漫画证据见 [实施记录](product/plans/0.14.1-comic-implementation.md)。本轮不替代 0.13 验收或整版发布；部署与后续修复状态以上述线上验证记录为准。

漫画补齐见实施记录第 16 节：iOS 完整 TXT 流式校验、可取消/容量保护导入、漫画首图封面与 JPEG/手势回归；公共核心修复 UnRAR 未对齐整数访问，通过 1024 例 ASan/UBSan 有界变异回归及 API23 三 ABI 配对链接/开发探针 16 KiB ELF 检查。Android 本端也已进入正式漫画链路，能力状态为 partial，不再写作未接入。上述公共编译/探针不替代最终客户端打包、设备与双端接续。最新 Kindle 单元/UI、共享核心、Backend 和真实 HTTPS/PG17 结果见 Kindle 实施记录；用户已授权分离开发与发布检查，不再用历史清单隐式阻塞普通开发检查，发布校验仍保留。

用户授权后的同服务五阶段联调已通过：四原包 Android→iOS→Android 回退更新→iOS 删除→Android 确认，使用真实客户端和 HTTPS/隔离 PG17。Android build108 三阶段、iOS build123/124 两阶段均通过，保留原时间、时间优先、清单冲突和删除暂停均有实际证据；见[双端联调记录](product/plans/0.14.1-comic-cross-client-validation.md)。不再把模拟器双向接续列为缺失，物理设备/压力预算/完整界面对照和版本出口仍独立待验收。

Kindle 六原包同服务五阶段也已全部通过（Android build115 与 iOS 实际客户端），见[联合记录](product/plans/0.14.1-kindle-cross-client-validation.md)。最终非真机回归：iOS 单元135通过/12条件跳过/0失败、Kindle UI2/2、共享32项、核心7项、Backend88项（含18项真实PG17）、原生安全1024例有界变异；Android owner交付293项单元及模拟器流程。最终串行 `make check` 完整通过，iOS clean build149；条件跳过、历史失败与修复链均保留，不将模拟器证据当成真机预算或发布验收。

## 组件与版本

执行顺序更新（2026-10-25）：用户已通过 [Decision 0020](product/decisions/0020-defer-device-validation.md) 将需要 iPhone 的性能/压力/样本验收后置到全格式功能完成后；现在继续漫画/Kindle 功能、界面与非设备回归。完整 G1/G2/G3 未通过，但不再以连接真机或漫画完整设备验收阻塞 Kindle 开发。此变更不豁免测试，不改变格式范围、数据保护、公共契约冻结要求或版本/发布状态。

| 组件 | 当前源码 | 状态依据 |
|---|---|---|
| Android | 0.14.1；build 以源码为准 | [version.properties](../apps/android/version.properties) |
| iOS | 0.14.1；build 以源码为准 | [Xcode 配置](../apps/ios/XLibReader.xcodeproj/project.pbxproj) |
| Backend | 0.10.0 | [package.json](../services/backend/package.json) |
| macOS | 无构建目标 | planned，仅项目约束 |

当前工作树两端版本名均为0.14.1（本轮沿用已有版本名），尚无对应发布清单，版本出口未关闭。普通 `make check` 不再默认绑定历史清单；显式 RELEASE/RELEASE_VERSION、check-alpha、release-check 仍严格检查版本及 build。0.14.1 开发不通过伪造已完成发布清单来绕过检查；源码改号不表示已发布或全部验收通过。既有功能范围见 [0.13.0 计划](product/plans/0.13.0.md)，新格式目标见 0.14.1 计划。0.11.0/0.12.0 草稿保留，0.10.0 仍是 released/tagged 的 SQLite 强制迁移基线；旧 migrator 退役政策不变。TXT API 保持 v1，PDF/EPUB/漫画/Kindle 使用 v2 类型化进度协议；Backend 组件保持0.10.0。漫画/Kindle已按用户确认部署并有公开API行为证据；健康接口不暴露部署提交，不能据此声称服务器等于当前工作树。本轮新增限流修复未部署。

## 当前产品能力与接口

- 14 项 active 能力、1 项 candidate（自动翻页）；含 0.14.1 的两项新阅读能力，漫画与 Kindle 双端功能及实际联合接续已通过本轮非真机验证，状态仍为 partial，等待后置设备验收和整版出口。PDF/EPUB 已有 Android/iOS 实现及模拟器和真实隔离 PostgreSQL 接续测试，性能与发布验收待完成。0.13 曾按 Android 先行、先 PDF 后 EPUB，再实施 iOS；该历史顺序不约束 0.14.1 同批并行。各端状态见 [矩阵](product/matrix/capability-matrix.md)，用户已确认的规则集中于能力文件，决策解释理由。
- 旧同步长文中的 offset 优先算法、手动应用配置要求、全量删除及身份删除说明已移除；保留稳定文件入口及有用的平台实现细节。
- 后端与 OpenAPI 新增 `DELETE /v1/progress/{bookHash}/{fileSize}`，只删除认证身份下指定文件的进度，不存在记录也返回 204。
- 旧的全量进度清空与身份删除路由、服务方法已移除。两端传输层改为 deleteBookProgress；旧全量删除协调器方法及未被调用的 Android 确认方法已删除。初次盘点将这个 Android 方法误计为用户入口，此处纠正。
- Android/iOS 均已补齐单书删除用户入口、在途上传排序及阅读会话暂停；0.11.0 真实服务与跨设备行为由用户确认通过。
- 普通开发检查/CI 不隐式选发布清单，显式选择缺失或不匹配的清单仍失败。历史 0.11.0 退役策略与开发/发布入口回归使用隔离夹具，不依赖当前组件版本。Android/iOS 构建自动递增 build 号，只有显式传入不同 `VERSION` 时更新组件版本名；Backend 仅在显式传入 `VERSION` 时更新 package 版本。Alpha 保留版本名/清单不变检查，正式发布仍严格匹配最终 build。

## 已确认能力的实现

| 范围 | Android | iOS |
|---|---|---|
| 搜索 | 已补齐匹配/计数，包含跨 segment、续查和手动回绕测试 | 已补齐 200 条续查、主动回绕至原起点、当前页起搜、Unicode 测试及临时阅读同步隔离 |
| 书签 | 已补齐单条删除及空列表，保持位置唯一 | 已补齐同位置唯一及重复提示；历史重复记录未自动清理 |
| 同步配置 | 已补齐自动应用、凭据/缓存/旧提示失效 | 已补齐旧异步响应隔离和凭据串行写入；延迟登录/拉取测试通过 |
| 阅读阶段 | 已实现定位/比较门控及仅实际位移生成时间；导入与缺失时间不生成阅读事件，真机流程由用户确认通过 | 已有准备门控及恢复时间保留；新导入时间为 0，未知时间禁止上传，先比较真实云端状态，实际位移才生成时间；真机流程由用户确认通过 |
| 同步范围 | 仅活动正式阅读书籍；离线恢复比较最新状态，退出不补传 | 已移除全书库上传；仅活动正式会话，离线恢复先比较，失败不上传 |
| 跳转提示 | 已显示当前本地与云端进度；旧提示失效有回归测试，真机接受/拒绝流程由用户确认通过 | 已显示双方进度；旧提示随配置/网络失效，真机接受/拒绝流程由用户确认通过 |
| 单书云端删除 | 已补齐入口、串行请求、暂停及关闭重开恢复测试 | 已补齐入口、确认、串行请求、同会话暂停和重开恢复；失败不暂停 |

后端时间优先裁决已有；客户端最新阅读时间生成与上传的 0.11.0 双端真机联调由用户确认通过。服务端仍不能判断 UI 阅读阶段，客户端回归继续负责保护这些规则。

## 尚未作产品决定

自动翻页是否成为正式跨端可选能力；Android 批量导入上限、字节去重与起搜前选择书首是否形成共同规则；历史导入伪阅读时间如何处理；章节识别的一致性验收；空文件、重复导入和历史重复书签处理；大文件量化指标；新客户端同步范围；更强认证方案。它们是未明确范围，不作为已确认需求，也不应按某个已有客户端自行补全。

## 验证

### P5：Backend PostgreSQL 边界与集成

Backend 保持 PostgreSQL，不改为 SQLite。身份和进度 SQL 已分别收口到 `IdentityRepository`、`ProgressRepository`；Service 继续控制事务和业务顺序。身份级 user lock 串行化容量检查、上传、单书删除与设备撤销，并在等待后重新查询设备状态，避免排队请求使用撤销前快照。没有修改 OpenAPI、路由、响应、PostgreSQL migration、同步规则或组件版本。

`make test-backend-postgres` 使用临时 PostgreSQL 17、私有 Unix socket、独立 owner 与受限应用角色执行完整 Backend 检查：lint、typecheck、build 和 71 项测试通过，其中 13 项真实数据库集成测试覆盖受限角色、Token/身份隔离、并发注册与上传、批次回滚、10,000 条容量并发、上传/删除顺序及撤销后排队请求拒绝。此前各节记载的“PostgreSQL 测试跳过”是当时的历史验证记录，不再代表当前 P5 状态。

安全复核未发现新增凭据输出或权限扩大；应用角色无 superuser、createdb、createrole、bypassrls 和 schema DDL 权限。P5 没有生产数据库迁移，也没有访问或部署真实服务。随后 P8 的指定双端真机接续由用户确认通过；0.11.0 仍为 draft，本任务没有生产部署或发布。

### P6：Mobile Local Storage Consolidation

[本地存储审计](architecture/local-storage-audit.md) 保留迁移前事实；[Local Storage Contract](architecture/local-storage-contract.md) 是当前共享数据语义和 Schema v2 约束。Android/iOS 生产路径现已把书库、正式进度、书签、目录、非敏感设置与同步状态写入各端 `xlib.db`。TXT 仍在文件系统；Android Token 保持 Keystore 保护，iOS Credential 保持原 Keychain service/account。Backend 继续使用 PostgreSQL。

0.10.0 首次迁移曾在业务 Store 写入前解析 legacy，并在一个 SQLite 事务中提交正式数据、设置、缓存和 migration ledger。0.11.0 已删除这些旧格式读取器；生产路径只使用 SQLite。删书继续在数据库事务中登记正文待删除路径，失败会在下次书库加载重试。

P6 阶段的 Android 167 项单元测试和 iOS Simulator 87 项单元测试全部通过，包含 Schema v1 → v2、无 ledger 不清理、allowlist、清理中断恢复、来源变化和正文缺失保护。当前更完整的测试计数见下文 P8 状态。存储工作没有修改 OpenAPI、Backend PostgreSQL Schema、认证、跨设备规则或 Product Capability。磁盘耗尽、性能与真实跨设备发布验收归入 P8；其中磁盘耗尽自动化和真实双端验收现已完成。

### P7：Legacy Persistence Cleanup

[P7 清理合同](architecture/legacy-persistence-cleanup.md) 现描述已实现状态。P7.1 删除双端旧运行时 Store 回退；数据库打开失败时保留数据并显示不可用状态。P7.2 把本地 Schema 升至 v2，只有存在 0.10.0 migration ledger、fingerprint/数据库/TXT 校验通过时，才按显式 allowlist 幂等删除旧业务数据；Token、Keystore、Keychain、TXT、SQLite 和未知项不在删除范围。

P7.3 已删除一次性 legacy parser、旧模型及 `0.9.0 → 当前工作区` 安装覆盖脚本。0.11.0 draft 清单声明 `contains_legacy_migrator: false`、`minimum_direct_from: 0.10.0`、`required_intermediate: 0.10.0`；未经过 0.10.0 的设备不能直接升级。用户已确认 Android 0.10.0 完成真机测试和发布；P7 阶段的 iOS Simulator/构建/单元测试不表述为真机分发证据，之后 P8 的 iOS 真机发布链与实际渠道版本下限由用户另行确认通过。

此前 0.11.0 存储清理没有新增 Capability 或修改 API；当前 0.13 开发已新增 v2 定位协议及 PostgreSQL 003 迁移，保留原认证和时间裁决语义。0.11.0 尚未由本任务发布、tag 或 push；实际分发版本下限由用户确认已落实。

### P8：系统验收与维护（完成）

[P8 验收记录](architecture/p8-system-validation.md) 是当前系统级证据和缺口清单。`make check-alpha` 现强制运行 tracked-sensitive-data 检查、隔离 PostgreSQL 17、Android 测试/lint/build、iOS 单元/UI 测试；构建号允许递增，版本名和所选发布清单必须保持不变。数据库不可用或版本名被意外修改都会失败。CI 与 release verification 也使用 PostgreSQL 17 owner/受限应用角色，release verification 在生成未签名 Debug artifact 前运行双端测试。

Android 和 iOS 都新增了真实 SQLite `SQLITE_FULL` 故障测试：容量耗尽时整笔写入回滚，原有书籍保持完整。测试暴露并修复了 Android 在 SQLite 自动回滚后再次结束事务会抛异常的问题；Android 数据库初始化失败现在关闭 helper。iOS 容量限制施加在被测连接自身，避免另一连接的 PRAGMA 无效；失败初始化继续由已初始化连接属性的析构路径关闭，避免重复关闭。

本阶段没有修改 OpenAPI、同步数据结构、认证、服务端 PostgreSQL Schema、跨设备规则或 Product Capability。应用日志专项检查未发现正文、邮箱、Token 或真实服务地址输出；Android 数据库打开失败不再把可能含本地路径的异常写入日志。

当前自动验证通过：Backend PostgreSQL 17 为 71/71；Android 为 170/170 且 lint/Debug build 通过；AppleShared 为 3/3；iOS Simulator 为 89/89 单元测试和 11/11 UI 测试。双端阅读字节边界修复后重新运行的完整 Alpha 门禁通过，版本源保持不变。iOS 测试夹具也在删除临时根目录前显式关闭共享 SQLite 测试连接，避免框架把临时文件路径作为连接违规写入日志。

P8 已完成定义范围。用户已确认 0.11.0 Android/iOS 使用同一非生产身份的真机跨设备接续、iOS 物理设备发布链，以及实际应用分发渠道的 0.10.0 最低直升版本验证均已通过；未提供的运行日志明细不补写。用户还确认 iPhone 上此前报错的书籍经 UTF-8 BOM 字节映射修复后已能打开，Android 在 UTF-16 字符边界修复后完成真机测试且无问题。用户明确豁免本轮 Android 真机性能采集，记录和校验器均保留该豁免且不声称 Android 性能结果。

iOS 0.11.0/build 45 已在 iPhone 15 Pro Max/iOS 26.5.2 上完成 Release 自动化性能采集。固定样本覆盖 12 个小/大文件、UTF-8/UTF-16LE/GB18030、冷/缓存打开组合各 5 轮，双向翻页各 30 次，超过 200 条搜索 5 轮及取消，以及 20 本批量导入和确定性中断状态恢复各 5 轮。打开首屏中位数为 77.9–102.9 ms；翻页的接受输入至过渡完成中位数为 378.7/378.6 ms；搜索首结果和完成中位数为 34.2/68.3 ms；批量导入和恢复中位数为 86.5/78.5 ms。批量场景无残留临时文件，恢复测试通过。当前 XCTest 只提供逻辑写入量，不提供读取字节；正式门禁校验真实逻辑写入指标，已有 Activity Monitor 读盘样本仅作探索证据，不以 TXT 大小或请求缓冲伪造读盘值。

`make check-p8-performance-record` 已通过并生成 median/p95 报告；最终 `make check-alpha` 也已通过，包含 Backend/PostgreSQL 17 的 71 项测试、AppleShared 3 项、Android 170 项及 lint/build、iOS 89 项单元测试和 11 项正常 UI 测试，以及契约、安全扫描、发布清单和版本不可变检查。P8 的 18 项真机性能测试为独立 opt-in 套件，普通 Simulator 门禁会明确跳过。自动采集、证据边界和可重复命令见 [P8 验收记录](architecture/p8-system-validation.md)。本阶段没有发布、tag、push、部署或商店上传。

P0–P4 与早期版本的逐轮测试记录由 Git 历史保留；当前验收以本文件上述结果、[重构计划](refactoring-plan.md)及[P8 验收记录](architecture/p8-system-validation.md)为准。

## 0.13 当前开发证据（2026-10-21）

双端多格式实现、测试结果及剩余验收边界见 [0.13 开发验证记录](product/plans/0.13.0-validation.md)。客户端仍为 0.12.0，源码保留未提交；没有发布、部署、tag 或 push。

## 0.13 iOS 真机补充（2026-10-23）

iPhone 15 Pro Max / iOS 26.5.2 已执行 102 项普通单元测试、22 个不同 UI 用例分批回归、六类大文档各三轮 Release 测量（18 轮、180 次导航）及 30 次交替打开千页 PDF/超长章 EPUB；上述断言均有通过记录，修复真机测试构建动态框架加载路径。最终 `make check` 通过，版本 0.12.0 build 78。真机 UI 的初次失败与复核、内存采集及验收边界统一记录在 [iOS 真机验证](product/plans/0.13.0-ios-device-validation.md)，不再将所有多格式真机测试描述为未执行。

同日追加 PDF 手动左右裁边：所有 PDF 全局共用、不保存，重启应用后默认关闭；原 PDF、正式进度与同步坐标保持不变。12 项文档单元与 2 项 UI 真机回归全部通过，含跨书共用、恢复、边缘对齐及原有 PDF 流程；`make check` 通过。当前版本 0.12.0 build 86，未提交或发布；详细证据见上述真机记录的裁边追加章节。

产品总览和能力文档中的“PDF/EPUB 尚未实现”“v2 同步待实施”已按代码及已有服务互操作证据纠正。复杂真实样本、低端设备、完整系统内存与性能预算仍有验收边界；该历史轮开发版本为 0.12.0，当前组件版本见上表，未因此发布。

## 0.13 双端功能补齐核对（2026-10-23）

[功能完成清单](product/plans/0.13.0-client-completion-review.md) 以代码、未提交修改及现有测量区分功能、性能和验收。初次静态核对为双端 0.12.0 build 86；随后按用户要求修复 iOS PDF 页内搜索起点与书首搜索回绕条件，CAP-SEARCH 恢复 done，新增真机自动化与检查结果见 [iOS 搜索补齐记录](product/plans/0.13.0-ios-search-completion.md)。版本名仍为 0.12.0，build 以源码为准。Android 重点仍为千页 PDF 全扫描约 6.44 s 及新格式代表性真机覆盖；iOS 重点仍为超长章首次打开/定位、PDF 内存及复杂设备样本。未将裁边或批量导入自动传播为其他端的强制需求，未发布或部署。
