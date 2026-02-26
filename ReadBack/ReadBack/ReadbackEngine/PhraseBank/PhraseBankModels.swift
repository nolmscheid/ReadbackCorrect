// ReadbackEngine/PhraseBank/PhraseBankModels.swift
// Structured phrase corpus for regression tests and optional dev UI.
// Supports multiple expected intents per phrase (runwayOp, taxiToRunway, crossRunway, continueTaxi, etc.).

import Foundation

/// GPS override for a phrase case (SIM MIC, SIM ANE, or "at home").
public struct PhraseGPS: Codable, Equatable {
    public let lat: Double
    public let lon: Double
    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// One expected intent in a phrase case (kind + optional operation, runway(s), validated, extra).
public struct ExpectedIntent: Codable, Equatable {
    /// Intent kind: "runwayOp", "taxiToRunway", "crossRunway", "continueTaxi", "frequencyChange", etc.
    public let kind: String
    /// For runwayOp: "holdShort", "clearedTakeoff", "clearedLand", "lineUpAndWait"
    public let operation: String?
    /// Single runway (e.g. "14", "29L", "06L")
    public let runway: String?
    /// For crossRunway: multiple runways to cross
    public let runways: [String]?
    /// When non-nil, assert produced intent's validated matches this.
    public let validated: Bool?
    /// Per-runway validation for crossRunway: key = runway (e.g. "24L"), value = true/false/nil. When present, assert each.
    public let validatedMap: [String: Bool?]?
    /// Future fields (e.g. taxiway="D")
    public let extra: [String: String]?

    public init(kind: String, operation: String? = nil, runway: String? = nil, runways: [String]? = nil, validated: Bool? = nil, validatedMap: [String: Bool?]? = nil, extra: [String: String]? = nil) {
        self.kind = kind
        self.operation = operation
        self.runway = runway
        self.runways = runways
        self.validated = validated
        self.validatedMap = validatedMap
        self.extra = extra
    }
}

/// A single phrase case: transcript, optional normalized assertions, and expected intents.
public struct PhraseCase: Codable, Equatable {
    public let id: String
    /// Short label for the case
    public let title: String
    /// Raw text the user might say
    public let transcript: String
    /// Optional substrings that must appear in normalized output (case-insensitive)
    public let expectedNormalizedContains: [String]?
    /// Expected intents (multiple per phrase allowed)
    public let expectedIntents: [ExpectedIntent]
    public let notes: String?
    /// Optional GPS for this case (SIM MIC, SIM ANE, or "at home"). When nil, tests may use a default.
    public let gps: PhraseGPS?

    public init(id: String, title: String, transcript: String, expectedNormalizedContains: [String]? = nil, expectedIntents: [ExpectedIntent], notes: String? = nil, gps: PhraseGPS? = nil) {
        self.id = id
        self.title = title
        self.transcript = transcript
        self.expectedNormalizedContains = expectedNormalizedContains
        self.expectedIntents = expectedIntents
        self.notes = notes
        self.gps = gps
    }
}
