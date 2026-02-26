// ReadbackEngine/ReadbackEngine.swift
// Public API: process transcript with GPS context, return normalized text, snaps, intents, confidence.

import CoreLocation
import Foundation

public struct GPSContext: Sendable {
    public let lat: Double
    public let lon: Double
    public let altitudeFt: Double?
    public let trackDeg: Double?
    public let groundSpeedKt: Double?
    public let timestamp: Date?
    public init(lat: Double, lon: Double, altitudeFt: Double? = nil, trackDeg: Double? = nil, groundSpeedKt: Double? = nil, timestamp: Date? = nil) {
        self.lat = lat
        self.lon = lon
        self.altitudeFt = altitudeFt
        self.trackDeg = trackDeg
        self.groundSpeedKt = groundSpeedKt
        self.timestamp = timestamp
    }
}

public struct TextSpan: Sendable {
    public let start: Int
    public let end: Int
    public let label: String?
    public init(start: Int, end: Int, label: String? = nil) {
        self.start = start
        self.end = end
        self.label = label
    }
}

public struct ReadbackResult: Sendable {
    public let normalizedText: String
    public let snaps: [SnapEvent]
    public let intents: [ParsedIntent]
    public let overallConfidence: Double
    public let fieldConfidences: [String: Double]
    public let uncertainSpans: [TextSpan]
    /// True if runway op matched a NASR runway at nearest airport(s), false if impossible, nil if unknown.
    public let runwayValidated: Bool?
    public init(normalizedText: String, snaps: [SnapEvent], intents: [ParsedIntent], overallConfidence: Double, fieldConfidences: [String: Double], uncertainSpans: [TextSpan], runwayValidated: Bool? = nil) {
        self.normalizedText = normalizedText
        self.snaps = snaps
        self.intents = intents
        self.overallConfidence = overallConfidence
        self.fieldConfidences = fieldConfidences
        self.uncertainSpans = uncertainSpans
        self.runwayValidated = runwayValidated
    }
}

/// Set to true for debug logging (default off).
public var ReadbackEngineDebugLogging = false

public final class ReadbackEngine: Sendable {
    private let store: NASRStore

    #if DEBUG
    /// When true, log every runway validation candidate (including empty usableRunways). Default false; set via UserDefaults key "ReadbackEngine.debugLogRunwayCandidates".
    private static var debugLogRunwayCandidates: Bool {
        (UserDefaults.standard.object(forKey: "ReadbackEngine.debugLogRunwayCandidates") as? Bool) ?? false
    }
    #else
    private static let debugLogRunwayCandidates = false
    #endif

    public init(store: NASRStore) {
        self.store = store
    }

