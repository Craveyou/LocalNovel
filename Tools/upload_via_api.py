#!/usr/bin/env python3
"""纯 GitHub REST API 上传工程 → 触发 Actions → 下载未签名 ipa。

与 upload_and_build.sh 的区别：全程只用 api.github.com，不调用 git、不访问
github.com:443（沙箱对该地址不稳定），因此只要有【写权限凭据】就能跑通。

写权限凭据（二选一，绝不打印、绝不写入仓库）：
  LN_GH_PAT       环境变量，值为 classic PAT
  LN_GH_PAT_FILE  文件路径，文件内容为 classic PAT（推荐）
PAT 需要勾选 repo + workflow（更新 .github/workflows 必须有 workflow scope）。

用法： LN_GH_PAT_FILE=/path/to/token.txt python3 Tools/upload_via_api.py
输出： build/LocalNovel-<版本>-b<build>-unsigned.ipa（另存一份 LocalNovel-unsigned.ipa 作为最新副本）
"""
import base64
import concurrent.futures
import io
import json
import os
import plistlib
import re
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = "https://api.github.com"
REPO_NAME = os.environ.get("REPO_NAME", "LocalNovel")
RUNNER = os.environ.get("RUNNER_LABEL", "xcode-27")

# 不上传的目录/文件
EXCLUDE_DIRS = {".git", "build", "__pycache__", ".DS_Store"}
EXCLUDE_FILES = {".DS_Store"}


def load_token():
    t = os.environ.get("LN_GH_PAT", "").strip()
    if not t:
        f = os.environ.get("LN_GH_PAT_FILE", "")
        if f and os.path.isfile(f):
            t = open(f, encoding="utf-8").read().strip()
    if not t:
        # 退回连接器令牌（只读，仅用于给出清晰诊断）
        t = os.environ.get("GITHUB_TOKEN", "").strip()
    return t


TOKEN = load_token()


def require_token():
    """只在真正要联网的分支检查凭据：--unpack-only 纯本地操作，不该被拦。"""
    if not TOKEN:
        print("❌ 未找到凭据。请设置 LN_GH_PAT 或 LN_GH_PAT_FILE 指向含 classic PAT 的文件")
        print("   （PAT 需勾选 repo + workflow；本连接器令牌为只读，无法写入）")
        sys.exit(1)


def call(method, path, payload=None, raw=False, timeout=30):
    url = path if path.startswith("http") else API + path
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "LocalNovel-Builder")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read()
            if raw:
                return r.status, body, dict(r.headers)
            return r.status, (json.loads(body) if body else {}), dict(r.headers)
    except urllib.error.HTTPError as e:
        body = e.read()
        try:
            parsed = json.loads(body)
        except Exception:
            parsed = {}
        return e.code, (body if raw else parsed), dict(e.headers)
    except Exception as e:
        return -1, (b"" if raw else {"error": str(e)}), {}


def safe(obj):
    """输出前脱敏"""
    return str(obj).replace(TOKEN, "<隐藏>")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """禁止 urlopen 自动跟随 302，否则 Authorization 头会被带到签名 URL。"""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_NO_REDIRECT = urllib.request.build_opener(_NoRedirect())


def get_with_redirect(path, timeout=300, retries=4):
    """GET 可能返回 302 的下载端点；重定向后用【不带凭据】的请求取回内容。

    artifact 的签名地址有效期短，大文件下载也容易读超时。失败时重新向 API
    申请一个新的签名地址再试，避免整轮编译白跑（编译成功却拿不到 ipa）。
    """
    url = path if path.startswith("http") else API + path
    last = ""
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(url, headers={
            "Authorization": "Bearer " + TOKEN,
            "Accept": "application/vnd.github+json",
            "User-Agent": "LocalNovel-Builder",
        })
        loc = ""
        try:
            with _NO_REDIRECT.open(req, timeout=30) as r:
                return 200, r.read()
        except urllib.error.HTTPError as e:
            if e.code not in (301, 302, 303, 307, 308):
                return e.code, e.read()
            loc = e.headers.get("Location") or ""
            if not loc:
                return e.code, e.read()
        except Exception as e:  # noqa: BLE001
            last = f"取下载地址失败：{type(e).__name__}"
        if loc:
            try:
                clean = urllib.request.Request(
                    loc, headers={"User-Agent": "LocalNovel-Builder"})
                with urllib.request.urlopen(clean, timeout=timeout) as r:
                    return 200, r.read()
            except Exception as e:  # noqa: BLE001
                last = f"第 {attempt}/{retries} 次下载失败：{type(e).__name__}"
        print("   " + (last or "下载失败") + "，重试…")
        time.sleep(3)
    return -1, (last or "下载失败").encode()


