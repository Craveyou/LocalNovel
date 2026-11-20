#!/usr/bin/env bash
# 一键：取 OAuth token → 复用已存在仓库 → 推送 → GitHub Actions 编译 → 下载未签名 ipa
#
# 前置：在 https://github.com/new 新建【空】仓库（默认名 LocalNovel），
#       不要勾选初始化 README / .gitignore / License。
# 原因：当前 GitHub 集成令牌（ghu_）被平台禁止新建仓库
#       （403 Resource not accessible by integration），但可自由推送到已有仓库。
# 用法： bash Tools/upload_and_build.sh
# 可覆盖： REPO_NAME / RUNNER_LABEL
# 输出： build/LocalNovel-<版本>-b<build>-unsigned.ipa（另存一份最新副本 LocalNovel-unsigned.ipa）
#
# 安全：token 只通过环境变量引用，绝不打印（含 push 错误输出统一过滤）；
#       push 后立即从 git remote 清除；artifact 走重定向地址、不带 token。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKILL="/root/.codebuddy/skills/github-connector/scripts/get_token.sh"
REPO_NAME="${REPO_NAME:-LocalNovel}"
RUNNER="${RUNNER_LABEL:-macos-26}"
PY="$(command -v python3 || command -v python3.11 || true)"
[[ -n "$PY" ]] || { echo "❌ 需要 python3"; exit 1; }
API="https://api.github.com"

# 所有可能夹带 token 的输出统一过这层过滤
mask() {
  "$PY" -c "
import os, sys
t = os.environ.get('GITHUB_TOKEN', '')
s = sys.stdin.read()
sys.stdout.write(s.replace(t, '<隐藏>') if t else s)
"
}

# ---------- 1. 授权 ----------
# 连接器下发的 ghu_ 令牌是【只读】的（所有写操作 403 Resource not accessible by integration）。
# 因此优先使用用户提供的 PAT（classic，需 repo + workflow 权限）：
#   LN_GH_PAT      直接放环境变量
#   LN_GH_PAT_FILE 从文件读取（推荐，避免 token 出现在命令行 / 聊天记录）
# 两者都没有时退回连接器令牌，并在 push 阶段给出明确诊断。
# 有写权限凭据时走纯 API 通道：只需 api.github.com，绕开 git 直连 github.com 的超时
if [[ -n "${LN_GH_PAT:-}" || ( -n "${LN_GH_PAT_FILE:-}" && -f "${LN_GH_PAT_FILE:-}" ) ]]; then
  echo "== 检测到 PAT，改用纯 API 通道上传（不依赖 git 网络）=="
  exec "$PY" "$ROOT/Tools/upload_via_api.py"
fi

if [[ -f "$SKILL" ]]; then
  source "$SKILL" github >/dev/null 2>&1 || {
    echo "❌ 无法获取 GitHub token，请在 CodeBuddy 设置页「连接器」重新授权 GitHub"; exit 1; }
  echo "== 使用连接器令牌（只读）=="
fi
: "${GITHUB_TOKEN:?未获取到 GitHub token}"

AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json")
code=$(curl -sS -o /tmp/ln_user.json -w "%{http_code}" "${AUTH[@]}" "$API/user")
[[ "$code" == "200" ]] || {
  echo "❌ GitHub 授权无效 (HTTP $code)。请在 CodeBuddy 设置页「连接器」重新授权 GitHub。"
  exit 1
}
OWNER=$("$PY" -c "import json;print(json.load(open('/tmp/ln_user.json'))['login'])")
echo "== 账号 $OWNER / 目标仓库 $REPO_NAME =="

cleanup() {
  git remote set-url origin "https://github.com/${OWNER}/${REPO_NAME}.git" 2>/dev/null || true
}
trap cleanup EXIT

# ---------- 2. 复用已存在的仓库 ----------
code=$(curl -sS -o /tmp/ln_repo.json -w "%{http_code}" "${AUTH[@]}" \
  "$API/repos/${OWNER}/${REPO_NAME}")
