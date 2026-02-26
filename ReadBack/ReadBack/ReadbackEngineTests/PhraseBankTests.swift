// ReadbackEngineTests/PhraseBankTests.swift
// Regression harness: run each PhraseCase through normalization + intent extraction and assert expected intents.

import XCTest
@testable import ReadBack

final class PhraseBankTests: XCTestCase {

    var store: NASRStore!

    override func setUp() {
        super.setUp()
        store = NASRStore()
        if let dir = Bundle(for: PhraseBankTests.self).resourceURL?.appendingPathComponent("fixtures", isDirectory: true),
           FileManager.default.fileExists(atPath: dir.path) {
            let aviationDir = dir.deletingLastPathComponent().appendingPathComponent("aviation_data_v2")
            if FileManager.default.fileExists(atPath: aviationDir.path) { store.load(from: aviationDir) }
        }
        if store.airports.isEmpty { try? loadStoreFromBundle() }
    }

    private func loadStoreFromBundle() throws {
        let bundle = Bundle(for: PhraseBankTests.self)
        if let resourcePath = bundle.resourcePath {
            let aviationDir = URL(fileURLWithPath: resourcePath).appendingPathComponent("aviation_data_v2")
            if FileManager.default.fileExists(atPath: aviationDir.path) { store.load(from: aviationDir) }
        }
    }

    func testPhraseBankRegression() throws {
        let bundle = Bundle(for: PhraseBankTests.self)
        let cases = try PhraseBankLoader.loadFromBundle(bundle)
        XCTAssertFalse(cases.isEmpty, "PhraseBank should contain at least one case")

        let engine = ReadbackEngine(store: store)
        let defaultGPS = PhraseGPS(lat: 44.88, lon: -93.22)

        for phraseCase in cases {
            let gpsContext = phraseCase.gps.map { GPSContext(lat: $0.lat, lon: $0.lon) }
                ?? GPSContext(lat: defaultGPS.lat, lon: defaultGPS.lon)
            let result = engine.process(transcript: phraseCase.transcript, gps: gpsContext)

            if let contains = phraseCase.expectedNormalizedContains {
                for sub in contains {
                    let normalizedUpper = result.normalizedText.uppercased()
                    let subUpper = sub.uppercased()
                    XCTAssertTrue(
                        normalizedUpper.contains(subUpper),
                        "[\(phraseCase.id)] \(phraseCase.title): expected normalized to contain '\(sub)'. transcript: \(phraseCase.transcript). normalized: \(result.normalizedText). produced intents: \(describeIntents(result.intents, runwayValidated: result.runwayValidated))"
                    )
                }
            }

            if phraseCase.expectedIntents.isEmpty {
                let hasRunwayOp = result.intents.contains { if case .runwayOperation = $0 { return true }; return false }
                XCTAssertFalse(
                    hasRunwayOp,
                    "[\(phraseCase.id)] \(phraseCase.title): expected no runwayOp intent. transcript: \(phraseCase.transcript). normalized: \(result.normalizedText). produced intents: \(describeIntents(result.intents, runwayValidated: result.runwayValidated))"
                )
            } else {
                for expected in phraseCase.expectedIntents {
                    let match = producedIntentMatches(expected: expected, intents: result.intents, runwayValidated: result.runwayValidated)
                    XCTAssertTrue(
                        match.found,
                        "[\(phraseCase.id)] \(phraseCase.title): expected intent \(expected.kind) not matched. transcript: \(phraseCase.transcript). normalized: \(result.normalizedText). produced intents: \(describeIntents(result.intents, runwayValidated: result.runwayValidated)). expected: \(expected)"
                    )
                    if let valid = expected.validated, match.found, expected.kind == "runwayOp", result.runwayValidated != nil {
                        XCTAssertEqual(
                            result.runwayValidated, valid,
                            "[\(phraseCase.id)] \(phraseCase.title): runwayOp validated expected \(valid), got \(String(describing: result.runwayValidated))"
                        )
                    }
                    if match.found, expected.kind == "crossRunway", let validatedMap = expected.validatedMap {
                        let crossIntent = result.intents.compactMap { i -> CrossRunwayIntent? in if case .crossRunway(let c) = i { return c }; return nil }.first
                        XCTAssertNotNil(crossIntent, "[\(phraseCase.id)] crossRunway intent missing")
                        let anyProduced = crossIntent?.runwayValidated.values.contains(where: { $0 != nil }) ?? false
                        if anyProduced {
                            for (rwy, expVal) in validatedMap {
                                let produced = crossIntent?.runwayValidated[rwy] ?? nil
                                XCTAssertEqual(produced, expVal, "[\(phraseCase.id)] crossRunway runway=\(rwy) expected=\(String(describing: expVal)) got=\(String(describing: produced))")
                            }
                        }
                    }
                }
            }
        }
    }

