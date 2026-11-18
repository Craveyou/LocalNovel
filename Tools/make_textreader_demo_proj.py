#!/usr/bin/env python3
"""生成 TextReaderKitDemo.xcodeproj（TextReaderKit framework + TextReaderDemo App）。

沿用主工程的 PBXFileSystemSynchronizedRootGroup：目录里的 Swift / 资源自动同步，
不需要为每个文件写 PBXFileReference。工程对象 ID 确定性分配，便于自检。
"""
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parent.parent
KIT_DIR = ROOT / "TextReaderKit"
DEMO_DIR = ROOT / "TextReaderDemo"
PROJ = ROOT / "TextReaderKitDemo.xcodeproj"


def ident(n: int) -> str:
    return f"AA{n:022d}"


ID = {
    "kit_product": ident(1),
    "demo_product": ident(2),
    "kit_sources": ident(3),
    "demo_sources": ident(4),
    "kit_frameworks": ident(5),
    "demo_frameworks": ident(6),
    "kit_resources": ident(7),
    "demo_resources": ident(8),
    "copy_phase": ident(9),
    "kit_group": ident(11),
    "demo_group": ident(12),
    "products_group": ident(13),
    "kit_target": ident(20),
    "demo_target": ident(21),
    "main_group": ident(30),
    "project": ident(40),
    "project_config_list": ident(50),
    "kit_config_list": ident(51),
    "demo_config_list": ident(52),
    "cfg_project_debug": ident(60),
    "cfg_project_release": ident(61),
    "cfg_kit_debug": ident(62),
    "cfg_kit_release": ident(63),
    "cfg_demo_debug": ident(64),
    "cfg_demo_release": ident(65),
    "kit_link": ident(70),
    "kit_embed": ident(71),
    "proxy": ident(72),
    "dependency": ident(73),
}

COMMON = """
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CODE_SIGN_STYLE = Automatic;
				DEVELOPMENT_TEAM = "";
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 27.0;
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_STRICT_CONCURRENCY = minimal;
				SWIFT_VERSION = 5.0;
"""

KIT_SETTINGS = """
				CODE_SIGN_STYLE = Automatic;
				DEFINES_MODULE = YES;
				DYLIB_INSTALL_NAME_BASE = "@rpath";
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 27.0;
				MARKETING_VERSION = 1.0;
				CURRENT_PROJECT_VERSION = 5;
				PRODUCT_BUNDLE_IDENTIFIER = com.localnovel.textreaderkit;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
"""

