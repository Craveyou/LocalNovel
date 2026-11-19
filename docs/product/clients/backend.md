# Backend Implementation

## Role

同步能力的服务提供方，不承担终端阅读界面。源码位于 [services/backend](../../../services/backend/)。

## Implemented Capabilities

CAP-SYNC-IDENTITY、CAP-PROGRESS-SYNC、CAP-CLOUD-DATA-CONTROL 的服务端职责已有实现。单书删除路由及传输契约已替换旧全量删除与身份删除；当前源码状态不代表生产已部署。见 [矩阵](../matrix/capability-matrix.md)。

## Partial Capabilities

暂无额外服务范围缺口；隔离 PostgreSQL 17 集成测试已通过，指定双端真机接续由用户确认通过，证据边界见 [P8 验收记录](../../architecture/p8-system-validation.md)。服务不能代替客户端验证阅读阶段和删除后的本次会话暂停。

## Planned Capabilities

0.14.1 的 CAP-PROGRESS-SYNC / CAP-CLOUD-DATA-CONTROL 格式扩展 planned：由 iOS agent 统一负责 Backend、API/OpenAPI、PostgreSQL 迁移和共同测试，与双端客户端开发同期推进；为 CBZ/CBR、无 DRM Kindle 的类型化进度提供校验、读取、派生进度、兼容冲突和单书删除，保持 PostgreSQL 与现有认证/裁决规则。拟议位置与实施依赖见 [技术设计](../../architecture/0.14.1-ebook-formats.md)；现行 OpenAPI 尚不接受新定位，Backend 不承担解包、正文转换或 OCR。

更强身份认证是方向，方案未定，不据此创建密码/验证码能力。

## Unsupported Capabilities

当前服务不提供本地书库、正文阅读、书内搜索、目录、书签、阅读偏好或自动翻页。不提供身份删除和全量进度清空接口。

## Client-specific Features

没有终端专属功能；健康检查、指标、限流、备份与恢复属于服务运维。

## Implementation Notes

TypeScript / Fastify / PostgreSQL；事务、用户行锁、条件更新和凭据加密属实现细节。[OpenAPI](../../../contracts/openapi.yaml) 是机器契约，[API](../../API.md) 是集中说明；部署步骤仅维护在 [服务 README](../../../services/backend/README.md)。Alpha 邮箱恢复固定 Token 风险仍存在。
