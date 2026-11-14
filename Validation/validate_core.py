#!/usr/bin/env python3
"""S1 等价验证：用 Python 复刻 Core 层算法，在真实目录树上跑测试用例。

与 Swift 文件一一对应：
  NaturalSort.swift / MediaResolver.swift / BookScanner.swift / BookSections.swift
  ChapterSplitter.swift / EpubParser.swift / ChapterTitleCleaner.swift

覆盖：自然排序、全角数字、媒体分类、章节装配、三分区扫描、
      漫画「部 → 话」多级层级、pdf 单话、单文件小说自动分章、epub 解析、旧结构兼容。
"""
from __future__ import annotations

import re
import sys
import tempfile
import unicodedata
import zipfile
from dataclasses import dataclass, field
from functools import cmp_to_key
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SAMPLE = ROOT / "SampleBook"

# ---------------------------------------------------------------- 等价实现

TEXT_EXT = {"txt", "text", "md", "markdown"}
IMAGE_EXT = {"jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif", "apng"}
VIDEO_EXT = {"mp4", "mov", "m4v"}
AUDIO_EXT = {"mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf"}
ANIMATED_EXT = {"gif", "apng"}
NOVEL_EXT = {"txt", "text", "md", "markdown", "epub", "pdf"}
SECTIONS = {"novel": "小说", "comic": "漫画", "organized": "整理"}


def normalize(s: str) -> str:
    """对齐 Swift：NFC 合成 + 全角 ASCII/空格转半角"""
    s = unicodedata.normalize("NFC", s)
    out = []
    for ch in s:
        v = ord(ch)
        if v == 0x3000:
            out.append(" ")
        elif 0xFF01 <= v <= 0xFF5E:
            out.append(chr(v - 0xFEE0))
        else:
            out.append(ch)
    return "".join(out)


def tokenize(s: str):
    return re.findall(r"\d+|\D+", s)


def cmp_numbers(a: str, b: str) -> int:
    x, y = a.lstrip("0") or "0", b.lstrip("0") or "0"
    if len(x) != len(y):
        return -1 if len(x) < len(y) else 1
    return (x > y) - (x < y)


def cmp_text(a: str, b: str) -> int:
    return (a > b) - (a < b)


def natural_less(a_raw: str, b_raw: str) -> bool:
    a, b = normalize(a_raw), normalize(b_raw)
    if a == b:
        return a_raw < b_raw
    ta, tb = tokenize(a), tokenize(b)
    for x, y in zip(ta, tb):
        if x.isdigit() and y.isdigit():
            r = cmp_numbers(x, y)
        else:
            r = cmp_text(x, y)
        if r:
            return r < 0
    return len(ta) < len(tb)


def natural_cmp(a, b):
    return 0 if a == b else (-1 if natural_less(a, b) else 1)


def natural_sorted(items, key=lambda x: x):
    return sorted(items, key=cmp_to_key(lambda x, y: natural_cmp(key(x), key(y))))


def ext(name: str) -> str:
    return name.rsplit(".", 1)[-1].lower() if "." in name else ""


def stem(name: str) -> str:
    return name.rsplit(".", 1)[0] if "." in name else name


def is_hidden(name: str) -> bool:
    return name.startswith(".") or name in {"Thumbs.db", "desktop.ini", "放书说明.txt"}


def classify(name: str):
    e = ext(name)
    if e in TEXT_EXT:
        return "text"
    if e in IMAGE_EXT:
        return "image"
    if e in VIDEO_EXT:
        return "video"
    if e in AUDIO_EXT:
        return "audio"
    return None


def image_sequence(name: str):
    s = normalize(stem(name))
    return int(s) if s.isdigit() else None


def animated_by_ext(url: Path) -> bool:
    return ext(url.name) in ANIMATED_EXT


@dataclass
class MediaItem:
    url: Path
    kind: str
    sequence: int | None
    is_animated: bool = False

    @property
    def file_name(self):
        return self.url.name


@dataclass
class Chapter:
    url: Path
    raw_name: str
    title: str
    kind: str = "folder"      # folder / file / slice
    group: str | None = None
    start: int | None = None  # slice 起始偏移(AST 码点，示例文本均为 BMP)
    length: int | None = None

    @property
    def display_title(self):
        if self.group and self.group != self.title:
            return f"{self.group} · {self.title}"
        return self.title


