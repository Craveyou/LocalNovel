"""Validate opt-in physical-device evidence and summarize it in the run directory."""
import argparse
import json
import math
import statistics
from pathlib import Path


def records(path, prefix):
    return [json.loads(line.split(prefix, 1)[1]) for line in path.read_text(errors="replace").splitlines() if prefix in line]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--churn-log", default="MixedSessions.log")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    manifest = {row["name"]: row for row in json.loads((root / "artifacts/document-performance/manifest.json").read_text())}
    names = {"PDFSmall": "pdf-small", "PDFLarge": "pdf-large", "PDFImages": "pdf-images", "EPUBSmall": "epub-small", "EPUBLarge": "epub-large", "EPUBLongChapter": "epub-long-chapter"}
    rows = []
    lines = ["# iOS physical-device document measurements", "", "Renderer readiness, not first pixel. Warm OS caches. App physical footprint excludes WebKit child processes and GPU. Navigation polling resolution is 10 ms.", "", "| Sample | Runs | Import median ms | Open median ms | Navigation median / max ms | Full miss median ms | App peak MiB |", "|---|---:|---:|---:|---:|---:|---:|"]
    for test, sample in names.items():
        log = args.directory / (test + ".log")
        group = records(log, "XLIB_DOC_PERF ")
        if len(group) != args.runs or {r["run"] for r in group} != set(range(1, args.runs + 1)):
            raise SystemExit(f"Missing or duplicate runs: {sample}")
        if "** TEST EXECUTE SUCCEEDED **" not in log.read_text(errors="replace"):
            raise SystemExit(f"Test did not succeed: {sample}")
        for row in group:
            if row["sample"] != sample or "-physical-release" not in row["platform"] or row["source_bytes"] != manifest[sample]["bytes"]:
                raise SystemExit(f"Wrong environment or fixture: {sample}")
            values = [row[key] for key in ("import_ms", "open_ms", "miss_ms", "peak_app_mib", "main_gap_ms")] + row["navigation_ms"]
            if len(row["navigation_ms"]) != 10 or not all(isinstance(v, (int, float)) and math.isfinite(v) and v >= 0 for v in values):
                raise SystemExit(f"Invalid metrics: {sample}")
        nav = [v for row in group for v in row["navigation_ms"]]
        med = lambda key: statistics.median(r[key] for r in group)
        lines.append(f"| {sample} | {len(group)} | {med('import_ms'):.1f} | {med('open_ms'):.1f} | {statistics.median(nav):.1f} / {max(nav):.1f} | {med('miss_ms'):.1f} | {max(r['peak_app_mib'] for r in group):.1f} |")
        rows.extend(group)
    churn_path = args.directory / args.churn_log
    churn = records(churn_path, "XLIB_DOC_CHURN ")
    if len(churn) != 1 or len(churn[0]["cycles"]) != 30 or "** TEST EXECUTE SUCCEEDED **" not in churn_path.read_text(errors="replace"):
        raise SystemExit("Missing successful 30-cycle mixed-session evidence")
    cycles = churn[0]["cycles"]
    if [r["cycle"] for r in cycles] != list(range(1, 31)) or not all(r["web_released"] for r in cycles):
        raise SystemExit("Mixed-session release checks failed")
    lines += ["", f"Mixed sessions: 30 cycles in {churn[0]['elapsed_ms']/1000:.1f} s; all chapter WebViews released. Closed-app footprint: {cycles[0]['closed_app_mib']:.1f} MiB first, {cycles[-1]['closed_app_mib']:.1f} MiB last, {max(r['closed_app_mib'] for r in cycles):.1f} MiB maximum. Framework caches and GPU memory are outside the release assertion."]
    (args.directory / "measurements.json").write_text(json.dumps({"samples": rows, "mixed_sessions": churn[0]}, indent=2) + "\n")
    (args.directory / "results.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
