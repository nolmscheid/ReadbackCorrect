# Aviation data build scripts

These scripts generate the JSON files used by ReadBack for aviation reference data (waypoints, Victor airways, airports). You can run them locally and host the output on a web server, then set that URL in the app under **Settings → Data server URL** and tap **UPDATE**.

## Output files

| File | Description | App use |
|------|-------------|---------|
| `waypoints.json` | Fix/waypoint IDs (and optional names) | Phonetic spelling → code (e.g. "Golf Echo Papa" → GEP) |
| `victor_airways.json` | Array of Victor airway numbers, e.g. `["1","2",...,"500"]` | Route validation |
| `airports.json` | Airport id, name, city, state | Clearance limit → identifier (e.g. "Denver" → KDEN) |

## Manifest

Your server must also serve `aviation_manifest.json` at the base URL:

```json
{
  "cycle": "2026-02-19",
  "files": {
    "airports": "airports.json",
    "victor_airways": "victor_airways.json",
    "waypoints": "waypoints.json"
  }
}
```

Use the current FAA NASR cycle date (28-day cycle) for `cycle`. The app downloads each path in `files` relative to the manifest base URL.

## Scripts

### 1. Build waypoints (`build_waypoints.py`)

Fetches designated points (fix/waypoint IDs) from FAA Open Data and writes `waypoints.json`.

**Requirements:** Python 3.7+, `requests` (optional, for HTTP).

**Run:**
```bash
cd scripts
pip install requests   # if using network source
python build_waypoints.py
```

Output: `out/waypoints.json` (array of `{"id": "GEP", "name": "..."}`). Copy to your server or app bundle.

**Sources (in order of use):**
1. If `--csv PATH` is given, reads a local CSV with columns `IDENT` (or `id`) and optionally `NAME` (or `name`).
2. Otherwise, tries to download from FAA ArcGIS Open Data (Designated Points). If that fails, uses a bundled fallback list of common US waypoint IDs.

### 2. Build Victor airways (`build_victor_airways.py`)

Writes `victor_airways.json` with Victor airway numbers (e.g. 1–500). No external source required.

**Run:**
```bash
python build_victor_airways.py
```

Output: `out/victor_airways.json`.

### 3. Airports

The app bundle already includes a large `airports.json` (FAA-style id, name, city, state). To refresh from FAA:

- **Option A:** Download the 28-day NASR subscription from [FAA NASR Subscription](https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/), extract the airport CSV, and map columns to `id`, `name`, `city`, `state` (e.g. LOCID → id, NAME → name, SERVCITY → city, STATE → state). Save as JSON array.
- **Option B:** Use [FAA Airports – ArcGIS](https://adds-faa.opendata.arcgis.com/datasets/faa::airports-1/) and export CSV/JSON, then convert to the shape above.

A `build_airports.py` script can be added later to automate this from a local NASR CSV or ArcGIS export.

## Hosting and app update

1. Run the scripts and copy `out/*.json` and a manifest to a web-accessible directory (e.g. `https://yourserver.com/readback_data/`).
2. In ReadBack: **Settings → Data server URL** = `https://yourserver.com/readback_data` (no trailing slash is fine).
3. Tap **UPDATE**. The app fetches `aviation_manifest.json` and then each file in `files`, and stores them in app support. Subsequent launches use this data until the next update.

## Bundle seed data

For offline use with no server, the app uses seed data from its bundle (`waypoints.json`, `victor_airways.json`, `airports.json` in the Xcode target). You can replace or extend the bundle files by running these scripts and copying output into the ReadBack app target’s resource folder.
