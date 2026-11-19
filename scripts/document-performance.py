#!/usr/bin/env python3
"""Deterministic, self-authored PDF/EPUB simulator fixtures and raw-result report."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import statistics
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/document-performance"


def pdf(path, pages, images=False):
    objects = [b"", b"", b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    kids = []
    for index in range(pages):
        page_id = len(objects) + 1
        stream_id = page_id + 1
        image_id = page_id + 2
        kids.append(f"{page_id} 0 R")
        resource = f"/XObject << /Im {image_id} 0 R >>" if images else "/Font << /F1 3 0 R >>"
        objects.append(f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << {resource} >> /Contents {stream_id} 0 R >>".encode())
        if images:
            content = b"q 612 0 0 792 0 0 cm /Im Do Q"
        else:
            lines = [f"Page {index+1:04d} line {line:02d}: DOCNEEDLE original text ABC123 reading." for line in range(32)]
            content = ("BT /F1 12 Tf 36 750 Td 20 TL " + " ".join(f"({line}) Tj T*" for line in lines) + " ET").encode()
        packed = zlib.compress(content)
        objects.append(f"<< /Length {len(packed)} /Filter /FlateDecode >>\nstream\n".encode() + packed + b"\nendstream")
        if images:
            # Incompressible RGB stresses file/image IO without a third-party image library.
            raw = random.Random(13000 + index).randbytes(512 * 768 * 3)
            packed = zlib.compress(raw)
            objects.append(f"<< /Type /XObject /Subtype /Image /Width 512 /Height 768 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length {len(packed)} >>\nstream\n".encode() + packed + b"\nendstream")
    objects[0] = b"<< /Type /Catalog /Pages 2 0 R >>"
    objects[1] = f"<< /Type /Pages /Count {pages} /Kids [{' '.join(kids)}] >>".encode()
    with path.open("wb") as stream:
        stream.write(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
        offsets = [0]
        for index, obj in enumerate(objects, 1):
            offsets.append(stream.tell())
            stream.write(f"{index} 0 obj\n".encode() + obj + b"\nendobj\n")
        xref = stream.tell()
        stream.write(f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode())
        for offset in offsets[1:]:
            stream.write(f"{offset:010d} 00000 n \n".encode())
        stream.write(f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())


def epub(path, chapters, chapter_bytes):
    def entry(archive, name, value):
        info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_STORED if name == "mimetype" else zipfile.ZIP_DEFLATED
        archive.writestr(info, value)
    with zipfile.ZipFile(path, "w") as archive:
        entry(archive, "mimetype", "application/epub+zip")
        entry(archive, "META-INF/container.xml", '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>')
        manifest = ''.join(f'<item id="c{i}" href="c{i}.xhtml" media-type="application/xhtml+xml"/>' for i in range(chapters))
        spine = ''.join(f'<itemref idref="c{i}"/>' for i in range(chapters))
        entry(archive, "OPS/book.opf", f'<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><manifest>{manifest}</manifest><spine>{spine}</spine></package>')
        for i in range(chapters):
            pieces, size, line = [], 0, 0
            while size < chapter_bytes:
                # Vary the text to keep expansion well below the supported ZIP-bomb limit.
                salt = hashlib.sha256(f"{i}:{line}".encode()).hexdigest()
                text = f'<p id="p{line}">第{i+1}章 {line} 中文阅读👩‍💻é DOCNEEDLE {salt} 正文结束。</p>'
                pieces.append(text)
                size += len(text.encode())
                line += 1
            entry(archive, f"OPS/c{i}.xhtml", '<html xmlns="http://www.w3.org/1999/xhtml"><body>' + ''.join(pieces) + '</body></html>')


def generate():
    folder = OUTPUT / "fixtures"
    folder.mkdir(parents=True, exist_ok=True)
    scenarios = [("pdf-small", "pdf", 20, 0), ("pdf-large", "pdf", 1000, 0),
                 ("pdf-images", "scan", 40, 0), ("epub-small", "epub", 2, 4096),
                 ("epub-large", "epub", 64, 128*1024), ("epub-long-chapter", "epub", 2, 2*1024*1024)]
    records = []
    for name, kind, count, size in scenarios:
        path = folder / (name + (".epub" if kind == "epub" else ".pdf"))
        if kind == "epub":
            epub(path, count, size)
        else:
            pdf(path, count, kind == "scan")
        records.append(dict(name=name, file=path.name, units=count, chapter_target_bytes=size,
                            bytes=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    (OUTPUT / "manifest.json").write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(records, ensure_ascii=False, indent=2))


def report(logs):
    rows = []
    for log in logs:
        for line in Path(log).read_text(errors="replace").splitlines():
            if "XLIB_DOC_PERF " in line:
                rows.append(json.loads(line.split("XLIB_DOC_PERF ", 1)[1]))
    if not rows:
        raise SystemExit("No measured results found")
    keys = [(r['platform'], r['sample'], r['run']) for r in rows]
    if len(keys) != len(set(keys)):
        raise SystemExit("Duplicate platform/sample/run: select only one final log per sample")
    manifest = {r['name']:r for r in json.loads((OUTPUT/'manifest.json').read_text())}
    for r in rows:
        if r['source_bytes'] != manifest[r['sample']]['bytes']:
            raise SystemExit("Source size does not match generated fixture manifest")
        measured = ['import_ms','open_ms','miss_ms','peak_app_mib','main_gap_ms','reopen_ms','search_first_ms','search_second_ms']
        if not all(isinstance(r[k], (int,float)) and math.isfinite(r[k]) and r[k] >= 0 for k in measured):
            raise SystemExit("Invalid measurement")
        if len(r['navigation_ms']) != 10:
            raise SystemExit("Expected 10 measured navigations per run")
    (OUTPUT / "measurements.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n")
    lines = ["# Document simulator measurements", "", "In-process repeats; OS disk caches are not purged. Not physical-device acceptance. Polling resolution is 10 ms. Open means renderer readiness, not guaranteed first displayed pixel.", "",
             "Memory: Android application PSS / iOS application physical footprint; excludes WebView child processes. Peaks are sampled, not guaranteed absolute peaks.", "",
             "| Platform | Sample | Runs | Import median ms | Open median ms | Navigation median / max ms | Full miss median ms | App sampled peak max MiB | Main-loop max gap ms |",
             "|---|---|---:|---:|---:|---:|---:|---:|---:|"]
    for platform, sample in sorted({(r['platform'], r['sample']) for r in rows}):
        group = [r for r in rows if (r['platform'], r['sample']) == (platform, sample)]
        med = lambda key: statistics.median([r[key] for r in group])
        nav = [v for r in group for v in r['navigation_ms']]
        lines.append(f"| {platform} | {sample} | {len(group)} | {med('import_ms'):.1f} | {med('open_ms'):.1f} | {statistics.median(nav):.1f} / {max(nav):.1f} | {med('miss_ms'):.1f} | {max(r['peak_app_mib'] for r in group):.1f} | {max(r['main_gap_ms'] for r in group):.1f} |")
    (OUTPUT / "results.md").write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["generate", "report"])
    parser.add_argument("logs", nargs="*")
    args = parser.parse_args()
    generate() if args.action == "generate" else report(args.logs)
