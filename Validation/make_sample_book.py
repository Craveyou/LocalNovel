#!/usr/bin/env python3
"""生成与用户真实结构一致的示例书（作者文件夹 / 章节文件夹 / txt+图片+动图+音视频）。
用途：给 S1 等价验证提供真实目录树，也作为 Xcode 工程里可直接导入的样例数据。
仅使用本地 Pillow + ffmpeg，不联网。
"""
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent / "SampleBook"


def png(path: Path, label: str, color=(70, 110, 170)):
    img = Image.new("RGB", (480, 300), color)
    d = ImageDraw.Draw(img)
    d.rectangle([20, 20, 460, 280], outline=(255, 255, 255), width=3)
    d.text((40, 130), label, fill=(255, 255, 255))
    img.save(path)
    return img


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


def write_text(path: Path, lines):
    path.write_text("\n\n".join(lines) + "\n", encoding="utf-8")


def main():
    if ROOT.exists():
        shutil.rmtree(ROOT)
    ROOT.mkdir(parents=True)

    # 书 1：墨青山
    b1 = ROOT / "墨青山"

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

    # 书 2：林下客
    b2 = ROOT / "林下客"
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
