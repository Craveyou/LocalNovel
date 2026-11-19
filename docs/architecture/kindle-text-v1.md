# Kindle 规范正文参考版本 v1

2026-10-25 实现版本。对应 `format=kindle / version=1 / profile=kindle-text-v1`，不使用 EPUB 定位。参考源码为 `packages/kindle-core`；六原包参考输出已通过 Node、Apple JavaScriptCore、Android 宿主、两端 DOM/选区及 Backend PostgreSQL 验证，实际 Android↔iOS 五阶段接续见 [联合记录](../product/plans/0.14.1-kindle-cross-client-validation.md)。这些是支持子集内的功能证据，不是完整真机/G2/G3 通过声明。采用本 profile 后不得原地改变既有正文含义；行为变化必须使用新 profile 和显式迁移。

## 原文件与内容选择

- 身份始终为原始完整文件的 SHA-256 + fileSize。MOBI/AZW/AZW3 只是输入别名；出版模式为 mobi6、kf8 或 mixed-kf8，持久化 format 统一为 kindle。应用副本保留原始字节。
- 支持 BOOKMOBI Palm 单记录表、MOBI 6/7/8、UTF-8 或 Windows-1252、未压缩/PalmDOC/HUFF-CDIC。按实际记录表和头识别，不依赖文件名。
- 混合出版物按 EXTH 121 选择其 KF8 头，核对前一记录 BOUNDARY；KF8 失败不回退旧正文。DRM、KFX、Print Replica、固定版式、未知编码/压缩方式和损坏结构明确拒绝。
- MOBI6 按 mbp:pagebreak 划分单元，filepos 使用选定正文的字节位置建立锚点；KF8 按 skeleton/fragment 索引重建出版顺序。NCX、guide TOC 及内部位置必须映射到实际正文；失效链接不按百分比或章首猜位置。

## 唯一正文算法

1. 使用有界的自有 HTML tokenizer/树，不依赖浏览器修复后的 innerText；属性名/标签名转 ASCII 小写，属性实体解码，重复属性取首个。普通文本和实体由同一输出过程生成规范文本、净化 HTML 和映射。
2. 排除 head、script、style、iframe、object、embed、form、input、button、audio、video、noscript、template、svg、math 子树；排除 hidden 属性或内联 display:none / visibility:hidden。作者 CSS 不参与正文真值；不执行活动内容、不加载远端图片/字体/CSS。
3. HTML 命名实体取共享 `entities.js` 表，数字实体按同一解码器处理；正文保留原 Unicode，不做 NFC/NFKC。UTF-8 非法序列拒绝；Windows-1252 采用固定 WHATWG 字节映射。
4. CRLF/CR 归一为 LF。普通文本只折叠 ASCII TAB/LF/FF/CR/SPACE 连续串为一个空格；首尾的待定空格不输出。NBSP 等其他 Unicode 空白保持原值。
5. p/div/section/article/header/footer/main/nav/aside/h1–h6/li/ul/ol/blockquote/pre/table/tr/hr 是块边界；br 为断行。边界采用待定 LF：后续确有内容时才输出，已有 LF 不再重复，不额外增加尾 LF。pre 内容保留空白，仅规范换行；它本身仍有块边界。
6. 每个可见 img 输出一个 U+FFFC。有效内置 PNG/JPEG/GIF 使用受控本地资源 ID；没有本地资源的远端图片不联网，保留占位。复制删除 U+FFFC，搜索以同长度空格替代，其他字符的 UTF-16 索引不变。
7. 每个内容单元之间插入恰好一个 LF。全书 `canonicalText = chapters.map(text).join("\n")`；`textHash = lowercaseHex(SHA256(UTF8(canonicalText)))`，没有额外编码 BOM 或终结符。

`coverResource` 优先采用有效的出版物内置封面，否则取首张可用内置图片，无图则为 null；不把独立封面额外插入规范正文。iOS 在后台生成最长边 192 像素的可重建缩略图，缓存最多 8 MiB / 64 项，缓存操作不写正式阅读位置。

