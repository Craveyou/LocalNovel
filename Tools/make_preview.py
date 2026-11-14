#!/usr/bin/env python3
"""生成 HTML 交互原型：数据直接来自 SampleBook，素材复制到 Preview/assets。
用途：在没有 Mac/Xcode 的情况下，先在浏览器/手机上看清界面与阅读流程。
注意：这是原型，不是 iOS 应用；GIF 由浏览器原生播放，动图在 App 里由 ImageIO 逐帧解码。
"""
from pathlib import Path
import json
import shutil
import sys

ROOT = Path(__file__).resolve().parent.parent
SAMPLE = ROOT / "SampleBook"
PREVIEW = ROOT / "Preview"
ASSETS = PREVIEW / "assets"

sys.path.insert(0, str(ROOT / "Validation"))
from validate_core import scan_library, resolve_chapter, classify, is_hidden  # noqa: E402


def main():
    if not SAMPLE.is_dir():
        print("缺少 SampleBook，请先运行 make_sample_book.py", file=sys.stderr)
        return 1
    if ASSETS.exists():
        shutil.rmtree(ASSETS)
    ASSETS.mkdir(parents=True)

    books = []
    for bidx, (book_title, chapters) in enumerate(scan_library(SAMPLE)):
        chapters_data = []
        for cidx, chapter in enumerate(chapters):
            content = resolve_chapter(chapter)
            paragraphs = []
            if content.text_url:
                text = content.text_url.read_text(encoding="utf-8")
                paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]

            images = []
            for iidx, m in enumerate(content.images):
                ext = m.url.suffix
                name = f"b{bidx}c{cidx}_img{iidx}{ext}"
                shutil.copy2(m.url, ASSETS / name)
                images.append({"src": "assets/" + name,
                               "label": m.file_name,
                               "animated": m.is_animated})

            av = []
            for aidx, m in enumerate(content.av_media if hasattr(content, "av_media") else content.av):
                ext = m.url.suffix
                name = f"b{bidx}c{cidx}_av{aidx}{ext}"
                shutil.copy2(m.url, ASSETS / name)
                av.append({"src": "assets/" + name, "label": m.file_name,
                           "kind": m.kind})

            chapters_data.append({
                "title": chapter.title,
                "paragraphs": paragraphs,
                "images": images,
                "av": av,
                "ignored": content.ignored,
            })
        books.append({"title": book_title, "chapters": chapters_data})

    data = json.dumps({"books": books}, ensure_ascii=False)

    html = TEMPLATE.replace("__DATA__", data)
    (PREVIEW / "index.html").write_text(html, encoding="utf-8")
    print(f"原型已生成：{PREVIEW / 'index.html'}")
    print(f"  素材 {len(list(ASSETS.iterdir()))} 个，书 {len(books)} 本，"
          f"章节 {sum(len(b['chapters']) for b in books)} 章")
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
.app{display:grid;grid-template-columns:220px 240px 1fr;height:calc(100% - 30px)}
.pane{background:var(--panel);border-right:1px solid var(--line);overflow-y:auto;padding:10px 0}
.pane h2{font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:var(--sub);margin:8px 14px 12px}
.item{display:block;width:100%;text-align:left;border:0;background:transparent;color:var(--text);
  padding:11px 14px;font-size:14px;cursor:pointer;border-left:3px solid transparent}
.item:hover{background:var(--card)}
.item.active{background:var(--card);border-left-color:var(--accent);font-weight:600}
.item small{display:block;color:var(--sub);font-weight:400;margin-top:3px}
.reader{overflow-y:auto;padding:0 0 60px}
.reader-inner{max-width:760px;margin:0 auto;padding:24px 26px}
.reader h1{font-size:22px;margin:0 0 22px}
p.body{font-size:var(--fs);line-height:var(--lh);margin:0 0 1em;white-space:pre-wrap}
.sec{font-size:12px;font-weight:600;color:var(--sub);margin:26px 0 12px;letter-spacing:.05em}
figure{margin:0 0 18px}
figure img{width:100%;border-radius:10px;display:block;background:var(--card);cursor:zoom-in}
figcaption{font-size:11px;color:var(--sub);margin-top:5px}
video{width:100%;border-radius:10px;background:#000;display:block}
audio{width:100%}
.media{border:1px solid var(--line);border-radius:12px;padding:12px;background:var(--card);margin-bottom:16px}
.media .name{font-size:13px;margin-bottom:8px;word-break:break-all}
.hint{font-size:12px;color:var(--sub);margin-top:20px}
.toolbar{display:flex;gap:14px;align-items:center;flex-wrap:wrap;background:var(--panel);
  border-bottom:1px solid var(--line);padding:8px 14px;font-size:13px;position:sticky;top:0;z-index:5}
.toolbar label{display:flex;gap:6px;align-items:center;color:var(--sub)}
.toolbar input[type=range]{width:110px}
.empty{display:flex;align-items:center;justify-content:center;height:100%;color:var(--sub);font-size:14px;text-align:center;padding:30px}
#overlay{position:fixed;inset:0;background:#000;display:none;align-items:center;justify-content:center;
  z-index:50;overflow:hidden;touch-action:none}
