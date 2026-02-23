#!/usr/bin/env bash
# Build waypoints, airports, victor_airways; then set aviation_manifest.json cycle from FAA.
# Usage: ./build_all_and_update_manifest.sh [--no-set-cycle]
# Use --no-set-cycle to skip updating manifest cycle (e.g. when offline).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building waypoints..."
python3 build_waypoints.py

echo "Building airports..."
python3 build_airports.py

echo "Building victor airways..."
python3 build_victor_airways.py

if [[ "${1:-}" != "--no-set-cycle" ]]; then
  echo "Setting manifest cycle from FAA..."
  python3 check_faa_cycle.py --set-manifest
else
  echo "Skipping manifest cycle update (--no-set-cycle)."
fi

echo "Done. Output in out/"