DEMO_SETTINGS = """
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 5;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_CFBundleDisplayName = "TextReader Demo";
				IPHONEOS_DEPLOYMENT_TARGET = 27.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.localnovel.textreaderdemo;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
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
		{a['kit_link']} /* TextReaderKit.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {a['kit_product']} /* TextReaderKit.framework */; }};
		{a['kit_embed']} /* TextReaderKit.framework in Embed Frameworks */ = {{isa = PBXBuildFile; fileRef = {a['kit_product']} /* TextReaderKit.framework */; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{a['proxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {a['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {a['kit_target']};
			remoteInfo = TextReaderKit;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		{a['copy_phase']} /* Embed Frameworks */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 10;
			files = (
				{a['kit_embed']} /* TextReaderKit.framework in Embed Frameworks */,
			);
			name = "Embed Frameworks";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		{a['kit_product']} /* TextReaderKit.framework */ = {{isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = TextReaderKit.framework; sourceTree = BUILT_PRODUCTS_DIR; }};
		{a['demo_product']} /* TextReaderDemo.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TextReaderDemo.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{a['kit_group']} /* TextReaderKit */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = TextReaderKit;
			sourceTree = "<group>";
		}};
		{a['demo_group']} /* TextReaderDemo */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = TextReaderDemo;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{a['kit_frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{a['demo_frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{a['kit_link']} /* TextReaderKit.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{a['main_group']} = {{
			isa = PBXGroup;
			children = (
				{a['kit_group']} /* TextReaderKit */,
				{a['demo_group']} /* TextReaderDemo */,
				{a['products_group']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{a['products_group']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{a['kit_product']} /* TextReaderKit.framework */,
				{a['demo_product']} /* TextReaderDemo.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{a['kit_target']} /* TextReaderKit */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {a['kit_config_list']} /* Build configuration list for PBXNativeTarget "TextReaderKit" */;
			buildPhases = (
				{a['kit_sources']} /* Sources */,
				{a['kit_frameworks']} /* Frameworks */,
				{a['kit_resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{a['kit_group']} /* TextReaderKit */,
			);
			name = TextReaderKit;
			packageProductDependencies = (
			);
			productName = TextReaderKit;
			productReference = {a['kit_product']} /* TextReaderKit.framework */;
			productType = "com.apple.product-type.framework";
		}};
		{a['demo_target']} /* TextReaderDemo */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {a['demo_config_list']} /* Build configuration list for PBXNativeTarget "TextReaderDemo" */;
			buildPhases = (
				{a['demo_sources']} /* Sources */,
				{a['demo_frameworks']} /* Frameworks */,
				{a['demo_resources']} /* Resources */,
				{a['copy_phase']} /* Embed Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				{a['dependency']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{a['demo_group']} /* TextReaderDemo */,
			);
			name = TextReaderDemo;
			packageProductDependencies = (
			);
			productName = TextReaderDemo;
			productReference = {a['demo_product']} /* TextReaderDemo.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{a['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastUpgradeCheck = 2700;
				TargetAttributes = {{
					{a['kit_target']} = {{
						CreatedOnToolsVersion = 27.0;
					}};
					{a['demo_target']} = {{
						CreatedOnToolsVersion = 27.0;
					}};
				}};
			}};
			buildConfigurationList = {a['project_config_list']} /* Build configuration list for PBXProject "TextReaderKitDemo" */;
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
				{a['kit_target']} /* TextReaderKit */,
				{a['demo_target']} /* TextReaderDemo */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{a['kit_resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{a['demo_resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{a['kit_sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{a['demo_sources']} /* Sources */ = {{
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
			target = {a['kit_target']} /* TextReaderKit */;
			targetProxy = {a['proxy']} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		{a['cfg_project_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{COMMON}
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
{COMMON}
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{a['cfg_kit_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{KIT_SETTINGS}
			}};
			name = Debug;
		}};
		{a['cfg_kit_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{KIT_SETTINGS}
			}};
			name = Release;
		}};
		{a['cfg_demo_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{DEMO_SETTINGS}
			}};
			name = Debug;
		}};
		{a['cfg_demo_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{DEMO_SETTINGS}
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{a['project_config_list']} /* Build configuration list for PBXProject "TextReaderKitDemo" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{a['cfg_project_debug']} /* Debug */,
				{a['cfg_project_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{a['kit_config_list']} /* Build configuration list for PBXNativeTarget "TextReaderKit" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{a['cfg_kit_debug']} /* Debug */,
				{a['cfg_kit_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{a['demo_config_list']} /* Build configuration list for PBXNativeTarget "TextReaderDemo" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{a['cfg_demo_debug']} /* Debug */,
				{a['cfg_demo_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {a['project']} /* Project object */;
}}
"""


def check_pbxproj(text: str) -> int:
    defined = set(re.findall(r"^\t\t([A-F0-9]{24})(?:\s+/\*.*?\*/)?\s*=\s*\{", text, re.M))
    referenced = set(re.findall(r"\b([A-F0-9]{24})\b", text))
    missing = referenced - defined
    assert not missing, f"未定义的对象引用: {sorted(missing)}"
    assert text.count("{") == text.count("}"), "花括号不配对"
    for section in re.findall(r"/\* Begin ([\w]+) section \*/", text):
        assert f"/* End {section} section */" in text, f"section 未闭合: {section}"
    return len(defined)


def write_scheme():
    scheme_dir = PROJ / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    blueprint = f'BlueprintIdentifier = "{ID["demo_target"]}"'
    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" {blueprint} BuildableName="TextReaderDemo.app" BlueprintName="TextReaderDemo" ReferencedContainer="container:TextReaderKitDemo.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" {blueprint} BuildableName="TextReaderDemo.app" BlueprintName="TextReaderDemo" ReferencedContainer="container:TextReaderKitDemo.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" {blueprint} BuildableName="TextReaderDemo.app" BlueprintName="TextReaderDemo" ReferencedContainer="container:TextReaderKitDemo.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"></ArchiveAction>
</Scheme>
"""
    (scheme_dir / "TextReaderDemo.xcscheme").write_text(xml, encoding="utf-8")


def main():
    assert sorted(KIT_DIR.rglob("*.swift")), "TextReaderKit/ 下没有 Swift 文件"
    assert sorted(DEMO_DIR.rglob("*.swift")), "TextReaderDemo/ 下没有 Swift 文件"

    if PROJ.exists():
        shutil.rmtree(PROJ)
    PROJ.mkdir(parents=True)

    text = build_pbxproj()
    count = check_pbxproj(text)
    (PROJ / "project.pbxproj").write_text(text, encoding="utf-8")
    ws = PROJ / "project.xcworkspace"
    ws.mkdir(parents=True, exist_ok=True)
    (ws / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Workspace version = "1.0">\n   <FileRef location = "self:">\n   </FileRef>\n</Workspace>\n',
        encoding="utf-8")
    write_scheme()
    print("已生成 TextReaderKitDemo.xcodeproj")
    print(f"  pbxproj 对象数：{count}，引用完整性 / 括号 / section 自检通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
