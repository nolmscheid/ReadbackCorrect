// ReadbackEngine/Normalization/TaxiwayRepair.swift
// Repairs SR variants around "via <taxiway>" so intent extraction sees canonical " VIA <letter> ".
// Only runs when TAXI is present; does not change IFR/hold-at-fix content.

import Foundation

/// NATO phonetic → single letter for taxiway display.
private let natoToLetter: [String: String] = [
    "ALPHA": "A", "ALFA": "A", "BRAVO": "B", "CHARLIE": "C", "CHARLEY": "C",
    "DELTA": "D", "ECHO": "E", "FOXTROT": "F", "GOLF": "G", "HOTEL": "H",
    "INDIA": "I", "JULIET": "J", "JULIETTE": "J", "KILO": "K", "LIMA": "L",
    "MIKE": "M", "NOVEMBER": "N", "OSCAR": "O", "PAPA": "P", "QUEBEC": "Q",
    "ROMEO": "R", "SIERRA": "S", "TANGO": "T", "UNIFORM": "U", "VICTOR": "V",
    "WHISKEY": "W", "XRAY": "X", "X-RAY": "X", "YANKEE": "Y", "ZULU": "Z",
]

/// Phrases to canonicalize to " VIA " when they appear before a taxiway (only in taxi context).
private let viaLikePhrases: [(String, Int)] = [
    ("OF THE", 2),
    ("VEE AH", 2),
    ("THE", 1),
    ("OF", 1),
]

private func isTaxiwayToken(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespaces).uppercased()
    if t.isEmpty { return false }
    if t.count == 1, t.first!.isLetter { return true }
    return natoToLetter[t] != nil
}

private func asTaxiwayLetter(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespaces).uppercased()
    if t.count == 1, t.first!.isLetter { return t }
    return natoToLetter[t]
}

/// Repair SR variants ("the delta", "of the delta", "vee ah delta") to canonical " VIA D ".
/// Only touches text when TAXI is present; only normalizes phrases in taxi context (within ~10 tokens after TAXI or when "TAXI TO" exists).
/// Returns uppercase with single spaces. Logs only when a change was made.
public func repairTaxiwayPhrases(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    guard trimmed.uppercased().contains("TAXI") else { return trimmed }
    var work = trimmed.uppercased()
    while work.contains("  ") { work = work.replacingOccurrences(of: "  ", with: " ") }
    let tokens = work.split(separator: " ").map { String($0) }
    guard let taxiIdx = tokens.firstIndex(where: { $0 == "TAXI" }) else { return work }

    let hasTaxiTo = work.contains("TAXI TO")
    let taxiRegionEnd = min(taxiIdx + 10, tokens.count)
    var out: [String] = []
    var i = 0
    var changed = false

    while i < tokens.count {
        let inTaxiRegion = (i >= taxiIdx && i < taxiRegionEnd) || hasTaxiTo
        var replaced = false
        if inTaxiRegion, i + 1 < tokens.count {
            for (phrase, phraseWordCount) in viaLikePhrases {
                let phraseTokens = phrase.split(separator: " ").map { String($0) }
                guard phraseTokens.count == phraseWordCount else { continue }
                let match = (0..<phraseWordCount).allSatisfy { j in
                    i + j < tokens.count && tokens[i + j] == phraseTokens[j]
                }
                let nextIdx = i + phraseWordCount
                guard match, nextIdx < tokens.count, isTaxiwayToken(tokens[nextIdx]) else { continue }
                out.append("VIA")
                if let letter = asTaxiwayLetter(tokens[nextIdx]) {
                    out.append(letter)
                    changed = true
                } else {
                    out.append(tokens[nextIdx])
                }
                i = nextIdx + 1
                replaced = true
                break
            }
        }
        if !replaced {
            if inTaxiRegion, tokens[i] == "VIA", i + 1 < tokens.count, isTaxiwayToken(tokens[i + 1]) {
                out.append("VIA")
                out.append(asTaxiwayLetter(tokens[i + 1]) ?? tokens[i + 1])
                if asTaxiwayLetter(tokens[i + 1]) != nil { changed = true }
                i += 2
            } else {
                out.append(tokens[i])
                i += 1
            }
        }
    }

    let result = out.joined(separator: " ")
    if changed {
        ReadbackDebugLog.log("taxiwayRepair: before=\"\(trimmed.prefix(80))\(trimmed.count > 80 ? "…" : "")\" after=\"\(result.prefix(80))\(result.count > 80 ? "…" : "")\"")
    }
    return result
}
