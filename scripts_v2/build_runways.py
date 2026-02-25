#!/usr/bin/env python3
"""
Build runways.json from FAA NASR APT_RWY.csv + APT_RWY_END.csv.
Joins on (ARPT_ID, RWY_ID). Output: aviation_data_v2/runways.json.
Streams CSVs; uses real FAA column names only.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
AVIATION_DATA = SCRIPT_DIR.parent / "aviation_data_v2"
OUT_FILE = AVIATION_DATA / "runways.json"


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


def _float_or_none(s: str | None):
    if not s:
        return None
    try:
        return float(s)
    except (ValueError, TypeError):
        return None


def build_runways(rwy_csv: Path, rwy_end_csv: Path) -> tuple[list[dict], dict[str, int]]:
    # key (arpt_id, rwy_id) -> runway record with ends[]
    runways: dict[tuple[str, str], dict] = {}
    stats = {
        "totalRowsRead": 0,
        "totalEndRowsRead": 0,
        "totalWritten": 0,
        "skippedMissingArptRwy": 0,
        "skippedParseErrors": 0,
    }

    with open(rwy_csv, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["totalRowsRead"] += 1
            arpt = _strip(row, "ARPT_ID")
            rwy_id = _strip(row, "RWY_ID")
            if not arpt or not rwy_id:
                stats["skippedMissingArptRwy"] += 1
                continue
            arpt = arpt.upper()
            rwy_id = rwy_id.upper()
            key = (arpt, rwy_id)
            if key in runways:
                continue
            length_ft = _int_or_none(_strip(row, "RWY_LEN"))
            width_ft = _int_or_none(_strip(row, "RWY_WIDTH"))
            surface = _strip(row, "SURFACE_TYPE_CODE")
            lighting = _strip(row, "RWY_LGT_CODE")
            runways[key] = {
                "airport_identifier": arpt,
                "runway_id": rwy_id,
                "length_ft": length_ft,
                "width_ft": width_ft,
                "surface": surface or None,
                "lighting": lighting or None,
                "ends": [],
            }
            stats["totalWritten"] += 1

    with open(rwy_end_csv, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["totalEndRowsRead"] += 1
            arpt = _strip(row, "ARPT_ID")
            rwy_id = _strip(row, "RWY_ID")
            end_id = _strip(row, "RWY_END_ID")
            if not arpt or not rwy_id:
                continue
            key = (arpt.upper(), rwy_id.upper())
            if key not in runways:
                continue
            lat = _float_or_none(_strip(row, "LAT_DECIMAL"))
            lon = _float_or_none(_strip(row, "LONG_DECIMAL"))
            elev = _float_or_none(_strip(row, "RWY_END_ELEV")) or _int_or_none(_strip(row, "RWY_END_ELEV"))
            true_align = _strip(row, "TRUE_ALIGNMENT")
            ils_type = _strip(row, "ILS_TYPE")
            disp = _int_or_none(_strip(row, "DISPLACED_THR_LEN"))
            tdz = _float_or_none(_strip(row, "TDZ_ELEV")) or _int_or_none(_strip(row, "TDZ_ELEV"))
            end = {
                "end_id": end_id or "",
                "latitude": round(lat, 3) if lat is not None else None,
                "longitude": round(lon, 3) if lon is not None else None,
                "elevation_ft": elev,
                "true_alignment": true_align or None,
                "ils_type": ils_type or None,
                "displaced_threshold_ft": disp,
                "tdz_elev_ft": tdz,
            }
            runways[key]["ends"].append(end)

    out_list = []
    for (arpt, rwy_id) in sorted(runways.keys()):
        rec = runways[(arpt, rwy_id)]
        rec["ends"] = sorted(rec["ends"], key=lambda e: (e["end_id"] or ""))
        out_list.append(rec)

    return out_list, stats


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Build runways.json from APT_RWY + APT_RWY_END")
    parser.add_argument("--rwy-csv", type=Path, required=True, help="APT_RWY.csv")
    parser.add_argument("--rwy-end-csv", type=Path, required=True, help="APT_RWY_END.csv")
    parser.add_argument("-o", "--output", type=Path, default=OUT_FILE, help="Output JSON path")
    args = parser.parse_args()

    if not args.rwy_csv.exists():
        print(f"CSV not found: {args.rwy_csv}", file=sys.stderr)
        sys.exit(1)
    if not args.rwy_end_csv.exists():
        print(f"CSV not found: {args.rwy_end_csv}", file=sys.stderr)
        sys.exit(1)

    out_list, stats = build_runways(args.rwy_csv, args.rwy_end_csv)

    if not out_list:
        print("ERROR: runways output is empty; refusing to write.", file=sys.stderr)
        sys.exit(1)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_list, f, separators=(",", ":"), ensure_ascii=False)

    print(
        f"Runways summary: rows={stats['totalRowsRead']} end_rows={stats['totalEndRowsRead']} "
        f"written={stats['totalWritten']} skippedMissingArptRwy={stats['skippedMissingArptRwy']} "
        f"skippedParseErrors={stats['skippedParseErrors']}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
