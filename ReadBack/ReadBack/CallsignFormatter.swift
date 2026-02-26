import Foundation

enum CallsignFormatter {

    // MARK: - Public API

    /// Normalizes user input like "n641cc", "641cc" -> "N641CC"
    static func normalizeUserCallsign(_ input: String) -> String {
        let cleaned = input
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty { return "" }
        if cleaned.hasPrefix("N") { return cleaned }
        return "N" + cleaned
    }

    /// Returns true if transmission contains the callsign in common variants
    static func matchesTransmission(_ transmissionUpper: String, desiredUserInput: String) -> Bool {
        let t = compressSpokenCallsigns(in: transmissionUpper.uppercased())
        let desired = normalizeUserCallsign(desiredUserInput).uppercased()
        if desired.isEmpty { return true }

        let desiredNoN = desired.hasPrefix("N") ? String(desired.dropFirst()) : desired

        // Direct contains
        if t.contains(desired) { return true }
        if t.contains(desiredNoN) { return true }

        // Last-3 shorthand (e.g., "1CC", "CC" not supported yet, but "1CC" is)
        // We’ll treat last 3 of non-N callsign as match if present as a token.
        if desiredNoN.count >= 3 {
            let last3 = String(desiredNoN.suffix(3))
            if containsToken(t, token: last3) { return true }
        }

        return false
    }

    /// Compresses spoken callsigns in the text:
    /// "NOVEMBER SIX FOUR ONE CHARLIE CHARLIE" -> "N641CC"
    /// "SIX FOUR ONE CHARLIE CHARLIE" -> "641CC"
    static func compressSpokenCallsigns(in textUpper: String) -> String {
        let upper = textUpper.uppercased()
        let tokens = upper
            .replacingOccurrences(of: #"[^\w\s\.]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { String($0) }

        // Try to find sequences that look like [NOVEMBER] <digits...> <letters...>
        // We'll scan and build a compressed version.
        var out: [String] = []
        var i = 0

        while i < tokens.count {
            let tok = tokens[i]

            // Optional leading NOVEMBER -> "N"
            var hasNPrefix = false
            var j = i
            if tok == "NOVEMBER" || tok == "NOV" {
                hasNPrefix = true
                j += 1
            }

            // Collect digits (spoken or numeric) - expect at least 1 digit
            var digits = ""
            while j < tokens.count {
                if let d = spokenDigit(tokens[j]) {
                    digits.append(d)
                    j += 1
                    continue
                }
                if tokens[j].allSatisfy(\.isNumber) {
                    digits.append(contentsOf: tokens[j])
                    j += 1
                    continue
                }
                break
            }

            // Collect letters (phonetic or letter tokens)
            var letters = ""
            while j < tokens.count {
                if let l = phoneticLetter(tokens[j]) {
                    letters.append(l)
                    j += 1
                    continue
                }
                // Single letter
                if tokens[j].count == 1, let c = tokens[j].first, c.isLetter {
                    letters.append(c)
                    j += 1
                    continue
                }
                break
            }

            // If it looks like a callsign fragment, emit it compressed
            if !digits.isEmpty, !letters.isEmpty {
                let compressed = (hasNPrefix ? "N" : "") + digits + letters
                out.append(compressed)
                i = j
                continue
            }

            // Otherwise, keep token as-is
            out.append(tokens[i])
            i += 1
        }

        return out.joined(separator: " ")
    }

    /// Removes callsign from the displayed body text when matched (so it doesn’t repeat the green header)
    static func removeCallsignFromDisplayText(
        _ textUpper: String,
        desiredUserInput: String,
        onlyIfMatched matched: Bool
    ) -> String {

        let t0 = compressSpokenCallsigns(in: textUpper.uppercased())
        guard matched else { return normalizeSpaces(t0) }

        let desired = normalizeUserCallsign(desiredUserInput).uppercased()
        let desiredNoN = desired.hasPrefix("N") ? String(desired.dropFirst()) : desired

        var t = t0
        // Remove as token occurrences
        t = removeToken(t, token: desired)
        t = removeToken(t, token: desiredNoN)

        return normalizeSpaces(t)
    }

    // MARK: - Helpers

    private static func normalizeSpaces(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsToken(_ s: String, token: String) -> Bool {
        let pattern = #"(?<![A-Z0-9])\#(NSRegularExpression.escapedPattern(for: token))(?![A-Z0-9])"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(s.startIndex..., in: s)
        return re.firstMatch(in: s, options: [], range: range) != nil
    }

    private static func removeToken(_ s: String, token: String) -> String {
        guard !token.isEmpty else { return s }
        let pattern = #"(?<![A-Z0-9])\#(NSRegularExpression.escapedPattern(for: token))(?![A-Z0-9])"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        let result = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")
        return result
    }

    private static func spokenDigit(_ t: String) -> String? {
        switch t {
        case "ZERO": return "0"
        case "ONE": return "1"
        case "TWO": return "2"
        case "THREE", "TREE": return "3"
        case "FOUR": return "4"
        case "FIVE": return "5"
        case "SIX": return "6"
        case "SEVEN": return "7"
        case "EIGHT": return "8"
        case "NINE", "NINER": return "9"
        default: return nil
        }
    }

    private static func phoneticLetter(_ t: String) -> Character? {
        switch t {
        case "ALPHA", "ALFA": return "A"
        case "BRAVO": return "B"
        case "CHARLIE": return "C"
        case "DELTA": return "D"
        case "ECHO": return "E"
        case "FOXTROT": return "F"
        case "GOLF": return "G"
        case "HOTEL": return "H"
        case "INDIA": return "I"
        case "JULIET", "JULIETT": return "J"
        case "KILO": return "K"
        case "LIMA": return "L"
        case "MIKE": return "M"
        case "NOVEMBER": return "N"
        case "OSCAR": return "O"
        case "PAPA": return "P"
        case "QUEBEC": return "Q"
        case "ROMEO": return "R"
        case "SIERRA": return "S"
        case "TANGO": return "T"
        case "UNIFORM": return "U"
        case "VICTOR": return "V"
        case "WHISKEY": return "W"
        case "XRAY", "X-RAY": return "X"
        case "YANKEE": return "Y"
        case "ZULU": return "Z"
        default: return nil
        }
    }
}
