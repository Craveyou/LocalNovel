# 跨端契约与行为样例

本目录是 P1 的唯一合成样例源，不含真实账户、书籍正文或凭据。样例是已确认能力与现行 API 的可执行验收输入，不是新的需求来源。

| 文件 | 用途 | 消费方 |
|---|---|---|
| progress-behavior.json | 较新回读、旧远端、同时间、同设备、提示阈值、未知时间与安全整数边界 | Android/iOS 验证是否提示；Backend 验证同一对进度的时间裁决 |
| arbitration.json | 同时间设备排序、幂等、未来时间调整边界 | Backend；客户端不承担服务端裁决，明确不适用 |
| wire.json | 两类请求、成功响应、设备 null 字段、错误信封；位置接近 JS 安全整数上限、version 超出该上限仍为字符串 | OpenAPI 校验、Backend 输入/路由、Android 实际 HTTP、iOS Codable 与实际 HTTP |
| invalid-wire.json | 缺失字段、null、类型错误、负数、非法哈希、空数组、额外请求字段、非法决定 | OpenAPI；其中上传请求另经 Backend 实际 Zod Schema 拒绝 |
| comic-locators.json | 第一批 CBZ/CBR locator v1 的范围、哈希、半上取整及错误输入；独立于 documents 下的漫画排序样本 | Backend Schema、OpenAPI 及真实 PostgreSQL 约束测试；供双端直接消费 |
| documents/comic-basic.cbz / comic-basic.json | 24 页原创合成 PNG，含自然顺序 index 10 的长图；配套原文件/页面哈希、尺寸和预期页序 | iOS/Android 导入、阅读、UI 和真机测试的共同输入，不是 RAR 或性能验收证据 |
| documents/comic-basic-rar4.cbr / comic-basic-rar4.json | 真实 RAR4 stored、非固实、单卷、无加密，复用 CBZ 的 24 张 PNG 与页序 | CBR 导入/图片读取正例；不覆盖压缩方法或固实字典 |
| documents/comic-basic-rar5.cbr / comic-basic-rar5.json | 真实 RAR5 stored、非固实、单卷、无加密，复用相同 PNG 与页序 | CBR 导入/图片读取正例；不代表完整 RAR5 或 Android ABI 验收 |

Android 通过 Gradle test resources 指向此目录；iOS 仅在 XCTest target 复制本目录为测试 bundle 资源；Backend 直接读取源文件。不手工维护平台副本，不打包进正式应用。资源缺失或解析失败必须失败，不能跳过。

## 执行

- `ruby scripts/check-contract.rb`：路由覆盖。
- `ruby scripts/check-contract-fixtures.rb`：当前 OpenAPI Schema 样例与反例验证。
- `make check`：以上检查、Backend/Android 测试及构建；iOS 在此入口仅构建。
- iOS 执行 `XLibReaderTests/ContractFixturesTests`，CI 的完整 iOS 测试也包含它。

后端路由测试使用服务替身，验证真实路由的请求解析和响应信封，不证明数据库 SQL/事务符合契约；专用 PostgreSQL 集成测试另行执行。Android 用本机临时端口，通过测试范围的静态 mock 放行该地址；生产 HTTPS 校验不变。iOS 使用 URLProtocol 截获所有测试请求，不访问外部服务。

漫画定位夹具以 `base` 合并每个 `validOverrides` / `invalidOverrides` 的 `overrides` 得到完整 locator；`rounding` 替换 base.y，expected 为六位十进制半上取整结果。`schemaInvalid: false` 表示跨字段规则（page < pageCount），由 Backend/客户端业务校验而不是 OpenAPI 3.0 静态 Schema 表达。夹具只含合成不透明哈希，不证明页序或原包内容；不替代客户端根据本地清单核对 pageKey。`scripts/test-backend-postgres.sh` 使用临时 PG17 专用库执行 003→004 旧数据保留、漫画约束和冲突/回滚测试；默认 Backend 测试无专用库时跳过 PG 集成项。

`contract-schema.rb` 是仅供测试使用的受限 OpenAPI 3.0 Schema 校验器，覆盖当前使用的 `$ref`、allOf、类型、required、additionalProperties:false、枚举、数值/长度/数组边界、pattern、nullable、int64/uuid/email 格式。新增未知断言或格式会失败，需扩展校验器或迁移至完整工具后才能通过。email 格式仅作基本结构校验，完整输入规则仍由 Zod 测试负责；它不声称是通用 OpenAPI 验证器。

## 漫画原包夹具生成与复验