@dataclass
class ChapterContent:
    chapter: Chapter
    text_url: Path | None
    images: list[MediaItem]
    av: list[MediaItem]
    ignored: list[str] = field(default_factory=list)
    pdf_url: Path | None = None


@dataclass
class Book:
    path: Path
    title: str
    category: str
    chapters: list[Chapter]
    series: str | None = None


def resolve_chapter(ch: Chapter, animated_detector=animated_by_ext) -> ChapterContent:
    if ch.kind != "folder":
        if ext(ch.url.name) == "pdf":
            return ChapterContent(ch, None, [], [], [], ch.url)
        return ChapterContent(ch, ch.url, [], [], [], None)
    if not ch.url.is_dir():
        return ChapterContent(ch, None, [], [], [], None)

    texts, images, av, ignored = [], [], [], []
    pdf_url = None
    for p in sorted(ch.url.iterdir(), key=lambda x: x.name):
        name = p.name
        if is_hidden(name) or not p.is_file():
            continue
        if ext(name) == "pdf":
            if pdf_url is None:
                pdf_url = p
            else:
                ignored.append(name)
            continue
        kind = classify(name)
        if kind is None:
            ignored.append(name)
            continue
        if kind == "text":
            texts.append(p)
        elif kind == "image":
            anim = animated_detector(p)
            images.append(MediaItem(p, "animatedImage" if anim else "image",
                                    image_sequence(name), anim))
        elif kind in ("video", "audio"):
            av.append(MediaItem(p, kind, None))

    texts = natural_sorted(texts, key=lambda p: p.name)
    text_url = texts[0] if texts else None
    ignored += [p.name for p in texts[1:]]

    with_seq = [m for m in images if m.sequence is not None]
    no_seq = [m for m in images if m.sequence is None]

    def seq_cmp(a, b):
        sc = (a.sequence > b.sequence) - (a.sequence < b.sequence)
        return sc if sc else natural_cmp(a.file_name, b.file_name)

    with_seq.sort(key=cmp_to_key(seq_cmp))
    no_seq = natural_sorted(no_seq, key=lambda m: m.file_name)
    av = natural_sorted(av, key=lambda m: m.file_name)
    return ChapterContent(ch, text_url, with_seq + no_seq, av, ignored, pdf_url)


def subdirectories(folder: Path):
    if not folder.is_dir():
        return []
    dirs = [p for p in folder.iterdir() if p.is_dir() and not is_hidden(p.name)]
    return natural_sorted(dirs, key=lambda p: p.name)


def files_in(folder: Path):
    if not folder.is_dir():
        return []
    return [p for p in folder.iterdir() if p.is_file() and not is_hidden(p.name)]


# ---------------- 小说 ----------------

def scan_novel(root: Path):
    """每个电子书文件一本书；根目录下的子文件夹 = 一个系列（"系列 · 子系列"）"""
    found: list[tuple[Path, str | None]] = []

    def collect(d: Path, depth: int, series: list[str]):
        for p in sorted(d.iterdir()):
            if is_hidden(p.name):
                continue
            if p.is_dir():
                if depth < 3:
                    collect(p, depth + 1, series + [p.name])
            elif ext(p.name) in NOVEL_EXT:
                found.append((p, " · ".join(series) if series else None))

    if root.is_dir():
        collect(root, 0, [])
    books = [Book(p, stem(p.name), "novel",
                  [Chapter(p, p.name, stem(p.name), "slice")], series)
             for p, series in found]
    return natural_sorted(books, key=lambda b: b.title)


# ---------------- 漫画 ----------------

def collect_comic(dir_path: Path, book_root: Path, depth: int, group: list[str]):
    if depth > 5:
        return []
    images = [p for p in files_in(dir_path) if ext(p.name) in IMAGE_EXT]
    pdfs = [p for p in files_in(dir_path) if ext(p.name) == "pdf"]
    is_root = dir_path == book_root

    chapters: list[Chapter] = []
    if images:
        chapters.append(Chapter(dir_path, dir_path.name, dir_path.name,
                                "folder", " · ".join(group)))

    pdf_group = "" if is_root else " · ".join(group + [dir_path.name])
    for pdf in pdfs:
        chapters.append(Chapter(pdf, pdf.name, stem(pdf.name), "file", pdf_group))

    if depth < 5:
        next_group = group if is_root else group + [dir_path.name]
        for sub in subdirectories(dir_path):
            chapters += collect_comic(sub, book_root, depth + 1, next_group)
    return chapters


