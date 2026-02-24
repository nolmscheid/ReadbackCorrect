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

# Locate APT_BASE/NAV_BASE/FIX_BASE CSVs recursively under NASR_WORK_DIR
AIRPORT_CSV=$(find "$NASR_WORK_DIR" -type f -iname "APT_BASE.csv" -print -quit || true)
NAVAID_CSV=$(find "$NASR_WORK_DIR" -type f -iname "NAV_BASE.csv" -print -quit || true)
FIX_CSV=$(find "$NASR_WORK_DIR" -type f -iname "FIX_BASE.csv" -print -quit || true)

if [ -z "$AIRPORT_CSV" ] || [ -z "$NAVAID_CSV" ] || [ -z "$FIX_CSV" ]; then
  if [ -z "$nested_zip" ]; then
    echo "ERROR: NASR CSV bundle zip not found under $CSV_DATA and base CSVs (APT_BASE/NAV_BASE/FIX_BASE) not found under $NASR_WORK_DIR." >&2
  else
    echo "ERROR: Base CSVs (APT_BASE/NAV_BASE/FIX_BASE) not found under $NASR_WORK_DIR after extracting $nested_zip." >&2
  fi
  exit 1
fi

echo "APT_BASE=$AIRPORT_CSV"
echo "NAV_BASE=$NAVAID_CSV"
echo "FIX_BASE=$FIX_CSV"

export AIRPORT_CSV="$AIRPORT_CSV"
export NAVAID_CSV="$NAVAID_CSV"
export FIX_CSV="$FIX_CSV"
export CYCLE="$CYCLE"
export NASR_WORK_DIR="$NASR_WORK_DIR"

