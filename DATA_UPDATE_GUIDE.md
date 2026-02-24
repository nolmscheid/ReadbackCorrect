# ReadBack aviation data – update guide

ReadBack uses three reference files: **airports**, **Victor airways**, and **waypoints**. The app can use bundled data (included in the build) or data you download from a server.

## In the app

- **Settings → Data server URL**  
  Set this to the base URL of your data server (e.g. `https://yourserver.com/readback_data`). No trailing slash needed.
- **Settings → UPDATE**  
  Fetches `aviation_manifest.json` from that URL, then downloads each file listed in the manifest and saves them locally. After that, the app uses this data until you run UPDATE again.

If the Data server URL is empty, UPDATE will ask you to set one or use the FAA page to get data manually. The app always has **bundle seed data** (airports, Victor airways, waypoints) so it works offline even before any update.

## Building the JSON files yourself

See the **`scripts/`** folder:

- **`scripts/README.md`** – Describes the build scripts and the manifest format.
- **`scripts/build_waypoints.py`** – Builds `waypoints.json` from a local CSV or FAA source (with a fallback list).
- **`scripts/build_victor_airways.py`** – Builds `victor_airways.json` (Victor 1–500).
- **`scripts/out/`** – Contains sample output and a sample `aviation_manifest.json`.

After running the scripts, copy the `out/*.json` files and the manifest to a web server. Point the app’s Data server URL at that server and tap UPDATE.

## Manifest format

Your server must serve at the base URL:

**`aviation_manifest.json`** with at least:

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

Use the current FAA 28-day cycle date for `cycle`. The app downloads each value in `files` (e.g. `airports.json`) relative to the base URL.

## FAA sources (for building data)

- **28-day NASR subscription:**  
  [FAA NASR Subscription](https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/)  
  Full ZIP includes airport, fix, and airway data (CSV or legacy TXT). Update every 28 days.
- **Designated points (waypoints):**  
  FAA Open Data (e.g. Designated Points) or export from NASR FIX/designated point CSV.
- **Airports:**  
  The bundle already includes a large airport list. To refresh, use NASR APT data or [FAA Airports – ArcGIS](https://adds-faa.opendata.arcgis.com/datasets/faa::airports-1/).

The app does **not** download from the FAA directly; you (or a script) build the JSON files and host them. The app only performs HTTP GETs to your manifest and file URLs.
