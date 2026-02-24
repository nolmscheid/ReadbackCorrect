# FAA Data, Plates, and “From Database” Indicators — Strategy

This document outlines a phased approach for:

1. **FAA reference data** (waypoints, Victor airways, airports): host on GitHub (or similar), hardcode a default download URL so users only see “Check for updates” → “Download”.
2. **Plate (airport diagram) download**: when and how to prompt—Settings “Add Plate” and/or proximity-based “Download diagram for this airport?”.
3. **Visual “found in database” indicators**: reuse the C-row pattern (e.g. light gray box with code) for waypoints and Victor airways in the route so users see when a value came from the reference data.

---

## 1. FAA reference data (waypoints, Victor airways, airports)

### Current behavior

- **Settings** has a “Data server URL” field. If set, “Check for updates” fetches `aviation_manifest.json` from that URL and compares `cycle`; “Download” fetches each file in the manifest and saves to Application Support. If the URL is empty, the app uses bundle seed data and tells the user to set a URL or use the FAA page.
- Users must **know** a URL (or get it from you) to ever download updates. They never see “it just works” unless you hand them a URL.

### Goal

- **Users do not see or edit the download link.** They only see:
  - **Check for updates** — “Data is current (2026-02-19)” or “New data available. Tap Download.”
  - **Download** — fetches from a **default** server (e.g. your GitHub repo or a small static host).
- Optional: keep an “Advanced” or “Developer” section in Settings where the URL can be overridden for testing or self‑hosting.

### Approach

1. **Default data server URL (hardcoded)**  
   - In `AviationDataManager` (or a small config), define a **default** base URL, e.g.:
     - GitHub raw: `https://raw.githubusercontent.com/<your-org>/<readback-data>/main/aviation_data/`
     - Or a GitHub Release: `https://github.com/<org>/<repo>/releases/download/data-v1/` with manifest + JSON assets.
     - Or any static host (S3, Cloudflare, etc.) where you publish the same manifest + JSON files.
   - **Runtime logic:**  
     - If the user has **not** set a custom URL in Settings, use the hardcoded default for “Check for updates” and “Download”.  
     - If the user **has** set a custom URL, use that instead (so power users or enterprises can point to their own server).
   - In Settings UI:
     - **Option A (simplest):** Remove the URL field from the main screen. Show only “Check for updates” and “Download”. Optionally add “Data source: Default” with an “Advanced” expandable that reveals the URL (and allows override).
     - **Option B:** Pre-fill the URL field with the default and make it editable; label it “Data server URL (optional)” so users can leave it as-is.

2. **Hosting the files**  
   - Put in a repo (e.g. `readback-data` or a folder in the main repo):
     - `aviation_manifest.json` (cycle + `files`: airports, victor_airways, waypoints).
     - `airports.json`, `victor_airways.json`, `waypoints.json` (same format the app already expects).
   - Update the manifest `cycle` when you rebuild from FAA NASR (e.g. every 28 days). The app only does GETs; users never see the repo or the raw link.

3. **Check for updates / Download**  
   - No change to the *logic*: still fetch manifest, compare cycle, download listed files into Application Support, then reload.  
   - Only change: when `dataSourceBaseURL` is empty, use the **default** URL instead of showing “Set a data server URL…”. So “Check for updates” and “Download” work out of the box.

**Summary:** One hardcoded default URL; Settings can override. Users only see “Check for updates” and “Download”; no need to see or paste a link.

---

## 2. Plate (airport diagram) download

### Current behavior

- Diagrams are **bundle-only**: `AirportDiagramInfo.known` is a fixed list (e.g. KMIC); the PDF/image is in the app bundle. No download, no “add plate” flow.
- AIRPORT_DIAGRAM_GPS_FEATURE.md describes a future “download/cache diagrams by airport id”.

### Goal

- Support **downloading** airport diagrams (plates) and caching them locally.
- **When** to prompt:
  - **Option A:** Settings → “Add Plate” (user picks an airport, we download that plate).
  - **Option B:** When the user is **near an airport** (e.g. within 0.5 mi) and we have a diagram available for that airport, show an alert: “Download diagram for [airport]?”.
  - **Recommended:** Support **both**: Settings for explicit add; optional proximity prompt for convenience (can be toggled in Settings).

### Approach

#### 2.1 Data model

- **Plates manifest (on server):**  
  A JSON file (e.g. `plates_manifest.json`) at the same base URL or a dedicated URL, listing **available** diagrams:
  - Airport ID (e.g. KMIC, KSTC).
  - URL to the diagram asset (PDF or PNG).
  - Optional: bounds (minLat, maxLat, minLon, maxLon) for georeferencing; or the app uses a default/cached bounds per airport.
- **Local storage:**  
  - Application Support: e.g. `ReadBack/plates/<airportId>.pdf` (or `.png`) and optionally `plates/<airportId>_bounds.json`.
  - In memory: extend `AirportDiagramInfo` (or a separate “PlateInfo”) to include:
    - Source: bundle vs downloaded.
    - Local file URL for downloaded plates.

- **App’s list of “known” diagrams:**  
  - **Bundle:** Current static list (e.g. KMIC).  
  - **Downloaded:** Scan `ReadBack/plates/` and build a list of `AirportDiagramInfo` (or equivalent) with `assetName` → path to cached file.  
  - **Available but not downloaded:** From plates manifest; used for “Add Plate” picker and for proximity prompt (“we have a diagram for this airport, want to download?”).

#### 2.2 Settings → “Add Plate”

