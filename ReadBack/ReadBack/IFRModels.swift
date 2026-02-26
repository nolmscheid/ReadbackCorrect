import Foundation

// MARK: - Slot container

/// Generic slot for a single extracted IFR field. Holds value, confidence, validation state, and source text.
struct Slot<T> {
    var value: T?
    var confidence: Double
    var validated: Bool
    var sourceText: String

    init(value: T? = nil, confidence: Double = 0.5, validated: Bool = false, sourceText: String = "") {
        self.value = value
        self.confidence = confidence
        self.validated = validated
        self.sourceText = sourceText
    }
}

// MARK: - Parsing context

/// Context passed into IFR parse. Tokenize once at start of parse; extraction methods use this.
struct ParsingContext {
    let normalizedText: String
    let tokens: [String]
    let foldedTokens: [String]
    let foldedText: String

    init(normalizedText: String) {
        self.normalizedText = normalizedText
        self.tokens = normalizedText.split(separator: " ").map { String($0) }
        self.foldedTokens = SpokenNumberFolder.foldTokens(self.tokens)
        self.foldedText = self.foldedTokens.joined(separator: " ")
    }
}

// MARK: - Aviation data provider (stub)

/// Provider for clearance-limit / airport lookup. Stub for now; allows validation to check "clearance limit exists".
protocol AviationDataProvider: AnyObject {
    func hasClearanceLimit(_ name: String) -> Bool
}

// MARK: - Route data

/// Structured route data for IFR clearance.
struct RouteData {
    /// Route fixes/waypoints (e.g. segment identifiers). May be empty if not parsed.
    let fixes: [String]
    /// Raw route text as extracted (display text can be derived via formatRouteForDisplay(rawText) if needed).
    let rawText: String

    init(fixes: [String], rawText: String) {
        self.fixes = fixes
        self.rawText = rawText
    }
}

// MARK: - Altitude data

/// Structured altitude data for IFR clearance.
struct AltitudeData {
    /// Initial altitude in feet, or nil if not parsed.
    let initialFeet: Int?
    /// Expect altitude in feet, or nil if not present.
    let expectFeet: Int?
    /// Raw altitude line as built (display text can be derived from this if needed).
    let rawText: String

    init(initialFeet: Int?, expectFeet: Int?, rawText: String) {
        self.initialFeet = initialFeet
        self.expectFeet = expectFeet
        self.rawText = rawText
    }
}

// MARK: - IFR clearance

/// Unified IFR clearance model using slot containers. All extraction is slot-based; validation and confidence applied by IFRValidator.
struct IFRClearance {
    var callsign: Slot<String>
    var clearanceLimit: Slot<String>
    var route: Slot<RouteData>
    var altitude: Slot<AltitudeData>
    var frequency: Slot<String>
    var squawk: Slot<String>
    var void: Slot<String>
    var specialInstructions: Slot<String>

    /// Weighted average of slot confidences (computed by IFRValidator). Clamped 0...1.
    var overallConfidence: Double

    init(
        callsign: Slot<String> = Slot(),
        clearanceLimit: Slot<String> = Slot(),
        route: Slot<RouteData> = Slot(),
        altitude: Slot<AltitudeData> = Slot(),
        frequency: Slot<String> = Slot(),
        squawk: Slot<String> = Slot(),
        void: Slot<String> = Slot(),
        specialInstructions: Slot<String> = Slot(),
        overallConfidence: Double = 0.5
    ) {
        self.callsign = callsign
        self.clearanceLimit = clearanceLimit
        self.route = route
        self.altitude = altitude
        self.frequency = frequency
        self.squawk = squawk
        self.void = void
        self.specialInstructions = specialInstructions
        self.overallConfidence = overallConfidence
    }

    /// True if at least one CRAFT slot has a value (same semantics as craftHasContent).
    var hasContent: Bool {
        clearanceLimit.value != nil || route.value != nil || altitude.value != nil ||
        frequency.value != nil || squawk.value != nil || void.value != nil
    }
}
