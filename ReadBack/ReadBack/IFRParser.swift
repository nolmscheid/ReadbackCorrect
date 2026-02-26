import Foundation

/// IFR clearance parser. Tokenizes once, then runs slot-based extraction. No UI; no global state mutation.
final class IFRParser {

    /// Parse clearance from context. Uses context.normalizedText; tokenize once at call site.
    func parse(context: ParsingContext) -> IFRClearance {
        var clearance = IFRClearance()
        let text = context.normalizedText

        clearance.callsign = extractCallsign(text: text)
        clearance.clearanceLimit = extractClearanceLimit(tokens: context.foldedTokens)
        clearance.route = extractRoute(text: text)
        clearance.altitude = extractAltitude(text: text)
        clearance.frequency = extractFrequency(text: context.foldedText)
        clearance.squawk = extractSquawk(text: context.foldedText)
        clearance.void = extractVoid(text: text)
        clearance.specialInstructions = extractSpecialInstructions(text: text)

        return clearance
    }

    // MARK: - Extraction (each returns Slot<T>; logic moved from existing CRAFT extraction)

    func extractCallsign(text: String) -> Slot<String> {
        // Existing behavior: callsign is not extracted in CRAFT; matching is done elsewhere. Return empty slot.
        return Slot(value: nil, confidence: 0.5, validated: false, sourceText: "")
    }

    func extractClearanceLimit(tokens: [String]) -> Slot<String> {
        let stopWords: Set<String> = [
            "AS",
            "VIA",
            "MAINTAIN",
            "DEPARTURE",
            "EXPECT",
            "SQUAWK",
            "CONTACT",
            "FREQUENCY"
        ]

        guard let clearedIdx = tokens.firstIndex(where: { $0.uppercased() == "CLEARED" }),
              clearedIdx + 1 < tokens.count,
              tokens[clearedIdx + 1].uppercased() == "TO" else {
            return Slot(value: nil, confidence: 0.5, validated: false, sourceText: "")
        }

        var clearanceTokens: [String] = []
        var idx = clearedIdx + 2

        while idx < tokens.count {
            let t = tokens[idx]
            if stopWords.contains(t.uppercased()) {
                break
            }
            clearanceTokens.append(t)
            idx += 1
        }

        if clearanceTokens.last?.uppercased() == "AIRPORT" {
            clearanceTokens.removeLast()
        }

        let joinedString = clearanceTokens.joined(separator: " ")
        let value = joinedString.isEmpty ? nil : joinedString
        return Slot(value: value, confidence: 0.7, validated: false, sourceText: value ?? "")
    }

