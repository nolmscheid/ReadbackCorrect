import Foundation

/// Normalizes ATC/aviation speech for parsing and display.
/// Based on FAA Order 7110.65 phraseology and common ASR misrecognitions.
/// Apply before intent parsing and in tokenization so runway/numbers match.
struct AviationNormalizer {

    /// Normalize ATC/aviation speech. When waypointIds is non-empty, phonetic spellings (e.g. "Golf Echo Papa") that match a waypoint ID are replaced with that ID (e.g. "GEP").
    static func normalize(_ text: String, waypointIds: Set<String> = []) -> String {
        var result = text.lowercased()

        // Multi-word corrections (run before single-word so "holt short" → "hold short")
        // Includes fast-speech and noisy-radio variants (mushed words, dropped syllables).
        let phraseCorrections: [String: String] = [
            "holt short": "hold short",
            "hold shirt": "hold short",
            "hold short of": "hold short of",
            "hold short of runway": "hold short of runway",
            "holdshort": "hold short",
            "holdshort of": "hold short of",
            "hold short of run way": "hold short of runway",
            "run way": "runway",
            "clear to land": "cleared to land",
            "clear the land": "cleared to land",
            "cleared the land": "cleared to land",
            "cleared two": "cleared to",
            "clear two": "cleared to",
            "cleared the ": "cleared to ",
            "clear the ": "cleared to ",
            "clear land": "cleared to land",
            "clearland": "cleared to land",
            "cleared land": "cleared to land",
            "cleared to lan": "cleared to land",
            "clear to lan": "cleared to land",
            "cleared for landing": "cleared to land",
            "cleared to landing": "cleared to land",
            "clear for takeoff": "cleared for takeoff",
            "cleared for take off": "cleared for takeoff",
            "cleared to takeoff": "cleared for takeoff",
            "cleared to take off": "cleared for takeoff",
            "clear to takeoff": "cleared for takeoff",
            "clear to take off": "cleared for takeoff",
            "cleared takeoff": "cleared for takeoff",
            "cleared take off": "cleared for takeoff",
            "clear takeoff": "cleared for takeoff",
            "clear take off": "cleared for takeoff",
            "cleartakeoff": "cleared for takeoff",
            "cleartake off": "cleared for takeoff",
            "line up and hold": "line up and wait",
            "lineup and wait": "line up and wait",
            "lineup and weight": "line up and wait",
            "lineupandwait": "line up and wait",
            "line up and weight": "line up and wait",
            "vialpha": "via alpha",
            "viaalfa": "via alpha",
            // ASR often hears "via" as "the" in taxi instructions
            "taxi the ": "taxi via ",
            " taxi the ": " taxi via ",
            " via the ": " via ",
            "continue on the ": "continue on ",
            "proceed on the ": "proceed on ",
            "flightlevel": "flight level",
            "after dep": "after departure",
            "main tan": "maintain",
            "climb and mantain": "climb and maintain",
            "claim and maintain": "climb and maintain",
            "claim and maintained": "climb and maintain",
            "descend and mantain": "descend and maintain",
            "free two": "three two",
            "tree two": "three two",
            "fife": "five",
            "niner": "nine",
            "tree": "three",
            "thirt": "thirty",
            "fower": "four",
            "wun": "one",
            "niner thousand": "9000",
            "nine thousand": "9000",
            "fife thousand": "5000",
            "five thousand": "5000",
            "tree thousand": "3000",
            "three thousand": "3000",
            "one thousand": "1000",
            "two thousand": "2000",
            "four thousand": "4000",
            "six thousand": "6000",
            "seven thousand": "7000",
            "eight thousand": "8000",
            "ten thousand": "10000",
            "climb and maintain": "climb and maintain",
            "climb and maintained": "climb and maintain",
            "descend and maintain": "descend and maintain",
            "descend and maintained": "descend and maintain",
            "run runway": "hold short runway",
            "run runways": "hold short runway",
            "heading to 70": "heading 270",
            "heading to 90": "heading 090",
            // Do NOT add "hold runway" → "hold short runway": "line up and hold runway 13" uses "hold" = hold on runway (i.e. line up and wait). IFR also uses "hold" for holding patterns.
            "hold of runway": "hold short of runway",
            "go round": "go around",
            "context center": "contact center",
            "context tower": "contact tower",
            "context departure": "contact departure",
            "context approach": "contact approach",
            "context ground": "contact ground",
            "moniter": "monitor",
            "may day": "mayday",
            "claim": "climb",
            "climate": "climb",
            "climate and maintain": "climb and maintain",
            "maintain bfr": "maintain vfr",
            "maintain gfr": "maintain vfr",
            "maintain fr": "maintain vfr",
            // IFR route: ATC says "Victor 2 3" / "Victor twenty three" → V23; "Oscar Charlie November" → OCN
            "victor 2 3": "v23",
            "victor 23": "v23",
            "victor 1 2": "v12",
            "victor 1 2 3": "v123",
            "victor 20 3": "v23",   // "Victor twenty three"
            "oscar charlie november": "ocn",
        ]

        for (wrong, correct) in phraseCorrections {
            result = result.replacingOccurrences(of: wrong, with: correct)
        }

        // Collapse ASR stutter: "landd", "landdd", etc. → "land" (so mono text and parsing both show "land")
        while result.contains("landd") {
            result = result.replacingOccurrences(of: "landd", with: "land")
        }

        // ASR artifacts: "X thousand ten minutes" often becomes "X001 0 minutes" or "X010 minutes" (altitude + 10 min)
        let expectAltMinFixes: [(String, String)] = [
            ("5001 0 minutes", "5000 10 minutes"), ("5001 0 minute", "5000 10 minutes"), ("5001  0 minutes", "5000 10 minutes"), ("5001 0 min", "5000 10 min"),
            ("5010 minutes", "5000 10 minutes"), ("5010 min", "5000 10 min"),
            ("6001 0 minutes", "6000 10 minutes"), ("6001 0 minute", "6000 10 minutes"), ("6001  0 minutes", "6000 10 minutes"), ("6001 0 min", "6000 10 min"),
            ("6010 minutes", "6000 10 minutes"), ("6010 min", "6000 10 min"),
            ("7001 0 minutes", "7000 10 minutes"), ("7001 0 minute", "7000 10 minutes"), ("7001  0 minutes", "7000 10 minutes"), ("7001 0 min", "7000 10 min"),
            ("7010 minutes", "7000 10 minutes"), ("7010 min", "7000 10 min"),
            ("8001 0 minutes", "8000 10 minutes"), ("8001 0 minute", "8000 10 minutes"), ("8001  0 minutes", "8000 10 minutes"), ("8001 0 min", "8000 10 min"),
            ("8010 minutes", "8000 10 minutes"), ("8010 min", "8000 10 min"),
            ("9001 0 minutes", "9000 10 minutes"), ("9001 0 minute", "9000 10 minutes"), ("9001  0 minutes", "9000 10 minutes"), ("9001 0 min", "9000 10 min"),
            ("9010 minutes", "9000 10 minutes"), ("9010 min", "9000 10 min"),
            ("11001 0 minutes", "11000 10 minutes"), ("11001 0 minute", "11000 10 minutes"), ("11001 0 min", "11000 10 min"),
            ("11010 minutes", "11000 10 minutes"), ("11010 min", "11000 10 min"),
        ]
        for (wrong, correct) in expectAltMinFixes {
            result = result.replacingOccurrences(of: wrong, with: correct)
        }
        // ASR sometimes merges "8000 ten" into one number "80010 minutes"; split to "8000 10 minutes"
        let mergedExpectFixes: [(String, String)] = [
            ("50010 minutes", "5000 10 minutes"), ("50010 min", "5000 10 min"),
            ("60010 minutes", "6000 10 minutes"), ("60010 min", "6000 10 min"),
            ("70010 minutes", "7000 10 minutes"), ("70010 min", "7000 10 min"),
            ("80010 minutes", "8000 10 minutes"), ("80010 min", "8000 10 min"),
            ("90010 minutes", "9000 10 minutes"), ("90010 min", "9000 10 min"),
            ("100010 minutes", "10000 10 minutes"), ("100010 min", "10000 10 min"),
            ("110010 minutes", "11000 10 minutes"), ("110010 min", "11000 10 min"),
        ]
        for (wrong, correct) in mergedExpectFixes {
            result = result.replacingOccurrences(of: wrong, with: correct)
        }

        // ASR often runs "departure" into itself: "departurearture", "departurear-ture", or doubles it
        let departureFixes = [
            "departurearture": "departure",
            "departurear-ture": "departure",
            "departurear ture": "departure",
            "departure departure": "departure",
        ]
        for (wrong, correct) in departureFixes {
            result = result.replacingOccurrences(of: wrong, with: correct)
        }

        // ASR merges "Expect 10,000 ten minutes" → "10 001 0 minutes" or similar
        result = result.replacingOccurrences(of: "10 001 0 minutes", with: "10000 10 minutes")
        result = result.replacingOccurrences(of: "10 001 0 minute", with: "10000 10 minutes")
        result = result.replacingOccurrences(of: "10 001 0 min", with: "10000 10 min")

        // ASR merges "Departure frequency 119.1. Squawk 4463" → "FREQUENCY 119.14463" (no space); split so F and T parse
        if let freqSquawk = try? NSRegularExpression(pattern: #"(\d{3}\.\d+?)(\d{4})\b"#) {
            result = freqSquawk.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "$1 $2")
        }

