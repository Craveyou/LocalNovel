#!/usr/bin/env python3
"""生成 HTML 交互原型：数据直接来自 SampleBook，素材复制到 Preview/assets。
用途：在没有 Mac/Xcode 的情况下，先在浏览器/手机上看清界面与阅读流程。

对应本轮结构：书库首页 = 小说 / 漫画 / 整理 三个文件夹 → 分区书列表 → 章节 → 阅读。
注意：这是原型，不是 iOS 应用；GIF 由浏览器原生播放，动图在 App 里由 ImageIO 逐帧解码。
"""
from pathlib import Path
import json
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parent.parent
SAMPLE = ROOT / "SampleBook"
PREVIEW = ROOT / "Preview"
ASSETS = PREVIEW / "assets"

sys.path.insert(0, str(ROOT / "Validation"))
from validate_core import (  # noqa: E402
    scan_sections, resolve_chapter, split_text, ext, SECTIONS,
)

SECTION_HINT = {
    "novel": "每本一个文件：txt / md / epub / pdf",
    "comic": "每部一个文件夹：部 → 话，图片或 pdf",
    "organized": "作者 → 章节 → 正文 + 插图 + 音视频",
}
SECTION_ICON = {"novel": "📖", "comic": "🖼", "organized": "📁"}


def tidy(text: str):
    """段落切分，对齐 Swift TextLoader.paragraphs"""
    out, buf = [], []
    for line in text.split("\n"):
        if line.strip():
            buf.append(line)
        elif buf:
            joined = "\n".join(buf).strip()
            if joined:
                out.append(joined)
            buf = []
    if buf:
        joined = "\n".join(buf).strip()
        if joined:
            out.append(joined)
    return out


def epub_chapters(path: Path):
    """返回 [(title, body)]：container → opf → spine → xhtml"""
    with zipfile.ZipFile(path) as z:
        container = z.read("META-INF/container.xml").decode("utf-8", "ignore")
        m = re.search(r'full-path\s*=\s*"([^"]+)"', container)
        if not m:
            return []
        opf_path = m.group(1)
        opf = z.read(opf_path).decode("utf-8", "ignore")
        base = opf_path.rsplit("/", 1)[0] if "/" in opf_path else ""
        manifest = {}
        for attrs in re.findall(r"(?is)<item\b([^>]*)>", opf):
            i = re.search(r'id\s*=\s*"([^"]+)"', attrs)
            h = re.search(r'href\s*=\s*"([^"]+)"', attrs)
            med = re.search(r'media-type\s*=\s*"([^"]+)"', attrs)
            if i and h and (not med or "html" in med.group(1)):
                manifest[i.group(1)] = h.group(1)
        spine = re.findall(r'(?is)<itemref\b[^>]*idref\s*=\s*"([^"]+)"', opf)
        names = [manifest[s] for s in spine if s in manifest] or sorted(manifest.values())
        out = []
        for href in names:
            link = (base + "/" + href) if base else href
            try:
                html = z.read(link).decode("utf-8", "ignore")
            except KeyError:
                continue
            body = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", html)
            body = re.sub(r"(?i)<br\s*/?>", "\n", body)
            body = re.sub(r"(?i)</(p|div|h[1-6]|li|tr|section)>", "\n", body)
            body = re.sub(r"(?s)<[^>]+>", "", body)
            body = body.replace("&nbsp;", " ").replace("&amp;", "&").strip()
            h = re.search(r"(?is)<h1[^>]*>(.*?)</h1>", html) or \
                re.search(r"(?is)<title[^>]*>(.*?)</title>", html)
            title = re.sub(r"(?s)<[^>]+>", "", h.group(1)).strip() if h else ""
            out.append((title or Path(href).stem, body))
        return out


def pdf_pages(pdf: Path, prefix: str):
    """把 pdf 每页转成 png，返回相对路径列表（poppler 已预装）"""
    target = ASSETS / prefix
    try:
        subprocess.run(["pdftoppm", "-png", "-r", "80", str(pdf), str(target)],
                       check=True, capture_output=True)
    except Exception:
        return []
    pages = []
    for p in sorted(ASSETS.glob(prefix + "*.png")):
        pages.append("assets/" + p.name)
    return pages