    public func process(transcript: String, gps: GPSContext, asrConfidence: Double? = nil) -> ReadbackResult {
        let normResult = Normalizer.normalize(transcript)
        let afterTaxi = repairTaxiwayPhrases(normResult.normalizedText)
        let repairedText = repairATCPhrases(afterTaxi)
        let foldedFromRepaired = repairedText.split(separator: " ").map(String.init)
        let gpsPoint = GeoPoint(lat: gps.lat, lon: gps.lon, altitudeFt: gps.altitudeFt)
        let snaps = EntitySnapper.snap(
            foldedTokens: normResult.foldedTokens,
            foldedTokenSpans: normResult.foldedTokenSpans,
            store: store,
            gps: gpsPoint
        )
        var intents: [ParsedIntent] = []
        if let rwy = Parsers.extractRunwayOperation(from: repairedText, foldedTokens: foldedFromRepaired) {
            intents.append(.runwayOperation(rwy))
        }
        for alt in Parsers.extractAltitude(from: repairedText) {
            intents.append(.altitude(alt))
        }
        for fc in Parsers.extractFrequencyChange(from: repairedText) {
            intents.append(.frequencyChange(fc))
        }
        if let ifr = Parsers.extractIFRClearance(from: repairedText) {
            intents.append(.ifrClearance(ifr))
        }
        if let taxi = Parsers.extractTaxiToRunway(from: repairedText, foldedTokens: foldedFromRepaired) {
            var taxiValidated: Bool? = nil
            if let rwy = taxi.runway, !rwy.isEmpty {
                let (airportId, res) = Self.validateRunwayAgainstActiveAirport(runway: rwy, gps: gps, store: store, radiusNm: 3.0, gateNm: 0.7)
                taxiValidated = res
                ReadbackDebugLog.log("taxiValidation: runway=\(rwy) airport=\(airportId ?? "none") result=\(res == true ? "true" : (res == false ? "false" : "nil"))")
            }
            let taxiWithValidation = TaxiToRunwayIntent(runway: taxi.runway, validated: taxiValidated)
            intents.append(.taxiToRunway(taxiWithValidation))
        }
        for via in Parsers.extractViaTaxiway(from: repairedText) {
            intents.append(.viaTaxiway(via))
        }
        if let cross = Parsers.extractCrossRunway(from: repairedText, foldedTokens: foldedFromRepaired) {
            var validated: [String: Bool?] = [:]
            for rwy in cross.runways {
                let (airportId, res) = Self.validateRunwayAgainstActiveAirport(runway: rwy, gps: gps, store: store, radiusNm: 3.0, gateNm: 0.7)
                validated[rwy] = res
                ReadbackDebugLog.log("crossValidation: runway=\(rwy) airport=\(airportId ?? "none") result=\(res == true ? "true" : (res == false ? "false" : "nil"))")
            }
            let crossWithValidation = CrossRunwayIntent(runways: cross.runways, runwayValidated: validated)
            intents.append(.crossRunway(crossWithValidation))
        }
        if let cont = Parsers.extractContinueTaxi(from: repairedText) {
            intents.append(.continueTaxi(cont))
        }

        let hasValidNumeric = intents.contains { i in
            switch i {
            case .frequencyChange(let f): return f.frequencyMHz >= 118 && f.frequencyMHz <= 137
            case .altitude(let a): return a.altitudeFt >= 0 && a.altitudeFt <= 50000
            case .ifrClearance: return true
            case .runwayOperation: return true
            case .taxiToRunway, .crossRunway, .continueTaxi, .viaTaxiway: return true
            }
        }
        let hasValidSnaps = !snaps.isEmpty
        var hasValidatedIntent = false
        for i in intents {
            if case .ifrClearance(let ifr) = i, let limit = ifr.clearanceLimit {
                if store.airport(byIdentifier: limit) != nil || store.airport(byIcao: limit) != nil || store.fix(byIdentifier: limit) != nil {
                    hasValidatedIntent = true
                    break
                }
            }
            if case .frequencyChange(let f) = i, f.frequencyMHz >= 118 && f.frequencyMHz <= 137 { hasValidatedIntent = true; break }
        }
        var uncertainFields: [String] = []
        if snaps.isEmpty && !normResult.foldedTokens.filter({ $0.count >= 2 }).isEmpty { uncertainFields.append("snap") }
        var hasConflict = false
        let altIntents = intents.compactMap { i -> AltitudeIntent? in if case .altitude(let a) = i { return a }; return nil }
        if altIntents.count > 1 && Set(altIntents.map(\.altitudeFt)).count > 1 { hasConflict = true }
        let freqIntents = intents.compactMap { i -> FrequencyChangeIntent? in if case .frequencyChange(let f) = i { return f }; return nil }
        if freqIntents.count > 1 && Set(freqIntents.map(\.frequencyMHz)).count > 1 { hasConflict = true }

        let hasRunwayOp = intents.contains { if case .runwayOperation = $0 { return true }; return false }
        let runwayValidated = Self.validateRunwayIntent(intents: intents, store: store, gps: gps)
        let (overall, fieldConfidences) = ConfidenceModel.compute(
            hasValidNumericTokens: hasValidNumeric,
            hasValidSnaps: hasValidSnaps,
            hasValidatedIntent: hasValidatedIntent,
            uncertainFields: uncertainFields,
            hasConflict: hasConflict,
            hasRunwayOp: hasRunwayOp,
            runwayValidated: runwayValidated
        )
        var uncertainSpans: [TextSpan] = []
        for f in normResult.foldedTokenSpans where uncertainFields.contains("snap") {
            uncertainSpans.append(TextSpan(start: f.1, end: f.2, label: "uncertain"))
        }
        return ReadbackResult(
            normalizedText: repairedText,
            snaps: snaps,
            intents: intents,
            overallConfidence: overall,
            fieldConfidences: fieldConfidences,
            uncertainSpans: uncertainSpans,
            runwayValidated: runwayValidated
        )
    }

