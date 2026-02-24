# Full FAA Data, When It Updates, and Automation

This guide covers: (1) **where to get the full datasets** for waypoints, airports, and Victor airways; (2) **how to know when the FAA has updated** (28-day cycle); (3) **how to automate** building and publishing to GitHub so you (and the app) stay current.

---

## 1. Full data sources

### FAA 28-day cycle

- **NASR (National Airspace System Resources)** updates on a **28-day cycle**. The “effective” date is when that cycle’s data becomes active.
- **Cycle index:**  
  **https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/**  
  The current cycle is shown on that page (e.g. “Subscription effective February 19, 2026”). New cycles are typically posted ~28 days before the next effective date.

### Waypoints (`waypoints.json`)

| Source | How | Output |
|--------|-----|--------|
| **FAA ArcGIS – Designated Points** | `scripts/build_waypoints.py` (no args, or `--csv PATH` for local) | Full list of fix/waypoint IDs (+ optional names) |
| **Local NASR CSV** | After downloading NASR, use the **FIX** CSV; columns like `IDENT`, `NAME` | `python build_waypoints.py --csv /path/to/fix.csv` |

- **Script:** `scripts/build_waypoints.py`  
- **Default:** Fetches from FAA ArcGIS Designated Points (same server as below).  
- **Output:** `scripts/out/waypoints.json` — array of `{"id": "GEP", "name": "..."}`.

### Airports (`airports.json`)

| Source | How | Output |
|--------|-----|--------|
| **FAA ArcGIS – US_Airport** | `scripts/build_airports.py` (no args) | Full airport list: id, name, city, state |
| **Local NASR CSV** | NASR subscription → airport CSV (LOCID, NAME, SERVCITY, STATE) | `python build_airports.py --csv /path/to/airports.csv` |

- **Script:** `scripts/build_airports.py`  
- **Default:** Fetches from same FAA ArcGIS server, **US_Airport** layer (IDENT → id, NAME → name, SERVCITY → city, STATE → state).  
- **Output:** `scripts/out/airports.json` — array of `{"id": "KMSP", "name": "...", "city": "...", "state": "..."}`.

### Victor airways (`victor_airways.json`)

- **Script:** `scripts/build_victor_airways.py`  
- **Source:** Static list V1–V500 (no FAA API for the list itself; the app uses it for validation/normalization).  
- **Output:** `scripts/out/victor_airways.json` — `["1","2",...,"500"]`.

To include **actual Victor airway definitions** (which fixes are on which airway) you’d need NASR **ATS route** or similar data; that can be a later enhancement.

---

## 2. Knowing when the FAA has updated

- **Check the cycle page:**  
  Open **https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/** and note the “Subscription effective &lt;date&gt;”. When that date changes, a new cycle is active.

- **Script check (no automation):**  
  Run:
  ```bash
  cd scripts
  python3 check_faa_cycle.py
  ```
  This prints the **current FAA cycle date** (from the FAA page) and compares it to the **cycle in `out/aviation_manifest.json`**. If they differ, it exits with code 1 and tells you to rebuild and push. Use **`python3 check_faa_cycle.py --set-manifest`** to write the manifest with the current FAA cycle (after building).

- **Automatic “know when”:**  
  Use **Option A** or **B** below; both can run on a schedule and either update the repo (so you see a new commit) or create an Issue/notification so you know to run the build.

---

## 3. Automation options

### Option A: Fully automatic (GitHub Actions) — **implemented**

A workflow in the **ReadBack** repo (`.github/workflows/aviation-data.yml`) runs on a schedule and pushes to **ReadbackCorrect**:

1. **Runs:** Every Monday at 09:00 UTC, plus **Actions → Aviation data → Run workflow** anytime.
2. Builds waypoints, airports, victor_airways, and sets the manifest cycle from the FAA page.
3. Pushes the four files to **ReadbackCorrect** → `aviation_data/`.

**One-time setup:** In **ReadBack** → **Settings → Secrets and variables → Actions**, add a repository secret **`READBACK_CORRECT_PAT`** (a Personal Access Token with push access to the ReadbackCorrect repo). See **GITHUB_DATA_SETUP.md** §5 for steps.

**Result:** Hands-off; the app’s “Check for updates” will see new data after each successful run.

### Option B: “Notify me” automatic (GitHub Actions)

A lighter workflow that **only checks** and notifies:

1. Run on a schedule (e.g. every Monday).
2. Fetch current FAA cycle from the FAA page; read `aviation_manifest.json` from the repo (e.g. from `main`).
3. If FAA cycle &gt; manifest cycle, **open a GitHub Issue** (e.g. “FAA data cycle 2026-03-19 is available; please run scripts and push”) or trigger a **repository_dispatch** / external notification.

**Result:** You get a clear signal (“FAA has updated”) and you run the build + push yourself (or trigger Option A manually).

### Option C: Local cron (you run scripts and push)

On your Mac (or a server you control):

1. **Cron or launchd** runs every 2 weeks, e.g.:
   ```bash
   cd /path/to/ReadBack/scripts
   python3 check_faa_cycle.py && ./build_all_and_update_manifest.sh
   ```
2. `check_faa_cycle.py` exits 1 when FAA cycle is newer than manifest; `build_all_and_update_manifest.sh` rebuilds and sets the manifest cycle (you then commit/push).

**Result:** No GitHub Actions; you rely on your machine and a script that builds + commits + pushes to GitHub.

---

## 4. One-time: build full set and push to GitHub

**Option A — all-in-one script (recommended):**

```bash
cd scripts
./build_all_and_update_manifest.sh
```

This runs `build_waypoints.py`, `build_airports.py`, `build_victor_airways.py`, then sets `out/aviation_manifest.json` to the current FAA cycle. Use `--no-set-cycle` if you’re offline and want to keep the existing manifest cycle.

**Option B — step by step:**

1. `python3 check_faa_cycle.py` — optional: see current FAA cycle vs manifest.
2. `python3 build_waypoints.py` then `python3 build_airports.py` then `python3 build_victor_airways.py`.
3. `python3 check_faa_cycle.py --set-manifest` — write manifest with current FAA cycle.
4. Copy `out/aviation_manifest.json`, `out/airports.json`, `out/waypoints.json`, `out/victor_airways.json` into **ReadbackCorrect** → **`aviation_data/`**.
5. Commit and push to `main`. The app’s default URL will then serve the full set; users see “Check for updates” / “Download” and get the new cycle.

---

## 5. Matching logic (waypoints, Victors, etc.) — next step

Once the **full** waypoints and airports (and optionally richer Victor data) are in place:

- **Waypoints:** The app already uses `waypointIds` for phonetic→code (e.g. “Golf Echo Papa” → GEP) and for route normalization. With the full list, more spoken waypoints will resolve correctly.
- **Victor airways:** The app uses `victorAirwayNumbers` (e.g. “23” for V23) for validation. **Phase 2** in `FAA_DATA_AND_PLATES_STRATEGY.md` describes adding “from database” pills in the route (R) for waypoint IDs and Victor numbers.
- **Airports:** Already matched by name/city for clearance limit (C). Full set improves “Minneapolis”, “Denver”, etc.

Next steps for matching logic:

1. **Route (R) display:** Split the route string into tokens; for each token that is in `waypointIds` or is V+number in `victorAirwayNumbers`, render it in the gray “from DB” pill (same style as C-row airport code).
2. **Victor definitions (optional):** If you add NASR ATS route data later, you could validate “V23 OCN” as “OCN is on V23” for a stronger check.

The scripts and this doc get you to **full, downloadable data** and **knowing when the FAA updates**; automation (A/B/C) keeps GitHub (and the app) up to date with minimal manual work.
