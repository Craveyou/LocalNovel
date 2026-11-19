# 产品决策

重要取舍使用稳定编号，固定结构为 Context、Decision、Reason、Consequences。记录状态，区分已接受决定与待决问题；candidate 升格、拆分/合并或明确平台不支持时留下理由。日常开发过程不写入此目录。

- [0001 能力初始化与待决差异](0001-capability-baseline-and-open-questions.md)。
- [0002 最近阅读时间优先与当前位置提示](0002-latest-reading-time-wins.md)：用户已确认。
- [0003 阅读前比较定位与正式阅读边界](0003-pre-reading-progress-comparison.md)：用户已确认，含离线阅读及恢复后先比较再上传。
- [0004 首次手动开启，后续有效配置自动应用](0004-sync-configuration-auto-apply.md)：用户已确认。
- [0005 只上传正在阅读的书籍](0005-sync-only-current-reading-book.md)：用户已确认，离线阅读结束后不补传。
- [0006 书内搜索不区分大小写](0006-search-case-insensitive.md)：用户已确认。
- [0007 书内搜索不重叠命中](0007-search-non-overlapping-matches.md)：用户已确认。
- [0008 同一本书同一位置只保留一个书签](0008-bookmark-position-uniqueness.md)：用户已确认。
- [0009 支持单独删除书签](0009-delete-individual-bookmark.md)：用户已确认。
- [0010 云端进度只按单本书删除](0010-delete-cloud-progress-per-book.md)：用户已确认，能力升为 active。
- [0011 当前产品不提供同步身份删除](0011-no-sync-identity-deletion.md)：用户已确认，旧接口已移除。
- [0012 搜索分批加载，200 条不是总上限](0012-search-results-in-batches.md)：用户已确认。
- [0013 搜索到书末后由用户选择从开头继续](0013-search-wrap-with-user-choice.md)：用户已确认。
- [0014 搜索关键词按用户感知字符计数](0014-search-query-character-count.md)：用户已确认，去首尾空白后 2–32 个字符。
- [0015 强制经过 SQLite 迁移基线后再升级](0015-mandatory-sqlite-migration-baseline.md)：用户已确认 0.10.0 为强制中间版本，未来不长期支持 0.9.0 直升最新版。
- [0016 多格式阅读与渐进式交付](0016-multi-format-reading-scope.md)：用户确认 PDF/EPUB、Android 先行且验证后实施 iOS；0.13.0 范围进一步由 0017 明确，兼容子集仍需验证。

已有 [docs/DECISIONS.md](../../DECISIONS.md) 的 D-001～D-008 保留原编号和历史，不复制成新决策。发现过期或冲突时相互链接，不通过删掉旧记录掩盖变化。
- [0017 多格式 0.13.0 范围与复制升格](0017-multi-format-release-scope.md)：先 PDF，密码输入与搜索/书签/复制/进度同步纳入；复制升为 active Shared Optional，协议待协同实施。
- [0018 电子书原 0.14 分批方案](0018-ebook-format-batches.md)：保留格式范围与能力划分；当前 0.14.1 的并行顺序、公共归属及 TXT 界面基线以 0019 为准。
- [0019 双端并行与 TXT 界面基线](0019-parallel-clients-txt-ui-baseline.md)：当前目标 0.14.1；同批双端并行，所有公共部分由 iOS 负责，界面/操作/按钮遵循本端 TXT 阅读器；取代 0018 的原串行安排。
- [0020 功能优先、真机联合验收后置](0020-defer-device-validation.md)：用户确认当前无法连接 iPhone；需要设备的性能/压力/样本留到全格式功能后统一验收，不再阻塞 Kindle 开发；基本安全/功能测试不后置。
