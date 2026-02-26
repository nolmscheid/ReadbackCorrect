# Aviation Reference Data — Sources & Update Strategy

ReadBack uses FAA and other reference data to improve recognition of Victor airways, airport names, and procedures. This doc lists **free** vs **subscription** sources and how we use them.

---

## Free (FAA official)

### 1. 28-Day NASR Subscription — **FREE**

- **What:** National Airspace System Resources (airports, airways, fixes, procedures, navaids, etc.).
- **Where:** [FAA NASR Subscription](https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/)
- **Format:** Full ZIP or **individual CSV ZIPs** per type. Updates every **28 days** (AIRAC-style).
- **Relevant files:**
  - **APT** — Airports and Other Landing Facilities (name, ID, city, state).
  - **AWY** — Airway (Victor/Jet route structure; we use for Victor airway list).
  - **FIX** — Fix/waypoint (for OCN-style waypoints).
  - **DP** — Departure Procedures (SID names).
  - **STAR** — Standard Terminal Arrival (STAR names).
- **Current cycle URL pattern:**  
  - Index: `https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/`  
  - Full ZIP: `https://nfdc.faa.gov/webContent/28DaySub/28DaySubscription_Effective_YYYY-MM-DD.zip`  
  - APT CSV: `https://nfdc.faa.gov/webContent/28DaySub/extra/DD_Mon_YYYY_APT_CSV.zip` (e.g. `19_Feb_2026_APT_CSV.zip`)  
  - AWY CSV: `.../extra/DD_Mon_YYYY_AWY_CSV.zip`  
  - FIX CSV: `.../extra/DD_Mon_YYYY_FIX_CSV.zip` (fix/waypoint identifiers and names for route validation)
- **License/terms:** U.S. Government product; no fee. Check [FAA Aeronautical Data](https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/) for any use restrictions (typically fine for app use).

### 2. CIFP (Coded Instrument Flight Procedures) — **FREE**

- **What:** ARINC 424 procedure data (approaches, SIDs, STARs in coded form).
- **Where:** [FAA CIFP Download](https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/cifp/download/)
- **Update:** Every **28 days**.
- **Caveat:** Raw ARINC 424; needs parsing. For **procedure names** only, NASR **DP** and **STAR** CSVs are easier. Use CIFP only if we need full procedure geometry later.

### 3. Preferred Routes Database — **FREE**

