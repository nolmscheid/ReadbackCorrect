#!/usr/bin/env bash
# Download FAA NASR 28-day subscription zip, extract, and locate APT_BASE/NAV_BASE/FIX_BASE CSVs.
# Uses cycle from scripts/check_faa_cycle (same as v1). Exports AIRPORT_CSV, NAVAID_CSV, FIX_CSV, CYCLE, NASR_WORK_DIR.
# Exit non-zero if cycle unknown, download fails, or any required CSV is missing.
# Run from repo root. Usage: source scripts_v2/download_nasr.sh

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Get current FAA NASR cycle (same as scripts/check_faa_cycle.py and v1 pipeline)
CYCLE=$(python3 -c "
import sys
sys.path.insert(0, 'scripts')
from check_faa_cycle import fetch_current_cycle
c = fetch_current_cycle()
print(c or '')
" 2>/dev/null || true)

if [ -z "${CYCLE:-}" ]; then
  echo "ERROR: Could not fetch FAA NASR cycle from index. Check network and scripts/check_faa_cycle.py." >&2
  exit 1
fi

# FAA zip URL: nfdc.faa.gov 28-day subscription (same pattern as Archives on FAA NASR Subscription page)
ZIP_URL="https://nfdc.faa.gov/webContent/28DaySub/28DaySubscription_Effective_${CYCLE}.zip"
NASR_WORK_DIR="${NASR_WORK_DIR:-/tmp/nasr_v2_$$}"
mkdir -p "$NASR_WORK_DIR"
ZIP_FILE="$NASR_WORK_DIR/nasr.zip"

echo "FAA cycle: $CYCLE"
echo "NASR_WORK_DIR: $NASR_WORK_DIR"
echo "Downloading NASR zip..."
if command -v curl &>/dev/null; then
  curl -fsSL -o "$ZIP_FILE" "$ZIP_URL" || { echo "ERROR: Download failed: $ZIP_URL" >&2; exit 1; }
elif command -v wget &>/dev/null; then
  wget -q -O "$ZIP_FILE" "$ZIP_URL" || { echo "ERROR: Download failed: $ZIP_URL" >&2; exit 1; }
else
  echo "ERROR: Need curl or wget to download NASR zip." >&2
  exit 1
fi

echo "Extracting subscription zip to $NASR_WORK_DIR..."
unzip -o -q "$ZIP_FILE" -d "$NASR_WORK_DIR"
rm -f "$ZIP_FILE"

CSV_DATA="$NASR_WORK_DIR/CSV_Data"
nested_zip=""
if [ -d "$CSV_DATA" ]; then
  # Find nested CSV bundle zip like 19_Mar_2026_CSV.zip
  nested_zip=$(find "$CSV_DATA" -maxdepth 1 -type f -iname "*_CSV.zip" -print -quit || true)
  if [ -n "$nested_zip" ]; then
    echo "Found nested CSV bundle: $nested_zip"
    mkdir -p "$CSV_DATA/extracted"
    unzip -o -q "$nested_zip" -d "$CSV_DATA/extracted"
  else
    echo "No nested *_CSV.zip found under $CSV_DATA (will try to locate base CSVs directly)." >&2
  fi
else
  echo "WARNING: CSV_Data/ not found under $NASR_WORK_DIR (will try to locate base CSVs directly)." >&2
fi

# Diagnostic: list top-level contents when running in CI (helps debug zip structure changes)
if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "Contents of NASR_WORK_DIR (top-level):" >&2
  ls -la "$NASR_WORK_DIR" 2>/dev/null || true
  if [ -d "$CSV_DATA" ]; then
    echo "Contents of CSV_Data/:" >&2
    ls -la "$CSV_DATA" 2>/dev/null || true
  fi
fi

# Locate all required CSVs recursively under NASR_WORK_DIR
AIRPORT_CSV=$(find "$NASR_WORK_DIR" -type f -iname "APT_BASE.csv" -print -quit || true)
NAVAID_CSV=$(find "$NASR_WORK_DIR" -type f -iname "NAV_BASE.csv" -print -quit || true)
FIX_CSV=$(find "$NASR_WORK_DIR" -type f -iname "FIX_BASE.csv" -print -quit || true)
APT_RWY_CSV=$(find "$NASR_WORK_DIR" -type f -iname "APT_RWY.csv" -print -quit || true)
APT_RWY_END_CSV=$(find "$NASR_WORK_DIR" -type f -iname "APT_RWY_END.csv" -print -quit || true)
FRQ_CSV=$(find "$NASR_WORK_DIR" -type f -iname "FRQ.csv" -print -quit || true)
COM_CSV=$(find "$NASR_WORK_DIR" -type f -iname "COM.csv" -print -quit || true)
AWY_BASE_CSV=$(find "$NASR_WORK_DIR" -type f -iname "AWY_BASE.csv" -print -quit || true)
AWY_SEG_ALT_CSV=$(find "$NASR_WORK_DIR" -type f -iname "AWY_SEG_ALT.csv" -print -quit || true)
DP_BASE_CSV=$(find "$NASR_WORK_DIR" -type f -iname "DP_BASE.csv" -print -quit || true)
DP_RTE_CSV=$(find "$NASR_WORK_DIR" -type f -iname "DP_RTE.csv" -print -quit || true)
DP_APT_CSV=$(find "$NASR_WORK_DIR" -type f -iname "DP_APT.csv" -print -quit || true)
STAR_BASE_CSV=$(find "$NASR_WORK_DIR" -type f -iname "STAR_BASE.csv" -print -quit || true)
STAR_RTE_CSV=$(find "$NASR_WORK_DIR" -type f -iname "STAR_RTE.csv" -print -quit || true)
STAR_APT_CSV=$(find "$NASR_WORK_DIR" -type f -iname "STAR_APT.csv" -print -quit || true)
ILS_BASE_CSV=$(find "$NASR_WORK_DIR" -type f -iname "ILS_BASE.csv" -print -quit || true)
ILS_DME_CSV=$(find "$NASR_WORK_DIR" -type f -iname "ILS_DME.csv" -print -quit || true)
ILS_GS_CSV=$(find "$NASR_WORK_DIR" -type f -iname "ILS_GS.csv" -print -quit || true)
ILS_MKR_CSV=$(find "$NASR_WORK_DIR" -type f -iname "ILS_MKR.csv" -print -quit || true)

MISSING=""
[ -z "$AIRPORT_CSV" ] && MISSING="${MISSING} APT_BASE.csv"
[ -z "$NAVAID_CSV" ] && MISSING="${MISSING} NAV_BASE.csv"
[ -z "$FIX_CSV" ] && MISSING="${MISSING} FIX_BASE.csv"
[ -z "$APT_RWY_CSV" ] && MISSING="${MISSING} APT_RWY.csv"
[ -z "$APT_RWY_END_CSV" ] && MISSING="${MISSING} APT_RWY_END.csv"
[ -z "$FRQ_CSV" ] && MISSING="${MISSING} FRQ.csv"
[ -z "$COM_CSV" ] && MISSING="${MISSING} COM.csv"
[ -z "$AWY_BASE_CSV" ] && MISSING="${MISSING} AWY_BASE.csv"
[ -z "$AWY_SEG_ALT_CSV" ] && MISSING="${MISSING} AWY_SEG_ALT.csv"
[ -z "$DP_BASE_CSV" ] && MISSING="${MISSING} DP_BASE.csv"
[ -z "$DP_RTE_CSV" ] && MISSING="${MISSING} DP_RTE.csv"
[ -z "$DP_APT_CSV" ] && MISSING="${MISSING} DP_APT.csv"
[ -z "$STAR_BASE_CSV" ] && MISSING="${MISSING} STAR_BASE.csv"
[ -z "$STAR_RTE_CSV" ] && MISSING="${MISSING} STAR_RTE.csv"
[ -z "$STAR_APT_CSV" ] && MISSING="${MISSING} STAR_APT.csv"
[ -z "$ILS_BASE_CSV" ] && MISSING="${MISSING} ILS_BASE.csv"
[ -z "$ILS_DME_CSV" ] && MISSING="${MISSING} ILS_DME.csv"
[ -z "$ILS_GS_CSV" ] && MISSING="${MISSING} ILS_GS.csv"
[ -z "$ILS_MKR_CSV" ] && MISSING="${MISSING} ILS_MKR.csv"

if [ -n "$MISSING" ]; then
  echo "ERROR: Required CSV(s) not found under $NASR_WORK_DIR:$MISSING" >&2
  echo "This workflow expects the NASR 28-day subscription zip to contain CSV_Data/<cycle>_CSV.zip with APT_BASE, NAV_BASE, FIX_BASE, etc." >&2
  if [ -d "$NASR_WORK_DIR" ]; then
    echo "Directory listing (recursive, first 50 lines):" >&2
    find "$NASR_WORK_DIR" -type f -name "*.csv" 2>/dev/null | head -50
  fi
  exit 1
fi

echo "APT_BASE=$AIRPORT_CSV"
echo "NAV_BASE=$NAVAID_CSV"
echo "FIX_BASE=$FIX_CSV"
echo "APT_RWY=$APT_RWY_CSV" && echo "APT_RWY_END=$APT_RWY_END_CSV"
echo "FRQ=$FRQ_CSV" && echo "COM=$COM_CSV"
echo "AWY_BASE=$AWY_BASE_CSV" && echo "AWY_SEG_ALT=$AWY_SEG_ALT_CSV"
echo "DP_BASE=$DP_BASE_CSV" && echo "DP_RTE=$DP_RTE_CSV" && echo "DP_APT=$DP_APT_CSV"
echo "STAR_BASE=$STAR_BASE_CSV" && echo "STAR_RTE=$STAR_RTE_CSV" && echo "STAR_APT=$STAR_APT_CSV"
echo "ILS_BASE=$ILS_BASE_CSV" && echo "ILS_DME=$ILS_DME_CSV" && echo "ILS_GS=$ILS_GS_CSV" && echo "ILS_MKR=$ILS_MKR_CSV"

export AIRPORT_CSV="$AIRPORT_CSV"
export NAVAID_CSV="$NAVAID_CSV"
export FIX_CSV="$FIX_CSV"
export APT_RWY_CSV="$APT_RWY_CSV"
export APT_RWY_END_CSV="$APT_RWY_END_CSV"
export FRQ_CSV="$FRQ_CSV"
export COM_CSV="$COM_CSV"
export AWY_BASE_CSV="$AWY_BASE_CSV"
export AWY_SEG_ALT_CSV="$AWY_SEG_ALT_CSV"
export DP_BASE_CSV="$DP_BASE_CSV"
export DP_RTE_CSV="$DP_RTE_CSV"
export DP_APT_CSV="$DP_APT_CSV"
export STAR_BASE_CSV="$STAR_BASE_CSV"
export STAR_RTE_CSV="$STAR_RTE_CSV"
export STAR_APT_CSV="$STAR_APT_CSV"
export ILS_BASE_CSV="$ILS_BASE_CSV"
export ILS_DME_CSV="$ILS_DME_CSV"
export ILS_GS_CSV="$ILS_GS_CSV"
export ILS_MKR_CSV="$ILS_MKR_CSV"
export CYCLE="$CYCLE"
export NASR_WORK_DIR="$NASR_WORK_DIR"

