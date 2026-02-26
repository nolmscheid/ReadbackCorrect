# Airport Diagram + GPS + Taxi Route Feature

## Goal

1. **GPS** – Use the phone’s location to show position on the airport.
2. **Load/download airport diagram** – Per-airport diagram (e.g. FAA plate) that can be loaded or downloaded.
3. **Position on map** – Show current position on the diagram (like ForeFlight).
4. **Taxi instructions → route on map** – When a card has taxi instructions, tap an icon to open the diagram and (eventually) show the route.

## Is it achievable?

**Yes.** This is the same idea as ForeFlight’s “you are here” on plates: a **georeferenced** diagram (image or PDF with known lat/lon bounds) plus **Core Location** (GPS), then **lat/lon → pixel** so you can draw a dot. Taxi “route” on the diagram is harder: it needs **taxiway centerline geometry** (lat/lon per segment) per airport to draw a path; without that we can still show “you are here” and the instruction text.

## How it works (high level)

1. **Georeferencing** – Each diagram has a **bounding box** in WGS84: `(minLat, maxLat, minLon, maxLon)`. The diagram image is drawn in a view; any `(lat, lon)` is mapped to view coordinates with a linear (or affine) transform. North-up:  
   `x = (lon - minLon) / (maxLon - minLon) * width`  
   `y = (1 - (lat - minLat) / (maxLat - minLat)) * height`

2. **GPS** – `CLLocationManager` (when-in-use) gives `CLLocation.coordinate`. That’s your blue dot. **Testing:** use a **mock position** (e.g. Settings: “Use test position for KMIC” with fixed lat/lon) so you can test off-airport.

