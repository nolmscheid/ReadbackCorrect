# ReadbackEngine

On-device **Readback Engine** that converts Apple Speech transcripts into aviation-correct structured data using the NASR v2 dataset (`aviation_data_v2/*.json`).

## Requirements

- **On-device only** — no network during recognition.
- **NASR v2 JSON** — the GitHub Action builds these into `aviation_data_v2/`; the app ships with a baseline copy and can refresh via download.
- **Deterministic** — same transcript + GPS yields the same result.

## Usage

### 1. Load the store

Load from a directory that contains the v2 JSON files (e.g. app bundle or Application Support after download):

```swift
let store = NASRStore()
try store.load(from: aviationDataV2DirectoryURL)
```

### 2. Create the engine and process

```swift
let engine = ReadbackEngine(store: store)
let gps = GPSContext(lat: 44.88, lon: -93.22, altitudeFt: 3500, trackDeg: 270)
let result = engine.process(transcript: "contact approach on one two eight point seven", gps: gps, asrConfidence: nil)
```

### 3. Use the result

- **`result.normalizedText`** — normalized string (numbers folded, phonetics → letters, runway phrases).
- **`result.snaps`** — `[SnapEvent]`: original substring, replacement (e.g. fix/airport id), type, confidence, start/end.
- **`result.intents`** — `[ParsedIntent]`: `.frequencyChange`, `.altitude`, `.ifrClearance` with associated data.
- **`result.overallConfidence`** — 0...1.
- **`result.fieldConfidences`** — per-field confidence for UI.
- **`result.uncertainSpans`** — `[TextSpan]` for highlighting uncertain regions.

## API summary

- **`ReadbackEngine(store: NASRStore)`**
- **`process(transcript: String, gps: GPSContext, asrConfidence: Double? = nil) -> ReadbackResult`**
- **`GPSContext`**: `lat`, `lon`, `altitudeFt?`, `trackDeg?`, `groundSpeedKt?`, `timestamp?`
- **`ReadbackResult`**: `normalizedText`, `snaps`, `intents`, `overallConfidence`, `fieldConfidences`, `uncertainSpans`

## Adding fixtures (golden tests)

1. Add a new JSON file under **`ReadbackEngineTests/fixtures/`**.
2. Required fields:
   - **`transcript`** — raw transcript string.
   - **`gps`** — `{ "lat": number, "lon": number }` (e.g. Minneapolis: 44.88, -93.22).
3. Optional:
   - **`expectedNormalizedContains`** — array of strings that must appear in `normalizedText`.
   - **`expectedIntents`** — array of `{ "kind": "frequencyChange"|"altitude"|"ifrClearance", ... }` with optional `frequencyMHz`, `verb`, `altitudeFt`, `clearanceLimit`, `squawk`.
   - **`minOverallConfidence`** — minimum required confidence (0...1).

Example:

```json
{
  "transcript": "climb and maintain one zero thousand",
  "gps": { "lat": 44.88, "lon": -93.22 },
  "expectedNormalizedContains": ["10000"],
  "expectedIntents": [
    { "kind": "altitude", "verb": "climb", "altitudeFt": 10000 }
  ],
  "minOverallConfidence": 0.5
}
```

4. Run the **ReadbackEngineTests** target (or the golden test method). Fixtures are loaded from the test bundle’s `fixtures` resource or from the `ReadbackEngineTests/fixtures` directory next to the test file.

## Debug logging

Set `ReadbackEngineDebugLogging = true` to enable debug output (default: off).
