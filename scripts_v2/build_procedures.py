#!/usr/bin/env python3
"""
Build departures.json and arrivals.json from FAA NASR procedure CSVs.
Departures: DP_BASE.csv + DP_RTE.csv + DP_APT.csv.
Arrivals: STAR_BASE.csv + STAR_RTE.csv + STAR_APT.csv.
Uses real FAA column names; maps CSV headers dynamically where present.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
AVIATION_DATA = SCRIPT_DIR.parent / "aviation_data_v2"
OUT_DEP = AVIATION_DATA / "departures.json"
OUT_ARR = AVIATION_DATA / "arrivals.json"


def _strip(row: dict, key: str) -> str | None:
    v = row.get(key)
    if v is None or not isinstance(v, str):
        return None
    t = v.strip()
    return t if t else None


def _int_or_none(s: str | None):
    if not s:
        return None
    try:
        return int(float(s))
    except (ValueError, TypeError):
        return None


def _route_row_to_segment(row: dict, seqno_key: str = "SEQNO") -> dict:
    """Build one route segment from DP_RTE or STAR_RTE row using actual headers."""
    seq = _int_or_none(_strip(row, seqno_key))
    seg = {"seq": seq}
    for key in ("FIX_ID", "FIX_TYPE", "NAV_ID", "NAV_TYPE", "PATH_TERM", "ALT_DESC", "SPEED", "SPEED_ALT", "RNV_LEG", "TRANSITION", "POINT", "POINT_TYPE", "NEXT_POINT", "ROUTE_NAME", "BODY_SEQ", "ARPT_RWY_ASSOC"):
        v = _strip(row, key)
        if v is not None:
            seg[key.lower()] = v
    return seg


def build_departures(dp_base: Path, dp_rte: Path, dp_apt: Path) -> tuple[list[dict], dict[str, int]]:
    procs: dict[str, dict] = {}
    stats = {"baseRows": 0, "rteRows": 0, "aptRows": 0, "written": 0, "skippedMissingId": 0}

    with open(dp_base, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["baseRows"] += 1
            # FAA DP_BASE uses DP_COMPUTER_CODE as unique id; fallback DP_NAME or DP_ID
            proc_id = _strip(row, "DP_COMPUTER_CODE") or _strip(row, "DP_NAME") or _strip(row, "DP_ID")
            if not proc_id:
                stats["skippedMissingId"] += 1
                continue
            proc_id = proc_id.upper()
            if proc_id in procs:
                continue
            procs[proc_id] = {
                "id": proc_id,
                "name": _strip(row, "DP_NAME") or "",
                "type": _strip(row, "DP_TYPE") or _strip(row, "GRAPHICAL_DP_TYPE") or None,
                "status": _strip(row, "STATUS_CODE") or None,
                "airports": [],
                "route": [],
            }
            stats["written"] += 1

    with open(dp_rte, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        seqno_key = "POINT_SEQ" if (reader.fieldnames and "POINT_SEQ" in (reader.fieldnames or [])) else "SEQNO"
        if reader.fieldnames and "SEQNUM" in (reader.fieldnames or []):
            seqno_key = "SEQNUM"
        for row in reader:
            stats["rteRows"] += 1
            proc_id = _strip(row, "DP_COMPUTER_CODE") or _strip(row, "DP_NAME") or _strip(row, "DP_ID")
            if not proc_id or proc_id.upper() not in procs:
                continue
            procs[proc_id.upper()]["route"].append(_route_row_to_segment(row, seqno_key))

    with open(dp_apt, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["aptRows"] += 1
            proc_id = _strip(row, "DP_COMPUTER_CODE") or _strip(row, "DP_NAME") or _strip(row, "DP_ID")
            arpt = _strip(row, "ARPT_ID")
            if not proc_id or proc_id.upper() not in procs:
                continue
            apt_rec = {"airport_identifier": (arpt or "").upper()}
            rwy = _strip(row, "RWY_END_ID") or _strip(row, "RWY") or _strip(row, "RUNWAY")
            if rwy:
                apt_rec["runway"] = rwy.upper()
            existing = procs[proc_id.upper()]["airports"]
            if not any(e.get("airport_identifier") == apt_rec["airport_identifier"] and e.get("runway") == apt_rec.get("runway") for e in existing):
                existing.append(apt_rec)

    out_list = []
    for proc_id in sorted(procs.keys()):
        rec = procs[proc_id]
        rec["route"] = sorted(rec["route"], key=lambda s: (s.get("seq") if s.get("seq") is not None else -1))
        out_list.append(rec)
    return out_list, stats


def build_arrivals(star_base: Path, star_rte: Path, star_apt: Path) -> tuple[list[dict], dict[str, int]]:
    procs: dict[str, dict] = {}
    stats = {"baseRows": 0, "rteRows": 0, "aptRows": 0, "written": 0, "skippedMissingId": 0}

    with open(star_base, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["baseRows"] += 1
            proc_id = _strip(row, "STAR_COMPUTER_CODE") or _strip(row, "ARRIVAL_NAME") or _strip(row, "STAR_ID") or _strip(row, "SID_STAR_ID") or _strip(row, "ID")
            if not proc_id:
                stats["skippedMissingId"] += 1
                continue
            proc_id = proc_id.upper()
            if proc_id in procs:
                continue
            procs[proc_id] = {
                "id": proc_id,
                "name": _strip(row, "ARRIVAL_NAME") or _strip(row, "STAR_NAME") or _strip(row, "NAME") or "",
                "type": _strip(row, "STAR_TYPE") or _strip(row, "TYPE") or None,
                "status": _strip(row, "STATUS_CODE") or None,
                "airports": [],
                "route": [],
            }
            stats["written"] += 1

    with open(star_rte, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        seqno_key = "POINT_SEQ" if (reader.fieldnames and "POINT_SEQ" in (reader.fieldnames or [])) else "SEQNO"
        if reader.fieldnames and "SEQNUM" in (reader.fieldnames or []):
            seqno_key = "SEQNUM"
        for row in reader:
            stats["rteRows"] += 1
            proc_id = _strip(row, "STAR_COMPUTER_CODE") or _strip(row, "ARRIVAL_NAME") or _strip(row, "STAR_ID") or _strip(row, "SID_STAR_ID") or _strip(row, "ID")
            if not proc_id or proc_id.upper() not in procs:
                continue
            procs[proc_id.upper()]["route"].append(_route_row_to_segment(row, seqno_key))

    with open(star_apt, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats["aptRows"] += 1
            proc_id = _strip(row, "STAR_COMPUTER_CODE") or _strip(row, "ARRIVAL_NAME") or _strip(row, "STAR_ID") or _strip(row, "SID_STAR_ID") or _strip(row, "ID")
            arpt = _strip(row, "ARPT_ID")
            if not proc_id or proc_id.upper() not in procs:
                continue
            apt_rec = {"airport_identifier": (arpt or "").upper()}
            rwy = _strip(row, "RWY_END_ID") or _strip(row, "RWY") or _strip(row, "RUNWAY")
            if rwy:
                apt_rec["runway"] = rwy.upper()
            existing = procs[proc_id.upper()]["airports"]
            if not any(e.get("airport_identifier") == apt_rec["airport_identifier"] and e.get("runway") == apt_rec.get("runway") for e in existing):
                existing.append(apt_rec)

    out_list = []
    for proc_id in sorted(procs.keys()):
        rec = procs[proc_id]
        rec["route"] = sorted(rec["route"], key=lambda s: (s.get("seq") if s.get("seq") is not None else -1))
        out_list.append(rec)
    return out_list, stats


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description="Build departures.json and arrivals.json from NASR procedure CSVs")
    parser.add_argument("--dp-base", type=Path, required=True, help="DP_BASE.csv")
    parser.add_argument("--dp-rte", type=Path, required=True, help="DP_RTE.csv")
    parser.add_argument("--dp-apt", type=Path, required=True, help="DP_APT.csv")
    parser.add_argument("--star-base", type=Path, required=True, help="STAR_BASE.csv")
    parser.add_argument("--star-rte", type=Path, required=True, help="STAR_RTE.csv")
    parser.add_argument("--star-apt", type=Path, required=True, help="STAR_APT.csv")
    parser.add_argument("-o", "--output-dir", type=Path, default=AVIATION_DATA, help="Output directory")
    args = parser.parse_args()

    for p in (args.dp_base, args.dp_rte, args.dp_apt, args.star_base, args.star_rte, args.star_apt):
        if not p.exists():
            print(f"CSV not found: {p}", file=sys.stderr)
            sys.exit(1)

    dep_list, dep_stats = build_departures(args.dp_base, args.dp_rte, args.dp_apt)
    arr_list, arr_stats = build_arrivals(args.star_base, args.star_rte, args.star_apt)

    out_dep = args.output_dir / "departures.json"
    out_arr = args.output_dir / "arrivals.json"
    args.output_dir.mkdir(parents=True, exist_ok=True)

    if not dep_list:
        print("ERROR: departures output is empty; refusing to write.", file=sys.stderr)
        sys.exit(1)
    if not arr_list:
        print("ERROR: arrivals output is empty; refusing to write.", file=sys.stderr)
        sys.exit(1)

    with open(out_dep, "w", encoding="utf-8") as f:
        json.dump(dep_list, f, separators=(",", ":"), ensure_ascii=False)
    with open(out_arr, "w", encoding="utf-8") as f:
        json.dump(arr_list, f, separators=(",", ":"), ensure_ascii=False)

    print(
        f"Departures summary: base={dep_stats['baseRows']} rte={dep_stats['rteRows']} apt={dep_stats['aptRows']} "
        f"written={dep_stats['written']} skippedMissingId={dep_stats['skippedMissingId']}",
        file=sys.stderr,
    )
    print(
        f"Arrivals summary: base={arr_stats['baseRows']} rte={arr_stats['rteRows']} apt={arr_stats['aptRows']} "
        f"written={arr_stats['written']} skippedMissingId={arr_stats['skippedMissingId']}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