3. **Diagram source** – Options:
   - **Bundle:** ship a PNG/PDF per airport (e.g. KMIC) with a small JSON that stores the airport id and bounds.
   - **Download:** same JSON + URL to diagram image/PDF; app caches it. FAA d-TPP has airport diagrams; some are georeferenced in the PDF, many are not (tools like [GeoReferencePlates](https://github.com/jlmcgraw/GeoReferencePlates) add georeferencing for diagrams).

4. **Taxi card → diagram** – On a card that contains taxi intent (e.g. “Taxi to runway 32 via A, B”), add a **“Show on diagram”** (or map) icon. Tap → open the **Airport Diagram** screen for that airport with:
   - Diagram + current (or test) position.
   - Optional: taxi instruction text in a callout.
   - **Route line:** only if we have taxiway geometry (e.g. “A”, “B” as polylines). That data exists in FAA/third-party sources but is a separate data pipeline; v1 can ship without it and still be useful (position + instructions on the diagram).

## Data needed per airport

- **Diagram:** one image (PNG) or PDF. For KMIC you have `mic_airport_diagram.pdf`; we can use it in PDFKit or export one page to PNG and use that for the overlay math.
- **Bounds:** geographic rectangle that the diagram covers. For KMIC (Crystal Airport), reference point is about **45.062°N, 93.353°W**. A small diagram might span roughly:
  - Lat: 45.058 – 45.066  
  - Lon: -93.358 – -93.348  
  (Exact values can be tuned by comparing diagram to a known point.)

## Testing when not at the airport

- **Settings / Debug:** “Use test position”:
  - Toggle: “Use test position for diagram”
  - Optional: airport selector (e.g. KMIC) and lat/lon fields (e.g. 45.061, -93.352 for a ramp spot at KMIC).
- When enabled, the diagram view uses this **mock coordinate** instead of real GPS so you can test on a desk.

## Implementation phases

| Phase | What |
|-------|------|
| **1** | Core Location (GPS) + “Use test position” toggle + stored test lat/lon (e.g. for KMIC). |
| **2** | One airport diagram (KMIC): load from bundle (PNG or PDF), define bounds in code/config, full-screen view that draws diagram + position dot (GPS or test). |
| **3** | “Show on diagram” on **taxi** cards: from card, open diagram view (airport from card or user-selected); show position + optional taxi instruction text. |
| **4** | (Later) Download/cache diagrams by airport id; list of airports with diagrams. |
| **5** | (Later) Taxiway geometry and draw route on diagram when we have “via A, B” and data for A/B. |

## KMIC reference (Crystal Airport)

- **FAA id:** KMIC (MIC).
- **Approx. reference point:** 45.062°N, 93.353°W (from FAA / AirNav).
- **Diagram:** Add `mic_airport_diagram.pdf` (or an exported PNG) to the app bundle or a downloadable assets bundle; we’ll reference it by airport id (e.g. `KMIC` or `MIC`).

## Info.plist

Add a **Location When In Use Usage Description** (key `NSLocationWhenInUseUsageDescription`) so iOS can prompt for GPS permission, e.g.:  
*"ReadBack uses your location to show your position on the airport diagram."*

## Files to add (suggested)

- `LocationManager.swift` – CLLocationManager wrapper, publishes current location; respects “use test position” and test coordinate.
- `AirportDiagramModel.swift` – Struct for airport id, diagram asset name/URL, bounds (minLat, maxLat, minLon, maxLon).
- `AirportDiagramView.swift` – SwiftUI view: load diagram (image or PDF page), compute transform from lat/lon to view coords, draw diagram + user position dot (+ optional route later).
- **Settings:** “Use test position for diagram” toggle; optional test lat/lon (and airport) for KMIC.
- **TransmissionCard:** For rows that represent taxi intents, add a button that presents `AirportDiagramView` for the chosen airport (from card or default).

Once the diagram asset (PDF or PNG) and bounds are in place, Phase 1–3 are straightforward; route drawing (Phase 5) depends on sourcing taxiway geometry.

---

## Drawing the route: next step

### Do we need to “parse” every diagram?

**No.** You don’t need to parse the PDF or image (OCR, vector extraction, etc.) to draw the route. That would be fragile and diagram-dependent.

**Yes, you need structured data per airport** – but that data is **taxiway geometry**, not the diagram itself:

- For each airport you want route drawing, you need a **dataset** that says: *“Taxiway A is this polyline”*, *“Taxiway B is this polyline”*, etc. (each polyline = list of lat/lon points, or x/y in diagram space).
- The **diagram** stays as today: one image/PDF + bounds. It’s only the background.
- The **route** is drawn by: (1) taking the parsed instruction (“via A, B, C”), (2) looking up the polylines for A, B, C in that airport’s dataset, (3) drawing those segments in order on top of the diagram (using the same lat/lon → view coords math as the position dot).

So: **one diagram per airport** (what you have now) is enough. **Route drawing** needs **one geometry file per airport** (taxiway centerlines), which is separate from the diagram.

### Where does taxiway geometry come from?

| Source | Pros | Cons |
|--------|------|------|
| **FAA Airport Mapping (AM) / NASR** | Authoritative, many airports | Need to parse FAA format (e.g. AM_Taxiway, centerline coordinates); pipeline work |
| **Hand-built for one airport (e.g. KMIC)** | Full control, proves the feature | Doesn’t scale to hundreds of airports |
| **Community or third-party GeoJSON/JSON** | Can scale if someone publishes it | Licensing and maintenance |

### Practical next step (e.g. for KMIC)

1. **Define a simple format** for one airport, e.g. `kmic_taxiways.json`:
   - List of taxiway **segments**: each has an `id` (e.g. `"A"`, `"B"`) and a list of `[lat, lon]` (or `[x, y]` in diagram space) for the centerline.
2. **Build KMIC by hand** (or from a single FAA/AM export if available): trace taxiways A, B, G, D, etc. into a JSON. You can derive points by tapping on the diagram (reuse the same “tap → lat/lon” logic) and saving segments.
3. **In the app:** when opening the diagram with a taxi instruction “via A, B”:
   - Load `kmic_taxiways.json` (or the active airport’s file).
   - Find segments for A and B; optionally connect start position → first segment and last segment → runway.
   - Draw the route as a path (e.g. SwiftUI `Path` or a line overlay) using the same `pointInView` transform so it aligns with the diagram.

So the **next step** is: add a **taxiway geometry file** (and loader) for **one** airport (e.g. KMIC), then in `AirportDiagramView` draw the route when we have both (a) a taxi instruction with “via X, Y, …” and (b) geometry for that airport. No need to “parse” every diagram; only add geometry data for airports where you want route drawing.

---

## How to build the taxiway JSON (#2)

You need a file like `kmic_taxiways.json` with one polyline per taxiway. Two practical ways:

### Option A: Trace in the app (recommended)

Use the **same diagram and same tap→lat/lon math** so coordinates line up perfectly.

1. **Add a “Trace taxiway” mode** in the diagram view (e.g. a toolbar button or a Settings toggle “Taxiway editor”).
2. **Record a segment:** Tap “Start segment”, then tap several points along the **centerline** of taxiway A (e.g. 5–15 points). Tap “End segment” and enter the id (e.g. `A`). The app converts each tap to (lat, lon) and stores them.
3. **Repeat** for B, G, D, G1, G2, etc. (every taxiway you want to support).
4. **Export:** The app writes `kmic_taxiways.json` (e.g. to app support or clipboard) in the format below. You copy it into the project or add it to the bundle.

No need to look up coordinates elsewhere; you’re tracing on the real diagram.

### Option B: Get coordinates outside the app

1. **Reuse “tap to set start”:** Open the diagram, tap a point on taxiway A, then check **Settings → test position** (Lat/Lon). Write down that lat/lon. Move mentally to the next point, tap again, write down again. Build the list for A, then B, etc. (Tedious but works.)
2. **Or use a web map:** With the same bounds (e.g. 45.058–45.066, -93.358 to -93.348), use a lat/lon picker or small web page that shows the diagram image and outputs (lat, lon) on click. Then type the JSON by hand or from a spreadsheet.

### JSON format (same for either option)

```json
[
  { "id": "A", "points": [[45.0621, -93.3530], [45.0625, -93.3525], ...] },
  { "id": "B", "points": [[45.0618, -93.3540], ...] }
]
```

- **id:** Taxiway designator (string): `"A"`, `"B"`, `"G"`, `"D"`, `"G1"`, etc.
- **points:** Array of `[latitude, longitude]` (WGS84, same as diagram bounds). Order = start of taxiway → end. 5–20 points per segment is usually enough; more for curves.

File name by airport: `{airportId}_taxiways.json` (e.g. `KMIC_taxiways.json`) in the bundle or app support.
