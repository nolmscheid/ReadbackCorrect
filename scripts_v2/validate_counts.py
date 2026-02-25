#!/usr/bin/env python3
"""
Lightweight sanity check: compare FAA CSV row counts (minus header) to output JSON object counts.
Prints a short report. Run after build_all_and_update_manifest.sh (or set env vars / pass paths).
Skip reasons come from each builder's stderr summary when you run the build.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
AVIATION_DATA = REPO_ROOT / "aviation_data_v2"


def csv_row_count(path: Path) -> int:
    """Count data rows (excluding header) in a CSV."""
    if not path.exists():
        return -1
    count = 0
    with open(path, "rb") as f:
        for line in f:
            if line.strip():
                count += 1
    return max(0, count - 1)


def json_count(path: Path) -> int:
    """Count top-level list length in JSON file."""
    if not path.exists():
        return -1
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return len(data) if isinstance(data, list) else 0
    except (json.JSONDecodeError, TypeError):
        return -1


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Compare CSV row counts to JSON output counts")
    parser.add_argument("--nasr-dir", type=Path, default=None, help="NASR_WORK_DIR (default: env NASR_WORK_DIR)")
    parser.add_argument("--aviation-dir", type=Path, default=AVIATION_DATA, help="aviation_data_v2 directory")
    args = parser.parse_args()

    nasr = args.nasr_dir or Path(os.environ.get("NASR_WORK_DIR", ""))
    if not nasr.exists():
        print("NASR_WORK_DIR not set or path does not exist. Run after: source scripts_v2/download_nasr.sh", file=sys.stderr)
        sys.exit(1)

    def find_csv(name: str) -> Path:
        for p in nasr.rglob(name):
            if p.is_file():
                return p
        return Path()

    pairs = [
        ("APT_BASE.csv", "airports.json", "airports"),
        ("NAV_BASE.csv", "navaids.json", "navaids"),
        ("FIX_BASE.csv", "fixes.json", "fixes"),
        ("APT_RWY.csv", "runways.json", "runways"),
        ("FRQ.csv", "frequencies.json", "frequencies"),
        ("COM.csv", "comms.json", "comms"),
        ("AWY_BASE.csv", "airways.json", "airways"),
        ("DP_BASE.csv", "departures.json", "departures"),
        ("STAR_BASE.csv", "arrivals.json", "arrivals"),
        ("ILS_BASE.csv", "ils.json", "ils"),
    ]

    print("Dataset          CSV rows    JSON count   Diff (CSV - JSON)")
    print("-" * 55)
    for csv_name, json_name, label in pairs:
        csv_path = find_csv(csv_name)
        json_path = args.aviation_dir / json_name
        csv_n = csv_row_count(csv_path) if csv_path else -1
        json_n = json_count(json_path)
        diff = (csv_n - json_n) if csv_n >= 0 and json_n >= 0 else None
        diff_str = str(diff) if diff is not None else "N/A"
        print(f"{label:16} {csv_n:>8}   {json_n:>10}   {diff_str:>12}")
    print("-" * 55)
    print("Skip reasons and exact stats: run the build scripts and check stderr summary lines.")


if __name__ == "__main__":
    main()
