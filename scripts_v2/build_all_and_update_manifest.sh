#!/usr/bin/env bash
# Build aviation_data_v2 from FAA NASR 28-day data: download zip, extract CSVs, run build scripts, write manifest.
# Uses same FAA cycle logic as scripts/check_faa_cycle.py (v1). Fails if any required CSV is missing or output is empty.
# Run from repo root. Output: aviation_data_v2/

set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p aviation_data_v2

# Download NASR zip and locate all CSVs (exits non-zero if cycle/download/any CSV missing)
source "$REPO_ROOT/scripts_v2/download_nasr.sh"

echo "Building airports.json..."
python3 scripts_v2/build_airports.py --airport-csv "$AIRPORT_CSV" -o aviation_data_v2/airports.json

echo "Building navaids.json..."
python3 scripts_v2/build_navaids.py --csv "$NAVAID_CSV" -o aviation_data_v2/navaids.json

echo "Building fixes.json..."
python3 scripts_v2/build_fixes.py --csv "$FIX_CSV" -o aviation_data_v2/fixes.json

echo "Building runways.json..."
python3 scripts_v2/build_runways.py --rwy-csv "$APT_RWY_CSV" --rwy-end-csv "$APT_RWY_END_CSV" -o aviation_data_v2/runways.json

echo "Building frequencies.json..."
python3 scripts_v2/build_frequencies.py --csv "$FRQ_CSV" -o aviation_data_v2/frequencies.json

echo "Building comms.json..."
python3 scripts_v2/build_comms.py --csv "$COM_CSV" -o aviation_data_v2/comms.json

echo "Building airways.json..."
python3 scripts_v2/build_airways.py --base-csv "$AWY_BASE_CSV" --seg-csv "$AWY_SEG_ALT_CSV" -o aviation_data_v2/airways.json

echo "Building departures.json and arrivals.json..."
python3 scripts_v2/build_procedures.py \
  --dp-base "$DP_BASE_CSV" --dp-rte "$DP_RTE_CSV" --dp-apt "$DP_APT_CSV" \
  --star-base "$STAR_BASE_CSV" --star-rte "$STAR_RTE_CSV" --star-apt "$STAR_APT_CSV" \
  -o aviation_data_v2

echo "Building ils.json..."
python3 scripts_v2/build_ils.py \
  --base-csv "$ILS_BASE_CSV" --dme-csv "$ILS_DME_CSV" --gs-csv "$ILS_GS_CSV" --mkr-csv "$ILS_MKR_CSV" \
  -o aviation_data_v2/ils.json

# Deterministic non-empty checks: ensure we loaded substantial data
count_json() {
  python3 -c "import json; d=json.load(open('$1')); print(len(d) if isinstance(d,list) else 0)"
}

airports_count=$(count_json aviation_data_v2/airports.json)
fixes_count=$(count_json aviation_data_v2/fixes.json)
navaids_count=$(count_json aviation_data_v2/navaids.json)
runways_count=$(count_json aviation_data_v2/runways.json)
frequencies_count=$(count_json aviation_data_v2/frequencies.json)
comms_count=$(count_json aviation_data_v2/comms.json)
airways_count=$(count_json aviation_data_v2/airways.json)
departures_count=$(count_json aviation_data_v2/departures.json)
arrivals_count=$(count_json aviation_data_v2/arrivals.json)
ils_count=$(count_json aviation_data_v2/ils.json)

echo "aviation_data_v2/airports.json: $airports_count records"
echo "aviation_data_v2/fixes.json: $fixes_count records"
echo "aviation_data_v2/navaids.json: $navaids_count records"
echo "aviation_data_v2/runways.json: $runways_count records"
echo "aviation_data_v2/frequencies.json: $frequencies_count records"
echo "aviation_data_v2/comms.json: $comms_count records"
echo "aviation_data_v2/airways.json: $airways_count records"
echo "aviation_data_v2/departures.json: $departures_count records"
echo "aviation_data_v2/arrivals.json: $arrivals_count records"
echo "aviation_data_v2/ils.json: $ils_count records"

fail() { echo "ERROR: $1" >&2; exit 1; }

[ "$airports_count" -le 10000 ] && fail "airports.json has too few records ($airports_count), expected > 10000."
[ "$fixes_count" -le 50000 ] && fail "fixes.json has too few records ($fixes_count), expected > 50000."
[ "$navaids_count" -le 500 ] && fail "navaids.json has too few records ($navaids_count), expected > 500."
[ "$runways_count" -eq 0 ] && fail "runways.json is empty."
[ "$frequencies_count" -eq 0 ] && fail "frequencies.json is empty."
[ "$comms_count" -eq 0 ] && fail "comms.json is empty."
[ "$airways_count" -eq 0 ] && fail "airways.json is empty."
[ "$departures_count" -eq 0 ] && fail "departures.json is empty."
[ "$arrivals_count" -eq 0 ] && fail "arrivals.json is empty."
[ "$ils_count" -eq 0 ] && fail "ils.json is empty."

echo "Writing manifest..."
python3 scripts_v2/build_manifest.py --faa-cycle "$CYCLE" -o aviation_data_v2/aviation_manifest.json

echo "Done. Output in aviation_data_v2/"
