#!/usr/bin/env python3
"""生成与用户真实结构一致的示例书。

三分区结构：
  小说/   每个文件一本书（txt / epub / pdf）
  漫画/   漫画名 → 第几部 → 第几话 → 图片；另有 pdf 单话
  整理/   作者名 → 章节名 → txt + 序号图片 + 动图 + 音视频

用途：给 S1 等价验证提供真实目录树，也作为 Xcode 工程里可直接导入的样例数据。
仅使用本地 Pillow + reportlab + zipfile，不联网。
"""
from pathlib import Path
import shutil
import subprocess
import zipfile

from PIL import Image, ImageDraw
from reportlab.pdfgen import canvas

ROOT = Path(__file__).resolve().parent.parent / "SampleBook"


def png(path: Path, label: str, color=(70, 110, 170), size=(480, 300)):
    img = Image.new("RGB", size, color)
    d = ImageDraw.Draw(img)
    d.rectangle([20, 20, size[0] - 20, size[1] - 20], outline=(255, 255, 255), width=3)
    d.text((40, 130), label, fill=(255, 255, 255))
    img.save(path)


def animated_gif(path: Path):
    frames = []
    for i, c in enumerate([(190, 80, 80), (80, 170, 90), (80, 100, 200)]):
        im = Image.new("RGB", (480, 300), c)
        d = ImageDraw.Draw(im)
        d.ellipse([60 + i * 90, 90, 200 + i * 90, 230], fill=(255, 255, 255))
        d.text((40, 40), f"frame {i + 1}", fill=(255, 255, 255))
        frames.append(im)
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=400, loop=0)


def make_video(path: Path):
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "lavfi", "-i", "testsrc=size=480x300:rate=15:duration=3",
        "-f", "lavfi", "-i", "sine=frequency=440:duration=3",
        "-c:v", "libopenh264", "-b:v", "800k", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-shortest", str(path),
    ], check=True)


def make_audio(path: Path):
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "lavfi", "-i", "sine=frequency=660:duration=3",
        "-c:a", "aac", str(path),
    ], check=True)


def make_pdf(path: Path, pages):
    c = canvas.Canvas(str(path), pagesize=(480, 700))
    for i, text in enumerate(pages):
        c.setFont("Helvetica-Bold", 24)
        c.drawString(60, 620, text)
        c.setFont("Helvetica", 13)
        c.drawString(60, 580, f"page {i + 1} / {len(pages)}")
        c.rect(40, 80, 400, 460)
        c.showPage()
    c.save()


def make_epub(path: Path, title: str, chapters):
    """最小可用 epub：mimetype + container.xml + OPF + 若干 xhtml"""
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>""")
        items, refs = [], []
        for i, (name, body) in enumerate(chapters, start=1):
            href = f"text/ch{i:02d}.xhtml"
            items.append(f'<item id="c{i}" href="{href}" media-type="application/xhtml+xml"/>')
            refs.append(f'<itemref idref="c{i}"/>')
            z.writestr(f"OEBPS/{href}", f"""<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>{name}</title></head>
<body><h1>{name}</h1><p>{body}</p></body></html>""")
        z.writestr("OEBPS/content.opf", f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>{title}</dc:title></metadata>
  <manifest>{''.join(items)}</manifest>
  <spine>{''.join(refs)}</spine>
</package>""")


def write_text(path: Path, lines):
    path.write_text("\n\n".join(lines) + "\n", encoding="utf-8")


