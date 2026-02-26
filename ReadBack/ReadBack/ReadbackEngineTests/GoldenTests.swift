// ReadbackEngineTests/GoldenTests.swift
// Golden tests: load fixtures from ReadbackEngineTests/fixtures/*.json and assert normalized text, intents, confidence.

import XCTest
@testable import ReadBack

struct Fixture: Decodable {
    let transcript: String
    let gps: GPS
    let expectedNormalizedContains: [String]?
    let expectedIntents: [ExpectedIntent]?
    let minOverallConfidence: Double?
    struct GPS: Decodable {
        let lat: Double
        let lon: Double
    }
    struct ExpectedIntent: Decodable {
        let kind: String
        let frequencyMHz: Double?
        let verb: String?
        let altitudeFt: Int?
        let clearanceLimit: String?
        let squawk: String?
        let operation: String?
        let runway: String?
    }
}

final class GoldenTests: XCTestCase {

    var store: NASRStore!

    override func setUp() {
        super.setUp()
        store = NASRStore()
        if let dir = Bundle(for: GoldenTests.self).resourceURL?.appendingPathComponent("fixtures", isDirectory: true), FileManager.default.fileExists(atPath: dir.path) {
            let aviationDir = dir.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("aviation_data_v2")
            if FileManager.default.fileExists(atPath: aviationDir.path) { store.load(from: aviationDir) }
        }
        if store.airports.isEmpty { try? loadStoreFromBundle() }
    }

    private func loadStoreFromBundle() throws {
        let bundle = Bundle(for: GoldenTests.self)
        if let resourcePath = bundle.resourcePath {
            let aviationDir = URL(fileURLWithPath: resourcePath).appendingPathComponent("aviation_data_v2")
            if FileManager.default.fileExists(atPath: aviationDir.path) { store.load(from: aviationDir) }
        }
    }

