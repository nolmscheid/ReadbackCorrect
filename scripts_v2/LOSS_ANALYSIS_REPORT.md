# LOSS ANALYSIS AUDIT — FAA NASR Pipeline

**No builder logic was modified.** This report is based on running `scripts_v2/loss_analysis_audit.py` against the extracted NASR CSV bundle.

---

## STEP 1 — Real CSV Headers (confirmed)

**NAV_BASE.csv**  
`EFF_DATE, NAV_ID, NAV_TYPE, STATE_CODE, CITY, COUNTRY_CODE, NAV_STATUS, NAME, STATE_NAME, REGION_CODE, COUNTRY_NAME, FAN_MARKER, OWNER, OPERATOR, NAS_USE_FLAG, PUBLIC_USE_FLAG, NDB_CLASS_CODE, OPER_HOURS, HIGH_ALT_ARTCC_ID, HIGH_ARTCC_NAME, LOW_ALT_ARTCC_ID, LOW_ARTCC_NAME, LAT_DEG, LAT_MIN, LAT_SEC, LAT_HEMIS, LAT_DECIMAL, LONG_DEG, LONG_MIN, LONG_SEC, LONG_HEMIS, LONG_DECIMAL, ... (ELEV, CHAN, FREQ, etc.)`

**COM.csv**  
`EFF_DATE, COMM_LOC_ID, COMM_TYPE, NAV_ID, NAV_TYPE, CITY, STATE_CODE, REGION_CODE, COUNTRY_CODE, COMM_OUTLET_NAME, LAT_DEG, LAT_MIN, LAT_SEC, LAT_HEMIS, LAT_DECIMAL, LONG_DEG, LONG_MIN, LONG_SEC, LONG_HEMIS, LONG_DECIMAL, FACILITY_ID, FACILITY_NAME, ALT_FSS_ID, ALT_FSS_NAME, OPR_HRS, COMM_STATUS_CODE, COMM_STATUS_DATE, REMARK`  
*(No `COM_OUTLET_ID` column in this bundle.)*

**AWY_BASE.csv**  
`EFF_DATE, REGULATORY, AWY_DESIGNATION, AWY_LOCATION, AWY_ID, UPDATE_DATE, REMARK, AIRWAY_STRING`

**AWY_SEG_ALT.csv**  
`EFF_DATE, REGULATORY, AWY_LOCATION, AWY_ID, POINT_SEQ, FROM_POINT, FROM_PT_TYPE, NAV_NAME, ... (MIN_ENROUTE_ALT, etc.)`

**DP_BASE.csv**  
`EFF_DATE, DP_NAME, AMENDMENT_NO, ARTCC, DP_AMEND_EFF_DATE, RNAV_FLAG, DP_COMPUTER_CODE, GRAPHICAL_DP_TYPE, SERVED_ARPT`

**DP_RTE.csv**  
`EFF_DATE, DP_NAME, ARTCC, DP_COMPUTER_CODE, ROUTE_PORTION_TYPE, ROUTE_NAME, BODY_SEQ, TRANSITION_COMPUTER_CODE, POINT_SEQ, POINT, ICAO_REGION_CODE, POINT_TYPE, NEXT_POINT, ARPT_RWY_ASSOC`

**DP_APT.csv**  
`EFF_DATE, DP_NAME, ARTCC, DP_COMPUTER_CODE, BODY_NAME, BODY_SEQ, ARPT_ID, RWY_END_ID`

---

## STEP 2 & 3 — Quantified drop reasons and loss assessment

### === NAV ANALYSIS ===

| Metric | Count |
|--------|-------|
| Total rows | 1639 |
| Unique NAV_ID values | 1557 |
| Rows where NAV_ID is blank | 0 |
| Rows where LAT_DECIMAL is blank | 0 |
| Rows where LONG_DECIMAL is blank | 0 |
| Duplicate NAV_ID occurrences | 74 distinct IDs appear >1 time; total extra rows = 82 |

**Top 10 duplicate NAV_IDs (id, count):**  
`IL` 4, `BR` 3, `GB` 3, `MW` 3, `PK` 3, `ST` 3, `SW` 3, `AA` 2, `AB` 2, `ABQ` 2

**Conclusion:**  
1) **Dropped intentionally:** Yes — we keep one row per NAV_ID (first occurrence).  
2) **Key mismatch:** No.  
3) **Duplicates:** Yes — 82 rows are duplicate NAV_ID (74 IDs with >1 row).  
4) **Invalid (missing lat/lon):** No — no blank NAV_ID, LAT_DECIMAL, or LONG_DECIMAL.  
5) **Orphaned:** N/A.

**Decision:** Keep current behavior (collapse by NAV_ID, keep first). No change unless we want multiple rows per NAV_ID (schema change).

---

### === COM ANALYSIS ===

| Metric | Count |
|--------|-------|
| Total rows | 1823 |
| Rows COMM_LOC_ID blank | 766 |
| Rows COM_OUTLET_ID blank | 1823 (column not present) |
| Rows both blank | 766 |
| Unique COMM_LOC_ID | 1029 |
| Unique COM_OUTLET_ID | 0 |

