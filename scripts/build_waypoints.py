#!/usr/bin/env python3
"""
Build waypoints.json for ReadBack from FAA or local CSV.
Output: out/waypoints.json — array of {"id": "GEP", "name": "..."}.
"""
from __future__ import annotations

import csv
import json
import os
import re
import sys
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent / "out"
OUT_FILE = OUT_DIR / "waypoints.json"

# FAA ArcGIS Open Data: Designated Points (fix/waypoint identifiers).
# Server caps per-request size (typically 1000); we paginate to get all.
# Fallback if CSV not provided and network fails: use bundled list of common US waypoint IDs.
FAA_DESIGNATED_POINTS_BASE = (
    "https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/arcgis/rest/services"
    "/Designated_Points/FeatureServer/0/query"
    "?where=1%3D1&outFields=IDENT,NAME&returnGeometry=false&f=json"
    "&orderByFields=IDENT&resultRecordCount={count}&resultOffset={offset}"
)
PAGE_SIZE = 1000

# Common US waypoint IDs (fallback when no CSV and no network) — subset for bundle/offline use.
FALLBACK_WAYPOINT_IDS = [
    "GEP", "OCN", "JOT", "BEE", "BDF", "ORD", "MSP", "STP", "ANE", "FCM", "MIC", "LVN",
    "GRB", "EAU", "RST", "DLH", "INL", "BRD", "STC", "AXN", "TVF", "BJI", "GFK",
    "DEN", "D01", "LAR", "CYS", "DDC", "ICT", "MKC", "STL", "MCI", "SGF", "JLN",
    "ORD", "MDW", "RFD", "PIA", "BMI", "CMI", "IND", "SBN", "FWA", "LAF", "EVV",
    "CVG", "DAY", "CMH", "LCK", "TOL", "DET", "DTW", "FNT", "MBS", "GRR", "AZO",
    "MKE", "MSN", "CWA", "LSE", "RHI", "ATW", "EAU", "AUW", "FLG", "GCN", "PRC",
    "PHX", "TUS", "ABQ", "SAF", "AMA", "LBB", "DFW", "DAL", "FTW", "ACT", "GTU",
    "AUS", "SAT", "HOU", "IAH", "EFD", "CXO", "SGR", "BPT", "LFK", "TYR", "GGG",
    "OKC", "TUL", "FSM", "XNA", "LIT", "MEM", "NQA", "BNA", "CHA", "TYS", "TRI",
    "ATL", "PDK", "FTY", "MCN", "AHN", "SAV", "JAX", "GNV", "TLH", "ECP", "PFN",
    "TPA", "SRQ", "MCO", "SFB", "DAB", "MLB", "MIA", "FLL", "PBI", "RSW", "FMY",
    "CLT", "GSO", "RDU", "RWI", "FAY", "ILM", "MYR", "CRE", "CHS", "CAE", "AGS",
    "GSP", "AVL", "HKY", "RDU", "INT", "GSO", "ROA", "LYH", "ORF", "PHF", "RIC",
    "DCA", "IAD", "BWI", "SBY", "MTN", "ACY", "PHL", "PNE", "ILG", "ABE", "AVP",
    "IPT", "MDT", "LNS", "HAR", "JST", "DUJ", "PIT", "AGC", "LBE", "CKB", "EKN",
    "CRW", "HTS", "BKW", "LWB", "BLF", "ROA", "LYH", "CHO", "SHD", "EWN", "OAJ",
    "ILM", "FAY", "RDU", "RWI", "GSO", "INT", "CLT", "UZA", "GSP", "AND", "CEU",
    "GMU", "GDC", "SPA", "CHS", "CRE", "SAV", "SSI", "BQK", "VLD", "ABY", "MGR",
    "BOS", "ORH", "PVD", "HVN", "BDL", "GON", "BDR", "HPN", "SWF", "POU", "ALB",
    "SCH", "SYR", "ITH", "ELM", "BGM", "AVP", "ABE", "RDG", "MDT", "LNS", "HAR",
    "JST", "DUJ", "PIT", "LBE", "CKB", "EKN", "PKB", "CRW", "HTS", "BKW", "LWB",
    "BLF", "ROA", "LYH", "CHO", "SHD", "EWN", "OAJ", "ILM", "FAY", "RDU", "GSO",
    "CLT", "UZA", "GSP", "AND", "CEU", "GMU", "CHS", "SAV", "JAX", "GNV", "TLH",
    "TPA", "SRQ", "MCO", "MLB", "DAB", "MIA", "FLL", "PBI", "RSW", "FMY", "PIE",
    "SEA", "BFI", "PAE", "OLM", "SHN", "TCM", "GRF", "PWT", "CLM", "BLI", "FHR",
    "ORS", "Bellingham", "PDX", "TTD", "HIO", "EUG", "MFR", "RDM", "BDN", "LMT",
    "BOI", "SUN", "TWF", "PIH", "IDA", "JAC", "CPR", "RKS", "CYS", "LAR", "DDC",
    "GCK", "ICT", "Wichita", "SLN", "MHK", "TOP", "FOE", "CNU", "MCI", "STJ",
    "SGF", "JLN", "FSM", "XNA", "LIT", "MEM", "NQA", "BNA", "HOP", "CHA", "TYS",
]