`python3 scripts/generate-comic-fixtures.py` 生成 `documents/comic-basic.cbz`、`comic-basic-rar4.cbr`、`comic-basic-rar5.cbr` 和各自同名 JSON，共六份产物；`--check` 不写文件，逐字节比对全部产物；`--self-test` 在内存验证确定性、PNG 解码/CRC、24 张不同图片、长图位置、RAR 头部/数据 CRC 与负例结构。仅依赖 Python 标准库，无字体、图像库、网络或第三方图片；PNG 使用脚本固定的 Huffman/run-length DEFLATE，ZIP 使用固定时间戳与 stored 条目，RAR 使用显式最小测试编码器，避免运行时压缩器版本造成字节漂移。生成图片/归档的原创来源和使用许可同时放在各包的 README.txt 与外部 JSON 中。既有 CBZ/JSON 字节保持不变。

正例固定恰好 24 页：`pages/1.png` 至 `pages/24.png`，全部实际可解码 PNG，600×800；第 11 页（零基 page 10，`pages/11.png`）为 600×3600 长图，用于 `y=0.234567` 页内恢复。ZIP 物理页序刻意为 24→1；预期阅读序为自然数值 1→24，不按物理或字符串字典序。图像绘有大页码、页编号位条、不同配色和几何图案；长图另有分区编号，不依赖 OCR 或字体。普通说明文件 README.txt 不计入页面数。

需要负例时，测试先建立专用临时目录，再运行 `python3 scripts/generate-comic-fixtures.py --output-dir <临时正例目录> --negative-dir <临时负例目录>`；生成 9 个独立归档和 negative-manifest.json，不把坏归档混入 UI 正例或提交至 documents。涵盖父路径/反斜线、NFC 重名、有效但不支持的 GIF、无页面、链接、坏图片、ZIP CRC 损坏和截断。生成器不解包这些路径；真实拒绝逻辑仍由各端/native 测试执行，生成器自测不声称应用已拒绝所有负例。不生成加密/分卷/RAR 冒牌样本，也不修改另行负责的 comic-order-v1.json。

UI/物理设备测试应复制/读取同一受控 CBZ；现有 iOS 测试通过 bundle 子目录 `fixtures/documents` 查找 `comic-basic.cbz`。本轮只提供数据，不修改客户端、bundle 配置或执行设备测试；具体执行结果由各端报告。

### RAR4/RAR5 stored 正例与冻结身份

两份 `.cbr` 是真实 RAR 签名/头部/数据/结束块，不是改后缀 ZIP；都含 24 张逐字节等同 CBZ 的原始 PNG，物理顺序 24→1，另有不计入页面的 README.txt。相同自然页序意味着相同 pageKey/manifestHash，但原包字节不同，必须使用各自 JSON 的 bookHash/fileSize，不得因为图片相同而合并同步身份。长图仍为 `pages/11.png`、零基 index 10、600×3600，其他页 600×800。

| 原包 | bytes | SHA-256 |
|---|---:|---|
| comic-basic-rar4.cbr | 601499 | `9f8665cabe1a6a9fe11f4673f06d282e0db80d7d56ce5cc4bfd5d39dd91d05c4` |
| comic-basic-rar5.cbr | 601294 | `f072d818b99e4ba61d6eabde7c133088c7ca8e619e01d0b2a28cb1212dacba11` |

