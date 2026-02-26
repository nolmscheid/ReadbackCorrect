# Test scenarios — Maintain & MAYDAY

Use these after a build that includes **maintain** graphics and **MAYDAY** alert card + sound. Speak each phrase (with LISTEN on); confirm the card shows the expected row and, for MAYDAY, that the card flashes and the alert sound plays.

---

## 1. Maintain (altitude)

FAA 7110.65: *"Climb and maintain…"*, *"Descend and maintain…"*, *"Maintain (altitude)"*.

| # | Say this | Expect on card |
|---|----------|-----------------|
| 1 | **Climb and maintain five thousand** | One row: **CLIMB 5000** with **up arrow** icon. |
| 2 | **Descend and maintain three thousand** | One row: **DESCEND 3000** with **down arrow** icon. |
| 3 | **Maintain four thousand** | One row: **MAINTAIN 4000** with **level (horizontal line)** icon. |
| 4 | **Maintain niner thousand** | One row: **MAINTAIN 9000** with level icon (not 900). |
| 4b | **Maintain flight level three five zero** | One row: **MAINTAIN FL350** with level icon. |
| 4c | **Climb and maintain flight level 180** | One row: **CLIMB FL180** with up arrow. |

---

## 2. Maintain heading

FAA phraseology: *"Maintain heading (of) 180"*.

| # | Say this | Expect on card |
|---|----------|-----------------|
| 5 | **Maintain heading 180** | One row: **MAINTAIN HEADING 180** with **level + heading (compass)** icon. |
| 6 | **Maintain heading of 270** | One row: **MAINTAIN HEADING 270** with level + heading icon. |
| 7 | **Maintain heading 090** | One row: **MAINTAIN HEADING 090** with level + heading icon. |

Compare with a plain heading (no “maintain”):

| 8 | **Turn left heading 360** | One row: **HEADING 360** with **left turn + heading** icon. |
| 8b | **Turn right heading 090** | One row: **HEADING 090** with **right turn + heading** icon. |
| 8c | **Heading 270** | One row: **HEADING 270** with **heading** icon only. |

---

## 3. MAYDAY (distress)

*Hope it’s never needed; good to verify the alert works. MAYDAY does **not** require a callsign — it could be another aircraft; the app always shows and alerts on MAYDAY even with callsign filter on.*

| # | Say this | Expect |
|---|----------|--------|
| 9 | **Mayday mayday mayday** | Card appears with **red flashing background**; top row: **MAYDAY — DISTRESS** (white text + triangle icon); **alert sound** plays once when card appears. |
| 10 | **May day** (two words) | Same as above (normalizer converts to “mayday”). |
| 11 | **Mayday** (once) | Same as above. |
| 11b | With **callsign filter ON**, say **Mayday mayday** (no callsign) | Card still appears and alert still plays — MAYDAY is never filtered by callsign. |

If the sound is too quiet or you want a real siren: the code uses a system alert (e.g. New Mail); you can swap in a custom .wav/.mp3 via `MaydayAlertPlayer` in `TransmissionCard.swift`.

---

## 4. Combined (optional)

| # | Say this | Expect |
|---|----------|--------|
| 12 | **Climb and maintain five thousand maintain heading 270** | Two rows: **CLIMB 5000** (up arrow), then **MAINTAIN HEADING 270** (level icon). |
| 13 | **N641CC taxi to runway 22 via alpha cross 22L hold short 22R** | Taxi row, then CROSS 22L, then HOLD SHORT 22R (order preserved). |

---

## 5. IFR CRAFT (sample clearances — for when IFR is implemented)

Use these as **one phrase per row** (say the whole line with LISTEN on). See **IFR_AND_FLIGHT_FOLLOWING_SPEC.md** for CRAFT layout and notepad-style card design.

| # | Say this (full clearance) | CRAFT to expect |
|---|---------------------------|-----------------|
| 14 | **N641CC, cleared to the Denver Airport via the Platteville Two departure, then as filed. Maintain 8000, expect flight level 350 10 minutes after departure. Departure frequency 124.7, squawk 4721.** | C: Denver Airport · R: Platteville Two, then as filed · A: 8000, expect FL350 10 min · F: 124.7 · T: 4721 |
| 15 | **N641CC, cleared to the Palomar Airport via fly heading 175, vectors V23, OCN, direct. Maintain 5000, expect 7000 5 minutes after departure. Departure frequency 121.30, squawk 1312.** | C: Palomar Airport · R: Hdg 175, vectors V23, OCN, direct · A: 5000, expect 7000 5 min · F: 121.30 · T: 1312 |
| 16 | **N641CC, cleared to the Riverside Airport via present position direct. Maintain 3000. Departure frequency 132.45, squawk 4521. Clearance void if not off by 1430 Zulu.** | C: Riverside Airport · R: Present position direct · A: 3000 · F: 132.45 · T: 4521 · V: 1430 Z |

*Until IFR parsing and the CRAFT card are built, these will appear as plain transmission cards; use them to confirm speech recognition and callsign match, then re-test once the CRAFT notepad UI is in place.*

---

*After you run a build with these updates, run through the table in order and note any phrases that don’t parse or show the wrong icon/label.*
