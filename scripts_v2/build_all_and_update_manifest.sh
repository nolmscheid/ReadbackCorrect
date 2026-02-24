#!/usr/bin/env bash
# Build aviation_data_v2 from FAA NASR 28-day data: download zip, extract CSVs, run build scripts, write manifest.
# Uses same FAA cycle logic as scripts/check_faa_cycle.py (v1). Fails if any required CSV is missing or output is empty.
# Run from repo root. Output: aviation_data_v2/

set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p aviation_data_v2

# Download NASR zip and locate Airport.csv, Navaid.csv, Fix.csv (exits non-zero if cycle/download/CSV missing)
source "$REPO_ROOT/scripts_v2/download_nasr.sh"

echo "Building airports.json..."
python3 scripts_v2/build_airports.py --airport-csv "$AIRPORT_CSV" -o aviation_data_v2/airports.json

echo "Building navaids.json..."
python3 scripts_v2/build_navaids.py --csv "$NAVAID_CSV" -o aviation_data_v2/navaids.json

echo "Building fixes.json..."
python3 scripts_v2/build_fixes.py --csv "$FIX_CSV" -o aviation_data_v2/fixes.json

# Fail if any output is empty (would publish empty arrays)
for f in aviation_data_v2/airports.json aviation_data_v2/navaids.json aviation_data_v2/fixes.json; do
  count=$(python3 -c "import json; d=json.load(open('$f')); print(len(d) if isinstance(d,list) else 0)")
  if [ "$count" -eq 0 ]; then
    echo "ERROR: Generated file is empty: $f (would publish empty data)." >&2
    exit 1
  fi
  echo "$f: $count records"
done

echo "Writing manifest..."
python3 scripts_v2/build_manifest.py --faa-cycle "$CYCLE" -o aviation_data_v2/aviation_manifest.json

echo "Done. Output in aviation_data_v2/"