#zoom{max-width:94%;max-height:82%;object-fit:contain;transition:transform .16s ease;cursor:zoom-in}
.lb-bar{position:absolute;top:0;left:0;right:0;display:flex;align-items:center;gap:12px;
  padding:calc(10px + env(safe-area-inset-top)) 14px 10px;background:rgba(0,0,0,.62);color:#fff;font-size:13px}
.lb-bar button{background:rgba(255,255,255,.18);border:0;color:#fff;border-radius:16px;padding:5px 12px;font-size:13px;cursor:pointer}
.lb-nav{position:absolute;top:50%;transform:translateY(-50%);width:40px;height:56px;border:0;
  background:rgba(255,255,255,.14);color:#fff;font-size:28px;border-radius:10px;cursor:pointer}
.lb-nav.prev{left:8px}.lb-nav.next{right:8px}
.lb-hint{position:absolute;bottom:calc(18px + env(safe-area-inset-bottom));left:0;right:0;text-align:center;
  color:rgba(255,255,255,.8);font-size:12px;pointer-events:none}
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
<div class="banner">交互原型（非 iOS 应用）· 点图片进全屏灯箱 · 视频可全屏 · 长按视频/音轨临时倍速 · 动图在正式 App 中由 ImageIO 逐帧解码</div>
<div class="toolbar">
  <button class="back" id="back">← 返回</button>
  <label>字号 <input type="range" id="fs" min="14" max="28" value="18"></label>
  <label>行距 <input type="range" id="lh" min="14" max="26" value="19"></label>
  <label><input type="checkbox" id="dark"> 夜间</label>
  <label>长按倍速 <select id="rate"><option value="1.5">1.5×</option><option value="2" selected>2×</option><option value="3">3×</option></select></label>
  <span style="color:var(--sub)">三栏 · 连续滚动 · 正文 → 图片 → 章末媒体</span>
</div>
<div class="app">
  <div class="pane show" id="paneBooks"><h2>书库</h2><div id="books"></div></div>
  <div class="pane" id="paneChapters"><h2>章节</h2><div id="chapters"></div></div>
  <div class="reader" id="reader"><div class="reader-inner" id="content"></div></div>
</div>
<div id="overlay">
  <img id="zoom" src="" alt="">
  <div class="lb-bar"><button id="lbClose">✕ 关闭</button><span id="lbCount"></span>
    <span style="margin-left:auto;opacity:.7" id="lbName"></span></div>
  <button class="lb-nav prev" id="lbPrev">‹</button>
  <button class="lb-nav next" id="lbNext">›</button>
  <div class="lb-hint">左右滑动翻页 · 双击或滚轮缩放 · 点击空白处关闭</div>
</div>
<script>
const DATA = __DATA__;
let b = 0, c = 0;
const $ = id => document.getElementById(id);
const esc = s => String(s).replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));

function renderBooks(){
  $('books').innerHTML = DATA.books.map((bk,i)=>
    `<button class="item ${i===b?'active':''}" data-b="${i}">${esc(bk.title)}<small>${bk.chapters.length} 章</small></button>`).join('');
  $('books').querySelectorAll('.item').forEach(el=>el.onclick=()=>{
    b=+el.dataset.b; c=0; renderBooks(); renderChapters(); renderReader(); show('reader');
  });
}
function renderChapters(){
  const bk=DATA.books[b];
  $('chapters').innerHTML=bk.chapters.map((ch,i)=>
    `<button class="item ${i===c?'active':''}" data-c="${i}">${esc(ch.title)}<small>${ch.images.length} 图 · ${ch.av.length} 媒体</small></button>`).join('');
  $('chapters').querySelectorAll('.item').forEach(el=>el.onclick=()=>{
    c=+el.dataset.c; renderChapters(); renderReader(); show('reader'); $('reader').scrollTop=0;
  });
}
function renderReader(){
  const ch=DATA.books[b].chapters[c];
  let html=`<h1>${esc(ch.title)}</h1>`;
  ch.paragraphs.forEach(p=> html+=`<p class="body">${esc(p)}</p>`);
  if(ch.images.length) html+=`<div class="sec">插图 · ${ch.images.length}</div>`;
  ch.images.forEach((im,i)=> html+=`<figure><img src="${im.src}" alt="${esc(im.label)}" data-zi="${i}"><figcaption>${esc(im.label)}${im.animated?' · 动图':''} · 点击全屏</figcaption></figure>`);
  if(ch.av.length) html+=`<div class="sec">章末媒体</div>`;
  ch.av.forEach(m=>{
    const isV=m.kind==='video';
    const player=isV
      ? `<video controls preload="none" playsinline src="${m.src}"></video>`
      : `<audio controls preload="none" src="${m.src}"></audio>`;
    const pad=isV?'':`<div class="audio-pad">按住此处临时倍速播放</div>`;
    html+=`<div class="media"><div class="name">${esc(m.label)} · ${isV?'视频':'音频'}（点击播放，不自动播放）</div>
      <div class="av-wrap" data-av>${player}${pad}
        ${isV?'<button class="fs-btn">⛶ 全屏播放</button>':''}
        <span class="rate-badge"></span>
      </div></div>`;
  });
  if(ch.ignored.length) html+=`<div class="hint">已忽略 ${ch.ignored.length} 个未识别文件：${esc(ch.ignored.slice(0,3).join('、'))}</div>`;
  $('content').innerHTML=html;
  $('content').querySelectorAll('[data-zi]').forEach(el=>el.onclick=()=>openLB(+el.dataset.zi));
  bindMedia($('content'));
}

// ---- 沉浸式全屏灯箱：翻页 / 缩放 / 关闭 ----
let zi=0, lbScale=1, RATE=2.0;
const curImgs=()=>DATA.books[b].chapters[c].images;
function openLB(i){
  const list=curImgs(); if(!list.length) return;
  zi=(i+list.length)%list.length; lbScale=1;
  applyLB(); $('overlay').style.display='flex';
}
function applyLB(){
  const im=curImgs()[zi]; if(!im) return;
  $('zoom').src=im.src; $('zoom').style.transform=`scale(${lbScale})`;
  $('lbCount').textContent=`${zi+1} / ${curImgs().length}`;
  $('lbName').textContent=im.label+(im.animated?' · 动图':'');
}
function closeLB(){ $('overlay').style.display='none'; $('zoom').src=''; lbScale=1; }
function stepLB(d){ openLB(zi+d); }
$('lbClose').onclick=e=>{e.stopPropagation();closeLB();};
$('lbPrev').onclick=e=>{e.stopPropagation();stepLB(-1);};
$('lbNext').onclick=e=>{e.stopPropagation();stepLB(1);};
$('overlay').onclick=e=>{ if(e.target.id==='overlay') closeLB(); };
$('zoom').ondblclick=e=>{e.stopPropagation(); lbScale=lbScale>1?1:2.5; applyLB();};
$('zoom').onwheel=e=>{e.preventDefault(); lbScale=Math.min(5,Math.max(1,lbScale+(e.deltaY<0?.25:-.25))); applyLB();};
let sx=null;
$('overlay').addEventListener('pointerdown',e=>{ if(e.target.id==='overlay') sx=e.clientX; });
$('overlay').addEventListener('pointerup',e=>{
  if(sx!==null && lbScale===1 && Math.abs(e.clientX-sx)>60) stepLB(e.clientX<sx?1:-1);
  sx=null;
});
document.addEventListener('keydown',e=>{
  if($('overlay').style.display!=='flex') return;
  if(e.key==='Escape') closeLB();
  if(e.key==='ArrowLeft') stepLB(-1);
  if(e.key==='ArrowRight') stepLB(1);
});
$('rate').onchange=e=>{ RATE=parseFloat(e.target.value); };

// ---- 视频全屏 + 长按倍速（浏览器 API 模拟原生行为） ----
function bindMedia(root){
  root.querySelectorAll('[data-av]').forEach(wrap=>{
    const el=wrap.querySelector('video,audio');
    const badge=wrap.querySelector('.rate-badge');
    const fsBtn=wrap.querySelector('.fs-btn');
    let timer=null, boosted=false;
    const begin=()=>{
      timer=setTimeout(()=>{
        boosted=true; el.playbackRate=RATE;
        if(el.paused){ const p=el.play(); if(p && p.catch) p.catch(()=>{}); }
        badge.textContent=RATE+'× 快进中'; badge.style.display='block';
      },350);
    };
    const end=()=>{
      clearTimeout(timer); timer=null;
      if(boosted){ el.playbackRate=1; badge.style.display='none'; boosted=false; }
    };
    wrap.addEventListener('pointerdown',begin);
    ['pointerup','pointercancel','pointerleave'].forEach(ev=>wrap.addEventListener(ev,end));
    if(fsBtn) fsBtn.onclick=e=>{
      e.stopPropagation();
      if(el.requestFullscreen) el.requestFullscreen();
      else if(el.webkitEnterFullscreen) el.webkitEnterFullscreen();
    };
  });
}
function show(which){
  ['paneBooks','paneChapters','reader'].forEach(id=>$(id).classList.remove('show'));
  $(which).classList.add('show');
}
$('back').onclick=()=>{
  if($('reader').classList.contains('show')) show('paneChapters');
  else if($('paneChapters').classList.contains('show')) show('paneBooks');
};
$('fs').oninput=e=>document.documentElement.style.setProperty('--fs',e.target.value+'px');
$('lh').oninput=e=>document.documentElement.style.setProperty('--lh',(e.target.value/10));
$('dark').onchange=e=>document.body.classList.toggle('dark',e.target.checked);
renderBooks(); renderChapters(); renderReader();
</script>
</body>
</html>
"""


if __name__ == "__main__":
    sys.exit(main())
