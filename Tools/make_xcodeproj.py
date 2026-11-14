#!/usr/bin/env python3
"""确定性生成 LocalNovel.xcodeproj（不手写 pbxproj）。
使用 Xcode 16+ 的 PBXFileSystemSynchronizedRootGroup：目录里的 .swift 自动同步，
无需为每个文件写 PBXFileReference / PBXBuildFile，显著降低工程文件出错概率。
同时生成 workspace 与共享 scheme，保证 Xcode 打开后可直接 Cmd+R。
"""
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parent.parent
PROJ = ROOT / "LocalNovel.xcodeproj"
APP_DIR = ROOT / "LocalNovel"
TEST_DIR = ROOT / "LocalNovelTests"


def ident(n: int) -> str:
    return f"AA{n:022d}"  # 24 位十六进制字符，确定性


# 对象 ID 分配
ID = {
    "app_product": ident(1),
    "test_product": ident(2),
    "app_sources": ident(3),
    "app_frameworks": ident(4),
    "app_resources": ident(5),
    "test_sources": ident(6),
    "test_frameworks": ident(7),
    "test_resources": ident(8),
    "exceptions": ident(10),
    "group_app": ident(11),
    "group_tests": ident(12),
    "app_target": ident(20),
    "test_target": ident(21),
    "main_group": ident(30),
    "products_group": ident(31),
    "project": ident(40),
    "project_config_list": ident(50),
    "app_config_list": ident(51),
    "test_config_list": ident(52),
    "cfg_project_debug": ident(60),
    "cfg_project_release": ident(61),
    "cfg_app_debug": ident(62),
    "cfg_app_release": ident(63),
    "cfg_test_debug": ident(64),
    "cfg_test_release": ident(65),
    "proxy": ident(70),
    "dependency": ident(71),
}

COMMON_PROJECT_SETTINGS = """
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CODE_SIGN_STYLE = Automatic;
				DEVELOPMENT_TEAM = "";
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				IPHONEOS_DEPLOYMENT_TARGET = 27.0;
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_STRICT_CONCURRENCY = minimal;
				SWIFT_VERSION = 5.0;
"""

APP_SETTINGS = """
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 2;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = LocalNovel/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 27.0;
				MARKETING_VERSION = 1.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.localnovel.reader;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
"""

TEST_SETTINGS = """
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 27.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.localnovel.reader.tests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/LocalNovel.app/LocalNovel";
"""


