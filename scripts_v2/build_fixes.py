#!/usr/bin/env python3
"""
Build fixes.json for offline IFR clearance validation (Phase 2).
Extracts RNAV waypoints, intersections, named fixes from FAA 28-day NASR dataset (CSV).
Output: aviation_data_v2/fixes.json. Schema: identifier, latitude, longitude.
No airway structure. Uppercase identifiers, no duplicates, sorted alphabetically.
"""
from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
AVIATION_DATA = SCRIPT_DIR.parent / "aviation_data_v2"
OUT_FILE = AVIATION_DATA / "fixes.json"


def normalize_id(s: str | None) -> str | None:
    if not s or not isinstance(s, str):
        return None
    t = s.strip().upper()
    return t if t else None


def build_fixes(csv_path: Path) -> tuple[list[dict], dict[str, int]]:
    by_id: dict[str, dict] = {}
    stats = {
        "rows": 0,
        "written": 0,
        "skippedMissingIdent": 0,
        "skippedMissingLatLon": 0,
        "skippedParseErrors": 0,
    }
    with open(csv_path, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []
        print("FIX_BASE headers:", headers, file=sys.stderr)
        for row in reader:
            stats["rows"] += 1
            ident_raw = (row.get("FIX_ID") or row.get("IDENT") or "").strip()
            if not ident_raw:
                stats["skippedMissingIdent"] += 1
                continue
            ident = normalize_id(ident_raw)
            if not ident:
                stats["skippedMissingIdent"] += 1
                continue
            if ident in by_id:
                continue

            lat_str = (row.get("LAT_DECIMAL") or "").strip()
            lon_str = (row.get("LONG_DECIMAL") or "").strip()
            if not lat_str or not lon_str:
                stats["skippedMissingLatLon"] += 1
                continue
            try:
                lat = float(lat_str)
                lon = float(lon_str)
            except (ValueError, TypeError):
                stats["skippedParseErrors"] += 1
                continue

            by_id[ident] = {
                "identifier": ident,
                "latitude": round(lat, 3),
                "longitude": round(lon, 3),
            }
            stats["written"] += 1

    out_list = [by_id[k] for k in sorted(by_id.keys())]
    return out_list, stats


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(
        description="Build fixes.json from NASR FIX_BASE.csv (Phase 2 → aviation_data_v2)"
    )
    parser.add_argument(
        "--csv",
        type=Path,
        required=True,
        help="NASR FIX_BASE.csv (FIX_ID,LAT_DECIMAL,LONG_DECIMAL,...)",
    )
    parser.add_argument(
        "-o", "--output", type=Path, default=OUT_FILE, help="Output JSON path"
    )
    args = parser.parse_args()

    if not args.csv.exists():
        print(f"CSV not found: {args.csv}", file=sys.stderr)
        sys.exit(1)

    out_list, stats = build_fixes(args.csv)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_list, f, separators=(",", ":"), ensure_ascii=False)

    print(
        f"Fixes summary: rows={stats['rows']} written={stats['written']} "
        f"skippedMissingIdent={stats['skippedMissingIdent']} "
        f"skippedMissingLatLon={stats['skippedMissingLatLon']} "
        f"skippedParseErrors={stats['skippedParseErrors']}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