if [[ "$code" != "200" ]]; then
  echo "❌ 仓库 ${OWNER}/${REPO_NAME} 尚不存在或不可访问 (HTTP $code)。"
  echo "   当前是 GitHub App 集成令牌，GitHub 禁止它新建仓库"
  echo "   （403 Resource not accessible by integration，私有/公开/组织均如此）。"
  echo "   请在 https://github.com/new 新建空仓库 ${REPO_NAME}，"
  echo "   不要初始化 README / .gitignore / License，然后重跑本脚本。"
  exit 1
fi
echo "   ✅ 仓库已存在，直接复用（不新建，规避集成令牌限制）"

# ---------- 3. 推送 ----------
echo "== 推送代码 =="
git init -q 2>/dev/null || true
git config user.name "LocalNovel Builder"
git config user.email "builder@local.invalid"
git add -A
git commit -q -m "build: 触发未签名 ipa 构建" || true
git branch -M main
git remote remove origin 2>/dev/null || true
git remote add origin "https://oauth2:${GITHUB_TOKEN}@github.com/${OWNER}/${REPO_NAME}.git"

if git push -u origin main >/tmp/ln_push.out 2>/tmp/ln_push.err; then
  { cat /tmp/ln_push.out; cat /tmp/ln_push.err; } | mask | tail -8
else
  echo "❌ push 失败："
  { cat /tmp/ln_push.out; cat /tmp/ln_push.err; } | mask | tail -25
  if grep -qiE 'workflow|GH006|refusing to allow' /tmp/ln_push.err; then
    echo ""
    echo "   诊断：集成令牌缺少写入 .github/workflows 的权限"
    echo "   （GitHub App 需要 workflows: write，多数集成未申请）。"
    echo "   处理：可改用带 repo + workflow 权限的 PAT，或在网页手动创建 workflow 文件。"
  fi
  exit 1
fi
cleanup
echo "   token 已从 git remote 清除"

