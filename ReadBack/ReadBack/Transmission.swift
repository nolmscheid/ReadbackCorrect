import Foundation

/// Detects when the phrase is likely the pilot calling ATC (e.g. "Crystal Tower Cherokee 641CC, requesting taxi").
/// Such phrases start with a facility name (Tower, Ground, Approach, etc.) then the callsign; we suppress them from cards.
enum PilotInitiatorDetector {
    /// Facility keywords that start a pilot call. Must appear at start of phrase (first word or second word after airport name).
    /// Excludes "DEPARTURE" so ATC "N12345, departure frequency 124.7" is not suppressed.
    private static let facilityStartPattern = #"^\s*(?:\w+\s+)?(TOWER|GROUND|APPROACH|CENTER|DELIVERY|CLEARANCE|RADIO|ATIS)\b"#

    /// True if normalized text looks like the pilot initiating (facility first, then callsign). Call only when callsign filter already passed.
    static func isLikelyPilotInitiator(normalizedText: String, callsign: String) -> Bool {
        let t = normalizedText.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 5 else { return false }
        let compressed = CallsignFormatter.compressSpokenCallsigns(in: t)
        guard CallsignFormatter.matchesTransmission(compressed, desiredUserInput: callsign) else { return false }
        guard let regex = try? NSRegularExpression(pattern: facilityStartPattern) else { return false }
        let range = NSRange(t.startIndex..., in: t)
        return regex.firstMatch(in: t, range: range) != nil
    }
}

/// Determines which tab shows this transmission: ATC (hold short, taxi, cleared to land, etc.) or IFR (clearances, readbacks).
enum TransmissionKind: Equatable {
    case atc   // Controller instructions: hold short, taxi, cleared to land, etc.
    case ifr   // IFR clearance or pilot readback (CRAFT); show only on IFR tab.

    /// Classify normalized (uppercase) transmission text: IFR if it looks like a clearance/readback ("cleared to X" but not "cleared to land").
    static func classify(normalizedText: String) -> TransmissionKind {
        let t = normalizedText.uppercased()
        let isLandClearance = t.contains("CLEARED TO LAND") || t.contains("CLEAR TO LAND")
        guard t.contains("CLEARED TO"), !isLandClearance else { return .atc }
        // Clearance limit phrase present; treat as IFR (controller clearance or pilot readback).
        return .ifr
    }
}

struct Transmission: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let kind: TransmissionKind
    let createdAt = Date()
    /// Runway designator from engine intent (e.g. "99", "09", "32"); used for badge instead of re-parsing transcript.
    let runwayFromIntent: String?
    /// True = matched NASR, false = impossible, nil = unknown. Used for badge validity styling.
    let runwayValidated: Bool?
    /// Per-runway validation for CROSS runway intents: key = normalized runway (e.g. "24L"), value = true/false/nil.
    let crossRunwayValidated: [String: Bool?]
    /// VIA taxiway(s) from intent (e.g. ["D", "C"]) so card shows "VIA D" even when SR said "of the delta".
    let viaTaxiways: [String]
    /// "Taxi to runway X" — runway from first taxiToRunway intent.
    let taxiToRunway: String?
    /// Validation for taxiToRunway: true/false/nil (same semantics as runwayValidated).
    let taxiToRunwayValidated: Bool?

    init(text: String, kind: TransmissionKind = .atc, runwayFromIntent: String? = nil, runwayValidated: Bool? = nil, crossRunwayValidated: [String: Bool?] = [:], viaTaxiways: [String] = [], taxiToRunway: String? = nil, taxiToRunwayValidated: Bool? = nil) {
        self.text = text
        self.kind = kind
        self.runwayFromIntent = runwayFromIntent
        self.runwayValidated = runwayValidated
        self.crossRunwayValidated = crossRunwayValidated
        self.viaTaxiways = viaTaxiways
        self.taxiToRunway = taxiToRunway
        self.taxiToRunwayValidated = taxiToRunwayValidated
    }
}