    func testGoldenFixtures() throws {
        let fixturesDir = fixtureDirectory()
        let files = try FileManager.default.contentsOfDirectory(at: fixturesDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles).filter { $0.pathExtension == "json" }
        XCTAssertGreaterThanOrEqual(files.count, 15, "Need at least 15 fixture files")
        let engine = ReadbackEngine(store: store)
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let data = try Data(contentsOf: url)
            let fixture = try JSONDecoder().decode(Fixture.self, from: data)
            let gps = GPSContext(lat: fixture.gps.lat, lon: fixture.gps.lon)
            let result = engine.process(transcript: fixture.transcript, gps: gps)
            if let contains = fixture.expectedNormalizedContains {
                for sub in contains {
                    XCTAssertTrue(result.normalizedText.contains(sub) || result.normalizedText.uppercased().contains(sub.uppercased()), "Fixture \(url.lastPathComponent): expected normalized text to contain '\(sub)', got: \(result.normalizedText)")
                }
            }
            if let minConf = fixture.minOverallConfidence {
                XCTAssertGreaterThanOrEqual(result.overallConfidence, minConf, "Fixture \(url.lastPathComponent): confidence \(result.overallConfidence) < \(minConf)")
            }
            if let expectedIntents = fixture.expectedIntents {
                for exp in expectedIntents {
                    let match = result.intents.contains { i in
                        switch (exp.kind, i) {
                        case ("frequencyChange", .frequencyChange(let f)): return exp.frequencyMHz == nil || abs((exp.frequencyMHz ?? 0) - f.frequencyMHz) < 0.01
                        case ("altitude", .altitude(let a)): return (exp.verb == nil || exp.verb == a.verb.rawValue) && (exp.altitudeFt == nil || exp.altitudeFt == a.altitudeFt)
                        case ("ifrClearance", .ifrClearance(let ifr)): return (exp.clearanceLimit == nil || ifr.clearanceLimit == exp.clearanceLimit) && (exp.squawk == nil || ifr.squawk == exp.squawk)
                        case ("runwayOperation", .runwayOperation(let r)): return (exp.operation == nil || exp.operation == r.operation.rawValue) && (exp.runway == nil || r.runway == exp.runway)
                        default: return false
                        }
                    }
                    XCTAssertTrue(match, "Fixture \(url.lastPathComponent): expected intent \(exp.kind) not found in \(result.intents)")
                }
            }
        }
    }

    private func fixtureDirectory() -> URL {
        if let resourceURL = Bundle(for: GoldenTests.self).resourceURL {
            let fixtures = resourceURL.appendingPathComponent("fixtures", isDirectory: true)
            if FileManager.default.fileExists(atPath: fixtures.path) { return fixtures }
        }
        let testFile = URL(fileURLWithPath: #file)
        return testFile.deletingLastPathComponent().appendingPathComponent("fixtures", isDirectory: true)
    }

    func testNormalizerRunway() {
        let r = Normalizer.normalize("runway two seven left")
        XCTAssertTrue(r.foldedTokens.contains("27L") || r.normalizedText.contains("27L") || r.normalizedText.contains("27"), "Expected runway 27L in \(r.normalizedText)")
    }

    func testNormalizerFrequency() {
        let r = Normalizer.normalize("one two eight point seven")
        XCTAssertTrue(r.foldedTokens.contains("128.7") || r.normalizedText.contains("128.7"), "Expected 128.7 in \(r.normalizedText)")
    }

    func testNormalizerPhonetic() {
        let r = Normalizer.normalize("golf echo papa")
        XCTAssertTrue(r.foldedTokens.contains("GEP") || r.normalizedText.contains("GEP"), "Expected GEP in \(r.normalizedText)")
    }

    // MARK: - Runway operation

    func testRunwayNinerNinerBecomes99() {
        let norm = Normalizer.normalize("CLEARED TO LAND RUNWAY NINER NINER")
        let intent = Parsers.extractRunwayOperation(from: norm.normalizedText, foldedTokens: norm.foldedTokens)
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.operation, .clearedLand)
        XCTAssertEqual(intent?.runway, "99", "runway niner niner must be 99 (two-digit), not 09")
    }

    func testRunwayZeroNinerBecomes09() {
        let norm = Normalizer.normalize("CLEARED TO LAND RUNWAY ZERO NINER")
        let intent = Parsers.extractRunwayOperation(from: norm.normalizedText, foldedTokens: norm.foldedTokens)
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.operation, .clearedLand)
        XCTAssertEqual(intent?.runway, "09")
    }

    func testRunwayNinerNinerEngineRunway99NearKMIC() {
        let engine = ReadbackEngine(store: store)
        let gps = GPSContext(lat: 44.88, lon: -93.22)
        let result = engine.process(transcript: "CLEARED TO LAND RUNWAY NINER NINER", gps: gps)
        let rwyIntent = result.intents.compactMap { i -> RunwayOperationIntent? in if case .runwayOperation(let r) = i { return r }; return nil }.first
        XCTAssertNotNil(rwyIntent)
        XCTAssertEqual(rwyIntent?.runway, "99")
    }

    func testRunwayRoomOnlyNinerNinerBecomes99() {
        let norm = Normalizer.normalize("CLEARED TO LAND RUNWAY ROOM ONLY NINER NINER")
        let intent = Parsers.extractRunwayOperation(from: norm.normalizedText, foldedTokens: norm.foldedTokens)
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.operation, .clearedLand)
        XCTAssertEqual(intent?.runway, "99", "filler 'room only' between runway and digits should be skipped")
    }

    func testRunwayUhZeroNinerBecomes09() {
        let norm = Normalizer.normalize("CLEARED TO LAND RUNWAY UH ZERO NINER")
        let intent = Parsers.extractRunwayOperation(from: norm.normalizedText, foldedTokens: norm.foldedTokens)
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.operation, .clearedLand)
        XCTAssertEqual(intent?.runway, "09", "filler 'uh' between runway and digits should be skipped")
    }

    func testHoldRunway32BecomesHoldShort32() {
        let norm = Normalizer.normalize("641CC HOLD RUNWAY 32")
        let intent = Parsers.extractRunwayOperation(from: norm.normalizedText, foldedTokens: norm.foldedTokens)
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.operation, .holdShort)
        XCTAssertEqual(intent?.runway, "32")
    }

    func testHoldRunwayTwoSevenLeftBecomesHoldShort27L() {
        let norm = Normalizer.normalize("HOLD RUNWAY TWO SEVEN LEFT")
        let intent = Parsers.extractRunwayOperation(from: norm.normalizedText, foldedTokens: norm.foldedTokens)
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.operation, .holdShort)
        XCTAssertEqual(intent?.runway, "27L")
    }

    func testHoldAtFixDoesNotCreateRunwayIntent() {
        let norm = Normalizer.normalize("N641CC HOLD AT GEP AS PUBLISHED")
        let intent = Parsers.extractRunwayOperation(from: norm.normalizedText, foldedTokens: norm.foldedTokens)
        XCTAssertNil(intent, "IFR hold at fix must not produce runwayOperation intent")
    }
}
