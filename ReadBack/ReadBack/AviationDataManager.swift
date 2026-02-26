import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Manifest published by a data server. Lists cycle date and relative paths to JSON files.
struct AviationManifest: Codable {
    let cycle: String           // e.g. "2026-02-19"
    var updated: String?       // optional ISO timestamp
    let files: [String: String] // e.g. ["airports": "airports.json", "victor_airways": "victor_airways.json", "waypoints": "waypoints.json"]
}

/// Loads and optionally updates FAA reference data (Victor airways, airports, waypoints) from bundle or app support.
/// Updates come from a manifest-based server (you host JSON files) or, in future, direct FAA NASR download.
/// See AVIATION_DATA_SOURCES.md for manifest format and server setup.
final class AviationDataManager: ObservableObject {

    static let shared = AviationDataManager()

    /// Victor airway numbers (e.g. "23" for V23). Use for validation / normalization.
    @Published private(set) var victorAirwayNumbers: Set<String> = []
    /// Airport display names and common variants (e.g. "Denver", "Palomar", "Riverside Municipal").
    @Published private(set) var airportNames: [String] = []
    /// Full airport records for lookup (e.g. clearance limit → identifier).
    private var airportRecords: [AirportRecord] = []
    /// O(1) lookups by normalized name/city and by id to avoid scanning 20k+ records on every CRAFT update.
    private var airportByNameNorm: [String: AirportRecord] = [:]
    private var airportByCityNorm: [String: AirportRecord] = [:]
    private var airportById: [String: AirportRecord] = [:]
    /// Waypoint IDs (e.g. OCN, JOT) for route validation. Names in waypointRecords for phonetic lookup.
    @Published private(set) var waypointIds: Set<String> = []
    /// Procedure names (SID/STAR) when we add DP/STAR data.
    @Published private(set) var procedureNames: [String] = []

    /// When the loaded data was last updated (bundle or downloaded).
    @Published private(set) var lastUpdatedDate: Date?
    /// Effective date of the NASR cycle if loaded from server/FAA (e.g. "2026-02-19").
    @Published private(set) var nasrEffectiveDate: String?

    /// True while checking or downloading.
    @Published private(set) var isUpdating: Bool = false
    /// Message for the user (e.g. "New data available", "Download failed").
    @Published var statusMessage: String?
    /// True when Check for updates found a newer cycle or no data yet; show Download button.
    @Published private(set) var updateAvailable: Bool = false
    /// Total size of downloaded aviation JSON files (e.g. "2.3 MB"). Nil if none downloaded.
    @Published private(set) var downloadedDataSizeFormatted: String?

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let lastUpdatedKey = "AviationDataManager.lastUpdated"
    private let nasrEffectiveKey = "AviationDataManager.nasrEffectiveDate"
    /// When the server manifest includes "updated" (ISO timestamp), we store it so we can detect new builds even when cycle is unchanged.
    private let manifestUpdatedKey = "AviationDataManager.manifestUpdated"
    /// Base URL for aviation data server (e.g. https://yourserver.com/readback_data). Empty = use bundle only; Check uses FAA page for cycle.
    private let dataSourceBaseURLKey = "AviationDataManager.dataSourceBaseURL"

    /// Default data server used when the user has not set a custom URL. Points to aviation_data/ in the ReadbackCorrect repo (see GITHUB_DATA_SETUP.md).
    static let defaultDataServerBaseURL = "https://raw.githubusercontent.com/nolmscheid/ReadbackCorrect/main/aviation_data"
    /// Base URL for aviation_data_v2 (NASR v2 for ReadbackEngine). Must be raw content: https://raw.githubusercontent.com/nolmscheid/ReadbackCorrect/<BRANCH>/aviation_data_v2/
    /// Branch must match where aviation_data_v2 is committed (e.g. aviation-data-v2 at https://github.com/nolmscheid/ReadbackCorrect/tree/aviation-data-v2/aviation_data_v2).
    static let defaultDataServerBaseURLV2Branch = "aviation-data-v2"
    static var defaultDataServerBaseURLV2: String {
        "https://raw.githubusercontent.com/nolmscheid/ReadbackCorrect/\(defaultDataServerBaseURLV2Branch)/aviation_data_v2"
    }