- New section in Settings: **“Airport diagrams”** or **“Plates”**.
  - **“Add plate…”** button → opens a screen:
    - Search / browse by airport ID or name (use existing `airportRecords` or a filtered list from the same reference data).
    - List or search results show airport id + name; tap one → “Download diagram for KMIC?” → download from plates manifest URL and save to `plates/KMIC.pdf`, then refresh the list of known diagrams.
  - List of **already downloaded** plates (airport id + name) with option to remove (delete file and remove from list).

- **Flow:** User doesn’t need to type a URL; the app uses the plates manifest (from the same default or custom data server) to resolve airport id → download URL.

#### 2.3 Proximity-based prompt (“Download diagram for this airport?”)

- **When:** On app launch or when app becomes active (and optionally when location updates), if:
  - User’s location is within **0.5 miles** (or configurable) of an airport’s reference point (from airport data or from plates manifest),
  - That airport has a diagram in the **plates manifest** (available to download),
  - We don’t already have that diagram downloaded (or in bundle).
- **UI:** One-time (or once per airport) alert: “You’re near [Airport name (KXXX)]. Download airport diagram?” [Download] [Not now].
- **Settings:** Toggle “Suggest diagram when near airport” (default on) so users can disable the prompt.
- **Throttling:** Don’t prompt again for the same airport for 24h (or until they download it) to avoid annoyance.

**Summary:** Plates manifest on server; “Add Plate” in Settings for manual add; optional proximity prompt with a Settings toggle and throttling.

---

## 3. “Found in database” indicators in the UI

### Current behavior

- **C (Clearance limit):** When we match the spoken clearance limit to an airport in the database, we show the **display name** and, in a **light gray box**, the **airport code** (e.g. MSP). So the gray box is the “we looked this up” indicator.
- **R (Route)** and **A/F/T/V:** No explicit indication that a waypoint or Victor airway came from the reference data.

### Goal

- Reuse the **same visual language** (e.g. light gray rounded box, secondary text) for:
  - **Waypoints** in the route (R): when a token in the route string is a known waypoint ID (in `waypointIds`), show it in a gray pill/badge so it’s clear “from DB”.
  - **Victor airways** in the route: when a token is “Vnn” and `nn` is in `victorAirwayNumbers`, show it in the same style.
- Airport (C) already has the gray box; we can add a small optional “✓” or leave as-is.

### Approach

1. **Route string (R) parsing for tokens**  
   - The route string can look like: `"DIRECT"`, `"BJI • THEN AS FILED"`, `"V23 OCN"`, `"DIRECT GEP V23"`, etc.
   - Split the displayed route into **segments** (e.g. by space and “•”): e.g. `["DIRECT", "BJI", "•", "THEN", "AS", "FILED"]` or `["V23", "OCN"]`.
   - For each segment:
     - If it’s a **3–5 letter all-caps token** and it’s in `waypointIds` → treat as **waypoint from DB**.
     - If it’s **V + digits** (e.g. V23) and the number part is in `victorAirwayNumbers` → treat as **Victor from DB**.
   - Render: for “from DB” segments, wrap in the same gray rounded background + semibold/monospaced as the C-row code; for others, plain text. Result: route line becomes a mix of plain text and gray pills (e.g. `DIRECT` **BJI** `• THEN AS FILED` or **V23** **OCN**).

2. **C (Clearance limit)**  
   - Already has gray box with airport code. Optionally add a very small checkmark icon next to the code, or leave as-is; the gray box is enough to mean “from database”.

3. **Implementation notes**  
   - `formatRouteForDisplay` currently returns a single string. To support “pill per token”, either:
     - Change the R row to accept an array of segments (string or “segment with DB flag”), and in the view loop over segments and render DB segments in a gray pill; or
     - Build an attributed string / view builder that inserts inline pills for known waypoints and Victors.
   - Need a helper: “given route string R, return list of (text, isFromDB)” using `waypointIds` and `victorAirwayNumbers`. Splitting by spaces and “•” and matching each token is enough for a first pass.

**Summary:** Same gray-pill style as C-row code for waypoint IDs and Victor numbers in the route; optional subtle checkmark on C. Users then see at a glance “this came from the reference data.”

---

## 4. Phasing

| Phase | What |
|-------|------|
| **1** | **Default data URL:** Hardcode default base URL; use it when user hasn’t set a custom URL. Optionally hide or pre-fill URL in Settings. No change to manifest or file formats. |
| **2** | **“From database” in route:** Parse R into segments; render waypoint IDs and Victor numbers that exist in `waypointIds` / `victorAirwayNumbers` in the gray pill style. |
| **3** | **Plates manifest + Add Plate:** Define `plates_manifest.json` and a simple “Add Plate” flow in Settings (search airport → download → save to app support; extend diagram list to include downloaded). |
| **4** | **Proximity prompt:** When within 0.5 mi of an airport that has a plate in the manifest, prompt once to download; Settings toggle and throttling. |

Phase 1 gives “Check for updates / Download” without users seeing a link. Phase 2 gives clear “from DB” feedback for route. Phases 3–4 add plate download and proximity.

---

## 5. File / URL summary

- **Reference data (existing):**  
  `aviation_manifest.json` + `airports.json`, `victor_airways.json`, `waypoints.json` at a **default** base URL (e.g. GitHub raw or Releases). Same format as today.
- **Plates (new):**  
  `plates_manifest.json` (list of airport id + diagram URL + optional bounds). Diagram files stored under Application Support `ReadBack/plates/<id>.pdf` (or .png).
- **Settings:**  
  “Check for updates” / “Download” use default URL unless user overrides. “Add plate…” uses same server (or a dedicated plates base URL) to resolve diagram URLs. Optional “Suggest diagram when near airport” toggle.

This keeps the app simple for users (no URLs to copy), preserves power-user override, and aligns plates and “from database” visuals with the existing C-row pattern.
