#!/usr/bin/env bash
# Download FAA NASR 28-day subscription zip, extract, and locate Airport/Navaid/Fix CSVs.
# Uses cycle from scripts/check_faa_cycle (same as v1). Exports AIRPORT_CSV, NAVAID_CSV, FIX_CSV, CYCLE.
# Exit non-zero if cycle unknown, download fails, or any required CSV is missing.
# Run from repo root. Usage: source scripts_v2/download_nasr.sh  (or eval $(scripts_v2/download_nasr.sh))

set -e
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

if [ -z "$CYCLE" ]; then
  echo "ERROR: Could not fetch FAA NASR cycle from index. Check network and scripts/check_faa_cycle.py." >&2
  exit 1
fi

# FAA zip URL: nfdc.faa.gov 28-day subscription (same pattern as Archives on FAA NASR Subscription page)
ZIP_URL="https://nfdc.faa.gov/webContent/28DaySub/28DaySubscription_Effective_${CYCLE}.zip"
WORK_DIR="${NASR_WORK_DIR:-/tmp/nasr_v2_$$}"
mkdir -p "$WORK_DIR"
ZIP_FILE="$WORK_DIR/nasr.zip"

echo "FAA cycle: $CYCLE"
echo "Downloading NASR zip..."
if command -v curl &>/dev/null; then
  curl -fsSL -o "$ZIP_FILE" "$ZIP_URL" || { echo "ERROR: Download failed: $ZIP_URL" >&2; exit 1; }
elif command -v wget &>/dev/null; then
  wget -q -O "$ZIP_FILE" "$ZIP_URL" || { echo "ERROR: Download failed: $ZIP_URL" >&2; exit 1; }
else
  echo "ERROR: Need curl or wget to download NASR zip." >&2
  exit 1
fi

echo "Extracting to $WORK_DIR..."
unzip -o -q "$ZIP_FILE" -d "$WORK_DIR"
rm -f "$ZIP_FILE"

# Robust discovery: find by name, no fixed folder layout (zip may have one top-level dir or flat CSVs)
AIRPORT_CSV=$(find "$WORK_DIR" -type f \( -iname "airport*.csv" -o -iname "apt*.csv" \) | head -1)
NAVAID_CSV=$(find "$WORK_DIR" -type f \( -iname "navaid*.csv" -o -iname "nav*.csv" \) | head -1)
FIX_CSV=$(find "$WORK_DIR" -type f \( -iname "fix*.csv" -o -iname "designated*point*.csv" -o -iname "dpp*.csv" \) | head -1)

missing=""
[ -z "$AIRPORT_CSV" ] && missing="${missing} Airport.csv"
[ -z "$NAVAID_CSV" ] && missing="${missing} Navaid.csv"
[ -z "$FIX_CSV" ]    && missing="${missing} Fix.csv (or Designated_Point.csv)"

if [ -n "$missing" ]; then
  echo "ERROR: Required NASR CSVs not found inside zip:${missing}" >&2
  echo "Searched under: $WORK_DIR" >&2
  exit 1
fi

echo "Found: Airport=$AIRPORT_CSV Navaid=$NAVAID_CSV Fix=$FIX_CSV"
export AIRPORT_CSV NAVAID_CSV FIX_CSV CYCLE NASR_WORK_DIR="$WORK_DIR"