def main():
    if ROOT.exists():
        shutil.rmtree(ROOT)
    ROOT.mkdir(parents=True)

    # ---------------- 小说 ----------------
    novel = ROOT / "小说"
    novel.mkdir()

    write_text(novel / "风起长安.txt", [
        "第一章 起风",
        "长安城的春天来得迟，风里还带着沙。",
        "他站在城门口，忽然想起很多年前的那句话。",
        "第二章 入城",
        "城门开了，马蹄声从远处滚过来。",
        "第三章 夜雨",
        "雨下了一整夜，檐角的水滴答不停。",
    ])
    write_text(novel / "无章节的短篇.txt", ["这篇没有章节标题。", "整本会被当成一章显示。"])

    make_epub(novel / "样例epub.epub", "样例 EPUB", [
        ("第一章 山门", "山门外站着一个少年。"),
        ("第二章 试剑", "剑锋上还有昨夜的血。"),
        ("第三章 下山", "他背着剑，走下石阶。"),
    ])
    make_pdf(novel / "样例pdf.pdf", ["Chapter 1 旧城", "Chapter 2 灯火"])

    # ---------------- 漫画 ----------------
    comic = ROOT / "漫画" / "星海旅人"
    p1 = comic / "第1部" / "第1话"
    p1.mkdir(parents=True)
    for i in range(1, 4):
        png(p1 / f"{i}.jpg", f"第1部 第1话 p{i}", (40 + i * 20, 90, 150), (600, 900))
    p2 = comic / "第1部" / "第2话"
    p2.mkdir(parents=True)
    for i in range(1, 3):
        png(p2 / f"{i}.jpg", f"第1部 第2话 p{i}", (140, 60 + i * 20, 90), (600, 900))
    # 卷目录 + pdf 单话（用户提到的第二种放法）
    make_pdf(comic / "第5话.pdf", ["第5话 p1", "第5话 p2", "第5话 p3"])

    comic2 = ROOT / "漫画" / "短篇集"
    s1 = comic2 / "单行本" / "第1话"
    s1.mkdir(parents=True)
    for i in range(1, 3):
        png(s1 / f"{i}.png", f"单行本 第1话 p{i}", (90, 90, 160), (600, 900))

    # ---------------- 整理 ----------------
    b1 = ROOT / "整理" / "墨青山"

    ch1 = b1 / "01_序章"
    ch1.mkdir(parents=True)
    write_text(ch1 / "正文.txt", [
        "清晨的雾还没散，巷口那盏灯亮了一整夜。",
        "他把书合上，听见远处有人在喊自己的名字。",
        "这一去，就是很多年。",
    ])
    png(ch1 / "1.png", "插图 1", (70, 110, 170))
    animated_gif(ch1 / "2.gif")
    png(ch1 / "3.jpg", "插图 3", (150, 100, 70))
    make_video(ch1 / "序章影像.mp4")

    ch2 = b1 / "02_第一章 起风了"
    ch2.mkdir(parents=True)
    write_text(ch2 / "正文.txt", [
        "风从山脊那边过来，卷起一地枯叶。",
        "她站在门口，没有回头。",
    ])
    for n, label in [(1, "插图 1"), (2, "插图 2"), (10, "插图 10")]:
        png(ch2 / f"{n}.png", label, (60 + n * 8, 120, 140))
    png(ch2 / "无序号插图.jpg", "无序号（排在最后）", (120, 120, 120))
    make_audio(ch2 / "章末配乐.m4a")

    ch3 = b1 / "03_第二章 无声"
    ch3.mkdir(parents=True)
    write_text(ch3 / "正文.txt", ["这一章没有插图，也没有音视频。", "只有文字。"])

    ch4 = b1 / "04_空章"
    ch4.mkdir(parents=True)

    ch5 = b1 / "05_异常章"
    ch5.mkdir(parents=True)
    write_text(ch5 / "正文.txt", ["用于验证多个 txt 时取自然序第一个。"])
    write_text(ch5 / "附录.txt", ["这个文件应被忽略。"])
    png(ch5 / "２.png", "全角数字文件名", (100, 160, 100))
    png(ch5 / "cover_extra.jpg", "无序号图", (90, 90, 160))
    (ch5 / "notes.docx").write_text("unknown", encoding="utf-8")
    (ch5 / ".DS_Store").write_bytes(b"hidden")

    b2 = ROOT / "整理" / "林下客"
    ch6 = b2 / "第一章 夜行"
    ch6.mkdir(parents=True)
    write_text(ch6 / "正文.txt", ["第二本书，用来验证书库并列显示。", "夜色很深。"])
    png(ch6 / "1.png", "第二本书插图", (130, 90, 150))

    print(f"示例书已生成：{ROOT}")
    for p in sorted(ROOT.rglob("*")):
        if p.is_file():
            print("  ", p.relative_to(ROOT))


if __name__ == "__main__":
    main()
