# Mobile Local Storage Contract

0.13 的 TXT/PDF/EPUB SQLite v3 基线见第 7 节；0.14.1 漫画开发扩展的 SQLite v4 基线见第 8 节。Kindle 已进入双端 SQLite v5 typed 存储，见第 9 节；各端迁移和真实接续均有独立测试证据，不以一端结果代验另一端。SQLite/原文件/安全存储边界保持。

状态：P6.1–P6.4 已在当前工作树实现并通过本地自动化验证。本文定义 Android/iOS 共享的数据语义、SQLite 约束和迁移行为；平台实现代码不共享。它不新增 Product Capability，也不修改同步 API、Backend PostgreSQL Schema 或跨设备同步规则。

格式范围：TXT 继续使用原字节 offset；Android/iOS SQLite Schema v3 新增格式和独立的类型化位置、书签表，定义见第 7 节。v1/v2 升级保留 TXT 的 offset、时间、书签、设置和同步状态，不补造阅读时间。PDF 密码仅用于会话内存，搜索及选区仍为临时状态。

## 1. 持久化边界

| 数据 | 唯一持久化边界 | 规则 |
|---|---|---|
| Book、Progress、Bookmark、TOC、Setting、非敏感 SyncState | 客户端 `xlib.db` | 业务代码经 typed Store/Repository 访问，不直接执行 SQL |
| TXT 正文 | 应用私有 `books` / `Books` 目录 | SQLite 只保存相对路径与验证用 metadata |
| Token、Secret、Credential | Android Keystore 保护的现有密文；iOS Keychain | 不写入 SQLite、迁移指纹、日志或测试夹具 |
| 阅读窗口、导入临时文件 | Disposable Cache | 可删除、可重建，不作为业务 source of truth |
| Backend 数据 | PostgreSQL | 不受本 Contract 影响 |

SQLite 开启 foreign keys 和 WAL。Android/iOS 各自使用平台数据库 API；两端不共享 ORM、迁移运行时代码或本地 ID。

## 2. 共享数据语义

- `Book`：客户端本地 ID、展示 metadata、应用管理目录内相对路径、文件大小、修改时间和编码。TXT 文件是正文事实来源。
- `Progress`：每本书一个 byte offset 和可空 `readAtMs`。空值表示未知/未读；百分比只由 offset/fileSize 计算。
- `Bookmark`：本地 ID、book ID、byte offset、可空摘录和创建时间；同一本书同一 offset 唯一。
- `TOC`：可重建快照；document 保存源文件指纹，entry 按 ordinal 排序并使用 byte offset。
- `Setting`：稳定 key 的规范字符串值；typed Repository 负责默认值、解析和归一化，不保存 JSON blob。
- `SyncState`：非敏感同步配置、书籍 hash cache 与按账号隔离的远端进度 cache。Token/credential 不属于 SyncState。
- `PendingFileDeletion`：数据库删除书籍时记录待删相对路径；提交后删除 TXT，失败则在下次书库加载重试。

Android legacy `long` ID 写为十进制字符串；iOS UUID 写为规范小写字符串。它们只在本地有效。跨设备书籍身份继续使用 SHA-256 + fileSize。

## 3. Schema v1

以下 DDL 是共享最小约束。Android 额外使用 `book_preferences` 保存现有单书 `pageMode`；iOS 不建立无业务使用者的对应数据。字段声明可按平台 SQLite API 等价表达。

