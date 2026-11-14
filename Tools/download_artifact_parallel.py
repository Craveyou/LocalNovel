#!/usr/bin/env python3
"""并行分块下载 GitHub Actions artifact。

背景：artifact 的重定向是带签名的对象存储地址，有效期短、单连接读很慢，
串行续传常在几分钟后超时。实测该对象存储支持 206 Range，并发分块可在
几十秒内取回完整压缩包。

用法：
  LN_GH_PAT_FILE=<pat> python3 Tools/download_artifact_parallel.py <artifact_id> <out.zip>
  # 可选：OWNER / REPO_NAME / LN_PARALLEL / LN_CHUNKS 环境变量

下载请求【不带任何凭据】：token 只用于向 GitHub API 换取签名地址。
"""
import concurrent.futures
import os
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

API = "https://api.github.com"
TOKEN = ""
if os.environ.get("LN_GH_PAT_FILE"):
    TOKEN = Path(os.environ["LN_GH_PAT_FILE"]).read_text(encoding="utf-8").strip()
elif os.environ.get("LN_GH_PAT"):
    TOKEN = os.environ["LN_GH_PAT"].strip()
if not TOKEN:
    sys.exit("❌ 需要 LN_GH_PAT_FILE 或 LN_GH_PAT（不打印令牌内容）")

OWNER = os.environ.get("OWNER", "")
REPO_NAME = os.environ.get("REPO_NAME", "LocalNovel")
PARALLEL = int(os.environ.get("LN_PARALLEL", "12"))
CHUNKS = int(os.environ.get("LN_CHUNKS", "32"))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


OPENER = urllib.request.build_opener(NoRedirect())


def api(path, headers=None):
    h = {"Authorization": "Bearer " + TOKEN,
         "Accept": "application/vnd.github+json",
         "User-Agent": "LocalNovel-Builder"}
    h.update(headers or {})
    return urllib.request.Request(path if path.startswith("http") else API + path,
                                  headers=h)


def main():
    if len(sys.argv) < 3:
        sys.exit("用法：download_artifact_parallel.py <artifact_id> <out.zip>")
    art_id, out = sys.argv[2], Path(sys.argv[3])

    if not OWNER:
        import json
        with urllib.request.urlopen(api("/user"), timeout=30) as r:
            owner = json.load(r).get("login", "")
    else:
        owner = OWNER
    url = f"/repos/{owner}/{REPO_NAME}/actions/artifacts/{art_id}/zip"

    def fresh_location():
        try:
            OPENER.open(api(url), timeout=30)
            return ""
        except urllib.error.HTTPError as e:
            return e.headers.get("Location") or ""
        except Exception:
            return ""

    loc = fresh_location()
    if not loc:
        sys.exit("❌ 未拿到签名下载地址")

    # 探测总大小（Range 只需 1 字节）
    with urllib.request.urlopen(
            urllib.request.Request(loc, headers={
                "User-Agent": "ln", "Range": "bytes=0-0"}), timeout=60) as r:
        cr = r.headers.get("Content-Range") or ""
    if "/" not in cr:
        sys.exit("❌ 服务端不支持 Range，无法并行分块")
    total = int(cr.rsplit("/", 1)[-1])
    size = (total + CHUNKS - 1) // CHUNKS
    ranges = [(i * size, min((i + 1) * size, total) - 1) for i in range(CHUNKS)]
    print(f"总大小 {total} 字节，分 {CHUNKS} 块，并发 {PARALLEL}", flush=True)

    def fetch(i):
        a, b = ranges[i]
        for attempt in range(6):
            try:
                target = loc if attempt == 0 else fresh_location()
                if not target:
                    raise RuntimeError("签名地址为空")
                req = urllib.request.Request(target, headers={
                    "User-Agent": "ln", "Range": f"bytes={a}-{b}"})
                with urllib.request.urlopen(req, timeout=150) as resp:
                    if resp.status != 206:
                        raise RuntimeError(f"HTTP {resp.status}")
                    data = resp.read()
                if len(data) != b - a + 1:
                    raise RuntimeError(f"短读 {len(data)}/{b - a + 1}")
                return i, data
            except Exception as e:  # noqa: BLE001
                print(f"  块 {i:02d} 第 {attempt + 1} 次失败：{type(e).__name__}", flush=True)
                time.sleep(2)
        raise RuntimeError(f"块 {i} 最终失败")

    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=PARALLEL) as ex:
        futs = [ex.submit(fetch, i) for i in range(CHUNKS)]
        for f in concurrent.futures.as_completed(futs):
            i, data = f.result()
            results[i] = data
    if len(results) != CHUNKS:
        sys.exit(f"❌ 只取回 {len(results)}/{CHUNKS} 块")
    blob = b"".join(results[i] for i in range(CHUNKS))
    if len(blob) != total:
        sys.exit(f"❌ 长度不符 {len(blob)}/{total}")
    out.write_bytes(blob)
    if not zipfile.is_zipfile(out):
        sys.exit("❌ 产物不是合法 zip")
    with zipfile.ZipFile(out) as z:
        names = z.namelist()
        ipa = next((n for n in names if n.lower().endswith(".ipa")), None)
        if not ipa:
            sys.exit("❌ artifact 里没有 ipa")
        ipa_bytes = z.read(ipa)
    print(f"✅ 已写入 {out}（{len(blob)} 字节），内容：{names}", flush=True)
    return ipa_bytes


if __name__ == "__main__":
    ipa_bytes = main()
    dest = Path(os.environ.get("LN_IPA_OUT", "build/LocalNovel-unsigned.ipa"))
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(ipa_bytes)
    print(f"✅ ipa 已写出：{dest}（{len(ipa_bytes) / 1024:.0f} KB）")