        // "Victor 2 3" / "Victor 4 5" etc. → V23, V45 (any Victor + space-separated digits)
        result = normalizeVictorAirway(result)

        // Single-word / common ASR misrecognitions (FAA/ICAO + fast speech + noisy radio)
        let wordCorrections: [String: String] = [
            "holt": "hold",
            "shirt": "short",
            "runways": "runway",
            "alfa": "alpha",
            "alpa": "alpha",
            "juliet": "juliett",
            "maintained": "maintain",
            "mantain": "maintain",
            "squak": "squawk",
            "quack": "squawk",
            "sqaw": "squawk",
            "squaw": "squawk",
            "frecuency": "frequency",
            "tutu": "22",
            "claim": "climb",
            "climate": "climb",
            "klein": "climb",
            "decedent": "descend",
            "descendant": "descend",
            "bfr": "vfr",
            "gfr": "vfr",
            "taxy": "taxi",
            "hedding": "heading",
            "contax": "contact",
            "moniter": "monitor",
            "boyd": "void",
        ]

        let words = result.split(separator: " ").map { String($0) }
        result = words.map { wordCorrections[$0] ?? $0 }.joined(separator: " ")

        // Convert spoken numbers to digits (aviation: niner→9, fife→5, tree→3 already handled above)
        result = convertNumbers(result)