```sql
CREATE TABLE books (
  local_id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  source_name TEXT NOT NULL,
  author TEXT NOT NULL,
  relative_path TEXT NOT NULL UNIQUE,
  file_size INTEGER NOT NULL CHECK (file_size >= 0),
  source_modified_at_ms INTEGER,
  encoding TEXT NOT NULL
);

CREATE TABLE reading_progress (
  book_id TEXT PRIMARY KEY REFERENCES books(local_id) ON DELETE CASCADE,
  offset_bytes INTEGER NOT NULL CHECK (offset_bytes >= 0),
  read_at_ms INTEGER
);

CREATE TABLE bookmarks (
  local_id TEXT PRIMARY KEY,
  book_id TEXT NOT NULL REFERENCES books(local_id) ON DELETE CASCADE,
  offset_bytes INTEGER NOT NULL CHECK (offset_bytes >= 0),
  excerpt TEXT,
  created_at_ms INTEGER NOT NULL,
  UNIQUE (book_id, offset_bytes)
);

CREATE TABLE toc_documents (
  book_id TEXT PRIMARY KEY REFERENCES books(local_id) ON DELETE CASCADE,
  source_file_size INTEGER NOT NULL,
  source_modified_at_ms INTEGER NOT NULL,
  encoding TEXT,
  generator_schema_version INTEGER NOT NULL
);

CREATE TABLE toc_entries (
  book_id TEXT NOT NULL REFERENCES toc_documents(book_id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL,
  entry_id TEXT,
  title TEXT NOT NULL,
  offset_bytes INTEGER NOT NULL,
  level INTEGER NOT NULL,
  PRIMARY KEY (book_id, ordinal)
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE sync_configuration (
  singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1),
  configured_email TEXT,
  authenticated_email TEXT,
  device_id TEXT,
  device_name TEXT,
  server_url TEXT,
  has_started INTEGER NOT NULL DEFAULT 0 CHECK (has_started IN (0, 1)),
  credential_server_url TEXT,
  active_email TEXT,
  active_device_name TEXT
);

CREATE TABLE book_hash_cache (
  book_id TEXT PRIMARY KEY REFERENCES books(local_id) ON DELETE CASCADE,
  source_file_size INTEGER NOT NULL,
  source_modified_at_ms INTEGER NOT NULL,
  book_hash TEXT NOT NULL
);

CREATE TABLE remote_progress_cache (
  account_scope TEXT NOT NULL,
  book_hash TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  offset_bytes INTEGER NOT NULL,
  read_at_ms INTEGER NOT NULL,
  version TEXT NOT NULL,
  source_device_id TEXT NOT NULL,
  source_device_name TEXT NOT NULL,
  source_platform TEXT NOT NULL,
  fetched_at_ms INTEGER,
  PRIMARY KEY (account_scope, book_hash, file_size)
);

CREATE TABLE pending_file_deletions (
  relative_path TEXT PRIMARY KEY,
  requested_at_ms INTEGER NOT NULL
);

CREATE TABLE legacy_migrations (
  migration_id TEXT PRIMARY KEY,
  source_fingerprint TEXT NOT NULL,
  completed_at_ms INTEGER NOT NULL,
  imported_rows INTEGER NOT NULL
);
```

所有写入把 offset 限制在 `0...fileSize`。缓存表可以重建；`books`、`reading_progress`、`bookmarks`、`settings` 和 `sync_configuration` 是正式数据。删书在同一事务中级联删除 metadata 并写入 `pending_file_deletions`，TXT 删除失败不会留下无法判定的半状态。

## 4. Repository 边界

当前实现以最少边界接入现有代码，不为每张表建立空 Adapter：

- Android `LocalDatabase` 只暴露 typed 方法；`BookStore`、`BookmarkStore`、`TocStore`、`ReadingPreferences`、`BookHashCache`、`RemoteProgressStore`、`SyncServerConfig` 和 `SyncTokenStore` 委托这些方法。生产路径不再把正式业务值写回 SharedPreferences。
- iOS `LocalDatabase` 由 `LibraryStore`、`SettingsStore`、`SyncStateStore` 和 `SyncConfigurationSession` 使用。生产路径不再把正式业务值写回 JSON/UserDefaults。
- Android Token 密文/IV 与 Keystore alias 保持原实现；iOS `SyncCredentialVault` 的 Keychain service/account 与编码保持原实现。
- legacy 构造器与旧读写分支已在 P7.1 删除。数据库不可用时客户端保留磁盘数据并显示启动错误，不创建第二个业务 source of truth。

## 5. 0.10.0 历史迁移合同

1. Schema 创建后、任何业务写入前运行一次迁移。
2. 正式输入先完整解析和校验；正文缺失、路径越界、孤立书签、重复正式键或不可恢复快照使事务失败。
3. Android 从同一 `xlib_reader` SharedPreferences 快照迁移；iOS 优先 `books.json`，失败时只使用可解码的 `books.last-good.json`。
4. `updatedAt == 0` / Unix epoch 迁为 NULL；不得制造当前阅读时间。
5. TOC、hash 与 remote cache 损坏时丢弃该缓存；正式书库、进度、书签和设置不能静默变空。
6. 正式数据、设置、可用缓存和 `legacy_migrations` 在一个事务中提交。失败回滚全部数据库写入。
7. 同一 migration ID + fingerprint 重开直接使用 SQLite，不重复插入；同一 ID 但 fingerprint 改变时拒绝覆盖。
8. 成功后 SQLite 是唯一业务读写源。上述旧格式读取器只存在于已发布的 0.10.0，不再存在于 0.11.0 源码。

