#!/usr/bin/env python3
"""
Build airports.json for offline IFR clearance validation (Phase 2).
Extracts from FAA 28-day NASR dataset (CSV). Output: aviation_data_v2/airports.json.
Schema: identifier, name, city, state, latitude, longitude, elevation_ft, runways[], frequencies{}.
ICAO only (KXXX). Excludes private, heliports, seaplane bases, closed.
"""
from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
AVIATION_DATA = SCRIPT_DIR.parent / "aviation_data_v2"
OUT_FILE = AVIATION_DATA / "airports.json"

# NASR / FAA column name variants
ID_COLS = ("ARPT_ID", "IDENT", "LOCID", "id", "IDENTIFIER")
NAME_COLS = ("NAME", "name", "Name")
CITY_COLS = ("CITY", "SERVCITY", "city", "City")
STATE_COLS = ("STATE", "state", "State")
LAT_COLS = ("LAT_DEG", "LATITUDE", "latitude", "Y", "y")
LON_COLS = ("LONG_DEG", "LONGITUDE", "longitude", "X", "x")
ELEV_COLS = ("ELEVATION", "ELEV_ft", "elevation_ft", "ELEV")

# Facility/ownership: exclude private, heliport, seaplane, closed
TYPE_COLS = ("TYPE", "FACILITY_TYPE", "SITE_TYPE", "TYPE_CODE", "Ownership")
STATE_STATUS = ("STATE", "STATUS", "SVC_IND")  # e.g. closed

# Frequency type mapping (NASR: CLD=clearance, GND=ground, TWR=tower, DEP=departure)
FREQ_TYPE_MAP = {
    "CLD": "clearance",
    "CLR": "clearance",
    "CLEARANCE": "clearance",
    "GND": "ground",
    "GROUND": "ground",
    "TWR": "tower",
    "TOWER": "tower",
    "DEP": "departure",
    "DEPARTURE": "departure",
}


def normalize_id(s: str | None) -> str | None:
    if not s or not isinstance(s, str):
        return None
    t = s.strip().upper()
    if not t or len(t) < 3 or len(t) > 4:
        return None
    return t if re.match(r"^K[A-Z0-9]{2,3}$", t) else None


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


def should_exclude_airport(row: dict, fieldnames: list[str]) -> bool:
    """Exclude private, heliport, seaplane base, closed."""
    type_val = _pick(row, TYPE_COLS)
    if type_val:
        u = type_val.upper()
        if "HELI" in u or "H" == u or u in ("HELIPORT", "2"):
            return True
        if "SEAPLANE" in u or "WATER" in u or "S" == u or u in ("SEAPLANE BASE", "4"):
            return True
        if "PRIVATE" in u or "PR" == u or "P" == u:
            return True
    status = _pick(row, STATE_STATUS)
    if status and "CLOSED" in (status or "").upper():
        return True
    return False


