#!/usr/bin/env python3
"""
Build navaids.json for offline IFR clearance validation (Phase 2).
Parses NAV_BASE.csv from FAA 28-day NASR dataset (CSV). Output: aviation_data_v2/navaids.json.
Schema: identifier, type, name, latitude, longitude, elevation_ft.
Uppercase identifiers, no duplicates, sorted alphabetically.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
AVIATION_DATA = SCRIPT_DIR.parent / "aviation_data_v2"
OUT_FILE = AVIATION_DATA / "navaids.json"


def normalize_id(s: str | None) -> str | None:
    if not s or not isinstance(s, str):
        return None
    t = s.strip().upper()
    # NAV_ID in NAV_BASE is typically 2–4 alphanumeric characters
    return t if t and 2 <= len(t) <= 4 else None


def build_navaids(csv_path: Path, debug: bool = False) -> tuple[list[dict], dict[str, int], list[dict]]:
    by_id: dict[str, dict] = {}
    stats = {
        "totalRowsRead": 0,
        "totalWritten": 0,
        "skippedMissingIdent": 0,
        "skippedMissingLatLon": 0,
        "skippedParseErrors": 0,
    }
    debug_samples: list[dict] = []

    with open(csv_path, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []
        if debug:
            print("NAV_BASE headers (first 25):", headers[:25], file=sys.stderr)

        for row in reader:
            stats["totalRowsRead"] += 1
            try:
                ident_raw = (row.get("NAV_ID") or "").strip()
                if not ident_raw:
                    stats["skippedMissingIdent"] += 1
                    continue
                ident = normalize_id(ident_raw)
                if not ident:
                    stats["skippedMissingIdent"] += 1
                    continue

                if ident in by_id:
                    # Deduplicate by identifier; keep first
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

                name = (row.get("NAME") or "").strip()
                nav_type = (row.get("NAV_TYPE") or "").strip().upper()

                elev_ft = None
                elev_str = (row.get("ELEV") or "").strip()
                if elev_str:
                    try:
                        elev_ft = int(float(elev_str))
                    except (ValueError, TypeError):
                        stats["skippedParseErrors"] += 1
                        elev_ft = None

                rec = {
                    "identifier": ident,
                    "type": nav_type,
                    "name": name.upper() if name else "",
                    "latitude": round(lat, 3),
                    "longitude": round(lon, 3),
                    "elevation_ft": elev_ft,
                }
                by_id[ident] = rec
                stats["totalWritten"] += 1

                if debug and len(debug_samples) < 2:
                    debug_samples.append(rec)
            except Exception:
                stats["skippedParseErrors"] += 1
                continue

    out_list = [by_id[k] for k in sorted(by_id.keys())]
    return out_list, stats, debug_samples


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(
        description="Build navaids.json from NAV_BASE.csv (Phase 2 → aviation_data_v2)"
    )
    parser.add_argument(
        "--csv",
        type=Path,
        required=True,
        help="FAA NASR NAV_BASE.csv (NAV_ID,NAV_TYPE,NAME,LAT_DECIMAL,LONG_DECIMAL,FREQ,ELEV,...)",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=OUT_FILE,
        help="Output JSON path",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Print header names and first 2 parsed navaid objects",
    )
    args = parser.parse_args()

    if not args.csv.exists():
        print(f"CSV not found: {args.csv}", file=sys.stderr)
        sys.exit(1)

    out_list, stats, debug_samples = build_navaids(args.csv, debug=args.debug)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_list, f, separators=(",", ":"), ensure_ascii=False)

    # Always-on summary
    print(
        "Navaids summary:",
        f"rows={stats['totalRowsRead']}",
        f"written={stats['totalWritten']}",
        f"skippedMissingIdent={stats['skippedMissingIdent']}",
        f"skippedMissingLatLon={stats['skippedMissingLatLon']}",
        f"skippedParseErrors={stats['skippedParseErrors']}",
        file=sys.stderr,
    )

    if args.debug and debug_samples:
        print("Sample parsed navaids (first up to 2):", file=sys.stderr)
        for rec in debug_samples:
            print(json.dumps(rec, ensure_ascii=False), file=sys.stderr)


if __name__ == "__main__":
    main()