def normalize_id(s: str | None) -> str | None:
    if not s or not isinstance(s, str):
        return None
    t = s.strip().upper()
    return t if t and re.match(r"^[A-Z0-9]{2,5}$", t) else None


def build_from_csv(path: Path) -> list[dict]:
    rows: list[dict] = []
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            return rows
        # Accept IDENT or id; NAME or name
        id_col = next((c for c in ("IDENT", "id", "Id", "IDENTIFIER") if c in reader.fieldnames), None)
        name_col = next((c for c in ("NAME", "name", "Name") if c in reader.fieldnames), None)
        if not id_col:
            return rows
        for row in reader:
            wid = normalize_id(row.get(id_col, ""))
            if not wid:
                continue
            name = (row.get(name_col) or "").strip() if name_col else ""
            rows.append({"id": wid, "name": name or None})
    return rows


def build_from_faa_api() -> list[dict] | None:
    import urllib.request
    rows: list[dict] = []
    seen: set[str] = set()
    offset = 0
    while True:
        url = FAA_DESIGNATED_POINTS_BASE.format(count=PAGE_SIZE, offset=offset)
        try:
            req = urllib.request.Request(
                url,
                headers={"User-Agent": "ReadBack/1.0 (aviation data build)"},
            )
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = json.load(resp)
        except Exception as e:
            print(f"FAA Designated Points fetch failed (offset={offset}): {e}", file=sys.stderr)
            if offset == 0:
                return None
            break
        features = data.get("features") or []
        for f in features:
            att = f.get("attributes") or {}
            wid = normalize_id(att.get("IDENT") or att.get("ident") or "")
            if not wid or wid in seen:
                continue
            seen.add(wid)
            name = (att.get("NAME") or att.get("name") or "").strip() or None
            rows.append({"id": wid, "name": name})
        if len(features) < PAGE_SIZE:
            break
        offset += PAGE_SIZE
        print(f"Fetched {len(rows)} waypoints so far...", file=sys.stderr)
    return rows if rows else None


def build_fallback() -> list[dict]:
    return [{"id": w, "name": None} for w in sorted(set(FALLBACK_WAYPOINT_IDS))]


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Build waypoints.json for ReadBack")
    parser.add_argument("--csv", type=Path, help="Local CSV with IDENT (or id) and optional NAME (or name)")
    parser.add_argument("-o", "--output", type=Path, default=OUT_FILE, help="Output JSON path")
    parser.add_argument("--no-network", action="store_true", help="Skip FAA API; use fallback list only")
    args = parser.parse_args()

    if args.csv and args.csv.exists():
        rows = build_from_csv(args.csv)
        print(f"Loaded {len(rows)} waypoints from CSV", file=sys.stderr)
    elif not args.no_network:
        rows = build_from_faa_api()
        if rows:
            print(f"Loaded {len(rows)} waypoints from FAA API", file=sys.stderr)
        else:
            rows = build_fallback()
            print("Using fallback waypoint list", file=sys.stderr)
    else:
        rows = build_fallback()
        print("Using fallback waypoint list (--no-network)", file=sys.stderr)

    # Dedupe by id, keep first
    by_id: dict[str, dict] = {}
    for r in rows:
        i = r.get("id")
        if i and i not in by_id:
            by_id[i] = r
    out_list = [by_id[k] for k in sorted(by_id.keys())]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_list, f, indent=2, ensure_ascii=False)
    print(f"Wrote {len(out_list)} waypoints to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