def ipa_version_label(data):
    """从 ipa 内的 Info.plist 读真实版本；读不到就退回工程里的 Info.plist。"""
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            for n in z.namelist():
                if n.endswith("Info.plist") and n.startswith("Payload/"):
                    p = plistlib.loads(z.read(n))
                    v = str(p.get("CFBundleShortVersionString") or "").strip()
                    b = str(p.get("CFBundleVersion") or "").strip()
                    if v:
                        return f"{v}-b{b}" if b else v
    except Exception:
        pass
    try:
        with open(os.path.join(ROOT, "LocalNovel", "Info.plist"), "rb") as f:
            p = plistlib.load(f)
        v = str(p.get("CFBundleShortVersionString") or "0").strip()
        b = str(p.get("CFBundleVersion") or "").strip()
        return f"{v}-b{b}" if b else v
    except Exception:
        return "unknown"


def install_ipa_from_zip(zip_path):
    """从 artifact zip 里取出 ipa，按真实版本命名写进 build/，另留固定名副本。"""
    blob = Path(zip_path).read_bytes()
    ipa_bytes = None
    try:
        with zipfile.ZipFile(io.BytesIO(blob)) as z:
            for name in z.namelist():
                if name.lower().endswith(".ipa"):
                    ipa_bytes = z.read(name)
                    break
    except zipfile.BadZipFile:
        print("❌ artifact zip 不是合法压缩包（可能拿到了错误页）")
        return None
    if not ipa_bytes:
        print("❌ artifact 里没有 ipa")
        return None

    # 命名规范：LocalNovel-<版本>-b<build>-unsigned.ipa，避免多版本混在一个名字里
    label = ipa_version_label(ipa_bytes)
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    out_path = os.path.join(ROOT, "build", f"LocalNovel-{label}-unsigned.ipa")
    with open(out_path, "wb") as f:
        f.write(ipa_bytes)
    # 同时留一份不带版本号的固定名，方便老的安装习惯与脚本引用
    alias_path = os.path.join(ROOT, "build", "LocalNovel-unsigned.ipa")
    with open(alias_path, "wb") as f:
        f.write(ipa_bytes)
    print(f"\n✅ 完成：{out_path}（{len(ipa_bytes) / 1024:.0f} KB）")
    print(f"   最新副本：{alias_path}")
    with zipfile.ZipFile(io.BytesIO(ipa_bytes)) as z:
        for n in z.namelist()[:8]:
            print("   " + n)
    print("\n下一步：把该 ipa 拖进 Sideloadly / AltStore，用你的 Apple ID 重签安装。")
    return out_path