- **What:** Preferred route strings (origin/destination → route).
- **Where:** [Preferred Routes](https://www.fly.faa.gov/rmt/nfdc_preferred_routes_database)  
  - CSV: `https://www.fly.faa.gov/rmt/data_file/prefroutes_db.csv`
- **Use:** Optional; more for route suggestion than for speech recognition.

### 4. FAA ArcGIS Open Data (Airports) — **FREE**

- **What:** Airport list (identifier, name, location, etc.).
- **Where:** [FAA Airports – ArcGIS](https://adds-faa.opendata.arcgis.com/datasets/faa::airports-1/explore) — can export or use API.
- **Use:** Alternative to NASR APT if we want a simple airport table without parsing NASR.

---

## Subscription / paid (for your decision)

- **FAA SWIM / Data Portal APIs:** Some real-time or premium datasets may require registration or subscription. For **static reference data** (airports, airways, procedures), the **free NASR subscription** is enough.
- **Third-party aviation data (ForeFlight, Garmin, Jeppesen):** Usually paid; offer cleaned/merged data. Only consider if we need global data or premium features; not required for US NASR-based recognition.

**Recommendation:** Use **only free FAA NASR (APT, AWY, DP, STAR)** for ReadBack. No subscription needed for the phased plan.

---

## What we use in ReadBack

| Data           | Source        | Update cycle | Use in app                          |
|----------------|---------------|--------------|-------------------------------------|
| Victor airways | NASR AWY CSV  | 28 days      | Validate/normalize “Victor 2 3” → V23 |
| Airport names  | NASR APT CSV  | 28 days      | “Cleared to [X]” fuzzy match        |
| SID/STAR names | NASR DP/STAR  | 28 days      | “Via Platteville Two” recognition   |
| Fix/waypoints  | NASR FIX CSV  | 28 days      | Optional; waypoint names            |

---

## Update strategy (Settings)

You can get updates in two ways:

### Option A: Data server (recommended)

1. **Set a data server URL** in Settings → Aviation Reference Data. The server hosts a **manifest** and the JSON files it lists.
2. **Check for updates** fetches `aviation_manifest.json` from that URL and compares its `cycle` to what you have.
3. **Download** fetches each file listed in the manifest and saves it into app support. The app then uses those files (airports, Victor airways, waypoints) until the next update.

No FAA parsing in the app: you (or a script) pull from FAA, build the JSON files and manifest, and host them. The app only does HTTP GETs. Easiest to run a small script or cron that downloads FAA NASR ZIPs, parses APT/AWY/FIX into the JSON shapes below, and uploads to S3, GitHub Releases, or any static host.

### Option B: FAA direct (future)

- **Check for updates** with no server set: the app scrapes the FAA NASR subscription page for the current cycle and tells you “FAA cycle is X; set a data server URL to download, or open FAA page.”
- **Download** with no server set: opens the FAA NASR page in the browser so you can download manually. In-app download of raw FAA ZIPs (with a ZIP library and CSV parsing) can be added later if you want to skip hosting a server.

### Runtime

- **Bundled seed:** `victor_airways.json`, `airports.json`, `waypoints.json` in the app bundle so the app works offline without ever updating.
- **App Support:** If present, `Application Support/ReadBack/aviation_data/` is used first (after a successful Download). Same filenames as bundle.

---

## Manifest format (data server)

Your server must expose a JSON manifest at the base URL:

**URL:** `{Data Server URL}/aviation_manifest.json`  
**Example:** `https://yourserver.com/readback_data/aviation_manifest.json`

**Schema:**

```json
{
  "cycle": "2026-02-19",
  "updated": "2026-02-19T12:00:00Z",
  "files": {
    "airports": "airports.json",
    "victor_airways": "victor_airways.json",
    "waypoints": "waypoints.json"
  }
}
```

- **cycle** (required): NASR cycle date (YYYY-MM-DD). Used to compare with the user’s current data.
- **updated** (optional): ISO timestamp when you built the data.
- **files** (required): Keys are logical names; values are paths relative to the manifest base URL. The app downloads each URL and saves the file under Application Support using the **filename** only (e.g. `airports.json`). So paths can be `airports.json` or `v1/airports.json`; the app expects to find `airports.json`, `victor_airways.json`, and `waypoints.json` in app support after download.

**File formats the app expects:**

- **airports.json:** Array of `{ "id": "KDEN", "name": "...", "city": "...", "state": "..." }`.
- **victor_airways.json:** Array of Victor airway numbers as strings, e.g. `["1","2","3",...,"500"]`.
- **waypoints.json:** Array of `{ "id": "OCN", "name": "Ocean" }` (name optional).

You can generate these from FAA NASR APT/AWY/FIX CSVs with a script; the app does not parse FAA CSVs itself when using a server.

---

## File layout (in app)

- **Bundle:** `victor_airways.json`, `airports.json`, `waypoints.json` as seed data.  
- **App Support (after Download):** Same filenames under `Application Support/ReadBack/aviation_data/`.

**Adding bundle data in Xcode:** Add `victor_airways.json`, `airports.json`, and `waypoints.json` to the ReadBack app target so they are copied to the app bundle. `AviationDataManager` loads from app support first, then falls back to the bundle.

---

## CSV format notes (NASR)

- **APT CSV:** Column layout is documented in the NASR README and layout PDF in the subscription ZIP. We need at least: facility site number, official name, city, state, location ID (e.g. KDEN).
- **AWY CSV:** Contains route type (e.g. V) and route number; we extract distinct “V” + number for Victor list.
- **FIX CSV:** Fix/waypoint records (e.g. waypoint ID, name, type). Use for route validation and “Oscar Charlie November” → OCN-style resolution. Inspect the ZIP’s FIX layout/README for exact columns.
- **DP / STAR CSV:** Procedure name and airport; we extract procedure names for recognition.

When implementing the downloader, inspect the first few rows and the README in the ZIP for exact column names and delimiters.