**Conclusion:**  
1) **Dropped intentionally:** Only in the sense that we require a non-blank outlet id.  
2) **Key mismatch:** We use COMM_LOC_ID; COM_OUTLET_ID does not exist in this CSV.  
3) **Duplicates:** Not the cause of the 766 gap.  
4) **Invalid:** 766 rows have blank COMM_LOC_ID — we cannot assign a stable identifier.  
5) **Orphaned:** N/A.

**Decision:** Keep using COMM_LOC_ID as primary. The 766 rows have no COMM_LOC_ID in the source; we cannot retain them without another key. No code change for current bundle; if FAA adds COM_OUTLET_ID later, we could add a fallback for blank COMM_LOC_ID.

---

### === AWY ANALYSIS ===

| Metric | Count |
|--------|-------|
| AWY_BASE rows | 1519 |
| Distinct AWY_ID in AWY_BASE | 1469 |
| Duplicate AWY_ID in BASE (skip) | 50 |
| Distinct AWY_ID in AWY_SEG_ALT | 1469 |
| AWY_ID in BASE but not in SEG | 0 |

**Conclusion:**  
1) **Dropped intentionally:** Yes — we keep one record per AWY_ID (first base row).  
2) **Key mismatch:** No.  
3) **Duplicates:** Yes — 50 extra base rows are duplicate AWY_ID.  
4) **Invalid:** N/A.  
5) **Orphaned:** No — every distinct AWY_ID in base appears in AWY_SEG_ALT.

**Decision:** No change. Keep collapsing by AWY_ID. We are not losing valid distinct airways.

---

### === DP ANALYSIS ===

| Metric | Count |
|--------|-------|
| DP_BASE rows | 1191 |
| Distinct DP_COMPUTER_CODE in BASE | 1162 |
| Duplicate DP_COMPUTER_CODE in BASE (skip) | 29 |
| Distinct DP_COMPUTER_CODE in RTE | 1046 |
| Distinct DP_COMPUTER_CODE in APT | 1002 |
| DP_BASE IDs not in RTE or APT | 116 |

**Sample 10 IDs missing route linkage:**  
`ABQ3.ABQ`, `ACY3.ACY`, `AGC9.AGC`, `ALB7.ALB`, `ALICO7.ALICO`, `ANCH1.ANCH`, `APF6.APF`, `ASG5.ASG`, `ASPE7.ASPE`, `ATL2.ATL`

**Conclusion:**  
1) **Dropped intentionally:** Yes — we keep one procedure per DP_COMPUTER_CODE (first base row); 29 base rows are duplicates.  
2) **Key mismatch:** No.  
3) **Duplicates:** Yes — 29 duplicate DP_COMPUTER_CODE in DP_BASE.  
4) **Invalid:** N/A.  
5) **Orphaned:** 116 procedure IDs have no rows in DP_RTE or DP_APT; the builder still writes them with empty route and empty airports (we do not drop base-only procedures).

**Decision:** No change. Keep collapsing by DP_COMPUTER_CODE. Base-only procedures are already retained with empty route/airports.

---

## STEP 4 — Recommended minimal safe fixes (summary)

| Dataset | Finding | Recommendation |
|---------|--------|----------------|
| **NAV** | 82 rows are duplicate NAV_ID; we keep first. No missing ident/lat/lon. | **No change.** Keep collapse by NAV_ID. |
| **COM** | 766 rows have blank COMM_LOC_ID; no COM_OUTLET_ID in CSV. | **Implemented:** synthetic ids for blank COMM_LOC_ID (see below). |
| **AWY** | 50 rows are duplicate AWY_ID in base; no base-only orphans. | **No change.** Keep collapse by AWY_ID. |
| **DP** | 29 rows are duplicate DP_COMPUTER_CODE in base; base-only procedures already written with empty route/airports. | **No change.** Keep collapse by DP_COMPUTER_CODE. |

---

## COM synthetic IDs (post-audit implementation)

**Why synthetic ids are required for COM:**  
In the current NASR bundle, COM.csv has no `COM_OUTLET_ID` column and 766 rows have blank `COMM_LOC_ID`. Those rows would otherwise be dropped. To retain them without breaking stability across cycles, we assign a **deterministic synthetic id** when `COMM_LOC_ID` is blank.

**How it works:**  
- If `COMM_LOC_ID` is present, we use it as `outlet_id` (unchanged).  
- If `COMM_LOC_ID` is blank, we set `outlet_id = "SYN:" + sha1(canonical_key)`.  
- The canonical key uses: COMM_TYPE, COMM_OUTLET_NAME, FACILITY_ID, NAV_ID, NAV_TYPE, CITY, STATE_CODE, REGION_CODE, COUNTRY_CODE, LAT_DECIMAL, LONG_DECIMAL. Canonicalization: strip whitespace, uppercase, empty → `""`, lat/lon rounded to 6 decimals, joined with `"|"`.  
- Same logical row in a future cycle yields the same synthetic id; duplicates (same canonical key) are collapsed (first wins).  

**Validation:**  
`scripts_v2/validate_comms_ids.py` checks: (1) no duplicate `outlet_id` in comms.json, (2) running the builder twice on the same CSV yields identical ids.

---

*Report generated by `scripts_v2/loss_analysis_audit.py`. Re-run with path to `CSV_Data/extracted` to regenerate.*
