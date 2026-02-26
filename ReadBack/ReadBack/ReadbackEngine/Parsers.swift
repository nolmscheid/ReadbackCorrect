// ReadbackEngine/Parsers.swift
// Intent parsers: frequency change, altitude, IFR clearance (partial CRAFT).

import Foundation

public enum ParsedIntent: Sendable {
    case frequencyChange(FrequencyChangeIntent)
    case altitude(AltitudeIntent)
    case ifrClearance(IFRClearanceIntent)
    case runwayOperation(RunwayOperationIntent)
    /// "Taxi to runway 14"
    case taxiToRunway(TaxiToRunwayIntent)
    /// "Cross runway 29L 29R"
    case crossRunway(CrossRunwayIntent)
    /// "Continue on Charlie" / "Continue on C"
    case continueTaxi(ContinueTaxiIntent)
    /// "Via Delta" / "VIA D" (taxi route)
    case viaTaxiway(ViaTaxiwayIntent)
}

public struct ViaTaxiwayIntent: Sendable {
    public let taxiway: String
    public init(taxiway: String) { self.taxiway = taxiway }
}

public struct TaxiToRunwayIntent: Sendable {
    public let runway: String?
    /// true = runway exists at active airport, false = impossible, nil = unknown (e.g. not on airport).
    public let validated: Bool?
    public init(runway: String?, validated: Bool? = nil) {
        self.runway = runway
        self.validated = validated
    }
}

public struct CrossRunwayIntent: Sendable {
    public let runways: [String]
    /// Per-runway validation: key = normalized runway (e.g. "24L"), value = true/false/nil.
    public let runwayValidated: [String: Bool?]
    public init(runways: [String], runwayValidated: [String: Bool?] = [:]) {
        self.runways = runways
        self.runwayValidated = runwayValidated
    }
}

public struct ContinueTaxiIntent: Sendable {
    public let taxiway: String?
    public init(taxiway: String?) { self.taxiway = taxiway }
}

public enum RunwayOperation: String, Sendable {
    case lineUpAndWait
    case clearedTakeoff
    case holdShort
    case clearedLand
}

public struct RunwayOperationIntent: Sendable {
    public let operation: RunwayOperation
    public let runway: String?
    public init(operation: RunwayOperation, runway: String?) {
        self.operation = operation
        self.runway = runway
    }
}

public struct FrequencyChangeIntent: Sendable {
    public let facilityType: String?
    public let frequencyMHz: Double
    public init(facilityType: String?, frequencyMHz: Double) {
        self.facilityType = facilityType
        self.frequencyMHz = frequencyMHz
    }
}

public struct AltitudeIntent: Sendable {
    public enum Verb: String, Sendable { case climb, descend, maintain }
    public let verb: Verb
    public let altitudeFt: Int
    public init(verb: Verb, altitudeFt: Int) {
        self.verb = verb
        self.altitudeFt = altitudeFt
    }
}

public struct IFRClearanceIntent: Sendable {
    public let clearanceLimit: String?
    public let routeTokens: [String]
    public let initialAltitude: Int?
    public let squawk: String?
    public let departureFreq: Double?
    public init(clearanceLimit: String?, routeTokens: [String], initialAltitude: Int?, squawk: String?, departureFreq: Double?) {
        self.clearanceLimit = clearanceLimit
        self.routeTokens = routeTokens
        self.initialAltitude = initialAltitude
        self.squawk = squawk
        self.departureFreq = departureFreq
    }
}

public enum Parsers {

    /// Detect "contact X on 128.7", "change to 120.2", "monitor 121.5"
    public static func extractFrequencyChange(from normalizedText: String) -> [FrequencyChangeIntent] {
        var results: [FrequencyChangeIntent] = []
        let lower = normalizedText.lowercased()
        let tokens = normalizedText.split(separator: " ").map { String($0) }
        for i in 0..<tokens.count {
            let t = tokens[i].lowercased()
            if t == "contact" || t == "change" || t == "monitor" || t == "switch" || t == "try" {
                var j = i + 1
                while j < tokens.count && !isLikelyFrequency(tokens[j]) { j += 1 }
                if j < tokens.count, let freq = parseFrequency(tokens[j]) {
                    results.append(FrequencyChangeIntent(facilityType: nil, frequencyMHz: freq))
                }
            }
            if (t == "on" || t == "to") && i + 1 < tokens.count, let freq = parseFrequency(tokens[i + 1]) {
                results.append(FrequencyChangeIntent(facilityType: nil, frequencyMHz: freq))
            }
        }
        return results
    }

