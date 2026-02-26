#!/usr/bin/env python3
"""
Write aviation_data/aviation_manifest.json with faa_cycle, build_timestamp, and counts.
Counts are read from aviation_data/airports.json, navaids.json, fixes.json.
Run after build_airports, build_navaids, build_fixes.
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
AVIATION_DATA = SCRIPT_DIR.parent / "aviation_data"
MANIFEST_FILE = AVIATION_DATA / "aviation_manifest.json"

FILES = ("airports.json", "navaids.json", "fixes.json")
COUNT_KEYS = ("airports", "navaids", "fixes")


def get_count(path: Path) -> int:
    if not path.exists():
        return 0
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return len(data) if isinstance(data, list) else 0
    except (json.JSONDecodeError, TypeError):
        return 0


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Write aviation_manifest.json with cycle, timestamp, counts")
    parser.add_argument("--faa-cycle", type=str, required=True, help="FAA cycle date YYYY-MM-DD")
    parser.add_argument("-o", "--output", type=Path, default=MANIFEST_FILE, help="Manifest output path")
    args = parser.parse_args()

    cycle = args.faa_cycle.strip()
    if len(cycle) != 10 or cycle[4] != "-" or cycle[7] != "-":
        print("--faa-cycle must be YYYY-MM-DD", file=sys.stderr)
        sys.exit(1)

    counts = {}
    for key, filename in zip(COUNT_KEYS, FILES):
        path = AVIATION_DATA / filename
        counts[key] = get_count(path)

    manifest = {
        "faa_cycle": cycle,
        "build_timestamp": datetime.now(tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "counts": counts,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(manifest, f, separators=(",", ":"), ensure_ascii=False)
    print(f"Wrote manifest to {args.output} (airports={counts['airports']}, navaids={counts['navaids']}, fixes={counts['fixes']})", file=sys.stderr)


if __name__ == "__main__":
    main()