    /// Base URL for data server. When set, overrides the default. When empty, Check for updates and Download use defaultDataServerBaseURL.
    var dataSourceBaseURL: String {
        get { defaults.string(forKey: dataSourceBaseURLKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: dataSourceBaseURLKey) }
    }

    /// Base URL used for manifest and downloads: custom URL if set, otherwise the default (e.g. GitHub).
    private var effectiveBaseURL: String {
        let custom = dataSourceBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return Self.defaultDataServerBaseURL
    }

    private init() {
        loadData()
    }

    // MARK: - Load

    private var waypointRecords: [WaypointRecord] = []

    private func loadData() {
        ensureAppSupportDirectory()
        let supportDir = appSupportAviationDataDirectory()
        let hasSupportData = supportDir != nil && fileManager.fileExists(atPath: supportDir!.appendingPathComponent("victor_airways.json").path)

        if hasSupportData, let dir = supportDir {
            loadVictor(from: dir.appendingPathComponent("victor_airways.json"))
            loadAirports(from: dir.appendingPathComponent("airports.json"))
            loadWaypoints(from: dir.appendingPathComponent("waypoints.json"))
            lastUpdatedDate = defaults.object(forKey: lastUpdatedKey) as? Date
            nasrEffectiveDate = defaults.string(forKey: nasrEffectiveKey)
        }
        if victorAirwayNumbers.isEmpty {
            loadVictorFromBundle()
        }
        if airportNames.isEmpty {
            loadAirportsFromBundle()
        }
        if waypointIds.isEmpty {
            loadWaypointsFromBundle()
        }
        refreshDownloadedDataSize()
    }

