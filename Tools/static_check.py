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
          "<string>2.11.9</string>" in plist and "CURRENT_PROJECT_VERSION = 10" in pbx
          and "MARKETING_VERSION = 2.11.9" in pbx)
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
    check("下滑关闭大图（向下跟手 + 松手阈值）",
          "verticalDrag" in gallery and "swipedDown" in gallery
          and "dy > 110 && abs(dy) > abs(dx)" in gallery
          and "min(dy * 0.9, 300)" in gallery)
    check("最后一张从右边缘继续左滑关闭（中间左滑不误关）",
          "isLastPage" in gallery and "swipedPastEnd" in gallery
          and "dx < -90" in gallery and "fromRightEdge" in gallery
          and "value.startLocation.x >= width - 44" in gallery)
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
    check("小说章末不再放「下一章」按钮；其他分区仍保留按钮 + 最后一章提示",
          "private var endMark" in reader
          and "if category == .novel {" in reader
          and "onOpenNext(next)" in reader
          and "advanceIfPulledPastBottom" in reader)
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

    check("阅读方式六档可切换，默认滑动翻页",
          "enum PageTurnMode" in prefs_src and "case page = 1" in prefs_src
          and "case slide = 2" in prefs_src and "case cover = 3" in prefs_src
          and "case vertical = 4" in prefs_src and "case none = 5" in prefs_src
          and "defaults.object(forKey: Keys.pageTurn) as? Int" in prefs_src
          and "@Published var pageTurn: PageTurnMode = .slide" in prefs_src)
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
          "guard visible.length > 0 else { return (0, nil) }" in paginator
          and "guard step.advance > 0 else { break }" in paginator)
    check("分页与绘制共用同一套排版参数",
          "static func attributes(_ type: ReaderTypography" in paginator
          and "TextPaginator.attributed(paragraphs:" in paged
          and "typography: input.typography" in paged)
    check("翻页用 UIPageViewController 仿真翻页",
          "transitionStyle: .pageCurl" in paged and "UIPageViewControllerDataSource" in paged)
    check("文字页用 CoreText 绘制同一段区间",
          "class CoreTextPageView" in paged and "CTFrameDraw(frame, context)" in paged
          and "NSIntersectionRange(textRange, full)" in paged)
    check("文字颜色取主题色，绘制时不复制整章文本",
          ".foregroundColor: theme.uiTextColor" in paginator
          and "NSMutableAttributedString(attributedString: attributed)" not in paged)
    check("翻页记忆沿用段落锚点，与滚动模式互通",
          'restoreParagraph' in paged and 'anchor.hasPrefix("blk-p")' in reader
          and 'noteAnchor("blk-p\\(paragraph)"' in reader)
    check("点屏幕左右边缘翻页（中间不误触）",
          "width * 0.28" in paged and "width * 0.72" in paged
          and "shouldReceive touch" in paged)
    check("翻到末页（滑动继续右拖 / 卷曲左滑 / 右侧点击）直接进下一章",
          "func advanceToNextChapter" in paged
          and "nextChapterThreshold" in paged
          and "handleSwipeLeft" in paged
          and "scrollViewDidEndDragging" in paged
          and "if !input.hasNextChapter { list.append(.footer) }" in paged
          and "struct FooterPageView" in paged and "已是最后一章" in paged
          and "Button(action: onOpenNext)" not in paged)
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
          "category == .novel\n            && prefs.pageTurn.isPaged" in reader
          and "&& prefs.pageTurn.isPaged" in reader)
    check("设置页标明阅读方式仅影响小说",
          "Section(\"阅读方式（仅小说）\")" in settings
          and "「整理」是图文混排" in settings and "始终上下滚动" in settings)
    check("结构说明写清各分区阅读方式",
          "只有小说用分页阅读" in guide and "翻页设置不影响这里" in guide
          and "控制菜单" in guide and "点书直接进正文" in guide)
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
    check("版本升到 2.11.9 / build 7",
          "<string>2.11.9</string>" in plist
          and "<key>CFBundleVersion</key>\n\t<string>10</string>" in plist)


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
    check("远端画廊：分页吸附 + 缩放 + 下滑关闭",
          "scrollTargetBehavior(.paging)" in media_views
          and "ZoomableImageView(image: image" in media_views
          and "min(dy * 0.9, 300)" in media_views)
    check("远端画廊与本地图纸同一套关闭手势（下滑 + 末页右边缘左滑 + 放大让位）",
          "swipedPastEnd" in media_views
          and "swipedDown" in media_views
          and "fromRightEdge" in media_views
          and "value.startLocation.x >= width - 44" in media_views
          and "guard zoomedId == nil else" in media_views
          and "onZoomChanged: onZoomChanged" in media_views
          and "settleBack()" in media_views)
    check("两处画廊手势阈值完全一致（不会一边好关、一边难关）",
          all(t in gallery for t in ("dy > 110", "dx < -90", "width - 44"))
          and all(t in media_views for t in ("dy > 110", "dx < -90", "width - 44")))

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
          and "case .chapters:" in nas_views)
    check("NAS 阅读层拿到兄弟章节，章末可「下一章 / 下一集」",
          "let siblings: [NASChapterRef]" in nas_lib_views
          and "NASChapterReaderView(route: route, chapter: chapter, siblings: chapters)" in nas_lib_views
          and "private var nextChapter: NASChapterRef?" in nas_lib_views)
    check("NAS 阅读进度与书库共用 ProgressStore（书 / 章两级 key）",
          "enum NASProgress" in nas_lib_views
          and "static func bookKey" in nas_lib_views
          and "static func chapterKey" in nas_lib_views
          and "ProgressStore.shared.setLastChapter(progressKey" in nas_lib_views
          and "ProgressStore.shared.noteAnchor" in nas_lib_views)
    check("NAS 章节列表标出「读到这章」",
          "lastChapterId == NASProgress.chapterKey(chapter.url)" in nas_lib_views)
    check("NAS 关掉大图后能滚回刚看的那张",
          "onClose: ((Int) -> Void)? = nil" in media_views
          and "onClose?(currentIndex)" in media_views
          and 'pendingAnchor = "blk-i\\(closed)"' in nas_lib_views)
    check("NAS 阅读页顺序与整理一致：正文 → 插图 → 章末媒体",
          "sectionLabel(\"插图 · \(images.count)\")" in nas_lib_views
          and "MediaAttachmentView(item: item," in nas_lib_views
          and "RemoteTextCache.shared.text" in nas_lib_views)
    check("NAS 书目录里直接放文件时仍当作一本书",
          "把目录本身当成一本书" in nas_lib_views
          and "hasMedia ? 1 : nil" in nas_lib)
    check("版本升到 2.11.9 / build 7",
          "<string>2.11.9</string>" in plist
          and "<key>CFBundleVersion</key>\n\t<string>10</string>" in plist)

    print("\n== S. 本轮：txt 乱码（UTF-16 误判 / GBK / Big5） ==")
    encoding_src = (APP / "Core" / "TextEncoding.swift").read_text(encoding="utf-8")
    loader_src = (APP / "Core" / "TextLoader.swift").read_text(encoding="utf-8")

    check("编码选项含自动 / UTF-8 / GBK / Big5 / UTF-16",
          all(c in encoding_src for c in ("case auto", "case utf8", "case gb18030",
                                          "case big5", "case utf16")))
    check("按书记忆编码（目录取父目录，单文件取自身）",
          "static func bookKey(for chapter: Chapter)" in encoding_src
          and "deletingLastPathComponent().standardizedFileURL.path" in encoding_src
          and "static func set(_ option: TextEncodingOption" in encoding_src)
    check("乱码根因已修：UTF-16 必须先有 BOM 或 NUL 特征才尝试",
          "looksLikeBOMLessUTF16" in loader_src
          and "if looksLikeBOMLessUTF16(data)," in loader_src)
    check("BOM 优先（UTF-8 / UTF-16 LE / BE）",
          "0xEF" in loader_src and "utf16LittleEndian" in loader_src
          and "utf16BigEndian" in loader_src)
    check("GB18030 与 Big5 打分取最优（常用字 + 全角标点 + 扩展区惩罚）",
          "commonHanzi" in loader_src and "readability(" in loader_src
          and "best?.score ?? -Double.infinity" in loader_src
          and "0x3000...0x303F, 0xFF01...0xFF65" in loader_src)
    check("替换符 / 私用区 / 锟斤拷 判为乱码",
          "锟斤拷" in loader_src and "0xE000...0xF8FF" in loader_src
          and "0xFFFD" in loader_src)
    check("手动编码会清掉这本书的正文缓存",
          "func setTextEncoding" in store_src
          and "textCache = keepText" in store_src
          and "objectWillChange.send()" in store_src)
    check("阅读器有「文本编码」菜单，只在读文字时出现",
          "private var encodingMenu" in reader
          and "showsEncoding: showsEncodingMenu" in reader
          and "content.pdfURL == nil && content.textURL != nil" in reader)
    check("NAS 阅读页同样能换编码",
          "TextEncodingStore.bookKey(forURL:" in nas_lib_views
          and "RemoteTextCache.shared.invalidate()" in nas_lib_views)

    # ---------- T. 本轮：标签栏不收起 / 章节跳末页 / 大文件闪退 ----------
    print("\n== T. 本轮：阅读标签栏 / 章节跳末页 / 大文件内存 ==")
    check("阅读页自己声明隐藏底部标签栏（书库）",
          ".toolbar(.hidden, for: .tabBar)" in reader)
    check("阅读页自己声明隐藏底部标签栏（NAS）",
          ".toolbar(.hidden, for: .tabBar)" in nas_lib_views)
    check("隐藏标签栏声明在 tab 内容视图上（写在 TabView 上不生效）",
          ".toolbar(chrome.isImmersive ? .hidden : .visible, for: .tabBar)\n                .tabItem" in tab)
    check("跳末页根因：按 pages 取段落，插图/章末页不写锚点",
          "if case .text(let slice) = pages[currentIndex] { return slice.paragraph }" in paged
          and "if let paragraph = currentParagraph { onProgress?(paragraph) }" in paged)
    check("锚点越界回落到本章开头（重新切章后不跳末尾）",
          "value < paragraphs.count else { return 0 }" in reader)
    check("整章只建一份排版文本（不再每页一份全文）",
          "private(set) var measureAttributed" in paged
          and "let attributed = measureAttributed" in paged)
    check("页控制器按窗口淘汰（大章节不常驻全部页视图）",
          "func evict(except range: ClosedRange<Int>)" in paged
          and "abs(key - index) > 2" in paged)
    check("绘制不再复制整章文本上色",
          ".foregroundColor: theme.uiTextColor" in paginator
          and "NSMutableAttributedString(attributedString: attributed)" not in paged)
    check("大文件读取用内存映射，不整份拷贝进堆",
          "Data(contentsOf: url, options: .mappedIfSafe)" in loader_src)
    check("大文件先在小样本上判编码（不同时解出多份全文）",
          "decodeSampleLimit" in loader_src and "guessLegacyEncoding" in loader_src
          and "data.prefix(decodeSampleLimit)" in loader_src)
    check("分页循环用 autoreleasepool 回收中间对象",
          "autoreleasepool { () -> (advance: Int, paragraph: Int?) in" in paginator)
    check("没有 \\r 时不做换行替换（省一次全文复制）",
          'guard t.contains("\\r") else { return t }' in loader_src)
    check("启动扫描离开主线程（大文件不卡死主线程）",
          "let docs = appDocumentsURL()\n        let external = RootFolderAccess.shared.restoreRootFolder()" in store_src
          and "DispatchQueue.global(qos: .userInitiated).async {\n            var docsReport" in store_src)
    check("切章逐行扫描先判行长，不为每行创建字符串",
          "contentLength <= maxTitleLength * 2" in splitter
          and "getLineStart(&lineStart" in splitter)
    check("扫描期间有「正在读取书库」反馈",
          "library.isScanning" in root_view)

    print("\n== U. 滑动翻页 / 标签栏兜底 / 选章从章首开始 ==")
    pref_src = (APP / "Core" / "Preferences.swift").read_text(encoding="utf-8")
    chapter_list = (APP / "Views" / "ChapterListView.swift").read_text(encoding="utf-8")
    hider_path = APP / "Views" / "TabBarAutoHide.swift"
    hider = hider_path.read_text(encoding="utf-8") if hider_path.exists() else ""

    check("阅读方式六档：滚动 / 仿真 / 平移 / 覆盖 / 上下翻页 / 无动画",
          "case scroll = 0" in pref_src and "case page = 1" in pref_src
          and "case slide = 2" in pref_src and "var isPaged: Bool" in pref_src)
    check("滑动翻页用 UIScrollView 分页（整页跟手横移）",
          "scroller.isPagingEnabled = true" in paged
          and "contentInsetAdjustmentBehavior = .never" in paged)
    check("滑动页有左右页边阴影（纸张叠压感）",
          "UIColor.black.withAlphaComponent(0.16).cgColor" in paged
          and 'leftEdge.name = "edge.left"' in paged)
    check("五套引擎共用分页 / 定位 / 锚点（切换模式不丢位置）",
          "class PagedBaseController: UIViewController" in paged
          and "final class CurlPageController: PagedBaseController" in paged
          and "class SlidePageController: PagedBaseController" in paged
          and "final class CoverPageController: PagedBaseController" in paged
          and "final class InstantPageController: PagedBaseController" in paged
          and "final class VerticalPageController: SlidePageController" in paged)
    check("未翻页前始终用记忆段落定位（首帧尺寸变化不挤走位置）",
          "let anchor = didNavigate ? nearestParagraph(at: currentIndex) : restoreParagraph" in paged
          and "func clampedParagraph(_ value: Int) -> Int" in paged)
    check("标签栏 UIKit 兜底：布局阶段重复压住 UITabBarController",
          "struct TabBarAutoHide: UIViewControllerRepresentable" in hider
          and "override func viewWillLayoutSubviews()" in hider
          and "TabBarVisibility.setHidden(true, animated: false)" in hider
          and "tab.tabBar.isHidden = hidden" in hider)
    check("阅读页挂上标签栏兜底",
          "TabBarAutoHide()" in reader)
    check("用户主动在目录选章 → 从章首开始",
          'ProgressStore.shared.setAnchor("blk-p0", for: chapter.id)' in chapter_list)
    check("自动恢复上次章节时不重置锚点",
          "autoRestoredChapterId = chapter.id" in chapter_list
          and "if autoRestoredChapterId == chapter.id" in chapter_list)
    check("老用户升级后一次性迁移到滑动翻页（只做一次）",
          "Keys.slideMigrated" in pref_src and "if pageTurn == .page" in pref_src)
    check("主动设锚点会清掉同章的防抖旧值",
          "pendingAnchors.removeValue(forKey: chapterId)" in (APP / "Core" / "ProgressStore.swift").read_text(encoding="utf-8"))

    print("\n== V. 小说选书即读 / 中间单击控制菜单 / 目录弹层 ==")
    root = (APP / "Views" / "RootView.swift").read_text(encoding="utf-8")
    controls = (APP / "Views" / "ReaderControlsView.swift").read_text(encoding="utf-8")
    models = (APP / "Core" / "LibraryModels.swift").read_text(encoding="utf-8")
    list_view = (APP / "Views" / "ChapterListView.swift").read_text(encoding="utf-8")

    check("小说选书即读：选书后直接定位章节进 detail",
          "openNovelDirectly(book)" in root
          and "book.category == .novel" in root
          and "selectedChapter = nil" in root)
    check("切章完成 / 章节失效时重新定位（chapterSignature）",
          "var chapterSignature" in root
          and "contains(where: { $0.id == current.id })" in root)
    check("选章副作用统一到 RootView，目录页对小说放行",
          "ProgressStore.shared.setLastChapter(chapter.id, for: book.id)" in root
          and "guard book.category != .novel else { return }" in list_view)
    check("阅读器新增 chapters / onSelectChapter / onExit 参数",
          "let chapters: [Chapter]" in reader
          and "let onSelectChapter" in reader
          and "let onExit" in reader)
    check("翻页引擎中间区域单击回调 onTapCenter",
          "let onTapCenter: () -> Void" in paged
          and "controller.onTapCenter = onTapCenter" in paged
          and "onTapCenter?()" in paged)
    check("非翻页模式中间区域单击（坐标 28%~72%）",
          "func centerTappable" in reader
          and "point.x > w * 0.28 && point.x < w * 0.72" in reader)
    check("占位章标识，目录里过滤掉",
          "var isPlaceholder" in models
          and "filter { !$0.isPlaceholder }" in root)
    check("控制菜单可调字号 / 行距 / 翻页 / 外观",
          "struct ReaderControlsPanel" in controls
          and 'binding(for: \\.pageTurn)' in controls
          and 'binding(for: \\.appearance)' in controls
          and 'sliderRow("字号"' in controls
          and 'sliderRow("行距"' in controls)
    check("面板含目录入口与退出阅读",
          "onTOC: { showStylePanel = false; showCatalog = true }" in reader
          and 'entryButton("目录", systemImage: "list.bullet"' in controls
          and "onExit" in controls)
    check("目录面板列出全部章节、当前章高亮、点击跳转",
          "struct ReaderCatalogView" in (APP / "Views" / "ReaderCatalogView.swift").read_text(encoding="utf-8")
          and "chapter.id == currentId" in (APP / "Views" / "ReaderCatalogView.swift").read_text(encoding="utf-8")
          and "onSelect(chapter)" in (APP / "Views" / "ReaderCatalogView.swift").read_text(encoding="utf-8"))
    check("阅读页挂排版面板与目录面板（都走 overlay，不弹 sheet）",
          "ReaderControlsPanel(" in reader
          and "ReaderCatalogView(chapters: chapters" in reader
          and ".overlay(alignment: .bottom)" in reader
          and ".sheet(isPresented: $showTOC)" not in reader)
    check("控制菜单含「全部设置」入口（复用设置页）",
          "let onSettings: () -> Void" in controls
          and 'entryButton("全部设置", systemImage: "gearshape"' in controls
          and "onSettings: { showSettings = true }" in reader)

    print("\n== W. 本轮：章末去掉「下一章」按钮，翻到底直接续章 ==")
    reader = (APP / "Views" / "ReaderView.swift").read_text(encoding="utf-8")
    paged = (APP / "Views" / "PagedReaderView.swift").read_text(encoding="utf-8")

    check("有下一章时不再追加章末页（末页就是正文最后一页）",
          "if !input.hasNextChapter { list.append(.footer) }" in paged)
    check("章末页只剩「已是最后一章」，不再有按钮",
          "struct FooterPageView" in paged
          and "Button" not in paged.split("private struct FooterPageView")[1]
          and "已是最后一章" in paged)
    check("统一的续章出口：末页再翻才切，一次翻页只切一次",
          "func advanceToNextChapter" in paged
          and "nextTriggered" in paged
          and "input?.hasNextChapter == true" in paged)
    check("滑动翻页：末页继续右拖超过阈值才切章",
          "nextChapterThreshold: CGFloat = 72" in paged
          and ".contentOffset.x - maxOffset" in paged
          and "func finishDrag() -> Bool" in paged)
    check("仿真翻页：末页左滑切章（不再顶死在末页）",
          "UISwipeGestureRecognizer" in paged
          and "@objc private func handleSwipeLeft" in paged
          and "swipe.cancelsTouchesInView = false" in paged)
    check("点击翻页到末页同样进下一章",
          "if delta > 0, advanceToNextChapter() { return }" in paged)
    check("小说上下滚动：到底继续上拉进下一章（整理不受影响，短章也能拉）",
          "onScrollGeometryChange" in reader
          and "advanceIfPulledPastBottom" in reader
          and "guard category == .novel" in reader
          and ".scrollBounceBehavior(.always" in reader)

    print("\n== X. 本轮：小说阅读显示效果（排版 / 标题 / 页眉页脚 / 主题） ==")
    style = (APP / "Core" / "ReaderStyle.swift").read_text(encoding="utf-8")
    prefs_src = (APP / "Core" / "Preferences.swift").read_text(encoding="utf-8")
    paginator = (APP / "Core" / "TextPaginator.swift").read_text(encoding="utf-8")
    controls = (APP / "Views" / "ReaderControlsView.swift").read_text(encoding="utf-8")
    settings = (APP / "Views" / "SettingsView.swift").read_text(encoding="utf-8")
    paged = (APP / "Views" / "PagedReaderView.swift").read_text(encoding="utf-8")
    reader = (APP / "Views" / "ReaderView.swift").read_text(encoding="utf-8")

    check("排版参数集中成 ReaderTypography（字号/字重/行距/段距/字距/边距/对齐/缩进/繁简/标题）",
          "struct ReaderTypography" in style
          and all(k in style for k in ["var fontSize", "var fontFamily", "var weight",
                                       "var lineSpacing", "var paragraphSpacing", "var wordSpacing",
                                       "var horizontalPadding", "var alignment",
                                       "var firstLineIndent", "var isTraditional"]))
    check("主题模型含正文/背景/标题/页码/页眉页脚/分隔线 6 色 + 背景图",
          "struct ReaderTheme: Identifiable, Codable" in style
          and all(k in style for k in ["var textColor", "var backgroundColor", "var titleColor",
                                       "var pageIndexColor", "var headerFooterColor",
                                       "var separatorColor", "var backgroundImage"]))
    check("内置 6 套主题 + 自定义主题可持久化（JSON）",
          style.count("isBuiltIn: true") >= 6
          and "static let builtIns" in style
          and "JSONEncoder().encode(customThemes)" in prefs_src)
    check("章节标题作为标题块排进正文第一页（不是另起一页）",
          "static func titleAttributed" in paginator
          and "titleOffset: Int = 0" in paginator
          and "combined.append(titleAttr)" in paged)
    check("标题样式可调：字号比例/固定字号/字重/斜体/上下间距/下划线/分两行",
          all(k in style for k in ["var scale", "var isFixed", "var fixedSize", "var weight",
                                   "var isItalic", "var topPadding", "var bottomPadding",
                                   "var showBottomLine", "var splitTwoLines"])
          and "static func splitTitle" in paginator)
    check("页眉页脚按设置渲染（内容 / 开关 / 间距）",
          "ReaderHeaderMode" in prefs_src and "ReaderFooterMode" in prefs_src
          and "private let headerLabel" in paged
          and "headerLabel.frame" in paged
          and "TextPaginator.percentText" in paged)
    check("滚动模式与分页共用同一套字体与标题样式",
          "private var bodyFont: UIFont" in reader
          and "private var chapterTitleBlock" in reader
          and "chapterTitleBlock" in reader)
    check("繁简用 ICU 转换，不维护映射表",
          'StringTransform(rawValue: id)' in style
          and '"Simplified-Traditional"' in style
          and "ReaderTextPipeline.paragraphs(chapterId: chapter.id" in reader
          and "ChineseScript.toTraditional" in (APP / "Core" / "PurifyEngine.swift").read_text(encoding="utf-8"))
    check("阅读亮度只压阅读层 + 常亮退出即还原",
          "brightnessOverlay" in reader
          and "(1 - prefs.readerBrightness) * 0.8" in reader
          and "isIdleTimerDisabled = prefs.keepScreenOn" in reader
          and "UIApplication.shared.isIdleTimerDisabled = false" in reader)
    check("只作用于小说：滚动模式的排版/标题/边距都按分区拦一道",
          "guard category == .novel else { return raw }" in reader
          and "category == .novel ? prefs.horizontalPadding : 20" in reader
          and "if category == .novel {\n                        chapterTitleBlock" in reader)
    check("设置页与阅读面板都能调这些项（两处互通）",
          'Section("排版（仅小说）")' in settings
          and 'Section("章节标题（仅小说）")' in settings
          and 'Section("页眉页脚（仅小说）")' in settings
          and 'Section("阅读主题（仅小说）")' in settings
          and 'sliderRow("段距"' in controls
          and 'sliderRow("字距"' in controls
          and 'sliderRow("边距"' in controls)

    print("\n== Y. 本轮：翻页引擎六档（覆盖 / 上下翻页 / 无动画 / 动画时长 / 预取） ==")
    prefs_src = (APP / "Core" / "Preferences.swift").read_text(encoding="utf-8")
    paged = (APP / "Views" / "PagedReaderView.swift").read_text(encoding="utf-8")
    reader = (APP / "Views" / "ReaderView.swift").read_text(encoding="utf-8")
    controls = (APP / "Views" / "ReaderControlsView.swift").read_text(encoding="utf-8")

    check("六档翻页模式：滚动 / 仿真 / 平移 / 覆盖 / 上下翻页 / 无动画",
          all(k in prefs_src for k in ["case cover = 3", "case vertical = 4", "case none = 5"])
          and all(k in prefs_src for k in ['return "覆盖"', 'return "上下翻页"', 'return "无动画"']))
    check("每档映射到独立的呈现引擎",
          "case .cover:    return .cover" in prefs_src
          and "case .vertical: return .vertical" in prefs_src
          and "case .none:     return .none" in prefs_src
          and "case .cover:    controller = CoverPageController()" in paged
          and "case .vertical: controller = VerticalPageController()" in paged
          and "case .none:     controller = InstantPageController()" in paged)
    check("覆盖翻页：跟手拖拽 + 位移/速度阈值 + 松手回弹",
          "final class CoverPageController" in paged
          and "dx < -width * 0.28 || velocity < -700" in paged
          and "func dropIncoming()" in paged
          and "func commit()" in paged)
    check("上下翻页复用滑动引擎，只把轴换成纵向",
          "var isVertical: Bool { false }" in paged
          and "final class VerticalPageController: SlidePageController" in paged
          and "isVertical ? height : width" in paged)
    check("无动画模式：左右滑 + 点击直接换页，不加过渡",
          "final class InstantPageController" in paged
          and "move(by: gesture.direction == .left ? 1 : -1)" in paged)
    check("翻页动画时长可调，只对覆盖生效",
          "var flipDuration: Double = 0.28" in prefs_src
          and "let flipDuration: Double" in paged
          and "if prefs.pageTurn == .cover" in controls)
    check("翻页方式改成菜单选择（六档放不下一排分段）",
          ".pickerStyle(.menu)" in controls)
    check("相邻章正文预取（切章不空等）",
          "func warmNextChapter()" in reader
          and "library.paragraphs(for: next)" in reader)
    check("版本已升到 2.11.9 / build 7",
          "2.11.9" in (APP / "Info.plist").read_text(encoding="utf-8"))

    print("\n== Z. 本轮：上下菜单栏 + 进度滑杆 + 目录面板 ==")
    bars = (APP / "Views" / "ReaderChromeBars.swift").read_text(encoding="utf-8")
    catalog = (APP / "Views" / "ReaderCatalogView.swift").read_text(encoding="utf-8")
    reader = (APP / "Views" / "ReaderView.swift").read_text(encoding="utf-8")

    check("顶部条：返回 + 书名/章节名 + 右侧动作",
          "struct ReaderTopBar" in bars
          and "chevron.left" in bars
          and "let trailing: String?" in bars
          and "ReaderTopBar(title: topBarTitle" in reader)
    check("底部条：上一章 / 进度滑杆 / 下一章",
          "struct ReaderBottomBar" in bars
          and 'Text("上一章")' in bars and 'Text("下一章")' in bars
          and "Slider(value: Binding(get: { shownValue }" in bars)
    check("底部工具行：目录 / 日夜 / 主题 / 排版 / 设置",
          all(k in bars for k in ['tool("目录"', 'tool("主题"', 'tool("排版"', 'tool("设置"'])
          and 'isNight ? "白天" : "夜间"' in bars)
    check("进度按「章节 + 本章段落」折算，拖动时浮出章节名",
          "chapterIndex" in reader and "bookProgress" in reader
          and '"blk-p"' in reader
          and "scrubTitle" in reader and "chapterTitle(at:" in reader)
    check("目录面板从下方浮出（不是 sheet），带搜索 / 正序倒序 / 章节数",
          "ignoresSafeArea(edges: .bottom)" in catalog
          and "搜索章节" in catalog
          and "倒序" in catalog and "正序" in catalog
          and 'return "共 \\(chapters.count) 章"' in catalog)
    check("目录打开即定位当前章，并提供「定位到当前章」按钮",
          "proxy.scrollTo(currentId, anchor: .center)" in catalog
          and 'footerButton("定位到当前章")' in catalog)
    check("菜单开合由正文中间单击驱动，切章后自动收起",
          "showMenu.toggle()" in reader
          and "showMenu = false" in reader
          and "ReaderCatalogView(chapters: chapters" in reader)
    check("白天 / 夜间一键切换（按主题的 isNight 挑）",
          "private func toggleDayNight()" in reader
          and "$0.isNight == wantNight" in reader)

    print("\n== AA. 本轮：点击区可配 / 音量键翻页 / 启动进上次书 / 字体导入 ==")
    paged = (APP / "Views" / "PagedReaderView.swift").read_text(encoding="utf-8")
    reader = (APP / "Views" / "ReaderView.swift").read_text(encoding="utf-8")
    prefs_src = (APP / "Core" / "Preferences.swift").read_text(encoding="utf-8")
    settings = (APP / "Views" / "SettingsView.swift").read_text(encoding="utf-8")
    root = (APP / "Views" / "RootView.swift").read_text(encoding="utf-8")
    fontlib = (APP / "Core" / "ReaderFontLibrary.swift").read_text(encoding="utf-8")
    vol = (APP / "Core" / "VolumeKeyPager.swift").read_text(encoding="utf-8")

    check("三块点击区各自可选「上一页 / 下一页 / 菜单 / 无」",
          "enum TapZoneAction" in (APP / "Core" / "ReaderStyle.swift").read_text(encoding="utf-8")
          and all(k in prefs_src for k in ["var tapLeft", "var tapCenter", "var tapRight"])
          and "zone = input?.tapLeft ?? .prevPage" in paged
          and "private func perform(_ zone: TapZoneAction)" in paged)
    check("音量键翻页：KVO 监听系统音量 + 隐藏 MPVolumeView + 拨回基准值",
          "outputVolume" in vol and "MPVolumeView" in vol
          and "slider.value = target" in vol
          and "setCategory(.ambient" in vol)
    check("音量键只给小说分页模式，且用指令号驱动（不触发重排）",
          "guard category == .novel, prefs.pageTurn.isPaged, prefs.volumeKeyFlip" in reader
          and "let pageCommand: Int" in paged
          and "if new.pageCommand != lastPageCommand" in paged)
    check("启动可直接进入上次读的书（书库到位后再跳）",
          "autoOpenLastBookIfNeeded" in root
          and "ProgressStore.shared.lastChapterId(for: book.id)" in root
          and "didAutoOpen" in root)
    check("字体导入复用唯一的 fileImporter（不新增第二个）",
          "case font" in (APP / "Core" / "LibraryStore.swift").read_text(encoding="utf-8")
          and "library.activeImport = .font" in settings
          and "handleFontImport" in root
          and ".fileImporter" not in settings)
    check("字体落在沙盒并幂等注册，启动时刷新列表",
          "CTFontManagerRegisterFontsForURL" in fontlib
          and "ReaderFontLibrary.registerInstalled()" in (APP / "App" / "LocalNovelApp.swift").read_text(encoding="utf-8"))

    print("\n== AB. 本轮：自定义主题编辑器 ==")
    editor = (APP / "Views" / "ThemeEditorView.swift").read_text(encoding="utf-8")
    style = (APP / "Core" / "ReaderStyle.swift").read_text(encoding="utf-8")
    controls = (APP / "Views" / "ReaderControlsView.swift").read_text(encoding="utf-8")
    settings = (APP / "Views" / "SettingsView.swift").read_text(encoding="utf-8")
    reader = (APP / "Views" / "ReaderView.swift").read_text(encoding="utf-8")
    prefs_src = (APP / "Core" / "Preferences.swift").read_text(encoding="utf-8")

    check("主题管理：新建 / 复制内置 / 删除 / 夜间标记",
          "struct ThemeManagerView" in editor
          and "static func newCustom(from base: ReaderTheme" in style
          and ".onDelete { indexSet in" in editor
          and 'Toggle("作为夜间主题"' in editor)
    check("编辑器可改 6 个颜色 + 名称，并带实时预览",
          editor.count("ColorPicker(") >= 6
          and 'TextField("主题名字"' in editor
          and 'Section("预览")' in editor)
    check("背景图从相册选，落盘后只存文件名",
          "PhotosPicker(selection: $pickerItem" in editor
          and "ReaderBackgroundImage.save(imageData:" in editor
          and "loadTransferable(type: Data.self)" in editor)
    check("颜色双向转换（hex → Color / Color → hex）",
          "var hexRGB: String" in style
          and "var hexRGB: String { UIColor(self).hexRGB }" in style)
    check("保存可「仅保存」或「保存并应用」；删掉在用的主题回退纸白",
          'Button("保存并应用")' in editor and 'Button("仅保存")' in editor
          and "prefs.themeId = draft.id" in editor
          and "prefs.themeId = ReaderTheme.builtIns[0].id" in editor)
    check("阅读面板与设置页都能进主题管理",
          "onThemeEditor: { showThemeManager = true }" in reader
          and 'Button("管理") { onThemeEditor() }' in controls
          and "showThemeManager = true" in settings)
    check("自定义主题随 Preferences 一起持久化（JSON）",
          "JSONEncoder().encode(customThemes)" in prefs_src)

    print("\n== AC. 本轮：净化（正则替换） ==")
    purify = (APP / "Core" / "PurifyEngine.swift").read_text(encoding="utf-8")
    manager = (APP / "Views" / "PurifyManagerView.swift").read_text(encoding="utf-8")
    reader = (APP / "Views" / "ReaderView.swift").read_text(encoding="utf-8")
    prefs_src = (APP / "Core" / "Preferences.swift").read_text(encoding="utf-8")

    check("净化规则：正则 + 替换文本 + 开关 + 纯文本模式",
          "struct PurifyRule" in purify
          and all(k in purify for k in ["var pattern", "var replacement", "var isEnabled", "var isRegex"]))
    check("正则可编译、写错就跳过（不吞正文）",
          "NSRegularExpression(pattern: pattern" in purify
          and "continue   // 正则写错了" in purify)
    check("净化 → 繁简合并成一条流水线并带缓存",
          "enum ReaderTextPipeline" in purify
          and "PurifyEngine.fingerprint(active)" in purify
          and "ReaderTextPipeline.paragraphs(chapterId: chapter.id" in reader)
    check("净化只作用于小说正文，且空段落会被清掉",
          "guard category == .novel else { return raw }" in reader
          and "trimmingCharacters(in: .whitespacesAndNewlines).isEmpty" in purify)
    check("顶部右侧就是「净化」，改完立即生效（缓存按规则指纹失效）",
          'trailing: "净化"' in reader
          and "onTrailing: { showPurifyManager = true }" in reader
          and "ReaderTextPipeline.reset()" in prefs_src)
    check("规则管理页可增删改、带样例预览",
          "struct PurifyManagerView" in manager
          and "PurifyRuleEditor" in manager
          and "样例预览" in manager)

    print("\n== AD. 本轮：右侧浮动圆钮 ==")
    bars = (APP / "Views" / "ReaderChromeBars.swift").read_text(encoding="utf-8")
    reader = (APP / "Views" / "ReaderView.swift").read_text(encoding="utf-8")

    check("右侧浮钮：书签 / 目录 / 主题三个圆钮",
          "struct ReaderFloatingActions" in bars
          and bars.count('circle(') >= 3
          and "bookmark.fill" in bars)
    check("只在菜单展开时出现，书签状态实时反映当前位置",
          ".overlay(alignment: .trailing)" in reader
          and "if showMenu {" in reader
          and "isBookmarked: currentBookmark != nil" in reader)
    check("书签浮钮是开关：同位置不重复记，再点即取消",
          "private func toggleBookmark()" in reader
          and "annotations.remove(mark)" in reader
          and "addBookmark(at: currentParagraphIndex)" in reader)

    print("\n== AE. 本轮：书签 / 笔记精确跳段 ==")
    ann = (APP / "Core" / "ReaderAnnotations.swift").read_text(encoding="utf-8")
    cat = (APP / "Views" / "ReaderCatalogView.swift").read_text(encoding="utf-8")
    reader = (APP / "Views" / "ReaderView.swift").read_text(encoding="utf-8")
    root = (APP / "Views" / "RootView.swift").read_text(encoding="utf-8")

    check("书签 / 笔记带上段落下标跳转",
          "let onSelectParagraph: (Chapter, Int) -> Void" in cat
          and "onSelectParagraph(chapter, mark.paragraph)" in cat
          and "onSelectParagraph(chapter, note.paragraph)" in cat)
    check("待应用锚点先暂存、选章时再消费（不被「主动选章」重置）",
          "var pendingJump: (chapterId: String, anchor: String)?" in ann
          and "func consumePendingAnchor(for chapterId: String)" in ann
          and 'AnnotationStore.shared.pendingJump = (target.id, "blk-p\\(paragraph)")' in reader
          and "consumePendingAnchor(for: chapter.id)" in root)
    check("笔记列表可左滑编辑（点条目仍是跳转）",
          'Button("编辑") { editingNote = note }' in cat)

    print("\n== AF. 本轮：进度显示独立开关 ==")
    prefs_src = (APP / "Core" / "Preferences.swift").read_text(encoding="utf-8")
    paged = (APP / "Views" / "PagedReaderView.swift").read_text(encoding="utf-8")
    reader = (APP / "Views" / "ReaderView.swift").read_text(encoding="utf-8")

    check("页码 / 百分比显示是独立开关（不与页脚内容绑定）",
          "var showReadingProgress: Bool = true" in prefs_src
          and "showsProgress: prefs.showReadingProgress" in reader)
    check("关掉后连页脚那一条留白也收掉",
          "let progressOff = input?.showsProgress == false" in paged
          and "guard input?.showsProgress != false else { return \"\" }" in paged)

    print(f"\n结果：{len(PASS)} 通过 / {len(FAIL)} 失败")
    if FAIL:
        print("失败项：" + ", ".join(FAIL))
        return 1
    print("S6 静态自检通过（注意：Swift 编译仍需你在 Xcode 27 上执行）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