def download_artifact_resumable(path, dest, rounds=100):
    """断点续传下载 artifact：每轮刷新签名地址，用 Range 从已落盘偏移继续。

    artifact 的签名地址有效期很短，对象存储对大文件读也很慢，一次性 GET
    常在几分钟后超时。这里按 64KB 分块立即落盘，中断后换地址续传，
    直到 zip 的中央目录完整可解析。
    """
    dest = Path(dest)
    # Windows 没有 /tmp：父目录不存在时 open() 会 FileNotFoundError，先建好
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and zipfile.is_zipfile(dest):
        return True
    pos = dest.stat().st_size if dest.exists() else 0
    url = path if path.startswith("http") else API + path
    stalled = 0
    for round_no in range(1, rounds + 1):
        before = pos
        loc = ""
        req = urllib.request.Request(url, headers={
            "Authorization": "Bearer " + TOKEN,
            "Accept": "application/vnd.github+json",
            "User-Agent": "LocalNovel-Builder"})
        try:
            with _NO_REDIRECT.open(req, timeout=30) as r:
                # 极少数情况下 API 直接返回内容
                dest.write_bytes(r.read())
                return zipfile.is_zipfile(dest)
        except urllib.error.HTTPError as e:
            if e.code not in (301, 302, 303, 307, 308):
                print(f"   取地址 HTTP {e.code}，重试…")
                time.sleep(2)
                continue
            loc = e.headers.get("Location") or ""
        except Exception as e:  # noqa: BLE001
            print(f"   取地址失败 {type(e).__name__}，重试…")
            time.sleep(2)
            continue
        if not loc:
            time.sleep(2)
            continue
        try:
            clean = urllib.request.Request(loc, headers={
                "User-Agent": "LocalNovel-Builder",
                "Range": f"bytes={pos}-"})
            with urllib.request.urlopen(clean, timeout=90) as r:
                mode = "ab" if pos else "wb"
                if r.status == 200:  # 服务端不支持 Range，从头写
                    pos, mode = 0, "wb"
                elif r.status == 206:
                    cr = r.headers.get("Content-Range") or ""
                    start = cr.rsplit(" ", 1)[-1].split("-")[0]
                    if start.isdigit() and int(start) != pos:
                        pos, mode = 0, "wb"
                with open(dest, mode) as f:
                    while True:
                        chunk = r.read(65536)
                        if not chunk:
                            break
                        f.write(chunk)
                        f.flush()
                        pos += len(chunk)
        except Exception as e:  # noqa: BLE001
            print(f"   第 {round_no} 轮中断 {type(e).__name__}，已落盘 {pos} 字节，续传…")
            time.sleep(2)
        if dest.exists() and zipfile.is_zipfile(dest):
            print(f"   ✅ 下载完成：{pos} 字节")
            return True
        stalled = stalled + 1 if pos == before else 0
        if stalled >= 3:  # 卡住就从头再来
            dest.unlink(missing_ok=True)
            pos, stalled = 0, 0
    return False


# 只下载模式：编译已成功但下载失败时，不必重跑整轮编译
if len(sys.argv) >= 3 and sys.argv[1] == "--download-only":
    require_token()
    _art = sys.argv[2]
    _out = (sys.argv[3] if len(sys.argv) > 3
            else os.path.join(tempfile.gettempdir(), f"ln_artifact-{_art}.zip"))
    _code, _u, _ = call("GET", "/user")
    _owner = _u.get("login", "")
    _repo = os.environ.get("REPO_NAME", "LocalNovel")
    print(f"== 断点续传下载 artifact {_art} ==")
    ok = download_artifact_resumable(
        f"/repos/{_owner}/{_repo}/actions/artifacts/{_art}/zip", _out)
    sys.exit(0 if ok else 1)

# 只解包模式：zip 已经在本地，直接取出 ipa 落盘（CI 成功后不必再下载一次）
if len(sys.argv) >= 3 and sys.argv[1] == "--unpack-only":
    sys.exit(0 if install_ipa_from_zip(sys.argv[2]) else 1)


# ---------- 1. 身份与仓库 ----------
require_token()
code, user, _ = call("GET", "/user")
if code != 200:
    print(f"❌ 授权无效 (HTTP {code}): {safe(user.get('message'))}")
    sys.exit(1)
OWNER = user["login"]
REPO = f"/repos/{OWNER}/{REPO_NAME}"
print(f"== 账号 {OWNER} / 仓库 {REPO_NAME} ==")

code, info, _ = call("GET", REPO)
if code != 200:
    print(f"❌ 仓库不可访问 (HTTP {code}): {safe(info.get('message'))}")
    print("   请在 https://github.com/new 新建空仓库（不要初始化任何文件）")
    sys.exit(1)
print("   ✅ 仓库存在")

# ---------- 2. 收集文件 ----------
files = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
    for name in filenames:
        if name in EXCLUDE_FILES or name.endswith(".pyc"):
            continue
        full = os.path.join(dirpath, name)
        rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
        files.append((rel, full))
files.sort()
print(f"== 待上传 {len(files)} 个文件 ==")