    private func ensureAppSupportDirectory() {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let dir = support.appendingPathComponent("ReadBack", isDirectory: true).appendingPathComponent("aviation_data", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func loadVictor(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return }
        victorAirwayNumbers = Set(arr)
    }

    private func loadAirports(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([AirportRecord].self, from: data) else { return }
        airportRecords = arr
        airportNames = arr.flatMap { r in [r.name, r.city].compactMap { $0 }.filter { !$0.isEmpty } }
        buildAirportIndices()
    }

    private func loadVictorFromBundle() {
        guard let url = Bundle.main.url(forResource: "victor_airways", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return }
        victorAirwayNumbers = Set(arr)
    }

    private func loadAirportsFromBundle() {
        guard let url = Bundle.main.url(forResource: "airports", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([AirportRecord].self, from: data) else { return }
        airportRecords = arr
        airportNames = arr.flatMap { r in [r.name, r.city].compactMap { $0 }.filter { !$0.isEmpty } }
        buildAirportIndices()
    }

    /// Normalize airport name/city for index and query (same logic as airportMatch).
    private static func normalizeForAirportMatch(_ s: String?) -> String {
        guard let s = s, !s.isEmpty else { return "" }
        var t = s.uppercased()
        let abbrevs: [(String, String)] = [
            (" SAINT ", " ST "), ("SAINT ", "ST "), (" SAINT", " ST"),
            (" RGNL ", " REGIONAL "), (" RGNL", " REGIONAL"),
            (" INTL ", " INTERNATIONAL "), (" INTL", " INTERNATIONAL"),
            (" ARPT ", " AIRPORT "), (" ARPT", " AIRPORT"),
            (" MUNI ", " MUNICIPAL "), (" MUNI", " MUNICIPAL"),
            (" REG ", " REGIONAL "), (" REG", " REGIONAL"),
        ]
        for (abbrev, full) in abbrevs { t = t.replacingOccurrences(of: abbrev, with: full) }
        t = t.replacingOccurrences(of: " - ", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return t
    }

    /// Prefer primary airports (K-prefix or 3-letter) over heliports/hospitals when multiple share a city.
    private static func isPrimaryAirport(id: String?) -> Bool {
        guard let id = id, !id.isEmpty else { return false }
        let u = id.uppercased()
        return (u.count == 4 && u.hasPrefix("K")) || (u.count == 3 && u.allSatisfy { $0.isLetter })
    }

    private func buildAirportIndices() {
        airportByNameNorm.removeAll()
        airportByCityNorm.removeAll()
        airportById.removeAll()
        for r in airportRecords {
            guard let id = r.id, !id.isEmpty else { continue }
            let idUpper = id.uppercased()
            airportById[idUpper] = r
            if idUpper.count == 4 && idUpper.hasPrefix("K") {
                airportById[String(idUpper.dropFirst())] = r
            }
            let normName = Self.normalizeForAirportMatch(r.name)
            if !normName.isEmpty, airportByNameNorm[normName] == nil { airportByNameNorm[normName] = r }
            let normCity = Self.normalizeForAirportMatch(r.city)
            if !normCity.isEmpty {
                let existing = airportByCityNorm[normCity]
                let useThis = existing == nil || (Self.isPrimaryAirport(id: r.id) && !Self.isPrimaryAirport(id: existing?.id))
                if useThis { airportByCityNorm[normCity] = r }
            }
        }
    }

    private func loadWaypoints(from url: URL) {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([WaypointRecord].self, from: data) else { return }
        waypointRecords = arr
        waypointIds = Set(arr.compactMap { $0.id }.filter { !$0.isEmpty })
    }

    private func loadWaypointsFromBundle() {
        guard let url = Bundle.main.url(forResource: "waypoints", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([WaypointRecord].self, from: data) else { return }
        waypointRecords = arr
        waypointIds = Set(arr.compactMap { $0.id }.filter { !$0.isEmpty })
    }

    /// Fallback when DB has no name/city (e.g. downloaded FAA data). Common clearance phrases → (id, display name). Keys uppercase.
    private static let fallbackClearancePhrases: [String: (id: String, name: String)] = [
        "DULUTH": ("KDLH", "Duluth Intl"),
        "DENVER": ("KDEN", "Denver International"),
        "MINNEAPOLIS": ("KMSP", "Minneapolis–St. Paul"),
        "ST CLOUD": ("KSTC", "St. Cloud Regional"),
        "ST. CLOUD": ("KSTC", "St. Cloud Regional"),
        "ANOKA": ("KANE", "Anoka County–Blaine"),
        "BRAINERD": ("KBRD", "Brainerd Lakes Regional"),
        "CRYSTAL": ("KMIC", "Crystal"),
        "CHICAGO": ("KORD", "Chicago O'Hare"),
        "APPLETON": ("KATW", "Appleton"),
        "MILWAUKEE": ("KMKE", "Milwaukee"),
        "ROCHESTER": ("KRST", "Rochester International"),
        "BEMIDJI": ("BJI", "Bemidji Regional"),
    ]

    /// Normalized clearance phrase (uppercase, no ". ", no " AIRPORT") for fallback / exact lookup.
    private static func clearancePhraseKey(_ clearanceName: String) -> String {
        clearanceName.trimmingCharacters(in: .whitespaces).uppercased()
            .replacingOccurrences(of: ". ", with: " ")
            .replacingOccurrences(of: " AIRPORT", with: "", options: .caseInsensitive)
    }

    /// Returns the airport identifier (e.g. KDEN) for a clearance-limit name or city (e.g. "Denver", "Denver International"). Used in CRAFT C row.
    func airportIdentifier(forClearanceName clearanceName: String) -> String? {
        let q = Self.clearancePhraseKey(clearanceName)
        if let fallbackId = Self.fallbackClearancePhrases[q]?.id { return fallbackId }
        if let id = airportMatch(forClearanceName: clearanceName)?.id { return id }
        return Self.fallbackClearancePhrases[q]?.id
    }

    /// Returns the full airport name (e.g. "St. Cloud Regional") for a clearance-limit name when matched. Used in CRAFT C row. Falls back to city or identifier if name is empty.
    func airportDisplayName(forClearanceName clearanceName: String) -> String? {
        let q = Self.clearancePhraseKey(clearanceName)
        if let fallback = Self.fallbackClearancePhrases[q] {
            if let r = airportById[fallback.id], let name = r.name, !name.isEmpty { return name }
            if let r = airportById["K" + fallback.id], let name = r.name, !name.isEmpty { return name }
            return fallback.name
        }
        if let match = airportMatch(forClearanceName: clearanceName) {
            let name = (match.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
            if let city = airportCity(forIdentifier: match.id), !city.isEmpty { return city }
            return match.id
        }
        return Self.fallbackClearancePhrases[q]?.name
    }

    /// Returns the official airport name for an identifier (e.g. "KANE" → "Anoka County-Blaine Arpt"). Used in diagram list.
    func airportDisplayName(forIdentifier identifier: String) -> String? {
        let q = identifier.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count == 3 || q.count == 4 else { return nil }
        if let r = airportById[q], let name = r.name, !name.isEmpty { return name }
        if q.count == 3, let r = airportById["K" + q], let name = r.name, !name.isEmpty { return name }
        return nil
    }

    /// Returns the city for an airport identifier (e.g. "KDEN" → "Denver"). Used as fallback when name is empty.
    private func airportCity(forIdentifier identifier: String?) -> String? {
        guard let id = identifier, !id.isEmpty else { return nil }
        let q = id.uppercased()
        if let r = airportById[q], let city = r.city, !city.isEmpty { return city }
        if q.count == 3, let r = airportById["K" + q], let city = r.city, !city.isEmpty { return city }
        return nil
    }

    /// Shared match for identifier and display name. Priority: (1) airport name, (2) city only if no name match. ATC usually calls by airport name.
    private func airportMatch(forClearanceName clearanceName: String) -> (id: String, name: String?)? {
        let raw = clearanceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let q = raw.uppercased()
            .replacingOccurrences(of: ". ", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Fast path: identifier (3/4 char) via index
        if q.count >= 3, q.count <= 4, q.allSatisfy({ $0.isLetter || $0.isNumber }) {
            if let r = airportById[q], let id = r.id { return (id, r.name) }
            if q.count == 3, q.allSatisfy({ $0.isLetter }), let r = airportById["K" + q], let id = r.id { return (id, r.name) }
        }
        let qNorm = Self.normalizeForAirportMatch(raw)
        if !qNorm.isEmpty {
            if let r = airportByNameNorm[qNorm], let id = r.id { return (id, r.name) }
            if let r = airportByCityNorm[qNorm], let id = r.id { return (id, r.name) }
        }
        // Fallback: fuzzy match by scanning (e.g. "Denver International", "Rochester International")
        func normalizeAbbrevs(_ s: String) -> String {
            var t = s
            let pairs: [(String, String)] = [
                (" SAINT ", " ST "), ("SAINT ", "ST "), (" SAINT", " ST"),
                (" RGNL ", " REGIONAL "), (" RGNL", " REGIONAL"),
                (" INTL ", " INTERNATIONAL "), (" INTL", " INTERNATIONAL"),
                (" ARPT ", " AIRPORT "), (" ARPT", " AIRPORT"),
                (" MUNI ", " MUNICIPAL "), (" MUNI", " MUNICIPAL"),
                (" REG ", " REGIONAL "), (" REG", " REGIONAL"),
            ]
            for (abbrev, full) in pairs { t = t.replacingOccurrences(of: abbrev, with: full) }
            return t.trimmingCharacters(in: .whitespaces)
        }
        func normalizePunctuation(_ s: String) -> String {
            s.replacingOccurrences(of: " - ", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "/", with: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        let qNormLocal = normalizePunctuation(normalizeAbbrevs(q))
        let useStrictMatch = q.count <= 2
        typealias Candidate = (record: AirportRecord, score: Int, matchLength: Int, isPrimaryId: Bool)
        func pickBest(from candidates: [Candidate]) -> Candidate? {
            guard !candidates.isEmpty else { return nil }
            return candidates.max(by: { a, b in
                if a.score != b.score { return a.score < b.score }
                if a.matchLength != b.matchLength { return a.matchLength < b.matchLength }
                return !a.isPrimaryId && b.isPrimaryId
            })
        }
        // Pass 1: Match by airport NAME only (primary — ATC usually says the airport name).
        var nameCandidates: [Candidate] = []
        for r in airportRecords {
            guard r.id != nil, !(r.id ?? "").isEmpty else { continue }
            let nameRaw = (r.name ?? "").uppercased()
            let name = normalizePunctuation(normalizeAbbrevs(nameRaw))
            guard !name.isEmpty else { continue }
            let idStr = (r.id ?? "").uppercased()
            let isPrimary = (idStr.count == 4 && idStr.hasPrefix("K")) || (idStr.count == 3 && idStr.allSatisfy { $0.isLetter })
            if name == qNormLocal || name == q { nameCandidates.append((r, 4, name.count, isPrimary)); continue }
            // Query contains name: only allow if name is not much shorter (avoid "ROCHESTER" matching "CHESTER")
            if (qNormLocal.contains(name) || q.contains(name)) && name.count >= q.count - 1 { nameCandidates.append((r, 3, name.count, isPrimary)); continue }
            if !useStrictMatch, (name.contains(qNormLocal) || name.contains(q)) { nameCandidates.append((r, 3, q.count, isPrimary)); continue }
            if useStrictMatch, (name.hasPrefix(q + " ") || name.hasPrefix(q + ".") || name.hasPrefix(qNormLocal + " ")) { nameCandidates.append((r, 3, q.count, isPrimary)) }
        }
        if let best = pickBest(from: nameCandidates), let id = best.record.id { return (id, best.record.name) }
        // Pass 2: Only if no name match — match by city (fallback when phrase is just a city name).
        var cityCandidates: [Candidate] = []
        for r in airportRecords {
            guard r.id != nil, !(r.id ?? "").isEmpty else { continue }
            let cityRaw = (r.city ?? "").uppercased()
            let city = normalizePunctuation(normalizeAbbrevs(cityRaw))
            guard !city.isEmpty else { continue }
            let idStr = (r.id ?? "").uppercased()
            let isPrimary = (idStr.count == 4 && idStr.hasPrefix("K")) || (idStr.count == 3 && idStr.allSatisfy { $0.isLetter })
            if city == qNormLocal || city == q { cityCandidates.append((r, 2, city.count, isPrimary)); continue }
            // Query contains city: only allow if city is not much shorter (avoid "ROCHESTER" matching "CHESTER")
            if (qNormLocal.contains(city) || q.contains(city)) && city.count >= q.count - 1 { cityCandidates.append((r, 1, city.count, isPrimary)); continue }
            if !useStrictMatch, (city.contains(qNormLocal) || city.contains(q)) { cityCandidates.append((r, 1, q.count, isPrimary)); continue }
            if useStrictMatch, (city.hasPrefix(q + " ") || city.hasPrefix(q + ".") || city.hasPrefix(qNormLocal + " ")) { cityCandidates.append((r, 1, q.count, isPrimary)) }
        }
        if let best = pickBest(from: cityCandidates), let id = best.record.id { return (id, best.record.name) }
        return nil
    }

    private struct AirportRecord: Codable {
        let id: String?
        let name: String?
        let city: String?
        let state: String?
    }

    private struct WaypointRecord: Codable {
        let id: String?
        let name: String?
    }

    // MARK: - Manifest (server)

    /// Fetches aviation_manifest.json from the effective data server (default or custom). Returns nil if fetch fails.
    private func fetchManifest() async -> AviationManifest? {
        let base = effectiveBaseURL
        guard let url = URL(string: base.hasSuffix("/") ? base + "aviation_manifest.json" : base + "/aviation_manifest.json") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(AviationManifest.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Check for updates

    /// Fetches FAA NASR subscription index and returns the current cycle effective date (YYYY-MM-DD) if available.
    func fetchCurrentNASRCycleDate() async -> String? {
        guard let url = URL(string: "https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let html = String(data: data, encoding: .utf8) ?? ""
            // Current cycle link: "Subscription effective February 19, 2026" -> .../2026-02-19
            let pattern = #"Subscription effective ([A-Za-z]+) (\d{1,2}), (\d{4})"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  match.numberOfRanges >= 4,
                  let monthRange = Range(match.range(at: 1), in: html),
                  let dayRange = Range(match.range(at: 2), in: html),
                  let yearRange = Range(match.range(at: 3), in: html) else { return nil }
            let monthStr = String(html[monthRange])
            let day = String(html[dayRange])
            let year = String(html[yearRange])
            let monthNum = monthToNumber(monthStr)
            return "\(year)-\(monthNum)-\(day.count == 1 ? "0" + day : day)"
        } catch {
            return nil
        }
    }

    private func monthToNumber(_ name: String) -> String {
        let m: [String: String] = [
            "January": "01", "February": "02", "March": "03", "April": "04", "May": "05", "June": "06",
            "July": "07", "August": "08", "September": "09", "October": "10", "November": "11", "December": "12"
        ]
        return m[name] ?? "01"
    }

    /// Converts "2026-02-19" to "19_Feb_2026" for NASR extra CSV URLs.
    private func nasrDateToExtraFormat(_ yyyyMMdd: String) -> String? {
        let parts = yyyyMMdd.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard m >= 1, m <= 12 else { return nil }
        return "\(d)_\(months[m])_\(y)"
    }

    /// Call when user taps "Check for updates". Uses effective data server (default or custom) to fetch manifest and compare cycle.
    func checkForUpdates() async {
        await MainActor.run { isUpdating = true; statusMessage = nil }
        defer { Task { @MainActor in isUpdating = false } }

        guard let manifest = await fetchManifest() else {
            await MainActor.run { statusMessage = "Could not reach data server. Check network or Settings → Data server URL." }
            return
        }
        let storedCycle = nasrEffectiveDate
        let storedUpdated = defaults.string(forKey: manifestUpdatedKey)
        let cycleChanged = storedCycle == nil || storedCycle != manifest.cycle
        // Server may send "updated" (ISO timestamp) when workflow runs; newer timestamp = new build even if cycle unchanged
        let updatedNewer = manifest.updated.flatMap { server in
            guard let local = storedUpdated, !local.isEmpty else { return !server.isEmpty }
            return server > local
        } ?? false
        let hasUpdate = cycleChanged || updatedNewer
        await MainActor.run {
            updateAvailable = hasUpdate
            if storedCycle == nil {
                statusMessage = "Data available for cycle \(manifest.cycle). Tap Download."
            } else if hasUpdate {
                statusMessage = "New data available (\(manifest.cycle)). Tap Download."
            } else {
                statusMessage = "Data is current (\(manifest.cycle))."
            }
        }
    }

    // MARK: - Download and save

    /// Downloads data from the effective server (default or custom): manifest + JSON files.
    func downloadUpdates() async {
        await MainActor.run { isUpdating = true; statusMessage = nil }
        defer { Task { @MainActor in isUpdating = false } }

        guard let manifest = await fetchManifest() else {
            await MainActor.run { statusMessage = "Could not fetch manifest. Check server URL and network." }
            return
        }

        guard let supportDir = appSupportAviationDataDirectory() else {
            await MainActor.run { statusMessage = "Could not create app data folder." }
            return
        }

        let base = effectiveBaseURL
        let baseURL = URL(string: base.hasSuffix("/") ? base : base + "/")
        var failed: [String] = []
        for (key, path) in manifest.files {
            let pathTrimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: pathTrimmed, relativeTo: baseURL), url.scheme != nil else { failed.append(key); continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let dest = supportDir.appendingPathComponent((path as NSString).lastPathComponent)
                try data.write(to: dest)
            } catch {
                failed.append(key)
            }
        }
        if !failed.isEmpty {
            await MainActor.run { statusMessage = "Downloaded but some files failed: \(failed.joined(separator: ", "))." }
        }

        // Download aviation_data_v2 (NASR v2 for ReadbackEngine)
        let v2Failed = await downloadV2Updates()
        if !v2Failed.isEmpty {
            await MainActor.run { statusMessage = (statusMessage ?? "Data updated.") + " V2: some files failed: \(v2Failed.joined(separator: ", "))." }
        } else if failed.isEmpty {
            await MainActor.run { statusMessage = "Data updated to cycle \(manifest.cycle) (including NASR v2)." }
        }
        await MainActor.run { ReadbackEngineProvider.resetStore() }

        defaults.set(Date(), forKey: lastUpdatedKey)
        defaults.set(manifest.cycle, forKey: nasrEffectiveKey)
        if let u = manifest.updated { defaults.set(u, forKey: manifestUpdatedKey) }
        await MainActor.run {
            lastUpdatedDate = Date()
            nasrEffectiveDate = manifest.cycle
            updateAvailable = false
            loadData()
            refreshDownloadedDataSize()
        }
    }

    /// V2 JSON file names (same set NASRStore loads).
    private static let v2FileNames = [
        "aviation_manifest.json", "airports.json", "runways.json", "frequencies.json", "navaids.json",
        "fixes.json", "comms.json", "ils.json", "departures.json", "arrivals.json", "airways.json"
    ]

    /// Safety gate: do not overwrite local JSONs unless response is valid. Manifest is one object (~hundreds of bytes); data files are large arrays.
    private static let v2ManifestMinBytes = 50
    private static let v2DataFileMinBytes = 1000

    /// Downloads aviation_data_v2 files from raw.githubusercontent.com/nolmscheid/ReadbackCorrect/<BRANCH>/aviation_data_v2/ into Application Support.
    /// Does NOT overwrite existing files unless status==200, response starts with { or [, and size >= threshold.
    /// Returns list of failed file names.
    private func downloadV2Updates() async -> [String] {
        guard let dir = appSupportAviationDataV2Directory() else { return Self.v2FileNames }
        let base = Self.defaultDataServerBaseURLV2
        let baseURL = URL(string: base.hasSuffix("/") ? base : base + "/")
        guard let baseURL = baseURL else { return Self.v2FileNames }
        var failed: [String] = []
        for name in Self.v2FileNames {
            guard let url = URL(string: name, relativeTo: baseURL), url.scheme != nil else { failed.append(name); continue }
            let finalURL = url.absoluteURL
            let resolvedURLString = finalURL.absoluteString
            do {
                var request = URLRequest(url: finalURL)
                request.httpMethod = "GET"
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                let statusCode = http?.statusCode ?? -1
                let contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? "(none)"

                if name == "aviation_manifest.json" {
                    ReadbackDebugLog.log("v2 aviation_manifest.json resolvedURL=\(resolvedURLString)")
                    ReadbackDebugLog.log("v2 aviation_manifest.json status=\(statusCode) content-type=\(contentType)")
                    if statusCode != 200 {
                        let preview = String(data: data.prefix(80), encoding: .utf8) ?? "(non-UTF8)"
                        ReadbackDebugLog.log("v2 aviation_manifest.json responsePreview(80)=\(preview)")
                    }
                }

                let minBytes = name == "aviation_manifest.json" ? Self.v2ManifestMinBytes : Self.v2DataFileMinBytes
                let firstNonWhitespace = data.prefix(1024).first(where: { $0 != 0x20 && $0 != 0x0A && $0 != 0x0D && $0 != 0x09 })
                let startsWithJSON = firstNonWhitespace == UInt8(ascii: "[") || firstNonWhitespace == UInt8(ascii: "{")

                if statusCode != 200 || !startsWithJSON || data.count < minBytes {
                    failed.append(name)
                    continue
                }
                try data.write(to: dir.appendingPathComponent(name))
            } catch {
                failed.append(name)
            }
        }
        return failed
    }

    /// Removes downloaded aviation data and clears stored cycle/updated so the app falls back to bundle. Next "Check for updates" will show data available.
    func clearDownloadedData() {
        if let dir = appSupportAviationDataDirectory() {
            for name in ["aviation_manifest.json", "airports.json", "waypoints.json", "victor_airways.json"] {
                try? fileManager.removeItem(at: dir.appendingPathComponent(name))
            }
        }
        if let dirV2 = appSupportAviationDataV2Directory() {
            for name in Self.v2FileNames {
                try? fileManager.removeItem(at: dirV2.appendingPathComponent(name))
            }
        }
        ReadbackEngineProvider.resetStore()
        defaults.removeObject(forKey: lastUpdatedKey)
        defaults.removeObject(forKey: nasrEffectiveKey)
        defaults.removeObject(forKey: manifestUpdatedKey)
        lastUpdatedDate = nil
        nasrEffectiveDate = nil
        updateAvailable = true
        statusMessage = "Downloaded data cleared. Tap Check for updates, then Download."
        refreshDownloadedDataSize()
        loadData()
    }

    /// Opens the FAA NASR subscription page in the default browser so the user can download data manually.
    func openNASRPage() {
        guard let url = URL(string: "https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/") else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    private func appSupportAviationDataDirectory() -> URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("ReadBack", isDirectory: true).appendingPathComponent("aviation_data", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return fileManager.fileExists(atPath: dir.path) ? dir : nil
    }

    private func appSupportAviationDataV2Directory() -> URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("ReadBack", isDirectory: true).appendingPathComponent("aviation_data_v2", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return fileManager.fileExists(atPath: dir.path) ? dir : nil
    }

    /// Updates downloadedDataSizeFormatted from v1 + v2 JSON files in app support. Call after load, download, or clear.
    func refreshDownloadedDataSize() {
        var total: Int64 = 0
        if let dir = appSupportAviationDataDirectory() {
            for name in ["aviation_manifest.json", "airports.json", "waypoints.json", "victor_airways.json"] {
                let url = dir.appendingPathComponent(name)
                if let attrs = try? fileManager.attributesOfItem(atPath: url.path), let size = attrs[.size] as? Int64 {
                    total += size
                }
            }
        }
        if let dirV2 = appSupportAviationDataV2Directory() {
            for name in Self.v2FileNames {
                let url = dirV2.appendingPathComponent(name)
                if let attrs = try? fileManager.attributesOfItem(atPath: url.path), let size = attrs[.size] as? Int64 {
                    total += size
                }
            }
        }
        if total == 0 {
            downloadedDataSizeFormatted = nil
            return
        }
        let kb = Double(total) / 1024
        if kb >= 1024 {
            downloadedDataSizeFormatted = String(format: "%.1f MB", kb / 1024)
        } else {
            downloadedDataSizeFormatted = String(format: "%.0f KB", kb)
        }
    }
}
