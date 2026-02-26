# IFR Clearances & Flight Following — Prep for ReadBack Cards

This document prepares **parsing and card design** for IFR clearances and VFR flight following. It does not implement code; it gives a single reference for a future “IFR night” so we can build accurate cards.

---

## 1. IFR Clearance Structure (CRAFT)

Pilots use **CRAFT** to write down clearances. ATC issues items in a consistent order (FAA 7110.65). ReadBack should parse and display in the same order.

| Letter | Item | ATC phraseology (typical) | What to extract |
|--------|------|---------------------------|-----------------|
| **C** | **Clearance limit** | “Cleared to [airport/fix]”, “Cleared to the Palomar Airport” | Destination or limit: airport name, or fix/waypoint |
| **R** | **Route** | “Via [SID], [transition]”, “Fly heading 175”, “Vectors V23, OCN, direct” | Route description: headings, airways, fixes, “direct” |
| **A** | **Altitude** | “Maintain 5000”, “Expect 7000 five minutes after departure” | Initial altitude (ft); optional “expect” altitude + time |
| **F** | **Frequency** | “Departure frequency 121.30”, “Contact departure 124.8” | Departure (or next) frequency |
| **T** | **Transponder** | “Squawk 1312” | Squawk code (already supported) |

**Void time** (clearance void if not off by …) is often given at the end, e.g. “Clearance void if not off by 1430 Zulu.”

---

## 1b. Sample CRAFT Clearance (for testing)

Use this as a single phrase to speak when testing IFR clearance parsing (or paste into a test scenario). One natural ATC-style transmission:

**Sample 1 (with SID and expect altitude):**  
*“N641CC, cleared to the Denver Airport via the Platteville Two departure, then as filed. Maintain 8000, expect flight level 350 10 minutes after departure. Departure frequency 124.7, squawk 4721.”*

**Sample 2 (vectors, no SID):**  
*“N641CC, cleared to the Palomar Airport via fly heading 175, vectors V23, OCN, direct. Maintain 5000, expect 7000 5 minutes after departure. Departure frequency 121.30, squawk 1312.”*

**Sample 3 (with void time):**  
*“N641CC, cleared to the Riverside Airport via present position direct. Maintain 3000. Departure frequency 132.45, squawk 4521. Clearance void if not off by 1430 Zulu.”*

Map to CRAFT:
- **C** — Denver Airport / Palomar Airport / Riverside Airport  
- **R** — Platteville Two then as filed / Fly heading 175, vectors V23, OCN direct / Present position direct  
- **A** — 8000, expect FL350 10 min / 5000, expect 7000 5 min / 3000  
- **F** — 124.7 / 121.30 / 132.45  
- **T** — 4721 / 1312 / 4521  
- **Void** — (none) / (none) / 1430 Zulu  

---

## 2. IFR Phrases to Normalize (AviationNormalizer)

Add or extend so ASR and fast speech still match:

- **Clearance limit:** “cleared to [X] airport”, “cleared to [X]”, “cleared to the [X] airport”
- **Route:** “via [SID name]”, “fly heading …”, “vectors …”, “direct [fix]”, “after departure fly heading …”
- **Altitude:** “maintain [alt]”, “expect [alt] [time] after departure”, “expect [alt] 5 minutes after departure”
- **Frequency:** “departure frequency …” (already added); “contact departure …” (existing)
- **Void time:** “void if not off by [time]”, “clearance void [time]”

Spoken numbers and “niner”, “fife”, “tree”, “thousand”, “flight level” are already normalized; reuse for altitudes and headings in IFR.

---

## 3. Suggested IFR Intent / Card Rows

Keep **existing intents** (contact, squawk, climb/descend/maintain, heading). Add or specialize for IFR:

| Intent | Example phrase | Extract | Card row (concept) |
|--------|----------------|--------|---------------------|
| **Clearance limit** | “Cleared to the Palomar Airport” | Limit: airport/fix name (string) | CLEARED TO [Palomar Airport] |
| **Route** | “Via fly heading 175, vectors V23, OCN direct” | Route text or structured (heading, airway, fixes) | ROUTE … (or HEADING 175 → V23 → OCN → DIRECT) |
| **Initial altitude** | “Maintain 5000” | Already have `maintain(altitude)` | MAINTAIN 5000 (existing) |
| **Expect altitude** | “Expect 7000 five minutes after departure” | Altitude (Int), optional “X minutes after departure” | EXPECT 7000 (5 MIN AFTER DEP) |
| **Departure frequency** | “Departure frequency 121.30” | Already have contact/frequency row | CONTACT DEPARTURE 121.30 (existing) |
| **Squawk** | “Squawk 1312” | Already have `squawk(code)` | SQUAWK 1312 (existing) |
| **Void time** | “Clearance void if not off by 1430” | Time string or Date? | VOID 1430 (or VOID IF NOT OFF BY 1430) |

**Multi-intent rule:** One transmission can contain the whole clearance; parser should return multiple intents **in spoken order** (clearance limit → route → altitude → frequency → squawk → void time) and UI should render rows in that order.