def scan_comic(root: Path):
    books: list[Book] = []
    for folder in subdirectories(root):
        chapters = collect_comic(folder, folder, 0, [])
        if chapters:
            books.append(Book(folder, folder.name, "comic",
                              natural_sorted(chapters, key=lambda c: c.display_title)))
    if not books and root.is_dir():
        has_media = any(ext(p.name) in IMAGE_EXT or ext(p.name) == "pdf"
                        for p in files_in(root))
        if has_media:
            chapters = collect_comic(root, root, 0, [])
            if chapters:
                books.append(Book(root, root.name, "comic", chapters))
    return books


# ---------------- 整理 ----------------

def scan_organized(root: Path):
    if not root.is_dir():
        return []
    dirs = subdirectories(root)
    media = [p for p in files_in(root) if classify(p.name) is not None]

    if not dirs:
        if not media:
            return []
        return [Book(root, root.name, "organized",
                     [Chapter(root, root.name, root.name)])]

    if subdirectories(dirs[0]):
        books = []
        for bf in dirs:
            chapters = [Chapter(cf, cf.name, cf.name) for cf in subdirectories(bf)]
            books.append(Book(bf, bf.name, "organized",
                              natural_sorted(chapters, key=lambda c: c.raw_name)))
        return natural_sorted(books, key=lambda b: b.title)

    chapters = natural_sorted([Chapter(cf, cf.name, cf.name) for cf in dirs],
                              key=lambda c: c.raw_name)
    return [Book(root, root.name, "organized", chapters)]


# ---------------- 入口 ----------------

def scan_sections(root: Path):
    """返回 (layout, books)"""
    if not root.is_dir():
        return ("unreadable", [])

    items = [p for p in root.iterdir() if not is_hidden(p.name)]
    dirs = natural_sorted([p for p in items if p.is_dir()], key=lambda p: p.name)
    has_section_child = any(p.name in SECTIONS.values() for p in dirs)

    # 情形 1：直接选中某个分区
    if root.name in SECTIONS.values() and not has_section_child:
        key = next(k for k, v in SECTIONS.items() if v == root.name)
        scanner = {"novel": scan_novel, "comic": scan_comic, "organized": scan_organized}[key]
        return ("singleSection", scanner(root))

    # 情形 2：三分区书库根
    present = [p for p in dirs if p.name in SECTIONS.values()]
    if present:
        books: list[Book] = []
        for section in present:
            key = next(k for k, v in SECTIONS.items() if v == section.name)
            scanner = {"novel": scan_novel, "comic": scan_comic,
                       "organized": scan_organized}[key]
            books += scanner(section)
        for plain in dirs:
            if plain.name not in SECTIONS.values():
                books += scan_organized(plain)
        return ("sections", natural_sorted(books, key=lambda b: b.title))

    # 情形 3：旧书库
    legacy = scan_organized(root)
    if legacy:
        return ("legacyRoot", legacy)
    return ("empty", [])


# ---------------- 分章 ----------------

HEADING_RE = re.compile(
    r"^[\s\u3000]*("
    r"第[0-9０-９一二三四五六七八九十百千万零〇两]{1,8}[章节回卷话集篇部]"
    r"|Chapter\s+\d{1,4}"
    r"|(序章|序言|楔子|引子|前言|尾声|终章|后记|番外|外传)[\s\u3000:：·、-]*"
    r")",
    re.IGNORECASE,
)


def split_text(text: str):
    """对齐 Swift ChapterSplitter.split，返回 [(title, start, length)]"""
    if not text:
        return [("", 0, 0)]
    headings = []
    pos = 0
    for line in text.splitlines(keepends=True):
        line_start = pos
        pos += len(line)
        bare = line.strip()
        if bare and len(bare) <= 48 and HEADING_RE.match(bare):
            headings.append((re.sub(r"  +", " ", bare), line_start, pos))

    if len(headings) < 2:
        return [("", 0, len(text))]

    slices = []
    if headings[0][1] > 0:
        head = text[:headings[0][1]]
        if head.strip():
            slices.append(("开篇", 0, headings[0][1]))
    for i, (title, start, body_start) in enumerate(headings):
        end = headings[i + 1][1] if i + 1 < len(headings) else len(text)
        body_start = min(body_start, end)
        if body_start < end:
            slices.append((title or f"第 {i + 1} 章", body_start, end - body_start))
        else:
            slices.append((title or f"第 {i + 1} 章", start, end - start))
    return slices


