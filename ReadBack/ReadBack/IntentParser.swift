import Foundation

enum IntentParser {

    static func parseIntents(in textUpper: String) -> [ATCIntent] {
        let t = normalize(textUpper)

        var found: [(index: Int, intent: ATCIntent)] = []

        // TAXI
        if let idx = firstIndex(of: "TAXI", in: t) {
            let dest = extractTaxiRunway(from: t)
            let via = extractTaxiwaysVia(from: t)
            found.append((idx, .taxi(destinationRunway: dest, via: via)))
        }

        // HOLD SHORT
        if let idx = firstIndex(of: "HOLD SHORT", in: t) {
            let rwy = extractHoldShortRunway(from: t)
            found.append((idx, .holdShort(runway: rwy)))
        }

        // CROSS RUNWAY
        if let idx = firstIndex(of: "CROSS RUNWAY", in: t) {
            let rwy = extractCrossRunway(from: t)
            found.append((idx, .crossRunway(runway: rwy)))
        }

        // CLEARED FOR TAKEOFF
        if let idx = firstIndex(of: "CLEARED FOR TAKEOFF", in: t) {
            let rwy = extractAnyRunway(from: t, near: "TAKEOFF")
            found.append((idx, .clearedForTakeoff(runway: rwy)))
        }

        // CLEARED TO LAND
        if let idx = firstIndex(of: "CLEARED TO LAND", in: t) {
            let rwy = extractAnyRunway(from: t, near: "LAND")
            found.append((idx, .clearedToLand(runway: rwy)))
        }

        // LINE UP AND WAIT
        if let idx = firstIndex(of: "LINE UP AND WAIT", in: t) {
            let rwy = extractAnyRunway(from: t, near: "WAIT")
            found.append((idx, .lineUpAndWait(runway: rwy)))
        }

        // GO AROUND
        if let idx = firstIndex(of: "GO AROUND", in: t) {
            found.append((idx, .goAround))
        }

        // ALTITUDE: CLIMB / DESCEND / MAINTAIN
        if let idx = firstIndex(ofAny: ["CLIMB AND MAINTAIN", "DESCEND AND MAINTAIN", "MAINTAIN"], in: t),
           let alt = extractAltitude(from: t) {

            if t.contains("DESCEND AND MAINTAIN") {
                found.append((idx, .descend(altitude: alt)))
            } else if t.contains("CLIMB AND MAINTAIN") {
                found.append((idx, .climb(altitude: alt)))
            } else {
                found.append((idx, .maintain(altitude: alt)))
            }
        }

        // HEADING
        if let idx = firstIndex(of: "HEADING", in: t),
           let hdg = extractHeading(from: t) {
            found.append((idx, .heading(degrees: hdg)))
        }

        // CONTACT
        if let idx = firstIndex(of: "CONTACT", in: t) {
            let (facility, freq) = extractContact(from: t)
            found.append((idx, .contact(facility: facility, frequency: freq)))
        }

        // SQUAWK
        if let idx = firstIndex(of: "SQUAWK", in: t),
           let code = extractSquawk(from: t) {
            found.append((idx, .squawk(code: code)))
        }

        // sort by spoken order
        found.sort { $0.index < $1.index }
        return found.map { $0.intent }
    }

    // MARK: - Normalization

