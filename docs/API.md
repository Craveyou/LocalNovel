# XLib Sync API

0.14.1 的 CBZ/CBR 和 Kindle 定位已扩展到 OpenAPI 和 Backend；2026-10-25 用户确认已部署，iOS 已通过真实服务器验证12个文档样本的同步/删除/恢复，见[线上验证](product/plans/0.14.1-live-backend-validation.md)。本轮发现并在源码修复业务限流被包装成500的问题，修复尚未部署，不能声称线上限流已经通过。Kindle 的参考正文算法、两端宿主与真实隔离 PostgreSQL 的测试见 [实施记录](product/plans/0.14.1-kindle-implementation.md)；此前六原包真正 Android↔iOS 五阶段接续已[通过](product/plans/0.14.1-kindle-cross-client-validation.md)，该临时服务记录不冒充线上双端接续。真机与整版发布验收仍独立保留。

[OpenAPI](../contracts/openapi.yaml) 是当前 HTTP 契约；基础路径 `/v1`。业务定义见 [进度同步](product/capabilities/progress-sync.md)、[同步身份](product/capabilities/sync-identity.md) 和 [单书云端删除](product/capabilities/cloud-data-control.md)。

## 当前接口

| 方法 | 路径 | 语义 |
|---|---|---|
| POST | `/v1/auth/start-sync` | 按邮箱创建/恢复固定 Token，登记或重新启用设备 |
| GET | `/v1/devices` | 当前身份设备列表 |
| DELETE | `/v1/devices/{deviceId}` | 撤销指定设备，不删除身份或进度 |
| GET | `/v1/progress` | 只读拉取当前身份全部云端进度 |
| POST | `/v1/progress/sync` | 裁决 1–100 条候选；当前客户端产品范围只允许上传正在正式阅读的书 |
| DELETE | `/v1/progress/{bookHash}/{fileSize}` | 仅删除当前身份的指定书籍进度；成功或记录已不存在均返回 204 |

除 start-sync 外，以上接口同时要求 `Authorization: Bearer <token>` 与 `X-Device-Id: <uuid>`。Token 放在平台安全存储，不记录、不提交、不使用查询参数传输。Alpha 仅凭规范化邮箱恢复 Token，仍不是强身份认证。

## 阅读进度契约

TXT 继续使用 v1 字节进度；PDF/EPUB/CBZ/CBR/Kindle 使用下文 v2 类型化定位协议。两种协议隔离存储，客户端不把页码或内容锚点伪装成字节 offset。只上传当前活动书的进度，不同步正文、书签、选区或密码。跨端接续和部署状态分别记录，不从 Schema 支持推断客户端已验收。

- 书籍由完整文件 SHA-256 的小写 64 位十六进制哈希与文件大小标识；不上传正文、书名或路径。
- `offset` 是原始字节位置，范围为 0 到 fileSize，fileSize 必须大于 0；显示进度为二者比值。
- `readAtMs` 更新的候选获胜，即使位置更靠前；未来超过服务端时间五分钟时收敛到服务端时间，返回 timeAdjusted。
- 时间相同，设备公开 UUID 稳定字典序较大者获胜；同设备同时间同 offset 为 unchanged。同设备同时间不同 offset 保留既有状态，客户端实际改变位置时必须产生更新的阅读时间。
- 响应包含最终状态及 accepted / server_kept / unchanged。版本只用于相等性判断，不能以大小比较跨删除重建的记录。
- GET 无写入副作用；同步请求字段完整校验后才写入，重复 bookKey 拒绝。大于 100 条返回 413，字段业务校验失败返回 422。

## 单书删除与兼容性

bookHash 必须是小写 64 位十六进制，fileSize 路径参数为无前导零的正十进制整数，最大 9007199254740991。身份从认证获取，不能由路径或请求体覆盖。无效书籍标识返回 422；缺少路径段不匹配路由，绝不退化成全部删除。不需要请求体，兼容客户端发送空 JSON `{}`。

服务端事务内再次检查身份与设备有效性，按 user_id、book_hash、file_size 删除。不会删除其他书籍、身份、设备或任何本地数据。删除不是跨设备永久禁写，其他设备后续合法上传仍可能创建新记录。

旧 `DELETE /v1/progress` 与 `DELETE /v1/account` 已从当前源码及契约移除，调用返回 404；不提供兼容性的全量删除回退。这是删除接口的破坏性变更，已有部署不会因源码修改自动升级。Android/iOS 均已实现单书删除用户入口、删除后本次阅读会话暂停及关闭重开后的比较恢复；指定双端真机流程由用户确认通过，证据边界见 [P8 验收记录](architecture/p8-system-validation.md)。

## 非业务端点与错误

`GET /health` 无需认证，检查 API/数据库可用性。`GET /metrics` 使用独立 METRICS_TOKEN，只供内部监控。错误格式为 error 对象，包含 code、message、retryable、requestId；X-Request-Id 用于排障，不记录凭据或正文。

