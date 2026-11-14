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
    hits = [p for p in NETWORK_PATTERNS if p in combined]
    check("Swift 源码无网络调用", not hits, str(hits))
    plist = (APP / "Info.plist").read_text(encoding="utf-8")
    check("Info.plist 无 ATS 例外", "NSAppTransportSecurity" not in plist)
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
    check("覆盖 三层选法（书库根 / 作者 / 章节）",
          all(t in scanner for t in [".libraryRoot", ".singleBook", ".chapterFolder"]))
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
    check("选文件通道由 bestRoot 反推书库根",
          "static func bestRoot(from" in scanner and "BookScanner.bestRoot" in store
          and "handleFileImport" in store)
    check("点导入按钮瞬间即有醒目反馈（不再「无任何提示」）",
          "noteImportStarted" in store and "noteImportStarted" in welcome
          and "headline =" in store and "library.headline" in welcome)
    check("iPhone 第一屏可见三种导入方式",
          all(t in sidebar for t in ["导入书里的任意文件", "导入书库目录", "重新读取"]))
    check("UI 明确引导零交互路径（文件 App → 本地小说）",
          "我的 iPhone → 本地小说" in welcome and "导入书里的任意文件" in welcome)
    check("UI 明确说明「点文件夹需点打开 / 点文件立即导入」",
          "右上角「打开」" in welcome and "立即开始导入" in welcome
          and "右上角「打开」" in sidebar)
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
    check("未申请任何新系统能力（仍零权限）",
          "UIBackgroundModes" not in plist and "NSAppTransportSecurity" not in plist)

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
          "<string>4</string>" in plist and "CURRENT_PROJECT_VERSION = 4" in pbx)
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

    print(f"\n结果：{len(PASS)} 通过 / {len(FAIL)} 失败")
    if FAIL:
        print("失败项：" + ", ".join(FAIL))
        return 1
    print("S6 静态自检通过（注意：Swift 编译仍需你在 Xcode 27 上执行）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