    /// Validates runway op intent against nearest airport(s). Enforces radius filter; ground ops validate only against closest airport; clearedLand prefers closest, fallback only if no usable runways. Returns true if match, false if impossible, nil if unknown.
    private static func validateRunwayIntent(intents: [ParsedIntent], store: NASRStore, gps: GPSContext) -> Bool? {
        guard let rwyIntent = intents.compactMap({ i -> RunwayOperationIntent? in if case .runwayOperation(let r) = i { return r }; return nil }).first,
              let parsedRaw = rwyIntent.runway, !parsedRaw.isEmpty else { return nil }
        guard store.isLoaded else { return nil }
        let parsedCanonical = canonicalRunway(parsedRaw)

        let isGroundOp: Bool
        let baseRadiusNm: Double
        let maxRadiusNm: Double
        switch rwyIntent.operation {
        case .lineUpAndWait, .holdShort, .clearedTakeoff:
            isGroundOp = true
            baseRadiusNm = 3
            maxRadiusNm = 8
        case .clearedLand:
            isGroundOp = false
            baseRadiusNm = 10
            maxRadiusNm = 20
        }

        let accuracyM = LocationManager.shared.effectiveHorizontalAccuracy
        let computedRadiusNm: Double = {
            guard let acc = accuracyM else { return maxRadiusNm }
            if acc <= 20 { return baseRadiusNm }
            if acc <= 100 { return min(baseRadiusNm + 2, maxRadiusNm) }
            if acc <= 500 { return min(baseRadiusNm + 5, maxRadiusNm) }
            return maxRadiusNm
        }()

        // On-airport gate for ground ops only: only validate if nearest airport is within gate distance.
        let onAirportGateNm: Double? = isGroundOp ? {
            let baseOnAirportNm = 0.5
            let accM = accuracyM ?? 0
            let accuracyNm = max(0, accM / 1852.0)
            return min(2.0, baseOnAirportNm + max(0.2, accuracyNm * 2.0))
        }() : nil

        // Fetch candidates (geo grid may return items beyond radius); then enforce radius filter.
        let rawCandidates = store.nearestAirports(lat: gps.lat, lon: gps.lon, radiusNm: max(computedRadiusNm, 20), max: 30)
        let withinRadius = rawCandidates.filter { $0.distanceNm <= computedRadiusNm }
        let nearestDistNm = withinRadius.first?.distanceNm
        let nearestId = withinRadius.first?.item.identifier

        ReadbackDebugLog.log("runwayValidation: op=\(rwyIntent.operation.rawValue) accM=\(accuracyM.map { "\($0)" } ?? "nil") radiusNm=\(computedRadiusNm) gateNm=\(onAirportGateNm.map { "\($0)" } ?? "nil") nearest=\(nearestId ?? "nil") nearestDistNm=\(nearestDistNm.map { String(format: "%.3f", $0) } ?? "nil")")

        // Ground ops: skip validation if not on airport (nearest beyond gate).
        if let gate = onAirportGateNm, let dist = nearestDistNm, dist > gate {
            ReadbackDebugLog.log("runwayValidation: skip (not on airport): nearestDistNm=\(String(format: "%.3f", dist)) gateNm=\(gate)")
            ReadbackDebugLog.log("runwayValidationSummary: candidates=\(withinRadius.count) usableCandidates=0 chosen=none chosenDistNm=n/a result=unknown")
            ReadbackDebugLog.log("runwayValidation: result -> unknown (not on airport)")
            return nil
        }

        // No airport within radius
        if withinRadius.isEmpty {
            ReadbackDebugLog.log("runwayValidation: no airport within radiusNm=\(computedRadiusNm) -> unknown")
            ReadbackDebugLog.log("runwayValidationSummary: candidates=0 usableCandidates=0 chosen=none chosenDistNm=n/a result=unknown")
            ReadbackDebugLog.log("runwayValidation: result -> unknown (no airport within radius)")
            return nil
        }

        // Build (airport, distanceNm, usableEnds, runwayMatches) for each candidate within radius; log per-candidate only when flag set, or has usable runways, or is chosen (chosen gets its own line below).
        struct CandidateInfo { let airport: NASRAirport; let distanceNm: Double; let usableEnds: [String]; let runwayMatches: Bool }
        var infos: [CandidateInfo] = []
        for located in withinRadius {
            let airport = located.item
            let runways = store.runways(atAirport: airport.identifier)
            let rawDesignators = runways.map { $0.runwayId }
            let usableEnds = rawDesignators.flatMap { expandRunwayEnds($0) }
            let canonicalEnds = usableEnds.map { canonicalRunway($0) }
            let runwayMatches = !usableEnds.isEmpty && canonicalEnds.contains { nasrRunwayMatches(parsed: parsedCanonical, runwayId: $0) }
            infos.append(CandidateInfo(airport: airport, distanceNm: located.distanceNm, usableEnds: usableEnds, runwayMatches: runwayMatches))
            if Self.debugLogRunwayCandidates || !usableEnds.isEmpty {
                ReadbackDebugLog.log("runwayValidation: candidate airport=\(airport.identifier) distNm=\(String(format: "%.2f", located.distanceNm)) usableRunways=\(usableEnds)")
            }
        }

        let usableCandidatesCount = infos.filter { !$0.usableEnds.isEmpty }.count

        if isGroundOp {
            // Ground ops: validate ONLY against the single closest airport within radius.
            let closest = infos[0]
            if closest.usableEnds.isEmpty {
                ReadbackDebugLog.log("runwayValidation: chosen airport=\(closest.airport.identifier) distNm=\(String(format: "%.2f", closest.distanceNm)) -> unknown (no usable runways)")
                ReadbackDebugLog.log("runwayValidationSummary: candidates=\(infos.count) usableCandidates=\(usableCandidatesCount) chosen=\(closest.airport.identifier) chosenDistNm=\(String(format: "%.2f", closest.distanceNm)) result=unknown")
                ReadbackDebugLog.log("runwayValidation: result -> unknown (closest has no usable runways)")
                return nil
            }
            let resultStr = closest.runwayMatches ? "match" : "impossible"
            ReadbackDebugLog.log("runwayValidation: chosen airport=\(closest.airport.identifier) distNm=\(String(format: "%.2f", closest.distanceNm)) -> \(closest.runwayMatches ? "match" : "noMatch")")
            ReadbackDebugLog.log("runwayValidationSummary: candidates=\(infos.count) usableCandidates=\(usableCandidatesCount) chosen=\(closest.airport.identifier) chosenDistNm=\(String(format: "%.2f", closest.distanceNm)) result=\(resultStr)")
            ReadbackDebugLog.log("runwayValidation: result -> \(closest.runwayMatches ? "match" : "impossible (runway not at closest airport)")")
            return closest.runwayMatches
        }

        // ClearedLand: prefer closest; only fall back to next if closest has zero usable runways.
        var chosen: CandidateInfo?
        for info in infos {
            if !info.usableEnds.isEmpty {
                chosen = info
                break
            }
        }
        guard let ch = chosen else {
            ReadbackDebugLog.log("runwayValidation: no airport within radius has usable runways -> unknown")
            ReadbackDebugLog.log("runwayValidationSummary: candidates=\(infos.count) usableCandidates=\(usableCandidatesCount) chosen=none chosenDistNm=n/a result=unknown")
            ReadbackDebugLog.log("runwayValidation: result -> unknown (no usable runways in radius)")
            return nil
        }
        let resultStr = ch.runwayMatches ? "match" : "impossible"
        ReadbackDebugLog.log("runwayValidation: chosen airport=\(ch.airport.identifier) distNm=\(String(format: "%.2f", ch.distanceNm)) -> \(ch.runwayMatches ? "match" : "noMatch")")
        ReadbackDebugLog.log("runwayValidationSummary: candidates=\(infos.count) usableCandidates=\(usableCandidatesCount) chosen=\(ch.airport.identifier) chosenDistNm=\(String(format: "%.2f", ch.distanceNm)) result=\(resultStr)")
        ReadbackDebugLog.log("runwayValidation: result -> \(ch.runwayMatches ? "match" : "impossible (runway not at chosen airport)")")
        return ch.runwayMatches
    }

