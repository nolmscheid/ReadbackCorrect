#!/usr/bin/env python3
"""
Build airports.json for ReadBack from FAA ArcGIS US_Airport or local CSV.
Output: out/airports.json — array of {"id": "KMSP", "name": "...", "city": "...", "state": "..."}.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent / "out"
OUT_FILE = OUT_DIR / "airports.json"

# Same FAA ArcGIS server as Designated Points
FAA_US_AIRPORT_URL = (
    "https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/arcgis/rest/services/US_Airport/FeatureServer/0/query"
    "?where=1%3D1&outFields=IDENT,NAME,SERVCITY,STATE&returnGeometry=false&f=json&resultRecordCount=25000"
)


def normalize_id(s: str | None) -> str | None:
    if not s or not isinstance(s, str):
        return None
    t = s.strip().upper()
    return t if t and len(t) >= 2 and len(t) <= 4 else None


def build_from_csv(path: Path) -> list[dict]:
    rows: list[dict] = []
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            return rows
        id_col = next(
            (c for c in ("IDENT", "id", "Id", "LOCID", "IDENTIFIER") if c in (reader.fieldnames or [])),
            None,
        )
        name_col = next((c for c in ("NAME", "name", "Name") if c in (reader.fieldnames or [])), None)
        city_col = next(
            (c for c in ("SERVCITY", "city", "City", "CITY") if c in (reader.fieldnames or [])),
            None,
        )
        state_col = next((c for c in ("STATE", "state", "State") if c in (reader.fieldnames or [])), None)
        if not id_col:
            return rows
        for row in reader:
            aid = normalize_id(row.get(id_col, ""))
            if not aid:
                continue
            name = (row.get(name_col) or "").strip() or None
            city = (row.get(city_col) or "").strip() or None
            state = (row.get(state_col) or "").strip() or None
            rows.append({"id": aid, "name": name, "city": city, "state": state})
    return rows


def build_from_faa_api() -> list[dict] | None:
    try:
        import urllib.request
        req = urllib.request.Request(
            FAA_US_AIRPORT_URL,
            headers={"User-Agent": "ReadBack/1.0 (aviation data build)"},
        )
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.load(resp)
    except Exception as e:
        print("FAA US_Airport fetch failed:", e, file=sys.stderr)
        return None
    features = data.get("features") or []
    rows: list[dict] = []
    seen: set[str] = set()
    for f in features:
        att = f.get("attributes") or {}
        aid = normalize_id(att.get("IDENT") or att.get("ident") or "")
        if not aid or aid in seen:
            continue
        seen.add(aid)
        name = (att.get("NAME") or att.get("name") or "").strip() or None
        city = (att.get("SERVCITY") or att.get("city") or "").strip() or None
        state = (att.get("STATE") or att.get("state") or "").strip() or None
        rows.append({"id": aid, "name": name, "city": city, "state": state})
    return rows if rows else None


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Build airports.json for ReadBack")
    parser.add_argument("--csv", type=Path, help="Local CSV with IDENT (or id), NAME, SERVCITY, STATE")
    parser.add_argument("-o", "--output", type=Path, default=OUT_FILE, help="Output JSON path")
    parser.add_argument("--no-network", action="store_true", help="Skip FAA API; requires --csv")
    args = parser.parse_args()

    if args.csv and args.csv.exists():
        rows = build_from_csv(args.csv)
        print(f"Loaded {len(rows)} airports from CSV", file=sys.stderr)
    elif not args.no_network:
        rows = build_from_faa_api()
        if rows:
            print(f"Loaded {len(rows)} airports from FAA US_Airport API", file=sys.stderr)
        else:
            print("FAA API returned no data; use --csv with a NASR/ArcGIS export", file=sys.stderr)
            sys.exit(1)
    else:
        print("Use --csv PATH or remove --no-network to fetch from FAA", file=sys.stderr)
        sys.exit(1)

    by_id: dict[str, dict] = {}
    for r in rows:
        i = r.get("id")
        if i and i not in by_id:
            by_id[i] = r
    out_list = [by_id[k] for k in sorted(by_id.keys())]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_list, f, indent=2, ensure_ascii=False)
    print(f"Wrote {len(out_list)} airports to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
