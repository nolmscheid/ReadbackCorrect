// ReadbackEngine/Normalization/AviationRepair.swift
// Repairs SR variants for landing clearance to canonical "CLEARED TO LAND RUNWAY <n>".
// Only runs when aviation context is strong: LAND + runway designator + CLEAR/CLEARED in same phrase.

import Foundation

/// CLEAR or CLEARED, optional YOUR/TO/FOR, LAND, optional RUNWAY/RWY, then runway token. Capture 1=clear word, 2=mid, 3=RUNWAY/RWY, 4=runway token.
private let clearedLandVariantPattern = #"(CLEAR|CLEARED)\s+(YOUR|TO|FOR)?\s*LAND\s+((?:RUNWAY|RWY)\s+)?(\d{1,2}[LRC]?)"#

/// Normalizes landing clearance SR variants to "CLEARED TO LAND RUNWAY <n>" (or "CLEARED TO LAND <n>" if no RUNWAY/RWY).
/// Only applies when string contains LAND, a runway designator (RUNWAY or RWY + runway token), and CLEAR or CLEARED.
/// Never affects non-ATC text; single pass, no global replace.
public func repairATCPhrases(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    var work = trimmed.uppercased()
    while work.contains("  ") { work = work.replacingOccurrences(of: "  ", with: " ") }

    guard work.contains("LAND") else { return work }
    guard work.contains("CLEAR") || work.contains("CLEARED") else { return work }
    let hasRunwayDesignator = work.contains("RUNWAY") || work.contains("RWY")
    guard hasRunwayDesignator else { return work }

    guard let regex = try? NSRegularExpression(pattern: clearedLandVariantPattern) else { return work }

    let range = NSRange(work.startIndex..., in: work)
    guard let match = regex.firstMatch(in: work, options: [], range: range) else { return work }

    let rwyDesignatorRange = match.range(at: 3).location != NSNotFound ? Range(match.range(at: 3), in: work) : nil
    guard let rwyTokenRange = Range(match.range(at: 4), in: work) else { return work }

    let designator = rwyDesignatorRange.map { String(work[$0]) } ?? ""
    let rwyToken = String(work[rwyTokenRange])
    let replacement = "CLEARED TO LAND " + designator + rwyToken

    let fullMatchRange = Range(match.range, in: work)!
    let before = String(work[work.startIndex..<fullMatchRange.lowerBound])
    let after = String(work[fullMatchRange.upperBound...])
    let result = before + replacement + after

    ReadbackDebugLog.log("aviationRepair: before=\"\(trimmed.prefix(80))\(trimmed.count > 80 ? "…" : "")\" after=\"\(result.prefix(80))\(result.count > 80 ? "…" : "")\"")
    return result
}
