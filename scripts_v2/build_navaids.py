#!/usr/bin/env python3
"""
Build navaids.json for offline IFR clearance validation (Phase 2).
Parses NAV_BASE.csv from FAA 28-day NASR dataset (CSV). Output: aviation_data_v2/navaids.json.
No NAV_TYPE filtering: keep all rows with valid NAV_ID + LAT_DECIMAL/LONG_DECIMAL.
Schema: identifier, type, name, state, country, icao_region, latitude, longitude, elevation_ft,
frequency_khz_or_mhz, channel, status, tacan{}, flags{}.
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
    return t if t else None


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


def _int_or_none(s: str | None):
    if not s:
        return None
    try:
        return int(float(s))
    except (ValueError, TypeError):
        return None


def build_navaids(
    csv_path: Path,
    debug: bool = False,
) -> tuple[list[dict], dict[str, int], list[dict]]:
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
                ident_raw = _strip(row, "NAV_ID")
                if not ident_raw:
                    stats["skippedMissingIdent"] += 1
                    continue
                ident = normalize_id(ident_raw)
                if not ident:
                    stats["skippedMissingIdent"] += 1
                    continue

                if ident in by_id:
                    continue

                lat_str = _strip(row, "LAT_DECIMAL")
                lon_str = _strip(row, "LONG_DECIMAL")
                if not lat_str or not lon_str:
                    stats["skippedMissingLatLon"] += 1
                    continue
                lat = _float_or_none(lat_str)
                lon = _float_or_none(lon_str)
                if lat is None or lon is None:
                    stats["skippedParseErrors"] += 1
                    continue

                nav_type = (_strip(row, "NAV_TYPE") or "").upper()
                name = _strip(row, "NAV_NAME") or _strip(row, "NAME") or ""
                state = _strip(row, "STATE_CODE") or None
                country = _strip(row, "COUNTRY_CODE") or None
                icao_region = _strip(row, "ICAO_REGION_CODE") or None
                elev_raw = _strip(row, "ELEV")
                elevation_ft = _int_or_none(elev_raw) if elev_raw else None
                freq = _strip(row, "FREQ") or None
                channel = _strip(row, "CHANNEL") or None
                status = _strip(row, "STATUS_CODE") or None

                tacan_id = _strip(row, "TACAN_ID")
                tacan_chan = _strip(row, "TACAN_CHAN")
                tacan_call = _strip(row, "TACAN_CALL")
                tacan = {}
                if tacan_id is not None or tacan_chan is not None or tacan_call is not None:
                    tacan = {
                        "id": tacan_id,
                        "channel": tacan_chan,
                        "call": tacan_call,
                    }

                hiwas = _strip(row, "HIWAS")
                voice = _strip(row, "VOICE")
                tweb = _strip(row, "TWEB")
                fanmarker = _strip(row, "FANMARKER")
                lahso = _strip(row, "LAHSO")
                public_use = _strip(row, "PUBLIC_USE")
                flags = {
                    "hiwas": hiwas,
                    "voice": voice,
                    "tweb": tweb,
                    "fanmarker": fanmarker,
                    "lahso": lahso,
                    "public_use": public_use,
                }

                rec = {
                    "identifier": ident,
                    "type": nav_type,
                    "name": name.upper() if name else "",
                    "state": state,
                    "country": country,
                    "icao_region": icao_region,
                    "latitude": round(lat, 3),
                    "longitude": round(lon, 3),
                    "elevation_ft": elevation_ft,
                    "frequency_khz_or_mhz": freq,
                    "channel": channel,
                    "status": status,
                    "tacan": tacan,
                    "flags": flags,
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
        help="FAA NASR NAV_BASE.csv (NAV_ID,NAV_TYPE,NAV_NAME,LAT_DECIMAL,LONG_DECIMAL,FREQ,ELEV,...)",
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

    if not out_list:
        print("ERROR: navaids output is empty; refusing to write.", file=sys.stderr)
        sys.exit(1)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_list, f, separators=(",", ":"), ensure_ascii=False)

    print(
        f"Navaids summary: rows={stats['totalRowsRead']} "
        f"written={stats['totalWritten']} "
        f"skippedMissingIdent={stats['skippedMissingIdent']} "
        f"skippedMissingLatLon={stats['skippedMissingLatLon']} "
        f"skippedParseErrors={stats['skippedParseErrors']}",
        file=sys.stderr,
    )

    if args.debug and debug_samples:
        print("Sample parsed navaids (first up to 2):", file=sys.stderr)
        for rec in debug_samples:
            print(json.dumps(rec, ensure_ascii=False), file=sys.stderr)


if __name__ == "__main__":
    main()