    /// Canonical form for matching only: remove leading zero from two-digit number. "06L" -> "6L", "32" -> "32".
    private static func canonicalRunway(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces).uppercased()
        guard !t.isEmpty else { return s }
        let digitPart = t.prefix(while: { $0.isNumber })
        let letterPart = t.dropFirst(digitPart.count)
        guard digitPart.count >= 1, digitPart.count <= 2 else { return s }
        guard letterPart.isEmpty || (letterPart.count == 1 && "LRC".contains(letterPart)) else { return s }
        let numStr = String(digitPart)
        let normalizedNum: String
        if digitPart.count == 2 && digitPart.first == "0" {
            normalizedNum = String(digitPart.dropFirst())
        } else {
            normalizedNum = numStr
        }
        return normalizedNum + (letterPart.isEmpty ? "" : String(letterPart))
    }

    /// Expands a raw NASR runwayId (e.g. "14/32", "06L/24R") into two-digit display runway ends: ^\d{1,2}([LRC])?$.
    private static func expandRunwayEnds(_ rawId: String) -> [String] {
        let tokens = rawId.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        var result: [String] = []
        for token in tokens {
            guard !token.isEmpty else { continue }
            let digitPart = token.prefix(while: { $0.isNumber })
            let letterPart = token.dropFirst(digitPart.count)
            guard digitPart.count >= 1, digitPart.count <= 2 else { continue }
            guard letterPart.isEmpty || (letterPart.count == 1 && "LRC".contains(letterPart)) else { continue }
            let numStr = String(digitPart)
            let twoDigit = numStr.count == 1 ? "0" + numStr : numStr
            result.append(twoDigit + (letterPart.isEmpty ? "" : String(letterPart)))
        }
        return result
    }

    /// Canonical parsed designator matches canonical runway_id (exact; or digits-only parsed matches "32"/"32L"/"32R"/"32C").
    private static func nasrRunwayMatches(parsed: String, runwayId: String) -> Bool {
        let p = parsed.uppercased()
        let r = runwayId.uppercased()
        if p == r { return true }
        guard p.allSatisfy(\.isNumber), !p.isEmpty else { return false }
        guard r.hasPrefix(p) else { return false }
        let suffix = r.dropFirst(p.count)
        return suffix.isEmpty || (suffix.count == 1 && "LRC".contains(suffix))
    }

    /// Validates a single runway designator against the "active" (nearest within gate) airport. Uses same gate logic as ground ops.
    /// - Returns: (airportId, result) where result is true/false if on airport, nil if not on airport (unknown).
    static func validateRunwayAgainstActiveAirport(runway: String, gps: GPSContext, store: NASRStore, radiusNm: Double, gateNm: Double?) -> (airportId: String?, result: Bool?) {
        guard store.isLoaded else { return (nil, nil) }
        let parsedCanonical = canonicalRunway(runway)
        let rawCandidates = store.nearestAirports(lat: gps.lat, lon: gps.lon, radiusNm: max(radiusNm, 20), max: 30)
        let withinRadius = rawCandidates.filter { $0.distanceNm <= radiusNm }
        guard let nearest = withinRadius.first else { return (nil, nil) }
        if let gate = gateNm, nearest.distanceNm > gate {
            return (nearest.item.identifier, nil)
        }
        let airport = nearest.item
        let runways = store.runways(atAirport: airport.identifier)
        let rawDesignators = runways.map { $0.runwayId }
        let usableEnds = rawDesignators.flatMap { expandRunwayEnds($0) }
        let canonicalEnds = usableEnds.map { canonicalRunway($0) }
        let matches = !usableEnds.isEmpty && canonicalEnds.contains { nasrRunwayMatches(parsed: parsedCanonical, runwayId: $0) }
        return (airport.identifier, matches)
    }
}