迁移指纹排除 Android Token 密文与 IV；凭据正常轮换不应被解释为业务数据源改变。iOS Keychain 从未进入指纹。

## 6. 当前清理与验证

Android `LocalDatabaseTest` 和 iOS `LocalDatabaseTests` 当前覆盖正式 SQLite 读写、Schema v1 → v2、allowlist 清理、中断恢复、来源变化拒绝、正文缺失保护和正文删除重试。旧格式解析测试及安装覆盖脚本已在 P7.3 退役；0.10.0 的历史覆盖结果保留在 [Pre-P7.1 Upgrade Validation](pre-p7-upgrade-validation.md)。两端既有同步测试继续验证存储清理没有改变阅读前比较、时间生成、上传范围、身份隔离和单书云端删除。

0.11.0 只接受 0.10.0 作为最低直接升级来源。存在 0.10.0 migration ledger 的设备会在完整校验后清理 allowlist；校验失败时不删除 legacy，应用也不会回退写入旧格式。TXT、Secure Store、SQLite 与未知项始终保留。具体状态机和永久边界见 [Legacy Persistence Cleanup](legacy-persistence-cleanup.md)。

## 7. 0.13 开发中的多格式定位合同（locator v1 / SQLite v3）

开发客户端版本名为 0.13.0；本节不表示已通过全部设备或跨端验收。

- Android Schema v3 在原 v2 上原子增加 books.format（旧记录默认 txt）、document_positions 和 document_bookmarks；旧 TXT 的 byte offset、时间、书签、目录、设置及同步缓存保持原值。iOS 采用同义扩展，平台本地 ID 不共享。
- 非 TXT 的位置使用独立的规范列（格式、定位版本、页码/页数、归一化页内锚点，或资源路径、spine 序号/数量、正文 UTF-16 偏移/长度）；不写入 offset_bytes，不增加业务 JSON/Preferences 存储。原文件 SHA-256 与 fileSize 绑定位置，文件替换时保留旧记录并拒绝静默套用。
- PDF locator v1 为 format=pdf、version=1、page（0 起）、pageCount（1–100000）、y（从页面顶部开始的 0–1 锚点，六位小数）。对外页码为 page+1，百分比为 (page+y)/pageCount。恢复和单纯缩放不更新时间；主动翻页、跳页及实际平移到不同锚点才产生正式事件。
- EPUB locator v1 为 format=epub、version=1、resource（ZIP 根目录下解码并规范化的安全相对路径）、spineIndex/spineCount、textOffset/textLength。正文锚点为受支持 XHTML body 内文本节点按文档顺序连接后的 UTF-16 偏移，排除 script/style；换行统一 LF，偏移不切开字符。百分比为 (spineIndex+textOffset/textLength)/spineCount，空资源分数为 0。跨端应用前核对本地 resource、spine 和文本长度，禁止按压缩包大小换算。
- 书签唯一键为同书的规范位置：PDF 的 page+y 或 EPUB 的 resource+textOffset；不以百分比或客户端分页判重。搜索命中复用同一定位，搜索预览/选区始终是临时状态。
- 密码仅用于当前打开会话内存；原加密文件保持不变，解密页、文本及索引不进入普通磁盘缓存、日志、SQLite 或同步。密码输入/取消/错误、恢复、重排、原地操作均不生成阅读时间。
- 导入先创建临时副本、验证、重命名，再发布 SQLite 记录；发布失败删除本次应用副本。启动清理未发布的临时文件；文件删除仍使用事务内待删记录及提交后的重试。
- 新格式远端请求使用独立 v2 协议，不混入 TXT v1 缓存。未知格式/版本或无法应用的锚点拒绝，并保留本地位置和时间。

两端迁移均在 SQLite 事务内完成；文件发布失败补偿应用副本，重启清理仅针对应用管理的未引用原文件/导入临时文件。UTF-16 规范正文和坐标夹具位于 `contracts/fixtures/documents`，Java、Swift、Backend 共用。验证边界见 [0.13 记录](../product/plans/0.13.0-validation.md)。

