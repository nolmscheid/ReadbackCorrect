#!/usr/bin/env python3
"""
Build navaids.json for offline IFR clearance validation.
Extracts VOR and NDB only from FAA 28-day NASR dataset (CSV). Output: aviation_data/navaids.json.
Schema: identifier, type (VOR|NDB), name, latitude, longitude, elevation_ft.
Excludes TACAN-only. Uppercase identifiers, no duplicates, sorted alphabetically.
"""
from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
AVIATION_DATA = SCRIPT_DIR.parent / "aviation_data"
OUT_FILE = AVIATION_DATA / "navaids.json"

ID_COLS = ("IDENT", "id", "IDENTIFIER", "NAVAID_ID")
TYPE_COLS = ("TYPE", "TYPE_CODE", "NAVAID_TYPE", "type")
NAME_COLS = ("NAME", "name", "Name", "NAVAID_NAME")
LAT_COLS = ("LAT_DEG", "LATITUDE", "latitude", "Y", "y")
LON_COLS = ("LONG_DEG", "LONGITUDE", "longitude", "X", "x")
ELEV_COLS = ("ELEVATION", "ELEV_ft", "elevation_ft", "ELEV")

# Exclude TACAN-only. VOR-DME, VORTAC -> VOR.
ALLOWED_TYPES = frozenset(("VOR", "NDB", "VOR-DME", "VORTAC"))
TYPE_NORMALIZE = {"VOR-DME": "VOR", "VORTAC": "VOR"}


def normalize_id(s: str | None) -> str | None:
    if not s or not isinstance(s, str):
        return None
    t = s.strip().upper()
    return t if t and re.match(r"^[A-Z0-9]{2,4}$", t) else None


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


def _int(row: dict, *col_groups: tuple[str, ...]) -> int | None:
    v = _pick(row, *col_groups)
    if v is None:
        return None
    try:
        return int(float(v))
    except (ValueError, TypeError):
        return None


def build_navaids(csv_path: Path) -> list[dict]:
    by_id: dict[str, dict] = {}
    with open(csv_path, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_type = (_pick(row, TYPE_COLS) or "").strip().upper()
            if raw_type == "TACAN":
                continue
            if raw_type in ALLOWED_TYPES or raw_type in TYPE_NORMALIZE:
                out_type = TYPE_NORMALIZE.get(raw_type, raw_type)
            else:
                type_prefix = raw_type[:3] if len(raw_type) >= 3 else raw_type
                if type_prefix not in ("VOR", "NDB"):
                    continue
                out_type = type_prefix

            ident = normalize_id(_pick(row, ID_COLS))
            if not ident:
                continue
            if ident in by_id:
                continue
            lat = _float(row, LAT_COLS)
            lon = _float(row, LON_COLS)
            if lat is None or lon is None:
                continue
            name = (_pick(row, NAME_COLS) or "").strip() or ""
            elev = _int(row, ELEV_COLS)

            by_id[ident] = {
                "identifier": ident,
                "type": out_type,
                "name": name.upper() if name else "",
                "latitude": round(lat, 3),
                "longitude": round(lon, 3),
                "elevation_ft": elev,
            }
    return [by_id[k] for k in sorted(by_id.keys())]


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Build navaids.json from NASR Navaid CSV (VOR/NDB only)")
    parser.add_argument("--csv", type=Path, required=True, help="NASR Navaid CSV (IDENT, TYPE, NAME, LAT_DEG, LONG_DEG, ELEVATION)")
    parser.add_argument("-o", "--output", type=Path, default=OUT_FILE, help="Output JSON path")
    args = parser.parse_args()

    if not args.csv.exists():
        print(f"CSV not found: {args.csv}", file=sys.stderr)
        sys.exit(1)

    out_list = build_navaids(args.csv)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_list, f, separators=(",", ":"), ensure_ascii=False)
    print(f"Wrote {len(out_list)} navaids to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