# ---------- 4. 等待构建（push 自动触发；无 run 时 dispatch 兜底）----------
echo "== 等待构建（最长约 20 分钟）=="
RUN_ID=""; FINAL=""; DISPATCHED=false
for i in $(seq 1 60); do
  curl -sS -o /tmp/ln_runs.json "${AUTH[@]}" \
    "$API/repos/${OWNER}/${REPO_NAME}/actions/runs?per_page=10" || true
  read -r rid status conclusion < <("$PY" -c "
import json
try:
    d=json.load(open('/tmp/ln_runs.json'))
except Exception:
    d={}
runs=[r for r in d.get('workflow_runs',[]) if 'IPA' in (r.get('name') or '')]
r=(runs or d.get('workflow_runs') or [{}])[0]
print(r.get('id',''), r.get('status',''), r.get('conclusion') or 'pending')
") || true
  [[ -n "$rid" ]] && echo "   run $rid: $status / $conclusion"
  if [[ -n "$rid" && "$status" == "completed" ]]; then
    RUN_ID="$rid"; FINAL="$conclusion"; break
  fi
  # push 触发未出现时再手动 dispatch，避免与 push 重复构建、浪费 macOS 额度
  if [[ -z "$rid" && "$i" -ge 3 && "$DISPATCHED" == false ]]; then
    echo "   未检测到 push 触发，手动 dispatch 兜底（runner=$RUNNER）"
    curl -sS -o /tmp/ln_dispatch.json -w "   dispatch HTTP %{http_code}\n" -X POST "${AUTH[@]}" \
      -H "Content-Type: application/json" \
      "$API/repos/${OWNER}/${REPO_NAME}/actions/workflows/build-unsigned-ipa.yml/dispatches" \
      -d "{\"ref\":\"main\",\"inputs\":{\"runner\":\"${RUNNER}\"}}" || true
    DISPATCHED=true
  fi
  sleep 20
done

RUN_URL="https://github.com/${OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}"
[[ -n "$RUN_ID" ]] || { echo "❌ 等待超时，请查看 https://github.com/${OWNER}/${REPO_NAME}/actions"; exit 1; }
if [[ "$FINAL" != "success" ]]; then
  echo "❌ 构建失败：$FINAL"
  echo "   日志：$RUN_URL"
  # 失败时抓日志，便于定位 Xcode 版本 / 编译错误
  curl -sSL -o /tmp/ln_logs.zip "${AUTH[@]}" \
    "$API/repos/${OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}/logs" || true
  rm -rf /tmp/ln_logs && mkdir -p /tmp/ln_logs
  if unzip -q -o /tmp/ln_logs.zip -d /tmp/ln_logs 2>/dev/null; then
    echo "   --- 日志中的错误摘要 ---"
    grep -RhiE "::error::|error:|fatal:" /tmp/ln_logs 2>/dev/null | head -25 | mask || true
  fi
  exit 1
fi
echo "   ✅ 构建成功：$RUN_URL"

# ---------- 5. 下载 artifact ----------
echo "== 下载 ipa =="
curl -sS -o /tmp/ln_arts.json "${AUTH[@]}" \
  "$API/repos/${OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}/artifacts"
ART_ID=$("$PY" -c "
import json
d=json.load(open('/tmp/ln_arts.json'))
a=[x for x in d.get('artifacts',[]) if not x.get('expired')]
print(a[0]['id'] if a else '')
")
[[ -n "$ART_ID" ]] || { echo "❌ 未找到 artifact"; exit 1; }

# 先取重定向地址，再用不带 token 的请求下载，避免 token 被带到第三方存储域名
HEADERS=$(curl -sS -D - -o /dev/null "${AUTH[@]}" \
  "$API/repos/${OWNER}/${REPO_NAME}/actions/artifacts/${ART_ID}/zip")
LOC=$(printf '%s' "$HEADERS" | awk 'tolower($1)=="location:" {print $2}' | tr -d '\r' | tail -1)
rm -f /tmp/ln_art.zip
if [[ -n "$LOC" ]]; then
  curl -sSL -o /tmp/ln_art.zip "$LOC"
else
  curl -sSL -o /tmp/ln_art.zip "${AUTH[@]}" \
    "$API/repos/${OWNER}/${REPO_NAME}/actions/artifacts/${ART_ID}/zip"
fi
rm -rf /tmp/ln_art && mkdir -p /tmp/ln_art
unzip -q -o /tmp/ln_art.zip -d /tmp/ln_art
IPA="$(find /tmp/ln_art -name '*.ipa' -type f -print -quit)"
[[ -n "$IPA" ]] || { echo "❌ artifact 里没有 ipa"; exit 1; }
mkdir -p "$ROOT/build"
# 命名规范：产物名带版本号（取自下载到的 ipa 内 Info.plist）
LABEL="$(unzip -p "$IPA" 'Payload/*/Info.plist' 2>/dev/null \
  | python3 -c 'import sys,plistlib; p=plistlib.loads(sys.stdin.buffer.read()); print("%s-b%s" % (p.get("CFBundleShortVersionString","0"), p.get("CFBundleVersion","0")))' \
  2>/dev/null || echo unknown)"
OUT_IPA="$ROOT/build/LocalNovel-${LABEL}-unsigned.ipa"
cp "$IPA" "$OUT_IPA"
cp "$IPA" "$ROOT/build/LocalNovel-unsigned.ipa"

echo ""
echo "✅ 完成：$OUT_IPA"
echo "   最新副本：$ROOT/build/LocalNovel-unsigned.ipa"
echo "   体积：$(du -h "$OUT_IPA" | cut -f1)"
unzip -l "$OUT_IPA" | head -8
echo ""
echo "下一步：把该 ipa 拖进 Sideloadly / AltStore，用你的 Apple ID 重签安装。"
echo "免费账号签名 7 天有效；iPhone 需开启开发者模式并信任证书。"