## 映射与显示

每个章节带 resource、textStart、text、html、sourceHTML、anchors 和 maps。sourceHTML 是**被选定并重建的正文 HTML**（包含为 filepos 定位生成的空锚点），不是原始压缩文件字节坐标。原文件身份和正文映射不混用。

maps 的 textStart/textEnd 为章节内半开 UTF-16 范围；sourceStart/sourceEnd 为 sourceHTML 内半开 UTF-16 范围。等长 text 段可逐 code unit 双向映射；实体、折叠空白、图片使用区间对应，不能伪造精确的一对一源位置；合成 separator 的源位置为 -1。被隐藏/删除的源内容没有正文映射。Apple `sourceRange` / `canonicalRange` 明确返回这些区间，夹具保存全部跨度供其他宿主复验。

输出 HTML 中的文本节点拼接必须逐字等于章节 text；图片旁用零字号 U+FFFC 文本节点保留坐标。加载后先验证 DOM 文本一致，失败不保存/上传目标位置。内置链接经本地 scheme 访问；http(s) 链接只在用户确认后交给系统浏览器。字体/字号/行距/主题由本端阅读器控制，作者脚本和样式不会覆盖这一真值。

## 定位与存储

`textOffset` 为全书 UTF-16 偏移，0 ≤ offset ≤ textLength，1 ≤ length ≤ 2147483647；客户端还要求不切断代理对或组合字素。章节由 textStart 二分/顺序映射确定，不把章节编号或屏幕页码当作第二权威位置。

进度为 offset/length。书签键为 `kindle:1:kindle-text-v1:<textHash>:<textOffset>`。后端不持有正文，严格校验字段/范围，并在时间裁决前拒绝已有状态的 format/version/profile/textHash/textLength 不一致。客户端恢复还核对原文件身份、实际文本哈希/长度/边界。重排、选区、临时预览、导入、恢复不制造阅读时间；云端接受保留其时间。

iOS SQLite v5 扩展 typed text_hash/profile/text_offset/text_length，旧位置/书签键和全部旧行不变；Backend 新增 005，不改 003/004。只同步位置和正式阅读时间，不上传正文、资源、原文件、书签或选区。

## 有界运行与证据

原文件 ≤1 GiB；每次读取 ≤16 MiB；选定实际展开正文逐记录累计 ≤32 MiB；单条展开 ≤64 KiB；HTML 深度 ≤128、单元节点 ≤200000；每章映射 ≤200000、全书映射 ≤500000；净化显示正文 ≤64 Mi UTF-16 单元；全轮复杂度 ≤10000000 步。HUFF 字典/递归、索引记录数、变长整数、尾随长度和 NCX 层次均有界，并协作取消。图片先校验尺寸（≤1 亿像素）和有界缩略解码，再交给显示组件。宿主必须使用独占 VM，不把活动解析器并发共享给多本书。

导航条目、内部目标及正文单元分别不超过 10000；KF8 片段重建累计复制预算 128 MiB，避免小索引导致反复复制大正文。字节索引扫描按 8192 字节转换，不创建按整书每字节一项的 JS 数组；MOBI6 目标按单调有序游标分配到内容单元。原文件状态通过实际文件属性读取，不能复用 URL 的缓存大小/修改时间。

这些是拒绝异常输入的硬限额，不是已测得的设备内存预算。iOS 本轮未连接真机，WebKit 峰值、实际长书/多图和低内存压力仍按 0020 后置；不能用合成小样本声称支持所有出版社变体。

当前实现随机读取原包记录，但会在硬限额内保留所选展开正文、规范文本及净化 HTML；不是整书低内存流式排版，不以读接口随机访问推导设备内存预算。

可重建夹具：`node scripts/generate-kindle-fixtures.mjs`；测试：`make test-kindle-core`、`make test-apple-shared`、`make test-ios`、`make test-backend-postgres`、`make test-kindle-ios-interop`。实际结果及失败修复历史见 [实施记录](../product/plans/0.14.1-kindle-implementation.md)。
