#!/usr/bin/env python3
"""
Build ils.json from FAA NASR ILS_BASE.csv + ILS_DME.csv + ILS_GS.csv + ILS_MKR.csv.
Joins components by common key fields (LOC_ID/ILS_ID, ARPT_ID, RWY_ID as present).
Output: aviation_data_v2/ils.json. Uses real FAA column names only.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
AVIATION_DATA = SCRIPT_DIR.parent / "aviation_data_v2"
OUT_FILE = AVIATION_DATA / "ils.json"


def _strip(row: dict, key: str) -> str | None:
    v = row.get(key)
    if v is None or not isinstance(v, str):
        return None
    t = v.strip()
    return t if t else None


def _float_or_none(s: str | None):
    if not s:
        return None
    try:
        return float(s)
    except (ValueError, TypeError):
        return None


def _all_keys(row: dict) -> dict:
    """Return dict of all non-empty string values for nesting component rows."""
    return {k: v.strip() for k, v in row.items() if isinstance(v, str) and v.strip()}


def build_ils(
    base_csv: Path,
    dme_csv: Path,
    gs_csv: Path,
    mkr_csv: Path,
) -> tuple[list[dict], dict[str, int]]:
    # key (arpt, rwy, loc_id) -> base record + components
    ils_by_key: dict[tuple[str, str, str], dict] = {}
    stats = {"baseRows": 0, "dmeRows": 0, "gsRows": 0, "mkrRows": 0, "written": 0, "skippedMissingKey": 0}

    def base_key(row: dict) -> tuple[str, str, str] | None:
        arpt = _strip(row, "ARPT_ID") or _strip(row, "LOCATION_ID")
        rwy = _strip(row, "RWY_END_ID") or _strip(row, "RWY_ID") or _strip(row, "RUNWAY_ID")
        loc = _strip(row, "ILS_LOC_ID") or _strip(row, "ILS_ID") or _strip(row, "LOC_ID") or _strip(row, "KEY")
        if not arpt or not rwy:
            return None
        return (arpt.upper(), rwy.upper(), (loc or "").upper())

    with open(base_csv, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["baseRows"] += 1
            key = base_key(row)
            if not key:
                stats["skippedMissingKey"] += 1
                continue
            arpt, rwy, loc = key
            if key in ils_by_key:
                continue
            lat = _float_or_none(_strip(row, "LAT_DECIMAL"))
            lon = _float_or_none(_strip(row, "LONG_DECIMAL"))
            ils_by_key[key] = {
                "airport_identifier": arpt,
                "runway_id": rwy,
                "ident": loc or _strip(row, "ILS_LOC_ID") or _strip(row, "ILS_ID") or _strip(row, "LOC_ID") or "",
                "frequency": _strip(row, "LOC_FREQ") or _strip(row, "FREQ") or None,
                "latitude": round(lat, 3) if lat is not None else None,
                "longitude": round(lon, 3) if lon is not None else None,
                "components": {"dme": [], "gs": [], "markers": []},
            }
            stats["written"] += 1

    def dme_key(row: dict) -> tuple[str, str, str] | None:
        arpt = _strip(row, "ARPT_ID") or _strip(row, "LOCATION_ID")
        rwy = _strip(row, "RWY_END_ID") or _strip(row, "RWY_ID") or _strip(row, "RUNWAY_ID")
        loc = _strip(row, "ILS_LOC_ID") or _strip(row, "ILS_ID") or _strip(row, "LOC_ID")
        if not arpt or not rwy:
            return None
        return (arpt.upper(), rwy.upper(), (loc or "").upper())

    with open(dme_csv, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["dmeRows"] += 1
            key = dme_key(row)
            if not key:
                continue
            if key in ils_by_key:
                ils_by_key[key]["components"]["dme"].append(_all_keys(row))
            else:
                # Match by arpt+rwy only if no exact key
                for k, rec in ils_by_key.items():
                    if k[0] == key[0] and k[1] == key[1]:
                        rec["components"]["dme"].append(_all_keys(row))
                        break

    with open(gs_csv, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["gsRows"] += 1
            key = dme_key(row)
            if not key:
                continue
            if key in ils_by_key:
                ils_by_key[key]["components"]["gs"].append(_all_keys(row))
            else:
                for k, rec in ils_by_key.items():
                    if k[0] == key[0] and k[1] == key[1]:
                        rec["components"]["gs"].append(_all_keys(row))
                        break

    with open(mkr_csv, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["mkrRows"] += 1
            key = dme_key(row)
            if not key:
                continue
            if key in ils_by_key:
                ils_by_key[key]["components"]["markers"].append(_all_keys(row))
            else:
                for k, rec in ils_by_key.items():
                    if k[0] == key[0] and k[1] == key[1]:
                        rec["components"]["markers"].append(_all_keys(row))
                        break

    out_list = [ils_by_key[k] for k in sorted(ils_by_key.keys())]
    return out_list, stats


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Build ils.json from ILS_BASE + ILS_DME + ILS_GS + ILS_MKR")
    parser.add_argument("--base-csv", type=Path, required=True, help="ILS_BASE.csv")
    parser.add_argument("--dme-csv", type=Path, required=True, help="ILS_DME.csv")
    parser.add_argument("--gs-csv", type=Path, required=True, help="ILS_GS.csv")
    parser.add_argument("--mkr-csv", type=Path, required=True, help="ILS_MKR.csv")
    parser.add_argument("-o", "--output", type=Path, default=OUT_FILE, help="Output JSON path")
    args = parser.parse_args()

    for p in (args.base_csv, args.dme_csv, args.gs_csv, args.mkr_csv):
        if not p.exists():
            print(f"CSV not found: {p}", file=sys.stderr)
            sys.exit(1)

    out_list, stats = build_ils(args.base_csv, args.dme_csv, args.gs_csv, args.mkr_csv)

    if not out_list:
        print("ERROR: ils output is empty; refusing to write.", file=sys.stderr)
        sys.exit(1)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_list, f, separators=(",", ":"), ensure_ascii=False)

    print(
        f"ILS summary: base={stats['baseRows']} dme={stats['dmeRows']} gs={stats['gsRows']} mkr={stats['mkrRows']} "
        f"written={stats['written']} skippedMissingKey={stats['skippedMissingKey']}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
