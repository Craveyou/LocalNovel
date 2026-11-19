# Alpha 范围与退出标准

## 范围

当前需求目标为 [0.13.0](product/plans/0.13.0.md)，包括先 PDF 后 EPUB、PDF 密码输入、两种格式搜索/书签/复制/进度同步与现有 iOS 交互验收。开发期间 Android/iOS 继续使用 0.12.0，默认检查使用 [0.12.0 draft](../releases/0.12.0.yaml)；各客户端完成对应需求并验收后才升级为 0.13.0，再建立准确的目标版本清单。build 以源码和本次构建为准，Backend 保持 0.10.0、OpenAPI 保持现有 v1，多格式同步的协议与 Backend PostgreSQL 扩展已列为交付依赖，实施前协同评审；当前实现尚未修改。0.10.0 强制迁移基线与 migrator 退役边界继续有效。macOS 无应用目标，不属于本次交付范围。

## 必须通过

- OpenAPI 文件可解析，已声明的所有 `/v1` 路由与后端实现一致。
- Backend lint、typecheck、unit test 和 build 通过。
- Apple 共享包测试通过。
- Android unit test、lint 和 Debug build 通过；构建可递增 `versionCode`，但未显式传入不同 `VERSION` 时不修改版本名。
- iOS unit/UI test 和 Simulator Debug build 通过；构建可递增 build 号，但未显式传入不同 `VERSION` 时不修改 `MARKETING_VERSION`。
- 发布清单中的组件版本与源码一致。
- tracked-sensitive-data 检查通过；仓库不包含 `.env`、Token、签名密钥、keystore、真实数据库凭据或生产域名。
- 隔离 PostgreSQL 17 集成测试以 owner 执行 migration、以受限应用角色执行服务操作并全部通过。
- 整个 Alpha 检查前后的组件版本名、Info.plist 与所选发布清单保持一致；客户端 build 号可按规则递增。最终发布前更新清单快照，再运行严格的 release-check。

`make check-alpha` 自动创建只绑定本机 Unix socket 的临时 PostgreSQL 17 集群。PostgreSQL 17 或测试所需工具不可用时检查必须失败，不能跳过，也不能使用生产数据库代替。

## 人工验收

Android 与 iOS 至少完成一次：导入大 TXT、连续翻页、退出恢复、搜索跳转、目录跳转、书签、设置切换、离线阅读、开启同步、跨设备进度比较和破坏性删除确认。

发布前必须关闭 [CURRENT](CURRENT.md) 中对应范围的实现缺口；不能把协议层通过当作客户端能力完成。

真机跨设备接续、iOS 真机发布链、实际分发渠道最低直升版本和量化性能记录不由 Simulator/CI 自动检查代替。既有 P8 范围的用户确认、Android 性能采集豁免与 iOS Release 量化证据仅适用于当时的 0.11.0 验收，见 [P8 System Validation](architecture/p8-system-validation.md)。0.13.0 新格式与交互须按本版本计划补充验收，不沿用历史豁免声称新增能力已经验证。

详细交互清单按平台区分：Android 见 [features/reader.md](features/reader.md)，iOS 见 [features/ios.md](features/ios.md)。Android 与跨端同步目标见 [features/sync-client.md](features/sync-client.md)。
