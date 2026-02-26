import Foundation

enum ATISParser {

    static func parse(raw: String) -> ATISReport {
        let upper = raw.uppercased()
        var report = ATISReport(raw: upper)

        report.information = extractInfoLetter(upper)
        report.timeZulu = extractZuluTime(upper)
        report.wind = extractWind(upper)
        report.visibility = extractVisibility(upper)
        report.ceiling = extractCeiling(upper)
        report.temperatureDewpoint = extractTempDew(upper)
        report.altimeter = extractAltimeter(upper)

        report.runways = extractRunways(upper)
        report.approaches = extractApproaches(upper)
        report.remarks = extractRemarks(upper)

        return report
    }

    // MARK: - Extractors

    private static func extractInfoLetter(_ text: String) -> String? {
        // "INFORMATION SIERRA", "INFO X-RAY", "WITH INFORMATION ZULU"
        let patterns = [
            #"INFORMATION\s+([A-Z](?:-?[A-Z])?)"#,
            #"INFO(?:RMATION)?\s+([A-Z](?:-?[A-Z])?)"#,
            #"WITH\s+INFORMATION\s+([A-Z](?:-?[A-Z])?)"#
        ]
        if let g = firstRegexGroup(text, patterns: patterns) {
            return g.replacingOccurrences(of: "-", with: " ")
        }
        return nil
    }

    private static func extractZuluTime(_ text: String) -> String? {
        // "0158 ZULU", "0532 ZULU"
        let patterns = [
            #"\b(\d{4})\s*ZULU\b"#,
            #"\b(\d{4})Z\b"#
        ]
        return firstRegexGroup(text, patterns: patterns)
    }

    private static func extractAltimeter(_ text: String) -> String? {
        // "ALTIMETER 2992", "ALTIMETER 29.92", "A2992"
        let patterns = [
            #"ALTIMETER\s+(\d{2}\.\d{2})"#,
            #"ALTIMETER\s+(\d{4})"#,
            #"\bA(\d{4})\b"#
        ]
        if let g = firstRegexGroup(text, patterns: patterns) {
            // Normalize 2992 -> 29.92
            if g.count == 4, let n = Int(g) {
                let whole = n / 100
                let frac = n % 100
                return "\(whole).\(String(format: "%02d", frac))"
            }
            return g
        }
        return nil
    }

    private static func extractWind(_ text: String) -> String? {
        // "WIND 270 AT 15 GUST 27", "WIND 160 AT 03", "WINDS 320 AT 12"
        let pattern = #"\bWIND(?:S)?\s+(\d{3}|CALM)\s+(?:AT|@)\s+(\d{1,2})(?:\s+GUST(?:S)?\s+(\d{1,2}))?\b"#
        guard let m = firstRegexMatch(text, pattern: pattern) else { return nil }

        let dir = m.group(1) ?? ""
        let spd = m.group(2) ?? ""
        let gst = m.group(3)

        if dir == "CALM" { return "CALM" }
        if let gst, !gst.isEmpty { return "\(dir)@\(spd)G\(gst)" }
        return "\(dir)@\(spd)"
    }

