// ReadbackEngine/Normalizer.swift
// Text normalization and tokenization for ATC transcripts.
// Converts spoken numbers, phonetic alphabet, runway phrases; preserves spans.

import Foundation

/// A token with its range in the original transcript.
public struct TokenWithSpan: Sendable {
    public let value: String
    public let start: Int
    public let end: Int
    public init(value: String, start: Int, end: Int) {
        self.value = value
        self.start = start
        self.end = end
    }
}

/// Result of normalization: normalized string and tokens with spans.
public struct NormalizerResult: Sendable {
    public let normalizedText: String
    public let tokens: [TokenWithSpan]
    public let foldedTokens: [String]  // numbers folded (e.g. "one two eight point seven" -> "128.7")
    /// Each folded token with its span in the original transcript (start, end).
    public let foldedTokenSpans: [(String, Int, Int)]
}

private let digitMap: [String: String] = [
    "zero": "0", "one": "1", "two": "2", "three": "3", "tree": "3", "thiry": "3", "thirty": "3",
    "four": "4", "fower": "4", "five": "5", "fife": "5", "six": "6", "seven": "7", "eight": "8",
    "nine": "9", "niner": "9", "hundred": "", "thousand": ""
]

private let phoneticMap: [String: String] = [
    "alpha": "A", "bravo": "B", "charlie": "C", "delta": "D", "echo": "E", "foxtrot": "F",
    "golf": "G", "hotel": "H", "india": "I", "juliet": "J", "kilo": "K", "lima": "L",
    "mike": "M", "november": "N", "oscar": "O", "papa": "P", "quebec": "Q", "romeo": "R",
    "sierra": "S", "tango": "T", "uniform": "U", "victor": "V", "whiskey": "W", "xray": "X",
    "yankee": "Y", "zulu": "Z"
]

private let runwayWords: Set<String> = ["left", "right", "center", "centre", "l", "r", "c"]

public enum Normalizer {

    /// Normalize transcript: lowercase, collapse spaces, then apply number/phonetic/runway rules.
    public static func normalize(_ transcript: String) -> NormalizerResult {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalized = trimmed.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
        while normalized.contains("  ") {
            normalized = normalized.replacingOccurrences(of: "  ", with: " ")
        }

        let tokensWithSpans = tokenizeWithSpans(normalized)
        let tokenStrings = tokensWithSpans.map { $0.value }

        // 1) Try runway phrase: "runway" followed by digits + optional left/right/center
        var folded = foldRunwayPhrases(tokenStrings, tokensWithSpans)
        // 2) Fold spoken numbers (frequency / heading / altitude style)
        folded = foldSpokenNumbers(folded)
        // 3) Fold phonetic sequences into letters
        folded = foldPhoneticSequences(folded)

        let foldedText = folded.joined(separator: " ")
        let ranges = spanRangesForFoldedTokens(originalTokens: tokensWithSpans, foldedCount: folded.count)
        let foldedSpans = zip(folded, ranges).map { ($0.0, $0.1.0, $0.1.1) }
        return NormalizerResult(normalizedText: foldedText, tokens: tokensWithSpans, foldedTokens: folded, foldedTokenSpans: foldedSpans)
    }

    private static func spanRangesForFoldedTokens(originalTokens: [TokenWithSpan], foldedCount: Int) -> [(Int, Int)] {
        guard foldedCount > 0, !originalTokens.isEmpty else { return [] }
        if foldedCount >= originalTokens.count {
            return originalTokens.prefix(foldedCount).map { ($0.start, $0.end) }
        }
        var ranges: [(Int, Int)] = []
        var idx = 0
        let chunk = originalTokens.count / foldedCount
        var remainder = originalTokens.count % foldedCount
        for _ in 0..<foldedCount {
            let size = chunk + (remainder > 0 ? 1 : 0)
            if remainder > 0 { remainder -= 1 }
            guard idx < originalTokens.count else { break }
            let start = originalTokens[idx].start
            let endIdx = min(idx + size, originalTokens.count) - 1
            let end = originalTokens[endIdx].end
            ranges.append((start, end))
            idx += size
        }
        return ranges
    }

    private static func tokenizeWithSpans(_ text: String) -> [TokenWithSpan] {
        var result: [TokenWithSpan] = []
        var i = text.startIndex
        while i < text.endIndex {
            while i < text.endIndex && text[i].isWhitespace { i = text.index(after: i) }
            guard i < text.endIndex else { break }
            let start = text.distance(from: text.startIndex, to: i)
            var j = i
            while j < text.endIndex, !text[j].isWhitespace { j = text.index(after: j) }
            let end = text.distance(from: text.startIndex, to: j)
            let word = String(text[i..<j])
            result.append(TokenWithSpan(value: word, start: start, end: end))
            i = j
        }
        return result
    }

    private static func foldRunwayPhrases(_ tokens: [String], _ spans: [TokenWithSpan]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i].lowercased()
            if t == "runway" && i + 1 < tokens.count {
                var digits = ""
                var j = i + 1
                while j < tokens.count {
                    let w = tokens[j].lowercased()
                    if let d = digitMap[w] {
                        digits += d
                        j += 1
                    } else if w.count == 1, let c = w.first, c.isNumber {
                        digits += w
                        j += 1
                    } else if runwayWords.contains(w) {
                        if w == "left" || w == "l" { digits += "L" }
                        else if w == "right" || w == "r" { digits += "R" }
                        else if w == "center" || w == "centre" || w == "c" { digits += "C" }
                        j += 1
                        break
                    } else { break }
                }
                if !digits.isEmpty {
                    out.append(digits)
                    i = j
                    continue
                }
            }
            out.append(tokens[i])
            i += 1
        }
        return out
    }

    private static func foldSpokenNumbers(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < tokens.count {
            var numeric = ""
            var j = i
            while j < tokens.count {
                let w = tokens[j].lowercased()
                if let d = digitMap[w] {
                    numeric += d
                    j += 1
                } else if w.count == 1, let c = w.first, c.isNumber {
                    numeric += String(c)
                    j += 1
                } else if w == "point" && !numeric.isEmpty {
                    numeric += "."
                    j += 1
                } else { break }
            }
            if numeric.count >= 1 && j > i {
                result.append(numeric)
                i = j
            } else {
                result.append(tokens[i])
                i += 1
            }
        }
        return result
    }

    private static func foldPhoneticSequences(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < tokens.count {
            var letters = ""
            var j = i
            while j < tokens.count, let letter = phoneticMap[tokens[j].lowercased()] {
                letters += letter
                j += 1
            }
            if letters.count >= 2 {
                result.append(letters)
                i = j
            } else if letters.count == 1 {
                result.append(letters)
                i = j
            } else {
                result.append(tokens[i])
                i += 1
            }
        }
        return result
    }
}