常见状态：400 格式/设备头错误，401 无效凭据，403 身份或设备不可用，404 资源/路由不存在，413 请求过大，422 校验失败，429 限流，500/503 服务失败。受保护请求认证先于业务字段校验。

部署与数据库操作见 [服务 README](../services/backend/README.md)，实现职责见 [同步服务设计](features/sync-server.md)。

## 契约回归入口

[共享 JSON 样例](../contracts/fixtures/README.md) 由 Backend、Android、iOS 按职责直接消费；`scripts/check-contract-fixtures.rb` 校验当前 OpenAPI Schema 的报文正例与反例，已接入 `make check` 和 CI。字段/行为差异及验证限制在该说明维护。Schema 验证不替代跨字段业务约束、数据库集成或真实跨设备测试。

## 多格式进度 v2（0.13 开发）

- 继续使用现有 v1 身份和设备认证；新增 GET /v2/progress/{bookHash}/{fileSize}、POST /v2/progress/sync、DELETE /v2/progress/{bookHash}/{fileSize}。GET 只读取指定文件，缺失返回 items=[]；POST 接收 1–100 个不重复文件身份，携带 locator 和 readAtMs，不接受正文、标题、密码或书签。完整字段以 OpenAPI 为准。
- PDF/EPUB locator v1 及旧进度公式保持不变；v2 同时接受下述 CBZ/CBR 和 Kindle 定位。服务端从 locator 派生提示用进度。格式、定位版本或 profile 未知、越界、重复身份及多余字段拒绝；客户端必须额外核对源文件和实际页面/正文结构。
- 数据使用 PostgreSQL document_progress，与 TXT reading_progress 隔离；旧 GET /v1/progress 不返回 PDF/EPUB。旧 v1 TXT 读写保持兼容。新旧协议共享身份限额 10000 条及身份锁、时间优先和设备 UID 同时间裁决；超前五分钟的时间仍调整为服务端当前时间。
- 两个版本的单书 DELETE 都按认证身份及 SHA-256+fileSize 删除该文件在协议命名空间中的进度，幂等 204；不删除其他书或本地文件。客户端仍须串行上传/删除，并在删除成功后暂停本次阅读会话的上传。
- 迁移由数据库 owner 执行，API 使用受限角色。003 保持原样，新增 004_comic_progress.sql 扩展漫画约束并保留旧记录；迁移脚本显式授予应用角色 document_progress 的 DML 权限。用户已确认部署，公开 API 的漫画行为已实测；没有访问生产数据库核验迁移记录，跨端和设备验收状态单独记录。

### 第一批漫画 locator v1

CBZ/CBR 共用严格字段：`format`（cbz/cbr）、`version: 1`、`profile: comic-order-v1`、`manifestHash`、`pageKey`、`page`、`pageCount`、`y`。两个哈希均为小写 64 位十六进制。pageCount 为 1–10000 整数，page 为从 0 起且小于 pageCount 的整数；y 为 0–1 的自然顶部纵向锚点，按十进制半上取整到六位小数。服务端写入和读取均规范化 y；不接受路径、页文件名或其他未知字段。

进度为 `(page + 1) / pageCount`，不受 y 影响；单页为 100%，第一页不承诺 0%，不因此制造阅读事件。PDF 仍为 `(page + y) / pageCount`，EPUB 仍为原有 spine/正文公式。

同一 SHA-256+fileSize 的已有状态和候选必须匹配 format/version/profile/manifestHash/pageCount；相同 page 还须匹配 pageKey，不同 page 不要求 pageKey 相同。不匹配时无论阅读时间新旧，返回 422 `VALIDATION_FAILED`，整批回滚；匹配后再按既有时间与设备 UID 裁决。后端不持有页面清单，无法证明不同页 pageKey 的真实对应关系，客户端应用前必须核对本地清单。未知或不可应用的定位保留本地位置和时间，不回退为 PDF/EPUB/TXT。

### Kindle locator v1

严格字段为 `format: kindle`、`version: 1`、`profile: kindle-text-v1`、`textHash`、`textOffset`、`textLength`；不接受屏幕页码、转换文件路径或未知字段。textHash 是规范正文 UTF-8 的 SHA-256 小写 64 位十六进制，textLength 为 1–2147483647 整数 UTF-16 长度，textOffset 为 0–textLength 的整数。服务端提示进度为 `textOffset / textLength`；客户端另行验证实际正文和字素边界。

已有状态和候选必须匹配 format/version/profile/textHash/textLength，不匹配先于时间裁决返回 422，整批回滚；不按百分比猜位置。参考规范及源文跨度映射见 [kindle-text-v1](architecture/kindle-text-v1.md)。MOBI6/KF8/混合模式由同源核心选择，不伪装为 EPUB。

迁移由 owner 执行新增 `005_kindle_progress.sql`，保留 003/004、既有行和受限应用角色权限；API 不使用 owner。已完成隔离库 004→005 与 HTTPS/PG17 回归；用户已确认部署，公开 API 的 Kindle 行为已实测，不据此推断生产迁移记录或部署提交。
