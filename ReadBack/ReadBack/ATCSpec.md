📘 ATC_SPEC.md

ReadBack – Phase 1 ATC Coverage Map

⸻

1. Architecture Overview

ReadBack is structured into three layers:

1️⃣ Speech Layer

File: SpeechRecognizer.swift

Responsibilities:
    •    Microphone + Apple Speech
    •    Live transcript
    •    Silence detection
    •    Phrase window commit logic
    •    Duplicate prevention
    •    Producing Transmission objects

❗ This layer must NOT:
    •    Parse aviation meaning
    •    Extract runway/heading/altitude
    •    Render UI
    •    Remove callsign from text

This layer is “sacred” and rarely modified.

⸻

2️⃣ Aviation Logic Layer

Files:
    •    IntentParser.swift
    •    CallsignFormatter.swift
    •    AviationNormalizer.swift
    •    ATCIntent.swift
    •    ParsedTransmission.swift

Responsibilities:
    •    Extract structured ATC intents from raw text
    •    Match and normalize callsigns
    •    Convert spoken numbers to digits
    •    Preserve spoken order of instructions

This layer contains ALL regex and text interpretation.

It returns structured data:

enum ATCIntent {
    case taxi(destinationRunway: String?, via: [String])
    case holdShort(runway: String?)
    case crossRunway(runway: String?)
    case clearedForTakeoff(runway: String?)
    case clearedToLand(runway: String?)
    case lineUpAndWait(runway: String?)
    case climb(altitude: Int)
    case descend(altitude: Int)
    case maintain(altitude: Int)
    case heading(degrees: Int)
    case contact(facility: String?, frequency: String?)
    case squawk(code: String)
    case goAround
}

Parser output:

struct ParsedTransmission {
    let originalText: String
    let cleanedText: String
    let callsignMatched: Bool
    let intents: [ATCIntent]   // In spoken order
}


⸻

3️⃣ UI Layer

Files:
    •    ContentView.swift
    •    TransmissionCard.swift
    •    RunwayActionBadge.swift
    •    RunwayLocationBadge.swift
    •    TaxiwayBadge.swift

Responsibilities:
    •    Render cards
    •    Render badges/icons
    •    Display structured intent rows

UI never contains parsing logic.

⸻

2. Visual Language Rules

Callsign Header

If callsign matched:

✅ N641CC

Remove callsign from body text to reduce duplication.

⸻

Badge System

🔴 RunwayActionBadge

Used for:
    •    HOLD SHORT
    •    CLEARED FOR TAKEOFF
    •    CLEARED TO LAND
    •    CROSS RUNWAY
    •    LINE UP AND WAIT

Style:
    •    Red background
    •    White text
    •    Represents runway clearance/action

⸻

🟡 RunwayLocationBadge

Used when runway is part of taxi/surface navigation.

Style:
    •    Black background
    •    Yellow text
    •    Yellow border

Example:

[ 32 ]


⸻

🟡 TaxiwayBadge

Used for taxiway identifiers.

Style:
    •    Black background
    •    Yellow text
    •    Yellow border

Examples:

[ A ]   [ E ]   [ A3 ]


⸻

3. Phase 1 Intent Coverage

⸻

TAXI

Example

“TAXI TO RUNWAY 32 VIA ALPHA ECHO”

Extract
    •    destination runway: “32”
    •    via: [“A”, “E”]

UI

✈ TAXI TO [32]
VIA [A] [E]

Priority: Control (yellow)

⸻

HOLD SHORT

Example

“HOLD SHORT RUNWAY 32”

Extract
    •    runway: “32”

UI

HOLD SHORT [32]

Priority: Critical (red)

⸻

CROSS RUNWAY

Example

“CROSS RUNWAY 27”

UI

CROSS [27]

Priority: Critical

⸻

CLEARED FOR TAKEOFF

Example

“CLEARED FOR TAKEOFF RUNWAY 32”

UI

CLEARED FOR TAKEOFF [32]

Priority: Critical

⸻

CLEARED TO LAND

Example

“CLEARED TO LAND RUNWAY 32”

UI

CLEARED TO LAND [32]

Priority: Critical

⸻

LINE UP AND WAIT

Example

“LINE UP AND WAIT RUNWAY 32”

UI

LINE UP AND WAIT [32]

Priority: Critical

⸻

CLIMB / DESCEND / MAINTAIN

Examples

“CLIMB AND MAINTAIN 5000”
“DESCEND AND MAINTAIN 3000”
“MAINTAIN 4000”

Extract
    •    altitude: Int

UI

⬆ CLIMB 5000
⬇ DESCEND 3000
⏸ MAINTAIN 4000

Priority: Control (blue)

⸻

HEADING

Example

“FLY HEADING 320”
“TURN LEFT HEADING 180”

Extract
    •    degrees: Int

UI

🧭 HEADING 320

Priority: Control (blue)

⸻

CONTACT

Example

“CONTACT DEPARTURE 124.8”

Extract
    •    facility
    •    frequency

UI

📻 CONTACT DEPARTURE 124.8

Priority: Control

⸻

SQUAWK

Example

“SQUAWK 4621”

UI

🔢 SQUAWK 4621

Priority: Control

⸻

GO AROUND

Example

“GO AROUND”

UI

⚠ GO AROUND

Priority: Critical

⸻

4. Multi-Intent Rule

If a transmission contains multiple instructions:

“CLIMB AND MAINTAIN 3000 HEADING 320”

Parser must return:
    1.    climb(3000)
    2.    heading(320)

UI must render in spoken order.

⸻

5. Phraseology alignment (FAA 7110.65)

Parsing and normalization are designed to match **FAA Order 7110.65** (and ICAO-style) ATC phraseology where possible:

- **Hold short:** Controllers say “hold short” (or “hold short of”) the runway; we parse `HOLD SHORT [RUNWAY] nn[L|R|C]`.
- **Cross runway:** Controllers issue a crossing clearance per runway; we parse `CROSS RUNWAY nn[L|R|C]` and accept “and nnL/nnR” in the same instruction.
- **Runway designators:** “Runway two four left” → 24L, “runway one four” → 14. We normalize spoken “left/right/center” to L/R/C for display.
- **Taxi:** “Taxi to runway nn[,] [via …][,] [cross …][,] hold short …” — we accept common variants and sloppy phrasing; add patterns as real-world examples show.

When adding or changing patterns, prefer 7110.65 wording first, then add variants (e.g. “and” between runways, “left” vs “L”) so we stay aligned with controller training while still catching real radio.

⸻

6. Development Rules

Rule 1

SpeechRecognizer commit logic is not modified during UI or parsing work.

Rule 2

Parser is deterministic and pure.

Rule 3

UI components are dumb visual blocks.

Rule 4

Always commit stable milestones before adding new parsing rules.

⸻

7. IFR and Flight Following (Future)

See **IFR_AND_FLIGHT_FOLLOWING_SPEC.md** for prepared coverage of IFR clearances (CRAFT: clearance limit, route, altitude, frequency, squawk, void time) and VFR flight following (radar contact, remain VFR, squawk). That doc defines suggested intents, phrases to normalize, and card row concepts—no implementation yet.

⸻

8. Phase 1 Completion Definition

Phase 1 is complete when:
    •    All intents above parse reliably
    •    Multi-intent order preserved
    •    Taxi + Hold Short combos render correctly
    •    Callsign filtering stable
    •    No duplicate carryover between transmissions
