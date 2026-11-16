import Foundation
import CoreFoundation
import PDFKit

// MARK: - 正文读取：编码自动检测 + 段落切分
// 支持 txt / md（自动识别 UTF-8 / UTF-16 / GB18030 / Big5）、epub（解包取文字）、pdf（抽取文字）。
// 检测失败时给出明确错误，不静默返回乱码。
//
// 检测顺序与「为什么有的 txt 会乱码」的说明见 TextEncoding.swift 顶部注释。
// 关键点：UTF-16 必须先有 BOM 或明显 NUL 特征才允许尝试，
// 否则 GBK 文件会被它「成功」解成一屏乱码汉字。

enum TextLoader {
    enum TextError: LocalizedError {
        case unreadable(URL)
        case undecodable(URL)
        case pdfWithoutText(URL)
        case epubUnreadable(URL)
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let u):     return "无法读取文件：\(u.lastPathComponent)"
            case .undecodable(let u):    return "无法识别文本编码：\(u.lastPathComponent)（可在阅读器菜单「文本编码」里手动指定）"
            case .pdfWithoutText(let u): return "这个 PDF 没有可选文字（可能是扫描件）：\(u.lastPathComponent)。漫画 PDF 请放进「漫画」分区，会按页显示。"
            case .epubUnreadable(let u): return "无法解析 epub：\(u.lastPathComponent)（文件可能损坏或加密）"
            case .unsupported(let s):    return "不支持的格式：\(s)"
            }
        }
    }

    /// 老中文编码：GB18030（向下兼容 GBK / GB2312）与 Big5
    private static let legacyEncodings: [String.Encoding] = [
        TextEncodingOption.cfEncoding(.GB_18030_2000),
        TextEncodingOption.cfEncoding(.big5)
    ]

    /// 高频汉字：解对时占比高，解错（如 Big5 解 GBK）时几乎不命中。
    /// 用它给候选编码打分，比「猜字节范围」可靠得多。
    private static let commonHanzi: Set<Unicode.Scalar> = Set("""
    的一是了我不人在他有这上们来到时大地为子中你说生国年着就那和要她出也得里后自以会家可下而过天去能对小多然于心学么之都好看起发当没成只如事把还用第样道想作种开美总从无情己面最女但现前些所同日手又行意动方期它头经长儿回位分爱老因很给名法间斯知世什两次使身者被高已亲其进此话常与活正感见明问力理尔点文几定本公特做外孩相西果走将月十实向声车全信重三机工物气每并别真打太新比才便夫再书部水像眼等体却加电主界门利海受听表德少克代员许先口由死安写性马光白或住难望教命花结乐色更拉东神记处让母父应直字场平报友关放至张认接告入笑内英军候民岁往何度山觉路带万男边风解叫任金快原吃妈变通师立象数四失满战远格士音轻目条呢病始达深完今提求清王化空业思切怎非找片钱吗语元喜曾离飞科言干流欢约各即指合反题必该论交终林请医晚制球决传画保读运及则房早院量苦火布品近坐产答星精视五连司奇管类未朋且台夜青北队久乎越观落尽形影红爸百令周吧识步希术留市半热送兴造谈容极随演收首根讲整式取照办强石古华拿计您装似足双转诉米称丽客南领节衣站黑刻统断福城故历惊脸选包紧争另建维绝树系伤示愿持千史谁准联妇纪基买志静诗独复痛消社算义竟确酒需单治卡幸念举仅钟怕共毛句息功官待究跟穿室易游程号居考突皮哪费倒价图具刚脑永歌响商礼细专黄块脚味灵改据般破引食仍存众注笔甚某沉血备习校默务土微娘须试怀料调广苏显赛查密议底列富梦错座参八除跑亮假印设线温虽掉京初养香停际致阳纸李纳验助激够严证帝饭忘趣支春集丈木研班普导顿睡展跳获艺六波察群皇段急庭创区奥器谢弟店否害草排背止组州朝封睛板角况曲馆育忙质河续哥呼若推境遇雨标姐充围案伦护冷警贝雪索剧船险烟依斗值帮汉慢佛肯闻唱沙局伯族低玩资屋击速顾泪洲团圣旁堂兵七露园牛哭旅街劳型烈姑陈莫鱼异抱宝权鲁简态级票怪寻杀律胜份汽右洋范床舞秘午登楼贵吸责例追较职属渐左录丝牙党继托赶章智冲叶胡吉卖坚喝肉遗救修松临藏担戏善卫药悲敢靠村戴词森耳差短祖云规窗散迷油旧适乡架恩投弹铁博雷府压超负勒杂醒洗采毫嘴毕九冰既状乱景席珍童顶派素脱农疑练野按犯拍征坏骨余承置彩灯巨琴免环暗换技翻束增忍餐缺忆判欧层付阵批岛项狗休懂武革良恶恋委拥妙探呀营退摇弄桌熟宣银势奖宫忽套康供优课鸟喊降夏困罪亡鞋健模败伴守挥鲜财孤枪禁恐伙杰迹妹遍盖副坦牌江顺秋菜划授归浪凡预奶雄升编典袋含盛济蒙棋端腿招释介烧误
    """.unicodeScalars)

    /// 整本文本缓存：epub 解包 / pdf 抽文字都不便宜，切章与阅读共用一次结果。
    /// 只留最近 8 本，避免大书库把内存吃满。
    private static let documentCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 8
        return cache
    }()

    /// 纯文本读取（txt / md）
    /// 用 mappedIfSafe：几十 MB 的正文不再整份拷贝进堆，直接映射文件，
    /// 只有解码后生成的 String 占用内存（大文件闪退的重要一环）。
    static func load(_ url: URL, preferred: TextEncodingOption = .auto) throws -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw TextError.unreadable(url)
        }
        if let text = decode(data, preferred: preferred) { return normalize(text) }
        throw TextError.undecodable(url)
    }

    /// 已下载到内存的正文（NAS 远端章节用）：编码检测与本地文件同一套规则
    static func text(from data: Data, preferred: TextEncodingOption = .auto) -> String? {
        guard let decoded = decode(data, preferred: preferred) else { return nil }
        return normalize(decoded)
    }

    /// 按扩展名读取「一本书的全文」：txt / md / epub / pdf
    static func loadDocument(_ url: URL, preferred: TextEncodingOption = .auto) throws -> String {
        let key = cacheKey(url, preferred: preferred)
        if let hit = documentCache.object(forKey: key) { return hit as String }
        let text = try loadDocumentUncached(url, preferred: preferred)
        documentCache.setObject(text as NSString, forKey: key)
        return text
    }

    private static func loadDocumentUncached(_ url: URL, preferred: TextEncodingOption) throws -> String {
        let ext = MediaResolver.fileExtension(url.lastPathComponent)
        switch ext {
        case "epub":
            return try EpubParser.plainText(url: url)
        case "pdf":
            return try loadPDF(url)
        case "txt", "text", "md", "markdown", "":
            return try load(url, preferred: preferred)
        default:
            throw TextError.unsupported(ext)
        }
    }

    /// 缓存 key 必须带上编码：用户手动改编码后要能读到新结果，而不是命中旧缓存
    private static func cacheKey(_ url: URL, preferred: TextEncodingOption) -> NSString {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let stamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        return "\(url.path)|\(stamp)|\(size)|\(preferred.rawValue)" as NSString
    }

    private static func loadPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw TextError.unreadable(url) }
        guard let text = document.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextError.pdfWithoutText(url)
        }
        return normalize(text)
    }

    /// 按区间取正文（章节切片）；区间越界时返回整段可用的部分
    static func substring(_ text: String, range: NSRange) -> String {
        let ns = text as NSString
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        guard safe.length > 0 else { return "" }
        return ns.substring(with: safe)
    }

    // MARK: - 解码

    /// 手动指定优先；指定的解不出来才退回自动，避免整章变空白
    private static func decode(_ data: Data, preferred: TextEncodingOption) -> String? {
        guard !data.isEmpty else { return "" }

        if let enc = preferred.stringEncoding,
           let s = String(data: data, encoding: enc), !s.isEmpty {
            return s
        }
        // 用户手动选 UTF-8 但文件里有少量坏字节：宽松解码，坏字节变问号，至少能读
        if preferred == .utf8 {
            let relaxed = String(decoding: data, as: UTF8.self)
            if !relaxed.isEmpty { return relaxed }
        }

        return decodeAutomatically(data)
    }

    /// 判定编码时只看前 64 KB：中文正文的字节分布在这个长度上已足够稳定
    private static let decodeSampleLimit = 64 * 1024

    /// 在样本上比较 GB18030 / Big5，返回更可读的那个编码。
    /// 判不准（样本几乎全是 ASCII、两种编码得分接近）就返回 nil，
    /// 交给整份文件打分，避免把 Big5 的书错认成 GBK。
    private static func guessLegacyEncoding(in sample: Data) -> String.Encoding? {
        var best: (encoding: String.Encoding, score: Double)?
        var runnerUp = -Double.infinity
        for enc in legacyEncodings {
            guard let s = decodeSample(sample, encoding: enc), !isGarbled(s) else { continue }
            let score = readability(s)
            if score > (best?.score ?? -Double.infinity) {
                runnerUp = best?.score ?? -Double.infinity
                best = (enc, score)
            } else if score > runnerUp {
                runnerUp = score
            }
        }
        guard let best, best.score >= 0.35 else { return nil }
        guard hasCJKContent(sample) else { return nil }
        if runnerUp.isFinite, best.score - runnerUp < 0.08 { return nil }
        return best.encoding
    }

    /// 样本里非 ASCII 字节占比够高才值得相信「简繁判定」
    private static func hasCJKContent(_ sample: Data) -> Bool {
        var nonASCII = 0
        var total = 0
        for byte in sample.prefix(4096) {
            total += 1
            if byte >= 0x80 { nonASCII += 1 }
        }
        guard total > 0 else { return false }
        return Double(nonASCII) / Double(total) > 0.10
    }

    /// 样本末尾可能切在多字节字符中间：回退 1~3 字节再试，避免整体解码失败
    private static func decodeSample(_ sample: Data, encoding: String.Encoding) -> String? {
        for trim in 0..<4 {
            let end = sample.count - trim
            guard end > 3 else { return nil }
            if let s = String(data: sample.prefix(end), encoding: encoding), !s.isEmpty {
                return s
            }
        }
        return nil
    }

    /// 自动检测：BOM → 严格 UTF-8 → 有特征的 UTF-16 → GB18030/Big5 打分 → 系统探测
    private static func decodeAutomatically(_ data: Data) -> String? {
        if let s = decodeByBOM(data) { return s }

        // Foundation 对非法 UTF-8 返回 nil，能过就是对的
        if let s = String(data: data, encoding: .utf8), !isGarbled(s) { return s }

        // 无 BOM 的 UTF-16 必须「长得像」才认：中文 UTF-16 不含 NUL 字节，
        // 只有英文/混合文本会有大量 0x00，此时才值得试
        if looksLikeBOMLessUTF16(data),
           let s = String(data: data, encoding: .utf16), !isGarbled(s) {
            return s
        }

        var best: (text: String, score: Double)?
        // 大文件先在小样本上判编码，再整份解一次。
        // 原来把 GB18030 / Big5 各解一份全文再比对，一本 50 MB 的书会同时持有
        // 两三个完整 String（每个约 100 MB），还没画出一行就被系统杀掉。
        if data.count > decodeSampleLimit {
            if let encoding = guessLegacyEncoding(in: data.prefix(decodeSampleLimit)),
               let s = String(data: data, encoding: encoding), !s.isEmpty, !isGarbled(s) {
                return s
            }
        }
        for enc in legacyEncodings {
            guard let s = String(data: data, encoding: enc), !s.isEmpty else { continue }
            if isGarbled(s) { continue }
            let score = readability(s)
            if score > (best?.score ?? -Double.infinity) { best = (s, score) }
        }
        if let best, best.score >= 0.35 { return best.text }

        // Shift_JIS / EUC-KR 等交给系统探测（ICU）兜底
        if let s = detectByFoundation(data), !isGarbled(s) { return s }

        return best?.text
    }

    /// 文件自己声明的编码，最可信
    private static func decodeByBOM(_ data: Data) -> String? {
        if data.count >= 3, data[data.startIndex] == 0xEF,
           data[data.startIndex + 1] == 0xBB, data[data.startIndex + 2] == 0xBF {
            return String(data: Data(data.dropFirst(3)), encoding: .utf8)
        }
        if data.count >= 2, data[data.startIndex] == 0xFF, data[data.startIndex + 1] == 0xFE {
            return String(data: Data(data.dropFirst(2)), encoding: .utf16LittleEndian)
        }
        if data.count >= 2, data[data.startIndex] == 0xFE, data[data.startIndex + 1] == 0xFF {
            return String(data: Data(data.dropFirst(2)), encoding: .utf16BigEndian)
        }
        return nil
    }

    /// 无 BOM 的 UTF-16 特征：成对的 0x00 字节（ASCII 文本）占三成以上
    private static func looksLikeBOMLessUTF16(_ data: Data) -> Bool {
        guard data.count >= 8, data.count % 2 == 0 else { return false }
        let sample = min(data.count, 512)
        var zeroEven = 0
        var zeroOdd = 0
        var index = 0
        while index + 1 < sample {
            if data[data.startIndex + index] == 0 { zeroEven += 1 }
            if data[data.startIndex + index + 1] == 0 { zeroOdd += 1 }
            index += 2
        }
        let pairs = Double(sample / 2)
        guard pairs > 0 else { return false }
        return Double(zeroOdd) / pairs > 0.3 || Double(zeroEven) / pairs > 0.3
    }

    /// 系统探测（NSString 的 ICU 检测）；取不到就不勉强
    private static func detectByFoundation(_ data: Data) -> String? {
        var converted: NSString?
        var lossy: ObjCBool = false
        let encoding = NSString.stringEncoding(for: data,
                                               encodingOptions: nil,
                                               convertedString: &converted,
                                               usedLossyConversion: &lossy)
        guard encoding != 0, let ns = converted else { return nil }
        let text = ns as String
        return text.isEmpty ? nil : text
    }

    /// 明显的坏：替换符、私用区、常见乱码串
    private static func isGarbled(_ s: String) -> Bool {
        if s.contains("锟斤拷") || s.contains("烫烫烫") || s.contains("屯屯屯") { return true }

        var total = 0
        var bad = 0
        for scalar in s.unicodeScalars {
            total += 1
            if total > 4000 { break }
            let v = scalar.value
            if v == 0xFFFD || (0xE000...0xF8FF).contains(v) { bad += 1 }
        }
        guard total > 0 else { return false }
        return Double(bad) / Double(total) > 0.005
    }

    /// 可读性打分：常用字 / 中文标点加分，扩展区与控制符扣分。
    /// 解对 GBK 时全角标点密集、常用字多；解错时这两项都会塌下来。
    private static func readability(_ s: String) -> Double {
        var total = 0
        var good = 0.0
        var bad = 0.0
        for scalar in s.unicodeScalars {
            if total >= 4000 { break }
            total += 1
            let v = scalar.value
            switch v {
            case 0x09, 0x0A, 0x0D, 0x20:
                good += 1.0
            case 0x21...0x7E:
                good += 0.9
            case 0x4E00...0x9FFF:
                good += commonHanzi.contains(scalar) ? 1.5 : 0.7
            case 0x3000...0x303F, 0xFF01...0xFF65:
                good += 1.6                     // 中文 / 全角标点
            case 0x2000...0x206F:
                good += 1.2                     // 破折号、省略号
            case 0x3040...0x30FF, 0xAC00...0xD7AF:
                good += 1.0                     // 日文假名、韩文
            case 0x3400...0x4DBF, 0x20000...0x2FA1F:
                bad += 1.0                      // 扩展区：中文 txt 里罕见，多半是解错
            case 0xFFFD:
                bad += 4.0
            case 0xE000...0xF8FF:
                bad += 4.0                      // 私用区，必是错
            default:
                if v < 0x20 { bad += 3.0 } else { good += 0.5 }
            }
        }
        guard total > 0 else { return 0 }
        return (good - bad) / Double(total)
    }

    /// 去 BOM、统一换行、去掉行尾空白
    static func normalize(_ s: String) -> String {
        var t = s
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        // 没有 \r 就不要做替换：replacingOccurrences 会复制整份文本，
        // 几十 MB 的书白复制一次就是几十 MB 的峰值内存。
        guard t.contains("\r") else { return t }
        return t
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// 按空行/换行切分为段落，供 LazyVStack 逐段渲染（长文本不一次性塞进一个 Text）
    static func paragraphs(_ text: String) -> [String] {
        let raw = text.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [String] = []
        var buffer: [String] = []

        func flush() {
            let joined = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { result.append(joined) }
            buffer.removeAll(keepingCapacity: true)
        }

        for line in raw {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else {
                buffer.append(String(line))
            }
        }
        flush()
        return result
    }
}
