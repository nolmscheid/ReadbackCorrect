// ReadbackEngine/NASRStore.swift
// Loads aviation_data_v2/*.json and builds in-memory indexes + geo grid.
// Thread-safe after load; all data immutable.
// Manifest is optional; data files load regardless of manifest presence/validity.

import Foundation

/// V2 pipeline manifest; all fields optional so schema drift does not break loading.
private struct NASRManifest: Decodable {
    var faa_cycle: String?
    var build_timestamp: String?
    var counts: [String: Int]?
}

public final class NASRStore: @unchecked Sendable {
    var airports: [NASRAirport] { _airports }
    var runways: [NASRRunway] { _runways }
    var frequencies: [NASRFrequency] { _frequencies }
    var navaids: [NASRNavaid] { _navaids }
    var fixes: [NASRFix] { _fixes }
    var comms: [NASRComm] { _comms }
    var ils: [NASRILS] { _ils }
    var departures: [NASRProcedure] { _departures }
    var arrivals: [NASRProcedure] { _arrivals }

    private var _airports: [NASRAirport] = []
    private var _runways: [NASRRunway] = []
    private var _frequencies: [NASRFrequency] = []
    private var _navaids: [NASRNavaid] = []
    private var _fixes: [NASRFix] = []
    private var _comms: [NASRComm] = []
    private var _ils: [NASRILS] = []
    private var _departures: [NASRProcedure] = []
    private var _arrivals: [NASRProcedure] = []

    // Identifier lookups (uppercase)
    private var _airportsById: [String: NASRAirport] = [:]
    private var _airportsByIcao: [String: NASRAirport] = [:]
    private var _runwaysByAirport: [String: [NASRRunway]] = [:]
    private var _frequenciesByFacility: [String: [NASRFrequency]] = [:]
    private var _navaidsById: [String: NASRNavaid] = [:]
    private var _fixesById: [String: NASRFix] = [:]
    private var _commsByOutlet: [String: NASRComm] = [:]

    // Geo indexes
    private var _airportGeo: GeoBucket<NASRAirport>?
    private var _fixGeo: GeoBucket<NASRFix>?
    private var _navaidGeo: GeoBucket<NASRNavaid>?

    static let defaultAirportRadiusNm = 80.0
    static let defaultFixNavaidRadiusNm = 150.0

    public init() {}

    /// Load from a directory containing aviation_data_v2 JSON files. Manifest is optional; all data files are loaded regardless. Does not throw.
    func load(from directory: URL) {
        let decoder = JSONDecoder()
        var decodeFailures: [String] = []

        // Optional manifest: decode and log; on failure log path, size, error, and first 300 chars.
        let manifestURL = directory.appendingPathComponent("aviation_manifest.json")
        _tryLoadManifest(from: manifestURL)

        // Load data files regardless of manifest; log size and count per file; on decode failure log and continue.
        _airports = _loadArrayAndLog([NASRAirport].self, from: directory.appendingPathComponent("airports.json"), decoder: decoder, fileLabel: "airports.json", decodeFailures: &decodeFailures) ?? []
        _runways = _loadArrayAndLog([NASRRunway].self, from: directory.appendingPathComponent("runways.json"), decoder: decoder, fileLabel: "runways.json", decodeFailures: &decodeFailures) ?? []
        _frequencies = _loadArrayAndLog([NASRFrequency].self, from: directory.appendingPathComponent("frequencies.json"), decoder: decoder, fileLabel: "frequencies.json", decodeFailures: &decodeFailures) ?? []
        _navaids = _loadArrayAndLog([NASRNavaid].self, from: directory.appendingPathComponent("navaids.json"), decoder: decoder, fileLabel: "navaids.json", decodeFailures: &decodeFailures) ?? []
        _fixes = _loadArrayAndLog([NASRFix].self, from: directory.appendingPathComponent("fixes.json"), decoder: decoder, fileLabel: "fixes.json", decodeFailures: &decodeFailures) ?? []
        _comms = _loadArrayAndLog([NASRComm].self, from: directory.appendingPathComponent("comms.json"), decoder: decoder, fileLabel: "comms.json", decodeFailures: &decodeFailures) ?? []
        _ils = _loadArrayAndLog([NASRILS].self, from: directory.appendingPathComponent("ils.json"), decoder: decoder, fileLabel: "ils.json", decodeFailures: &decodeFailures) ?? []
        _departures = _loadArrayAndLog([NASRProcedure].self, from: directory.appendingPathComponent("departures.json"), decoder: decoder, fileLabel: "departures.json", decodeFailures: &decodeFailures) ?? []
        _arrivals = _loadArrayAndLog([NASRProcedure].self, from: directory.appendingPathComponent("arrivals.json"), decoder: decoder, fileLabel: "arrivals.json", decodeFailures: &decodeFailures) ?? []

        if !decodeFailures.isEmpty {
            ReadbackDebugLog.log("NASR load decode failures: \(decodeFailures.joined(separator: ", "))")
        }
        ReadbackDebugLog.log("NASR load done. isLoaded=\(!_airports.isEmpty) \(debugCounts())")

        _buildIndexes()
    }