# ---------- 2.5 空仓库引导 ----------
# Git Data API 在「零 commit」的仓库上创建 blob 会返回 409 "Git Repository is empty"；
# 先用 Contents API 提交一个初始文件，把 git 对象库和 main 分支 bootstrap 出来。
code, ref0, _ = call("GET", REPO + "/git/ref/heads/main")
if code != 200:
    # 空仓库时该接口可能返回 404 或 409("Git Repository is empty")，均需先 bootstrap
    print(f"== main ref 不可读 (HTTP {code})，Contents API 引导初始 commit ==")
    seed = base64.b64encode(b"# LocalNovel\n").decode("ascii")
    c, body, _ = call("PUT", REPO + "/contents/README.md",
                      {"message": "init: 初始化空仓库", "content": seed})
    if c not in (200, 201):
        print(f"❌ 初始化失败 (HTTP {c}): {safe(body.get('message') if isinstance(body, dict) else body)}")
        sys.exit(1)
    # 回读确认 main 已建立
    c2, ref2, _ = call("GET", REPO + "/git/ref/heads/main")
    if c2 != 200:
        print(f"❌ 初始化后仍读不到 main (HTTP {c2})，请检查 PAT 的 repo 权限")
        sys.exit(1)
    print("   ✅ 初始 commit 完成，main 分支已建立")

# ---------- 3. 创建 blob ----------
def make_blob(item):
    rel, full = item
    with open(full, "rb") as f:
        content = base64.b64encode(f.read()).decode("ascii")
    payload = {"content": content, "encoding": "base64"}
    # 403/429 多为 secondary rate limit；-1 为网络瞬断（连接重置 / 读超时）。
    # 单例抖动不该让整轮上传失败，统一退避重试并放宽单次超时。
    for attempt in range(5):
        c, body, _ = call("POST", REPO + "/git/blobs", payload, timeout=60)
        if c in (200, 201) and "sha" in body:
            return rel, c, body
        if c in (403, 429, 502, 503, 504, -1):
            time.sleep(2 * (attempt + 1))
            continue
        break
    return rel, c, body


tree = []
failed = []
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
    for rel, c, body in ex.map(make_blob, files):
        if c in (200, 201) and "sha" in body:
            mode = "100755" if rel.endswith(".sh") else "100644"
            tree.append({"path": rel, "mode": mode, "type": "blob", "sha": body["sha"]})
        else:
            failed.append((rel, c, safe(body.get("message") if isinstance(body, dict) else body)))

if failed:
    print(f"❌ {len(failed)} 个 blob 创建失败，例如：")
    for rel, c, msg in failed[:5]:
        print(f"   {rel}: HTTP {c} | {msg}")
    if any(c in (403, 401) for _, c, _ in failed):
        print("   诊断：凭据缺少 contents: write。请确认 PAT 勾选了 repo，")
        print("   且若为 fine-grained PAT，需把该仓库加入 repository access。")
    sys.exit(1)
print(f"   ✅ {len(tree)} 个 blob")

# ---------- 4. tree → commit → ref ----------
code, treesha, _ = call("POST", REPO + "/git/trees", {"tree": tree})
if code not in (200, 201):
    print(f"❌ 创建 tree 失败 (HTTP {code}): {safe(treesha.get('message'))}")
    sys.exit(1)

# 空仓库无父提交；若已有 main 则沿用
parents = []
code, ref, _ = call("GET", REPO + "/git/ref/heads/main")
ref_exists = code == 200
if ref_exists:
    parents = [ref["object"]["sha"]]

code, commit, _ = call("POST", REPO + "/git/commits", {
    "message": "build: 上传工程并触发未签名 ipa 构建",
    "tree": treesha["sha"],
    "parents": parents,
})
if code not in (200, 201):
    print(f"❌ 创建 commit 失败 (HTTP {code}): {safe(commit.get('message'))}")
    sys.exit(1)

if ref_exists:
    code, out, _ = call("PATCH", REPO + "/git/refs/heads/main", {"sha": commit["sha"]})
else:
    code, out, _ = call("POST", REPO + "/git/refs",
                        {"ref": "refs/heads/main", "sha": commit["sha"]})
if code not in (200, 201):
    print(f"❌ 更新 main 失败 (HTTP {code}): {safe(out.get('message'))}")
    if "workflow" in safe(out.get("message", "")).lower():
        print("   诊断：更新 .github/workflows 需要 PAT 勾选 workflow scope。")
    sys.exit(1)
PUSHED_SHA = commit["sha"]
print(f"   ✅ 已推送 main（commit {PUSHED_SHA[:8]}），push 事件将自动触发 CI")

