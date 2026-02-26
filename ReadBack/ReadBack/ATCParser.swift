import Foundation

enum ATCParser {

    static func parse(
        text: String,
        desiredCallsign: String,
        callsignFilterEnabled: Bool
    ) -> ParsedTransmission {

        let upper = text.uppercased()

        let matched = callsignFilterEnabled
            ? CallsignFormatter.matchesTransmission(upper, desiredUserInput: desiredCallsign)
            : true

        let cleaned = CallsignFormatter.removeCallsignFromDisplayText(
            upper,
            desiredUserInput: desiredCallsign,
            onlyIfMatched: matched
        )

        // Parse intents from cleaned text (so the callsign doesn't interfere)
        let intents = IntentParser.parseIntents(in: cleaned)

        return ParsedTransmission(
            originalText: upper,
            cleanedText: cleaned,
            callsignMatched: matched,
            intents: intents
        )
    }
}