    private func _tryLoadManifest(from url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            ReadbackDebugLog.log("aviation_manifest.json: file missing (optional)")
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            ReadbackDebugLog.log("aviation_manifest.json: read failed path=\(url.absoluteURL.path) error=\(error)")
            return
        }
        let size = data.count
        do {
            let manifest = try JSONDecoder().decode(NASRManifest.self, from: data)
            let cycle = manifest.faa_cycle ?? "(nil)"
            let ts = manifest.build_timestamp ?? "(nil)"
            let countsStr = manifest.counts.map { "\($0)" } ?? "(nil)"
            ReadbackDebugLog.log("manifest decoded path=\(url.absoluteURL.path) size=\(size) faa_cycle=\(cycle) build_timestamp=\(ts) counts=\(countsStr)")
        } catch {
            let preview = String(data: data, encoding: .utf8).map { s in
                let end = s.index(s.startIndex, offsetBy: min(300, s.count), limitedBy: s.endIndex) ?? s.endIndex
                return String(s[..<end])
            } ?? "(not UTF-8)"
            ReadbackDebugLog.log("manifest decode failed path=\(url.absoluteURL.path) size=\(size) bytes error=\(error) preview=\(preview)")
        }
    }

    private func _loadArrayAndLog<T: Decodable>(_ type: T.Type, from url: URL, decoder: JSONDecoder, fileLabel: String, decodeFailures: inout [String]) -> T? where T: RandomAccessCollection, T.Index == Int {
        guard FileManager.default.fileExists(atPath: url.path) else {
            ReadbackDebugLog.log("\(fileLabel): file missing")
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            ReadbackDebugLog.log("\(fileLabel): read failed error=\(error)")
            decodeFailures.append(fileLabel)
            return nil
        }
        let size = data.count
        do {
            let decoded = try decoder.decode(T.self, from: data)
            let count = decoded.count
            ReadbackDebugLog.log("\(fileLabel) size=\(size) bytes loaded=\(count)")
            return decoded
        } catch {
            ReadbackDebugLog.log("\(fileLabel) decode failed size=\(size) error=\(error)")
            decodeFailures.append(fileLabel)
            return nil
        }
    }

    private func _buildIndexes() {
        _airportsById = Dictionary(uniqueKeysWithValues: _airports.map { ($0.identifier.uppercased(), $0) })
        _airportsByIcao = Dictionary(_airports.compactMap { a in
            guard let icao = a.icaoId, !icao.isEmpty else { return nil }
            return (icao.uppercased(), a)
        }, uniquingKeysWith: { first, _ in first })
        _runwaysByAirport = Dictionary(grouping: _runways, by: { $0.airportIdentifier.uppercased() })
        _frequenciesByFacility = Dictionary(grouping: _frequencies, by: { $0.facilityId.uppercased() })
        _navaidsById = Dictionary(uniqueKeysWithValues: _navaids.map { ($0.identifier.uppercased(), $0) })
        _fixesById = Dictionary(uniqueKeysWithValues: _fixes.map { ($0.identifier.uppercased(), $0) })
        _commsByOutlet = Dictionary(uniqueKeysWithValues: _comms.map { ($0.outletId.uppercased(), $0) })

        var ag = GeoBucket<NASRAirport>(extractId: { $0.identifier }, extractPosition: { ($0.latitude, $0.longitude) })
        ag.load(_airports)
        _airportGeo = ag
        var fg = GeoBucket<NASRFix>(extractId: { $0.identifier }, extractPosition: { ($0.latitude, $0.longitude) })
        fg.load(_fixes)
        _fixGeo = fg
        var ng = GeoBucket<NASRNavaid>(extractId: { $0.identifier }, extractPosition: { ($0.latitude, $0.longitude) })
        ng.load(_navaids)
        _navaidGeo = ng
    }

    // MARK: - Geo queries

    func nearestAirports(lat: Double, lon: Double, radiusNm: Double = 80.0, max: Int = 50) -> [LocatedItem<NASRAirport>] {
        guard let geo = _airportGeo else { return [] }
        let center = GeoPoint(lat: lat, lon: lon, altitudeFt: nil)
        let candidates = geo.candidates(lat: lat, lon: lon, radiusNm: radiusNm)
        let withDist = candidates.map { a in LocatedItem(item: a, distanceNm: center.distanceNm(to: GeoPoint(lat: a.latitude, lon: a.longitude, altitudeFt: Double(a.elevationFt ?? 0)))) }
        return Array(withDist.sorted { $0.distanceNm < $1.distanceNm }.prefix(max))
    }

    func nearbyFixes(lat: Double, lon: Double, radiusNm: Double = 150.0) -> [LocatedItem<NASRFix>] {
        guard let geo = _fixGeo else { return [] }
        let center = GeoPoint(lat: lat, lon: lon, altitudeFt: nil)
        let candidates = geo.candidates(lat: lat, lon: lon, radiusNm: radiusNm)
        let withDist = candidates.map { f in LocatedItem(item: f, distanceNm: center.distanceNm(to: GeoPoint(lat: f.latitude, lon: f.longitude, altitudeFt: nil))) }
        return withDist.sorted { $0.distanceNm < $1.distanceNm }
    }

    func nearbyNavaids(lat: Double, lon: Double, radiusNm: Double = 150.0) -> [LocatedItem<NASRNavaid>] {
        guard let geo = _navaidGeo else { return [] }
        let center = GeoPoint(lat: lat, lon: lon, altitudeFt: nil)
        let candidates = geo.candidates(lat: lat, lon: lon, radiusNm: radiusNm)
        let withDist = candidates.map { n in LocatedItem(item: n, distanceNm: center.distanceNm(to: GeoPoint(lat: n.latitude, lon: n.longitude, altitudeFt: Double(n.elevationFt ?? 0)))) }
        return withDist.sorted { $0.distanceNm < $1.distanceNm }
    }

    // MARK: - By-id lookups

    func airport(byIdentifier id: String) -> NASRAirport? { _airportsById[id.uppercased()] }
    func airport(byIcao icao: String) -> NASRAirport? { _airportsByIcao[icao.uppercased()] }
    func runways(atAirport identifier: String) -> [NASRRunway] { _runwaysByAirport[identifier.uppercased()] ?? [] }
    func frequencies(atFacility facilityId: String) -> [NASRFrequency] { _frequenciesByFacility[facilityId.uppercased()] ?? [] }
    func navaid(byIdentifier id: String) -> NASRNavaid? { _navaidsById[id.uppercased()] }
    func fix(byIdentifier id: String) -> NASRFix? { _fixesById[id.uppercased()] }
    func comm(byOutletId id: String) -> NASRComm? { _commsByOutlet[id.uppercased()] }

    /// Internal-only: true if any NASR data was loaded (e.g. airports count > 0).
    var isLoaded: Bool { !_airports.isEmpty }

    /// Internal-only: counts for debug logging. Format: "airports=N navaids=N ..."
    func debugCounts() -> String {
        var parts: [String] = []
        parts.append("airports=\(_airports.count)")
        parts.append("navaids=\(_navaids.count)")
        parts.append("fixes=\(_fixes.count)")
        parts.append("runways=\(_runways.count)")
        parts.append("frequencies=\(_frequencies.count)")
        parts.append("comms=\(_comms.count)")
        parts.append("departures=\(_departures.count)")
        parts.append("arrivals=\(_arrivals.count)")
        parts.append("ils=\(_ils.count)")
        return parts.joined(separator: " ")
    }

    /// All known identifiers (airport id, icao, fix, navaid) for snapping.
    func allIdentifiers() -> Set<String> {
        var s = Set<String>()
        for a in _airports {
            s.insert(a.identifier.uppercased())
            if let icao = a.icaoId, !icao.isEmpty { s.insert(icao.uppercased()) }
        }
        for f in _fixes { s.insert(f.identifier.uppercased()) }
        for n in _navaids { s.insert(n.identifier.uppercased()) }
        return s
    }
}