    private static func normalize(_ s: String) -> String {
        s.uppercased()
            .replacingOccurrences(of: #"[^\w\s\.]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Index helpers

    private static func firstIndex(of needle: String, in haystack: String) -> Int? {
        guard let r = haystack.range(of: needle) else { return nil }
        return haystack.distance(from: haystack.startIndex, to: r.lowerBound)
    }

    private static func firstIndex(ofAny needles: [String], in haystack: String) -> Int? {
        var best: Int? = nil
        for n in needles {
            if let i = firstIndex(of: n, in: haystack) {
                if best == nil || i < best! { best = i }
            }
        }
        return best
    }

    // MARK: - Extractors (Runways / Taxiways / Numbers)

    private static func extractTaxiRunway(from t: String) -> String? {
        // TAXI TO RUNWAY 32
        let pattern = #"TAXI\s+TO\s+RUNWAY\s+(\d{1,2})([LRC])?"#
        return runwayFrom(pattern: pattern, in: t)
    }

    private static func extractHoldShortRunway(from t: String) -> String? {
        // HOLD SHORT (OF) RUNWAY 27L
        let pattern = #"HOLD\s+SHORT(?:\s+OF)?\s+RUNWAY\s+(\d{1,2})([LRC])?"#
        return runwayFrom(pattern: pattern, in: t)
    }

    private static func extractCrossRunway(from t: String) -> String? {
        let pattern = #"CROSS\s+RUNWAY\s+(\d{1,2})([LRC])?"#
        return runwayFrom(pattern: pattern, in: t)
    }

    private static func extractAnyRunway(from t: String, near _: String) -> String? {
        // fallback: any RUNWAY ##
        let pattern = #"RUNWAY\s+(\d{1,2})([LRC])?"#
        return runwayFrom(pattern: pattern, in: t)
    }

    private static func runwayFrom(pattern: String, in t: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(t.startIndex..., in: t)
        guard let m = re.firstMatch(in: t, options: [], range: range) else { return nil }

        guard let r1 = Range(m.range(at: 1), in: t) else { return nil }
        let num = String(t[r1])

        var suffix = ""
        if m.numberOfRanges > 2, let r2 = Range(m.range(at: 2), in: t) {
            suffix = String(t[r2])
        }

        return (num.count == 1 ? "0\(num)" : num) + suffix
    }

    private static func extractTaxiwaysVia(from t: String) -> [String] {
        // VIA ALPHA ECHO
        // VIA A E
        // Stops at comma, HOLD SHORT, CROSS, RUNWAY, or end.
        let pattern = #"VIA\s+(.+?)(?:,|HOLD\s+SHORT|CROSS\s+RUNWAY|RUNWAY|$)"#
        guard let viaChunk = firstRegexGroup(pattern: pattern, in: t, group: 1) else { return [] }

        let cleaned = viaChunk
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty { return [] }

        let tokens = cleaned.split(separator: " ").map { String($0).uppercased() }

        let phonetic: [String: String] = [
            "ALPHA":"A","ALFA":"A",
            "BRAVO":"B",
            "CHARLIE":"C",
            "DELTA":"D",
            "ECHO":"E",
            "FOXTROT":"F",
            "GOLF":"G",
            "HOTEL":"H",
            "INDIA":"I",
            "JULIET":"J","JULIETT":"J",
            "KILO":"K",
            "LIMA":"L",
            "MIKE":"M",
            "NOVEMBER":"N",
            "OSCAR":"O",
            "PAPA":"P",
            "QUEBEC":"Q",
            "ROMEO":"R",
            "SIERRA":"S",
            "TANGO":"T",
            "UNIFORM":"U",
            "VICTOR":"V",
            "WHISKEY":"W",
            "XRAY":"X","X-RAY":"X",
            "YANKEE":"Y",
            "ZULU":"Z"
        ]

        var out: [String] = []
        for tok in tokens {

            // ✅ Important: ignore pure numbers so runway numbers never appear in VIA
            if tok.allSatisfy(\.isNumber) {
                continue
            }

            if let mapped = phonetic[tok] {
                out.append(mapped)
            } else {
                // Allow taxiway formats like A, B, E, A1, B2
                // Reject long junk tokens.
                let isTaxiway = tok.count <= 4 && tok.first?.isLetter == true
                if isTaxiway {
                    out.append(tok)
                }
            }
        }

        // Dedup but keep order
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }
    private static func extractAltitude(from t: String) -> Int? {
        // CLIMB AND MAINTAIN 5000
        // MAINTAIN 3 000 (if spaced digits, normalize already removed punctuation but not spaces)
        let pattern = #"(?:CLIMB\s+AND\s+MAINTAIN|DESCEND\s+AND\s+MAINTAIN|MAINTAIN)\s+(\d[\d\s]{2,6})"#
        guard let raw = firstRegexGroup(pattern: pattern, in: t, group: 1) else { return nil }
        let digits = raw.filter(\.isNumber)
        return Int(digits)
    }

    private static func extractHeading(from t: String) -> Int? {
        // HEADING 90 -> 90, UI can pad to 3 digits
        let pattern = #"HEADING\s+(\d{1,3})"#
        guard let raw = firstRegexGroup(pattern: pattern, in: t, group: 1) else { return nil }
        return Int(raw.filter(\.isNumber))
    }

    private static func extractContact(from t: String) -> (facility: String?, frequency: String?) {
        // CONTACT DEPARTURE 124.8
        // CONTACT TOWER 118.3
        let pattern = #"CONTACT\s+([A-Z]+)?\s*([0-9]{3}\.[0-9]{1,3})?"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return (nil, nil) }
        let range = NSRange(t.startIndex..., in: t)
        guard let m = re.firstMatch(in: t, options: [], range: range) else { return (nil, nil) }

        var facility: String?
        var freq: String?

        if m.numberOfRanges > 1, let r1 = Range(m.range(at: 1), in: t) {
            let f = String(t[r1]).trimmingCharacters(in: .whitespacesAndNewlines)
            facility = f.isEmpty ? nil : f
        }
        if m.numberOfRanges > 2, let r2 = Range(m.range(at: 2), in: t) {
            let fr = String(t[r2]).trimmingCharacters(in: .whitespacesAndNewlines)
            freq = fr.isEmpty ? nil : fr
        }

        return (facility, freq)
    }

    private static func extractSquawk(from t: String) -> String? {
        let pattern = #"SQUAWK\s+(\d{4})"#
        return firstRegexGroup(pattern: pattern, in: t, group: 1)
    }

    // MARK: - Regex helper

    private static func firstRegexGroup(pattern: String, in text: String, group: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, options: [], range: range) else { return nil }
        guard m.numberOfRanges > group else { return nil }
        guard let r = Range(m.range(at: group), in: text) else { return nil }
        return String(text[r])
    }
}