        // ASR often outputs "9 1000" or "9 or 1000" for "niner thousand" — combine to 9000 (and similar)
        result = combineDigitThousand(result)

        // ASR often mishears "niner thousand" as "900 000" or "900000" — fix to 9000 (and similar)
        result = fixAltitudeThousandsMisrecognition(result)

        // "Flight level three five zero" → "flight level 350" (combine digit sequence after "flight level")
        result = normalizeFlightLevel(result)

        // Runway designators: "24 left" → "24l", "24 right" → "24r", "24 center" → "24c" (so cards show 24L, 24R, 24C)
        result = normalizeRunwaySuffixes(result)

        // Waypoint spelling → code only when the code is in the waypoint DB. Common fixes (e.g. GEP in MSP area) are often said as "Direct GEP"; when ATC does spell, we only convert to the code if it's a known fix.
        if !waypointIds.isEmpty {
            result = replacePhoneticWaypoints(result, waypointIds: waypointIds)
        }

        return result
    }

    /// ICAO phonetic word → single letter (lowercase key for matching).
    private static let phoneticToLetter: [String: String] = [
        "alfa": "A", "alpha": "A", "bravo": "B", "charlie": "C", "delta": "D", "echo": "E",
        "foxtrot": "F", "golf": "G", "hotel": "H", "india": "I", "indigo": "I", "juliett": "J", "juliet": "J", "juliette": "J",
        "kilo": "K", "lima": "L", "mike": "M", "november": "N", "oscar": "O", "papa": "P",
        "quebec": "Q", "romeo": "R", "sierra": "S", "tango": "T", "uniform": "U", "victor": "V",
        "whiskey": "W", "whisky": "W", "xray": "X", "x-ray": "X", "yankee": "Y", "zulu": "Z",
    ]

    /// Replace sequences that spell a known waypoint ID with that ID. Handles (1) phonetic words ("golf echo papa" → GEP) and (2) spaced single letters ("G E P" → GEP). Only replaces when the spelled ID is in waypointIds (database match).
    private static func replacePhoneticWaypoints(_ text: String, waypointIds: Set<String>) -> String {
        let idsUpper = Set(waypointIds.map { $0.uppercased() })
        let maxLen = idsUpper.map(\.count).max() ?? 0
        guard maxLen >= 1 else { return text }
        var words = text.split(separator: " ").map { String($0) }
        var i = 0
        var out: [String] = []
        while i < words.count {
            let wordNorm = words[i].lowercased().trimmingCharacters(in: .punctuationCharacters)
            var letter: String? = phoneticToLetter[wordNorm]
            if letter == nil, wordNorm.count == 1, let c = wordNorm.first, c.isLetter {
                letter = String(c).uppercased()
            }
            if letter == nil {
                out.append(words[i])
                i += 1
                continue
            }
            var spelled = letter!
            var j = i + 1
            while j < words.count {
                let nextNorm = words[j].lowercased().trimmingCharacters(in: .punctuationCharacters)
                guard let nextLetter = phoneticToLetter[nextNorm] else { break }
                spelled += nextLetter
                j += 1
                if spelled.count > maxLen { break }
            }
            // Prefer longest match that is a known waypoint (e.g. GEP over G, E, P)
            var bestEnd = i
            var bestId: String?
            for len in (1 ... min(spelled.count, maxLen)).reversed() {
                let prefix = String(spelled.prefix(len))
                if idsUpper.contains(prefix) {
                    bestId = prefix
                    bestEnd = i + len - 1
                    break
                }
            }
            if let id = bestId {
                out.append(id)
                i = bestEnd + 1
            } else {
                out.append(words[i])
                i += 1
            }
        }
        return out.joined(separator: " ")
    }

    /// "9 1000" or "9 or 1000" (ASR for "niner thousand") → "9000"; same for 1–9.
    private static func combineDigitThousand(_ text: String) -> String {
        let pairs: [(String, String)] = [
            ("9 or 1000", "9000"), ("9 1000", "9000"),
            ("8 or 1000", "8000"), ("8 1000", "8000"),
            ("7 or 1000", "7000"), ("7 1000", "7000"),
            ("6 or 1000", "6000"), ("6 1000", "6000"),
            ("5 or 1000", "5000"), ("5 1000", "5000"),
            ("4 or 1000", "4000"), ("4 1000", "4000"),
            ("3 or 1000", "3000"), ("3 1000", "3000"),
            ("2 or 1000", "2000"), ("2 1000", "2000"),
            ("1 or 1000", "1000"), ("1 1000", "1000"),
        ]
        var result = text
        for (wrong, correct) in pairs {
            result = result.replacingOccurrences(of: wrong, with: correct)
        }
        return result
    }

    /// ASR often outputs "900 000" or "900000" for "niner thousand". Replace with 9000 (and 5000, 3000, etc.).
    private static func fixAltitudeThousandsMisrecognition(_ text: String) -> String {
        let fixes: [(String, String)] = [
            ("900000", "9000"), ("900 000", "9000"),
            ("500000", "5000"), ("500 000", "5000"),
            ("300000", "3000"), ("300 000", "3000"),
            ("400000", "4000"), ("400 000", "4000"),
            ("100000", "1000"), ("100 000", "1000"),
            ("200000", "2000"), ("200 000", "2000"),
            ("600000", "6000"), ("600 000", "6000"),
            ("700000", "7000"), ("700 000", "7000"),
            ("800000", "8000"), ("800 000", "8000"),
        ]
        var result = text
        for (wrong, correct) in fixes {
            result = result.replacingOccurrences(of: wrong, with: correct)
        }
        return result
    }

    /// "flight level 3 5 0" → "flight level 350" so altitude parser can match FL (all occurrences).
    private static func normalizeFlightLevel(_ text: String) -> String {
        let pattern = #"flight\s+level\s+((?:\d\s*)+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        var result = ""
        var pos = text.startIndex
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 2,
                  let fullRange = Range(m.range, in: text),
                  let capRange = Range(m.range(at: 1), in: text) else { return }
            let digits = String(text[capRange]).replacingOccurrences(of: " ", with: "")
            guard !digits.isEmpty else { return }
            result += text[pos ..< fullRange.lowerBound]
            result += "flight level " + digits
            pos = fullRange.upperBound
        }
        result += text[pos...]
        return result.isEmpty ? text : result
    }

    /// Replace "(\d{1,2}) left|right|center" with "(\d{1,2})l|r|c" for runway parsing (cards show 24L, 24R, 24C).
    private static func normalizeRunwaySuffixes(_ text: String) -> String {
        let pattern = #"(\d{1,2})\s+(left|right|center)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        let suffixMap: [String: String] = ["left": "l", "right": "r", "center": "c"]
        var result = ""
        var pos = text.startIndex
        let range = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 3,
                  let fullRange = Range(m.range, in: text),
                  let numRange = Range(m.range(at: 1), in: text),
                  let wordRange = Range(m.range(at: 2), in: text) else { return }
            let word = String(text[wordRange]).lowercased()
            guard let letter = suffixMap[word] else { return }
            result += text[pos ..< fullRange.lowerBound]
            result += String(text[numRange]) + letter
            pos = fullRange.upperBound
        }
        result += text[pos...]
        return result
    }

    /// "Victor 2 3" / "Victor 23" / "Victor 4 5 6" → V23, V456 (Victor airway + digits, collapse spaces).
    private static func normalizeVictorAirway(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\bvictor\s+((?:\d\s*)+)"#, options: .caseInsensitive) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        var result = ""
        var pos = text.startIndex
        for match in matches {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range, in: text),
                  let capRange = Range(match.range(at: 1), in: text) else { continue }
            result += text[pos ..< fullRange.lowerBound]
            let digits = String(text[capRange]).replacingOccurrences(of: " ", with: "")
            result += "v" + digits
            pos = fullRange.upperBound
        }
        result += text[pos...]
        return result.isEmpty ? text : result
    }

    private static func convertNumbers(_ text: String) -> String {
        let numberMap: [String: String] = [
            "zero": "0",
            "one": "1",
            "two": "2",
            "three": "3",
            "four": "4",
            "five": "5",
            "six": "6",
            "seven": "7",
            "eight": "8",
            "nine": "9",
            "ten": "10",
            "twenty": "20",
            "thirty": "30",
            "forty": "40",
            "fifty": "50",
            "hundred": "100",
            "thousand": "1000",
        ]

        let words = text.split(separator: " ").map { String($0) }
        var converted: [String] = []
        for word in words {
            if let digit = numberMap[word] {
                converted.append(digit)
            } else {
                converted.append(word)
            }
        }
        return converted.joined(separator: " ")
    }
}
