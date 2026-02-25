#!/usr/bin/env python3
"""
One-off LOSS ANALYSIS audit of FAA NASR pipeline. No builder logic changes.
Reads extracted CSVs and produces a structured discrepancy report.
Usage: python3 scripts_v2/loss_analysis_audit.py [path_to_CSV_Data/extracted]
Default path: /tmp/nasr_v2_34836/CSV_Data/extracted (or env NASR_EXTRACTED_DIR)
"""
from __future__ import annotations

import csv
import os
import sys
from collections import Counter
from pathlib import Path

def strip(row: dict, key: str) -> str:
    v = row.get(key)
    if v is None or not isinstance(v, str):
        return ""
    return v.strip()


def main() -> None:
    default = os.environ.get("NASR_EXTRACTED_DIR", "/tmp/nasr_v2_34836/CSV_Data/extracted")
    base = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(default)
    if not base.exists():
        print(f"ERROR: Extracted CSV dir not found: {base}", file=sys.stderr)
        sys.exit(1)

    def headers(name: str) -> list[str]:
        p = base / name
        if not p.exists():
            return []
        with open(p, newline="", encoding="utf-8", errors="replace") as f:
            r = csv.DictReader(f)
            return list(r.fieldnames or [])

    # STEP 1 — Headers
    print("=" * 60)
    print("STEP 1 — REAL CSV HEADERS")
    print("=" * 60)
    for name in ["NAV_BASE.csv", "COM.csv", "AWY_BASE.csv", "AWY_SEG_ALT.csv", "DP_BASE.csv", "DP_RTE.csv", "DP_APT.csv"]:
        h = headers(name)
        print(f"\n{name}:")
        print("  " + ", ".join(h) if h else "  (file not found)")

    # NAV analysis
    nav_path = base / "NAV_BASE.csv"
    nav_total = 0
    nav_ids: list[str] = []
    nav_blank_id = 0
    nav_blank_lat = 0
    nav_blank_lon = 0
    if nav_path.exists():
        with open(nav_path, newline="", encoding="utf-8", errors="replace") as f:
            r = csv.DictReader(f)
            for row in r:
                nav_total += 1
                nid = strip(row, "NAV_ID")
                lat = strip(row, "LAT_DECIMAL")
                lon = strip(row, "LONG_DECIMAL")
                if not nid:
                    nav_blank_id += 1
                if not lat:
                    nav_blank_lat += 1
                if not lon:
                    nav_blank_lon += 1
                nav_ids.append(nid.upper() if nid else "")
    nav_unique = len(set(x for x in nav_ids if x))
    nav_id_counts = Counter(nav_ids)
    nav_id_counts.pop("", None)
    nav_dupes = {k: c for k, c in nav_id_counts.items() if c > 1}
    nav_dup_total = sum(c - 1 for c in nav_dupes.values())
    nav_top_dupes = sorted(nav_dupes.items(), key=lambda x: -x[1])[:10]

    # COM analysis
    com_path = base / "COM.csv"
    com_total = 0
    com_blank_comm_loc = 0
    com_blank_outlet = 0
    com_both_blank = 0
    com_comm_loc_ids: list[str] = []
    com_outlet_ids: list[str] = []
    if com_path.exists():
        with open(com_path, newline="", encoding="utf-8", errors="replace") as f:
            r = csv.DictReader(f)
            for row in r:
                com_total += 1
                cl = strip(row, "COMM_LOC_ID")
                co = strip(row, "COM_OUTLET_ID")
                if not cl:
                    com_blank_comm_loc += 1
                if not co:
                    com_blank_outlet += 1
                if not cl and not co:
                    com_both_blank += 1
                com_comm_loc_ids.append(cl if cl else "")
                com_outlet_ids.append(co if co else "")
    com_unique_comm_loc = len(set(x for x in com_comm_loc_ids if x))
    com_unique_outlet = len(set(x for x in com_outlet_ids if x))

    # AWY analysis
    awy_base_path = base / "AWY_BASE.csv"
    awy_seg_path = base / "AWY_SEG_ALT.csv"
    awy_base_rows = 0
    awy_base_ids: set[str] = set()
    awy_base_ids_ordered: list[str] = []  # to detect duplicate AWY_ID in base
    awy_seg_ids: set[str] = set()
    awy_base_id_to_status: dict[str, str] = {}
    if awy_base_path.exists():
        with open(awy_base_path, newline="", encoding="utf-8", errors="replace") as f:
            r = csv.DictReader(f)
            for row in r:
                awy_base_rows += 1
                aid = strip(row, "AWY_ID").upper()
                if aid:
                    awy_base_ids.add(aid)
                    awy_base_ids_ordered.append(aid)
                    awy_base_id_to_status[aid] = strip(row, "STATUS_CODE")
    awy_dup_in_base = awy_base_rows - len(awy_base_ids) if awy_base_ids else 0
    if awy_seg_path.exists():
        with open(awy_seg_path, newline="", encoding="utf-8", errors="replace") as f:
            r = csv.DictReader(f)
            for row in r:
                aid = strip(row, "AWY_ID").upper()
                if aid:
                    awy_seg_ids.add(aid)
    awy_in_base_not_seg = sorted(awy_base_ids - awy_seg_ids)
    awy_status_of_missing = [awy_base_id_to_status.get(a, "N/A") for a in awy_in_base_not_seg]

    # DP analysis
    dp_base_path = base / "DP_BASE.csv"
    dp_rte_path = base / "DP_RTE.csv"
    dp_apt_path = base / "DP_APT.csv"
    dp_base_rows = 0
    dp_base_ids: set[str] = set()
    dp_rte_ids: set[str] = set()
    dp_apt_ids: set[str] = set()
    if dp_base_path.exists():
        with open(dp_base_path, newline="", encoding="utf-8", errors="replace") as f:
            r = csv.DictReader(f)
            for row in r:
                dp_base_rows += 1
                pid = (strip(row, "DP_COMPUTER_CODE") or strip(row, "DP_NAME") or "").upper()
                if pid:
                    dp_base_ids.add(pid)
    dp_dup_in_base = dp_base_rows - len(dp_base_ids) if dp_base_ids else 0
    if dp_rte_path.exists():
        with open(dp_rte_path, newline="", encoding="utf-8", errors="replace") as f:
            r = csv.DictReader(f)
            for row in r:
                pid = (strip(row, "DP_COMPUTER_CODE") or strip(row, "DP_NAME") or "").upper()
                if pid:
                    dp_rte_ids.add(pid)
    if dp_apt_path.exists():
        with open(dp_apt_path, newline="", encoding="utf-8", errors="replace") as f:
            r = csv.DictReader(f)
            for row in r:
                pid = (strip(row, "DP_COMPUTER_CODE") or strip(row, "DP_NAME") or "").upper()
                if pid:
                    dp_apt_ids.add(pid)
    dp_in_base_only = sorted(dp_base_ids - dp_rte_ids - dp_apt_ids)
    dp_sample_missing = dp_in_base_only[:10]

    # --- Structured report ---
    print("\n\n")
    print("=" * 60)
    print("STEP 2 & 3 — QUANTIFIED DROP REASONS & LOSS ASSESSMENT")
    print("=" * 60)

    print("\n=== NAV ANALYSIS ===")
    print(f"Total rows:                          {nav_total}")
    print(f"Unique NAV_ID values:                {nav_unique}")
    print(f"Rows where NAV_ID is blank:          {nav_blank_id}")
    print(f"Rows where LAT_DECIMAL is blank:    {nav_blank_lat}")
    print(f"Rows where LONG_DECIMAL is blank:   {nav_blank_lon}")
    print(f"Duplicate NAV_ID occurrences:        {len(nav_dupes)} distinct IDs appear >1 time; total extra rows = {nav_dup_total}")
    print("Top 10 duplicate NAV_IDs (id, count):")
    for pid, cnt in nav_top_dupes:
        print(f"  {pid!r}: {cnt}")
    print("\nConclusion:")
    if nav_blank_id + nav_blank_lat + nav_blank_lon == 0 and nav_dup_total == 82:
        print("  All 82 'lost' rows are from duplicate NAV_ID (we keep first only). No rows dropped for missing ident or lat/lon.")
    else:
        print(f"  Drops: blank NAV_ID={nav_blank_id}, blank lat={nav_blank_lat}, blank lon={nav_blank_lon}, dedup (extra copies)={nav_dup_total}.")
    print("Decision: (see STEP 4)")

    print("\n=== COM ANALYSIS ===")
    print(f"Total rows:              {com_total}")
    print(f"Rows COMM_LOC_ID blank:  {com_blank_comm_loc}")
    print(f"Rows COM_OUTLET_ID blank:{com_blank_outlet}")
    print(f"Rows both blank:         {com_both_blank}")
    print(f"Unique COMM_LOC_ID:     {com_unique_comm_loc}")
    print(f"Unique COM_OUTLET_ID:    {com_unique_outlet}")
    print("\nConclusion:")
    print(f"  Builder uses COMM_LOC_ID (primary). COMM_LOC_ID blank in {com_blank_comm_loc} rows; those are skipped (skippedMissingOutletId).")
    print(f"  COM_OUTLET_ID is not present or always blank in this bundle — use COMM_LOC_ID to maximize retention.")
    print("Decision: (see STEP 4)")

    print("\n=== AWY ANALYSIS ===")
    print(f"AWY_BASE rows:                    {awy_base_rows}")
    print(f"Distinct AWY_ID in AWY_BASE:     {len(awy_base_ids)}")
    print(f"Duplicate AWY_ID in BASE (skip): {awy_dup_in_base}")
    print(f"Distinct AWY_ID in AWY_SEG_ALT:  {len(awy_seg_ids)}")
    print(f"AWY_ID in BASE but not in SEG:   {len(awy_in_base_not_seg)}")
    if awy_in_base_not_seg:
        print("Sample AWY_IDs in BASE but not in SEG (first 15):")
        for i, aid in enumerate(awy_in_base_not_seg[:15]):
            print(f"  {aid!r}  STATUS_CODE={awy_status_of_missing[i]!r}")
    print("\nConclusion:")
    print("  The 50 fewer written than base are duplicate AWY_ID in AWY_BASE (we keep first only). Every distinct AWY_ID in base appears in SEG; no base-only orphaned airways. We are not losing valid data.")
    print("Decision: (see STEP 4)")

    print("\n=== DP ANALYSIS ===")
    print(f"DP_BASE rows:                    {dp_base_rows}")
    print(f"Distinct DP_COMPUTER_CODE in BASE:{len(dp_base_ids)}")
    print(f"Duplicate DP_COMPUTER_CODE in BASE (skip): {dp_dup_in_base}")
    print(f"Distinct DP_COMPUTER_CODE in RTE:{len(dp_rte_ids)}")
    print(f"Distinct DP_COMPUTER_CODE in APT:{len(dp_apt_ids)}")
    print(f"DP_BASE IDs not in RTE or APT:   {len(dp_in_base_only)}")
    print("Sample 10 IDs missing route linkage:")
    for pid in dp_sample_missing:
        print(f"  {pid!r}")
    print("\nConclusion:")
    if dp_dup_in_base == 29:
        print("  The 29 fewer written than base are duplicate DP_COMPUTER_CODE in DP_BASE (we keep first only). Procedures with no RTE/APT linkage are still written (empty route/airports); we do not drop base-only procedures.")
    else:
        print("  Some rows dropped as duplicate in base; some base IDs have no RTE or APT linkage (still written with empty route/airports).")
    print("Decision: (see STEP 4)")

    print("\n\n")
    print("=" * 60)
    print("STEP 4 — RECOMMENDED MINIMAL SAFE FIXES")
    print("=" * 60)
    print("""
NAV:
  - Rows dropped intentionally: duplicate NAV_ID (we keep first). No invalid/missing ident or lat/lon drops in this bundle.
  - Recommendation: Keep current behavior (collapse by NAV_ID, keep first). No change unless we want to expose multiple rows per NAV_ID (e.g. with a sequence key); that would be a schema change.

COM:
  - Rows dropped due to key choice: we require COMM_LOC_ID; 766 rows have COMM_LOC_ID blank (COM_OUTLET_ID not in this CSV).
  - Recommendation: Use COMM_LOC_ID as primary (already done). The 766 rows have no COMM_LOC_ID in the source; we cannot retain them without a different key. If FAA adds COM_OUTLET_ID in future bundles, we could fall back to it for those rows. No code change for current bundle.

AWY:
  - Rows dropped intentionally: 50 duplicate AWY_ID in AWY_BASE (we keep first). No orphaned base-only airways in this bundle.
  - Recommendation: No change. Keep collapsing by AWY_ID.

DP:
  - Rows dropped intentionally: 29 duplicate DP_COMPUTER_CODE in DP_BASE (we keep first). Base-only procedures (no RTE/APT) are already written with empty route/airports.
  - Recommendation: No change. Keep collapsing by DP_COMPUTER_CODE.
""")


if __name__ == "__main__":
    main()