# ---------- 5. 等待构建 ----------
# 只认【本次 commit sha】触发的 run：仓库里可能残留历史失败 run，
# 若按「第一个 IPA run」取，会误判成旧的 failure 而提前退出。
print("== 等待构建（最长约 20 分钟）==")
run_id, final, dispatched = "", "", False
for i in range(60):
    code, runs, _ = call("GET", REPO + f"/actions/runs?per_page=20")
    all_runs = runs.get("workflow_runs", [])
    candidates = [r for r in all_runs
                  if r.get("head_sha") == PUSHED_SHA and "IPA" in (r.get("name") or "")]
    r = candidates[0] if candidates else {}
    rid, status = r.get("id", ""), r.get("status", "")
    conclusion = r.get("conclusion") or "pending"
    if rid:
        print(f"   run {rid}: {status} / {conclusion}")
    elif i == 0:
        print("   等待本次 commit 的 run 出现…")
    if rid and status == "completed":
        run_id, final = rid, conclusion
        break
    if not rid and i >= 1 and not dispatched:
        print(f"   未检测到 push 触发，dispatch 兜底（runner={RUNNER}）")
        c, dbody, _ = call("POST", REPO + "/actions/workflows/build-unsigned-ipa.yml/dispatches",
                           {"ref": "main", "inputs": {"runner": RUNNER}})
        print(f"   dispatch HTTP {c}")
        # 只有 2xx 才算触发成功；404/422 多为 workflow 尚未被索引，下一轮重试
        if c in (200, 201, 204):
            dispatched = True
        else:
            msg = dbody.get("message") if isinstance(dbody, dict) else dbody
            print(f"   dispatch 未成功，稍后重试：{safe(msg)}")
    time.sleep(20)

run_url = f"https://github.com/{OWNER}/{REPO_NAME}/actions/runs/{run_id}"
if not run_id:
    print(f"❌ 等待超时，请查看 https://github.com/{OWNER}/{REPO_NAME}/actions")
    sys.exit(1)
if final != "success":
    print(f"❌ 构建失败：{final}\n   日志：{run_url}")
    c, blob = get_with_redirect(REPO + f"/actions/runs/{run_id}/logs", timeout=60)
    if c == 200 and blob:
        try:
            with zipfile.ZipFile(io.BytesIO(blob)) as z:
                hits = []
                for n in z.namelist():
                    text = z.read(n).decode("utf-8", "replace")
                    hits += [l.strip() for l in text.splitlines()
                             if re.search(r"::error::|error:|fatal:", l, re.I)]
                for line in hits[:25]:
                    print("   " + safe(line))
        except Exception:
            pass
    sys.exit(1)
print(f"   ✅ 构建成功：{run_url}")

# ---------- 6. 下载 artifact ----------
print("== 下载 ipa ==")
code, arts, _ = call("GET", REPO + f"/actions/runs/{run_id}/artifacts")
alive = [a for a in arts.get("artifacts", []) if not a.get("expired")]
if not alive:
    print("❌ 未找到 artifact")
    sys.exit(1)
# 优先选名字含 ipa 的产物，避免误取日志/其它 artifact
alive.sort(key=lambda a: (0 if "ipa" in (a.get("name") or "").lower() else 1))
art_id = alive[0]["id"]
print(f"   artifact: {alive[0].get('name')} (id={art_id})")

# 带 token 的请求只用于换取签名地址；重定向后的下载不带任何凭据。
# 大文件走断点续传：签名地址有效期短、对象存储读超时很常见。
# 缓存文件必须按 artifact id 命名：跨 run 复用会把上一次的旧包当成新产物（曾把 1.7 当成 1.8 交付）
_resume_dest = Path(os.environ.get(
    "LN_ARTIFACT_CACHE",
    os.path.join(tempfile.gettempdir(), f"ln_artifact-{art_id}.zip")))
if not download_artifact_resumable(
        REPO + f"/actions/artifacts/{art_id}/zip", _resume_dest):
    print("❌ artifact 下载失败。编译产物仍在，可稍后续传：")
    print(f"   LN_GH_PAT_FILE=<pat> python3 Tools/upload_via_api.py "
          f"--download-only {art_id} {_resume_dest}")
    sys.exit(1)
if not install_ipa_from_zip(_resume_dest):
    sys.exit(1)
