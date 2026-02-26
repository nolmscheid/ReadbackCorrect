import Foundation

/// Temporary IFR evaluation harness for grammar-refactor-v1 branch. Internal testing only.
/// Does not modify UI. Does not auto-run. Call runIFRTests() manually (e.g. from debugger or temporary button).
enum IFRParserTestHarness {

    private static let testTranscripts = [
        "cleared to rochester airport via gopher two departure gep direct far maintain four thousand expect nine thousand ten minutes after departure departure frequency one two four point seven squawk six zero four two",
        "cleared to rochester airport as filed maintain three thousand departure frequency one two five point two squawk four three two one",
        "cleared to st cloud via direct stc maintain five thousand expect seven thousand departure frequency one two six point three",
        "cleared to minneapolis airport maintain flight level two three zero departure frequency one two four point seven squawk one two zero zero",
        "cleared to duluth airport via brainerd v o r direct maintain four thousand",
        "cleared as filed maintain three thousand squawk four six two three",
        "cleared to rochester airport via gopher two departure maintain four thousand expect nine thousand ten minutes after departure squawk six zero four two",
        "cleared to rochester airport maintain four thousand expect three thousand departure frequency one two four point seven squawk six zero four two",
    ]

    /// Run IFR parse + validate on test transcripts and print results. Call manually; does not auto-run.
    static func runIFRTests() {
        let waypointIds = AviationDataManager.shared.waypointIds
        let parser = IFRParser()

        for raw in testTranscripts {
            print("RAW: \(raw)")

            let normalized = AviationNormalizer.normalize(raw, waypointIds: waypointIds).uppercased()
            let context = ParsingContext(normalizedText: normalized)
            print("FOLDED TEXT:", context.foldedText)
            var clearance = parser.parse(context: context)
            IFRValidator.validate(clearance: &clearance, context: context, dataProvider: nil)

            printSlot("CALLSIGN", clearance.callsign.value)
            printSlot("CLEARANCE LIMIT", clearance.clearanceLimit.value)

            if let route = clearance.route.value {
                print("ROUTE: rawText=\(route.rawText) fixes=\(route.fixes)")
            } else {
                print("ROUTE: (nil)")
            }

            if let alt = clearance.altitude.value {
                print("ALTITUDE: initialFeet=\(String(describing: alt.initialFeet)) expectFeet=\(String(describing: alt.expectFeet))")
            } else {
                print("ALTITUDE: (nil)")
            }

            printSlot("FREQUENCY", clearance.frequency.value)
            printSlot("SQUAWK", clearance.squawk.value)
            print("overallConfidence: \(clearance.overallConfidence)")
            print(String(repeating: "-", count: 60))
        }
    }

    private static func printSlot(_ name: String, _ value: String?) {
        if let v = value {
            print("\(name): \(v)")
        } else {
            print("\(name): (nil)")
        }
    }
}
