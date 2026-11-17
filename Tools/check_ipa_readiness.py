#!/usr/bin/env python3
"""打包就绪检查：在【没有 Xcode 的环境】里也能真跑，验证工程是否具备产出 ipa 的条件。

它不能编译 Swift，也不假装能编译；只核对构建链需要的所有配置与交付脚本完整性。
用在本地 Mac 打包前，或 GitHub Actions workflow 的第一步。
"""
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import xml.dom.minidom as minidom

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "LocalNovel"
PROJ = ROOT / "LocalNovel.xcodeproj"
TOOLS = ROOT / "Tools"
WORKFLOW = ROOT / ".github" / "workflows" / "build-unsigned-ipa.yml"

PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(f"  [{'PASS' if cond else 'FAIL'}] {name}" + (f"  -> {detail}" if detail else ""))


def main():
    print("== 工程打包就绪检查（不需要 Xcode）==\n")

    print("-- A. 工程文件 --")
    files = {
        "pbxproj": PROJ / "project.pbxproj",
        "workspace": PROJ / "project.xcworkspace" / "contents.xcworkspacedata",
        "scheme": PROJ / "xcshareddata" / "xcschemes" / "LocalNovel.xcscheme",
        "Info.plist": APP / "Info.plist",
        "打包脚本": TOOLS / "build_unsigned_ipa.sh",
        "CI workflow": WORKFLOW,
    }
    for label, p in files.items():
        check(f"{label} 存在", p.is_file(), str(p.relative_to(ROOT)))

    pbx = (files["pbxproj"]).read_text(encoding="utf-8")
    check("pbxproj 花括号配对", pbx.count("{") == pbx.count("}"))
    check("pbxproj 使用文件同步组（新增 Swift 自动纳入产物）",
          "PBXFileSystemSynchronizedRootGroup" in pbx)
    check("无 Swift Package 第三方依赖", "packageProductDependencies = (\n\t\t\t);" in pbx
          or "XCSwiftPackageProductDependency" not in pbx)

    print("\n-- B. 构建设置（决定能否编出 arm64 真机包）--")
    settings = {
        "部署目标 iOS 27": "IPHONEOS_DEPLOYMENT_TARGET = 27.0",
        "真机 SDK": "SDKROOT = iphoneos",
        "Bundle ID": "PRODUCT_BUNDLE_IDENTIFIER = com.localnovel.reader",
        "iPhone + iPad": 'TARGETED_DEVICE_FAMILY = "1,2"',
        "使用自定义 Info.plist": "GENERATE_INFOPLIST_FILE = NO",
        "Info.plist 路径": "INFOPLIST_FILE = LocalNovel/Info.plist",
    }
    for label, token in settings.items():
        check(label, token in pbx, token)
    check("签名方式为 Automatic（打包脚本会临时关闭）", "CODE_SIGN_STYLE = Automatic" in pbx)

    print("\n-- C. Info.plist --")
    with open(files["Info.plist"], "rb") as f:
        plist = plistlib.load(f)
    need_keys = ["CFBundleIdentifier", "CFBundleExecutable", "CFBundlePackageType",
                 "CFBundleShortVersionString", "UILaunchScreen",
                 "UIApplicationSceneManifest"]
    check("必备键齐全", all(k in plist for k in need_keys),
          str([k for k in need_keys if k not in plist]))
    check("Bundle ID 由构建设置注入", plist.get("CFBundleIdentifier") == "$(PRODUCT_BUNDLE_IDENTIFIER)")
    check("声明 arm64", "arm64" in plist.get("UIRequiredDeviceCapabilities", []))
    check("无后台/画中画权限，只加 NAS 需要的本地网络权限",
          "UIBackgroundModes" not in plist
          and plist.get("NSLocalNetworkUsageDescription") is not None
          and plist.get("NSAppTransportSecurity", {}).get("NSAllowsArbitraryLoads") is True)
    check("声明 iPad 多窗口", plist.get("UIApplicationSceneManifest", {})
          .get("UIApplicationSupportsMultipleScenes") is True)
    check("含 UISceneConfigurations（避免启动黑屏）",
          "UISceneConfigurations" in plist.get("UIApplicationSceneManifest", {}))

    print("\n-- C2. 文件 App 目录可见 / App 图标 --")
    check("文件共享与就地打开均开启",
          plist.get("UIFileSharingEnabled") is True
          and plist.get("LSSupportsOpeningDocumentsInPlace") is True)
    check("Documents 说明文件引导（Apple 要求目录里至少一个文件）",
          (APP / "Core" / "DocumentsBootstrap.swift").is_file())
    check("版本号提升以刷新系统元数据",
          plist.get("CFBundleVersion") == "9" and plist.get("CFBundleShortVersionString") == "2.11.8")
    check("CFBundleIcons 声明图标文件",
          "CFBundleIconFiles" in plist.get("CFBundleIcons", {})
          .get("CFBundlePrimaryIcon", {}))
    icon_set = APP / "Assets.xcassets" / "AppIcon.appiconset"
    check("AppIcon asset catalog 存在",
          (icon_set / "Contents.json").is_file() and (icon_set / "AppIcon.png").is_file())
    check("散装图标 PNG 覆盖 iPhone / iPad 主屏尺寸",
          all((APP / f"AppIcon-{s}.png").is_file() for s in (120, 152, 167, 180)))
    check("构建设置指向 AppIcon asset",
          "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon" in pbx)
    check("CI 断言 Assets.car 编译结果",
          "Assets.car" in files["CI workflow"].read_text(encoding="utf-8"))

    print("\n-- D. XML / 脚本 / CI 配置 --")
    for label, key in [("scheme", "scheme"), ("workspace", "workspace")]:
        try:
            minidom.parse(str(files[key]))
            check(f"{label} XML 合法", True)
        except Exception as exc:  # noqa: BLE001
            check(f"{label} XML 合法", False, str(exc))

    script = files["打包脚本"].read_text(encoding="utf-8")
    check("打包脚本关闭签名（未签名 ipa 是自己重签的输入）",
          all(t in script for t in ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
                                    "CODE_SIGN_IDENTITY=\"\""]))
    check("打包脚本产出标准 Payload/ 结构", "Payload" in script and "zip -q -r" in script)
    check("打包脚本校验 arm64 二进制", "grep -q \"arm64\"" in script)
    bash = subprocess.run(["bash", "-n", str(files["打包脚本"])],
                          capture_output=True, text=True)
    check("打包脚本 bash 语法通过", bash.returncode == 0, bash.stderr.strip())

    wf = files["CI workflow"].read_text(encoding="utf-8")
    check("workflow 默认使用 xcode-27 镜像（含 iOS 27 SDK）",
          "runs-on:" in wf and "xcode-27" in wf
          and "github.event.inputs.runner || 'xcode-27'" in wf)
    check("workflow 断言 Xcode 27", "MAJOR" in wf and "-ge 27" in wf)
    check("workflow 关闭签名、不接触 Apple 账号",
          "CODE_SIGNING_ALLOWED=NO" in wf and "DEVELOPMENT_TEAM=\"\"" in wf)
    check("workflow 上传 ipa 产物", "actions/upload-artifact@v4" in wf)
    try:
        import yaml  # type: ignore
        yaml.safe_load(wf.replace("on:", '"on":'))
        check("workflow YAML 语法通过", True)
    except ImportError:
        check("workflow YAML 关键结构完整（未装 PyYAML，做文本核对）",
              all(t in wf for t in ["jobs:", "steps:", "uses:", "run:"]))
    except Exception as exc:  # noqa: BLE001
        check("workflow YAML 语法通过", False, str(exc))

    upload = TOOLS / "upload_and_build.sh"
    check("上传 + 构建脚本存在", upload.is_file())
    if upload.is_file():
        up = upload.read_text(encoding="utf-8")
        check("上传脚本只在环境变量里引用 token（不打印）",
              "${GITHUB_TOKEN}" in up and "echo ${GITHUB_TOKEN}" not in up)
        check("上传脚本 push 后清除 remote 里的 token",
              "git remote set-url origin" in up and "trap cleanup EXIT" in up)
        check("上传脚本覆盖 复用仓库/推送/触发/轮询/下载",
              all(t in up for t in ["/repos/${OWNER}/${REPO_NAME}", "git push", "dispatches",
                                    "actions/runs", "artifacts"]))
        check("集成令牌限制：仓库需预先创建并给出指引",
              "Resource not accessible by integration" in up and "github.com/new" in up)
        check("上传脚本对 push 输出做 token 脱敏", "mask" in up and "mask | tail" in up)
        b2 = subprocess.run(["bash", "-n", str(upload)], capture_output=True, text=True)
        check("上传脚本 bash 语法通过", b2.returncode == 0, b2.stderr.strip())

    swift = sorted(APP.rglob("*.swift"))
    check("Swift 源文件已就位", len(swift) >= 24, f"{len(swift)} 个")

    print(f"\n结果：{len(PASS)} 通过 / {len(FAIL)} 失败")
    if FAIL:
        print("失败项：" + ", ".join(FAIL))
        return 1
    print("✅ 工程打包就绪。注意：真正的编译仍需 macOS + Xcode 27，")
    print("   在 Mac 上执行 `bash Tools/build_unsigned_ipa.sh`，或用 CI workflow 产出 ipa。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