    private func producedIntentMatches(expected: ExpectedIntent, intents: [ParsedIntent], runwayValidated: Bool?) -> (found: Bool, validatedOk: Bool) {
        let found = intents.contains { intent in
            switch (expected.kind, intent) {
            case ("runwayOp", .runwayOperation(let r)):
                let opMatch = expected.operation == nil || r.operation.rawValue == expected.operation
                let rwyMatch = expected.runway == nil || r.runway == expected.runway
                return opMatch && rwyMatch
            case ("taxiToRunway", .taxiToRunway(let t)):
                let rwyMatch = expected.runway == nil || t.runway == expected.runway
                let valMatch = expected.validated == nil || t.validated == expected.validated
                return rwyMatch && valMatch
            case ("crossRunway", .crossRunway(let c)):
                guard let expRunways = expected.runways else { return true }
                return Set(c.runways) == Set(expRunways)
            case ("continueTaxi", .continueTaxi(let c)):
                let taxiwayMatch = (expected.extra?["taxiway"]).map { c.taxiway == $0 } ?? (c.taxiway != nil)
                return taxiwayMatch
            case ("viaTaxiway", .viaTaxiway(let v)):
                return (expected.extra?["taxiway"]).map { v.taxiway == $0 } ?? true
            default:
                return false
            }
        }
        let validatedOk: Bool
        if expected.validated == nil {
            validatedOk = true
        } else if expected.kind == "runwayOp" {
            validatedOk = runwayValidated == expected.validated
        } else if expected.kind == "taxiToRunway" {
            let taxiIntent = intents.compactMap { i -> TaxiToRunwayIntent? in if case .taxiToRunway(let t) = i { return t }; return nil }.first { expected.runway == nil || $0.runway == expected.runway }
            validatedOk = taxiIntent?.validated == expected.validated
        } else {
            validatedOk = true
        }
        return (found, validatedOk)
    }

    private func describeIntents(_ intents: [ParsedIntent], runwayValidated: Bool?) -> String {
        var parts: [String] = []
        for i in intents {
            switch i {
            case .runwayOperation(let r): parts.append("runwayOp(\(r.operation.rawValue),\(r.runway ?? "nil"))")
            case .taxiToRunway(let t): parts.append("taxiToRunway(\(t.runway ?? "nil"), validated:\(String(describing: t.validated)))")
            case .crossRunway(let c): parts.append("crossRunway(\(c.runways), validated:\(c.runwayValidated))")
            case .continueTaxi(let c): parts.append("continueTaxi(\(c.taxiway ?? "nil"))")
            case .frequencyChange(let f): parts.append("frequencyChange(\(f.frequencyMHz))")
            case .altitude(let a): parts.append("altitude(\(a.verb.rawValue),\(a.altitudeFt))")
            case .ifrClearance: parts.append("ifrClearance")
            case .viaTaxiway(let v): parts.append("viaTaxiway(\(v.taxiway))")
            }
        }
        return "[\(parts.joined(separator: ", "))] runwayValidated=\(String(describing: runwayValidated))"
    }
}