def build_airports(
    airport_csv: Path,
    runway_csv: Path | None = None,
    freq_csv: Path | None = None,
) -> list[dict]:
    rows: list[dict] = []
    by_id: dict[str, dict] = {}
    # Diagnostics
    rows_read = 0
    written = 0
    skipped_missing_ident = 0
    skipped_missing_latlon = 0
    skipped_missing_name = 0
    skipped_filtered = 0
    skipped_parse_errors = 0
    used_default_latlon = 0
    used_default_name = 0
    used_default_state = 0
    wrote_samples = 0

    with open(airport_csv, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        fieldnames = list(reader.fieldnames or [])
        print("APT_BASE headers:", fieldnames, file=sys.stderr)

        def resolve(required: str, *alts: str) -> str:
            if required in fieldnames:
                return required
            for a in alts:
                if a in fieldnames:
                    return a
            # case-insensitive fallback
            upper_map = {h.upper(): h for h in fieldnames}
            for name in (required, *alts):
                if name.upper() in upper_map:
                    return upper_map[name.upper()]
            print(
                f"ERROR: Required column '{required}' not found in APT_BASE headers. "
                f"Available: {fieldnames}",
                file=sys.stderr,
            )
            sys.exit(1)

        col_arpt_id = resolve("ARPT_ID")
        col_icao_id = resolve("ICAO_ID", "ICAO")
        col_name = resolve("ARPT_NAME", "NAME")
        col_city = resolve("CITY")
        col_state = resolve("STATE_CODE")
        col_lat = resolve("LAT_DECIMAL")
        col_lon = resolve("LONG_DECIMAL")
        col_elev = resolve("ELEV")

        for row in reader:
            rows_read += 1
            # Primary identifier: ARPT_ID (LID); ICAO_ID is optional and stored separately.
            lid = (row.get(col_arpt_id) or "").strip().upper()
            icao = (row.get(col_icao_id) or "").strip().upper()
            if not lid:
                skipped_missing_ident += 1
                continue
            identifier = lid
            # Use APT_BASE decimal degrees; require both LAT_DECIMAL and LONG_DECIMAL
            lat_raw = (row.get(col_lat) or "").strip()
            lon_raw = (row.get(col_lon) or "").strip()
            if not lat_raw or not lon_raw:
                skipped_missing_latlon += 1
                continue
            try:
                lat = float(lat_raw)
                lon = float(lon_raw)
            except (ValueError, TypeError):
                skipped_parse_errors += 1
                continue
            name_src = (row.get(col_name) or "").strip()
            if not name_src:
                used_default_name += 1
            name = name_src or ""
            city = (row.get(col_city) or "").strip() or ""
            state_src = (row.get(col_state) or "").strip()
            if not state_src:
                used_default_state += 1
            state = state_src or ""
            elev_raw = (row.get(col_elev) or "").strip()
            elev = None
            if elev_raw:
                try:
                    elev = int(round(float(elev_raw)))
                except (ValueError, TypeError):
                    skipped_parse_errors += 1
                    elev = None

            by_id[identifier] = {
                "identifier": identifier,
                "icao_id": icao or None,
                "name": name.upper() if name else "",
                "city": city.upper() if city else "",
                "state": state.upper() if state else "",
                "latitude": round(lat, 3),
                "longitude": round(lon, 3),
                "elevation_ft": elev if elev is not None else None,
                "runways": [],
                "frequencies": {},
            }
            written += 1
            if wrote_samples < 3:
                print("WROTE sample row:", row, file=sys.stderr)
                wrote_samples += 1

    # Runways: ARPT_ID, RWY_ID (or RUNWAY_ID, BASE_RWY, etc.)
    if runway_csv and runway_csv.exists():
        rwy_id_cols = ("ARPT_ID", "IDENT", "LOCID", "SITE_NUMBER")
        rwy_num_cols = ("RWY_ID", "RUNWAY_ID", "BASE_RWY", "IDENT")
        with open(runway_csv, newline="", encoding="utf-8", errors="replace") as f:
            reader = csv.DictReader(f)
            for row in reader:
                aid = normalize_id(_pick(row, rwy_id_cols))
                if not aid or aid not in by_id:
                    continue
                rwy = (_pick(row, rwy_num_cols) or "").strip().upper()
                if rwy and rwy not in by_id[aid]["runways"]:
                    by_id[aid]["runways"].append(rwy)

    # Frequencies: ARPT_ID, TYPE (or FREQ_TYPE), FREQ (or FREQUENCY)
    if freq_csv and freq_csv.exists():
        freq_id_cols = ("ARPT_ID", "IDENT", "LOCID", "SITE_NUMBER")
        freq_type_cols = ("TYPE", "FREQ_TYPE", "FACILITY_TYPE")
        freq_val_cols = ("FREQ", "FREQUENCY", "FREQ_VALUE")
        with open(freq_csv, newline="", encoding="utf-8", errors="replace") as f:
            reader = csv.DictReader(f)
            for row in reader:
                aid = normalize_id(_pick(row, freq_id_cols))
                if not aid or aid not in by_id:
                    continue
                raw_type = (_pick(row, freq_type_cols) or "").strip().upper()
                key = FREQ_TYPE_MAP.get(raw_type) or FREQ_TYPE_MAP.get(raw_type[:3])
                if not key or key not in ("clearance", "ground", "tower", "departure"):
                    continue
                freq_val = (_pick(row, freq_val_cols) or "").strip()
                if not freq_val or not re.match(r"^\d{3}\.\d{1,3}$", freq_val):
                    continue
                if key not in by_id[aid]["frequencies"]:
                    by_id[aid]["frequencies"][key] = []
                if freq_val not in by_id[aid]["frequencies"][key]:
                    by_id[aid]["frequencies"][key].append(freq_val)

    for rec in by_id.values():
        rec["runways"] = sorted(rec["runways"])
        rec["frequencies"] = {k: v for k, v in rec["frequencies"].items() if v}

    # Summary diagnostics
    print(
        f"Airports summary: rows={rows_read} written={written} "
        f"skippedMissingIdent={skipped_missing_ident} "
        f"skippedMissingLatLon={skipped_missing_latlon} "
        f"skippedMissingParseErrors={skipped_parse_errors}",
        file=sys.stderr,
    )

    return [by_id[k] for k in sorted(by_id.keys())]


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Build airports.json from NASR CSV (Phase 2 → aviation_data_v2)")
    parser.add_argument("--airport-csv", type=Path, required=True, help="NASR Airport CSV (ARPT_ID, NAME, CITY, STATE, LAT_DEG, LONG_DEG, ELEVATION, TYPE)")
    parser.add_argument("--runway-csv", type=Path, default=None, help="Optional: NASR Runway CSV (ARPT_ID, RWY_ID)")
    parser.add_argument("--freq-csv", type=Path, default=None, help="Optional: NASR Airport Frequency CSV (ARPT_ID, TYPE, FREQ)")
    parser.add_argument("-o", "--output", type=Path, default=OUT_FILE, help="Output JSON path")
    args = parser.parse_args()

    if not args.airport_csv.exists():
        print(f"Airport CSV not found: {args.airport_csv}", file=sys.stderr)
        sys.exit(1)

    out_list = build_airports(args.airport_csv, args.runway_csv, args.freq_csv)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_list, f, separators=(",", ":"), ensure_ascii=False)
    print(f"Wrote {len(out_list)} airports to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
