import Foundation
import CoreLocation

/// Geographic bounds for an airport diagram (image/PDF covers this rectangle).
struct AirportDiagramBounds {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
    }

    func contains(_ coord: CLLocationCoordinate2D) -> Bool {
        coord.latitude >= minLat && coord.latitude <= maxLat &&
        coord.longitude >= minLon && coord.longitude <= maxLon
    }
}

/// Metadata for one airport diagram: id, bundle asset name or local file, and geographic bounds.
struct AirportDiagramInfo {
    let airportId: String
    /// Name of PDF or image in app bundle (e.g. "mic_airport_diagram"). Ignored when localPDFURL is set.
    let assetName: String
    /// Use PDF if true, else image (png/jpg).
    let isPDF: Bool
    let bounds: AirportDiagramBounds
    /// When set, the diagram is loaded from this file (downloaded plate). Takes precedence over bundle assetName.
    let localPDFURL: URL?

    init(airportId: String, assetName: String, isPDF: Bool, bounds: AirportDiagramBounds, localPDFURL: URL? = nil) {
        self.airportId = airportId
        self.assetName = assetName
        self.isPDF = isPDF
        self.bounds = bounds
        self.localPDFURL = localPDFURL
    }

    static let kmic = AirportDiagramInfo(
        airportId: "KMIC",
        assetName: "mic_airport_diagram",
        isPDF: true,
        bounds: AirportDiagramBounds(
            minLat: 45.058,
            maxLat: 45.066,
            minLon: -93.358,
            maxLon: -93.348
        )
    )

    /// Placeholder bounds for downloaded diagrams when we don't have real bounds (e.g. 0.01° box).
    private static let defaultDownloadedBounds = AirportDiagramBounds(
        minLat: 45.05, maxLat: 45.07, minLon: -93.36, maxLon: -93.34
    )

    /// All diagrams: only downloaded plates (no bundle KMIC). Add diagrams via Settings → search and "Download diagram from FAA".
    static var known: [AirportDiagramInfo] {
        var list: [AirportDiagramInfo] = []
        for id in PlateDownloadManager.shared.downloadedIdentifiers {
            if let url = PlateDownloadManager.shared.localPDFURL(airportId: id) {
                list.append(AirportDiagramInfo(
                    airportId: id,
                    assetName: id,
                    isPDF: true,
                    bounds: defaultDownloadedBounds,
                    localPDFURL: url
                ))
            }
        }
        return list
    }

    static func find(airportId: String) -> AirportDiagramInfo? {
        let id = airportId.uppercased()
        return known.first { $0.airportId == id || String($0.airportId.dropFirst()) == id } // KMIC or MIC
    }

    private static let defaultDiagramIdKey = "AirportDiagramInfo.defaultDiagramIdentifier"

    /// Saved default diagram (last LOAD). Nil until user has said "LOAD KXXX" and opened it.
    static var defaultDiagram: AirportDiagramInfo? {
        guard let id = UserDefaults.standard.string(forKey: defaultDiagramIdKey), !id.isEmpty else { return nil }
        return find(airportId: id)
    }

    /// Call when user opens a diagram via "LOAD KXXX" so it becomes the default for future "Show on diagram" (e.g. taxi with no airport in text).
    static func setDefaultDiagram(airportId: String) {
        let id = airportId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        UserDefaults.standard.set(id, forKey: defaultDiagramIdKey)
    }

    /// Picks a diagram from transmission text by finding the first airport ID we have a diagram for. Returns nil if none found (caller can use defaultDiagram).
    static func diagramFromTransmission(_ text: String) -> AirportDiagramInfo? {
        let upper = text.uppercased()
        // Match K + 3 letters (e.g. KMIC, KANE)
        let pattern = "K[A-Z]{3}"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)),
           let range = Range(match.range, in: upper) {
            let id = String(upper[range])
            if let found = find(airportId: id) { return found }
        }
        // Match 3-letter codes at word boundary (e.g. MIC, ANE) and try with K prefix
        let threeLetter = "[A-Z]{3}"
        if let regex = try? NSRegularExpression(pattern: threeLetter) {
            let nsRange = NSRange(upper.startIndex..., in: upper)
            let matches = regex.matches(in: upper, range: nsRange)
            for m in matches {
                guard let r = Range(m.range, in: upper) else { continue }
                let three = String(upper[r])
                if let found = find(airportId: "K" + three) ?? find(airportId: three) { return found }
            }
        }
        return nil
    }

    /// "LOAD KANE" / "LOAD KXXX" – special phrase (no callsign). Returns the diagram for that airport if we have it, else nil.
    static func diagramFromLoadPhrase(_ text: String) -> AirportDiagramInfo? {
        let upper = text.uppercased()
        guard upper.contains("LOAD") else { return nil }
        // After LOAD, expect optional spaces then K + 3 letters or 3 letters
        let pattern = "LOAD\\s+(K?[A-Z]{3})\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(upper.startIndex..., in: upper)
        guard let match = regex.firstMatch(in: upper, range: nsRange),
              let range = Range(match.range(at: 1), in: upper) else { return nil }
        let id = String(upper[range])
        let withK = id.count == 3 ? "K" + id : id
        return find(airportId: withK) ?? find(airportId: id)
    }
}

/// One taxiway segment for route drawing: id (e.g. "A") and centerline points [lat, lon].
struct TaxiwaySegment: Codable {
    let id: String
    /// Ordered points: [latitude, longitude] each.
    let points: [[Double]]
}
