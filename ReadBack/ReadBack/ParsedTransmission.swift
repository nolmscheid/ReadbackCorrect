import Foundation

struct ParsedTransmission: Equatable {
    let originalText: String
    let cleanedText: String
    let callsignMatched: Bool
    let intents: [ATCIntent]   // must be in spoken order
}