    private static func extractVisibility(_ text: String) -> String? {
        // "VISIBILITY 10", "VISIBILITY MORE THAN 10"
        let patterns = [
            #"VISIBILITY\s+(MORE\s+THAN\s+)?(\d{1,2})(?:\s*SM)?"#,
            #"\bVIS\s+(\d{1,2})(?:\s*SM)?"#
        ]

        // Try to keep "MORE THAN 10" if present
        if let m = firstRegexMatch(text, pattern: patterns[0]) {
            let more = (m.group(1) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let vis = (m.group(2) ?? "")
            if !more.isEmpty { return "P\(vis)SM" }
            return "\(vis)SM"
        }
        if let g = firstRegexGroup(text, patterns: [patterns[1]]) {
            return "\(g)SM"
        }
        return nil
    }

    private static func extractCeiling(_ text: String) -> String? {
        // Rough ceiling: first BKN/OVC layer like "BKN 020" or "OVC 030" or transcript "BROKEN 5000"
        let patterns = [
            #"\b(BKN|OVC)\s*(\d{3})\b"#,              // METAR style
            #"\b(BROKEN|OVERCAST)\s+(\d{3,5})\b"#     // spoken style
        ]

        if let m = firstRegexMatch(text, pattern: patterns[0]) {
            let type = m.group(1) ?? ""
            let h = m.group(2) ?? ""
            return "\(type) \(h)"
        }
        if let m = firstRegexMatch(text, pattern: patterns[1]) {
            let type = m.group(1) ?? ""
            let h = m.group(2) ?? ""
            return "\(type) \(h)"
        }
        return nil
    }

    private static func extractTempDew(_ text: String) -> String? {
        // "TEMPERATURE 21 ... DEWPOINT 16", messy transcripts vary a lot
        let tempPattern = #"\bTEM(?:PERATURE)?\s+(-?\d{1,2})\b"#
        let dewPattern  = #"\bDEW(?:POINT)?\s+(-?\d{1,2})\b"#

        let t = firstRegexGroup(text, patterns: [tempPattern])
        let d = firstRegexGroup(text, patterns: [dewPattern])

        if let t, let d { return "\(t)C / \(d)C" }
        if let t { return "\(t)C" }
        return nil
    }

    private static func extractRunways(_ text: String) -> [String] {
        // "RUNWAY 32", "RUNWAYS 35R 35L", "LANDING AND DEPARTING RUNWAY 23"
        let pattern = #"\bRUNWAY(?:S)?\s+((?:\d{1,2}[LRC]?\s*)+)\b"#
        guard let m = firstRegexMatch(text, pattern: pattern) else { return [] }
        let chunk = (m.group(1) ?? "")
        let parts = chunk
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // De-dupe preserve order
        var seen = Set<String>()
        return parts.filter { seen.insert($0).inserted }
    }

    private static func extractApproaches(_ text: String) -> [String] {
        // "ILS RUNWAY 23", "VISUAL APPROACH", "RNAV"
        var out: [String] = []

        if text.contains("ILS") { out.append("ILS") }
        if text.contains("RNAV") { out.append("RNAV") }
        if text.contains("VISUAL") { out.append("VISUAL") }

        // De-dupe
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    private static func extractRemarks(_ text: String) -> [String] {
        // Keep a few common advisories when detectable
        var notes: [String] = []
        if text.contains("DENSITY ALTITUDE") { notes.append("DENSITY ALTITUDE") }
        if text.contains("SKYDIV") { notes.append("SKYDIVING OPS") }
        if text.contains("BIRD") { notes.append("BIRD ACTIVITY") }
        if text.contains("CONSTRUCTION") { notes.append("CONSTRUCTION") }
        if text.contains("RUNWAY") && text.contains("CLOSED") { notes.append("RWY CLOSED") }

        var seen = Set<String>()
        return notes.filter { seen.insert($0).inserted }
    }

    // MARK: - Regex helpers

    private struct RegexHit {
        let matches: [String?]
        func group(_ i: Int) -> String? {
            guard i >= 0, i < matches.count else { return nil }
            return matches[i]
        }
    }

    private static func firstRegexGroup(_ text: String, patterns: [String]) -> String? {
        for p in patterns {
            if let m = firstRegexMatch(text, pattern: p) {
                return m.group(1)
            }
        }
        return nil
    }

    private static func firstRegexMatch(_ text: String, pattern: String) -> RegexHit? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, options: [], range: range) else { return nil }

        var groups: [String?] = []
        for i in 0..<match.numberOfRanges {
            let r = match.range(at: i)
            if r.location == NSNotFound, r.length == 0 {
                groups.append(nil)
                continue
            }
            if let swiftRange = Range(r, in: text) {
                groups.append(String(text[swiftRange]))
            } else {
                groups.append(nil)
            }
        }
        return RegexHit(matches: groups)
    }
}
