#!/usr/bin/env python3
"""S6 静态自检（沙箱无 Xcode，无法编译 Swift，故做力所能及的静态检查）。
检查项：括号配对、框架 import 完整性、自定义类型定义、网络/后台能力、
       Info.plist 权限、pbxproj 结构、工程文件齐全。
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "LocalNovel"
TESTS = ROOT / "LocalNovelTests"

PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(f"  [{'PASS' if cond else 'FAIL'}] {name}" + (f"  -> {detail}" if detail else ""))


def strip_non_code(src: str) -> str:
    """去掉字符串字面量与注释，保留换行，避免括号统计被内容干扰"""
    out, i, state = [], 0, "code"
    while i < len(src):
        c = src[i]
        nxt = src[i + 1] if i + 1 < len(src) else ""
        if state == "code":
            if c == "/" and nxt == "/":
                state, i = "line", i + 2
                out.append("  ")
            elif c == "/" and nxt == "*":
                state, i = "block", i + 2
                out.append("  ")
            elif c == '"':
                state, i = "string", i + 1
                out.append(" ")
            else:
                out.append(c)
                i += 1
        elif state == "line":
            if c == "\n":
                state = "code"
                out.append("\n")
            else:
                out.append(" ")
            i += 1
        elif state == "block":
            if c == "*" and nxt == "/":
                state, i = "code", i + 2
                out.append("  ")
            else:
                out.append("\n" if c == "\n" else " ")
                i += 1
        else:  # string
            if c == "\\":
                out.append("  ")
                i += 2
            elif c == '"':
                state, i = "code", i + 1
                out.append(" ")
            else:
                out.append("\n" if c == "\n" else " ")
                i += 1
    return "".join(out)


def balanced(src: str) -> bool:
    pairs = {")": "(", "]": "[", "}": "{"}
    stack = []
    for c in src:
        if c in "([{":
            stack.append(c)
        elif c in ")]}":
            if not stack or stack.pop() != pairs[c]:
                return False
    return not stack


NEEDS_IMPORT = {
    "UIImage": "UIKit", "UIView": "UIKit", "UIImageView": "UIKit",
    "UIScrollView": "UIKit", "UIScrollViewDelegate": "UIKit",
    "UITapGestureRecognizer": "UIKit", "UIColor": "UIKit",
    "UILongPressGestureRecognizer": "UIKit", "UIGestureRecognizer": "UIKit",
    "UIGestureRecognizerDelegate": "UIKit",
    "AVPlayerViewController": "AVKit",
    "NSObject": "Foundation",
    "CADisplayLink": "QuartzCore",
    "CGImageSource": "ImageIO", "kCGImageSource": "ImageIO", "kCGImageProperty": "ImageIO",
    "AVPlayer": "AVFoundation", "AVPlayerItem": "AVFoundation",
    "AVPlayerLayer": "AVFoundation", "AVAudioSession": "AVFoundation", "CMTime": "AVFoundation",
    "CFStringEncodings": "CoreFoundation", "CFStringConvertEncoding": "CoreFoundation",
    "NSRegularExpression": "Foundation", "FileManager": "Foundation",
    "UserDefaults": "Foundation", "NSString": "Foundation", "NSCache": "Foundation",
    "XCTAssert": "XCTest", "XCTestCase": "XCTest",
    "@main": "SwiftUI", "WindowGroup": "SwiftUI", "@StateObject": "SwiftUI",
    "@EnvironmentObject": "SwiftUI", "@Published": "SwiftUI", "UIViewRepresentable": "SwiftUI",
    "NavigationSplitView": "SwiftUI", "ContentUnavailableView": "SwiftUI",
    "LazyVStack": "SwiftUI", "ScrollViewReader": "SwiftUI", "TabView": "SwiftUI",
    "ColorScheme": "SwiftUI", "LazyHStack": "SwiftUI", "TapGesture": "SwiftUI",
}

EXPECTED_TYPES = [
    "MediaKind", "MediaItem", "Chapter", "ChapterContent", "Book", "Library",
    "LibraryLayout", "ScanDiagnostics",
    "NaturalSort", "MediaResolver", "ChapterTitleCleaner", "BookScanner", "TextLoader",
    "RootFolderAccess", "LibraryStore", "Preferences", "ProgressStore",
    "FrameDetector", "ImageLoader", "AnimatedFrame", "AnimatedFrameCache",
    "AnimatedFrameView", "AnimatedImageView", "LocalMediaPlayer",
    "PlayerContainerView", "PlayerLayerView", "MediaAttachmentView",
    "InlineMediaView", "MediaGalleryView", "ReaderView", "RootView", "WelcomeView",
    "LibrarySidebar", "ChapterListView", "SettingsView", "LocalNovelApp",
    "RateBoostGesture", "RateBoostCoordinator", "AudioSurfaceView",
    "ZoomableImageView", "FullscreenVideoView", "FullscreenPlayerHost",
    "DocumentsBootstrap", "ImportMode", "BookImporter", "BookImportError",
    "AppearanceMode",
]

NETWORK_PATTERNS = [
    "URLSession", "http://", "https://", "NSAppTransportSecurity",
    "Alamofire", "URLRequest", "WebSocket", "Network.framework",
]


def main():
    swift_files = sorted(list(APP.rglob("*.swift")) + list(TESTS.rglob("*.swift")))
    all_text = {p: p.read_text(encoding="utf-8") for p in swift_files}

    print("\n== A. Swift 源码结构 ==")
    check("Swift 文件数 >= 24", len(swift_files) >= 24, f"{len(swift_files)} 个")
    bad_balance = [p.name for p, s in all_text.items() if not balanced(strip_non_code(s))]
    check("括号配对（已剔除字符串/注释）", not bad_balance, str(bad_balance))
    main_count = sum(1 for s in all_text.values() if "@main" in s)
    check("恰好一个 @main 入口", main_count == 1, str(main_count))

    print("\n== B. 框架 import 完整性 ==")
    missing_imports = []
    for p, src in all_text.items():
        imports = re.findall(r"^import\s+(\w+)", src, re.M)
        code = strip_non_code(src)
        for token, framework in NEEDS_IMPORT.items():
            if token in code and framework not in imports:
                missing_imports.append(f"{p.name}: {token} 需要 {framework}")
    check("所有框架符号都有 import", not missing_imports, "; ".join(missing_imports[:5]))

    print("\n== C. 自定义类型定义 ==")
    defined = set()
    for s in all_text.values():
        defined |= set(re.findall(r"^\s*(?:public\s+|private\s+|fileprivate\s+)?(?:final\s+)?(?:struct|enum|class|protocol)\s+(\w+)", s, re.M))
        defined |= set(re.findall(r"^\s*(?:struct|enum|class)\s+(\w+)", s, re.M))
    missing_types = [t for t in EXPECTED_TYPES if t not in defined]
    check("关键类型均已定义", not missing_types, str(missing_types))

    print("\n== D. 离线 / 无后台能力 ==")
    combined = "\n".join(all_text.values())
    # 本轮起允许连自己的 NAS：网络调用只许出现在 WebDAV 客户端与远端图片缓存里
    network_files = {p.name for p in all_text if "URLSession" in all_text[p]}
    check("网络调用只出现在 NAS 客户端（其余仍是纯本地）",
          network_files <= {"WebDAVClient.swift", "RemoteImageCache.swift"}, str(network_files))
    check("没有引入任何第三方网络库",
          not any(k in combined for k in ["Alamofire", "WebSocket", "Network.framework"]))
    plist = (APP / "Info.plist").read_text(encoding="utf-8")
    check("ATS 只为你自填的 NAS http 地址放开，并声明本地网络用途",
          "NSAllowsArbitraryLoads" in plist and "NSLocalNetworkUsageDescription" in plist)
    check("Info.plist 无后台模式", "UIBackgroundModes" not in plist)
    check("Info.plist 声明 iPad 多窗口", "UIApplicationSupportsMultipleScenes" in plist)
    check("Info.plist 含 UISceneConfigurations（避免黑屏）", "UISceneConfigurations" in plist)
    code_only = "\n".join(strip_non_code(s) for s in all_text.values())
    check("iOS 端未误用 macOS 专属的 withSecurityScope（仅检查代码）",
          "withSecurityScope" not in code_only)
    check("未使用第三方依赖", all("import " + m not in combined for m in ["SDWebImage", "Alamofire", "Kingfisher", "SwiftUIX"]))

    print("\n== E. 工程文件 ==")
    proj = ROOT / "LocalNovel.xcodeproj"
    need = [
        proj / "project.pbxproj",
        proj / "project.xcworkspace" / "contents.xcworkspacedata",
        proj / "xcshareddata" / "xcschemes" / "LocalNovel.xcscheme",
        APP / "Info.plist",
        TESTS / "CoreLogicTests.swift",
        ROOT / "SampleBook",
        ROOT / "Validation" / "validate_core.py",
        ROOT / "Tools" / "build_unsigned_ipa.sh",
        ROOT / "Tools" / "check_ipa_readiness.py",
        ROOT / "Tools" / "upload_and_build.sh",
        ROOT / ".github" / "workflows" / "build-unsigned-ipa.yml",
    ]
    check("工程关键文件齐全", all(p.exists() for p in need),
          str([str(p.relative_to(ROOT)) for p in need if not p.exists()]))
    pbx = (proj / "project.pbxproj").read_text(encoding="utf-8")
    check("pbxproj 花括号配对", pbx.count("{") == pbx.count("}"))
    check("pbxproj 使用同步组（免逐文件登记）", "PBXFileSystemSynchronizedRootGroup" in pbx)
    check("部署目标 iOS 27", "IPHONEOS_DEPLOYMENT_TARGET = 27.0" in pbx)
    check("目标设备含 iPad", 'TARGETED_DEVICE_FAMILY = "1,2"' in pbx)

    print("\n== F0. 书库导入（零交互主路径 / 唯一选择器 / 醒目反馈） ==")
    scanner = (APP / "Core" / "BookScanner.swift").read_text(encoding="utf-8")
    access = (APP / "Core" / "RootFolderAccess.swift").read_text(encoding="utf-8")
    store = (APP / "Core" / "LibraryStore.swift").read_text(encoding="utf-8")
    welcome = (APP / "Views" / "RootView.swift").read_text(encoding="utf-8")
    sidebar = (APP / "Views" / "LibrarySidebar.swift").read_text(encoding="utf-8")
    check("保留原 scan(rootURL:) 接口（单元测试兼容）",
          "static func scan(rootURL:" in scanner)
    check("新增带诊断的层级自动识别", "scanWithDiagnostics" in scanner)
    check("三层结构改为「分区 → 书 → 章」，仍保留旧书库兼容",
          all(t in scanner for t in [".sections", ".singleSection", ".legacyRoot"])
          and "OrganizedScanner.scan(rootURL: dir" in scanner)
    check("目录读取失败不再被静默吞掉", "throw" in scanner and "readError" in scanner)
    check("保存书签后不再 stop→resolve→start 两段式",
          "func saveRootFolder(_ url: URL) -> URL" in access
          and "return url" in access
          and "resolvingBookmarkData" not in access.split("func saveRootFolder")[1].split("func restoreRootFolder")[0])
    check("书签持久化失败不阻断本次扫描",
          "try? url.bookmarkData" in access
          and "try RootFolderAccess.shared.saveRootFolder" not in store)
    check("导入改为复制进 App 文档目录（不再依赖临时授权 URL 的持久化）",
          "BookImporter.importIntoDocuments" in store
          and "performImport" in store and "appDocumentsURL()" in store)
    check("导入在后台线程执行、完成后自动重扫文档目录",
          "DispatchQueue.global" in store and "DispatchQueue.main.async" in store
          and "scanWithDiagnostics(rootURL: docs" in store)
    check("选择器失败 / 无选择 / 空结果都有醒目反馈",
          "applyImportFailure" in store and "applyNoSelection" in store
          and "headline =" in store and "importProgress" in store)
    check("导入不再反推书库根，按分区直接复制",
          "preferred: BookCategory?" in (APP / "Core" / "BookImporter.swift").read_text(encoding="utf-8")
          and "suggestedSection(for:" in (APP / "Core" / "BookImporter.swift").read_text(encoding="utf-8")
          and "bestRoot" not in store)
    check("点导入按钮瞬间即有醒目反馈（不再「无任何提示」）",
          "noteImportStarted" in store and "noteImportStarted" in welcome
          and "headline =" in store and "library.headline" in welcome)
    check("iPhone 第一屏可见三种导入方式",
          all(t in sidebar for t in ["导入书籍文件", "导入书籍文件夹", "重新读取"]))
    check("UI 明确引导零交互路径（文件 App → 本地小说）",
          "我的 iPhone → 本地小说" in welcome and "导入书籍文件" in welcome)
    check("UI 明确说明「点文件夹需点打开 / 点文件立即导入」",
          "右上角「打开」" in welcome and "立即开始导入" in welcome
          and "右上角「打开」" in store)
    check("提供 App 文档目录零权限兜底", "useAppDocuments" in store and "usingAppDocuments" in store)
    check("Info.plist 开启文件共享（文档目录可见）", "UIFileSharingEnabled" in plist)
    check("诊断信息在 iPhone 第一栏也可见", "library.diagnostics" in sidebar)

    # ---- 本轮根因：多个 fileImporter 叠加 / 反馈不可见 ----
    check("全工程【唯一】一个 .fileImporter（多个叠加会都不弹出）",
          code_only.count(".fileImporter(") == 1,
          f"实到 {code_only.count('.fileImporter(')} 个")
    check("单选择器由 activeImport 驱动，两种模式都允许选文件夹或文件",
          "enum ImportMode" in store and "activeImport" in store
          and "activeImport" in welcome
          and ".item" in welcome and ".folder" in welcome)
    check("不再残留 isImporting / isFileImporting 双开关",
          "isImporting" not in code_only and "isFileImporting" not in code_only)
    check("切回前台自动补扫 App 文档目录（零点击出书）",
          "refreshOnForeground" in store and "scenePhase" in welcome
          and ".onChange(of: scenePhase)" in welcome)
    check("restore 优先扫 App 文档目录、外部书签不 return 死锁",
          "appDocumentsURL()" in store and "docsReport" in store
          and "restoreRootFolder()" in store)
    check("空态大字状态取代底部极小灰字",
          "headline" in store and "library.headline" in sidebar
          and "EmptyLibraryState" in sidebar
          and "caption2" not in strip_non_code(sidebar))

    print("\n== F0-BIS. 本轮修复：章节记忆 / 滑动流畅度 / 章节删除 ==")
    reader = (APP / "Views" / "ReaderView.swift").read_text(encoding="utf-8")
    inline = (APP / "Views" / "InlineMediaView.swift").read_text(encoding="utf-8")
    chapters = (APP / "Views" / "ChapterListView.swift").read_text(encoding="utf-8")
    progress = (APP / "Core" / "ProgressStore.swift").read_text(encoding="utf-8")
    settings = (APP / "Views" / "SettingsView.swift").read_text(encoding="utf-8")
    importer = (APP / "Core" / "BookImporter.swift").read_text(encoding="utf-8")
    reader_code = strip_non_code(reader)

    check("阅读器去掉 .task 异步状态机（消除「一直载入章节」）",
          ".task(" not in reader_code
          and "@State private var content" not in reader_code
          and "载入章节" not in reader_code)
    check("内容 / 段落全部同步取自缓存，无 nil 等待态",
          "library.content(for: chapter)" in reader
          and "library.paragraphs(for: chapter)" in reader
          and "func paragraphs(for chapter: Chapter)" in store)
    check("滚动不再改父级 @State、不再同步写 UserDefaults",
          "currentAnchor" not in reader_code
          and "visibleAnimated" not in reader_code
          and "setAnchor(" not in reader_code
          and "noteAnchor(" in reader_code)
    check("进度写入节流 + 停滚合并落盘",
          "asyncAfter(deadline: .now() + 0.6" in progress
          and "flushAnchors()" in progress and "flushAnchors()" in reader_code)
    check("动图可见性下沉到子视图自己的 @State（不触发整页重绘）",
          "@State private var onScreen" in inline
          and "onDisappear { onScreen = false }" in inline)
    check("restore 只跑一次，不再每次 onAppear 全量重扫清缓存",
          "didRestore" in welcome)
    check("章节列表支持左滑删除 + 二次确认",
          ".swipeActions" in chapters and "confirmationDialog(" in chapters
          and "deleteChapter(" in store)
    check("书库支持左滑删除整本书 + 二次确认",
          ".swipeActions" in sidebar and "confirmationDialog(" in sidebar
          and "deleteBook(" in store)
    check("删除后清理进度；只读目录删不掉时改为隐藏",
          "func clearProgress" in progress and "clearProgress(for:" in store
          and "hideChapter(" in store and "hiddenChapterIds()" in store)
    check("隐藏章节可在设置里恢复",
          "restoreHiddenChapters()" in store and "恢复已隐藏" in settings)
    check("导入复制失败可回滚，不留半本书",
          "replaceCopy(" in importer and "moveItem(at: backup" in importer)
    check("书签改用默认选项以保留 iOS security scope",
          "options: []" in access
          and ".minimalBookmark" not in strip_non_code(access))

    print("\n== F. 全屏图片 / 视频全屏 / 长按倍速 ==")
    gallery = (APP / "Views" / "MediaGalleryView.swift").read_text(encoding="utf-8")
    check("图片以 fullScreenCover 沉浸式全屏呈现", "fullScreenCover(item:" in code_only)
    check("全屏画廊纯黑底、无常驻白色导航栏",
          "Color.black" in gallery and "NavigationStack" not in gallery)
    check("静态图支持捏合 / 双击缩放",
          "ZoomableImageView" in code_only and "viewForZooming" in code_only)
    check("动图在全屏下逐帧播放且可双击放大",
          "AnimatedImageView" in gallery and "scaleEffect" in gallery)
    check("内联插图有「可全屏」角标提示",
          "arrow.up.left.and.arrow.down.right" in combined)
    check("视频全屏使用系统 AVPlayerViewController", "AVPlayerViewController" in code_only)
    check("全屏与内联共享同一个 AVPlayer（无缝续播）", "controller.player" in code_only)
    check("全屏期间卸载内联播放层，避免抢渲染", "isFullscreen" in code_only)
    check("关闭全屏时收掉倍速状态", "onDismiss:" in code_only)
    check("画中画保持关闭（不后台播放）", "allowsPictureInPicturePlayback = false" in code_only)
    check("长按倍速基于 UIKit began/ended 精确控制",
          "UILongPressGestureRecognizer" in code_only
          and "case .began" in code_only and ".ended" in code_only)
    check("长按倍速写入 player.rate 并在松手还原", "player.rate" in code_only)
    check("长按倍速档位可在设置中调整",
          "longPressRate" in code_only and 'Picker("长按倍速"' in combined)
    check("音频面板也支持长按倍速", "AudioSurfaceView" in code_only)
    check("仍无后台播放等常驻能力，只新增本地网络权限",
          "UIBackgroundModes" not in plist and "NSLocalNetworkUsageDescription" in plist
          and "NSCameraUsageDescription" not in plist and "NSPhotoLibraryUsageDescription" not in plist)

    print("\n== G. 文件 App 目录可见 / App 图标 ==")
    bootstrap = (APP / "Core" / "DocumentsBootstrap.swift").read_text(encoding="utf-8")
    resolver = (APP / "Core" / "MediaResolver.swift").read_text(encoding="utf-8")
    app_entry = (APP / "App" / "LocalNovelApp.swift").read_text(encoding="utf-8")
    wf_text = (ROOT / ".github" / "workflows" / "build-unsigned-ipa.yml").read_text(encoding="utf-8")
    icon_set = APP / "Assets.xcassets" / "AppIcon.appiconset"
    check("Documents 目录启动即写说明文件（Apple 第 3 个条件）",
          "ensureVisibleInFilesApp" in bootstrap and "guideText.write" in bootstrap
          and "DocumentsBootstrap.ensureVisibleInFilesApp()" in app_entry)
    check("说明文件不被扫描器误当成一章正文",
          "guideFileName" in bootstrap
          and "DocumentsBootstrap.guideFileName" in resolver)
    check("切回前台补写说明文件", "DocumentsBootstrap.ensureVisibleInFilesApp()" in store)
    check("版本号提升以刷新系统元数据",
          "<string>2.4</string>" in plist and "CURRENT_PROJECT_VERSION = 1" in pbx
          and "MARKETING_VERSION = 2.4" in pbx)
    check("UI 给出「文件 App 搜索本地小说」兜底路径",
          "搜索框搜「本地小说」" in welcome and "搜索「本地小说」" in store)
    check("AppIcon asset catalog（1024 + Contents.json）",
          (icon_set / "Contents.json").is_file() and (icon_set / "AppIcon.png").is_file())
    check("散装图标 PNG 覆盖 iPhone / iPad 主屏尺寸",
          all((APP / f"AppIcon-{s}.png").is_file() for s in (120, 152, 167, 180)))
    check("Info.plist 声明图标文件（无 asset catalog 时的退路）",
          "CFBundleIconFiles" in plist and "CFBundleIcons~ipad" in plist)
    check("构建设置指向 AppIcon asset",
          "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon" in pbx)
    check("CI 断言 Assets.car 与图标声明",
          "Assets.car" in wf_text and "CFBundleIconName|CFBundleIconFiles" in wf_text)

    print("\n== H. 产物命名带版本号 ==")
    # 约定：编译产物一律叫 LocalNovel-<版本>-b<build>-unsigned.ipa，避免多版本互相覆盖
    build_sh = (ROOT / "Tools" / "build_unsigned_ipa.sh").read_text(encoding="utf-8")
    upload_py = (ROOT / "Tools" / "upload_via_api.py").read_text(encoding="utf-8")
    check("CI 从 Info.plist 取版本并写进 ipa 文件名",
          "CFBundleShortVersionString" in wf_text and "CFBundleVersion" in wf_text
          and "LocalNovel-${VER}-b${BUILD}-unsigned.ipa" in wf_text)
    check("CI artifact 名同样带版本号",
          "IPA_LABEL" in wf_text and "unsigned-ipa" in wf_text)
    check("本地打包脚本默认产物带版本号",
          "LocalNovel-${VER}-b${BUILD}-unsigned.ipa" in build_sh)
    check("API 上传脚本按包内版本命名并保留最新副本",
          "LocalNovel-{label}-unsigned.ipa" in upload_py
          and "LocalNovel-unsigned.ipa" in upload_py and "ipa_version_label" in upload_py)

    print("\n== H. 本轮：外观跟随系统 / 单击看图 / 整页吸附 / 视频旋转 / 独立设置页 ==")
    prefs_src = (APP / "Core" / "Preferences.swift").read_text(encoding="utf-8")
    zoom = (APP / "Media" / "ZoomableImageView.swift").read_text(encoding="utf-8")
    fullscreen = (APP / "Media" / "FullscreenVideoView.swift").read_text(encoding="utf-8")

    check("外观三档（跟随系统 / 浅色 / 深色），nil 表示跟随系统",
          "enum AppearanceMode" in prefs_src
          and all(t in prefs_src for t in ["case system", "case light", "case dark"])
          and "preferredScheme" in prefs_src and "return nil" in prefs_src)
    check("旧「夜间模式」开关迁移到三档并保留旧值兼容",
          "isDarkMode" not in strip_non_code(prefs_src)
          and "defaults.bool(forKey: Keys.dark)" in prefs_src)
    check("根视图按偏好覆盖外观（nil 即跟随系统）",
          ".preferredColorScheme(prefs.preferredScheme)" in welcome)
    check("设置页外观为三档 Picker，字号 / 行距 / 倍速 / 章节 / 书库全部集中",
          'Picker("外观"' in settings and "AppearanceMode.allCases" in settings
          and all(t in settings for t in ["字号", "行距", "长按倍速", "章节目录", "书库"]))
    check("书架（首页）与阅读器均可直达同一个独立设置页",
          "showSettings" in sidebar and "SettingsView()" in sidebar
          and "gearshape" in sidebar and "SettingsView()" in reader
          and 'navigationTitle("设置")' in settings)
    check("大图单击关闭：静态图 require(toFail:) 区分双击、动图 exclusively 互斥",
          "onSingleTap" in gallery and "require(toFail: doubleTap)" in zoom
          and "TapGesture(count: 1)" in gallery and "exclusively(before:" in gallery)
    check("分页改为整页吸附（不再停在两张图中间）",
          "scrollTargetBehavior(.paging)" in gallery
          and "scrollTargetLayout()" in gallery
          and "containerRelativeFrame" in gallery
          and "scrollPosition(id: $selection)" in gallery
          and "TabView" not in strip_non_code(gallery))
    check("缩放视图未放大时不抢横向翻页手势，放大后才允许平移",
          "isScrollEnabled = false" in zoom and "scrollViewDidZoom" in zoom
          and "scrollView.isScrollEnabled = scrollView.zoomScale > 1.01" in zoom)
    check("视频全屏 90° 循环旋转 + 宽高互换铺满",
          "rotate.right" in fullscreen and "rotation = (rotation + 90) % 360" in fullscreen
          and ".rotationEffect(.degrees(Double(rotation)))" in fullscreen
          and "sideways ? h : w" in fullscreen)

    print("\n== I. 本轮：单击切遮罩 / 上滑关闭 / 末页左滑关闭 / 下一章 / 多选删除 ==")
    check("全屏大图不再常驻底部操作提示",
          "bottomHint" not in gallery and "单击关闭 · 左右滑动翻页" not in gallery)
    check("单击切换顶部遮罩显隐（不再单击即关）",
          "chromeVisible" in gallery and "toggleChrome()" in gallery
          and "if chromeVisible" in gallery)
    check("上滑关闭大图（跟手位移 + 松手阈值）",
          "verticalDrag" in gallery and "swipedUp" in gallery and "dy < -90" in gallery)
    check("最后一张继续左滑关闭",
          "isLastPage" in gallery and "swipedPastEnd" in gallery
          and "dx < -90" in gallery)
    check("遮罩隐藏时系统状态栏与 Home 指示条一并隐藏",
          ".statusBarHidden(!chromeVisible)" in gallery
          and "persistentSystemOverlays(chromeVisible ? .visible : .hidden)" in gallery)
    check("图片放大后让出关闭手势，避免缩放时误关",
          "zoomedId == nil" in gallery and "onZoomChanged" in gallery
          and "scrollViewDidZoom" in zoom and "onZoomChanged" in zoom)
    check("关闭时回传当前图片，阅读器滚动定位回该插图",
          "onClose: (MediaItem) -> Void" in gallery
          and "pendingAnchor = imageAnchor" in reader
          and "proxy.scrollTo(anchor, anchor: .center)" in reader
          and "noteAnchor(anchor, for: chapter.id)" in reader)
    check("章末有下一章按钮，最后一章给出提示",
          "下一章" in reader and "onOpenNext(next)" in reader
          and "已是最后一章" in reader and "chapterFooter" in reader)
    check("下一章基于最新章节列表计算并直接切换",
          "nextChapter(after: chapter)" in welcome
          and "onOpenNext: { next in selectedChapter = next }" in welcome
          and "func nextChapter(after chapter: Chapter)" in welcome)
    check("章节支持多选批量删除（全选 / 计数 / 二次确认）",
          "isSelecting" in chapters and "selectedIds" in chapters
          and "confirmBatchDelete" in chapters and "deleteSelected(in:" in chapters
          and "toggleSelectAll" in chapters and "已选 \\(selectedIds.count)" in chapters)
    check("批量删除一次重扫，只读目录同样改为隐藏",
          "func deleteChapters" in store and "hidden += 1" in store
          and "invalidateCaches()" in store)
    check("章节列表渲染取最新扫描结果（删除后不再显示旧快照）",
          "private var currentBook: Book?" in chapters
          and "library.library?.books.first" in chapters)

    print("\n== J. 三分区书库：小说 / 漫画 / 整理（目录即分类） ==")
    models = (APP / "Core" / "LibraryModels.swift").read_text(encoding="utf-8")
    sections = (APP / "Core" / "BookSections.swift").read_text(encoding="utf-8")
    sidebar = (APP / "Views" / "LibrarySidebar.swift").read_text(encoding="utf-8")
    check("三个固定分区：小说 / 漫画 / 整理",
          "enum LibrarySection" in sections
          and all(f'return "{v}"' in models for v in ("小说", "漫画", "整理")))
    check("分区目录名与分类标签一致（小说 / 漫画 / 整理）",
          "var folderName: String { label }" in models
          and "var folderName: String { category.folderName }" in sections)
    check("分类由所在分区决定，不再按内容猜、也不再手动改",
          "let category: BookCategory" in models
          and "BookCategoryRule" not in models
          and "categoryOverrides" not in store
          and "setCategory" not in store
          and "CategoryFilter" not in sidebar)
    check("书库根同时扫描三个分区并汇总计数",
          "for section in presentSections" in scanner
          and "summ" in scanner and "layout: .sections" in scanner)
    check("漫画：漫画名 → 部 → 话 任意层，图片目录与 pdf 单话混排",
          "enum ComicScanner" in sections
          and "maxDepth = 5" in sections
          and "MediaResolver.isImageFile" in sections
          and "MediaResolver.isPDF" in sections
          and "groupName: pdfGroup" in sections)
    check("漫画中间层记为卷名，列表按「部 · 话」展示",
          "group.joined(separator: \" · \")" in sections
          and "var displayTitle: String" in models
          and "groupName" in models)
    check("小说：每个电子书文件一本书（txt / md / epub / pdf）",
          "enum NovelScanner" in sections
          and "bookExtensions" in sections
          and "category: .novel" in sections)
    check("整理：沿用作者 → 章节的旧结构",
          "enum OrganizedScanner" in sections
          and "chapterFolders" in sections
          and "category: .organized" in sections)
    check("旧版根目录书库不丢书（自动归入整理）",
          "legacyRoot" in scanner and "looseDirs" in scanner)
    check("首页就是三个文件夹卡片，点进去看该分区的书",
          "func sectionCard(" in sidebar and "openedSection" in sidebar
          and "library.count(in: category)" in sidebar
          and 'openedSeries ?? openedSection?.label ?? "书库"' in sidebar)
    check("分区内有书列表、无书给结构示例空态",
          "List(loose, id: \\.id, selection: $selection)" in sidebar
          and "ContentUnavailableView" in sidebar
          and "emptyDescription" in sidebar)
    check("启动即建好三个分区目录（打开「文件」App 就能放书）",
          "for section in LibrarySection.allCases" in bootstrap
          and "section.folderName" in bootstrap)
    check("小说分区支持文件夹 = 系列（含子系列，用 · 连接）",
          "let series: String?" in models
          and "series: series + [sub.lastPathComponent]" in sections
          and 'series.joined(separator: " · ")' in sections
          and "series: seriesName" in sections)
    check("系列可由书推导（自然排序），并单独取书 / 计数",
          "func seriesNames(in category: BookCategory) -> [String]" in models
          and "func books(in category: BookCategory, series: String?) -> [Book]" in models
          and "func count(in category: BookCategory, series: String?) -> Int" in models
          and "NaturalSort.sorted(Array(names))" in models)
    check("重扫 / 分章重建 Book 时系列归属不丢",
          "series: book.series" in store)
    check("分区页先列系列文件夹，再列未分组的书",
          "func seriesRow(" in sidebar and 'Text("系列")' in sidebar
          and 'Text("未分组")' in sidebar
          and "library.seriesNames(in: category)" in sidebar)
    check("点系列进入系列内的书列表，导航标题显示系列名",
          "func seriesBooks(_ category: BookCategory, series: String)" in sidebar
          and "openedSeries = name" in sidebar and "private var currentTitle" in sidebar)
    check("导入按当前层级落到分区 / 系列目录",
          "preferredSeries" in importer and "importTargetSeries" in store
          and 'components(separatedBy: " · ")' in importer)
    check("分区 / 系列页支持左边缘右滑返回上一级",
          "private var backSwipe: some Gesture" in sidebar
          and "value.startLocation.x <= 44" in sidebar
          and "value.translation.width >= 80" in sidebar
          and "simultaneousGesture(backSwipe)" in sidebar
          and "private func backToParent()" in sidebar)
    check("书库底部不再有常驻说明文字",
          "library.diagnostics" not in sidebar.split("private var statusBar")[1]
                                          .split("// MARK: - 分区空态文案")[0]
          and "在「文件」App → 本地小说 里整理这三个文件夹" not in sidebar)

    print("\n== K. 小说格式：自动分章 / epub / pdf ==")
    splitter = (APP / "Core" / "ChapterSplitter.swift").read_text(encoding="utf-8")
    epub = (APP / "Core" / "EpubParser.swift").read_text(encoding="utf-8")
    zip_src = (APP / "Core" / "ZipArchive.swift").read_text(encoding="utf-8")
    pdf_view = (APP / "Views" / "PdfChapterView.swift").read_text(encoding="utf-8")
    text_loader = (APP / "Core" / "TextLoader.swift").read_text(encoding="utf-8")
    check("单文件小说按「第X章 / Chapter N / 序章番外」自动分章",
          "enum ChapterSplitter" in splitter
          and "第[0-9０-９一二三四五六七八九十百千万零〇两]" in splitter
          and "Chapter\\\\s+\\\\d" in splitter
          and "序章|序言|楔子" in splitter)
    check("切不出章节就整本一章（绝不把书弄丢）",
          "guard headings.count >= 2 else" in splitter
          and "return [Slice(title: \"\", range: full)]" in splitter)
    check("章节按 UTF-16 区间切片，正文不串章",
          "NSRange(location: heading.start" in splitter
          and "func substring(_ text: String, range: NSRange)" in text_loader)
    check("小说扫描只给占位章，进入书时才后台切章（大书库启动不卡）",
          "chaptersDeferred" in models
          and "chaptersDeferred: true" in sections
          and "func ensureChapters(for book: Book)" in store
          and "DispatchQueue.global" in store)
    check("epub 自解析：zip 中央目录 + container.xml + opf + spine",
          "struct ZipArchive" in zip_src
          and "compression_decode_buffer" in zip_src
          and "META-INF/container.xml" in epub
          and "spineOrder" in epub and "manifestItems" in epub)
    check("epub 按 spine 分章，标题取 h1/h2/title",
          "for (index, item) in ordered.enumerated()" in epub
          and "func heading(in html: String)" in epub
          and "h1\", \"h2\", \"h3\", \"title\"" in epub)
    check("pdf 小说抽取文字，扫描件给出可操作提示",
          "PDFDocument(url: url)" in text_loader
          and "pdfWithoutText" in text_loader
          and "漫画 PDF 请放进「漫画」分区" in text_loader)
    check("漫画 pdf 单话按页懒渲染（可见才转图）",
          "func image(url: URL, page: Int, maxPixel: CGFloat) async" in pdf_view
          and "thumbnail(of:" in pdf_view
          and "LazyVStack(spacing: 0)" in pdf_view)
    check("漫画阅读满宽逐页、无圆角无间距",
          "struct ComicPageView" in (APP / "Views" / "ComicPageView.swift").read_text(encoding="utf-8")
          and "isComic" in reader and "comicBody" in reader
          and "LazyVStack(spacing: 0)" in reader)
    check("章节单位：漫画「话」、短剧「集」、其余「章」",
          "case .comic:      return \"话\"" in sidebar
          and "case .shortDrama: return \"集\"" in sidebar
          and "case .comic:      return \"话\"" in chapters)
    check("整本切片章节只能隐藏，不误删原文件",
          "var canDeleteFromDisk: Bool" in models
          and "整本文件里切出来的一章" in chapters
          and "chapter.canDeleteFromDisk" in store)

    print("\n== L. 本轮：小说翻页 / 漫画长图 / 目录结构说明 ==")
    paginator = (APP / "Core" / "TextPaginator.swift").read_text(encoding="utf-8")
    paged = (APP / "Views" / "PagedReaderView.swift").read_text(encoding="utf-8")
    comic_page = (APP / "Views" / "ComicPageView.swift").read_text(encoding="utf-8")
    comic_store = (APP / "Media" / "ComicImageStore.swift").read_text(encoding="utf-8")
    guide = (APP / "Views" / "StructureGuideView.swift").read_text(encoding="utf-8")
    settings = (APP / "Views" / "SettingsView.swift").read_text(encoding="utf-8")

    check("阅读方式两档可切换，默认左右翻页",
          "enum PageTurnMode" in prefs_src and "case page = 1" in prefs_src
          and "pageTurn = PageTurnMode(rawValue:" in prefs_src
          and "@Published var pageTurn: PageTurnMode = .page" in prefs_src)
    check("设置页提供阅读方式切换",
          'Picker("翻页"' in settings and ".pickerStyle(.segmented)" in settings
          and "showGuide = true" in settings)
    check("CoreText 分页：按容器尺寸逐页量出区间",
          "enum TextPaginator" in paginator
          and "CTFramesetterCreateFrame" in paginator
          and "CTFrameGetVisibleStringRange" in paginator)
    check("空白页不单独成页（分页点落在段尾时不产生空页）",
          "trimmingCharacters(in: .whitespacesAndNewlines).isEmpty" in paginator)
    check("容器放不下一行时立即退出（不死循环）",
          "guard visible.length > 0 else { break }" in paginator)
    check("分页与绘制共用同一套排版参数",
          "static func attributes(fontSize" in paginator
          and "TextPaginator.attributed(" in paged)
    check("翻页用 UIPageViewController 仿真翻页",
          "transitionStyle: .pageCurl" in paged and "UIPageViewControllerDataSource" in paged)
    check("文字页用 CoreText 绘制同一段区间",
          "class CoreTextPageView" in paged and "CTFrameDraw(frame, context)" in paged
          and "NSIntersectionRange(textRange, full)" in paged)
    check("文字颜色随浅色 / 深色实时取，不固化在分页里",
          "mutable.addAttribute(.foregroundColor, value: UIColor.label" in paged)
    check("翻页记忆沿用段落锚点，与滚动模式互通",
          'restoreParagraph' in paged and 'anchor.hasPrefix("blk-p")' in reader
          and 'noteAnchor("blk-p\\(paragraph)"' in reader)
    check("点屏幕左右边缘翻页（中间不误触）",
          "width * 0.28" in paged and "width * 0.72" in paged
          and "shouldReceive touch" in paged)
    check("末页给「下一章 / 已是最后一章」",
          "struct FooterPageView" in paged and "已是最后一章" in paged
          and "下一章" in paged)
    check("翻页模式下插图 / 音视频各占一页，内容不丢",
          "case image(MediaItem)" in paged and "case av(MediaItem)" in paged
          and "MediaAttachmentView(item: item" in paged)
    check("漫画页高按真实宽高比算（消除滚动抖动）",
          "ComicImageStore.shared.pixelSize(of:" in comic_page
          and "pageWidth * aspect" in comic_page)
    check("漫画不再用最长边 1800 降采样（长图糊的根因）",
          "maxPixel: 1800" not in comic_page and "ImageLoader.load(url:" not in comic_page)
    check("漫画长图用 CATiledLayer 分块绘制",
          "override class var layerClass: AnyClass { CATiledLayer.self }" in comic_store
          and "tiled.tileSize = CGSize(width: 1024, height: 1024)" in comic_store)
    check("tile 像素密度按屏幕 scale（否则一定会糊）",
          "contentsScale = scale" in comic_store
          and "window?.screen.scale" in comic_store)
    check("只有超大图才降采样兜底",
          "maxPixels = 40_000_000" in comic_store and "maxPixelSide = 4096" in comic_store)
    check("只读文件头取像素尺寸，不加载像素",
          "CGImageSourceCopyPropertiesAtIndex" in comic_store
          and "kCGImagePropertyPixelWidth" in comic_store)
    check("漫画按容器宽度满宽连排",
          "ComicPageView(item: item, width: geo.size.width)" in reader)
    check("结构说明覆盖漫画三层判定与排序",
          all(t in guide for t in ["漫画名文件夹", "中间文件夹", "直接有图片的文件夹",
                                   "每个 pdf", "自然排序"])
          and "漫画" in guide and "小说" in guide and "整理" in guide)
    check("放书说明.txt 同步漫画识别规则",
          "识别规则" in bootstrap and "漫画名文件夹 = 一部" in bootstrap
          and "中间文件夹 = 卷名" in bootstrap)

    print("\n== M. 本轮：翻页只给小说 / 漫画双格式包 ==")
    root_view = (APP / "Views" / "RootView.swift").read_text(encoding="utf-8")

    check("ReaderView 接收分区（不再是布尔 isComic）",
          "let category: BookCategory" in reader
          and "private var isComic: Bool { category == .comic }" in reader
          and "category: latestBook()?.category ?? .novel" in root_view)
    check("翻页只对「小说」生效，整理 / 漫画恒滚动",
          "category == .novel\n            && prefs.pageTurn == .page" in reader
          and "&& prefs.pageTurn == .page" in reader)
    check("设置页标明阅读方式仅影响小说",
          "Section(\"阅读方式（仅小说）\")" in settings
          and "「整理」是图文混排" in settings and "始终上下滚动" in settings)
    check("结构说明写清各分区阅读方式",
          "只有小说用左右翻页" in guide and "翻页设置不影响这里" in guide)
    check("漫画排序先分组再话名（同组相邻才分得成段）",
          "if ga.isEmpty != gb.isEmpty { return !ga.isEmpty }" in sections
          and 'let ga = a.groupName ?? "", gb = b.groupName ?? ""' in sections)
    check("章节列表按分组分段，包下列出章节",
          "private func chapterGroups(of book: Book)" in chapters
          and "Section {" in chapters and "chapterRow(chapter, showsGroup: false)" in chapters)
    check("没有被分组的书仍是一张平铺列表",
          "if groups.count <= 1 {" in chapters
          and "List(book.chapters, id: \\.id, selection: $selection)" in chapters)
    check("一个分组时不再重复显示组名",
          "if showsGroup, let group = chapter.groupName" in chapters)
    check("结构说明覆盖双格式包（PDF包 / 图片包）",
          "格式包（PDF / 图片）" in guide and "PDF包/" in guide and "图片包/" in guide)
    check("放书说明.txt 与分区提示同步双格式包",
          "格式包（PDF包 / 图片包）" in bootstrap and "格式包" in models
          and "PDF包" in sections)
    check("文档正文含双格式包一节",
          "### 5. 同一部书按格式分成两个包（PDF 包 + 图片包）"
          in (ROOT / "Docs" / "漫画目录结构说明.md").read_text(encoding="utf-8"))
    check("版本升到 2.4 / build 1",
          "<string>2.4</string>" in plist and "<key>CFBundleVersion</key>\n\t<string>1</string>" in plist)


    print("\n== N. 本轮：底部三页 / 短剧 / NAS 连接 ==")
    tab = (APP / "Views" / "MainTabView.swift").read_text(encoding="utf-8")
    nas_views = (APP / "Views" / "NASViews.swift").read_text(encoding="utf-8")
    dav = (APP / "Core" / "WebDAVClient.swift").read_text(encoding="utf-8")
    nas_store = (APP / "Core" / "NASModels.swift").read_text(encoding="utf-8")
    short = (APP / "Core" / "BookSections.swift").read_text(encoding="utf-8")
    app_entry = (APP / "App" / "LocalNovelApp.swift").read_text(encoding="utf-8")

    check("底部三页顺序：书库 → NAS → 设置，默认停在书库",
          "case library" in tab and "case nas" in tab and "case settings" in tab
          and "@State private var selection: Tab = .library" in tab
          and tab.index("Label(\"书库\"") < tab.index("Label(\"NAS\"")
          and tab.index("Label(\"NAS\"") < tab.index("Label(\"设置\""))
    check("App 入口改为三页容器",
          "MainTabView()" in app_entry and "RootView()" not in app_entry)
    check("设置页可作 Tab（不再强制「完成」按钮）",
          "showsDoneButton" in settings and "SettingsView(showsDoneButton: false)" in tab)
    check("短剧分类独立成类，书库与 NAS 都有",
          "case shortDrama" in models and "case shortDrama" in sections
          and "static let categories: [BookCategory] = [.comic, .organized, .shortDrama]" in nas_store)
    check("短剧扫描：剧照包 + 视频包 + 单片",
          "enum ShortDramaScanner" in short and "剧照" in short and "isRoot" in short
          and "case .shortDrama: return ShortDramaScanner.scan" in short)
    check("短剧剧照用漫画那套满宽连排",
          "category == .shortDrama && !content.images.isEmpty" in reader
          and "usesComicLayout" in reader)
    check("剧集行显示大小与时长",
          "VideoMetaFormat.line" in chapters and "VideoMetaStore" in chapters
          and "AVURLAsset" in (APP / "Media" / "VideoMetadata.swift").read_text(encoding="utf-8"))
    check("NAS 页右下角 ➕ 新建连接",
          "NASConnectionEditor" in nas_views and "systemName: \"plus\"" in nas_views
          and "accessibilityLabel(\"新建网络连接\")" in nas_views)
    check("连接填内网 + 外网地址，先探内网再探外网",
          "lanAddress" in nas_store and "wanAddress" in nas_store
          and "for (raw, isLAN) in [(connection.lanAddress, true), (connection.wanAddress, false)]" in nas_store)
    check("连接分类固定访问飞牛目录，且可自定义",
          "func categoryURL(" in nas_store and "categoryPaths" in nas_store
          and "defaultCategoryPaths" in nas_store)
    check("WebDAV 客户端只用 URLSession + XMLParser",
          "PROPFIND" in dav and "XMLParser" in dav and "Authorization" in dav
          and "URLSession" in dav)
    check("密码只进钥匙串，不进 UserDefaults",
          "Keychain.setPassword" in nas_store and "password" not in nas_store.split("private func persist")[1])
    media_views = (APP / "Views" / "RemoteMediaViews.swift").read_text(encoding="utf-8")
    player_src = (APP / "Media" / "LocalMediaPlayer.swift").read_text(encoding="utf-8")
    check("NAS 视频带认证头流式播放，不下载整部",
          "AVURLAssetHTTPHeaderFieldsKey" in player_src
          and "MediaAttachmentView(item:" in media_views
          and "headers: WebDAVClient.headers(account: account)" in media_views
          and "RemoteVideoView" in nas_views)
    check("结构说明覆盖短剧",
          "短剧" in guide and "剧照" in guide)

    print("\n== P. 本轮：NAS 图片缓存上限 / 阅读时收起标签栏 ==")
    chrome = (APP / "Core" / "ReadingChrome.swift").read_text(encoding="utf-8")
    cache = (APP / "Media" / "RemoteImageCache.swift").read_text(encoding="utf-8")
    root_view = (APP / "Views" / "RootView.swift").read_text(encoding="utf-8")
    remote_media = (APP / "Views" / "RemoteMediaViews.swift").read_text(encoding="utf-8")
    prefs_src = (APP / "Core" / "Preferences.swift").read_text(encoding="utf-8")

    check("阅读状态用计数而不是布尔（切章重建不闪标签栏）",
          "final class ReadingChrome" in chrome and "private var depth = 0" in chrome
          and "func enter()" in chrome and "func leave()" in chrome
          and "depth == 0, isImmersive" in chrome)
    check("阅读时收起标签栏，退出立即恢复",
          ".toolbar(chrome.isImmersive ? .hidden : .visible, for: .tabBar)" in tab
          and ".toolbar(chrome.isImmersive ? .hidden : .visible, for: .tabBar)" in root_view)
    check("文字 / 漫画 / 剧照 / 视频四类阅读界面都登记沉浸",
          "ReadingChrome.shared.enter()" in reader
          and "ReadingChrome.shared.leave()" in reader
          and remote_media.count("ReadingChrome.shared.enter()") == 2
          and remote_media.count("ReadingChrome.shared.leave()") == 2)
    check("缓存上限可调，默认 512 MB，可选「不限制」",
          "networkImageCacheMB" in prefs_src
          and "static let imageCacheOptions = [128, 256, 512, 1024, 2048, 0]" in prefs_src
          and "? 512" in prefs_src)
    check("设置页有 NAS 图片缓存区块：上限 / 占用 / 清理",
          'Section("NAS 图片缓存")' in settings and "Picker(\"上限\"" in settings
          and "LabeledContent(\"已占用\")" in settings
          and "清理图片缓存" in settings)
    check("清理前二次确认，且只动本机缓存",
          'confirmationDialog("清空 NAS 图片缓存？"' in settings
          and "只删除本机缓存文件" in settings)
    check("缓存按最久未修改淘汰，超限自动裁",
          "static func trim(folder: URL, limit: Int64) -> Usage" in cache
          and "contentModificationDateKey" in cache
          and "entries.sort { $0.date < $1.date }" in cache
          and "guard total > limit else" in cache)
    check("改上限后立即按新上限裁一次",
          "func enforceLimit() async" in cache
          and "RemoteImageCache.shared.enforceLimit()" in settings)
    check("落盘与淘汰在后台队列，不阻塞翻页",
          "private let queue = DispatchQueue(label: \"LocalNovel.remoteImageCache\"" in cache
          and "let target = folder" in cache and "try? payload.write(to: target" in cache)
    check("上限为 0 时不自动删（不限制）",
          "guard limit > 0 else { return measure(folder: folder) }" in cache)

    print("\n== Q. 本轮：连接编辑 / NAS 分类卡片 / 预取与 HTTP/2 ==")
    card = (APP / "Views" / "CategoryCard.swift").read_text(encoding="utf-8")

    check("书库与 NAS 的「大类入口」共用同一个卡片组件",
          "struct CategoryCard: View" in card
          and "CategoryCard(symbol: category.symbol" in sidebar
          and nas_views.count("CategoryCard(symbol: category.symbol") == 2)
    check("NAS 三个分类与书库同样是卡片列表（不再是 List 行）",
          "ForEach(NASConnection.categories) { category in" in nas_views
          and "private func card(_ category: BookCategory) -> some View" in nas_views
          and "VStack(spacing: 12)" in nas_views
          and "padding(16)" in nas_views)
    check("卡片右侧显示该目录下的部数（进入时并发数一次）",
          "private func countItems(endpoint: NASStore.Endpoint) async" in nas_views
          and "withTaskGroup(of: (String, Int?).self)" in nas_views
          and "entries.filter { $0.isDirectory }.count" in nas_views)
    check("连接可以编辑：左滑 / 长按 / 分类页右上角",
          'Label("编辑", systemImage: "pencil")' in nas_views
          and "contextMenu" in nas_views
          and 'Button { editing = true } label:' in nas_views)
    check("编辑后连接信息取 store 最新值并重新探测",
          "store.connections.first(where: { $0.id == connection.id })" in nas_views
          and "store.save(saved, password: password)" in nas_views
          and "await connect(force: true)" in nas_views)
    check("预取：前后各两张，命中内存直接跳过",
          "for offset in [-2, -1, 1, 2]" in media_views
          and "RemoteImageCache.shared.prefetch(urls, account: account)" in media_views
          and "func prefetch(_ urls: [URL], account: WebDAVAccount)" in cache
          and "if memory.object(forKey: key(url) as NSString) != nil { continue }" in cache)
    check("下载并发闸门 4 个，同一张图不重复下载",
          "private static let maxConcurrentDownloads = 4" in cache
          and "actor AsyncLimiter" in cache
          and "await limiter.acquire()" in cache
          and "if let running = inFlight[token]" in cache)
    check("URLSession 限 4 条连接/host，https 由系统协商 HTTP/2",
          "config.httpMaximumConnectionsPerHost = 4" in dav
          and "static let session: URLSession" in dav
          and "return try await session.data(for: request)" in dav)
    check("能显示当前实际协议（验证多路复用是否生效）",
          "final class ProtocolProbe: NSObject, URLSessionTaskDelegate" in dav
          and "networkProtocolName" in dav
          and "HTTP/2（多路复用）" in dav
          and "ProtocolProbe.shared.displayName" in nas_views)


    print("\n== R. 本轮：短剧格式分流 / 视频全屏旋转倍速 / NAS 书库三层 ==")
    resolver = (APP / "Core" / "MediaResolver.swift").read_text(encoding="utf-8")
    reader = (APP / "Views" / "ReaderView.swift").read_text(encoding="utf-8")
    store_src = (APP / "Core" / "LibraryStore.swift").read_text(encoding="utf-8")
    nas_lib = (APP / "Core" / "NASLibrary.swift").read_text(encoding="utf-8")
    nas_lib_views = (APP / "Views" / "NASLibraryViews.swift").read_text(encoding="utf-8")
    attachment = (APP / "Views" / "MediaAttachmentView.swift").read_text(encoding="utf-8")
    fullscreen = (APP / "Media" / "FullscreenVideoView.swift").read_text(encoding="utf-8")

    check("单文件章节按扩展名分流，视频/图片不再当正文",
          "resolveSingleFile" in resolver
          and "if imageExtensions.contains(ext)" in resolver
          and "if looseVideoExtensions.contains(ext)" in resolver
          and "avMedia: [MediaItem(url: url, kind: .video" in resolver)
    check("短剧常见容器都算「一集」（mkv/avi/wmv…）",
          "static let looseVideoExtensions" in resolver
          and '"mkv"' in resolver and '"rmvb"' in resolver and '"ts"' in resolver)
    check("没有正文的章节返回空串，不再塞「没有正文文件」",
          "纯媒体章节（短剧某一集视频、单张剧照）本来就没有正文" in store_src
          and "（本章没有正文文件）" not in store_src)
    check("纯媒体章节（短剧每集）直接进播放器布局",
          "isMediaOnly" in reader
          and "mediaOnlyBody" in reader
          and "MediaAttachmentView(item: item," in reader)
    check("阅读器空章节给出明确空态",
          "isEmptyChapter" in reader and "这一章没有可显示的内容" in reader)

    check("视频播放：全屏入口",
          'accessibilityLabel("全屏播放")' in attachment
          and "FullscreenVideoView(controller: controller" in attachment)
    check("视频播放：全屏内可旋转画面",
          'accessibilityLabel("旋转画面")' in fullscreen
          and "rotation = (rotation + 90) % 360" in fullscreen)
    check("视频播放：长按临时倍速，松手还原",
          "PlayerLayerView(player: controller.player) { active in boost(active) }" in attachment
          and "RateBoostGesture.attach(to: view, coordinator: context.coordinator)" in player_src
          and "func setBoost(_ active: Bool, rate: Double)" in player_src
          and "RateBoostGesture.attach(to: controller.view" in fullscreen)
    check("播放器支持远端认证头（NAS 视频复用同一套能力）",
          "headers: [String: String] = [:]" in attachment
          and "AVURLAssetHTTPHeaderFieldsKey" in (APP / "Media" / "LocalMediaPlayer.swift").read_text(encoding="utf-8"))

    check("远端剧照连排可点看大图",
          "galleryIndex = index" in media_views
          and "RemoteGalleryView" in media_views)
    check("远端画廊：分页吸附 + 缩放 + 上滑关闭",
          "scrollTargetBehavior(.paging)" in media_views
          and "ZoomableImageView(image: image" in media_views
          and "max(dy * 0.9, -260)" in media_views)

    check("NAS 三层：书名 → 章节 → 阅读",
          "struct NASBookListView" in nas_lib_views
          and "struct NASChapterListView" in nas_lib_views
          and "struct NASChapterReaderView" in nas_lib_views)
    check("NAS 章节识别与本地扫描同一规则",
          "private static func organizedChapters" in nas_lib
          and "private static func comicChapters" in nas_lib
          and "private static func dramaChapters" in nas_lib)
    check("NAS 分类入口直接进书名层（与书库同一层级）",
          "level: .books" in nas_views
          and "case .books:" in nas_views
          and "case .chapters:" in nas_views
          and "case .reader:" in nas_views)
    check("NAS 阅读页顺序与整理一致：正文 → 插图 → 章末媒体",
          "sectionLabel(\"插图 · \(images.count)\")" in nas_lib_views
          and "MediaAttachmentView(item: item," in nas_lib_views
          and "RemoteTextCache.shared.text" in nas_lib_views)
    check("NAS 书目录里直接放文件时仍当作一本书",
          "把目录本身当成一本书" in nas_lib_views
          and "hasMedia ? 1 : nil" in nas_lib)
    check("版本升到 2.4 / build 1",
          "<string>2.4</string>" in plist
          and "<key>CFBundleVersion</key>\n\t<string>1</string>" in plist)

    print(f"\n结果：{len(PASS)} 通过 / {len(FAIL)} 失败")
    if FAIL:
        print("失败项：" + ", ".join(FAIL))
        return 1
    print("S6 静态自检通过（注意：Swift 编译仍需你在 Xcode 27 上执行）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
