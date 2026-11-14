#!/usr/bin/env bash
# 在 macOS + Xcode 27 上生成【未签名】ipa，供 Sideloadly / AltStore / iOS App Signer 自己重签。
#
# 用法：  bash Tools/build_unsigned_ipa.sh [输出路径]
# 默认：  build/LocalNovel-unsigned.ipa
#
# 为什么必须 macOS：ipa 里是编译好的 arm64 Mach-O，UIKit/SwiftUI/AVKit
# 只有 macOS 上的 iOS SDK 提供，Linux 无法编译/链接，也无法 codesign。
# 本脚本全程关闭签名，产物正好是「自己签名」需要的输入。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="${1:-$ROOT/build/LocalNovel-unsigned.ipa}"
ARCHIVE="$ROOT/build/LocalNovel.xcarchive"
STAGE="$ROOT/build/ipa_stage"
APP_NAME="LocalNovel.app"

echo "== 1/5 环境预检 =="
[[ "$(uname -s)" == "Darwin" ]] || { echo "❌ 只能在 macOS 上运行（需要 iOS SDK）"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "❌ 未找到 xcodebuild，请先安装 Xcode 27 并执行 sudo xcode-select -s ..."; exit 1; }

XCODE_VER="$(xcodebuild -version | head -1)"
MAJOR="$(xcodebuild -version | awk 'NR==1{print $2}' | cut -d. -f1)"
echo "   $XCODE_VER"
[[ "$MAJOR" -ge 27 ]] || {
  echo "❌ 需要 Xcode 27+：工程的 IPHONEOS_DEPLOYMENT_TARGET 是 27.0，低版本 SDK 无法编译。"
  exit 1
}

[[ -f LocalNovel.xcodeproj/project.pbxproj ]] || { echo "❌ 找不到 LocalNovel.xcodeproj"; exit 1; }
[[ -f LocalNovel/Info.plist ]] || { echo "❌ 找不到 LocalNovel/Info.plist"; exit 1; }
plutil -lint LocalNovel/Info.plist >/dev/null || { echo "❌ Info.plist 不合法"; exit 1; }

echo "== 2/5 清理旧产物 =="
rm -rf "$ARCHIVE" "$STAGE" "$(dirname "$OUT")/ipa_verify"
mkdir -p "$(dirname "$OUT")" "$STAGE/Payload"

echo "== 3/5 编译未签名 archive（arm64 真机二进制）=="
xcodebuild \
  -project LocalNovel.xcodeproj \
  -scheme LocalNovel \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -sdk iphoneos \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  clean archive

BUILT_APP="$ARCHIVE/Products/Applications/$APP_NAME"
[[ -d "$BUILT_APP" ]] || { echo "❌ archive 里没有 $APP_NAME"; exit 1; }
[[ -f "$BUILT_APP/LocalNovel" ]] || { echo "❌ 缺少可执行文件 LocalNovel"; exit 1; }

echo "== 4/5 打包成 ipa（Payload/ 结构）=="
# ditto 比 cp -R 更能保留 .app 里的符号链接与扩展属性
ditto "$BUILT_APP" "$STAGE/Payload/$APP_NAME"
(cd "$STAGE" && zip -q -r "$OUT" Payload)

echo "== 5/5 产物校验 =="
unzip -l "$OUT" | grep -q "Payload/$APP_NAME/LocalNovel" || { echo "❌ ipa 结构不对"; exit 1; }
file "$STAGE/Payload/$APP_NAME/LocalNovel" | grep -q "arm64" || {
  echo "❌ 不是 arm64 真机二进制（可能误编成模拟器）"; exit 1;
}
if codesign -dv "$STAGE/Payload/$APP_NAME" >/dev/null 2>&1; then
  echo "   ℹ️ 产物带签名（ad-hoc 或已有签名）；重签工具会覆盖，不影响使用"
else
  echo "   ✅ 未签名（符合预期）"
fi
echo "   $(file "$STAGE/Payload/$APP_NAME/LocalNovel")"

echo ""
echo "✅ 完成：$OUT"
echo "   体积：$(du -h "$OUT" | cut -f1)"
echo ""
echo "下一步（自己签名）：把该 ipa 拖进 Sideloadly / AltStore / iOS App Signer，"
echo "填入你的 Apple ID 重签并安装。免费账号签名有效期 7 天、最多同时 3 个 App，"
echo "iPhone 需开启「开发者模式」并在「VPN 与设备管理」里信任证书。"