---

## 3b. CRAFT Card Design (notepad-style, easy to read)

Use a **notepad-style layout** so the card looks like a CRAFT notepad: one big letter per section, with content under each. Makes it easy to scan and copy.

**Layout concept:**

- **One card** when the transmission is detected as an IFR clearance (e.g. starts with “cleared to …” and has at least route or altitude or frequency/squawk).
- **Five sections in order:** C → R → A → F → T. Optional sixth: **V** (void time) if present.
- **Big section letters:** Large, bold **C** **R** **A** **F** **T** (and **V**) as left-side headers, like printed notepad columns. Same style pilots write in: letter in a circle or a heavy box, then the line for that item.
- **Content right of each letter:** Only the extracted value(s) for that item (no repeated “clearance limit” etc.). Empty sections can show a dash or stay blank.

**Visual sketch (target):**

```
┌─────────────────────────────────────────────────────────┐
│  C    Denver Airport                                     │
│  R    Platteville Two departure, then as filed           │
│  A    8000  •  Expect FL350 10 min after dep             │
│  F    124.7                                              │
│  T    4721                                               │
│  V    —  (or "1430 Z" if void time present)              │
└─────────────────────────────────────────────────────────┘
```

**Implementation notes:**

- **C** — Single line: clearance limit (airport or fix name). Monospaced or bold for the limit.
- **R** — One or two lines if needed: route (headings, SID, airways, “direct”). Can wrap; keep “fly heading NNN” and “direct” prominent.
- **A** — Main altitude + optional “Expect FLXXX / NNNN (time) after departure” on same or next line. Reuse existing altitude badge style (e.g. blue) for numbers.
- **F** — Frequency only (e.g. 124.7). Reuse contact/frequency styling (blue, monospaced).
- **T** — Squawk code only. Reuse existing squawk badge (orange).
- **V** — Void time string (e.g. “1430 Z”) or “—” when not given. Smaller or muted so it doesn’t dominate.

**Letter styling:** Large, bold, possibly in a circle or rounded rectangle (e.g. 28–32 pt, semibold). Slightly muted background (e.g. light gray) behind each letter column to reinforce “notepad column.” Keep runway/contact/squawk badge colors (red for runways, etc.) when those appear inside a section; the C R A F T letters themselves can be a single dark color (e.g. dark gray or navy) for clarity.

This design makes C R A F T the primary scan line; content is secondary under each letter, matching how pilots use CRAFT notepads.

---

## 4. Flight Following (VFR Advisories)

Flight following is **VFR**; ATC does not issue a full IFR clearance. Phrases to recognize for **cards**:

| Phrase / concept | What to extract | Card row (concept) |
|------------------|-----------------|---------------------|
| “Squawk 0322” (or any 4-digit) | Squawk code | SQUAWK 0322 (existing) |
| “Radar contact” | Confirmation only | RADAR CONTACT (informational row) |
| “Maintain VFR”, “Remain VFR” | No numeric; confirmation | REMAIN VFR or MAINTAIN VFR |
| “VFR advisories” (pilot request) | Optional: show “Requested VFR advisories” | REQUEST VFR ADVISORIES (optional) |

**Normalizer:** “remain vfr” / “maintain vfr” (already have “maintain vfr” in normalizer); “radar contact” as fixed phrase.

---

## 5. Parsing Hints (for Implementation)

- **Clearance limit:** Regex for “cleared to (the) … (airport)?”, stop at “via” or “maintain” or “squawk” so we don’t capture the whole sentence as the limit.
- **Route:** Can be free text between “via” and “maintain” (or “expect” or “departure frequency”); or split into “fly heading NNN”, “vectors …”, “direct [fix]”.
- **Expect altitude:** “expect [alt]” and optional “(N) minutes after departure” or “(in) (N) minutes”.
- **Void time:** “void if not off by (time)” or “clearance void (time)”; time can be “1430”, “14:30”, “1430 zulu”.
- **Radar contact:** Exact phrase “radar contact”; no parameters, one informational row.

---

## 6. References

- **FAA Order 7110.65** — ATC phraseology and clearance order.
- **CRAFT** — Clearance limit, Route, Altitude, Frequency, Transponder (and void Time).
- **AIM 4-2** — Radio communications phraseology.
- Existing **ATCSpec.md** — Intent list, badge system, multi-intent order, no parsing in UI.

---

## 7. When You Implement

1. **AviationNormalizer:** Add IFR/flight-following phrase variants (Section 2 and “remain vfr”, “radar contact”).
2. **Intent model (ATCIntent):** Add cases for clearance limit, route (or sub-types), expect altitude, void time, “radar contact”, “remain VFR” as needed.
3. **TransmissionCard:** New row builders for CLEARED TO, ROUTE, EXPECT, VOID TIME, RADAR CONTACT, REMAIN VFR; keep runway badges and existing contact/squawk/altitude/heading rows.
4. **Order:** Preserve spoken order in both parser and UI so a full IFR clearance renders C → R → A → F → T (and void if present).

This file is the single place to look when building IFR and flight-following cards.
