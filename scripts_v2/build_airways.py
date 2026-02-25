#!/usr/bin/env python3
"""
Build airways.json from FAA NASR AWY_BASE.csv + AWY_SEG_ALT.csv.
Groups segments by AWY_ID, sorted by SEQNO. Output: aviation_data_v2/airways.json.
Uses real FAA column names only.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
AVIATION_DATA = SCRIPT_DIR.parent / "aviation_data_v2"
OUT_FILE = AVIATION_DATA / "airways.json"


def _strip(row: dict, key: str) -> str | None:
    v = row.get(key)
    if v is None or not isinstance(v, str):
        return None
    t = v.strip()
    return t if t else None


def _int_or_none(s: str | None):
    if not s:
        return None
    try:
        return int(float(s))
    except (ValueError, TypeError):
        return None


def build_airways(base_csv: Path, seg_csv: Path) -> tuple[list[dict], dict[str, int]]:
    # awy_id -> { base info + segments[] }
    airways: dict[str, dict] = {}
    stats = {"baseRowsRead": 0, "segRowsRead": 0, "baseWritten": 0, "segmentsAdded": 0, "skippedMissingAwyId": 0}

    with open(base_csv, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["baseRowsRead"] += 1
            awy_id = _strip(row, "AWY_ID")
            if not awy_id:
                stats["skippedMissingAwyId"] += 1
                continue
            awy_id = awy_id.upper()
            if awy_id in airways:
                continue
            airways[awy_id] = {
                "airway_id": awy_id,
                "type": _strip(row, "AWY_TYPE") or None,
                "level": _strip(row, "AWY_LEVEL") or None,
                "status": _strip(row, "STATUS_CODE") or None,
                "segments": [],
            }
            stats["baseWritten"] += 1

    with open(seg_csv, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["segRowsRead"] += 1
            awy_id = _strip(row, "AWY_ID")
            if not awy_id or awy_id.upper() not in airways:
                continue
            awy_id = awy_id.upper()
            seq = _int_or_none(_strip(row, "SEQNO"))
            seg = {
                "seq": seq,
                "fix_id": _strip(row, "FIX_ID") or None,
                "fix_type": _strip(row, "FIX_TYPE") or None,
                "nav_id": _strip(row, "NAV_ID") or None,
                "nav_type": _strip(row, "NAV_TYPE") or None,
                "artcc": _strip(row, "ARTCC_ID") or None,
                "mea": _strip(row, "MEA") or None,
                "moca": _strip(row, "MOCA") or None,
                "min_alt": _strip(row, "MIN_ALT") or None,
                "max_alt": _strip(row, "MAX_ALT") or None,
                "direction": _strip(row, "DIRECTION") or None,
            }
            airways[awy_id]["segments"].append(seg)
            stats["segmentsAdded"] += 1

    out_list = []
    for awy_id in sorted(airways.keys()):
        rec = airways[awy_id]
        rec["segments"] = sorted(rec["segments"], key=lambda s: (s["seq"] if s["seq"] is not None else -1, s.get("fix_id") or "", s.get("nav_id") or ""))
        out_list.append(rec)

    return out_list, stats


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Build airways.json from AWY_BASE + AWY_SEG_ALT")
    parser.add_argument("--base-csv", type=Path, required=True, help="AWY_BASE.csv")
    parser.add_argument("--seg-csv", type=Path, required=True, help="AWY_SEG_ALT.csv")
    parser.add_argument("-o", "--output", type=Path, default=OUT_FILE, help="Output JSON path")
    args = parser.parse_args()

    if not args.base_csv.exists():
        print(f"CSV not found: {args.base_csv}", file=sys.stderr)
        sys.exit(1)
    if not args.seg_csv.exists():
        print(f"CSV not found: {args.seg_csv}", file=sys.stderr)
        sys.exit(1)

    out_list, stats = build_airways(args.base_csv, args.seg_csv)

    if not out_list:
        print("ERROR: airways output is empty; refusing to write.", file=sys.stderr)
        sys.exit(1)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_list, f, separators=(",", ":"), ensure_ascii=False)

    print(
        f"Airways summary: base_rows={stats['baseRowsRead']} seg_rows={stats['segRowsRead']} "
        f"written={stats['baseWritten']} segments_added={stats['segmentsAdded']} "
        f"skippedMissingAwyId={stats['skippedMissingAwyId']}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
