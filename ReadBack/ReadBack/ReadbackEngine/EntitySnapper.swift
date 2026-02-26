// ReadbackEngine/EntitySnapper.swift
// Snap tokens to NASR entities: exact → case-insensitive → edit distance → phonetic.
// Weight by distance for fixes/navaids; record SnapEvent.

import Foundation

public struct SnapEvent: Sendable {
    public let originalSubstring: String
    public let replacement: String
    public let type: SnapType
    public let confidence: Double
    public let start: Int
    public let end: Int
    public init(originalSubstring: String, replacement: String, type: SnapType, confidence: Double, start: Int, end: Int) {
        self.originalSubstring = originalSubstring
        self.replacement = replacement
        self.type = type
        self.confidence = confidence
        self.start = start
        self.end = end
    }
}

public enum SnapType: String, Sendable {
    case airport
    case fix
    case navaid
    case runway
}

/// Levenshtein distance (deterministic).
func levenshtein(_ a: String, _ b: String) -> Int {
    let a = Array(a)
    let b = Array(b)
    var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in 0...a.count { d[i][0] = i }
    for j in 0...b.count { d[0][j] = j }
    for i in 1...a.count {
        for j in 1...b.count {
            let cost = a[i-1] == b[j-1] ? 0 : 1
            d[i][j] = min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + cost)
        }
    }
    return d[a.count][b.count]
}

/// Normalized similarity 0...1 (1 = identical).
func similarity(_ a: String, _ b: String) -> Double {
    if a.isEmpty && b.isEmpty { return 1.0 }
    if a.isEmpty || b.isEmpty { return 0.0 }
    let d = levenshtein(a.lowercased(), b.lowercased())
    let maxLen = max(a.count, b.count)
    return 1.0 - Double(d) / Double(maxLen)
}

/// Jaro-Winkler-like: boost when prefix matches.
func stringScore(_ token: String, _ candidate: String) -> Double {
    let t = token.uppercased()
    let c = candidate.uppercased()
    if t == c { return 1.0 }
    if t.isEmpty || c.isEmpty { return 0.0 }
    let sim = similarity(t, c)
    let prefixMatch = c.hasPrefix(t) || t.hasPrefix(c)
    return min(0.99, sim + (prefixMatch ? 0.1 : 0))
}

struct EntitySnapper {
    static let defaultMinConfidence = 0.6

    /// Snap folded tokens to store entities; return SnapEvents for each snap above threshold.
    static func snap(
        foldedTokens: [String],
        foldedTokenSpans: [(String, Int, Int)],
        store: NASRStore,
        gps: GeoPoint,
        airportRadiusNm: Double = 80.0,
        fixNavaidRadiusNm: Double = 150.0,
        minConfidence: Double = defaultMinConfidence
    ) -> [SnapEvent] {
        var events: [SnapEvent] = []
        let nearbyAirports = store.nearestAirports(lat: gps.lat, lon: gps.lon, radiusNm: airportRadiusNm, max: 100)
        let nearbyFixItems = store.nearbyFixes(lat: gps.lat, lon: gps.lon, radiusNm: fixNavaidRadiusNm)
        let nearbyNavaidItems = store.nearbyNavaids(lat: gps.lat, lon: gps.lon, radiusNm: fixNavaidRadiusNm)
        let airportIds = Set(nearbyAirports.map { $0.item.identifier.uppercased() })
        let icaoIds = Set(nearbyAirports.compactMap { $0.item.icaoId?.uppercased() })
        let fixIds = Set(nearbyFixItems.map { $0.item.identifier.uppercased() })
        let navaidIds = Set(nearbyNavaidItems.map { $0.item.identifier.uppercased() })

        for (idx, token) in foldedTokens.enumerated() {
            let span: (Int, Int) = idx < foldedTokenSpans.count ? (foldedTokenSpans[idx].1, foldedTokenSpans[idx].2) : (0, 0)
            let tokenUpper = token.uppercased()
            if tokenUpper.count < 2 { continue }

            var bestEvent: SnapEvent?
            if let best = bestMatch(token: tokenUpper, candidates: Array(airportIds.union(icaoIds))) {
                var conf = stringScore(token, best)
                if let loc = nearbyAirports.first(where: { $0.item.identifier.uppercased() == best || $0.item.icaoId?.uppercased() == best }) {
                    conf *= distanceWeight(loc.distanceNm, radiusNm: airportRadiusNm)
                }
                if conf >= minConfidence { bestEvent = SnapEvent(originalSubstring: token, replacement: best, type: .airport, confidence: conf, start: span.0, end: span.1) }
            }
            if let best = bestMatch(token: tokenUpper, candidates: Array(fixIds)) {
                var conf = stringScore(token, best)
                if let loc = nearbyFixItems.first(where: { $0.item.identifier.uppercased() == best }) {
                    conf *= distanceWeight(loc.distanceNm, radiusNm: fixNavaidRadiusNm)
                }
                if conf >= minConfidence {
                    let ev = SnapEvent(originalSubstring: token, replacement: best, type: .fix, confidence: conf, start: span.0, end: span.1)
                    if bestEvent == nil || conf > bestEvent!.confidence { bestEvent = ev }
                }
            }
            if let best = bestMatch(token: tokenUpper, candidates: Array(navaidIds)) {
                var conf = stringScore(token, best)
                if let loc = nearbyNavaidItems.first(where: { $0.item.identifier.uppercased() == best }) {
                    conf *= distanceWeight(loc.distanceNm, radiusNm: fixNavaidRadiusNm)
                }
                if conf >= minConfidence {
                    let ev = SnapEvent(originalSubstring: token, replacement: best, type: .navaid, confidence: conf, start: span.0, end: span.1)
                    if bestEvent == nil || conf > bestEvent!.confidence { bestEvent = ev }
                }
            }
            if let ev = bestEvent { events.append(ev) }
        }
        return events
    }

    private static func distanceWeight(_ distanceNm: Double, radiusNm: Double) -> Double {
        if distanceNm <= 0 { return 1.0 }
        let ratio = distanceNm / radiusNm
        return max(0.5, 1.0 - ratio * 0.5)
    }

    private static func bestMatch(token: String, candidates: [String]) -> String? {
        var best: (String, Double)?
        for c in candidates {
            let score = stringScore(token, c)
            if score >= 0.6 && (best == nil || score > best!.1) {
                best = (c, score)
            }
        }
        return best?.0
    }
}
