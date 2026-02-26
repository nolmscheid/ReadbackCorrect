# Readback Correct — Product roadmap

Product goal: help pilots confirm what ATC said and get readbacks right (situational awareness + accuracy). Primary value for newer pilots and longer readbacks (e.g. IFR clearances). Offline-only, iOS first, App Store when ready. Personal aid only (no certification).

---

## 1. Audio input (research note)

**Cable (primary):** NFLIGHTCAM-style cable from panel → 3.5mm stereo → adapter (e.g. Lightning/USB-C) into iPhone/iPad. No 3.5mm on current iPhones, so dongle or USB-C adapter is typical.

**Bluetooth OUT from panel:** Some panels and adapters can stream radio audio *out* to the phone:

- **BendixKing AeroPanel 100** — second Bluetooth module streams pilot audio to devices (e.g. FlightLink app, cameras).
- **PS Engineering PMA8000BT / PMA8000C** — Bluetooth to two devices; music/phone; confirm whether radio monitor is streamed to phone.
- **Jupiter Avionics JA34-BT1** — universal radio adapter, Bluetooth A2DP streaming to phone/camera.

If the user’s panel has Bluetooth, they may be able to use it for app input instead of cable; document model and behavior when known.

---

## 2. Priority order

| Priority | Focus | Status / next |
|----------|--------|----------------|
| **1** | **ATC tab super solid** | In progress: vocabulary, taxi/cross cards, normalizer. |
| **2** | **IFR clearances** | After ATC: clearance model + card for long readbacks. |
| **3** | ATIS | After IFR: recognition + parsing. |
| **4** | Optional Whisper (Settings toggle) | Later: higher accuracy, more battery. |
| **5** | Save/history (cards, ATIS) | If users ask. |

---

## 3. ATC tab — current focus

- **Vocabulary / normalization:** FAA 7110.65-style phraseology + common ASR misrecognitions (e.g. holt→hold, clear/cleared variants). Centralized in `AviationNormalizer`; used before parsing and in delta/callsign logic where applicable.
- **Cards:** Taxi instructions are first-class: destination runway, VIA taxiways, then **cross runway** and **hold short** in *spoken order*, including multiple crosses and hold shorts per transmission. Cross runway gets a clear visual (e.g. red CROSS [nn]).
- **Flow:** Single card layout that “flows”: taxi to/via first, then cross/hold short sequence so complex instructions are easy to scan.
- **Real-world testing:** In-plane testing with cable (and Bluetooth if available); “show all / turn off callsign filter” as fallback when quality is poor.

---

## 4. IFR clearances (next)

- Define a simple clearance model: clearance limit, route, altitude, frequency, squawk, etc.
- One card type (e.g. “IFR clearance”) that shows these fields in order.
- Lives in ATC tab initially; separate tab only if needed.

---

## 5. ATIS

- Manual Listen / Stop is sufficient for now.
- Reuse same aviation vocabulary/normalizer; tune recognizer for fast, dense ATIS if needed.
- Parsing (info, wind, altimeter, etc.) after recognition is acceptable.

---

## 6. Future / optional

- Whisper (or other engine) behind Settings toggle for optional higher accuracy.
- Android if demand justifies it.
- Save button on cards + Saved list for IFR/ATIS if users request it.

---

*Last updated from product and technical alignment; adjust as priorities and testing results come in.*
