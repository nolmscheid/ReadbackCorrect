#!/usr/bin/env python3
"""
Check current FAA NASR cycle date and compare to aviation_manifest.json.
Run this to know when to rebuild and push (e.g. before or after each 28-day cycle).
Exit code 0 = same or no manifest; 1 = FAA cycle is newer (update recommended).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import urllib.request
except ImportError:
    urllib = None  # type: ignore

OUT_DIR = Path(__file__).resolve().parent / "out"
MANIFEST_PATH = OUT_DIR / "aviation_manifest.json"
FAA_NASR_INDEX = "https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/"

# "Subscription effective February 19, 2026" -> 2026-02-19
MONTHS: dict[str, str] = {
    "January": "01", "February": "02", "March": "03", "April": "04",
    "May": "05", "June": "06", "July": "07", "August": "08",
    "September": "09", "October": "10", "November": "11", "December": "12",
}


def fetch_current_cycle() -> str | None:
    if not urllib:
        return None
    try:
        req = urllib.request.Request(
            FAA_NASR_INDEX,
            headers={"User-Agent": "ReadBack/1.0 (FAA cycle check)"},
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            html = resp.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"Could not fetch FAA page: {e}", file=sys.stderr)
        return None
    # Subscription effective Month DD, YYYY
    m = re.search(
        r"Subscription effective\s+(\w+)\s+(\d{1,2}),\s+(\d{4})",
        html,
        re.IGNORECASE,
    )
    if not m:
        return None
    month_name, day, year = m.group(1), m.group(2), m.group(3)
    month = MONTHS.get(month_name)
    if not month:
        return None
    day_z = day.zfill(2)
    return f"{year}-{month}-{day_z}"


def get_manifest_cycle() -> str | None:
    if not MANIFEST_PATH.exists():
        return None
    try:
        with open(MANIFEST_PATH, encoding="utf-8") as f:
            data = json.load(f)
        return data.get("cycle")
    except (json.JSONDecodeError, TypeError):
        return None


def set_manifest_cycle(cycle: str) -> bool:
    """Write aviation_manifest.json with given cycle and standard files."""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest = {
        "cycle": cycle,
        "files": {
            "airports": "airports.json",
            "victor_airways": "victor_airways.json",
            "waypoints": "waypoints.json",
        },
    }
    try:
        with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2)
        return True
    except OSError as e:
        print(f"Could not write manifest: {e}", file=sys.stderr)
        return False


def main() -> int:
    import argparse
    parser = argparse.ArgumentParser(description="Check FAA NASR cycle vs manifest; optionally update manifest")
    parser.add_argument("--set-manifest", action="store_true", help="Write manifest with current FAA cycle and files")
    args = parser.parse_args()

    faa = fetch_current_cycle()
    if not faa:
        print("Could not determine current FAA NASR cycle from:", FAA_NASR_INDEX, file=sys.stderr)
        if args.set_manifest:
            sys.exit(2)
        return 0
    print(f"Current FAA NASR cycle: {faa}")

    if args.set_manifest:
        if set_manifest_cycle(faa):
            print(f"Updated {MANIFEST_PATH} with cycle {faa}", file=sys.stderr)
            return 0
        sys.exit(2)

    manifest_cycle = get_manifest_cycle()
    if not manifest_cycle:
        print("No aviation_manifest.json (or no 'cycle' key). Run build scripts and set cycle.", file=sys.stderr)
        return 0
    print(f"Manifest cycle:          {manifest_cycle}")

    if faa != manifest_cycle:
        print("\n→ New FAA cycle available. Rebuild waypoints, airports, victor_airways; update manifest cycle; push to GitHub.", file=sys.stderr)
        return 1
    print("\n→ Manifest is current.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
