# Phase 1: Hosting ReadBack aviation data on GitHub

This guide walks you through putting the app’s reference data (airports, Victor airways, waypoints) on GitHub so users can use **Check for updates** and **Download** without entering a URL. The app’s default URL points to the **ReadbackCorrect** repo.

**Repo:** [github.com/nolmscheid/ReadbackCorrect](https://github.com/nolmscheid/ReadbackCorrect)

---

## Option A: GitHub Raw (simplest)

**Best for:** Getting going quickly. Files are served from your repo’s `main` branch.

### 1. Use your existing repo

The app is already configured to use:

- **Base URL:** `https://raw.githubusercontent.com/nolmscheid/ReadbackCorrect/main/aviation_data`
- So the app will request `aviation_manifest.json` and the three JSON files from the **`aviation_data`** folder in **ReadbackCorrect**.

### 2. Create the `aviation_data` folder (on GitHub’s website)

GitHub doesn’t have a “New folder” button. You create a folder by **adding a file whose path includes the folder name**.

1. Open your repo: **https://github.com/nolmscheid/ReadbackCorrect**
2. Click **“Add file”** → **“Create new file”**.
3. In the **“Name your file...”** box, type exactly:  
   **`aviation_data/aviation_manifest.json`**  
   That creates the folder **`aviation_data`** and the file **`aviation_manifest.json`** inside it.
4. In the big text area, paste this (use the current FAA cycle date for `cycle` if you prefer):

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

5. Scroll down, add a commit message (e.g. “Add aviation data”), and click **“Commit new file”**.  
   You now have a folder **`aviation_data`** with **`aviation_manifest.json`** in it.

6. Add the other three files **inside** `aviation_data`:
   - Click the folder **`aviation_data`** in the file list so you’re “inside” it.
   - Click **“Add file”** → **“Upload files”**.
   - Drag and drop **`airports.json`**, **`victor_airways.json`**, and **`waypoints.json`** (from your ReadBack project: `ReadBack/ReadBack/waypoints.json`, `victor_airways.json`, and your airports file from the bundle or `scripts/out/`).
   - Commit the upload.

You should end up with this structure at the root of the repo:

```
ReadbackCorrect/
  aviation_data/
    aviation_manifest.json
    airports.json
    victor_airways.json
    waypoints.json
```

| File | Purpose |
|------|--------|
| `aviation_manifest.json` | Tells the app the cycle date and which files to download. |
| `airports.json` | Airport list (id, name, city, state). |
| `victor_airways.json` | Array of Victor airway numbers, e.g. `["1","2",...,"500"]`. |
| `waypoints.json` | Array of `{"id":"OCN","name":null}` (or with names). |

**Alternative (command line):** Clone the repo, create `aviation_data/` on your machine, put all four files in it, then commit and push. You can also build the JSON files with the scripts in `scripts/` (see `scripts/README.md` and `DATA_UPDATE_GUIDE.md`) and copy them into `aviation_data/`.

### 3. Base URL (already set in the app)

The app is configured to use:

`https://raw.githubusercontent.com/nolmscheid/ReadbackCorrect/main/aviation_data`

So it will request:

- `.../aviation_data/aviation_manifest.json`
- `.../aviation_data/airports.json`
- `.../aviation_data/victor_airways.json`
- `.../aviation_data/waypoints.json`

No change needed in Xcode unless you move the data to another repo or path.

### 4. Updating data (every 28 days)

- When the FAA cycle changes, regenerate or update the three JSON files (and the manifest `cycle`).
- Push the updated files to **`aviation_data/`** in ReadbackCorrect.  
  Users who tap **Check for updates** will see “New data available”; **Download** will pull the new files.

### 5. Automatic updates (hands-off)

The **ReadBack** repo includes a GitHub Actions workflow that builds the data and pushes it to ReadbackCorrect so you don’t have to do it manually.

- **Workflow:** `.github/workflows/aviation-data.yml` in **ReadBack**
- **Schedule:** Runs every **Monday at 09:00 UTC** (and you can run it anytime: **Actions → Aviation data → Run workflow**)
- **What it does:** Runs `build_all_and_update_manifest.sh` (waypoints, airports, Victor airways, manifest cycle from FAA), then commits and pushes the four files to **ReadbackCorrect** → `aviation_data/`.

**One-time setup:** Add a secret to the **ReadBack** repo so the workflow can push to ReadbackCorrect:

1. Create a **Personal Access Token (PAT)** on GitHub with `repo` scope (or fine-grained with push access to **ReadbackCorrect**).
2. In **ReadBack** repo: **Settings → Secrets and variables → Actions**.
3. Click **New repository secret**. Name: **`READBACK_CORRECT_PAT`**. Value: the PAT.
4. Save. The next time the workflow runs (or when you trigger it), it will push updated `aviation_data/` to ReadbackCorrect.

If the secret is not set, the workflow still runs the build but skips the push and prints a reminder to add `READBACK_CORRECT_PAT`.

**If you get 403 when pushing:** Use the “single-repo” setup instead so no PAT is needed:

1. In your **ReadbackCorrect** repo, add a **`scripts/`** folder and copy in the build scripts from this project: `build_all_and_update_manifest.sh`, `build_waypoints.py`, `build_airports.py`, `build_victor_airways.py`, `check_faa_cycle.py`.
2. In **ReadbackCorrect**, add **`.github/workflows/aviation-data.yml`** — use the contents of **`aviation-data-READBACKCORRECT.yml`** from the ReadBack repo (that version runs inside ReadbackCorrect and pushes with the built-in token; no PAT).
3. Commit and push. The workflow will run in ReadbackCorrect, build the data, and push `aviation_data/` in the same repo. You can leave or remove the workflow in ReadBack.

---

## Option B: GitHub Pages (optional)

**Best for:** A “real” static web server with cache headers. You can serve from the same repo.

1. In **ReadbackCorrect** go to **Settings → Pages**, set source to **Deploy from a branch**.
2. Branch: **main**, folder **/ (root)** or **/docs** (if you put files there).
3. Put the four files in **`aviation_data/`** (or the folder you choose). After deploy, the base URL would be e.g.  
   `https://nolmscheid.github.io/ReadbackCorrect/aviation_data`
4. If you switch to Pages, update **`defaultDataServerBaseURL`** in **AviationDataManager.swift** to that URL. For most users, **GitHub Raw** (Option A) is enough.

---

## Checklist

- [ ] In **ReadbackCorrect**, create folder **`aviation_data`**.
- [ ] Add **`aviation_manifest.json`** (correct `cycle` and `files` paths) inside `aviation_data/`.
- [ ] Add **`airports.json`**, **`victor_airways.json`**, **`waypoints.json`** inside `aviation_data/`.
- [ ] Commit and push. The app already uses `https://raw.githubusercontent.com/nolmscheid/ReadbackCorrect/main/aviation_data`.
- [ ] In the app: leave **Data server URL** in Settings blank, tap **Check for updates**, then **Download**, and confirm data loads.
- [ ] **(Optional)** For automatic updates: in **ReadBack** repo add secret **`READBACK_CORRECT_PAT`** (PAT with push to ReadbackCorrect). See §5 above.

---

## Troubleshooting

- **“Could not reach data server”**  
  - Confirm the repo is **public**.  
  - In a browser, open:  
    `https://raw.githubusercontent.com/nolmscheid/ReadbackCorrect/main/aviation_data/aviation_manifest.json`  
    You should see JSON. If you get 404, the `aviation_data` folder or manifest file is missing.

- **“Could not fetch manifest”**  
  - The base URL must point to the folder that *contains* `aviation_manifest.json`. For this repo it’s `.../ReadbackCorrect/main/aviation_data` (no trailing slash in the app; the code adds `/aviation_manifest.json`).

- **Some files fail to download**  
  - In the manifest, `files` should be `"airports": "airports.json"`, etc. (filenames only). The app appends them to the base URL, so they must live in `aviation_data/` next to the manifest.

Once this is done, users never need to see or type a URL; they just use **Check for updates** and **Download** in Settings.
