// ReadbackEngineProvider.swift
// Shared NASRStore + ReadbackEngine for the app. Loads aviation_data_v2 from bundle or Application Support when first used.

import Foundation

enum ReadbackEngineProvider {
    private static let lock = NSLock()
    private static var _store: NASRStore?
    private static var _engine: ReadbackEngine?

    /// Prefer Application Support (downloaded) aviation_data_v2; fall back to bundle.
    private static func aviationDataV2Directory() -> URL {
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appSupportV2 = support.appendingPathComponent("ReadBack", isDirectory: true).appendingPathComponent("aviation_data_v2", isDirectory: true)
            if FileManager.default.fileExists(atPath: appSupportV2.path),
               FileManager.default.fileExists(atPath: appSupportV2.appendingPathComponent("airports.json").path) {
                return appSupportV2
            }
        }
        return Bundle.main.resourceURL?.appendingPathComponent("aviation_data_v2", isDirectory: true)
            ?? URL(fileURLWithPath: "aviation_data_v2", isDirectory: true)
    }

    static var sharedStore: NASRStore {
        lock.lock()
        defer { lock.unlock() }
        if let s = _store { return s }
        let s = NASRStore()
        let dir = aviationDataV2Directory()
        ReadbackDebugLog.log("NASR load starting. bundleURL=\(dir.path)")
        s.load(from: dir)
        ReadbackDebugLog.log("NASR load success. \(s.debugCounts())")
        _store = s
        DispatchQueue.main.async {
            ReadbackDebugState.shared.nasrLoaded = s.isLoaded
        }
        return s
    }

    /// Call after downloading new aviation_data_v2 so the next access reloads from disk.
    static func resetStore() {
        lock.lock()
        _store = nil
        _engine = nil
        lock.unlock()
    }

    static var sharedEngine: ReadbackEngine {
        lock.lock()
        if let e = _engine {
            lock.unlock()
            return e
        }
        lock.unlock()
        let store = sharedStore
        lock.lock()
        defer { lock.unlock() }
        if let e = _engine { return e }
        let e = ReadbackEngine(store: store)
        _engine = e
        return e
    }

    #if DEBUG
    /// Call immediately after process(transcript:gps:) returns. Logs raw transcript, result summary, and NASR counts. Grep for "=== READBACK DEBUG ===".
    static func logReadbackDebug(rawTranscript: String, result: ReadbackResult, store: NASRStore) {
        print("=== READBACK DEBUG ===")
        print("RAW transcript: \(rawTranscript)")
        print("normalizedText: \(result.normalizedText)")
        print("overallConfidence: \(result.overallConfidence)")
        print("intents: \(formatIntents(result.intents))")
        let snaps = result.snaps
        print("snapEvents count: \(snaps.count)")
        for (i, ev) in snaps.prefix(5).enumerated() {
            print("  [\(i)] type=\(ev.type.rawValue) confidence=\(ev.confidence) replacement=\(ev.replacement)")
        }
        print("NASRStore loaded: \(store.debugCounts())")
        print("=== END READBACK DEBUG ===")
    }

    private static func formatIntents(_ intents: [ParsedIntent]) -> String {
        intents.map { intent in
            switch intent {
            case .frequencyChange(let f):
                return "frequencyChange(facilityType: \(f.facilityType ?? "nil"), frequencyMHz: \(f.frequencyMHz))"
            case .altitude(let a):
                return "altitude(verb: \(a.verb.rawValue), altitudeFt: \(a.altitudeFt))"
            case .ifrClearance(let i):
                return "ifrClearance(clearanceLimit: \(i.clearanceLimit ?? "nil"), routeTokens: \(i.routeTokens), initialAltitude: \(i.initialAltitude.map { String($0) } ?? "nil"), squawk: \(i.squawk ?? "nil"), departureFreq: \(i.departureFreq.map { String($0) } ?? "nil"))"
            case .runwayOperation(let r):
                return "runwayOperation(\(r.operation.rawValue), runway: \(r.runway ?? "nil"))"
            case .taxiToRunway(let t):
                return "taxiToRunway(runway: \(t.runway ?? "nil"))"
            case .crossRunway(let c):
                return "crossRunway(runways: \(c.runways))"
            case .continueTaxi(let c):
                return "continueTaxi(taxiway: \(c.taxiway ?? "nil"))"
            case .viaTaxiway(let v):
                return "viaTaxiway(taxiway: \(v.taxiway))"
            }
        }.joined(separator: " | ")
    }
    #endif
}
