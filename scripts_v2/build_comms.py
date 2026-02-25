#!/usr/bin/env python3
"""
Build comms.json from FAA NASR COM.csv.
Uses COMM_LOC_ID as outlet_id when present; for rows with blank COMM_LOC_ID (no COM_OUTLET_ID
in this bundle), uses a deterministic synthetic id: SYN:<sha1(canonical_key)> so we retain
those rows without breaking stability across cycles.
Output: aviation_data_v2/comms.json. Same schema; no duplicate ids.
"""
from __future__ import annotations

import csv
import hashlib
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
AVIATION_DATA = SCRIPT_DIR.parent / "aviation_data_v2"
OUT_FILE = AVIATION_DATA / "comms.json"

# Fixed order for canonical synthetic key (deterministic across cycles). Excludes EFF_DATE.
SYNTHETIC_KEY_FIELDS = [
    "COMM_TYPE",
    "COMM_OUTLET_NAME",
    "FACILITY_ID",
    "NAV_ID",
    "NAV_TYPE",
    "CITY",
    "STATE_CODE",
    "REGION_CODE",
    "COUNTRY_CODE",
    "LAT_DECIMAL",
    "LONG_DECIMAL",
]


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


def _canonical_value(row: dict, key: str) -> str:
    """Strip, uppercase; empty or missing -> ""."""
    v = _strip(row, key)
    if not v:
        return ""
    return v.upper()


def _build_synthetic_id(row: dict) -> str:
    """Build deterministic id for rows with blank COMM_LOC_ID. Uses SHA1 of canonical key."""
    parts: list[str] = []
    for key in SYNTHETIC_KEY_FIELDS:
        if key in ("LAT_DECIMAL", "LONG_DECIMAL"):
            v = _float_or_none(_strip(row, key))
            parts.append(f"{v:.6f}" if v is not None else "")
        else:
            parts.append(_canonical_value(row, key))
    canonical = "|".join(parts)
    digest = hashlib.sha1(canonical.encode("utf-8")).hexdigest()
    return f"SYN:{digest}"


def build_comms(csv_path: Path) -> tuple[list[dict], dict[str, int]]:
    out_list: list[dict] = []
    seen_ids: set[str] = set()
    stats = {
        "totalRowsRead": 0,
        "totalWritten": 0,
        "writtenWithCommLocId": 0,
        "writtenWithSyntheticId": 0,
        "skippedParseErrors": 0,
        "skippedDuplicateId": 0,
    }

    with open(csv_path, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["totalRowsRead"] += 1
            try:
                outlet_id = _strip(row, "COMM_LOC_ID") or _strip(row, "COM_OUTLET_ID")
                if not outlet_id:
                    outlet_id = _build_synthetic_id(row)
                    if outlet_id in seen_ids:
                        stats["skippedDuplicateId"] += 1
                        continue
                    seen_ids.add(outlet_id)
                    stats["writtenWithSyntheticId"] += 1
                else:
                    if outlet_id in seen_ids:
                        stats["skippedDuplicateId"] += 1
                        continue
                    seen_ids.add(outlet_id)
                    stats["writtenWithCommLocId"] += 1

                lat = _float_or_none(_strip(row, "LAT_DECIMAL"))
                lon = _float_or_none(_strip(row, "LONG_DECIMAL"))
                rec = {
                    "outlet_id": outlet_id,
                    "name": _strip(row, "COMM_OUTLET_NAME") or None,
                    "type": _strip(row, "COMM_OUTLET_TYPE") or _strip(row, "COMM_TYPE") or None,
                    "state": _strip(row, "STATE_CODE") or None,
                    "country": _strip(row, "COUNTRY_CODE") or None,
                    "latitude": round(lat, 3) if lat is not None else None,
                    "longitude": round(lon, 3) if lon is not None else None,
                    "artcc_id": _strip(row, "ARTCC_ID") or _strip(row, "FACILITY_ID") or None,
                }
                out_list.append(rec)
                stats["totalWritten"] += 1
            except Exception:
                stats["skippedParseErrors"] += 1
                continue

    return out_list, stats


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Build comms.json from COM.csv")
    parser.add_argument("--csv", type=Path, required=True, help="COM.csv path")
    parser.add_argument("-o", "--output", type=Path, default=OUT_FILE, help="Output JSON path")
    args = parser.parse_args()

    if not args.csv.exists():
        print(f"CSV not found: {args.csv}", file=sys.stderr)
        sys.exit(1)

    out_list, stats = build_comms(args.csv)

    if not out_list:
        print("ERROR: comms output is empty; refusing to write.", file=sys.stderr)
        sys.exit(1)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_list, f, separators=(",", ":"), ensure_ascii=False)

    print(
        f"Comms summary: rows={stats['totalRowsRead']} written={stats['totalWritten']} "
        f"writtenWithCommLocId={stats['writtenWithCommLocId']} writtenWithSyntheticId={stats['writtenWithSyntheticId']} "
        f"skippedParseErrors={stats['skippedParseErrors']} skippedDuplicateId={stats['skippedDuplicateId']}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
