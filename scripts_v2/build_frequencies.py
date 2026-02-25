#!/usr/bin/env python3
"""
Build frequencies.json from FAA NASR FRQ.csv.
Output: aviation_data_v2/frequencies.json. No filtering; skip only if FREQ/facility missing.
Uses real FAA column names: FREQ_TYPE, FACILITY_ID, FACILITY_TYPE, FREQ, FREQ_UNITS, etc.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
AVIATION_DATA = SCRIPT_DIR.parent / "aviation_data_v2"
OUT_FILE = AVIATION_DATA / "frequencies.json"


def _strip(row: dict, key: str) -> str | None:
    v = row.get(key)
    if v is None or not isinstance(v, str):
        return None
    t = v.strip()
    return t if t else None


def build_frequencies(csv_path: Path) -> tuple[list[dict], dict[str, int]]:
    out_list: list[dict] = []
    stats = {"totalRowsRead": 0, "totalWritten": 0, "skippedMissingFreq": 0, "skippedMissingFacility": 0}

    with open(csv_path, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["totalRowsRead"] += 1
            # FAA FRQ.csv uses FACILITY; some bundles may use FACILITY_ID
            facility_id = _strip(row, "FACILITY") or _strip(row, "FACILITY_ID")
            if not facility_id:
                stats["skippedMissingFacility"] += 1
                continue
            freq = _strip(row, "FREQ")
            if not freq:
                stats["skippedMissingFreq"] += 1
                continue
            rec = {
                "facility_id": facility_id,
                "facility_type": _strip(row, "FACILITY_TYPE") or None,
                "freq_type": _strip(row, "FREQ_TYPE") or _strip(row, "FREQ_USE") or None,
                "frequency": freq,
                "units": _strip(row, "FREQ_UNITS") or None,
                "service": _strip(row, "SERVICE") or _strip(row, "FREQ_USE") or None,
                "callsign": _strip(row, "CALL_SIGN") or _strip(row, "TOWER_OR_COMM_CALL") or _strip(row, "PRIMARY_APPROACH_RADIO_CALL") or None,
                "sector_name": _strip(row, "SECTOR_NAME") or _strip(row, "SECTORIZATION") or None,
                "comm_location": _strip(row, "COMM_LOCATION") or _strip(row, "SERVICED_FACILITY") or None,
                "remarks": _strip(row, "REMARKS") or _strip(row, "REMARK") or None,
            }
            out_list.append(rec)
            stats["totalWritten"] += 1

    return out_list, stats


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Build frequencies.json from FRQ.csv")
    parser.add_argument("--csv", type=Path, required=True, help="FRQ.csv path")
    parser.add_argument("-o", "--output", type=Path, default=OUT_FILE, help="Output JSON path")
    args = parser.parse_args()

    if not args.csv.exists():
        print(f"CSV not found: {args.csv}", file=sys.stderr)
        sys.exit(1)

    out_list, stats = build_frequencies(args.csv)

    if not out_list:
        print("ERROR: frequencies output is empty; refusing to write.", file=sys.stderr)
        sys.exit(1)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_list, f, separators=(",", ":"), ensure_ascii=False)

    print(
        f"Frequencies summary: rows={stats['totalRowsRead']} written={stats['totalWritten']} "
        f"skippedMissingFreq={stats['skippedMissingFreq']} skippedMissingFacility={stats['skippedMissingFacility']}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
