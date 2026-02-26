#!/usr/bin/env python3
"""
Build fixes.json for offline IFR clearance validation (replaces waypoints in this pipeline).
Extracts RNAV waypoints, intersections, named fixes from FAA 28-day NASR dataset (CSV).
Output: aviation_data/fixes.json. Schema: identifier, latitude, longitude.
No airway structure. Uppercase identifiers, no duplicates, sorted alphabetically.
"""
from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
AVIATION_DATA = SCRIPT_DIR.parent / "aviation_data"
OUT_FILE = AVIATION_DATA / "fixes.json"

ID_COLS = ("IDENT", "id", "IDENTIFIER", "FIX_ID")
LAT_COLS = ("LAT_DEG", "LATITUDE", "latitude", "Y", "y")
LON_COLS = ("LONG_DEG", "LONGITUDE", "longitude", "X", "x")


def normalize_id(s: str | None) -> str | None:
    if not s or not isinstance(s, str):
        return None
    t = s.strip().upper()
    return t if t and re.match(r"^[A-Z0-9]{2,5}$", t) else None


def _pick(row: dict, *col_groups: tuple[str, ...]) -> str | None:
    for cols in col_groups:
        for c in cols:
            if c in row:
                v = (row.get(c) or "").strip()
                if v:
                    return v
    return None


def _float(row: dict, *col_groups: tuple[str, ...]) -> float | None:
    v = _pick(row, *col_groups)
    if v is None:
        return None
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


def build_fixes(csv_path: Path) -> list[dict]:
    by_id: dict[str, dict] = {}
    with open(csv_path, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ident = normalize_id(_pick(row, ID_COLS))
            if not ident:
                continue
            if ident in by_id:
                continue
            lat = _float(row, LAT_COLS)
            lon = _float(row, LON_COLS)
            if lat is None or lon is None:
                continue
            by_id[ident] = {
                "identifier": ident,
                "latitude": round(lat, 3),
                "longitude": round(lon, 3),
            }
    return [by_id[k] for k in sorted(by_id.keys())]


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Build fixes.json from NASR Designated Points / FIX CSV")
    parser.add_argument("--csv", type=Path, required=True, help="NASR Fix/Designated Point CSV (IDENT, LAT_DEG, LONG_DEG)")
    parser.add_argument("-o", "--output", type=Path, default=OUT_FILE, help="Output JSON path")
    args = parser.parse_args()

    if not args.csv.exists():
        print(f"CSV not found: {args.csv}", file=sys.stderr)
        sys.exit(1)

    out_list = build_fixes(args.csv)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_list, f, separators=(",", ":"), ensure_ascii=False)
    print(f"Wrote {len(out_list)} fixes to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