    func extractRoute(text: String) -> Slot<RouteData> {
        let endMarkers = [" MAINTAIN ", " EXPECT ", " DEPARTURE ", " SQUAWK ", " CONTACT "]
        func routeFrom(afterStart startRange: Range<String.Index>) -> String? {
            let after = String(text[startRange.upperBound...])
            var endIndex = after.endIndex
            for marker in endMarkers {
                if let r = after.range(of: marker, options: .caseInsensitive), r.lowerBound < endIndex {
                    endIndex = r.lowerBound
                }
            }
            var route = String(after[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let periodRange = route.range(of: ". ") {
                let beforePeriod = String(route[..<periodRange.lowerBound])
                let lastWord = beforePeriod.split(separator: " ").last.map(String.init) ?? ""
                let isAbbrev = lastWord.count <= 3 && lastWord.allSatisfy { $0.isLetter }
                if !isAbbrev { route = beforePeriod.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            let routeEndTrims = [" CLIMB AND", " DESCEND AND", " EXPECT "]
            for suffix in routeEndTrims {
                if route.uppercased().hasSuffix(suffix.uppercased()) {
                    route = String(route.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
            return route.isEmpty ? nil : route
        }
        func trimAltitudeFromRoute(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.uppercased().hasPrefix("MAINTAIN ") { return "" }
            if let range = s.range(of: " MAINTAIN ", options: .caseInsensitive) {
                return String(s[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return s
        }
        var rawRoute: String?
        if let viaRange = text.range(of: " VIA ", options: .caseInsensitive), let route = routeFrom(afterStart: viaRange) {
            rawRoute = trimAltitudeFromRoute(route)
        } else if let flyDirectRange = text.range(of: " FLY DIRECT ", options: .caseInsensitive) {
            let afterDirect = routeFrom(afterStart: flyDirectRange)
            var routeText = afterDirect.flatMap { $0.isEmpty ? nil : $0 } ?? "DIRECT"
            routeText = trimAltitudeFromRoute(routeText)
            if routeText.isEmpty { routeText = "DIRECT" }
            rawRoute = routeText
        } else if let flyRange = text.range(of: " FLY ", options: .caseInsensitive), let route = routeFrom(afterStart: flyRange) {
            var r = trimAltitudeFromRoute(route)
            if r.isEmpty, text.range(of: " FLY DIRECT ", options: .caseInsensitive) != nil { r = "DIRECT" }
            if !r.isEmpty { rawRoute = r }
        }
        let value = rawRoute.map { RouteData(fixes: [], rawText: $0) }
        let conf = value != nil ? 0.5 + 0.2 : 0.5
        return Slot(value: value, confidence: conf, validated: false, sourceText: rawRoute ?? "")
    }

    func extractAltitude(text: String) -> Slot<AltitudeData> {
        let mantPattern = #"MAINTAIN\s+(?:(FL)(\d+)|FLIGHT\s+LEVEL\s+(\d+)|(\d+))"#
        guard let mant = try? NSRegularExpression(pattern: mantPattern),
              let mm = mant.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return Slot(value: nil, confidence: 0.5, validated: false, sourceText: "")
        }
        var altNum: String?
        var isFL = false
        if mm.numberOfRanges > 2, let r2 = Range(mm.range(at: 2), in: text) {
            altNum = String(text[r2])
            isFL = mm.range(at: 1).location != NSNotFound
        }
        if altNum == nil, mm.numberOfRanges > 3, let r3 = Range(mm.range(at: 3), in: text) {
            altNum = String(text[r3])
            isFL = true
        }
        if altNum == nil, mm.numberOfRanges > 4, let r4 = Range(mm.range(at: 4), in: text) {
            altNum = String(text[r4])
        }
        guard let num = altNum else {
            return Slot(value: nil, confidence: 0.5, validated: false, sourceText: "")
        }
        let flVal = Int(num)
        let useFL = isFL && (flVal ?? 0) >= 180
        let initialFeet: Int? = useFL ? ((flVal ?? 0) * 100) : Int(num)
        var aLine = useFL ? "FL\(num)" : (isFL && (flVal ?? 0) < 180 ? "\((flVal ?? 0) * 100)" : num)
        var expectFeet: Int?
        var gotExpect = false
        let expPattern = #"EXPECT\s+(?:FL|FLIGHT\s+LEVEL)?\s*(\d+)\s+(?:FEET?\s+)?(?:IN\s+)?(\d+)\s+MIN(?:UTE)?S?\s+AFTER\s+DEP(?:ARTURE)?"#
        if let exp = try? NSRegularExpression(pattern: expPattern, options: .caseInsensitive),
           let em = exp.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           em.numberOfRanges >= 3,
           let er1 = Range(em.range(at: 1), in: text),
           let er2 = Range(em.range(at: 2), in: text) {
            let expectAlt = String(text[er1])
            let expectMin = String(text[er2])
            let expIsFL = text.uppercased().contains("FLIGHT LEVEL") || text.contains("FL\(expectAlt)")
            expectFeet = expIsFL ? (Int(expectAlt) ?? 0) * 100 : Int(expectAlt)
            aLine += "  •  Exp \(expIsFL ? "FL" : "")\(expectAlt) \(expectMin)' a.d."
            gotExpect = true
        }
        if !gotExpect,
           let flExp = try? NSRegularExpression(pattern: #"EXPECT\s+FLIGHT\s+LEVEL\s+(\d{4,5})\s*MIN(?:UTE)?S?\s+AFTER\s+DEP(?:ARTURE)?"#, options: .caseInsensitive),
           let fm = flExp.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           fm.numberOfRanges >= 2, let fr = Range(fm.range(at: 1), in: text),
           let merged = Int(text[fr]), (1...59).contains(merged % 100) {
            let expectAltVal = merged / 100
            let expectMinVal = merged % 100
            expectFeet = expectAltVal * 100
            aLine += "  •  Exp FL\(expectAltVal) \(expectMinVal)' a.d."
            gotExpect = true
        }
        if !gotExpect,
           let singleExp = try? NSRegularExpression(pattern: #"EXPECT\s+(\d{4,5})\s*MIN(?:UTE)?S?\s+AFTER\s+DEP(?:ARTURE)?"#, options: .caseInsensitive),
           let sm = singleExp.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           sm.numberOfRanges >= 2, let sr = Range(sm.range(at: 1), in: text),
           let merged = Int(text[sr]), (1...59).contains(merged % 100) {
            let expectAltVal: Int
            let expectMinVal = merged % 100
            let expIsFL: Bool
            if merged >= 18000 {
                expectAltVal = merged / 100
                expIsFL = true
            } else {
                let candidate = (merged % 100 == 10) ? (merged - 10) / 10 : -1
                if candidate >= 5000, candidate <= 11000, candidate % 1000 == 0 {
                    expectAltVal = candidate
                } else {
                    expectAltVal = (merged / 100) * 100
                }
                expIsFL = false
            }
            expectFeet = expIsFL ? expectAltVal * 100 : expectAltVal
            aLine += "  •  Exp \(expIsFL ? "FL" : "")\(expectAltVal) \(expectMinVal)' a.d."
        }
        if !gotExpect,
           let simpleExp = try? NSRegularExpression(pattern: #"EXPECT\s+(?:FL(\d+)|FLIGHT\s+LEVEL\s+(\d+)|(\d+))"#, options: .caseInsensitive),
           let sem = simpleExp.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            var expAlt: String?
            if sem.numberOfRanges > 1, let r1 = Range(sem.range(at: 1), in: text) { expAlt = String(text[r1]) }
            if expAlt == nil, sem.numberOfRanges > 2, let r2 = Range(sem.range(at: 2), in: text) { expAlt = String(text[r2]) }
            if expAlt == nil, sem.numberOfRanges > 3, let r3 = Range(sem.range(at: 3), in: text) { expAlt = String(text[r3]) }
            if let e = expAlt, let val = Int(e) {
                let expIsFL = sem.range(at: 1).location != NSNotFound || sem.range(at: 2).location != NSNotFound
                expectFeet = expIsFL && val >= 180 ? val * 100 : val
                aLine += "  •  Exp \(expIsFL && val >= 180 ? "FL" : "")\(val)"
            }
        }
        let value = AltitudeData(initialFeet: initialFeet, expectFeet: expectFeet, rawText: aLine)
        let conf = 0.5 + 0.2
        return Slot(value: value, confidence: conf, validated: false, sourceText: aLine)
    }

    func extractFrequency(text: String) -> Slot<String> {
        let patterns: [(String, Int)] = [
            (#"DEPARTURE\s+FREQUENCY\s+([\d\s.]+?)(?=\s+SQUAWK|\s+[A-Z]{2,}|\s*$)"#, 1),
            (#"CONTACT\s+DEPARTURE\s+([\d\s.]+?)(?=\s+SQUAWK|\s+[A-Z]{2,}|\s*$)"#, 1),
            (#"OF\s+FREQUENCY\s+(\d{3}\.\d{1,3})"#, 1),
            (#"FREQUENCY\s+([\d\s.]+?)(?=\s+SQUAWK|\s+[A-Z]{2,}|\s*$)"#, 1),
        ]
        for (pattern, group) in patterns {
            if let raw = firstRegexGroup(pattern: pattern, in: text, group: group),
               let freq = normalizeFrequencyCapture(raw) {
                return Slot(value: freq, confidence: 0.5 + 0.2, validated: false, sourceText: raw)
            }
        }
        return Slot(value: nil, confidence: 0.5, validated: false, sourceText: "")
    }

    func extractSquawk(text: String) -> Slot<String> {
        if let s = firstRegexGroup(pattern: #"SQUAWK\s+(\d{4})"#, in: text, group: 1) {
            return Slot(value: s, confidence: 0.5 + 0.2, validated: false, sourceText: s)
        }
        if let s = firstRegexGroup(pattern: #"FREQUENCY\s+\d{3}\.\d{1,3}\s+(\d{4})\b"#, in: text, group: 1) {
            return Slot(value: s, confidence: 0.5 + 0.2, validated: false, sourceText: s)
        }
        return Slot(value: nil, confidence: 0.5, validated: false, sourceText: "")
    }

    func extractVoid(text: String) -> Slot<String> {
        if let v = firstRegexGroup(pattern: #"VOID\s+IF\s+NOT\s+OFF\s+BY\s+(\d{4})"#, in: text, group: 1) {
            return Slot(value: v + " Z", confidence: 0.5 + 0.2, validated: false, sourceText: v)
        }
        if let v = firstRegexGroup(pattern: #"CLEARANCE\s+VOID[^\d]*(\d{4})"#, in: text, group: 1) {
            return Slot(value: v + " Z", confidence: 0.5 + 0.2, validated: false, sourceText: v)
        }
        return Slot(value: nil, confidence: 0.5, validated: false, sourceText: "")
    }

    func extractSpecialInstructions(text: String) -> Slot<String> {
        // No existing extraction for special instructions; return empty slot.
        return Slot(value: nil, confidence: 0.5, validated: false, sourceText: "")
    }

    // MARK: - Helpers (mirror existing CRAFT helpers; no UI)

    private func firstRegexGroup(pattern: String, in text: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        guard match.numberOfRanges > group, let r = Range(match.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    private func normalizeFrequencyCapture(_ raw: String) -> String? {
        let collapsed = raw.replacingOccurrences(of: " ", with: "")
        guard collapsed.range(of: #"^\d{3}\.\d{1,3}$"#, options: .regularExpression) != nil else { return nil }
        return collapsed
    }

    private func formatRouteForDisplay(_ route: String) -> String {
        var r = route
        if let regex = try? NSRegularExpression(pattern: #"(V\d+)([A-Z]{2,})"#) {
            let range = NSRange(r.startIndex..., in: r)
            r = regex.stringByReplacingMatches(in: r, range: range, withTemplate: "$1 $2")
        }
        r = r.replacingOccurrences(of: ",", with: ", ")
        r = r.split(separator: " ").filter { !$0.isEmpty }.joined(separator: " ")
        for prefix in [" VECTORS ", " DIRECT ", " THEN "] {
            if r.uppercased().contains(prefix.uppercased()) {
                r = r.replacingOccurrences(of: prefix, with: " •\(prefix)", options: .caseInsensitive)
            }
        }
        return r.trimmingCharacters(in: .whitespaces)
    }
}
