#!/usr/bin/env bash
# Build aviation_data_v2 and set manifest from current FAA cycle.
# Uses same FAA cycle detection as scripts/check_faa_cycle.py.
# Run from repo root. Output: aviation_data_v2/

set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p aviation_data_v2

# Get current FAA NASR cycle (same logic as scripts/check_faa_cycle.py)
echo "Fetching FAA NASR cycle..."
CYCLE=$(python3 -c "
import sys
sys.path.insert(0, 'scripts')
from check_faa_cycle import fetch_current_cycle
c = fetch_current_cycle()
print(c or '')
" 2>/dev/null || true)

if [ -z "$CYCLE" ]; then
  echo "Could not fetch FAA cycle; using fallback date." >&2
  CYCLE=$(date -u +%Y-%m-%d)
fi
echo "FAA cycle: $CYCLE"

# Ensure JSON files exist so build_manifest can count (empty if no NASR CSVs provided)
for f in airports.json navaids.json fixes.json; do
  if [ ! -f "aviation_data_v2/$f" ]; then
    echo '[]' > "aviation_data_v2/$f"
  fi
done

# Write manifest with cycle and counts from aviation_data_v2
python3 scripts_v2/build_manifest.py --faa-cycle "$CYCLE" -o aviation_data_v2/aviation_manifest.json

echo "Done. Output in aviation_data_v2/"
