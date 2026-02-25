#!/usr/bin/env python3
"""
Validate comms.json: no duplicate outlet_ids, and synthetic IDs are deterministic
(run builder twice on same CSV yields identical ids).
Usage:
  validate_comms_ids.py comms.json
  validate_comms_ids.py --csv COM.csv  [runs builder twice and compares ids]
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def validate_no_duplicate_ids(comms_path: Path) -> tuple[bool, str]:
    """Ensure no duplicate outlet_id in comms.json."""
    with open(comms_path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        return False, "comms.json is not a list"
    ids = [rec.get("outlet_id") for rec in data if isinstance(rec, dict)]
    seen = set()
    dupes = []
    for i, oid in enumerate(ids):
        if oid is None:
            dupes.append((i, None))
            continue
        if oid in seen:
            dupes.append((i, oid))
        seen.add(oid)
    if dupes:
        return False, f"Duplicate or null outlet_id at indices: {[p[0] for p in dupes[:10]]}{'...' if len(dupes) > 10 else ''}"
    return True, f"OK: {len(ids)} unique outlet_ids"


def validate_deterministic_synthetic(csv_path: Path, build_comms_module) -> tuple[bool, str]:
    """Run build_comms twice in memory and compare outlet_ids; all must match."""
    out1, _ = build_comms_module.build_comms(csv_path)
    out2, _ = build_comms_module.build_comms(csv_path)
    ids1 = [r.get("outlet_id") for r in out1]
    ids2 = [r.get("outlet_id") for r in out2]
    if len(ids1) != len(ids2):
        return False, f"Run 1 wrote {len(ids1)} records, run 2 wrote {len(ids2)}"
    for i, (a, b) in enumerate(zip(ids1, ids2)):
        if a != b:
            return False, f"Id mismatch at index {i}: {a!r} vs {b!r}"
    return True, f"OK: {len(ids1)} ids identical across two runs"


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Validate comms.json outlet_ids")
    parser.add_argument("comms", nargs="?", type=Path, help="comms.json path")
    parser.add_argument("--csv", type=Path, help="COM.csv path (run determinism check)")
    parser.add_argument("--script-dir", type=Path, default=Path(__file__).resolve().parent, help="scripts_v2 dir for import")
    args = parser.parse_args()

    if args.comms:
        ok, msg = validate_no_duplicate_ids(args.comms)
        print(msg)
        if not ok:
            sys.exit(1)
        print("No duplicate ids.")
        sys.exit(0)

    if args.csv and args.csv.exists():
        sys.path.insert(0, str(args.script_dir))
        import build_comms as build_comms_module
        ok, msg = validate_deterministic_synthetic(args.csv, build_comms_module)
        print(msg)
        if not ok:
            sys.exit(1)
        print("Synthetic ids are deterministic.")
        sys.exit(0)

    print("Usage: validate_comms_ids.py <comms.json>  OR  validate_comms_ids.py --csv COM.csv", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