## 8. 0.14.1 第一批开发中的漫画定位（SQLite v4）

- iOS 在初始化且尚未暴露连接时，暂时关闭外键执行，在单一事务内重建 books、document_positions、document_bookmarks 的格式约束；逐列比较旧数据及行数，并执行 foreign_key_check，成功后提交并恢复外键。失败完整回滚，不清空书库或替换数据库。TXT/PDF/EPUB 原坐标与时间不重算，Keychain 不参与迁移。
- 漫画阶段 Android `LocalDatabase` 声明 v4；Kindle 接入中已声明 v5，公共 legacy 清理计划随实际源码记录为 5，不改变删除 allowlist。具体迁移和测试由 Android 本端交付，不以 iOS 测试代签通过。

本节为漫画 v4 基线；iOS 后续 Kindle 升级见第 9 节，不将 Android schema 同步改号。
- books.format 增加 cbz/cbr；漫画坐标使用独立 profile、manifest_hash、page_key、page_index、page_count、page_y 列。在 v4 中 Kindle 的 text_hash 列仅预留为空；iOS v5 的启用规则见第 9 节。
- comic-order-v1 的页序、清单哈希和坐标验证见 [设计](0.14.1-ebook-formats.md)及共享夹具。进度为 (page+1)/pageCount；书签键包含原格式、版本、profile、manifestHash、pageKey 和六位小数 y，不以屏幕缩放位置或百分比判重。
- 原图自然坐标为正式锚点；显示采样、缩放及视口重新布局不制造阅读事件。导入后无阅读时间，真正翻页、跳页或纵向内容移动才产生时间。图片不进入文本搜索/复制，不执行 OCR。
- Backend 使用独立 004 PostgreSQL 迁移扩展既有 v2 进度，不修改已执行的 003。此节描述开发实现，不表示第一批已联合验收；结果与缺口见 [实施记录](../product/plans/0.14.1-comic-implementation.md)。
- iOS 导入对完整临时副本流式验证；TXT 跨块保留编码边界且不转码，所有格式发布原文件及书库记录前再次检查取消。导入可取消，取消与容量不足保留旧书/进度/书签并清理本次副本；容量预检和分块写入保留 16 MiB 余量，最终写入错误仍是权威结果。
- 漫画封面取确定页序的第一页，最长边 192 像素；iOS 内存缓存上限 8 MiB / 64 项，可清空重建。封面、解码缓存和显示偏好都不改变原包身份、正式位置或阅读时间。

## 9. 0.14.1 Kindle（iOS SQLite v5）

- `books.format` 增加 kindle；保留源后缀于 sourceName，不将 AZW 后缀当内容类型。`document_positions` / `document_bookmarks` 使用 `profile='kindle-text-v1'`、`text_hash`、`text_offset`、`text_length`；页码、页数、y、resource、spine 和漫画哈希字段均为 NULL。版本固定 1，哈希小写 64 位，长度/偏移范围由 CHECK 和读取校验同时限制。
- 文本身份与 Unicode/字素边界以 [正文规范](kindle-text-v1.md) 为准。进度为 textOffset/textLength；书签键包含格式、版本、profile、textHash、textOffset。重排、恢复、预览和相同位置操作不制造阅读时间。
- iOS 单一事务重建三表并复制旧 typed 列。来自 v4 时完整保留 profile/manifest_hash/page_key/text_hash，来自 v3 时新列为空；不重新计算旧位置、键、ID、时间、摘录。逐表行数/值与 foreign_key_check 失败则回滚。迁移不修改原书、Keychain、旧 TXT 或 PDF/EPUB/漫画定位语义。
- 公共清理计划仅将 iOS schema 更新至 5；Android 仍为其已实现的 4，不扩大删除 allowlist。Backend 单独使用 PostgreSQL 005，不以 SQLite 版本推断服务已部署。
- 实际迁移、正文/DOM、重开及 HTTPS/PG17 证据见 [实施记录](../product/plans/0.14.1-kindle-implementation.md)，双端六原包同源与真实接续见[联合记录](../product/plans/0.14.1-kindle-cross-client-validation.md)。后置设备预算不由这些功能测试代签。