编码依据为 RAR 作者的 [RAR 4.00 Technical information（Debian 原文镜像）](https://sources.debian.org/src/rar/2:4.0.b3-1/technote.txt/) 和 [RARLAB RAR5 格式技术说明](https://www.rarlab.com/technote.htm)。RAR4 使用方法 0x30、UTF-8 名称、Unix 普通文件属性、固定 DOS 时间，头 CRC 为标准 CRC32 低 16 位；RAR5 使用方法 0、非固实标志、UTF-8 名称、Unix 属性、不带时间，头 CRC32 覆盖编码长度及头字段。两者每个文件均带标准数据 CRC32。脚本只实现该确定性 stored 子集，没有复制 RAR/UnRAR 实现，没有外部编码二进制或新增依赖/许可变更，也没有运行时联网。

`--self-test` 为 6/6 通过，包含独立结构遍历、每个头/文件数据 CRC、损坏头/数据和截断拒绝、PNG 逐页解码及与 CBZ 字节一致。Python 3.14.5 和系统 3.9.6 的 `--check` 均逐字节通过。产物已由 iOS 端到端导入/解码/书签/重开回归消费，真实 HTTPS/PG 同步也覆盖三种原包；实际结果及未完成边界见 [实施记录](../../docs/product/plans/0.14.1-comic-implementation.md)。不把单端结果当作 Android/iOS 联合验收。

另以临时 macOS 命令行验证器链接已有 AppleShared 静态库，直接调用现有 `ComicArchive`：两包各扫描 25 个普通文件（24 PNG + README），`visitFiles` 将所有 PNG 与 CBZ 逐字节比对，并以 ImageIO 实际解码全部 48 张图像、核对尺寸；各包首/末/长图读取及重新打开后读取均通过。验证器和模块缓存仅位于专用临时目录，未修改客户端或原生库。系统 `file` 分别识别为 RAR v4 / v5；这不是新一轮 iOS 导入/UI 或 Android 实测。

**覆盖限制：只验证 stored、非固实、单卷、无加密图像原包；不覆盖压缩方法、固实字典、RAR4 固实、分卷、加密、Unicode 名称边界、大包/恶意包或性能。** 这些夹具不替代 native agent 的 portable RAR4 修正与 Android NDK/ABI/设备验收，不解除第一批联合验收门槛。夹具字节已冻结供客户端回归；本次不修改主 agent 所有的实现记录。

### RAR4 compressed-solid 正例

新增 `documents/comic-basic-rar4-solid.cbr` 和同名 JSON：19,059 bytes，SHA-256
`3d12d67d112b8bdaf98eb1e144011e34e59ccd3ba4143c936897e07424a79adb`。
由独立开发工具 RAR 6.24 以 `-ma4 -s -m5 -mt1 -ts-` 压缩同一套原创 24 PNG 与 README；
不是改扩展名、stored 条目或只改 solid 标志。原工具默认反斜杠路径，仅将 ASCII 路径字段
规范为 `/` 并重算头 CRC；压缩数据、文件 CRC 和跨文件固实依赖不变。
页序、逐页内容 SHA-256 和 manifestHash 引用 `comic-basic.json`，原包身份独立。
生成器 `scripts/generate-rar4-solid-fixture.py --rar-tool /absolute/RAR-6.24/rar`
两次生成逐字节相同。工具仅用于开发期试用生成，不入库、不随应用分发、正常检查不依赖它；
其下载包 SHA-256 为 `dabe335834fb5f0fc236f03ba0d12c19fad7243cc56b980db61201ff94d84795`，
官方来源 https://www.rarlab.com/rar/rarmacos-arm-624.tar.gz。
普通测试直接消费固定资产。共享测试覆盖逆序读取全部图片、顺序访问、重开、损坏/取消及并发；
iOS 导入/书签/重开与前后各 20 页 UI 用例已扩展消费此资产，具体结果见实施记录。
此夹具补充而非替代上述 stored 限制，不表示完整算法/JPEG/恶意语料/真机或双端验收。

## 已知差异与适用边界

### Kindle 原包及规范向量

`documents/kindle-*` 是可完整阅读的原创 CC0 合成出版物，覆盖 MOBI6、PalmDOC/AZW、HUFF/CDIC、KF8/AZW3、混合和长正文，不是只有头部的占位文件。每个原包对应 `.json` 保存原始 SHA-256/fileSize、选择模式、canonicalText/textHash、章节/目录/源跨度映射。混合固定选 KF8，损坏不回落 MOBI6。

生成入口 `node scripts/generate-kindle-fixtures.mjs`，源码及自制 PNG/CRC 在 `packages/kindle-core/test/fixtures.mjs`；固定解码源、MIT 许可和宿主边界见包 README。`kindle-locators.json` 提供正反定位向量，由 Swift、Backend 和 OpenAPI 测试直接消费；规范见 [kindle-text-v1](../../docs/architecture/kindle-text-v1.md)。这些向量及有界变异不是出版社全集或真机压力证据，Android 宿主需另行复验同源结果。

- OpenAPI 的 fileSize/offset 标为 int64，但尚未通过 maximum 表达服务端 JS 安全整数上限；offset <= fileSize、bookKey 不重复也未用 Schema 表达。Backend 测试单独验证这些业务约束。本阶段不改变协议或用较弱 Schema 覆盖服务端规则。
- 旧 Android `parseRemote` 的 20 字符来源设备名称限制已在 0.13 本端修复；登记允许 80，不能通过缩窄公共产品规则恢复该限制。最新证据以客户端交付记录为准。
- Swift Codable 与 Android 手动解析不是完整 OpenAPI 验证器；不要求客户端拒绝所有 Schema 反例。正例必须兼容，字段错误的 API 防线由服务端负责；反例不被假装成三端完全相同的解析策略。
- 同时间服务端裁决不等于客户端一定上传或提示；Android 的新鲜度与重复提示拦截、iOS 会话状态门控在各端测试中覆盖。只有适用行为使用共同断言。
- P0 的完整会话/生命周期测试继续保留；本目录不取代 UI、数据库或真实跨设备验收。
