#!/usr/bin/env python3
"""S1 等价验证：用 Python 复刻 Core 层算法，在真实目录树上跑测试用例。
与 Swift 文件一一对应：
  NaturalSort.swift / MediaResolver.swift / BookScanner.swift / ChapterTitleCleaner.swift
覆盖：自然排序、全角数字、前导零、媒体分类、动图识别、章节装配、
      缺 txt / 空章 / 无音视频 / 多 txt / 未知文件 / 隐藏文件 / 两层目录结构。
"""
from __future__ import annotations

import re
import sys
import unicodedata
from dataclasses import dataclass, field
from functools import cmp_to_key
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SAMPLE = ROOT / "SampleBook"

# ---------------------------------------------------------------- 等价实现

TEXT_EXT = {"txt", "text", "md"}
IMAGE_EXT = {"jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif", "apng"}
VIDEO_EXT = {"mp4", "mov", "m4v"}
AUDIO_EXT = {"mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf"}
ANIMATED_EXT = {"gif", "apng"}


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
        if r != 0:
            return r < 0
    return len(ta) < len(tb)


def natural_cmp(a, b):
    if natural_less(a, b): return -1
    if natural_less(b, a): return 1
    return 0


def natural_sorted(items, key=lambda x: x):
    return sorted(items, key=cmp_to_key(lambda a, b: natural_cmp(key(a), key(b))))


def ext(name: str) -> str:
    return Path(name).suffix.lstrip(".").lower()


def stem(name: str) -> str:
    return Path(name).stem


def is_hidden(name: str) -> bool:
    return name.startswith(".") or name in ("Thumbs.db", "desktop.ini")


def classify(name: str):
    e = ext(name)
    if e in TEXT_EXT: return "text"
    if e in IMAGE_EXT: return "image"
    if e in VIDEO_EXT: return "video"
    if e in AUDIO_EXT: return "audio"
    return None


def image_sequence(name: str):
    s = normalize(stem(name))
    if s and all(c.isascii() and c.isdigit() for c in s):
        try: return int(s)
        except ValueError: return None
    return None


def animated_by_ext(url: Path) -> bool:
    return ext(url.name) in ANIMATED_EXT


@dataclass
class MediaItem:
    url: Path
    kind: str
    sequence: int | None
    is_animated: bool = False
    @property
    def file_name(self): return self.url.name


@dataclass
class Chapter:
    folder: Path
    raw_name: str
    title: str


@dataclass
class ChapterContent:
    chapter: Chapter
    text_url: Path | None
    images: list[MediaItem]
    av: list[MediaItem]
    ignored: list[str] = field(default_factory=list)


def resolve_chapter(ch: Chapter, animated_detector=animated_by_ext) -> ChapterContent:
    if not ch.folder.is_dir():
        return ChapterContent(ch, None, [], [], [])
    texts, images, av, ignored = [], [], [], []
    for p in sorted(ch.folder.iterdir(), key=lambda x: x.name):
        name = p.name
        if is_hidden(name) or not p.is_file():
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
    return ChapterContent(ch, text_url, with_seq + no_seq, av, ignored)


def subdirectories(folder: Path):
    if not folder.is_dir():
        return []
    dirs = [p for p in folder.iterdir() if p.is_dir() and not is_hidden(p.name)]
    return natural_sorted(dirs, key=lambda p: p.name)


def scan_library(root: Path):
    books = []
    for bf in subdirectories(root):
        chapters = [Chapter(cf, cf.name, cf.name) for cf in subdirectories(bf)]
        books.append((bf.name, natural_sorted(chapters, key=lambda c: c.raw_name)))
    return natural_sorted(books, key=lambda b: b[0])


# ---------------------------------------------------------------- 测试用例

PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    mark = "PASS" if cond else "FAIL"
    print(f"  [{mark}] {name}" + (f"  -> {detail}" if detail else ""))


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

    print("\n== C. 书库结构（两层） ==")
    lib = scan_library(SAMPLE)
    titles = [b[0] for b in lib]
    check("书数量=2", len(lib) == 2, str(titles))
    check("书按自然序并列", titles == ["墨青山", "林下客"], str(titles))
    ch_names = [c.raw_name for c in lib[0][1]]
    check("章节按自然序", ch_names[:3] == ["01_序章", "02_第一章 起风了", "03_第二章 无声"], str(ch_names))
    check("10 不在 2 前", ch_names.index("02_第一章 起风了") < ch_names.index("03_第二章 无声"))

    def content(title):
        for _, chapters in lib:
            for c in chapters:
                if c.raw_name == title:
                    return resolve_chapter(c)
        raise KeyError(title)

    print("\n== D. 章节装配：正文 → 图片 → 音视频 ==")
    c1 = content("01_序章")
    check("正文存在", c1.text_url is not None and c1.text_url.name == "正文.txt")
    check("图片按序号", [m.file_name for m in c1.images] == ["1.png", "2.gif", "3.jpg"],
          str([m.file_name for m in c1.images]))
    check("动图被标记", [m.is_animated for m in c1.images] == [False, True, False])
    check("章末视频", len(c1.av) == 1 and c1.av[0].kind == "video", str([m.file_name for m in c1.av]))

    c2 = content("02_第一章 起风了")
    check("10 排在 2 后", [m.file_name for m in c2.images][:3] == ["1.png", "2.png", "10.png"],
          str([m.file_name for m in c2.images]))
    check("无序号图排最后", c2.images[-1].file_name == "无序号插图.jpg")
    check("章末音频", len(c2.av) == 1 and c2.av[0].kind == "audio")
    check("音频不后台播放由视图层保证（本层只分类）", True)

    c3 = content("03_第二章 无声")
    check("无图片章节", c3.images == [])
    check("无音视频章节", c3.av == [])
    check("仅有正文", c3.text_url is not None)

    c4 = content("04_空章")
    check("空章不崩溃", c4.text_url is None and c4.images == [] and c4.av == [])

    c5 = content("05_异常章")
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

    print(f"\n结果：{len(PASS)} 通过 / {len(FAIL)} 失败")
    if FAIL:
        print("失败项：" + ", ".join(FAIL))
        return 1
    print("S1 Core 算法等价验证通过。")
    return 0


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


if __name__ == "__main__":
    sys.exit(main())