def novel_chapters(path: Path, prefix: str):
    """单文件小说 → 章节数据"""
    e = ext(path.name)
    if e == "epub":
        return [{"title": t, "paragraphs": tidy(body), "images": [], "av": [],
                 "group": "", "kind": "slice"} for t, body in epub_chapters(path)]
    if e == "pdf":
        pages = pdf_pages(path, prefix + "_pdf")
        return [{"title": path.stem, "paragraphs": [], "images": [], "av": [],
                 "group": "", "kind": "pdf", "pdfPages": pages,
                 "note": f"PDF 小说：正式 App 抽取文字阅读（本原型展示页面，共 {len(pages)} 页）"}]
    text = path.read_text(encoding="utf-8", errors="ignore")
    out = []
    for title, start, length in split_text(text):
        out.append({"title": title or path.stem,
                    "paragraphs": tidy(text[start:start + length]),
                    "images": [], "av": [], "group": "", "kind": "slice"})
    return out


def main():
    if not SAMPLE.is_dir():
        print("缺少 SampleBook，请先运行 make_sample_book.py", file=sys.stderr)
        return 1
    if ASSETS.exists():
        shutil.rmtree(ASSETS)
    ASSETS.mkdir(parents=True)

    _layout, books = scan_sections(SAMPLE)
    sections = {k: [] for k in SECTIONS}
    idx = 0

    for book in books:
        chapters_data = []

        if book.category == "novel":
            chapters_data = novel_chapters(book.path, f"n{idx}")
        else:
            for cidx, chapter in enumerate(book.chapters):
                content = resolve_chapter(chapter)
                paragraphs, images, pages = [], [], []

                if content.text_url and content.text_url.is_file() \
                        and ext(content.text_url.name) in {"txt", "text", "md", "markdown"}:
                    paragraphs = tidy(content.text_url.read_text(encoding="utf-8",
                                                                errors="ignore"))

                if content.pdf_url:
                    pages = pdf_pages(content.pdf_url, f"b{idx}c{cidx}_pdf")

                for iidx, m in enumerate(content.images):
                    name = f"b{idx}c{cidx}_img{iidx}{m.url.suffix}"
                    shutil.copy2(m.url, ASSETS / name)
                    images.append({"src": "assets/" + name, "label": m.file_name,
                                   "animated": m.is_animated})

                av = []
                for aidx, m in enumerate(content.av):
                    name = f"b{idx}c{cidx}_av{aidx}{m.url.suffix}"
                    shutil.copy2(m.url, ASSETS / name)
                    av.append({"src": "assets/" + name, "label": m.file_name,
                               "kind": m.kind})

                chapters_data.append({
                    "title": chapter.title,
                    "group": chapter.group or "",
                    "kind": chapter.kind,
                    "paragraphs": paragraphs,
                    "images": images,
                    "av": av,
                    "pdfPages": pages,
                    "ignored": content.ignored,
                })

        if not chapters_data:
            continue

        sections[book.category].append({"title": book.title,
                                        "series": book.series or "",
                                        "chapters": chapters_data})
        idx += 1

    data = {
        "sections": [
            {"key": key,
             "label": SECTIONS[key],
             "icon": SECTION_ICON[key],
             "hint": SECTION_HINT[key],
             "books": sections[key]}
            for key in ("novel", "comic", "organized")
        ]
    }

    html = TEMPLATE.replace("__DATA__", json.dumps(data, ensure_ascii=False))
    (PREVIEW / "index.html").write_text(html, encoding="utf-8")
    total = sum(len(s["books"]) for s in data["sections"])
    print(f"原型已生成：{PREVIEW / 'index.html'}")
    print(f"  素材 {len(list(ASSETS.iterdir()))} 个，书 {total} 本，"
          f"章节 {sum(len(b['chapters']) for s in data['sections'] for b in s['books'])} 章")
    return 0