# ---------------- epub ----------------

def epub_slices(path: Path):
    """对齐 EpubParser：container.xml → opf → spine → xhtml 取文字"""
    try:
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
            result = []
            for href in names:
                link = (base + "/" + href) if base else href
                link = re.sub(r"/\./", "/", link)
                try:
                    html = z.read(link).decode("utf-8", "ignore")
                except KeyError:
                    continue
                body = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", html)
                body = re.sub(r"(?i)<br\s*/?>", "\n", body)
                body = re.sub(r"(?i)</(p|div|h[1-6]|li|tr|section|article|blockquote)>", "\n", body)
                body = re.sub(r"(?s)<[^>]+>", "", body)
                body = re.sub(r"&nbsp;", " ", body).replace("&amp;", "&")
                body = body.strip()
                if not body:
                    continue
                h = re.search(r"(?is)<h1[^>]*>(.*?)</h1>", html) or \
                    re.search(r"(?is)<title[^>]*>(.*?)</title>", html)
                title = re.sub(r"(?s)<[^>]+>", "", h.group(1)).strip() if h else ""
                result.append(title or stem(Path(href).name))
            return result
    except Exception:
        return []


# ---------------------------------------------------------------- 测试用例

PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    mark = "PASS" if cond else "FAIL"
    print(f"  [{mark}] {name}" + (f"  -> {detail}" if detail else ""))


def clean_title(raw: str) -> str:
    patterns = [
        r"^\s*[\[\(【]?\d+[\]\)】]?\s*[._\-、:：]?\s*",
        r"^\s*[\[\(【]?\d+[\]\)】]\s*",
        r"^\s*第[0-9一二三四五六七八九十百千零〇两]+[章节回部卷集篇]\s*[.、:：]?\s*",
    ]
    s = normalize(raw)
    for p in patterns:
        m = re.match(p, s)
        if m:
            s = s[m.end():]
            break
    return s.strip() or raw