def build_pbxproj() -> str:
    a = ID
    return f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{a['proxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {a['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {a['app_target']};
			remoteInfo = LocalNovel;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
		{a['app_product']} /* LocalNovel.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LocalNovel.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{a['test_product']} /* LocalNovelTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = LocalNovelTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		{a['exceptions']} /* Exceptions for "LocalNovel" folder in "LocalNovel" target */ = {{
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = {a['app_target']} /* LocalNovel */;
		}};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{a['group_app']} /* LocalNovel */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				{a['exceptions']} /* PBXFileSystemSynchronizedBuildFileExceptionSet */,
			);
			path = LocalNovel;
			sourceTree = "<group>";
		}};
		{a['group_tests']} /* LocalNovelTests */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = LocalNovelTests;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{a['app_frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{a['test_frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{a['main_group']} = {{
			isa = PBXGroup;
			children = (
				{a['group_app']} /* LocalNovel */,
				{a['group_tests']} /* LocalNovelTests */,
				{a['products_group']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{a['products_group']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{a['app_product']} /* LocalNovel.app */,
				{a['test_product']} /* LocalNovelTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{a['app_target']} /* LocalNovel */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {a['app_config_list']} /* Build configuration list for PBXNativeTarget "LocalNovel" */;
			buildPhases = (
				{a['app_sources']} /* Sources */,
				{a['app_frameworks']} /* Frameworks */,
				{a['app_resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{a['group_app']} /* LocalNovel */,
			);
			name = LocalNovel;
			packageProductDependencies = (
			);
			productName = LocalNovel;
			productReference = {a['app_product']} /* LocalNovel.app */;
			productType = "com.apple.product-type.application";
		}};
		{a['test_target']} /* LocalNovelTests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {a['test_config_list']} /* Build configuration list for PBXNativeTarget "LocalNovelTests" */;
			buildPhases = (
				{a['test_sources']} /* Sources */,
				{a['test_frameworks']} /* Frameworks */,
				{a['test_resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{a['dependency']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{a['group_tests']} /* LocalNovelTests */,
			);
			name = LocalNovelTests;
			packageProductDependencies = (
			);
			productName = LocalNovelTests;
			productReference = {a['test_product']} /* LocalNovelTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{a['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastUpgradeCheck = 2700;
				TargetAttributes = {{
					{a['app_target']} = {{
						CreatedOnToolsVersion = 27.0;
					}};
					{a['test_target']} = {{
						CreatedOnToolsVersion = 27.0;
						TestTargetID = {a['app_target']};
					}};
				}};
			}};
			buildConfigurationList = {a['project_config_list']} /* Build configuration list for PBXProject "LocalNovel" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
				"zh-Hans",
			);
			mainGroup = {a['main_group']};
			preferredProjectObjectVersion = 77;
			productRefGroup = {a['products_group']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{a['app_target']} /* LocalNovel */,
				{a['test_target']} /* LocalNovelTests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{a['app_resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{a['test_resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{a['app_sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{a['test_sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{a['dependency']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {a['app_target']} /* LocalNovel */;
			targetProxy = {a['proxy']} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		{a['cfg_project_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{COMMON_PROJECT_SETTINGS}
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{a['cfg_project_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{COMMON_PROJECT_SETTINGS}
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{a['cfg_app_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{APP_SETTINGS}
			}};
			name = Debug;
		}};
		{a['cfg_app_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{APP_SETTINGS}
			}};
			name = Release;
		}};
		{a['cfg_test_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{TEST_SETTINGS}
			}};
			name = Debug;
		}};
		{a['cfg_test_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{TEST_SETTINGS}
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{a['project_config_list']} /* Build configuration list for PBXProject "LocalNovel" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{a['cfg_project_debug']} /* Debug */,
				{a['cfg_project_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{a['app_config_list']} /* Build configuration list for PBXNativeTarget "LocalNovel" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{a['cfg_app_debug']} /* Debug */,
				{a['cfg_app_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{a['test_config_list']} /* Build configuration list for PBXNativeTarget "LocalNovelTests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{a['cfg_test_debug']} /* Debug */,
				{a['cfg_test_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {a['project']} /* Project object */;
}}
"""


def check_pbxproj(text: str):
    """引用完整性 + 结构完整性自检"""
    defined = set(re.findall(
        r"^\t\t([A-F0-9]{24})(?:\s+/\*.*?\*/)?\s*=\s*\{", text, re.M
    ))
    referenced = set(re.findall(r"\b([A-F0-9]{24})\b", text))
    missing = referenced - defined
    assert not missing, f"未定义的对象引用: {sorted(missing)}"
    assert text.count("{") == text.count("}"), "花括号不配对"
    for section in re.findall(r"/\* Begin ([\w]+) section \*/", text):
        assert f"/* End {section} section */" in text, f"section 未闭合: {section}"
    assert "rootObject = " in text
    assert "objectVersion = 77" in text
    return len(defined)


def write_scheme():
    a = ID
    scheme_dir = PROJ / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    blueprint = f'BlueprintIdentifier = "{a["app_target"]}"'
    test_blueprint = f'BlueprintIdentifier = "{a["test_target"]}"'
    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" {blueprint} BuildableName="LocalNovel.app" BlueprintName="LocalNovel" ReferencedContainer="container:LocalNovel.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
         <TestableReference skipped="NO">
            <BuildableReference BuildableIdentifier="primary" {test_blueprint} BuildableName="LocalNovelTests.xctest" BlueprintName="LocalNovelTests" ReferencedContainer="container:LocalNovel.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" {blueprint} BuildableName="LocalNovel.app" BlueprintName="LocalNovel" ReferencedContainer="container:LocalNovel.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" {blueprint} BuildableName="LocalNovel.app" BlueprintName="LocalNovel" ReferencedContainer="container:LocalNovel.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"></ArchiveAction>
</Scheme>
"""
    (scheme_dir / "LocalNovel.xcscheme").write_text(xml, encoding="utf-8")


def main():
    app_swift = sorted(APP_DIR.rglob("*.swift"))
    test_swift = sorted(TEST_DIR.rglob("*.swift"))
    assert app_swift, "LocalNovel/ 下没有 Swift 源文件"
    assert test_swift, "LocalNovelTests/ 下没有测试文件"
    assert (APP_DIR / "Info.plist").is_file(), "缺少 Info.plist"

    if PROJ.exists():
        shutil.rmtree(PROJ)
    PROJ.mkdir(parents=True)

    text = build_pbxproj()
    count = check_pbxproj(text)
    (PROJ / "project.pbxproj").write_text(text, encoding="utf-8")

    ws = PROJ / "project.xcworkspace"
    ws.mkdir(parents=True, exist_ok=True)
    (ws / "contents.xcworkspacedata").write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<Workspace version = "1.0">
   <FileRef location = "self:">
   </FileRef>
</Workspace>
""", encoding="utf-8")

    write_scheme()

    print("已生成 LocalNovel.xcodeproj")
    print(f"  pbxproj 对象数：{count}，引用完整性 / 括号 / section 自检通过")
    print(f"  App Swift 源文件 {len(app_swift)} 个：")
    for p in app_swift:
        print("    ", p.relative_to(ROOT))
    print(f"  测试文件 {len(test_swift)} 个：")
    for p in test_swift:
        print("    ", p.relative_to(ROOT))


if __name__ == "__main__":
    sys.exit(main())