    private static func isLikelyFrequency(_ s: String) -> Bool {
        if s.contains(".") {
            let parts = s.split(separator: ".")
            guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) else { return false }
            return a >= 118 && a <= 137 && b >= 0 && b <= 999
        }
        if let v = Double(s) { return v >= 118 && v <= 137 }
        return false
    }

    private static func parseFrequency(_ s: String) -> Double? {
        guard let v = Double(s) else { return nil }
        if v >= 118 && v <= 137 { return v }
        return nil
    }

    /// Detect "climb and maintain 3000", "descend and maintain 2000", "maintain 5000"
    public static func extractAltitude(from normalizedText: String) -> [AltitudeIntent] {
        var results: [AltitudeIntent] = []
        let tokens = normalizedText.split(separator: " ").map { String($0) }
        var i = 0
        while i < tokens.count {
            let t = tokens[i].lowercased()
            var verb: AltitudeIntent.Verb?
            if t == "climb" { verb = .climb }
            else if t == "descend" { verb = .descend }
            else if t == "maintain" { verb = .maintain }
            if let v = verb {
                var j = i + 1
                while j < tokens.count && (tokens[j].lowercased() == "and" || tokens[j].lowercased() == "maintain") { j += 1 }
                if j < tokens.count, let alt = parseAltitude(tokens[j]) {
                    results.append(AltitudeIntent(verb: v, altitudeFt: alt))
                }
                i = j
                continue
            }
            i += 1
        }
        return results
    }

    private static func parseAltitude(_ s: String) -> Int? {
        if let v = Int(s), v >= 0 && v <= 50000 { return v }
        if s.hasSuffix("000") {
            let num = s.dropLast(3)
            if let v = Int(num) { return v * 1000 }
        }
        return nil
    }

    /// Runway/tower phrases: do not emit IFR for these; they are RunwayOperationIntent only.
    private static let runwayTowerPhrases = [
        "cleared to land", "cleared land", "cleared for takeoff", "cleared takeoff",
        "line up and wait", "hold short"
    ]

    /// Partial IFR: "cleared to X", route keywords, SID name, initial alt, squawk, departure freq. Also accepts squawk-only ("squawk 4521"). Returns nil when transcript is runway/tower only (cleared to land, cleared for takeoff, line up and wait, hold short).
    public static func extractIFRClearance(from normalizedText: String) -> IFRClearanceIntent? {
        let lower = normalizedText.lowercased()
        let hasRunwayTowerPhrase = runwayTowerPhrases.contains { lower.contains($0) }
        if hasRunwayTowerPhrase {
            let hasSquawk = lower.contains("squawk")
            let hasClearedToDestination = lower.contains("cleared to") && !lower.contains("cleared to land")
            if !hasSquawk || hasClearedToDestination { return nil }
        }
        let hasSquawkOnly = lower.contains("squawk") && (lower.contains("cleared") == false && lower.contains("clearance") == false)
        guard lower.contains("cleared") || lower.contains("clearance") || hasSquawkOnly else { return nil }
        let tokens = normalizedText.split(separator: " ").map { String($0) }
        var clearanceLimit: String?
        var routeTokens: [String] = []
        var initialAltitude: Int?
        var squawk: String?
        var departureFreq: Double?

        if let idx = tokens.firstIndex(where: { $0.lowercased() == "to" }), idx + 1 < tokens.count {
            clearanceLimit = String(tokens[idx + 1]).uppercased()
        }
        if let idx = tokens.firstIndex(where: { $0.lowercased() == "via" }), idx + 1 < tokens.count {
            var j = idx + 1
            while j < tokens.count {
                let w = String(tokens[j])
                if w.lowercased() == "then" || w.lowercased() == "and" { j += 1; continue }
                if let _ = Int(w) { break }
                routeTokens.append(w.uppercased())
                j += 1
            }
        }
        if let idx = tokens.firstIndex(where: { $0.lowercased() == "squawk" }), idx + 1 < tokens.count {
            let sq = String(tokens[idx + 1])
            if sq.allSatisfy({ $0.isNumber }) && sq.count == 4 { squawk = sq }
        }
        for i in 0..<tokens.count {
            if let alt = parseAltitude(String(tokens[i])), initialAltitude == nil {
                if i > 0 && (tokens[i-1].lowercased() == "climb" || tokens[i-1].lowercased() == "maintain") {
                    initialAltitude = alt
                }
            }
        }
        return IFRClearanceIntent(clearanceLimit: clearanceLimit, routeTokens: routeTokens, initialAltitude: initialAltitude, squawk: squawk, departureFreq: departureFreq)
    }

    // MARK: - Runway operation

    private static let runwayOpPhrases: [(String, RunwayOperation)] = [
        ("line up and wait", .lineUpAndWait),
        ("line up & wait", .lineUpAndWait),
        ("cleared for takeoff", .clearedTakeoff),
        ("cleared takeoff", .clearedTakeoff),
        ("hold short", .holdShort),
        ("hold runway", .holdShort),  // "hold runway 32" / "hold runway two seven left" → holdShort (only when runway present)
        ("cleared to land", .clearedLand),
        ("cleared land", .clearedLand),
    ]

    /// Detects runway instructions (line up and wait, cleared for takeoff, hold short, cleared to land) and extracts runway designator.
    /// Intent runway string is always two-digit (e.g. 06, 06L, 32).
    public static func extractRunwayOperation(from normalizedText: String, foldedTokens: [String]? = nil) -> RunwayOperationIntent? {
        let lower = normalizedText.lowercased()
        for (phrase, op) in runwayOpPhrases {
            if lower.contains(phrase) {
                let raw = runwayFromFoldedTokens(after: phrase, in: lower, foldedTokens: foldedTokens)
                    ?? runwayFromRegex(in: normalizedText)
                let runway = raw.map { formatRunwayTwoDigit($0) }
                return RunwayOperationIntent(operation: op, runway: runway)
            }
        }
        // "Hold runway XX" when normalizer folded to "hold 27L" (no "runway" in text): treat as holdShort if "hold" is followed by runway designator, not "at" (IFR).
        if lower.contains("hold "), let tokens = foldedTokens, !tokens.isEmpty {
            for (i, tok) in tokens.enumerated() where tok.trimmingCharacters(in: .whitespaces).lowercased() == "hold" {
                let nextIdx = i + 1
                guard nextIdx < tokens.count else { break }
                let next = tokens[nextIdx].trimmingCharacters(in: .whitespaces).lowercased()
                if next == "at" { return nil }
                if next == "runway" { break }
                if isRunwayToken(tokens[nextIdx]) {
                    if let raw = parseRunwayFromTokenSequence(tokens, startIndex: nextIdx) {
                        return RunwayOperationIntent(operation: .holdShort, runway: formatRunwayTwoDigit(raw))
                    }
                }
                break
            }
        }
        return nil
    }

    /// Aviation standard: two-digit runway (06, 14, 32). Single digit -> pad with leading 0.
    private static func formatRunwayTwoDigit(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces).uppercased()
        guard !t.isEmpty else { return s }
        let digitPart = t.prefix(while: { $0.isNumber })
        let letterPart = t.dropFirst(digitPart.count)
        guard !digitPart.isEmpty, digitPart.count <= 2 else { return s }
        guard letterPart.isEmpty || (letterPart.count == 1 && "LRC".contains(letterPart)) else { return s }
        let numStr = String(digitPart)
        let twoDigit = numStr.count == 1 ? "0" + numStr : numStr
        return twoDigit + (letterPart.isEmpty ? "" : String(letterPart))
    }

    /// Runway-like token: 1–2 digits optionally followed by L, R, or C (e.g. 32, 14, 27L, 4R).
    private static func isRunwayToken(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        let suffix = t.drop(while: { $0.isNumber })
        if suffix.isEmpty { return t.count <= 2 && t.allSatisfy(\.isNumber) }
        if suffix.count == 1, let c = suffix.first, "lrcLRC".contains(c) { return t.dropLast().allSatisfy(\.isNumber) && t.dropLast().count <= 2 }
        return false
    }

    /// Single digit token for runway assembly (e.g. "9", "0").
    private static func isSingleDigitToken(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.count == 1 && t.first?.isNumber == true
    }

    /// Filler tokens to skip before/within runway digit sequence (ASR junk e.g. "room only", "uh").
    private static let runwayFillerTokens: Set<String> = [
        "or", "room", "only", "to", "the", "a", "uh", "um", "and"
    ]

    private static func isRunwayFillerToken(_ s: String) -> Bool {
        runwayFillerTokens.contains(s.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Assemble runway from token sequence: ["9","9"], ["9","or","9"], ["0","9"], or single runway token (e.g. "32", "27L"). Skips filler tokens (room, only, uh, etc.) before/within digits. Max 2 digits then optional L/R/C.
    private static func parseRunwayFromTokenSequence(_ tokens: [String], startIndex: Int) -> String? {
        var i = startIndex
        while i < tokens.count {
            let tok = tokens[i]
            if isRunwayFillerToken(tok) {
                i += 1
                continue
            }
            if isRunwayToken(tok) {
                let digits = tok.filter(\.isNumber)
                let letter = tok.last.flatMap { c in "lrcLRC".contains(c) ? String(c).uppercased() : nil } ?? ""
                if digits.count >= 2 || !letter.isEmpty {
                    return digits + letter
                }
                if digits.count == 1 {
                    var digitStr = digits
                    var j = i + 1
                    while digitStr.count < 2 && j < tokens.count {
                        let next = tokens[j].trimmingCharacters(in: .whitespaces).lowercased()
                        if isRunwayFillerToken(tokens[j]) { j += 1; continue }
                        if isSingleDigitToken(tokens[j]) {
                            digitStr += tokens[j].filter(\.isNumber)
                            j += 1
                        } else { break }
                    }
                    if j < tokens.count {
                        let suffix = tokens[j].trimmingCharacters(in: .whitespaces).lowercased()
                        if suffix == "left" || suffix == "l" { return digitStr + "L" }
                        if suffix == "right" || suffix == "r" { return digitStr + "R" }
                        if suffix == "center" || suffix == "centre" || suffix == "c" { return digitStr + "C" }
                    }
                    return digitStr
                }
            }
            i += 1
        }
        return nil
    }

    private static func runwayFromFoldedTokens(after phrase: String, in normalizedLower: String, foldedTokens: [String]?) -> String? {
        guard let tokens = foldedTokens, !tokens.isEmpty else { return nil }
        let built = tokens.joined(separator: " ").lowercased()
        guard let phraseRange = built.range(of: phrase) else { return nil }
        let phraseEndIdx = built.distance(from: built.startIndex, to: phraseRange.upperBound)
        var charIdx = 0
        var tokenIdx = 0
        for (i, tok) in tokens.enumerated() {
            if charIdx + tok.count >= phraseEndIdx {
                tokenIdx = i + 1
                break
            }
            charIdx += tok.count + 1
        }
        return parseRunwayFromTokenSequence(tokens, startIndex: tokenIdx)
    }

    private static func runwayFromRegex(in normalizedText: String) -> String? {
        let lower = normalizedText.lowercased()
        let pattern = #"runway\s+(\d{1,2})\s*(left|right|center|l|r|c)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) else { return nil }
        guard let numRange = Range(match.range(at: 1), in: lower) else { return nil }
        let num = String(lower[numRange])
        var suffix = ""
        if match.numberOfRanges > 2, let sufRange = Range(match.range(at: 2), in: lower), !sufRange.isEmpty {
            let s = String(lower[sufRange])
            if s == "left" || s == "l" { suffix = "L" }
            else if s == "right" || s == "r" { suffix = "R" }
            else if s == "center" || s == "centre" || s == "c" { suffix = "C" }
        }
        return num + suffix
    }

    // MARK: - Taxi intents (multi-intent phrases)

    /// "Taxi to runway 14" → taxiToRunway(runway: "14")
    public static func extractTaxiToRunway(from normalizedText: String, foldedTokens: [String]? = nil) -> TaxiToRunwayIntent? {
        let lower = normalizedText.lowercased()
        let phrase = "taxi to runway"
        guard lower.contains(phrase) else { return nil }
        let raw = runwayFromFoldedTokens(after: phrase, in: lower, foldedTokens: foldedTokens)
            ?? runwayFromRegex(in: normalizedText)
        let runway = raw.map { formatRunwayTwoDigit($0) }
        return TaxiToRunwayIntent(runway: runway, validated: nil)
    }

    /// Stop words: after these we no longer collect cross-runway designators (e.g. "continue" in "cross runway 29L 29R continue on C").
    private static let crossRunwayStopWords: Set<String> = ["continue", "hold", "via", "then", "taxi", "to", "short"]

    /// "Cross runway 29L 29R" / "cross runways 29L and 29R" → crossRunway(runways: ["29L", "29R"]). Only parses runways in the segment after "cross runway(s)" until a stop word.
    public static func extractCrossRunway(from normalizedText: String, foldedTokens: [String]? = nil) -> CrossRunwayIntent? {
        let lower = normalizedText.lowercased()
        let tokens = foldedTokens ?? normalizedText.split(separator: " ").map { String($0) }
        let built = tokens.joined(separator: " ").lowercased()
        guard let crossRange = built.range(of: "cross") else { return nil }
        let afterCross = String(built[crossRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard afterCross.hasPrefix("runway") || afterCross.hasPrefix("runways") else { return nil }
        let afterRunway = afterCross.dropFirst(afterCross.hasPrefix("runways") ? 7 : 6).trimmingCharacters(in: .whitespaces)
        let segment = String(afterRunway)
        if segment.isEmpty { return nil }
        let segmentTokens = segment.split(separator: " ").map { String($0) }
        var runways: [String] = []
        var i = 0
        while i < segmentTokens.count {
            let t = segmentTokens[i].trimmingCharacters(in: .whitespaces).lowercased()
            if crossRunwayStopWords.contains(t) { break }
            if t == "and" || t == "&" { i += 1; continue }
            if isRunwayToken(segmentTokens[i]) {
                if let raw = parseRunwayFromTokenSequence(segmentTokens, startIndex: i) {
                    runways.append(formatRunwayTwoDigit(raw))
                    i += 1
                    continue
                }
            }
            i += 1
        }
        return runways.isEmpty ? nil : CrossRunwayIntent(runways: runways)
    }

    /// "Via Delta" / "VIA D" (after TaxiwayRepair) → viaTaxiway(taxiway: "D"). Only when TAXI is in phrase.
    public static func extractViaTaxiway(from normalizedText: String) -> [ViaTaxiwayIntent] {
        let lower = normalizedText.lowercased()
        guard lower.contains("taxi") else { return [] }
        let tokens = normalizedText.split(separator: " ").map { String($0) }
        var results: [ViaTaxiwayIntent] = []
        var i = 0
        while i < tokens.count - 1 {
            if tokens[i].uppercased() == "VIA" {
                let next = tokens[i + 1].trimmingCharacters(in: .whitespaces)
                if next.count == 1, next.first!.isLetter {
                    results.append(ViaTaxiwayIntent(taxiway: next.uppercased()))
                }
                i += 2
                continue
            }
            i += 1
        }
        return results
    }

    /// "Continue on Charlie" / "continue on C" → continueTaxi(taxiway: "C")
    public static func extractContinueTaxi(from normalizedText: String) -> ContinueTaxiIntent? {
        let lower = normalizedText.lowercased()
        guard lower.contains("continue") && lower.contains("on") else { return nil }
        let tokens = normalizedText.split(separator: " ").map { String($0) }
        for i in 0..<(tokens.count - 2) {
            if tokens[i].lowercased() == "continue" && tokens[i + 1].lowercased() == "on" {
                let taxiwayToken = String(tokens[i + 2]).trimmingCharacters(in: .whitespaces)
                if taxiwayToken.isEmpty { continue }
                let single = taxiwayToken.count == 1 ? taxiwayToken.uppercased() : nil
                let phonetic: String? = {
                    let low = taxiwayToken.lowercased()
                    if low == "alpha" { return "A" }; if low == "bravo" { return "B" }; if low == "charlie" || low == "charley" { return "C" }
                    if low == "delta" { return "D" }; if low == "echo" { return "E" }; if low == "foxtrot" { return "F" }
                    if low == "golf" { return "G" }; if low == "hotel" { return "H" }; if low == "india" { return "I" }
                    if low == "juliet" || low == "juliette" { return "J" }; if low == "kilo" { return "K" }; if low == "lima" { return "L" }
                    if low == "mike" { return "M" }; if low == "november" { return "N" }; if low == "oscar" { return "O" }
                    if low == "papa" { return "P" }; if low == "quebec" { return "Q" }; if low == "romeo" { return "R" }
                    if low == "sierra" { return "S" }; if low == "tango" { return "T" }; if low == "uniform" { return "U" }
                    if low == "victor" { return "V" }; if low == "whiskey" { return "W" }; if low == "xray" || low == "x-ray" { return "X" }
                    if low == "yankee" { return "Y" }; if low == "zulu" { return "Z" }
                    return nil
                }()
                let letter = single ?? phonetic
                return ContinueTaxiIntent(taxiway: letter ?? taxiwayToken.uppercased())
            }
        }
        return nil
    }
}