def main():
    if not SAMPLE.is_dir():
        print("缺少示例书，请先运行 make_sample_book.py", file=sys.stderr)
        return 1

    print("\n== A. 自然排序 ==")
    cases = [
        ("数字按数值", ["1", "2", "10", "3"], ["1", "2", "3", "10"]),
        ("前导零", ["01", "002", "1"], ["01", "1", "002"]),
        ("全角数字", ["１０", "２", "１"], ["１", "２", "１０"]),
        ("中英混合", ["a2", "a10", "a1"], ["a1", "a2", "a10"]),
        ("章节前缀", ["第10章", "第2章", "第1章"], ["第1章", "第2章", "第10章"]),
    ]
    for label, raw, expect in cases:
        got = natural_sorted(raw)
        check(label, got == expect, f"{raw} -> {got}")

    print("\n== B. 文件名解析 ==")
    check("纯数字序号", image_sequence("12.png") == 12)
    check("前导零序号", image_sequence("003.jpg") == 3)
    check("全角序号", image_sequence("２.gif") == 2)
    check("非序号文件名", image_sequence("无序号插图.jpg") is None)
    check("中文名非序号", image_sequence("封面.png") is None)
    check("动图扩展名", animated_by_ext(Path("2.gif")) and animated_by_ext(Path("x.apng")))
    check("静态图非动图", not animated_by_ext(Path("1.png")))
    check("隐藏文件", is_hidden(".DS_Store") and is_hidden("Thumbs.db"))
    check("未知扩展名", classify("notes.docx") is None)

    print("\n== C. 三分区书库根 ==")
    layout, books = scan_sections(SAMPLE)
    check("识别为三分区根", layout == "sections", layout)
    check("小说 8 本（根目录 5 本 + 系列里 3 本）",
          len([b for b in books if b.category == "novel"]) == 8,
          str([b.title for b in books if b.category == "novel"]))
    check("漫画 2 部",
          len([b for b in books if b.category == "comic"]) == 2,
          str([b.title for b in books if b.category == "comic"]))
    check("整理 2 本",
          len([b for b in books if b.category == "organized"]) == 2,
          str([b.title for b in books if b.category == "organized"]))

    print("\n== D. 整理：章节装配（正文 → 图片 → 音视频） ==")

    def chapter_of(raw_name):
        for b in books:
            if b.category != "organized":
                continue
            for c in b.chapters:
                if c.raw_name == raw_name:
                    return resolve_chapter(c)
        raise KeyError(raw_name)

    c1 = chapter_of("01_序章")
    check("正文存在", c1.text_url is not None and c1.text_url.name == "正文.txt")
    check("图片按序号", [m.file_name for m in c1.images] == ["1.png", "2.gif", "3.jpg"],
          str([m.file_name for m in c1.images]))
    check("动图被标记", [m.is_animated for m in c1.images] == [False, True, False])
    check("章末视频", len(c1.av) == 1 and c1.av[0].kind == "video",
          str([m.file_name for m in c1.av]))

    c2 = chapter_of("02_第一章 起风了")
    check("10 排在 2 后", [m.file_name for m in c2.images][:3] == ["1.png", "2.png", "10.png"],
          str([m.file_name for m in c2.images]))
    check("无序号图排最后", c2.images[-1].file_name == "无序号插图.jpg")
    check("章末音频", len(c2.av) == 1 and c2.av[0].kind == "audio")

    c3 = chapter_of("03_第二章 无声")
    check("无图片章节", c3.images == [])
    check("无音视频章节", c3.av == [])
    check("仅有正文", c3.text_url is not None)

    c4 = chapter_of("04_空章")
    check("空章不崩溃", c4.text_url is None and c4.images == [] and c4.av == [])

    c5 = chapter_of("05_异常章")
    check("多 txt 取第一个", c5.text_url is not None and c5.text_url.name == "正文.txt")
    check("多余 txt 进忽略列表", "附录.txt" in c5.ignored, str(c5.ignored))
    check("全角数字序号", [m.file_name for m in c5.images][0] == "２.png",
          str([m.file_name for m in c5.images]))
    check("未知文件被忽略", "notes.docx" in c5.ignored)
    check("隐藏文件不参与", all(".DS_Store" not in m.file_name for m in c5.images))
    check("无序号图排在序号图后", c5.images[-1].file_name == "cover_extra.jpg")

    print("\n== E. 标题清洗（可选） ==")
    for raw, expect in [("01_序章", "序章"), ("第01章 起风了", "起风了"), ("纯标题", "纯标题")]:
        cleaned = clean_title(raw)
        check(f"clean({raw})", cleaned == expect, cleaned)

    print("\n== F. 漫画：部 → 话 多级层级 ==")
    comic_books = {b.title: b for b in books if b.category == "comic"}
    star = comic_books.get("星海旅人")
    check("漫画按文件夹成书", star is not None, str(list(comic_books)))
    if star:
        titles = [c.title for c in star.chapters]
        check("部下的图片目录各成一话", titles == ["第1话", "第2话", "第5话"], str(titles))
        check("中间层记为卷名「第1部」", star.chapters[0].group == "第1部",
              str(star.chapters[0].group))
        check("列表标题为「第1部 · 第1话」", star.chapters[0].display_title == "第1部 · 第1话",
              star.chapters[0].display_title)
        check("图片话带卷名、pdf 话不带卷名（同书混排）",
              [c.group for c in star.chapters] == ["第1部", "第1部", ""],
              str([c.group for c in star.chapters]))
        check("根目录 pdf 成单话", any(c.kind == "file" and c.title == "第5话"
                                     for c in star.chapters), str(titles))
        pdf_chapter = next(c for c in star.chapters if c.kind == "file")
        pc = resolve_chapter(pdf_chapter)
        check("pdf 单话装配为 pdf 章节", pc.pdf_url is not None and pc.text_url is None)
        check("pdf 单话无卷名（在漫画根下）", pdf_chapter.group == "",
              repr(pdf_chapter.group))

    short = comic_books.get("短篇集")
    if short:
        check("单行本 → 第1话 也能识别", short.chapters[0].group == "单行本"
              and short.chapters[0].title == "第1话",
              str([(c.group, c.title) for c in short.chapters]))

    print("\n== G. 小说：单文件自动分章 ==")
    novel_books = {b.title: b for b in books if b.category == "novel"}
    check("小说书籍标题取文件名", "风起长安" in novel_books, str(list(novel_books)))

    full = (SAMPLE / "小说" / "风起长安.txt").read_text(encoding="utf-8")
    slices = split_text(full)
    check("按「第X章」切成 3 章", len(slices) == 3, str([s[0] for s in slices]))
    check("章节标题正确", [s[0] for s in slices] == ["第一章 起风", "第二章 入城", "第三章 夜雨"],
          str([s[0] for s in slices]))
    first = full[slices[0][1]:slices[0][1] + slices[0][2]]
    check("第一章不含第二章正文", "长安城的春天" in first and "城门开了" not in first)
    check("切片正文不再重复标题行", not first.lstrip().startswith("第一章"), first[:12])

    short_slices = split_text((SAMPLE / "小说" / "无章节的短篇.txt").read_text(encoding="utf-8"))
    check("无章节标题 → 整本一章", len(short_slices) == 1, str(short_slices))

    print("\n== G2. 小说：文件夹 = 一个系列 ==")
    novels = [b for b in books if b.category == "novel"]
    loose = [b for b in novels if b.series is None]
    grouped = [b for b in novels if b.series]
    check("分区根目录的书不属于任何系列", len(loose) == 5, str([b.title for b in loose]))
    check("系列文件夹里的书带系列名",
          sorted(b.title for b in grouped) == ["前传", "第一部 启程", "第二部 归途"],
          str(sorted(b.title for b in grouped)))
    check("一层文件夹 → 系列名", all(b.series == "银河旧事"
                                 for b in grouped if b.title != "前传"),
          str([(b.title, b.series) for b in grouped]))
    check("嵌套一层 → 「系列 · 子系列」",
          any(b.series == "长篇三部曲 · 前传" for b in grouped),
          str([b.series for b in grouped]))
    names = natural_sorted({b.series for b in grouped})
    check("系列名去重并自然排序（列表顺序稳定）",
          names == ["银河旧事", "长篇三部曲 · 前传"], str(names))
    check("按系列过滤只返回该系列的书",
          len([b for b in novels if b.series == "银河旧事"]) == 2)
    check("系列内书籍标题取文件名（不带路径）",
          all("/" not in b.title for b in grouped))

    print("\n== H. epub 解析 ==")
    epub_titles = epub_slices(SAMPLE / "小说" / "样例epub.epub")
    check("按 spine 取到 3 章", len(epub_titles) == 3, str(epub_titles))
    check("章节标题取 h1", epub_titles == ["第一章 山门", "第二章 试剑", "第三章 下山"],
          str(epub_titles))

    print("\n== I. 层级识别与旧结构兼容 ==")
    with tempfile.TemporaryDirectory(prefix="ln-layout-") as td:
        base = Path(td)

        legacy = base / "旧书库"
        a1 = legacy / "作者甲"
        (a1 / "01_序章").mkdir(parents=True)
        (a1 / "02_第二章").mkdir(parents=True)
        (a1 / "01_序章" / "正文.txt").write_text("x", encoding="utf-8")
        layout, got = scan_sections(legacy)
        check("旧结构 → legacyRoot", layout == "legacyRoot", layout)
        check("旧结构 1 本 / 2 章", len(got) == 1 and len(got[0].chapters) == 2,
              f"{len(got)} / {[len(b.chapters) for b in got]}")
        check("旧结构归入整理", got[0].category == "organized", got[0].category)

        single = base / "小说"
        single.mkdir()
        (single / "一本.txt").write_text("第一章 a\nb", encoding="utf-8")
        layout, got = scan_sections(single)
        check("直接选分区 → singleSection", layout == "singleSection", layout)
        check("分区内 1 本小说", len(got) == 1 and got[0].category == "novel")

        three = base / "三分区"
        (three / "小说").mkdir(parents=True)
        (three / "漫画").mkdir()
        (three / "整理").mkdir()
        (three / "小说" / "书.txt").write_text("第一章 x", encoding="utf-8")
        (three / "漫画" / "漫" / "第1话").mkdir(parents=True)
        (three / "漫画" / "漫" / "第1话" / "1.jpg").write_bytes(b"x")
        (three / "整理" / "作者" / "第1章").mkdir(parents=True)
        (three / "整理" / "作者" / "第1章" / "正文.txt").write_text("x", encoding="utf-8")
        layout, got = scan_sections(three)
        check("三分区根识别", layout == "sections", layout)
        check("三本书各归其类",
              {b.category for b in got} == {"novel", "comic", "organized"},
              str([(b.title, b.category) for b in got]))

        empty = base / "空目录"
        empty.mkdir()
        check("空目录 → empty", scan_sections(empty)[0] == "empty")

    print(f"\n结果：{len(PASS)} 通过 / {len(FAIL)} 失败")
    if FAIL:
        print("失败项：" + ", ".join(FAIL))
        return 1
    print("S1 Core 算法等价验证通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