TEMPLATE = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>本地小说阅读器 · 交互原型</title>
<style>
:root{
  --bg:#f7f7f9; --panel:#ffffff; --text:#1c1c1e; --sub:#6b6b70;
  --line:#e5e5ea; --accent:#3b6ddd; --card:#f2f2f7;
  --fs:18px; --lh:1.9;
}
body.dark{ --bg:#161618; --panel:#1e1e21; --text:#f2f2f7; --sub:#9a9aa0;
  --line:#333338; --accent:#6f9dff; --card:#26262b; }
*{box-sizing:border-box}
html,body{height:100%;margin:0}
body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Noto Sans CJK SC",sans-serif}
.banner{background:var(--accent);color:#fff;font-size:12px;padding:7px 14px;text-align:center;line-height:1.5}
.app{display:grid;grid-template-columns:240px 250px 1fr;height:calc(100% - 30px)}
.pane{background:var(--panel);border-right:1px solid var(--line);overflow-y:auto;padding:10px 0}
.pane h2{font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:var(--sub);margin:8px 14px 12px}
.item{display:block;width:100%;text-align:left;border:0;background:transparent;color:var(--text);
  padding:11px 14px;font-size:14px;cursor:pointer;border-left:3px solid transparent}
.item:hover{background:var(--card)}
.item.active{background:var(--card);border-left-color:var(--accent);font-weight:600}
.item small{display:block;color:var(--sub);font-weight:400;margin-top:3px}
.folder{display:flex;align-items:center;gap:12px;width:calc(100% - 24px);margin:8px 12px;
  padding:14px;border:0;border-radius:14px;background:var(--card);color:var(--text);
  font-size:15px;text-align:left;cursor:pointer}
.folder:hover{filter:brightness(.97)}
.folder .ic{font-size:22px;width:44px;height:44px;display:grid;place-items:center;
  background:rgba(59,109,221,.12);border-radius:12px;flex:none}
.folder .t{font-weight:600}
.folder small{display:block;color:var(--sub);font-weight:400;margin-top:2px;font-size:12px;line-height:1.4}
.folder .n{margin-left:auto;font-size:17px;color:var(--sub);font-variant-numeric:tabular-nums}
.backbar{display:flex;align-items:center;gap:8px;padding:6px 14px 10px;border-bottom:1px solid var(--line);
  margin-bottom:6px}
.backbar button{border:0;background:transparent;color:var(--accent);font-size:14px;cursor:pointer;padding:4px 0}
.backbar span{font-size:15px;font-weight:600}
.reader{overflow-y:auto;padding:0 0 60px}
.reader-inner{max-width:760px;margin:0 auto;padding:24px 26px}
.reader-inner.comic{max-width:none;padding:0 0 30px}
.reader h1{font-size:22px;margin:0 0 22px}
.reader .grouptag{font-size:12px;color:var(--sub);margin:-16px 0 18px}
p.body{font-size:var(--fs);line-height:var(--lh);margin:0 0 1em;white-space:pre-wrap}
.sec{font-size:12px;font-weight:600;color:var(--sub);margin:26px 0 12px;letter-spacing:.05em}
figure{margin:0 0 18px}
figure img{width:100%;border-radius:10px;display:block;background:var(--card);cursor:zoom-in}
figcaption{font-size:11px;color:var(--sub);margin-top:5px}
.comic-page{display:block;width:100%;margin:0;cursor:zoom-in;background:var(--card)}
video{width:100%;border-radius:10px;background:#000;display:block;transition:transform .25s ease}
audio{width:100%}
.media{border:1px solid var(--line);border-radius:12px;padding:12px;background:var(--card);margin-bottom:16px}
.media .name{font-size:13px;margin-bottom:8px;word-break:break-all}
.hint{font-size:12px;color:var(--sub);margin-top:20px;line-height:1.6}
.pdfnote{font-size:12px;color:var(--sub);margin:10px 0 14px;padding:10px 12px;
  border:1px dashed var(--line);border-radius:10px;background:var(--card)}
.toolbar{display:flex;gap:14px;align-items:center;flex-wrap:wrap;background:var(--panel);
  border-bottom:1px solid var(--line);padding:8px 14px;font-size:13px;position:sticky;top:0;z-index:5}
.toolbar label{display:flex;gap:6px;align-items:center;color:var(--sub)}
.toolbar input[type=range]{width:110px}
.empty{display:flex;align-items:center;justify-content:center;height:100%;color:var(--sub);font-size:14px;text-align:center;padding:30px}
#overlay{position:fixed;inset:0;background:#000;display:none;align-items:center;justify-content:center;
  z-index:50;overflow:hidden;touch-action:none}
#zoom{max-width:94%;max-height:82%;object-fit:contain;transition:transform .16s ease;cursor:zoom-in}
.lb-bar{position:absolute;top:0;left:0;right:0;display:flex;align-items:center;gap:12px;
  padding:calc(10px + env(safe-area-inset-top)) 14px 10px;background:rgba(0,0,0,.62);color:#fff;font-size:13px;
  transition:opacity .2s ease,transform .2s ease}
.lb-bar.hide{opacity:0;transform:translateY(-100%);pointer-events:none}
.lb-bar button{background:rgba(255,255,255,.18);border:0;color:#fff;border-radius:16px;padding:5px 12px;font-size:13px;cursor:pointer}
.lb-nav{position:absolute;top:50%;transform:translateY(-50%);width:40px;height:56px;border:0;
  background:rgba(255,255,255,.14);color:#fff;font-size:28px;border-radius:10px;cursor:pointer}
.lb-nav.prev{left:8px}.lb-nav.next{right:8px}
.av-wrap{position:relative}
.fs-btn{background:var(--panel);border:1px solid var(--line);color:var(--text);border-radius:8px;
  padding:4px 10px;font-size:12px;cursor:pointer;margin-top:8px}
.rate-badge{display:none;position:absolute;left:12px;bottom:16px;background:rgba(0,0,0,.72);color:#fff;
  font-size:12px;padding:4px 10px;border-radius:14px;pointer-events:none}
.audio-pad{height:74px;border-radius:10px;background:var(--card);display:flex;align-items:center;
  justify-content:center;color:var(--sub);font-size:13px;touch-action:none;user-select:none;cursor:pointer}
.back{display:none}
@media(max-width:860px){
  .app{grid-template-columns:1fr}
  .pane{display:none;height:100%}
  .pane.show{display:block}
  .reader{display:none}
  .reader.show{display:block}
  .back{display:inline-block}
}
</style>
</head>
<body>
<div class="banner">交互原型（非 iOS 应用）· 书库首页三个文件夹 · 漫画满宽连排 · 点图进全屏灯箱 · 长按视频/音轨临时倍速</div>
<div class="toolbar">
  <button class="back" id="back">← 返回</button>
  <label>字号 <input type="range" id="fs" min="14" max="28" value="18"></label>
  <label>行距 <input type="range" id="lh" min="14" max="26" value="19"></label>
  <label><input type="checkbox" id="dark"> 夜间</label>
  <label>长按倍速 <select id="rate"><option value="1.5">1.5×</option><option value="2" selected>2×</option><option value="3">3×</option></select></label>
  <span style="color:var(--sub)" id="tip">书库 → 分区 → 章节</span>
</div>
<div class="app">
  <div class="pane show" id="paneBooks"></div>
  <div class="pane" id="paneChapters"><h2>目录</h2><div id="chapters"></div></div>
  <div class="reader" id="reader"><div class="reader-inner" id="content"></div></div>
</div>
<div id="overlay">
  <img id="zoom" src="" alt="">
  <div class="lb-bar" id="lbBar"><button id="lbClose">✕ 关闭</button><span id="lbCount"></span>
    <span style="margin-left:auto;opacity:.7" id="lbName"></span></div>
  <button class="lb-nav prev" id="lbPrev">‹</button>
  <button class="lb-nav next" id="lbNext">›</button>
</div>
<script>
const DATA = __DATA__;
let sec = null, openSeries = null, b = 0, c = 0, lbList = [];
const $ = id => document.getElementById(id);
const esc = s => String(s).replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
const section = key => DATA.sections.find(s => s.key === key);

function currentBooks(){
  const s = section(sec);
  if(!s) return [];
  if(openSeries) return s.books.filter(bk => bk.series === openSeries);
  return s.books;
}

function seriesNames(s){
  const out = [];
  s.books.forEach(bk => { if(bk.series && out.indexOf(bk.series) < 0) out.push(bk.series); });
  return out;
}

function bookItem(bk, index){
  return `<button class="item ${index === b ? 'active' : ''}" data-b="${index}">${esc(bk.title)}<small>${bk.chapters.length} ${sec === 'comic' ? '话' : '章'}</small></button>`;
}

function renderBooks(){
  if(!sec){
    const cards = DATA.sections.map(s =>
      `<button class="folder" data-sec="${s.key}">
         <span class="ic">${s.icon}</span>
         <span><span class="t">${esc(s.label)}</span><small>${esc(s.hint)}</small></span>
         <span class="n">${s.books.length}</span>
       </button>`).join('');
    $('paneBooks').innerHTML = `<h2>书库</h2>${cards}`;
    $('paneBooks').querySelectorAll('[data-sec]').forEach(el => el.onclick = () => {
      sec = el.dataset.sec; openSeries = null; b = 0; c = 0;
      renderBooks(); renderChapters(); show('paneBooks');
    });
    $('tip').textContent = '书库 → 分区 → 系列 → 章节';
    return;
  }
  const s = section(sec);
  const back = `<div class="backbar"><button id="toHome">‹ ${openSeries ? esc(s.label) : '书库'}</button>`
    + `<span>${esc(openSeries || s.label)}</span></div>`;

  if(openSeries){
    const list = currentBooks().map((bk, i) => bookItem(bk, i)).join('');
    $('paneBooks').innerHTML = back + (list || '<div class="empty">这个系列还没有书</div>');
  } else if(!seriesNames(s).length){
    const list = s.books.map((bk, i) => bookItem(bk, i)).join('');
    $('paneBooks').innerHTML = back + (list || '<div class="empty">这个分区还没有书</div>');
  } else {
    const folders = seriesNames(s).map(n => {
      const count = s.books.filter(x => x.series === n).length;
      return `<button class="item" data-series="${esc(n)}" style="font-weight:600">▸ ${esc(n)}<small>${count} 本</small></button>`;
    }).join('');
    const loose = s.books.map((bk, i) => [bk, i]).filter(pair => !pair[0].series);
    const looseHtml = loose.length
      ? `<h2>未分组</h2>` + loose.map(pair => bookItem(pair[0], pair[1])).join('')
      : '';
    $('paneBooks').innerHTML = back + `<h2>系列</h2>` + folders + looseHtml;
  }

  $('toHome').onclick = () => goBack();
  $('paneBooks').querySelectorAll('[data-series]').forEach(el => el.onclick = () => {
    openSeries = el.dataset.series; b = 0; c = 0;
    renderBooks(); renderChapters(); show('paneBooks');
  });
  $('paneBooks').querySelectorAll('[data-b]').forEach(el => el.onclick = () => {
    b = +el.dataset.b; c = 0; renderBooks(); renderChapters(); renderReader(); show('reader');
  });
  $('tip').textContent = openSeries
    ? `${openSeries} · ${currentBooks().length} 本`
    : `${s.label} · ${s.books.length} 本`;
}

function goBack(){
  if(openSeries){ openSeries = null; b = 0; c = 0; renderBooks(); renderChapters(); show('paneBooks'); return; }
  if(sec){ sec = null; b = 0; c = 0; renderBooks(); renderChapters(); show('paneBooks'); }
}

// 左边缘向右滑 = 返回上一级（与 iOS 一致）
let swipeStart = null;
$('paneBooks').addEventListener('pointerdown', e => { swipeStart = { x: e.clientX, y: e.clientY }; });
$('paneBooks').addEventListener('pointerup', e => {
  if(!swipeStart) return;
  const dx = e.clientX - swipeStart.x;
  const dy = Math.abs(e.clientY - swipeStart.y);
  const fromEdge = swipeStart.x - $('paneBooks').getBoundingClientRect().left <= 44;
  if(fromEdge && dx >= 80 && dy <= 70) goBack();
  swipeStart = null;
});

function renderChapters(){
  if(!sec){ $('chapters').innerHTML = '<div class="empty">先在左栏选一个文件夹</div>'; return; }
  const bk = currentBooks()[b];
  if(!bk){ $('chapters').innerHTML = '<div class="empty">这个分区还没有书</div>'; return; }
  $('chapters').innerHTML = bk.chapters.map((ch, i) => {
    const meta = ch.images.length ? `${ch.images.length} 页`
      : (ch.pdfPages && ch.pdfPages.length ? `${ch.pdfPages.length} 页 pdf`
      : `${ch.paragraphs.length} 段`);
    const g = ch.group ? esc(ch.group) + ' · ' : '';
    return `<button class="item ${i === c ? 'active' : ''}" data-c="${i}">${g}${esc(ch.title)}<small>${meta}</small></button>`;
  }).join('');
  $('chapters').querySelectorAll('[data-c]').forEach(el => el.onclick = () => {
    c = +el.dataset.c; renderChapters(); renderReader(); show('reader'); $('reader').scrollTop = 0;
  });
}

function renderReader(){
  if(!sec){ $('content').innerHTML = '<div class="empty">选择一本书开始阅读</div>'; return; }
  const bk = currentBooks()[b];
  if(!bk){ $('content').innerHTML = '<div class="empty">选择一本书开始阅读</div>'; return; }
  const ch = bk.chapters[c];
  if(!ch){ $('content').innerHTML = '<div class="empty">选择一章开始阅读</div>'; return; }
  const isComic = sec === 'comic';
  const pages = (ch.images.length ? ch.images : (ch.pdfPages || []).map(src => ({src, label: ''})));
  $('content').className = 'reader-inner' + (isComic && pages.length ? ' comic' : '');

  let html = '';
  if(isComic && pages.length){
    html += `<div style="padding:14px 20px 6px"><h1 style="margin:0">${esc(ch.title)}</h1>`
      + (ch.group ? `<div class="grouptag" style="margin:6px 0 0">${esc(ch.group)}</div>` : '')
      + `</div>`;
    pages.forEach((p, i) => {
      html += `<img class="comic-page" src="${p.src}" alt="${esc(p.label)}" data-lb="${i}">`;
    });
    html += `<div class="hint" style="padding:0 20px">共 ${pages.length} 页 · 点任意一页进入全屏（左右翻页 / 上滑关闭 / 末页继续左滑关闭）</div>`;
    html += `<div style="padding:8px 20px 30px" class="hint">${c + 1 < bk.chapters.length ? '↓ 下一话：' + esc(bk.chapters[c + 1].title) : '已是最后一话'}</div>`;
    $('content').innerHTML = html;
    $('content').querySelectorAll('[data-lb]').forEach(el => el.onclick = () => openLB(+el.dataset.lb, pages));
    return;
  }

  html += `<h1>${esc(ch.title)}</h1>`;
  if(ch.group) html += `<div class="grouptag">${esc(ch.group)}</div>`;
  if(ch.note) html += `<div class="pdfnote">${esc(ch.note)}</div>`;
  ch.paragraphs.forEach(p => html += `<p class="body">${esc(p)}</p>`);

  if(ch.pdfPages && ch.pdfPages.length){
    ch.pdfPages.forEach((src, i) => {
      html += `<figure><img src="${src}" alt="page ${i + 1}" data-lb="${i}">`
        + `<figcaption>第 ${i + 1} 页</figcaption></figure>`;
    });
  }

  if(ch.images.length) html += `<div class="sec">插图 · ${ch.images.length}</div>`;
  ch.images.forEach((im, i) => {
    html += `<figure><img src="${im.src}" alt="${esc(im.label)}" data-lb="${i}">`
      + `<figcaption>${esc(im.label)}${im.animated ? ' · 动图' : ''} · 点击全屏</figcaption></figure>`;
  });

  if(ch.av.length) html += `<div class="sec">章末媒体</div>`;
  ch.av.forEach(m => {
    const isV = m.kind === 'video';
    const player = isV
      ? `<video controls preload="none" playsinline src="${m.src}"></video>`
      : `<audio controls preload="none" src="${m.src}"></audio>`;
    const pad = isV ? '' : `<div class="audio-pad">按住此处临时倍速播放</div>`;
    html += `<div class="media"><div class="name">${esc(m.label)} · ${isV ? '视频' : '音频'}（点击播放，不自动播放）</div>
      <div class="av-wrap" data-av>${player}${pad}
        ${isV ? '<button class="fs-btn">⛶ 全屏播放</button>' : ''}
        <span class="rate-badge"></span>
      </div></div>`;
  });

  if(ch.ignored && ch.ignored.length) html += `<div class="hint">已忽略 ${ch.ignored.length} 个未识别文件：${esc(ch.ignored.slice(0, 3).join('、'))}</div>`;

  html += c + 1 < bk.chapters.length
    ? `<div class="hint">↓ 下一章：${esc(bk.chapters[c + 1].title)}</div>`
    : `<div class="hint">✓ 已是最后一章</div>`;

  $('content').innerHTML = html;
  const imgs = ch.images.length ? ch.images : (ch.pdfPages || []).map(src => ({src, label: ''}));
  $('content').querySelectorAll('[data-lb]').forEach(el => el.onclick = () => openLB(+el.dataset.lb, imgs));
  bindMedia($('content'));
}

// ---- 沉浸式全屏灯箱：翻页 / 缩放 / 单击切遮罩 / 上滑或末页左滑关闭 ----
let zi = 0, lbScale = 1, RATE = 2.0, chrome = true;
function openLB(i, list){
  if(!list || !list.length) return;
  lbList = list; zi = (i + list.length) % list.length; lbScale = 1; chrome = true;
  applyLB(); $('overlay').style.display = 'flex'; syncChrome();
}
function applyLB(){
  const im = lbList[zi]; if(!im) return;
  $('zoom').src = im.src; $('zoom').style.transform = `scale(${lbScale})`;
  $('lbCount').textContent = `${zi + 1} / ${lbList.length}`;
  $('lbName').textContent = im.label || '';
}
function syncChrome(){ $('lbBar').classList.toggle('hide', !chrome); }
function closeLB(){ $('overlay').style.display = 'none'; $('zoom').src = ''; lbScale = 1; }
function stepLB(d){ openLB(zi + d, lbList); }
$('lbClose').onclick = e => { e.stopPropagation(); closeLB(); };
$('lbPrev').onclick = e => { e.stopPropagation(); stepLB(-1); };
$('lbNext').onclick = e => { e.stopPropagation(); stepLB(1); };
$('zoom').onclick = e => { e.stopPropagation(); chrome = !chrome; syncChrome(); };
$('overlay').onclick = e => { if(e.target.id === 'overlay') closeLB(); };
$('zoom').ondblclick = e => { e.stopPropagation(); lbScale = lbScale > 1 ? 1 : 2.5; applyLB(); };
$('zoom').onwheel = e => { e.preventDefault(); lbScale = Math.min(5, Math.max(1, lbScale + (e.deltaY < 0 ? .25 : -.25))); applyLB(); };

let sx = null, sy = null;
$('overlay').addEventListener('pointerdown', e => { sx = e.clientX; sy = e.clientY; });
$('overlay').addEventListener('pointerup', e => {
  if(sx !== null && lbScale === 1){
    const dx = e.clientX - sx, dy = e.clientY - sy;
    if(dy < -90) closeLB();
    else if(Math.abs(dx) > 60){
      const last = zi === lbList.length - 1, first = zi === 0;
      if(dx < 0 && last) closeLB();          // 末页继续左滑 → 关闭
      else if(!(dx > 0 && first)) stepLB(dx < 0 ? 1 : -1);
    }
  }
  sx = null; sy = null;
});
document.addEventListener('keydown', e => {
  if($('overlay').style.display !== 'flex') return;
  if(e.key === 'Escape') closeLB();
  if(e.key === 'ArrowLeft') stepLB(-1);
  if(e.key === 'ArrowRight') stepLB(1);
});
$('rate').onchange = e => { RATE = parseFloat(e.target.value); };

// ---- 视频全屏 + 长按倍速（浏览器 API 模拟原生行为） ----
function bindMedia(root){
  root.querySelectorAll('[data-av]').forEach(wrap => {
    const el = wrap.querySelector('video,audio');
    const badge = wrap.querySelector('.rate-badge');
    const fsBtn = wrap.querySelector('.fs-btn');
    let timer = null, boosted = false;
    const begin = () => {
      timer = setTimeout(() => {
        boosted = true; el.playbackRate = RATE;
        if(el.paused){ const p = el.play(); if(p && p.catch) p.catch(()=>{}); }
        badge.textContent = RATE + '× 快进中'; badge.style.display = 'block';
      }, 350);
    };
    const end = () => {
      clearTimeout(timer); timer = null;
      if(boosted){ el.playbackRate = 1; badge.style.display = 'none'; boosted = false; }
    };
    wrap.addEventListener('pointerdown', begin);
    ['pointerup','pointercancel','pointerleave'].forEach(ev => wrap.addEventListener(ev, end));
    if(fsBtn) fsBtn.onclick = e => {
      e.stopPropagation();
      if(el.requestFullscreen) el.requestFullscreen();
      else if(el.webkitEnterFullscreen) el.webkitEnterFullscreen();
    };
  });
}

function show(which){
  ['paneBooks','paneChapters','reader'].forEach(id => $(id).classList.remove('show'));
  $(which).classList.add('show');
}
$('back').onclick = () => {
  if($('reader').classList.contains('show')) show('paneChapters');
  else if($('paneChapters').classList.contains('show')) show('paneBooks');
};
$('fs').oninput = e => document.documentElement.style.setProperty('--fs', e.target.value + 'px');
$('lh').oninput = e => document.documentElement.style.setProperty('--lh', (e.target.value / 10));
$('dark').onchange = e => document.body.classList.toggle('dark', e.target.checked);
renderBooks(); renderChapters(); renderReader();
</script>
</body>
</html>
"""


if __name__ == "__main__":
    sys.exit(main())
